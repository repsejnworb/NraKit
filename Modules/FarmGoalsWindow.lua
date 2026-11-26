local _, ns = ...

-- Goals window (/nra goal): active goals, a form for new goals and the history of
-- finished ones. Same look as the other NraKit windows (UI.lua).
--
-- New goal form: pick a type (Item, Level, XP, Gold). An item can be dropped on the
-- slot, shift-clicked while the name box has focus, or typed. Item and gold goals can
-- start from what you already have: tick bags, bank, mail and other characters (the
-- last two need Inventory Tracker's data) and the starting count updates live.
-- "Edit" fills the same form with an existing goal (type fixed) to fix its target,
-- item, starting count or sounds without recreating it.
--
-- The icon at the top right of the form opens an icon picker beside the window, like
-- the macro window's: Automatic, an item or spell dropped on it, or any macro icon. The
-- icon list is our own (GetMacroIcons into our table), not Blizzard's shared
-- IconDataProvider, whose cache we'd otherwise be the ones to fill.

local UI = ns.UI
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local SIDEBAR_WIDTH = 170
local PAD = UI.PAD

local frame, scroll, form
local navButtons = {}
local page = "active" -- "active", "new", "history" or "edit"
local editID
local pool = UI.CreatePool()
local cards = {} -- goal id -> card widgets on the active page
local cardSignature

local GOAL_TYPES = {
	{ key = "item", label = "Item" },
	{ key = "level", label = "Level" },
	{ key = "xp", label = "XP" },
	{ key = "gold", label = "Gold" },
	{ key = "rep", label = "Reputation" },
	{ key = "skill", label = "Skill" },
	{ key = "currency", label = "Currency" },
}

local function G()
	return ns.goals
end

-- One line per type, under the type chips: what the goal counts.
local TYPE_HELP = {
	item = "Counts the items you loot from now on. Banking, mailing, trading or selling them never changes the count.",
	level = "Fills as you earn XP, until you reach the level.",
	xp = "Counts the XP you earn from now on.",
	gold = "Counts the money you gain from now on (loot, sales, quests). Spending doesn't count against it.",
	rep = "Follows your reputation with a faction: reach a standing, or gain an amount from now on.",
	skill = "Follows a skill (weapon skills, professions, riding...): reach a rank, or gain points from now on.",
	currency = "Follows a currency: reach an amount, or gain an amount from now on.",
}

local PICK_HEADINGS = { item = "Which item?", rep = "Which faction?", skill = "Which skill?", currency = "Which currency?" }
local HOW_MUCH = { item = "How many?", level = "Which level?", xp = "How much XP?", gold = "How much money?" }

------------------------------------------------------------------------------
-- Active goals
------------------------------------------------------------------------------

local Render

local function CardButton(card, label, onClick)
	local button = pool:Acquire("cardButton", function()
		local b = UI.CreateFlatButton(scroll.content, "", 20)
		b:SetFrameLevel(scroll.content:GetFrameLevel() + 2)
		return b
	end)
	button.text:SetText(label)
	button:SetWidth(button.text:GetStringWidth() + 20)
	button:SetScript("OnClick", onClick)
	return button
end

local function UpdateCard(card, goal)
	local name, icon = G().Describe(goal)
	local fraction, value = G().GetProgress(goal)
	card.icon:SetTexture(icon)
	card.icon:SetDesaturated(goal.paused and true or false)
	card.name:SetText(name)
	card.value:SetText(value)
	card.info:SetText(G().DescribeRate(goal))
	card.track:SetValue(math.min(math.max(fraction, 0), 1))
	if goal.completed then
		card.track:SetStatusBarColor(0.3, 0.85, 0.3)
		card.name:SetTextColor(0.3, 0.85, 0.3)
	elseif goal.paused then
		card.track:SetStatusBarColor(0.5, 0.5, 0.5)
		card.name:SetTextColor(unpack(UI.GREY))
	else
		card.track:SetStatusBarColor(unpack(UI.ACCENT))
		card.name:SetTextColor(unpack(UI.GOLD))
	end
end

local function AcquireCard()
	return pool:Acquire("card", function()
		local card = CreateFrame("Frame", nil, scroll.content)
		card:SetHeight(76)
		card.bg = card:CreateTexture(nil, "BACKGROUND")
		card.bg:SetAllPoints()
		card.bg:SetColorTexture(unpack(UI.PANEL))
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(36, 36)
		card.icon:SetPoint("TOPLEFT", 10, -10)
		card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		card.value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.value:SetPoint("TOPRIGHT", -12, -12)
		card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
		card.name:SetPoint("RIGHT", card.value, "LEFT", -8, 0)
		card.name:SetJustifyH("LEFT")
		card.name:SetWordWrap(false)
		card.track = CreateFrame("StatusBar", nil, card)
		card.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		card.track:SetMinMaxValues(0, 1)
		card.track:SetHeight(5)
		card.track:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -22)
		card.track:SetPoint("RIGHT", -12, 0)
		card.track.bg = card.track:CreateTexture(nil, "BACKGROUND")
		card.track.bg:SetAllPoints()
		card.track.bg:SetColorTexture(1, 1, 1, 0.12)
		UI.AddMilestoneTicks(card.track)
		card.info = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		card.info:SetPoint("BOTTOMLEFT", 56, 12)
		card.info:SetJustifyH("LEFT")
		return card
	end)
end

-- Identifies the list as shown (goals, finished, shelved), to know when cards must be rebuilt.
local function Signature(goals)
	local ids = {}
	for _, goal in ipairs(goals) do
		table.insert(ids, goal.id .. (goal.completed and "c" or "") .. (goal.shelved and "s" or "") .. (goal.paused and "p" or ""))
	end
	return table.concat(ids, ",")
end

local function AddCard(content, goal, y, width)
	local card = AcquireCard()
	card:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
	card:SetWidth(width)
	UpdateCard(card, goal)
	cards[goal.id] = card

	-- Buttons, right to left.
	local anchor
	local function Add(label, onClick)
		local button = CardButton(card, label, onClick)
		if anchor then
			button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
		else
			button:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
		end
		anchor = button
	end
	local id = goal.id
	if goal.completed then
		Add("Clear", function()
			G().RemoveGoal(id)
		end)
		if G().CanGoAgain(goal) then
			Add("Go again", function()
				G().GoAgain(goal)
			end)
		else
			Add("New target", function()
				ns:OpenGoalsWindow("edit", id)
			end)
		end
	elseif goal.shelved then
		Add("Remove", function()
			G().RemoveGoal(id)
		end)
		Add("Edit", function()
			ns:OpenGoalsWindow("edit", id)
		end)
		Add("Unshelve", function()
			G().SetShelved(goal, false)
		end)
	else
		Add("Remove", function()
			G().RemoveGoal(id)
		end)
		Add("Reset", function()
			goal.gained, goal.active, goal.milestone = 0, 0, 0
			if goal.type == "level" then
				goal.startLevel = UnitLevel("player") + UnitXP("player") / math.max(UnitXPMax("player"), 1)
			end
			G().Update()
		end)
		Add("Edit", function()
			ns:OpenGoalsWindow("edit", id)
		end)
		Add("Shelve", function()
			G().SetShelved(goal, true)
		end)
		Add(goal.paused and "Resume" or "Pause", function()
			goal.paused = not goal.paused or nil
			G().Update()
		end)
	end
	return y - 76 - 8
end

local function AddGroupHeading(content, text, y)
	local heading = pool:Acquire("groupHeading", function()
		local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetJustifyH("LEFT")
		label:SetTextColor(unpack(UI.ACCENT))
		return label
	end)
	heading:SetText(text)
	heading:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y - 6)
	return y - 26
end

local function RenderActive(content, width)
	local goals = G().GetData().goals
	local y = -PAD
	wipe(cards)
	local shelved = {}
	for _, goal in ipairs(goals) do
		if goal.shelved then
			table.insert(shelved, goal)
		else
			y = AddCard(content, goal, y, width)
		end
	end
	if #shelved > 0 then
		y = AddGroupHeading(content, "SHELVED  |cff808080not in the tracker, paused|r", y - 6)
		for _, goal in ipairs(shelved) do
			y = AddCard(content, goal, y, width)
		end
	end
	cardSignature = Signature(goals)

	if #goals == 0 then
		local heading = pool:Acquire("emptyHeading", function()
			local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			text:SetJustifyH("LEFT")
			text:SetTextColor(1, 1, 1)
			return text
		end)
		heading:SetText("No goals yet")
		heading:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y - 8)
		local text = pool:Acquire("emptyText", function()
			local t = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			t:SetJustifyH("LEFT")
			t:SetJustifyV("TOP")
			t:SetSpacing(3)
			return t
		end)
		text:SetWidth(width - 4)
		text:SetTextColor(unpack(UI.TEXT))
		text:SetText("A goal tracks something you're farming: an item you loot, a level, XP, gold, "
			.. "reputation, a skill or a currency. It counts what you gain from the moment you make it.\n\n"
			.. "Your goals show in a small tracker you can drag anywhere, with your rate per hour and "
			.. "the time left. You get a chime at 25, 50 and 75%, and a fanfare when a goal is done.")
		text:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
		local button = pool:Acquire("emptyButton", function()
			local b = UI.CreateFlatButton(content, "+  Create a Goal", 28)
			b:SetWidth(160)
			b:SetSelected(true)
			b:SetScript("OnClick", function()
				ns:OpenGoalsWindow("new")
			end)
			return b
		end)
		button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
		local tip = pool:Acquire("emptyTip", function()
			local t = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			t:SetJustifyH("LEFT")
			return t
		end)
		tip:SetText("Shortcut: type /nra goal 4000 and shift-click an item to paste it.")
		tip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)
		y = y - 220
	end
	return -y + PAD
end

------------------------------------------------------------------------------
-- History
------------------------------------------------------------------------------

local function RenderHistory(content, width)
	local history = G().GetData().history
	local y = -PAD
	for index, entry in ipairs(history) do
		local row = pool:Acquire("historyRow", function()
			local r = CreateFrame("Frame", nil, content)
			r:SetHeight(32)
			r.bg = r:CreateTexture(nil, "BACKGROUND")
			r.bg:SetAllPoints()
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(22, 22)
			r.icon:SetPoint("LEFT", 8, 0)
			r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
			r.restore = UI.CreateFlatButton(r, "Restore", 20)
			r.restore:SetPoint("RIGHT", -6, 0)
			r.restore:SetScript("OnClick", function(self)
				G().RestoreGoal(self:GetParent().entry)
				Render()
			end)
			r.restore:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, "Restore", "Put this goal back in the tracker, as it was when you cleared it.")
			end)
			r.restore:SetScript("OnLeave", GameTooltip_Hide)
			r.when = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			return r
		end)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
		row:SetWidth(width)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		local _, icon = G().Describe(entry)
		row.icon:SetTexture(icon)
		local name = entry.name
		if entry.type == "item" then
			name = G().FormatNumber(entry.target) .. " " .. name
		end
		row.name:SetText(name)
		row.entry = entry
		-- Cleared goals can come back; "Go again" runs are just a record.
		row.restore:SetShown(entry.goal ~= nil)
		row.when:ClearAllPoints()
		row.when:SetPoint("RIGHT", entry.goal and row.restore or row, entry.goal and "LEFT" or "RIGHT", -10, 0)
		row.when:SetText(string.format("took %s  ·  %s", G().FormatDuration(entry.active or 0),
			date("%Y-%m-%d", entry.completed)))
		y = y - 32
	end
	if #history == 0 then
		local empty = pool:Acquire("text", function()
			return content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		end)
		empty:SetText("Finished goals show up here once you clear them from the tracker.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y - 4)
		y = y - 30
	else
		local clear = pool:Acquire("clearHistory", function()
			local b = UI.CreateFlatButton(content, "Clear History", 22)
			b:SetScript("OnClick", function()
				wipe(G().GetData().history)
				Render()
			end)
			return b
		end)
		clear:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y - 10)
		y = y - 40
	end
	return -y + PAD
end

------------------------------------------------------------------------------
-- New goal / edit form
------------------------------------------------------------------------------

local formType = "item"
local formItemID
local formKey, formKeyName -- picked faction, skill or currency
local formMode = "reach"
local formStanding -- rep "reach": target reaction (5 = Friendly ... 8 = Exalted)
local formToMax = false -- skill "reach": follow the skill's cap
local formSounds = { milestone = "default", complete = "default" }
local formIcon -- a chosen icon (file ID or path), or nil for automatic
local iconPicker
local pickerQuery = ""
local pickerOffset = 0
local pickerEntries = {}
local PICKER_ROWS = 6
local PICKER_TYPES = { rep = true, skill = true, currency = true }

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function MakeEditBox(parent, width, numeric)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(numeric and true or false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function MakeHeading(parent, text)
	local heading = MakeLabel(parent, text:upper(), "GameFontNormalSmall")
	heading:SetTextColor(unpack(UI.ACCENT))
	return heading
end

-- Things to pick for rep, skill and currency goals: { id, name, sub, icon }.
local function BuildPickerEntries(goalType)
	local entries = {}
	if goalType == "rep" then
		local watched = C_Reputation.GetWatchedFactionData()
		for index = 1, C_Reputation.GetNumFactions() do
			local data = C_Reputation.GetFactionDataByIndex(index)
			if data and data.factionID and data.factionID > 0 and (not data.isHeader or data.isHeaderWithRep) then
				local entry = { id = data.factionID, name = data.name, sub = G().StandingLabel(data.reaction), reaction = data.reaction }
				if watched and watched.factionID == data.factionID then
					entry.sub = entry.sub .. "  ·  watched"
					table.insert(entries, 1, entry)
				else
					table.insert(entries, entry)
				end
			end
		end
	elseif goalType == "skill" then
		local header
		for index = 1, C_SkillInfo.GetNumSkillLines() do
			local info = C_SkillInfo.GetSkillLineInfo(index)
			if info and info.isHeader then
				header = info.name
			elseif info and info.skillID then
				table.insert(entries, {
					id = info.skillID, name = info.name, rank = info.rank, maxRank = info.maxRank,
					sub = string.format("%s  ·  %d / %d", header or "", info.rank, info.maxRank),
				})
			end
		end
	elseif goalType == "currency" then
		for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local info = C_CurrencyInfo.GetCurrencyListInfo(index)
			local link = C_CurrencyInfo.GetCurrencyListLink(index)
			local id = link and tonumber(link:match("currency:(%d+)"))
			if info and not info.isHeader and id then
				table.insert(entries, { id = id, name = info.name, icon = info.iconFileID, sub = G().FormatNumber(info.quantity) })
			end
		end
	end
	return entries
end

local function FilteredEntries()
	if pickerQuery == "" then
		return pickerEntries
	end
	local list = {}
	for _, entry in ipairs(pickerEntries) do
		if entry.name:lower():find(pickerQuery, 1, true) then
			table.insert(list, entry)
		end
	end
	return list
end

local function PickedEntry()
	for _, entry in ipairs(pickerEntries) do
		if entry.id == formKey then
			return entry
		end
	end
end

-- Current form values: target amount and starting count.
local function ReadForm()
	-- Money takes "1g 50s" style amounts and is counted in copper; the rest are plain numbers.
	local text = form.amount:GetText()
	local amount = formType == "gold" and G().ParseMoney(text) or tonumber(text)
	local holdings = form.holdings
	local start, ticked = 0, false
	if holdings and (formType == "item" or formType == "gold") then
		for _, seed in ipairs(form.seeds) do
			if seed:IsShown() and seed:GetChecked() and seed:IsEnabled() then
				start = start + (seed.count or 0)
				ticked = true
			end
		end
	end
	return amount, start, ticked
end

local UpdateForm

local function UpdatePicker()
	local list = FilteredEntries()
	pickerOffset = math.max(0, math.min(pickerOffset, #list - PICKER_ROWS))
	for index, row in ipairs(form.pickerRows) do
		local entry = list[index + pickerOffset]
		row.entry = entry
		if entry then
			row.name:SetText(entry.name)
			row.sub:SetText(entry.sub or "")
			row.selected:SetShown(entry.id == formKey)
			row:Show()
		else
			row:Hide()
		end
	end
	form.pickerEmpty:SetShown(#list == 0)
	form.pickerEmpty:SetText(#pickerEntries == 0 and "Nothing to pick yet." or "No matches.")
end

local function UpdateTargetChips(goalType, entry)
	-- Rep "reach": a chip per standing above the current one.
	local showStandings = goalType == "rep" and formMode == "reach"
	local current = entry and entry.reaction or 4
	local anchor
	for _, chip in ipairs(form.standingChips) do
		local visible = showStandings and chip.reaction > current
		chip:SetShown(visible)
		if visible then
			chip:ClearAllPoints()
			if anchor then
				chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
			else
				chip:SetPoint("LEFT", form.amountLabel, "LEFT", 160, 0)
			end
			anchor = chip
			chip:SetSelected(chip.reaction == formStanding)
		end
	end
	if showStandings and not anchor then
		form.amountHint:SetText("Already at the top standing: use Gain instead.")
	end
	form.maxChip:SetShown(goalType == "skill" and formMode == "reach")
	form.maxChip:SetSelected(formToMax)
end

function UpdateForm()
	local editing = page == "edit"
	local goal = editing and G().FindGoal(editID)
	if editing and not goal then
		page = "active"
		Render()
		return
	end
	local goalType = formType
	local itemID = formItemID
	local picking = PICKER_TYPES[goalType]

	-- 1. Type (fixed when editing)
	for _, chip in ipairs(form.typeChips) do
		chip:SetSelected(chip.key == goalType)
		chip:SetShown(not editing)
	end
	form.title:SetText(editing and ("Edit goal: " .. (G().Describe(goal))) or "New goal")
	local entryForIcon = PICKER_TYPES[goalType] and PickedEntry()
	local autoIcon = G().AutoIcon({
		type = goalType, itemID = itemID, key = entryForIcon and entryForIcon.id,
		target = goalType == "gold" and G().ParseMoney(form.amount:GetText()) or tonumber(form.amount:GetText()),
	})
	form.iconButton.icon:SetTexture(formIcon or autoIcon)
	form.iconLabel:SetText(formIcon and "Custom icon" or "Automatic icon")
	form.iconButton.autoIcon = autoIcon
	if iconPicker and iconPicker:IsShown() then
		iconPicker:Refresh()
	end
	local typeLabel
	for _, info in ipairs(GOAL_TYPES) do
		if info.key == goalType then
			typeLabel = info.label
		end
	end
	form.typeHeading:SetText(editing and ("Type: " .. typeLabel):upper() or "1. WHAT DO YOU WANT TO TRACK?")
	form.typeHelp:SetText(TYPE_HELP[goalType] or "")

	-- Numbered steps: (1. type), 2. which one (item/rep/skill/currency), then the target.
	local first = editing and 1 or 2
	local hasPick = PICK_HEADINGS[goalType] ~= nil
	local step = hasPick and first + 1 or first
	form.pickHeading:SetShown(hasPick)
	form.pickHeading:SetText(hasPick and (first .. ". " .. PICK_HEADINGS[goalType]):upper() or "")

	-- Item picker
	local isItem = goalType == "item"
	form.slot:SetShown(isItem)
	form.itemName:SetShown(isItem)
	form.itemHint:SetShown(isItem)
	form.itemLabel:SetShown(isItem)
	if isItem then
		local name = itemID and C_Item.GetItemNameByID(itemID)
		local icon = itemID and select(5, C_Item.GetItemInfoInstant(itemID))
		form.slot.icon:SetTexture(icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		form.itemLabel:SetText(name or (itemID and ("item " .. itemID)) or "No item picked")
	end

	-- Rep / skill / currency picker and mode
	form.pickerSearch:SetShown(picking)
	form.pickerList:SetShown(picking)
	form.pickedLabel:SetShown(picking)
	for _, chip in ipairs(form.modeChips) do
		chip:SetShown(picking)
		chip:SetSelected(chip.key == formMode)
	end
	local entry = picking and PickedEntry()
	if picking then
		UpdatePicker()
		form.pickedLabel:SetText(entry and ("|cffffd100" .. entry.name .. "|r  " .. (entry.sub or "")) or "Pick one from the list")
	end

	-- Amount / target: below the picker, the item, or right under the type.
	local targetY = picking and -292 or (goalType == "item" and -196 or -108)
	form.amountHeading:ClearAllPoints()
	form.amountHeading:SetPoint("TOPLEFT", 2, targetY)
	form.amountHeading:SetText((step .. ". " .. (picking and "Target" or HOW_MUCH[goalType] or "")):upper())
	form.amountLabel:ClearAllPoints()
	form.amountLabel:SetPoint("TOPLEFT", 2, targetY - (picking and 54 or 22))
	local amountLabels = {
		item = "How many to have", level = "Target level", xp = "XP to gain", gold = "Money to have",
		rep = formMode == "gain" and "Reputation to gain" or "Standing to reach",
		skill = formMode == "gain" and "Skill points to gain" or "Skill to reach",
		currency = formMode == "gain" and "Amount to gain" or "Amount to have",
	}
	form.amountLabel:SetText(amountLabels[goalType])
	form.amountHint:SetText("")
	local standingTarget = goalType == "rep" and formMode == "reach"
	form.amount:SetShown(not standingTarget)
	form.amount:SetEnabled(not (goalType == "skill" and formMode == "reach" and formToMax))
	form.amount:SetNumeric(goalType ~= "gold") -- money takes "1g 50s"
	if goalType == "skill" and formMode == "reach" and formToMax and entry
		and form.amount:GetText() ~= tostring(entry.maxRank) then
		form.amount:SetText(tostring(entry.maxRank))
	end
	UpdateTargetChips(picking and goalType, entry)
	form.amountHint:SetShown(picking)

	-- Starting count (item and gold)
	local seeding = goalType == "item" or goalType == "gold"
	form.seedHeading:SetShown(seeding)
	local holdings = seeding and (goalType == "gold" or itemID) and G().GetHoldings(goalType == "item" and itemID or nil) or nil
	form.holdings = holdings
	local isGold = goalType == "gold"
	local format = isGold and G().FormatGold or G().FormatNumber
	local seedInfo = {
		{ label = isGold and "This character" or "Bags", count = holdings and holdings.bags, show = true },
		{ label = "Bank", count = holdings and holdings.bank, show = not isGold },
		{ label = "Mail", count = holdings and holdings.mail, show = not isGold, needsTracker = true },
		{ label = "Other characters", count = holdings and holdings.othersTotal, show = true, needsTracker = true },
	}
	local sameThing = editing and goal.itemID == itemID
	if editing and sameThing then
		form.seedHeading:SetText(((step + 1) .. ". Starting count (now " .. format(goal.start or 0) .. ")"):upper())
		form.seedHelp:SetText("Tick to recount from what you have now. Leave all unticked to keep it.")
	else
		form.seedHeading:SetText(((step + 1) .. ". Start from what I have (optional)"):upper())
		form.seedHelp:SetText("Ticked counts are added as already done; only new loot is counted after that.")
	end
	form.seedHelp:SetShown(seeding)
	local lastSeed = form.seedHelp
	for index, seed in ipairs(form.seeds) do
		local info = seedInfo[index]
		seed:SetShown(seeding and info.show)
		if seeding and info.show then
			seed:ClearAllPoints()
			seed:SetPoint("TOPLEFT", lastSeed, "BOTTOMLEFT", lastSeed == form.seedHelp and -2 or 0, -4)
			lastSeed = seed
		end
		seed.count = info.count or 0
		local available = holdings ~= nil and (not info.needsTracker or holdings.trackerOn)
		seed:SetEnabled(available)
		seed.Text:SetText(info.label)
		seed.Text:SetTextColor(unpack(available and UI.TEXT or UI.TEXT_DIM))
		seed.countText:SetText(available and format(seed.count) or "")
	end
	local others = {}
	for _, other in ipairs(holdings and holdings.others or {}) do
		local r, g, b = ns.inventory.ClassColor(other.class)
		table.insert(others, string.format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255, other.name, format(other.count)))
		if #others == 4 then
			break
		end
	end
	form.othersText:SetShown(seeding)
	form.othersText:ClearAllPoints()
	form.othersText:SetPoint("TOPLEFT", lastSeed, "BOTTOMLEFT", 26, -4)
	form.othersText:SetPoint("RIGHT", form, "RIGHT")
	form.startText:ClearAllPoints()
	form.startText:SetPoint("TOPLEFT", lastSeed, "BOTTOMLEFT", 2, -24)
	if holdings and not holdings.trackerOn then
		form.othersText:SetText("Turn on Inventory Tracker to include mail and other characters.")
	else
		form.othersText:SetText(table.concat(others, "  ·  "))
	end

	local amount, start, ticked = ReadForm()
	if editing and sameThing and not ticked then
		start = goal.start or 0
	end
	if seeding then
		local target = amount
		form.startText:SetText(string.format("Starting count  |cffffffff%s|r%s", format(start),
			target and ("     (" .. format(start) .. " / " .. format(target) .. ")") or ""))
	end
	form.startText:SetShown(seeding)

	-- Sounds, under whatever came last
	local last = seeding and form.startText or (picking and form.amountHint or form.amountLabel)
	form.soundHeading:ClearAllPoints()
	form.soundHeading:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -26)
	form.soundHeading:SetText(((seeding and step + 2 or step + 1) .. ". Sounds (optional)"):upper())
	for _, row in ipairs(form.soundRows) do
		row.select:Refresh()
	end

	-- Create / save button, with why it's disabled
	local hint = ""
	local valid
	if goalType == "item" then
		valid = amount and amount > 0 and itemID ~= nil
		hint = not itemID and "Pick an item first." or (not valid and "Enter how many." or "")
	elseif goalType == "level" then
		valid = amount and amount > UnitLevel("player")
		hint = not valid and ("Enter a level above " .. UnitLevel("player") .. ".") or ""
	elseif picking then
		if not entry then
			valid = false
			hint = "Pick one from the list."
		elseif standingTarget then
			valid = formStanding ~= nil and formStanding > (entry.reaction or 0)
			hint = not valid and "Pick the standing to reach." or ""
		elseif goalType == "skill" and formMode == "reach" then
			valid = formToMax and entry.rank < entry.maxRank or (amount and amount > entry.rank)
			hint = not valid and ("Enter a rank above " .. entry.rank .. ", or pick Max.") or ""
		else
			valid = amount and amount > 0
			hint = not valid and "Enter an amount." or ""
		end
	elseif goalType == "gold" then
		valid = amount and amount > 0
		hint = not valid and "Enter an amount: 100 (gold), 50s or 1g 50s." or ""
	else
		valid = amount and amount > 0
		hint = not valid and "Enter an amount." or ""
	end
	if editing and valid and (goal.itemID ~= itemID or goal.key ~= formKey or (goal.mode or "reach") ~= formMode) then
		hint = "Changing what's tracked starts its progress over."
	end
	form.create:SetText(editing and "Save Changes" or "Create Goal")
	form.create:SetEnabled(valid and true or false)
	form.cancel:SetShown(editing)
	form.createHint:ClearAllPoints()
	form.createHint:SetPoint("LEFT", editing and form.cancel or form.create, "RIGHT", 12, 0)
	form.createHint:SetText(hint)
end

local function SetItem(itemID)
	formItemID = itemID
	if form.itemName:HasFocus() then
		form.itemName:ClearFocus()
	end
	form.itemName:SetText("")
	UpdateForm()
end

local function SetType(goalType)
	formType = goalType
	formKey, formKeyName, formStanding, formToMax = nil, nil, nil, false
	formMode = "reach"
	pickerQuery, pickerOffset = "", 0
	form.pickerSearch:SetText("")
	pickerEntries = BuildPickerEntries(goalType)
	form.amount:SetText(goalType == "level" and tostring(UnitLevel("player") + 1) or "")
	UpdateForm()
end

-- Clears the form for a new goal (keeps the chosen type).
local function ResetForm()
	formItemID = nil
	formSounds.milestone, formSounds.complete = "default", "default"
	formIcon = nil
	for _, seed in ipairs(form.seeds) do
		seed:SetChecked(false)
	end
	SetType(formType)
end

-- Fills the form with an existing goal, for Edit.
local function LoadGoal(goal)
	formType = goal.type
	formItemID, formKey, formKeyName = goal.itemID, goal.key, goal.name
	formMode = goal.mode or "reach"
	formStanding = goal.type == "rep" and formMode == "reach" and goal.target or nil
	formToMax = goal.toMax or false
	formSounds.milestone = goal.sounds and goal.sounds.milestone or "default"
	formSounds.complete = goal.sounds and goal.sounds.complete or "default"
	formIcon = goal.icon
	pickerQuery, pickerOffset = "", 0
	form.pickerSearch:SetText("")
	pickerEntries = BuildPickerEntries(goal.type)
	for _, seed in ipairs(form.seeds) do
		seed:SetChecked(false)
	end
	local amount = goal.target
	if goal.type == "gold" then
		amount = G().FormatGold(goal.target)
	elseif formStanding then
		amount = nil
	end
	form.amount:SetText(amount and tostring(amount) or "")
end

local function SubmitForm()
	if not form.create:IsEnabled() then
		return
	end
	local amount, start, ticked = ReadForm()
	local spec = { type = formType, icon = formIcon, sounds = { milestone = formSounds.milestone, complete = formSounds.complete } }
	if formType == "item" then
		spec.itemID, spec.target, spec.start = formItemID, amount, start
	elseif formType == "gold" then
		spec.target, spec.start = amount, start
	elseif PICKER_TYPES[formType] then
		local entry = PickedEntry()
		spec.key, spec.name, spec.mode = entry.id, entry.name, formMode
		if formType == "rep" and formMode == "reach" then
			spec.target = formStanding
		elseif formType == "skill" and formMode == "reach" and formToMax then
			spec.toMax, spec.target = true, entry.maxRank
		else
			spec.target = amount
		end
	else
		spec.target = amount
	end
	if page == "edit" then
		G().EditGoal(editID, spec, ticked)
	else
		G().AddGoal(spec)
	end
	page = "active"
	ResetForm()
	Render()
end

local function CreatePicker()
	form.pickerSearch = UI.CreateSearchBox(form, 220, function(text)
		pickerQuery = text
		pickerOffset = 0
		UpdatePicker()
	end)
	form.pickerSearch:SetPoint("TOPLEFT", 6, -126)
	form.pickedLabel = MakeLabel(form, "", "GameFontHighlight")
	form.pickedLabel:SetPoint("LEFT", form.pickerSearch, "RIGHT", 16, 0)
	form.pickedLabel:SetPoint("RIGHT", form, "RIGHT")
	form.pickedLabel:SetWordWrap(false)

	local list = CreateFrame("Frame", nil, form)
	list:SetPoint("TOPLEFT", 0, -154)
	list:SetPoint("RIGHT", form, "RIGHT")
	list:SetHeight(PICKER_ROWS * 22)
	local bg = list:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.PANEL))
	UI.AddBorder(list)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		pickerOffset = pickerOffset - delta * 2
		UpdatePicker()
	end)
	form.pickerList = list

	form.pickerRows = {}
	for index = 1, PICKER_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(22)
		row:SetPoint("TOPLEFT", 1, -1 - (index - 1) * 22)
		row:SetPoint("RIGHT", -1, 0)
		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.2)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		row.name = MakeLabel(row, "", "GameFontHighlight")
		row.name:SetPoint("LEFT", 8, 0)
		row.sub = MakeLabel(row, "", "GameFontDisableSmall")
		row.sub:SetPoint("RIGHT", -8, 0)
		row:SetScript("OnClick", function(self)
			if self.entry then
				formKey, formKeyName = self.entry.id, self.entry.name
				formStanding = nil
				if formType == "skill" and formMode == "reach" then
					formToMax = true
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				UpdateForm()
			end
		end)
		table.insert(form.pickerRows, row)
	end
	form.pickerEmpty = MakeLabel(list, "", "GameFontDisable")
	form.pickerEmpty:SetPoint("TOPLEFT", 8, -6)

	-- Reach / Gain
	form.modeChips = {}
	local anchor
	for _, info in ipairs({ { "reach", "Reach a level" }, { "gain", "Gain an amount" } }) do
		local chip = UI.CreateFlatButton(form, info[2], 22)
		chip.key = info[1]
		chip:SetScript("OnClick", function(self)
			formMode = self.key
			formStanding = nil
			form.amount:SetText("")
			UpdateForm()
		end)
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", 0, -312)
		end
		anchor = chip
		table.insert(form.modeChips, chip)
	end

	-- Standings for rep "reach"
	form.standingChips = {}
	for reaction = 5, 8 do
		local chip = UI.CreateFlatButton(form, G().StandingLabel(reaction), 22)
		chip.reaction = reaction
		chip:SetScript("OnClick", function(self)
			formStanding = self.reaction
			UpdateForm()
		end)
		chip:Hide()
		table.insert(form.standingChips, chip)
	end

	-- "Max" for skill "reach"
	form.maxChip = UI.CreateFlatButton(form, "Max (follows the cap)", 22)
	form.maxChip:SetScript("OnClick", function()
		formToMax = not formToMax
		if not formToMax then
			form.amount:SetText("")
		end
		UpdateForm()
	end)
end

local FOOTER_HEIGHT = 46

------------------------------------------------------------------------------
-- Icon picker
------------------------------------------------------------------------------

local ICON_COLUMNS, ICON_ROWS, ICON_SIZE, ICON_GAP = 8, 8, 34, 4
local iconList

-- Every macro icon (spell icons, then item icons), without repeats.
local function IconList()
	if not iconList then
		local raw = {}
		for _, fill in ipairs({ GetLooseMacroIcons, GetLooseMacroItemIcons, GetMacroIcons, GetMacroItemIcons }) do
			if fill then
				fill(raw)
			end
		end
		iconList = {}
		local seen = {}
		for _, icon in ipairs(raw) do
			-- Older clients give names ("INV_Misc_Bag_08"), newer ones file IDs.
			if type(icon) == "string" and not icon:find("[\\/]") then
				icon = "Interface\\Icons\\" .. icon
			end
			if not seen[icon] then
				seen[icon] = true
				table.insert(iconList, icon)
			end
		end
	end
	return iconList
end

-- The icon of the item or spell on the cursor, if any.
local function CursorIcon()
	local kind, id, _, spellID = GetCursorInfo()
	if kind == "item" and id then
		return select(5, C_Item.GetItemInfoInstant(id))
	elseif kind == "spell" and (spellID or id) then
		return C_Spell.GetSpellTexture(spellID or id)
	end
	return nil
end

local function PickIcon(icon)
	formIcon = icon
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	UpdateForm()
end

local function CreateIconPicker()
	local width = PAD * 2 + ICON_COLUMNS * ICON_SIZE + (ICON_COLUMNS - 1) * ICON_GAP
	local gridTop = 138
	local picker = CreateFrame("Frame", "NraKitGoalIconPicker", frame)
	picker:SetSize(width, gridTop + ICON_ROWS * (ICON_SIZE + ICON_GAP) + PAD + 16)
	picker:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	picker:SetFrameLevel(frame:GetFrameLevel() + 20)
	picker:EnableMouse(true)
	local bg = picker:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(picker)
	picker:Hide()
	picker.offset = 0

	local title = MakeLabel(picker, "Choose an icon", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetTextColor(1, 1, 1)
	local close = UI.CreateFlatButton(picker, "Done", 22)
	close:SetWidth(60)
	close:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
	close:SetScript("OnClick", function()
		picker:Hide()
	end)

	-- Automatic
	local auto = UI.CreateFlatButton(picker, "Automatic  (follows what the goal tracks)", 40)
	auto:SetWidth(width - 2 * PAD)
	auto:SetPoint("TOPLEFT", PAD, -44)
	auto.icon = auto:CreateTexture(nil, "ARTWORK")
	auto.icon:SetSize(30, 30)
	auto.icon:SetPoint("LEFT", 6, 0)
	auto.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	auto.text:ClearAllPoints()
	auto.text:SetPoint("LEFT", auto.icon, "RIGHT", 10, 0)
	auto:SetScript("OnClick", function()
		PickIcon(nil)
	end)
	picker.auto = auto

	-- Drop an item or spell
	local drop = CreateFrame("Button", nil, picker)
	drop:SetSize(36, 36)
	drop:SetPoint("TOPLEFT", PAD, -92)
	drop.icon = drop:CreateTexture(nil, "ARTWORK")
	drop.icon:SetAllPoints()
	drop.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
	UI.AddBorder(drop)
	local function TakeCursor()
		local icon = CursorIcon()
		if icon then
			ClearCursor()
			PickIcon(icon)
		end
	end
	drop:SetScript("OnReceiveDrag", TakeCursor)
	drop:SetScript("OnClick", TakeCursor)
	picker.drop = drop
	local dropText = MakeLabel(picker, "Drop an item or spell here to use its icon, or pick one below.", "GameFontDisableSmall")
	dropText:SetPoint("LEFT", drop, "RIGHT", 10, 0)
	dropText:SetPoint("RIGHT", picker, "RIGHT", -PAD, 0)

	-- The grid shows ICON_ROWS rows of the list; the mouse wheel scrolls it.
	picker.cells = {}
	for row = 1, ICON_ROWS do
		for column = 1, ICON_COLUMNS do
			local cell = CreateFrame("Button", nil, picker)
			cell:SetSize(ICON_SIZE, ICON_SIZE)
			cell:SetPoint("TOPLEFT", PAD + (column - 1) * (ICON_SIZE + ICON_GAP), -gridTop - (row - 1) * (ICON_SIZE + ICON_GAP))
			cell.texture = cell:CreateTexture(nil, "ARTWORK")
			cell.texture:SetAllPoints()
			cell.selected = cell:CreateTexture(nil, "OVERLAY")
			cell.selected:SetPoint("TOPLEFT", -2, 2)
			cell.selected:SetPoint("BOTTOMRIGHT", 2, -2)
			cell.selected:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.45)
			local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.2)
			cell:SetScript("OnClick", function(self)
				if self.iconValue then
					PickIcon(self.iconValue)
				end
			end)
			table.insert(picker.cells, cell)
		end
	end
	picker.position = MakeLabel(picker, "", "GameFontDisableSmall")
	picker.position:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
	picker:EnableMouseWheel(true)
	picker:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta * 2
		self:Refresh()
	end)

	function picker:Refresh()
		local list = IconList()
		local rows = math.ceil(#list / ICON_COLUMNS)
		self.offset = math.max(0, math.min(self.offset, rows - ICON_ROWS))
		for index, cell in ipairs(self.cells) do
			local icon = list[self.offset * ICON_COLUMNS + index]
			cell.iconValue = icon
			cell.texture:SetTexture(icon)
			cell.selected:SetShown(icon ~= nil and icon == formIcon)
			cell:SetShown(icon ~= nil)
		end
		self.auto.icon:SetTexture(form.iconButton.autoIcon)
		self.auto:SetSelected(formIcon == nil)
		self.drop.icon:SetTexture(formIcon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		self.position:SetText(#list == 0 and "No icons." or
			string.format("%d icons  ·  scroll for more", #list))
	end

	picker:HookScript("OnShow", function(self)
		self:Refresh()
	end)
	return picker
end

local function ToggleIconPicker()
	iconPicker = iconPicker or CreateIconPicker()
	iconPicker:SetShown(not iconPicker:IsShown())
end

local function CreateForm(body)
	-- The form scrolls; the Create/Save button sits in a footer that always shows.
	local area = UI.CreateScrollArea(body)
	area:SetPoint("TOPLEFT")
	area:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	area.content:SetSize(WIDTH - SIDEBAR_WIDTH - 15, 760)
	area:Hide()
	form = CreateFrame("Frame", nil, area.content)
	form:SetPoint("TOPLEFT", PAD, -PAD)
	form:SetSize(WIDTH - SIDEBAR_WIDTH - 15 - 2 * PAD, 730)
	form.area = area
	area:HookScript("OnHide", function()
		if iconPicker then
			iconPicker:Hide()
		end
	end)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footer:Hide()
	form.footer = footer

	form.title = MakeLabel(form, "New goal", "GameFontNormalLarge")
	form.title:SetPoint("TOPLEFT", 2, 0)
	form.title:SetTextColor(1, 1, 1)

	-- Icon (top right): opens the icon picker.
	local iconButton = CreateFrame("Button", nil, form)
	iconButton:SetSize(40, 40)
	iconButton:SetPoint("TOPRIGHT", -2, 0)
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetAllPoints()
	iconButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local iconHighlight = iconButton:CreateTexture(nil, "HIGHLIGHT")
	iconHighlight:SetAllPoints()
	iconHighlight:SetColorTexture(1, 1, 1, 0.15)
	UI.AddBorder(iconButton)
	iconButton:SetScript("OnClick", ToggleIconPicker)
	iconButton:SetScript("OnReceiveDrag", function()
		local icon = CursorIcon()
		if icon then
			ClearCursor()
			PickIcon(icon)
		end
	end)
	iconButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Goal icon", "Click to choose an icon, or drop an item or spell on it to use its icon.")
	end)
	iconButton:SetScript("OnLeave", GameTooltip_Hide)
	form.iconButton = iconButton
	form.iconLabel = MakeLabel(form, "", "GameFontDisableSmall")
	form.iconLabel:SetPoint("RIGHT", iconButton, "LEFT", -8, 0)

	form.typeHeading = MakeHeading(form, "1. What do you want to track?")
	form.typeHeading:SetPoint("TOPLEFT", 2, -30)
	form.typeHelp = MakeLabel(form, "", "GameFontDisableSmall")
	form.typeHelp:SetPoint("TOPLEFT", 2, -78)
	form.typeHelp:SetPoint("RIGHT", form, "RIGHT")
	form.pickHeading = MakeHeading(form, "")
	form.pickHeading:SetPoint("TOPLEFT", 2, -108)
	form.amountHeading = MakeHeading(form, "")

	form.typeChips = {}
	local anchor
	for _, info in ipairs(GOAL_TYPES) do
		local chip = UI.CreateFlatButton(form, info.label, 24)
		chip:SetWidth(math.max(chip:GetWidth(), 56))
		chip.key = info.key
		chip:SetScript("OnClick", function(self)
			SetType(self.key)
		end)
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", 0, -46)
		end
		anchor = chip
		table.insert(form.typeChips, chip)
	end

	-- Item slot: drop an item on it (or click while holding one).
	local slot = CreateFrame("Button", nil, form)
	slot:SetSize(40, 40)
	slot:SetPoint("TOPLEFT", 0, -126)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	UI.AddBorder(slot)
	local function TakeCursorItem()
		local kind, itemID = GetCursorInfo()
		if kind == "item" and itemID then
			ClearCursor()
			SetItem(itemID)
		end
	end
	slot:SetScript("OnReceiveDrag", TakeCursorItem)
	slot:SetScript("OnClick", TakeCursorItem)
	slot:SetScript("OnEnter", function(self)
		if formItemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(formItemID)
			GameTooltip:Show()
		end
	end)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	form.slot = slot

	form.itemLabel = MakeLabel(form, "", "GameFontNormal")
	form.itemLabel:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
	form.itemName = MakeEditBox(form, 220)
	form.itemName:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 16, 0)
	form.itemName:SetScript("OnEnterPressed", function(self)
		local text = strtrim(self:GetText())
		local itemID = tonumber(text:match("item:(%d+)")) or tonumber(text) or (text ~= "" and C_Item.GetItemInfoInstant(text))
		if itemID then
			SetItem(itemID)
		else
			self:ClearFocus()
			ns:Print("Unknown item \"" .. text .. "\". Try dropping it on the slot or shift-clicking it.")
		end
	end)
	form.itemHint = MakeLabel(form, "Drop an item on the slot, or type a name and press Enter. Shift-click an item while the box has focus.", "GameFontDisableSmall")
	form.itemHint:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -6)
	form.itemHint:SetPoint("RIGHT", form, "RIGHT")

	form.amountLabel = MakeLabel(form, "")
	form.amountLabel:SetPoint("TOPLEFT", 2, -150)
	form.amount = MakeEditBox(form, 110, true)
	form.amount:SetPoint("LEFT", form.amountLabel, "LEFT", 160, 0)
	-- Only typing updates the form; code that sets the text updates it itself.
	form.amount:SetScript("OnTextChanged", function(_, userInput)
		if userInput then
			UpdateForm()
		end
	end)
	form.amount:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if form.create:IsEnabled() then
			SubmitForm()
		end
	end)
	form.amountHint = MakeLabel(form, "", "GameFontDisableSmall")
	form.amountHint:SetPoint("TOPLEFT", form.amountLabel, "BOTTOMLEFT", 0, -10)

	CreatePicker()
	form.maxChip:SetPoint("LEFT", form.amount, "RIGHT", 10, 0)

	-- Starting count
	form.seedHeading = MakeHeading(form, "")
	form.seedHeading:SetPoint("TOPLEFT", form.amountLabel, "BOTTOMLEFT", 0, -22)
	form.seedHelp = MakeLabel(form, "Ticked counts are added as already done; only new loot is counted after that.", "GameFontDisableSmall")
	form.seedHelp:SetPoint("TOPLEFT", form.seedHeading, "BOTTOMLEFT", 0, -4)
	form.seeds = {}
	for index = 1, 4 do
		local seed = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
		seed:SetSize(22, 22)
		seed.Text:SetFontObject("GameFontHighlight")
		seed:SetHitRectInsets(0, -150, 0, 0)
		seed:SetScript("OnClick", function()
			UpdateForm()
		end)
		seed.countText = form:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		seed.countText:SetPoint("LEFT", seed, "LEFT", 200, 1)
		seed.countText:SetWidth(90)
		seed.countText:SetJustifyH("RIGHT")
		seed:HookScript("OnShow", function(self)
			self.countText:Show()
		end)
		seed:HookScript("OnHide", function(self)
			self.countText:Hide()
		end)
		table.insert(form.seeds, seed)
	end
	form.othersText = MakeLabel(form, "", "GameFontDisableSmall")
	form.othersText:SetPoint("RIGHT", form, "RIGHT")
	form.startText = MakeLabel(form, "", "GameFontNormal")

	-- Sounds (per goal; "Default" follows the settings)
	form.soundHeading = MakeHeading(form, "")
	form.soundRows = {}
	local soundAnchor = form.soundHeading
	for _, info in ipairs({ { "milestone", "Milestones (25/50/75%)" }, { "complete", "When it's done" } }) do
		local which = info[1]
		local label = MakeLabel(form, info[2])
		label:SetPoint("TOPLEFT", soundAnchor, "BOTTOMLEFT", 0, soundAnchor == form.soundHeading and -12 or -16)
		local select = UI.CreateSoundSelect(form, {
			width = 190,
			get = function()
				return formSounds[which]
			end,
			set = function(value)
				formSounds[which] = value
				ns.sounds.Play(value == "default" and G().DefaultSound(which) or value)
			end,
			defaultLabel = function()
				return G().DefaultSoundLabel(which)
			end,
			resolveDefault = function()
				return G().DefaultSound(which)
			end,
		})
		select:SetPoint("LEFT", label, "LEFT", 160, 0)
		table.insert(form.soundRows, { label = label, select = select })
		soundAnchor = label
	end

	form.create = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
	form.create:SetSize(160, 26)
	form.create:SetPoint("LEFT", PAD, 0)
	form.create:SetScript("OnClick", SubmitForm)
	form.cancel = UI.CreateFlatButton(footer, "Cancel", 26)
	form.cancel:SetWidth(80)
	form.cancel:SetPoint("LEFT", form.create, "RIGHT", 6, 0)
	form.cancel:SetScript("OnClick", function()
		page = "active"
		ResetForm()
		Render()
	end)
	form.createHint = MakeLabel(footer, "", "GameFontDisableSmall")
	form.createHint:SetPoint("LEFT", form.create, "RIGHT", 12, 0)

	-- Shift-clicking an item while the name box has focus picks it.
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
			if form:IsVisible() and form.itemName:HasFocus() and type(link) == "string" then
				local itemID = tonumber(link:match("item:(%d+)"))
				if itemID then
					SetItem(itemID)
				end
			end
		end)
	end
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function UpdateNav()
	local data = G().GetData()
	for _, button in ipairs(navButtons) do
		button:SetSelected(button.page == page)
		if button.page == "active" then
			button.count:SetText(#data.goals)
		elseif button.page == "history" then
			button.count:SetText(#data.history)
		end
	end
end

function Render()
	if not (frame and frame:IsShown()) then
		return
	end
	UpdateNav()
	pool:ReleaseAll()
	local showForm = page == "new" or page == "edit"
	form.area:SetShown(showForm)
	form.footer:SetShown(showForm)
	scroll:SetShown(not showForm)
	if showForm then
		-- Standings, skills and currencies may have changed since the list was built.
		if PICKER_TYPES[formType] then
			pickerEntries = BuildPickerEntries(formType)
		end
		UpdateForm()
		return
	end
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local height = page == "history" and RenderHistory(content, width) or RenderActive(content, width)
	content:SetHeight(height)
	scroll:SetScroll(scroll:GetVerticalScroll())
end

-- Goals change every second while running: update the cards in place unless the
-- list itself changed.
local function OnGoalsChanged()
	if not (frame and frame:IsShown()) then
		return
	end
	if page ~= "active" then
		if page == "history" then
			UpdateNav()
		end
		return
	end
	if Signature(G().GetData().goals) ~= cardSignature then
		Render()
		return
	end
	for _, goal in ipairs(G().GetData().goals) do
		if cards[goal.id] then
			UpdateCard(cards[goal.id], goal)
		end
	end
	UpdateNav()
end

local function CreateGoalsWindow()
	frame = UI.CreateWindow("NraKitGoalsFrame", "Goals", WIDTH, HEIGHT, SIDEBAR_WIDTH, "goals")

	local newButton = UI.CreateFlatButton(frame.sidebar, "+  New Goal", 28)
	newButton:SetWidth(SIDEBAR_WIDTH - 2 * PAD)
	newButton:SetPoint("TOPLEFT", PAD, -PAD)
	newButton:SetSelected(true)
	newButton:SetScript("OnClick", function()
		ns:OpenGoalsWindow("new")
	end)

	local anchor = newButton
	for _, info in ipairs({ { "active", "Active goals" }, { "history", "History" } }) do
		local button = UI.CreateNavButton(frame.sidebar, SIDEBAR_WIDTH - 2 * PAD, 26, info[2])
		button.page = info[1]
		button:SetScript("OnClick", function(self)
			page = self.page
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			scroll:SetScroll(0)
			Render()
		end)
		button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == newButton and -12 or -2)
		anchor = button
		table.insert(navButtons, button)
	end

	local help = frame.sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("BOTTOMLEFT", PAD, PAD)
	help:SetWidth(SIDEBAR_WIDTH - 2 * PAD)
	help:SetJustifyH("LEFT")
	help:SetSpacing(2)
	help:SetText("Goals count what you gain after you make them.\n\n"
		.. "They show in a small tracker you can drag anywhere. Right-click a goal there to pause, "
		.. "reset or remove it.\n\nThe tracker's look and sounds are in the NraKit settings.")

	scroll = UI.CreateScrollArea(frame.body)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -13, 0)
	scroll.content:SetWidth(WIDTH - SIDEBAR_WIDTH - 15)

	CreateForm(frame.body)

	frame:HookScript("OnShow", Render)
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:SetScript("OnEvent", function()
		if form:IsVisible() then
			UpdateForm()
		end
	end)
	ns.goals.onChanged = OnGoalsChanged
end

-- /nra goal, the tracker's "+" and "Edit". With a page ("new", "edit", ...), always shows it.
function ns:OpenGoalsWindow(toPage, goalID)
	if not ns:IsModuleEnabled("farmGoals") then
		ns:Print("Turn on Farm Goals first (/nra).")
		return
	end
	if not frame then
		CreateGoalsWindow()
	end
	if not toPage and frame:IsShown() then
		frame:Hide()
		return
	end
	if toPage == "recount" then
		toPage = "edit"
	end
	local focusTarget
	if toPage == "edit" then
		local goal = G().FindGoal(goalID)
		if not goal then
			return
		end
		editID = goalID
		LoadGoal(goal)
		-- "New target" on a finished goal: straight to typing the new number.
		focusTarget = goal.completed ~= nil
		form.area:SetScroll(0)
	elseif toPage == "new" and page == "edit" then
		ResetForm()
	end
	if toPage then
		page = toPage
	elseif #G().GetData().goals == 0 then
		page = "new"
	end
	if page == "new" and formType == "level" and form.amount:GetText() == "" then
		form.amount:SetText(tostring(UnitLevel("player") + 1))
	end
	frame:Show()
	Render()
	if focusTarget and form.amount:IsShown() then
		form.amount:SetFocus()
		form.amount:HighlightText()
	end
end

UI.RegisterTab({
	key = "goals", label = "Goals", menuLabel = "Farm Goals", order = 3, frameName = "NraKitGoalsFrame",
	open = function()
		ns:OpenGoalsWindow()
	end,
	module = "farmGoals",
})

ns:AddOptionsButton("farmGoals", "Open Goals Window", "Your goals, history and a new goal (/nra goal).", function()
	ns:OpenGoalsWindow()
end)
