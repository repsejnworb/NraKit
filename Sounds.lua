local _, ns = ...

-- Sound choices for NraKit's alerts.
--
-- A sound is stored as a string: "kit:NAME" (a Blizzard SOUNDKIT sound), "lsm:Name" (a
-- LibSharedMedia sound another addon registered), "none", or "default" (per-goal: use
-- the setting). The curated list below gets friendly names; "More sounds..." opens a
-- searchable list of every SOUNDKIT and LibSharedMedia sound.
--
-- Options use it with `type = "sound"`; UI.CreateSoundSelect is the dropdown + Play
-- button used in NraKit's windows.

local UI = ns.UI
local sounds = {}
ns.sounds = sounds

-- Every name here exists in Forever's SoundKitConstants.
sounds.CURATED = {
	{ group = "Chimes", entries = {
		{ "Quest complete", "IG_QUEST_LIST_COMPLETE" },
		{ "Rolling forward", "UI_QUEST_ROLLING_FORWARD_01" },
		{ "Ready check", "READY_CHECK" },
		{ "Map ping", "MAP_PING" },
		{ "Whisper", "TELL_MESSAGE" },
		{ "Friend online", "UI_BNET_TOAST" },
		{ "Group invite", "IG_PLAYER_INVITE" },
		{ "World quest complete", "UI_WORLDQUEST_COMPLETE" },
		{ "Talent ready", "UI_ORDERHALL_TALENT_READY_TOAST" },
	} },
	{ group = "Rewards", entries = {
		{ "Epic loot", "UI_EPICLOOT_TOAST" },
		{ "Legendary loot", "UI_LEGENDARY_LOOT_TOAST" },
		{ "Loot won", "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON" },
		{ "Coins", "LOOT_WINDOW_COIN_SOUND" },
		{ "Gift unwrap", "UI_STORE_UNWRAP" },
		{ "Dig site complete", "UI_DIG_SITE_COMPLETION_TOAST" },
		{ "Mission complete", "UI_GARRISON_TOAST_MISSION_COMPLETE" },
		{ "Building complete", "UI_GARRISON_TOAST_BUILDING_COMPLETE" },
		{ "Cheers", "UI_MISSION_SUCCESS_CHEERS" },
		{ "New record", "UI_CHALLENGES_NEW_RECORD" },
		{ "Stage complete", "UI_SCENARIO_STAGE_END" },
	} },
	{ group = "Alerts", entries = {
		{ "Raid warning", "RAID_WARNING" },
		{ "Boss emote", "RAID_BOSS_EMOTE_WARNING" },
		{ "Boss whisper", "UI_RAID_BOSS_WHISPER_WARNING" },
		{ "Alarm clock 1", "ALARM_CLOCK_WARNING_1" },
		{ "Alarm clock 2", "ALARM_CLOCK_WARNING_2" },
		{ "Alarm clock 3", "ALARM_CLOCK_WARNING_3" },
		{ "Queue ready", "PVP_THROUGH_QUEUE" },
		{ "Invasion alert", "UI_GARRISON_TOAST_INVASION_ALERT" },
		{ "Countdown done", "UI_BATTLEGROUND_COUNTDOWN_FINISHED" },
		{ "War mode", "UI_WARMODE_ACTIVATE" },
		{ "Aggro", "IG_CREATURE_AGGRO_SELECT" },
	} },
	{ group = "Soft", entries = {
		{ "Page turn", "IG_ABILITY_PAGE_TURN" },
		{ "Coin click", "IG_BACKPACK_COIN_OK" },
		{ "Gems", "PUT_DOWN_GEMS" },
	} },
}

local curatedLabels = {}
for _, group in ipairs(sounds.CURATED) do
	for _, entry in ipairs(group.entries) do
		curatedLabels["kit:" .. entry[2]] = entry[1]
	end
end

local function GetLSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- "UI_EPICLOOT_TOAST" -> "Epicloot toast"
local function PrettyKitName(name)
	local text = name:gsub("^UI_", ""):gsub("^IG_", ""):gsub("_", " "):lower()
	return (text:gsub("^%l", string.upper))
end

function sounds.Label(value)
	if not value or value == "none" then
		return "None"
	elseif value == "default" then
		return "Default"
	end
	if curatedLabels[value] then
		return curatedLabels[value]
	end
	local source, name = value:match("^(%a+):(.+)$")
	if source == "kit" then
		return PrettyKitName(name)
	elseif source == "lsm" then
		return name
	end
	return value
end

-- Whether a value can be played on this client (a library may be gone, a name renamed).
function sounds.IsValid(value)
	if value == "none" then
		return true
	end
	local source, name = type(value) == "string" and value:match("^(%a+):(.+)$")
	if source == "kit" then
		return SOUNDKIT[name] ~= nil
	elseif source == "lsm" then
		local lsm = GetLSM()
		return lsm ~= nil and lsm:IsValid("sound", name)
	end
	return false
end

function sounds.Play(value)
	if not value or value == "none" then
		return
	end
	local source, name = value:match("^(%a+):(.+)$")
	if source == "kit" and SOUNDKIT[name] then
		PlaySound(SOUNDKIT[name], "Master")
	elseif source == "lsm" then
		local lsm = GetLSM()
		local file = lsm and lsm:Fetch("sound", name, true)
		if file then
			PlaySoundFile(file, "Master")
		end
	end
end

-- Plays the sound chosen in a `type = "sound"` option, or its default if that's gone.
function sounds.PlayOption(key, default)
	local value = ns:GetValue(key)
	if not sounds.IsValid(value) then
		value = default
	end
	sounds.Play(value)
end

-- Every sound: the curated ones first (friendly names), then shared media, then all of
-- SOUNDKIT. { value, label, source }
function sounds.All()
	local list, seen = {}, {}
	for _, group in ipairs(sounds.CURATED) do
		for _, entry in ipairs(group.entries) do
			local value = "kit:" .. entry[2]
			if SOUNDKIT[entry[2]] then
				table.insert(list, { value = value, label = entry[1], source = group.group })
				seen[value] = true
			end
		end
	end
	local lsm = GetLSM()
	if lsm then
		for _, name in ipairs(lsm:List("sound")) do
			if name ~= "None" then
				table.insert(list, { value = "lsm:" .. name, label = name, source = "Shared media" })
			end
		end
	end
	local kits = {}
	for name, id in pairs(SOUNDKIT) do
		if type(id) == "number" and not seen["kit:" .. name] then
			table.insert(kits, { value = "kit:" .. name, label = PrettyKitName(name), source = name })
		end
	end
	table.sort(kits, function(a, b)
		return a.label < b.label
	end)
	for _, entry in ipairs(kits) do
		table.insert(list, entry)
	end
	return list
end

------------------------------------------------------------------------------
-- "More sounds..." window
------------------------------------------------------------------------------

local ROWS, ROW_HEIGHT = 16, 24
local picker

local function CreatePicker()
	picker = UI.CreateWindow("NraKitSoundPicker", "Choose a sound", 460, 560, 0)
	picker:SetFrameStrata("FULLSCREEN_DIALOG")
	local body = picker.body

	picker.search = UI.CreateSearchBox(body, 260, function(text)
		picker.query = text
		picker.offset = 0
		picker:Refresh()
	end)
	picker.search:SetPoint("TOPLEFT", UI.PAD + 6, -UI.PAD)
	picker.count = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	picker.count:SetPoint("LEFT", picker.search, "RIGHT", 12, 0)

	local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", UI.PAD, -UI.PAD - 30)
	hint:SetText("Click Play to listen, click a name to use it. Scroll with the mouse wheel.")

	local list = CreateFrame("Frame", nil, body)
	list:SetPoint("TOPLEFT", UI.PAD, -UI.PAD - 48)
	list:SetPoint("RIGHT", -UI.PAD, 0)
	list:SetHeight(ROWS * ROW_HEIGHT + 2)
	local bg = list:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.PANEL))
	UI.AddBorder(list)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		picker.offset = picker.offset - delta * 3
		picker:Refresh()
	end)

	picker.rows = {}
	for index = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 1, -1 - (index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -1, 0)
		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.2)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		row.play = UI.CreateFlatButton(row, "Play", 18)
		row.play:SetPoint("LEFT", 4, 0)
		row.play:SetScript("OnClick", function(self)
			sounds.Play(self:GetParent().value)
		end)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.play, "RIGHT", 8, 0)
		row.name:SetJustifyH("LEFT")
		row.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.source:SetPoint("RIGHT", -8, 0)
		row:SetScript("OnClick", function(self)
			if picker.onPick then
				picker.onPick(self.value)
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			picker:Hide()
		end)
		picker.rows[index] = row
	end

	local scrollHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	scrollHint:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -8)
	picker.position = scrollHint

	function picker:Refresh()
		local shown = {}
		for _, entry in ipairs(self.entries) do
			if self.query == "" or entry.label:lower():find(self.query, 1, true)
				or entry.source:lower():find(self.query, 1, true) then
				table.insert(shown, entry)
			end
		end
		self.offset = math.max(0, math.min(self.offset, #shown - ROWS))
		for index, row in ipairs(self.rows) do
			local entry = shown[index + self.offset]
			row:SetShown(entry ~= nil)
			if entry then
				row.value = entry.value
				row.name:SetText(entry.label)
				row.source:SetText(entry.source)
				row.selected:SetShown(entry.value == self.current)
			end
		end
		self.count:SetText(#shown .. " sounds")
		self.position:SetText(#shown > ROWS and string.format("%d-%d of %d", self.offset + 1,
			math.min(self.offset + ROWS, #shown), #shown) or "")
	end
end

-- Opens the full list; onPick(value) is called with the chosen sound.
function sounds.OpenPicker(current, onPick)
	if not picker then
		CreatePicker()
	end
	picker.entries = sounds.All()
	picker.current, picker.onPick = current, onPick
	picker.query, picker.offset = "", 0
	picker.search:SetText("")
	picker:Show()
	picker:Raise()
	-- Start with the current sound in view.
	for index, entry in ipairs(picker.entries) do
		if entry.value == current then
			picker.offset = math.max(0, index - 4)
		end
	end
	picker:Refresh()
end

------------------------------------------------------------------------------
-- Dropdown + Play button
------------------------------------------------------------------------------

-- Plays a menu entry's sound once the mouse rests on it, so sweeping over the list
-- doesn't play every sound.
local hovered
local function PreviewOnHover(description, value)
	if description.SetOnEnter then
		description:SetOnEnter(function()
			hovered = value
			C_Timer.After(0.35, function()
				if hovered == value then
					sounds.Play(value)
				end
			end)
		end)
	end
	if description.SetOnLeave then
		description:SetOnLeave(function()
			if hovered == value then
				hovered = nil
			end
		end)
	end
end

-- options: { get = fn() -> value, set = fn(value), width = number,
--            defaultLabel = "Default (Epic loot)" or a function returning it, resolveDefault = fn() -> value }.
-- With defaultLabel, "default" is a choice (per-goal sounds); resolveDefault is what it plays.
function UI.CreateSoundSelect(parent, options)
	local select = CreateFrame("Frame", nil, parent)
	select:SetSize((options.width or 200) + 48, 22)

	local button = UI.CreateFlatButton(select, "", 22)
	button:SetPoint("LEFT")
	button:SetWidth(options.width or 200)
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 8, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -4, -3)
	select.button = button

	local play = UI.CreateFlatButton(select, "Play", 22)
	play:SetPoint("LEFT", button, "RIGHT", 4, 0)
	play:SetScript("OnClick", function()
		local value = options.get()
		if value == "default" and options.resolveDefault then
			value = options.resolveDefault()
		end
		sounds.Play(value)
	end)
	select.play = play

	local function Set(value)
		options.set(value)
		select:Refresh()
	end

	button:SetScript("OnClick", function(self)
		if not (MenuUtil and MenuUtil.CreateContextMenu) then
			return
		end
		local current = options.get()
		MenuUtil.CreateContextMenu(self, function(_, root)
			if root.SetScrollMode then
				root:SetScrollMode(420)
			end
			local function IsSelected(value)
				return value == current
			end
			if options.defaultLabel then
				local radio = root:CreateRadio(select:DefaultLabel(), IsSelected, Set, "default")
				if options.resolveDefault then
					PreviewOnHover(radio, options.resolveDefault())
				end
			end
			root:CreateRadio("None", IsSelected, Set, "none")
			if current and current ~= "none" and current ~= "default" and not curatedLabels[current] then
				local radio = root:CreateRadio(sounds.Label(current), IsSelected, Set, current)
				PreviewOnHover(radio, current)
			end
			for _, group in ipairs(sounds.CURATED) do
				root:CreateTitle(group.group)
				for _, entry in ipairs(group.entries) do
					local value = "kit:" .. entry[2]
					if SOUNDKIT[entry[2]] then
						local radio = root:CreateRadio(entry[1], IsSelected, Set, value)
						PreviewOnHover(radio, value)
					end
				end
			end
			root:CreateDivider()
			root:CreateButton("More sounds...", function()
				sounds.OpenPicker(current, Set)
			end)
		end)
	end)

	function select:DefaultLabel()
		local label = options.defaultLabel
		return type(label) == "function" and label() or label
	end

	function select:Refresh()
		local value = options.get()
		local label = value == "default" and self:DefaultLabel() or sounds.Label(value)
		button.text:SetText(label)
	end

	function select:SetEnabled(enabled)
		button:SetEnabled(enabled)
		play:SetEnabled(enabled)
		button.text:SetTextColor(unpack(enabled and UI.TEXT or UI.TEXT_DIM))
		play.text:SetTextColor(unpack(enabled and UI.TEXT or UI.TEXT_DIM))
	end

	select:Refresh()
	return select
end
