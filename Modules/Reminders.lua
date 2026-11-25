local _, ns = ...

-- Reminders: notes to yourself that come back when they're due. /nra remind <text> is for
-- your next login; a trigger in front makes it come back later instead:
--   /nra remind 30m <text>                  in 30 minutes (s, m, h, d; 1h30m works too)
--   /nra remind in <zone>: <text>           when you enter that zone (or subzone)
--   /nra remind at <level>: <text>          when you reach that level
--   /nra remind @<character>: <text>        on that character's next login
-- @<character> goes with any trigger ("@Bankalt at 20: ..."). Shift-clicked links work.
--
-- A reminder that comes due shows on a card that stays up until you close it: tick what
-- you've done. Closing it keeps the rest: they move to a small tracker (an option) and the
-- card shows them again at your next login. A reminder never goes away unless you tick it.
-- Due reminders wait for combat to end before they show.
--
-- Saved account-wide in NraKitDB.remindersData = { nextID, characters = { [name] = { seen?,
-- list = { { id, text, kind = "login"|"time"|"zone"|"level", at?, zone?, level?, from?,
-- created, state = "waiting"|"due"|"done", dueAt?, away?, doneAt? } } } } }. A character is
-- `seen` once they log in with Reminders on; reminders for one that hasn't yet are kept
-- under the name you typed and picked up when they do.

local module = {
	key = "reminders",
	section = "Trackers & Reminders",
	name = "Reminders",
	description = "Notes to yourself that come back when they're due: /nra remind <text> for your next login, or after a time (30m), when you enter a zone, reach a level or log in on another character. Due reminders show on a card you close yourself, with a box to tick each one off, so you don't miss them.",
	default = false,
	options = {
		{
			key = "remindersTracker",
			header = "General",
			name = "Keep them on screen",
			description = "When you close the card with reminders not ticked off, they stay in a small list on screen until you tick them.",
			default = true,
		},
		{
			key = "remindersSound",
			name = "Play a sound",
			description = "Play a sound when reminders come due.",
			default = true,
		},
		{
			key = "remindersSoundChoice",
			parent = "remindersSound",
			type = "sound",
			name = "Sound",
			description = "Which sound plays when reminders come due.",
			default = "kit:UI_BNET_TOAST",
		},
	},
}

local LOGIN_DELAY = 5 -- seconds after logging in before the card shows (after the loading screen)
local CHECK_INTERVAL = 5 -- seconds between checks for timed reminders
local KEEP_DONE = 30 -- done reminders kept per character, newest first
local UNITS = { s = 1, m = 60, h = 3600, d = 86400 }

local UI = ns.UI
local reminders = {}
ns.reminders = reminders

local eventFrame = CreateFrame("Frame")
local ticker
local zonesBefore = {} -- the zone names you were in at the last check (lower case)
local showQueued = false -- due reminders wait for combat to end
local card, tracker
local trackerHidden = false -- hidden until the next login (folded is NraKitDB.remindersTrackerFolded)
local ready = false -- after the login check (timed reminders that passed while you were away count as such)
local initialized = false
local CardShow, RefreshTracker

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function DB()
	NraKitDB.remindersData = NraKitDB.remindersData or {}
	local data = NraKitDB.remindersData
	data.nextID = data.nextID or 1
	data.characters = data.characters or {}
	return data
end

-- "Bob-Stone", "bob stone" -> "bob stone": how names are compared.
local function NameKey(name)
	return strtrim((name or ""):gsub("-", " ")):lower()
end

function reminders.Character(name)
	local characters = DB().characters
	name = name or ns:PlayerName() or "?"
	characters[name] = characters[name] or { list = {} }
	return characters[name]
end

function reminders.List(name)
	return reminders.Character(name).list
end

local function Changed()
	if reminders.onChanged then
		reminders.onChanged()
	end
	ns:BadgeChanged()
	if card and card:IsShown() and not card.preview then
		card:Refresh()
	end
	RefreshTracker()
end

-- Your characters NraKit has seen, by full name.
function reminders.KnownCharacters()
	local names = {}
	for name, character in pairs(DB().characters) do
		if character.seen then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- The character an @name means: a full name or a first name of one you've logged in
-- with. Returns the name, whether it's known, and the matches if a first name fits several.
function reminders.ResolveCharacter(typed)
	local key = NameKey(typed)
	local matches = {}
	for _, name in ipairs(reminders.KnownCharacters()) do
		if NameKey(name) == key then
			return name, true
		end
		if NameKey(name):match("^(%S+)") == key then
			table.insert(matches, name)
		end
	end
	if #matches == 1 then
		return matches[1], true
	elseif #matches > 1 then
		return nil, true, matches
	end
	return (typed:gsub("^%l", string.upper)), false
end

-- Takes over reminders left under another spelling of your name, or your first name alone
-- (for a character that hadn't logged in with NraKit yet).
local function ClaimReminders()
	local me = ns:PlayerName() or "?"
	local mine = reminders.Character(me)
	local myKey, myFirst = NameKey(me), NameKey(me):match("^(%S+)")
	for name, character in pairs(DB().characters) do
		if name ~= me and not character.seen and (NameKey(name) == myKey or NameKey(name) == myFirst) then
			for _, reminder in ipairs(character.list) do
				table.insert(mine.list, reminder)
			end
			DB().characters[name] = nil
		end
	end
	mine.seen = true
end

function reminders.Find(id)
	for name, character in pairs(DB().characters) do
		for index, reminder in ipairs(character.list) do
			if reminder.id == id then
				return reminder, name, index
			end
		end
	end
end

-- Adds a reminder: spec = { text, kind, at?, zone?, level? }, for `character` (you by default).
function reminders.Add(spec, character)
	local me = ns:PlayerName() or "?"
	local data = DB()
	local reminder = {
		id = data.nextID,
		text = spec.text,
		kind = spec.kind or "login",
		at = spec.at,
		zone = spec.zone,
		level = spec.level,
		created = time(),
		state = "waiting",
	}
	if character and character ~= me then
		reminder.from = me
	end
	data.nextID = data.nextID + 1
	table.insert(reminders.List(character or me), reminder)
	Changed()
	return reminder
end

-- Old done reminders go, so the list doesn't grow forever.
local function PruneDone(list)
	local done = {}
	for _, reminder in ipairs(list) do
		if reminder.state == "done" then
			table.insert(done, reminder)
		end
	end
	if #done <= KEEP_DONE then
		return
	end
	table.sort(done, function(a, b)
		return (a.doneAt or 0) > (b.doneAt or 0)
	end)
	local drop = {}
	for index = KEEP_DONE + 1, #done do
		drop[done[index]] = true
	end
	for index = #list, 1, -1 do
		if drop[list[index]] then
			table.remove(list, index)
		end
	end
end

function reminders.SetDone(id, done)
	local reminder, owner = reminders.Find(id)
	if not reminder then
		return
	end
	if done then
		reminder.state, reminder.doneAt = "done", time()
		PruneDone(reminders.List(owner))
	else
		reminder.state, reminder.doneAt = "due", nil
		reminder.dueAt = reminder.dueAt or time()
	end
	Changed()
end

function reminders.SetText(id, text)
	local reminder = reminders.Find(id)
	text = strtrim(text or "")
	if reminder and text ~= "" then
		reminder.text = text
		Changed()
	end
end

function reminders.Remove(id)
	local _, owner, index = reminders.Find(id)
	if index then
		table.remove(reminders.List(owner), index)
		Changed()
	end
end

-- Puts a reminder back to waiting: for `seconds` more, or until the next login (nil).
function reminders.Snooze(id, seconds)
	local reminder = reminders.Find(id)
	if not reminder then
		return
	end
	reminder.state, reminder.dueAt, reminder.away, reminder.doneAt = "waiting", nil, nil, nil
	reminder.zone, reminder.level = nil, nil
	if seconds then
		reminder.kind, reminder.at = "time", time() + seconds
	else
		reminder.kind, reminder.at = "login", nil
	end
	Changed()
end

-- Your due reminders (not ticked off), oldest first.
function reminders.Due()
	local due = {}
	for _, reminder in ipairs(reminders.List()) do
		if reminder.state == "due" then
			table.insert(due, reminder)
		end
	end
	table.sort(due, function(a, b)
		if (a.dueAt or 0) ~= (b.dueAt or 0) then
			return (a.dueAt or 0) < (b.dueAt or 0)
		end
		return a.id < b.id
	end)
	return due
end

------------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------------

-- 90 -> "1 min 30 s", 7200 -> "2 h", 90000 -> "1 day 1 h".
function reminders.FormatDuration(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds < 60 then
		return seconds .. " s"
	end
	local days, hours = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
	local minutes, rest = math.floor(seconds % 3600 / 60), seconds % 60
	local parts = {}
	if days > 0 then
		table.insert(parts, days .. (days == 1 and " day" or " days"))
	end
	if hours > 0 then
		table.insert(parts, hours .. " h")
	end
	if minutes > 0 and days == 0 then
		table.insert(parts, minutes .. " min")
	end
	if rest > 0 and days == 0 and hours == 0 and minutes < 10 then
		table.insert(parts, rest .. " s")
	end
	return table.concat(parts, " ")
end

-- When a waiting reminder comes due: "Next login", "In 25 min", "In Darkshore", "At level 30".
function reminders.Describe(reminder)
	if reminder.kind == "time" then
		local left = (reminder.at or 0) - time()
		if left <= 0 then
			return "Any moment"
		end
		return "In " .. reminders.FormatDuration(left) .. date(left < 86400 and " (%H:%M)" or " (%a %H:%M)", reminder.at)
	elseif reminder.kind == "zone" then
		return "In " .. (reminder.zone or "?")
	elseif reminder.kind == "level" then
		return "At level " .. (reminder.level or "?")
	end
	return "Next login"
end

-- What came due, for the card: "From Main", "Came due while you were away", "You entered Darkshore".
function reminders.DueNote(reminder)
	local parts = {}
	if reminder.from then
		table.insert(parts, "From " .. reminder.from)
	end
	if reminder.away then
		table.insert(parts, "came due while you were away")
	elseif reminder.kind == "zone" then
		table.insert(parts, "you entered " .. (reminder.zone or "?"))
	elseif reminder.kind == "level" then
		table.insert(parts, "you reached level " .. (reminder.level or "?"))
	elseif reminder.kind == "time" and reminder.at then
		table.insert(parts, date("set for %H:%M", reminder.at))
	end
	local text = table.concat(parts, ", ")
	return (text:gsub("^%l", string.upper))
end

------------------------------------------------------------------------------
-- Parsing /nra remind
------------------------------------------------------------------------------

-- "1h30m" -> 5400; nil if it isn't only numbers with units.
local function ParseDuration(word)
	if not word:match("^[%d smhd]+$") or not word:match("^%d") then
		return nil
	end
	local total, rest = 0, word
	while rest ~= "" do
		local amount, unit, after = rest:match("^(%d+)([smhd])(.*)$")
		if not amount then
			return nil
		end
		total = total + tonumber(amount) * UNITS[unit]
		rest = after
	end
	return total > 0 and total or nil
end

-- The words after /nra remind -> spec = { text, kind, at?, zone?, level?, character?, known?,
-- duration? }, or nil and what's wrong. A trigger in front ends with a colon (zones have
-- spaces); a time doesn't need one ("30m text").
function reminders.Parse(input)
	local rest = strtrim(input or "")
	local spec = { kind = "login" }

	local who, after = rest:match("^@([^%s:]+)(.*)$")
	if who then
		-- A known "First Surname" takes both words.
		local second, afterSecond = after:match("^%s+([^%s:]+)(.*)$")
		local name, known, matches
		if second then
			name, known = reminders.ResolveCharacter(who .. " " .. second)
			if known and NameKey(name) == NameKey(who .. " " .. second) then
				after = afterSecond
			else
				name, known, matches = nil, nil, nil
			end
		end
		if not name then
			name, known, matches = reminders.ResolveCharacter(who)
		end
		if matches then
			return nil, string.format("Which %s? %s. Type their full name after @.", who, table.concat(matches, ", "))
		end
		spec.character, spec.known = name, known
		rest = strtrim((after:gsub("^%s*:", "")))
	end

	local zone, afterZone = rest:match("^[Ii][Nn]%s+([^:|]+):(.*)$")
	local level, afterLevel = rest:match("^[Aa][Tt]%s+(%d+)%s*:(.*)$")
	local word, afterWord = rest:match("^(%S+)%s+(.*)$")
	if not word then
		word, afterWord = rest, "" -- only a time: nothing to say
	end
	local timeWord = word and word:gsub(":$", "")
	if zone and strtrim(zone) ~= "" then
		spec.kind, spec.zone, rest = "zone", strtrim(zone), afterZone
	elseif level then
		spec.kind, spec.level, rest = "level", tonumber(level), afterLevel
	elseif timeWord and ParseDuration(timeWord:lower()) then
		spec.duration = ParseDuration(timeWord:lower())
		spec.kind, spec.at, rest = "time", time() + spec.duration, afterWord
	end

	spec.text = strtrim(rest)
	if spec.text == "" then
		return nil, "What should the reminder say? Type it after the trigger, e.g. /nra remind 30m check the auction house."
	end
	if spec.kind == "level" and (spec.level < 2 or spec.level > (GetMaxPlayerLevel and GetMaxPlayerLevel() or 999)) then
		return nil, "That's not a level you can reach."
	end
	local me = ns:PlayerName() or "?"
	if spec.character and NameKey(spec.character) == NameKey(me) then
		spec.character, spec.known = nil, nil -- @yourself is just a reminder
	end
	if spec.kind == "level" and not spec.character and UnitLevel("player") >= spec.level then
		return nil, string.format("You're level %d already.", UnitLevel("player"))
	end
	return spec
end

------------------------------------------------------------------------------
-- Coming due
------------------------------------------------------------------------------

local function CurrentZones()
	local zones = {}
	for _, get in ipairs({ GetRealZoneText, GetZoneText, GetSubZoneText, GetMinimapZoneText }) do
		local name = get and get()
		if type(name) == "string" and name ~= "" then
			zones[name:lower()] = true
		end
	end
	return zones
end

-- Marks your waiting reminders that are due now. how: "login" (the session's first check:
-- login reminders count, and timed ones that passed were while you were away), "zone" or
-- nil. Returns how many came due.
local function Evaluate(how)
	local now, zones = time(), CurrentZones()
	local level = UnitLevel("player") or 1
	local count = 0
	for _, reminder in ipairs(reminders.List()) do
		if reminder.state == "waiting" then
			local due = false
			if reminder.kind == "login" then
				due = how == "login"
			elseif reminder.kind == "time" then
				due = (reminder.at or 0) <= now
				reminder.away = due and how == "login" or nil
			elseif reminder.kind == "zone" then
				local zone = (reminder.zone or ""):lower()
				due = zones[zone] == true and not zonesBefore[zone]
			elseif reminder.kind == "level" then
				due = level >= (reminder.level or 0)
			end
			if due then
				reminder.state, reminder.dueAt = "due", now
				count = count + 1
			end
		end
	end
	zonesBefore = zones
	return count
end

-- Shows the card with what's due (after combat), with the sound.
local function ShowDue()
	showQueued = false
	if #reminders.Due() == 0 then
		return
	end
	if InCombatLockdown() then
		showQueued = true
		return
	end
	if ns:GetOption("remindersSound") then
		ns.sounds.PlayOption("remindersSoundChoice", "kit:UI_BNET_TOAST")
	end
	CardShow()
end

-- Checks for reminders that came due; shows them if any did.
function reminders.Check(how)
	if not ns:IsModuleEnabled(module.key) or not (ready or how == "login") then
		return
	end
	if Evaluate(how) > 0 then
		Changed()
		ShowDue()
	end
end

local function OnLogin()
	ClaimReminders()
	reminders.Check("login")
	ready = true
	if #reminders.Due() > 0 and not (card and card:IsShown()) then
		ShowDue() -- older due reminders you didn't tick come back every login
	end
end

------------------------------------------------------------------------------
-- Rows (card and tracker)
------------------------------------------------------------------------------

-- A tick box: box:SetChecked(on); onClick(box) after it flips.
function reminders.CreateCheck(parent, onClick)
	local box = CreateFrame("Button", nil, parent)
	box:SetSize(18, 18)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.08)
	UI.AddBorder(box)
	box.mark = box:CreateTexture(nil, "ARTWORK")
	box.mark:SetPoint("CENTER")
	box.mark:SetSize(16, 16)
	box.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	local highlight = box:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.1)
	function box:SetChecked(on)
		self.checked = on
		self.mark:SetShown(on)
	end
	function box:GetChecked()
		return self.checked == true
	end
	box:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		onClick(self)
	end)
	box:SetChecked(false)
	return box
end

-- Links in reminder text show their tooltip and can be clicked (shift-click to link them).
function reminders.EnableLinks(frame)
	frame:SetHyperlinksEnabled(true)
	frame:SetScript("OnHyperlinkEnter", function(self, link)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	frame:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
	frame:SetScript("OnHyperlinkClick", function(_, link, text, button)
		SetItemRef(link, text, button)
	end)
end

local function OpenRowMenu(owner, reminder)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Reminder")
		root:CreateButton(reminder.state == "done" and "Not done" or "Done", function()
			reminders.SetDone(reminder.id, reminder.state ~= "done")
		end)
		root:CreateButton("Remind me again in 15 minutes", function()
			reminders.Snooze(reminder.id, 15 * 60)
		end)
		root:CreateButton("Remind me again in 1 hour", function()
			reminders.Snooze(reminder.id, 3600)
		end)
		root:CreateButton("Remind me again next login", function()
			reminders.Snooze(reminder.id)
		end)
		root:CreateButton("Edit", function()
			if ns.OpenReminders then
				ns:OpenReminders(reminder.id)
			end
		end)
		root:CreateDivider()
		root:CreateButton("Delete", function()
			reminders.Remove(reminder.id)
		end)
	end)
end
reminders.OpenRowMenu = OpenRowMenu

-- A reminder line: tick box, text (links work), and a small note under it if `withNote`.
local function CreateRow(parent, height, onTick)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(height)
	row:EnableMouse(true)
	reminders.EnableLinks(row)
	row.check = reminders.CreateCheck(row, function(box)
		onTick(box:GetParent(), box:GetChecked())
	end)
	row.check:SetPoint("TOPLEFT", 2, -2)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 8, -2)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.note:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
	row.note:SetPoint("RIGHT", -4, 0)
	row.note:SetJustifyH("LEFT")
	row.note:SetWordWrap(false)
	row:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and self.reminder and not self.preview then
			OpenRowMenu(self, self.reminder)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.text:IsTruncated() then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.reminder.text, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function FillRow(row, reminder, withNote)
	row.reminder = reminder
	row.reminderID = reminder.id
	local done = reminder.state == "done"
	row.check:SetChecked(done)
	row.text:SetText(reminder.text)
	row.text:SetAlpha(done and 0.45 or 1)
	if withNote then
		local note = reminders.DueNote(reminder)
		row.note:SetText(note)
		row.note:SetShown(note ~= "")
	else
		row.note:Hide()
	end
end

------------------------------------------------------------------------------
-- The card: what came due, until you close it
------------------------------------------------------------------------------

local CARD_WIDTH = 420
local CARD_ROW = 40
local CARD_MAX_ROWS = 8

local function CreateCard()
	card = CreateFrame("Frame", "NraKitRemindersCard", UIParent)
	card:SetSize(CARD_WIDTH, 200)
	card:SetPoint("TOP", UIParent, "TOP", 0, -140)
	card:SetFrameStrata("DIALOG")
	card:SetToplevel(true)
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:EnableMouse(true)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", card.StartMoving)
	card:SetScript("OnDragStop", card.StopMovingOrSizing)
	card:Hide()
	-- Not in UISpecialFrames: Escape doesn't close it, you do.

	local bg = card:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(card)
	local accent = card:CreateTexture(nil, "BORDER")
	accent:SetColorTexture(unpack(UI.ACCENT))
	accent:SetPoint("TOPLEFT")
	accent:SetPoint("TOPRIGHT")
	accent:SetHeight(2)

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(22, 22)
	card.icon:SetPoint("TOPLEFT", UI.PAD, -12)
	card.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.title:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
	card.title:SetTextColor(unpack(UI.ACCENT))
	card.title:SetText("Reminders")

	card.rows = {}
	local function OnTick(row, checked)
		if row.preview then
			row.reminder.state = checked and "done" or "due" -- made up: nothing saved
		else
			reminders.SetDone(row.reminderID, checked)
		end
		card:Refresh()
	end
	for index = 1, CARD_MAX_ROWS do
		local row = CreateRow(card, CARD_ROW, OnTick)
		row:SetPoint("TOPLEFT", UI.PAD, -46 - (index - 1) * CARD_ROW)
		row:SetPoint("RIGHT", -UI.PAD, 0)
		card.rows[index] = row
	end
	card.more = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

	card.close = UI.CreateFlatButton(card, "Close", 24)
	card.close:SetWidth(90)
	card.close:SetPoint("BOTTOMRIGHT", -UI.PAD, UI.PAD)
	card.close:SetScript("OnClick", function()
		card:Hide()
	end)
	card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.hint:SetPoint("LEFT", UI.PAD, 0)
	card.hint:SetPoint("RIGHT", card.close, "LEFT", -10, 0)
	card.hint:SetPoint("BOTTOM", 0, UI.PAD + 6)
	card.hint:SetJustifyH("LEFT")

	function card:Refresh()
		local list = self.list
		local open = 0
		for index, row in ipairs(self.rows) do
			local reminder = list[index]
			row:SetShown(reminder ~= nil)
			if reminder then
				row.preview = self.preview
				FillRow(row, reminder, true)
			end
		end
		for _, reminder in ipairs(list) do
			if reminder.state ~= "done" then
				open = open + 1
			end
		end
		local shownRows = math.min(#list, CARD_MAX_ROWS)
		self.more:ClearAllPoints()
		self.more:SetPoint("TOPLEFT", UI.PAD + 28, -46 - shownRows * CARD_ROW)
		self.more:SetText(#list > CARD_MAX_ROWS and string.format("and %d more (/nra remind)", #list - CARD_MAX_ROWS) or "")
		local extra = #list > CARD_MAX_ROWS and 18 or 0
		self:SetHeight(46 + shownRows * CARD_ROW + extra + 48)
		if open == 0 then
			self.hint:SetText("All done!")
			self.close.text:SetText("Close")
		elseif ns:GetOption("remindersTracker") then
			self.hint:SetText("Tick what you've done. The rest stay on screen and come back at your next login.")
			self.close.text:SetText("Later")
		else
			self.hint:SetText("Tick what you've done. The rest come back at your next login.")
			self.close.text:SetText("Later")
		end
	end

	card:HookScript("OnShow", function()
		RefreshTracker()
	end)
	card:HookScript("OnHide", function(self)
		self.preview = nil
		RefreshTracker()
	end)
end

-- Shows the card with your due reminders (adding any that came due while it's up), or
-- `list` made-up ones for the preview.
function CardShow(list)
	if not card then
		CreateCard()
	end
	if list then
		card.preview, card.list = true, list
	else
		if not card:IsShown() or card.preview then
			card.list = {}
		end
		card.preview = nil
		local listed = {}
		for _, reminder in ipairs(card.list) do
			listed[reminder] = true
		end
		for _, reminder in ipairs(reminders.Due()) do
			if not listed[reminder] then
				table.insert(card.list, reminder)
			end
		end
	end
	card:Show()
	card:Raise()
	card:Refresh()
end
reminders.ShowCard = CardShow

------------------------------------------------------------------------------
-- The tracker: what's due, after you closed the card
------------------------------------------------------------------------------

local TRACKER_WIDTH = 260
local TRACKER_ROW = 24
local TRACKER_MAX_ROWS = 10

local function CreateTracker()
	tracker = CreateFrame("Frame", "NraKitRemindersTracker", UIParent)
	tracker:SetSize(TRACKER_WIDTH, 60)
	tracker:SetFrameStrata("MEDIUM")
	tracker:SetClampedToScreen(true)
	tracker:SetMovable(true)
	tracker:EnableMouse(true)
	tracker:RegisterForDrag("LeftButton")
	tracker:SetScript("OnDragStart", tracker.StartMoving)
	tracker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		if point then
			NraKitDB.remindersTrackerPosition = { point, relativePoint, x, y }
		end
	end)
	local position = NraKitDB.remindersTrackerPosition
	if position then
		tracker:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	else
		tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -420)
	end
	tracker:Hide()

	local bg = tracker:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(tracker)

	-- The header: click to fold or unfold, right-click for more, drag to move.
	local header = CreateFrame("Button", nil, tracker)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(28)
	header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		tracker:GetScript("OnDragStart")(tracker)
	end)
	header:SetScript("OnDragStop", function()
		tracker:GetScript("OnDragStop")(tracker)
	end)
	local highlight = header:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.04)
	tracker.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tracker.title:SetPoint("LEFT", 10, 0)
	tracker.title:SetTextColor(unpack(UI.ACCENT))
	tracker.arrow = header:CreateTexture(nil, "ARTWORK")
	tracker.arrow:SetSize(12, 12)
	tracker.arrow:SetPoint("RIGHT", -10, 0)
	tracker.arrow:SetAtlas("common-icon-forwardarrow")
	header:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			MenuUtil.CreateContextMenu(self, function(_, root)
				root:CreateTitle("Reminders")
				root:CreateButton(NraKitDB.remindersTrackerFolded and "Unfold" or "Fold", function()
					reminders.SetTrackerFolded(not NraKitDB.remindersTrackerFolded)
				end)
				root:CreateButton("Hide until next login", function()
					trackerHidden = true
					RefreshTracker()
					ns:Print("Reminders hidden until your next login. /nra remind show brings them back.")
				end)
				root:CreateButton("Open reminders", function()
					ns:OpenReminders()
				end)
			end)
		else
			reminders.SetTrackerFolded(not NraKitDB.remindersTrackerFolded)
		end
	end)
	header:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Reminders", (NraKitDB.remindersTrackerFolded and "Click to unfold." or "Click to fold.")
			.. " Right-click to hide it until your next login. Drag to move.")
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	tracker.header = header

	tracker.rows = {}
	local function OnTick(row, checked)
		reminders.SetDone(row.reminderID, checked)
	end
	for index = 1, TRACKER_MAX_ROWS do
		local row = CreateRow(tracker, TRACKER_ROW, OnTick)
		row:SetPoint("TOPLEFT", 8, -30 - (index - 1) * TRACKER_ROW)
		row:SetPoint("RIGHT", -8, 0)
		tracker.rows[index] = row
	end
	tracker.more = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tracker.list = {}
end

-- The tracker lists due reminders while the card is closed (ticked ones stay, dimmed, so a
-- slip can be undone, until all are done).
function RefreshTracker()
	local due = ns:IsModuleEnabled(module.key) and reminders.Due() or {}
	local wanted = #due > 0 and ns:GetOption("remindersTracker") and not trackerHidden
		and not (card and card:IsShown())
	if not wanted then
		if tracker then
			tracker:Hide()
			tracker.list = {}
		end
		return
	end
	if not tracker then
		CreateTracker()
	end
	local listed = {}
	for _, reminder in ipairs(tracker.list) do
		listed[reminder] = true
	end
	for _, reminder in ipairs(due) do
		if not listed[reminder] then
			table.insert(tracker.list, reminder)
		end
	end
	-- Reminders deleted or snoozed meanwhile go.
	for index = #tracker.list, 1, -1 do
		local state = tracker.list[index].state
		if state == "waiting" or not reminders.Find(tracker.list[index].id) then
			table.remove(tracker.list, index)
		end
	end
	local list = tracker.list
	local folded = NraKitDB.remindersTrackerFolded == true
	tracker.arrow:SetRotation(folded and 0 or -math.pi / 2)
	tracker.title:SetText(string.format("Reminders (%d)", #due))
	if folded then
		for _, row in ipairs(tracker.rows) do
			row:Hide()
		end
		tracker.more:SetText("")
		tracker:SetHeight(28)
		tracker:Show()
		return
	end
	for index, row in ipairs(tracker.rows) do
		row:SetShown(list[index] ~= nil)
		if list[index] then
			FillRow(row, list[index], false)
		end
	end
	local shownRows = math.min(#list, TRACKER_MAX_ROWS)
	tracker.more:ClearAllPoints()
	tracker.more:SetPoint("TOPLEFT", 34, -30 - shownRows * TRACKER_ROW)
	tracker.more:SetText(#list > TRACKER_MAX_ROWS and string.format("and %d more (/nra remind)", #list - TRACKER_MAX_ROWS) or "")
	tracker:SetHeight(36 + shownRows * TRACKER_ROW + (#list > TRACKER_MAX_ROWS and 16 or 0))
	tracker:Show()
end

function reminders.SetTrackerFolded(folded)
	NraKitDB.remindersTrackerFolded = folded or nil
	PlaySound(folded and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	RefreshTracker()
end

-- Brings your due reminders back on screen: the tracker, unfolded (or the card, without the
-- tracker option). With nothing due, says so.
function reminders.ShowTracker()
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Reminders first (/nra).")
		return
	end
	if #reminders.Due() == 0 then
		ns:Print("No reminders are due. /nra remind lists the ones waiting.")
		return
	end
	trackerHidden = false
	NraKitDB.remindersTrackerFolded = nil
	if ns:GetOption("remindersTracker") and not (card and card:IsShown()) then
		RefreshTracker()
	else
		CardShow()
	end
end

------------------------------------------------------------------------------
-- /nra remind
------------------------------------------------------------------------------

local function Confirm(reminder, spec)
	local text = reminder.text
	local whose = spec.character and (spec.character .. "'s") or "your"
	if spec.kind == "time" then
		ns:Print(string.format("I'll remind %s in %s (at %s): %s", spec.character or "you",
			reminders.FormatDuration(spec.duration), date("%H:%M", reminder.at), text))
	elseif spec.kind == "zone" then
		local note = ""
		if not spec.character and CurrentZones()[spec.zone:lower()] then
			note = " You're there now, so it's the next time you come back."
		end
		ns:Print(string.format("I'll remind %s when %s %s: %s.%s", spec.character or "you",
			spec.character and "they enter" or "you enter", spec.zone, text, note))
	elseif spec.kind == "level" then
		ns:Print(string.format("I'll remind %s at level %d: %s", spec.character or "you", spec.level, text))
	else
		ns:Print(string.format("Saved for %s next login: %s", whose, text))
	end
	if spec.character and not spec.known then
		ns:Print(string.format("I haven't seen %s log in with NraKit yet; saved anyway, they'll get it when they do.", spec.character))
	end
end

local function OnSlashCommand(rest)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Reminders first (/nra).")
		return
	end
	if rest == "" then
		ns:OpenReminders()
		return
	elseif rest:lower() == "show" then
		reminders.ShowTracker()
		return
	end
	local spec, problem = reminders.Parse(rest)
	if not spec then
		ns:Print(problem)
		return
	end
	local reminder = reminders.Add(spec, spec.character)
	if spec.kind == "zone" and not spec.character then
		zonesBefore = CurrentZones() -- where you are now doesn't count as entering
	end
	Confirm(reminder, spec)
	return reminder
end
reminders.OnSlashCommand = OnSlashCommand

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		local isLogin = ...
		if isLogin then
			zonesBefore = {}
			C_Timer.After(LOGIN_DELAY, OnLogin)
		else
			-- A reload, or a loading screen: no login reminders; where you are now isn't
			-- entering it after a reload.
			if not next(zonesBefore) then
				zonesBefore = CurrentZones()
				ClaimReminders()
				RefreshTracker()
			end
			ready = true
			reminders.Check("zone")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if showQueued then
			ShowDue()
		end
	elseif event == "PLAYER_LEVEL_UP" then
		C_Timer.After(0.5, reminders.Check)
	else
		reminders.Check("zone")
	end
end)

local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA" }

-- Key binding (Bindings.xml).
_G["BINDING_NAME_NRAKIT_SHOW_REMINDERS"] = "Show due reminders"
function NraKit_ShowReminders()
	reminders.ShowTracker()
end

ns:RegisterBadge({
	key = "reminders",
	option = "nraButtonBadgeReminders",
	module = module.key,
	count = function()
		return #reminders.Due()
	end,
	text = function(count)
		return string.format("%d %s due", count, count == 1 and "reminder" or "reminders")
	end,
	open = reminders.ShowTracker,
})

ns:RegisterMenuAction({
	module = module.key,
	label = function()
		local count = #reminders.Due()
		return count > 0 and string.format("Show due reminders |cffff9933(%d)|r", count) or nil
	end,
	onClick = reminders.ShowTracker,
})

ns:RegisterPreview("reminders", "Reminders: the card with reminders that came due", function()
	local now = time()
	CardShow({
		{ id = -1, text = "Go to Darkshore and hand in the turtle quests", kind = "login", state = "due", dueAt = now },
		{ id = -2, text = "Check the auction house for |cff1eff00[Coarse Thread]|r", kind = "time", at = now - 3600, away = true, state = "due", dueAt = now },
		{ id = -3, text = "Mail the bags to your main", kind = "login", from = "Bankalt", state = "due", dueAt = now },
	})
end)

function module:OnInitialize()
	local help = {
		summary = "Reminders: notes to yourself that come back at your next login, after a time, in a zone or at a level",
		usage = {
			"/nra remind - your reminders",
			"/nra remind show - show the due ones on screen again (after hiding or folding the list)",
			"/nra remind <text> - a reminder for your next login",
			"/nra remind 30m <text> - in 30 minutes (s, m, h, d: 2d is two days, 1h30m works too)",
			"/nra remind in <zone>: <text> - when you enter that zone or subzone",
			"/nra remind at <level>: <text> - when you reach that level",
			"/nra remind @<character>: <text> - on another character's next login (goes with the others too: @Alt at 20: ...)",
			"/nra reminder - the same as /nra remind",
		},
	}
	ns:RegisterSlashCommand("remind", OnSlashCommand, help)
	ns:RegisterSlashCommand("reminder", OnSlashCommand, help)
	ns:RegisterSlashCommand("reminders", OnSlashCommand, help)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
	initialized = true
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if enabled then
		ticker = C_Timer.NewTicker(CHECK_INTERVAL, function()
			reminders.Check()
		end)
		ClaimReminders()
		zonesBefore = CurrentZones()
		ready = ready or initialized -- turned on while playing
	elseif card then
		card:Hide()
	end
	RefreshTracker()
end

function module:OnOptionChanged()
	RefreshTracker()
	if card and card:IsShown() then
		card:Refresh()
	end
end

ns:RegisterModule(module)
