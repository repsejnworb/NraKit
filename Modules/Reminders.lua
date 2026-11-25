local _, ns = ...

-- Reminders & to-dos: notes to yourself that come back when they're due. /nra remind <text>
-- is for your next login; a trigger in front makes it come back later instead:
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
-- A to-do (/nra todo, same triggers) is a reminder without the card and sound: it goes
-- straight on the list (now, or when its trigger comes). The list on screen holds both, in
-- your order: drag a row, or use the arrows on the row under the mouse.
--
-- Saved account-wide in NraKitDB.remindersData = { nextID, characters = { [name] = { seen?,
-- list = { { id, text, kind = "login"|"time"|"zone"|"level", at?, zone?, level?, from?,
-- created, state = "waiting"|"due"|"done", quiet? (a to-do), order? (place in the list while
-- due), dueAt?, away?, doneAt?, since? } } } } }. A character is
-- `seen` once they log in with Reminders on; reminders for one that hasn't yet are kept
-- under the name you typed and picked up when they do.

local module = {
	key = "reminders",
	section = "Trackers & Reminders",
	name = "Reminders & to-dos",
	description = "Notes to yourself that come back when they're due: /nra remind <text> for your next login, or after a time (30m), when you enter a zone, reach a level or log in on another character. Due reminders show on a card you close yourself, so you don't miss them. To-dos (/nra todo) go straight on a list on screen instead, in your order.",
	default = false,
	options = {
		{
			key = "remindersTracker",
			header = "General",
			name = "Keep reminders on the list",
			description = "When you close the card with reminders not ticked off, they stay on the to-do list on screen until you tick them. (To-dos always go there.)",
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
local TICKED_STAY = 2 -- seconds a ticked row stays in the list (to untick a slip) before it fades
local TICKED_FADE = 1 -- seconds it takes to fade out
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
		quiet = spec.quiet or nil,
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

-- The place at the bottom of a character's list of due ones.
local function NextOrder(list)
	local last = 0
	for _, reminder in ipairs(list) do
		if reminder.state == "due" and reminder.order then
			last = math.max(last, reminder.order)
		end
	end
	return last + 1
end

-- Makes a reminder due now, at the bottom of the list.
local function MakeDue(reminder, list)
	reminder.order = NextOrder(list)
	reminder.state, reminder.dueAt = "due", time()
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
		reminder.order = reminder.order or NextOrder(reminders.List(owner))
	end
	Changed()
end

-- A to-do (no card, no sound) or a reminder.
function reminders.SetQuiet(id, quiet)
	local reminder = reminders.Find(id)
	if reminder then
		reminder.quiet = quiet or nil
		Changed()
	end
end

-- Moves one of your due reminders to `index` in the list (1 is the top).
function reminders.MoveTo(id, index)
	local due = reminders.Due()
	local from
	for position, reminder in ipairs(due) do
		if reminder.id == id then
			from = position
		end
	end
	if not from then
		return
	end
	local reminder = table.remove(due, from)
	table.insert(due, math.max(1, math.min(index, #due + 1)), reminder)
	for position, each in ipairs(due) do
		each.order = position
	end
	Changed()
end

-- Moves it up (-1) or down (1); to the top or bottom with `all`.
function reminders.Move(id, delta, all)
	local due = reminders.Due()
	for position, reminder in ipairs(due) do
		if reminder.id == id then
			reminders.MoveTo(id, all and (delta < 0 and 1 or #due) or position + delta)
			return
		end
	end
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
	reminder.since = time()
	if seconds then
		reminder.kind, reminder.at = "time", time() + seconds
	else
		reminder.kind, reminder.at = "login", nil
	end
	Changed()
end

-- Your due reminders and to-dos (not ticked off), in your order; only reminders with `loud`.
function reminders.Due(loud)
	local due = {}
	for _, reminder in ipairs(reminders.List()) do
		if reminder.state == "due" and not (loud and reminder.quiet) then
			table.insert(due, reminder)
		end
	end
	table.sort(due, function(a, b)
		if (a.order or math.huge) ~= (b.order or math.huge) then
			return (a.order or math.huge) < (b.order or math.huge)
		end
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

-- Why a reminder came due, for the card: "You entered Darkshore", "Time's up (after 30 min)",
-- "From Bankalt, you reached level 20", "Came due while you were away", "From last time".
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
		table.insert(parts, "time's up (after " .. reminders.FormatDuration(reminder.at - (reminder.since or reminder.created or reminder.at)) .. ")")
	elseif not reminder.from and not reminder.quiet then
		table.insert(parts, "from last time")
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
	return reminders.Validate(spec)
end

-- Checks a reminder before it's added (from /nra remind or the form). Returns the spec, or
-- nil and what's wrong.
function reminders.Validate(spec)
	if strtrim(spec.text or "") == "" then
		return nil, "What should the reminder say?"
	end
	if spec.kind == "time" and not (spec.duration and spec.duration > 0) then
		return nil, "How long until it comes due?"
	end
	if spec.kind == "zone" and strtrim(spec.zone or "") == "" then
		return nil, "Which zone?"
	end
	if spec.kind == "level" and not spec.level then
		return nil, "Which level?"
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
-- nil. Returns the ones that came due.
local function Evaluate(how)
	local now, zones = time(), CurrentZones()
	local level = UnitLevel("player") or 1
	local fresh = {}
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
				MakeDue(reminder, reminders.List())
				table.insert(fresh, reminder)
			end
		end
	end
	zonesBefore = zones
	return fresh
end

-- Shows the card for reminders that just came due (after combat), with the sound. At login it
-- also lists the ones still open from before (and shows for those alone).
local queued, queuedAtLogin = {}, false
local function ShowDue(fresh, atLogin)
	for _, reminder in ipairs(fresh or {}) do
		table.insert(queued, reminder)
	end
	queuedAtLogin = queuedAtLogin or atLogin == true
	if InCombatLockdown() then
		showQueued = true
		return
	end
	showQueued = false
	fresh, atLogin = {}, queuedAtLogin
	for _, reminder in ipairs(queued) do
		if reminder.state == "due" and not reminder.quiet then -- to-dos just go on the list
			table.insert(fresh, reminder)
		end
	end
	queued, queuedAtLogin = {}, false
	if #fresh == 0 and not (atLogin and #reminders.Due(true) > 0) then
		return
	end
	if ns:GetOption("remindersSound") then
		ns.sounds.PlayOption("remindersSoundChoice", "kit:UI_BNET_TOAST")
	end
	CardShow(fresh, atLogin)
end

-- Checks for reminders that came due, and shows them (not at login: OnLogin does). Returns them.
function reminders.Check(how)
	if not ns:IsModuleEnabled(module.key) or not (ready or how == "login") then
		return {}
	end
	local fresh = Evaluate(how)
	if #fresh > 0 then
		Changed()
		if how ~= "login" then
			ShowDue(fresh)
		end
	end
	return fresh
end

local function OnLogin()
	ClaimReminders()
	local fresh = reminders.Check("login")
	ready = true
	ShowDue(fresh, true) -- with the ones you didn't tick before: they come back every login
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
		root:CreateTitle(reminder.quiet and "To-do" or "Reminder")
		root:CreateButton(reminder.state == "done" and "Not done" or "Done", function()
			reminders.SetDone(reminder.id, reminder.state ~= "done")
		end)
		if reminder.state == "due" then
			root:CreateButton("Move to top", function()
				reminders.Move(reminder.id, -1, true)
			end)
			root:CreateButton("Move to bottom", function()
				reminders.Move(reminder.id, 1, true)
			end)
		end
		root:CreateButton(reminder.quiet and "Make it a reminder (pops up)" or "Make it a to-do (no pop-up)", function()
			reminders.SetQuiet(reminder.id, not reminder.quiet)
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

-- Reordering the list: up and down arrows on the row under the mouse (shift-click for the top
-- or bottom), and dragging a row onto another's place (a line shows where it lands).
local reorderRows = {}
local dropLine, dragged

local function DropTarget()
	for _, row in ipairs(reorderRows) do
		if row ~= dragged and row.canMove and row:IsVisible() and row:GetParent() == dragged:GetParent()
			and row:IsMouseOver() then
			return row
		end
	end
end

local function IndexOf(reminder)
	for index, each in ipairs(reminders.Due()) do
		if each == reminder then
			return index
		end
	end
end

function reminders.AddReorder(row)
	table.insert(reorderRows, row)
	local function Arrow(texture, delta)
		local arrow = CreateFrame("Button", nil, row)
		arrow:SetSize(16, 16)
		arrow:SetNormalTexture(texture)
		arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		arrow:SetFrameLevel(row:GetFrameLevel() + 3)
		arrow:Hide()
		arrow:SetScript("OnClick", function()
			reminders.Move(row.reminder.id, delta, IsShiftKeyDown())
		end)
		arrow:SetScript("OnEnter", function(self)
			UI.ShowTooltip(self, delta < 0 and "Move up" or "Move down",
				delta < 0 and "Shift-click: to the top. Or drag the row." or "Shift-click: to the bottom. Or drag the row.")
		end)
		arrow:SetScript("OnLeave", function()
			GameTooltip:Hide()
			if not row:IsMouseOver() then
				row.up:Hide()
				row.down:Hide()
			end
		end)
		return arrow
	end
	row.down = Arrow("Interface\\Buttons\\Arrow-Down-Up", 1)
	row.down:SetPoint("RIGHT", -2, 0)
	row.up = Arrow("Interface\\Buttons\\Arrow-Up-Up", -1)
	row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
	row:HookScript("OnEnter", function(self)
		self.up:SetShown(self.canMove == true)
		self.down:SetShown(self.canMove == true)
	end)
	row:HookScript("OnLeave", function(self)
		if not self:IsMouseOver() then
			self.up:Hide()
			self.down:Hide()
		end
	end)

	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(self)
		if not self.canMove then
			return
		end
		dragged, self.justDragged = self, true
		self:SetAlpha(0.5)
		if not dropLine then
			dropLine = CreateFrame("Frame", nil, UIParent)
			dropLine:SetFrameStrata("TOOLTIP")
			dropLine:SetHeight(2)
			local texture = dropLine:CreateTexture(nil, "OVERLAY")
			texture:SetAllPoints()
			texture:SetColorTexture(unpack(UI.ACCENT))
		end
		self:SetScript("OnUpdate", function()
			local target = DropTarget()
			dropLine:SetShown(target ~= nil)
			if target then
				local up = IndexOf(target.reminder) < IndexOf(dragged.reminder)
				dropLine:ClearAllPoints()
				dropLine:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", target, up and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
				dropLine:SetPoint(up and "BOTTOMRIGHT" or "TOPRIGHT", target, up and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0)
			end
		end)
	end)
	row:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:SetAlpha(1)
		if dropLine then
			dropLine:Hide()
		end
		local target = dragged == self and DropTarget()
		dragged = nil
		if target then
			reminders.MoveTo(self.reminder.id, IndexOf(target.reminder))
		end
	end)
end

local function FillRow(row, reminder, withNote)
	row.reminder = reminder
	row.reminderID = reminder.id
	row.canMove = reminder.state == "due"
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

local CARD_WIDTH = 440
local FRESH_ROW = 54
local OLDER_ROW = 22
local MAX_FRESH = 5
local MAX_OLDER = 6

-- One reminder that triggered the card: why (small, orange) over its text (large).
local function AcquireFreshRow(onTick)
	return card.pool:Acquire("fresh", function()
		local row = CreateRow(card, FRESH_ROW, onTick)
		row.text:SetFontObject("GameFontHighlightLarge")
		row.text:SetWordWrap(true)
		row.text:SetMaxLines(2)
		row.note:SetFontObject("GameFontNormalSmall")
		row.note:SetTextColor(unpack(UI.ACCENT))
		-- The why goes first, the text under it.
		row.note:ClearAllPoints()
		row.note:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 8, 2)
		row.note:SetPoint("RIGHT", -4, 0)
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", row.note, "BOTTOMLEFT", 0, -4)
		row.text:SetPoint("RIGHT", -4, 0)
		return row
	end)
end

local function AcquireOlderRow(onTick)
	return card.pool:Acquire("older", function()
		local row = CreateRow(card, OLDER_ROW, onTick)
		row.text:SetFontObject("GameFontHighlightSmall")
		row.check:SetSize(14, 14)
		row.check.mark:SetSize(13, 13)
		return row
	end)
end

local function AcquireLabel(font)
	return card.pool:Acquire("label" .. font, function()
		local label = card:CreateFontString(nil, "OVERLAY", font)
		label:SetJustifyH("LEFT")
		return label
	end)
end

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
	card.pool = UI.CreatePool()
	card.fresh, card.older = {}, {}

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

	-- Several reminders: Later (or Close once all are ticked). One: Done and Later.
	card.close = UI.CreateFlatButton(card, "Later", 24)
	card.close:SetWidth(90)
	card.close:SetPoint("BOTTOMRIGHT", -UI.PAD, UI.PAD)
	card.close:SetScript("OnClick", function()
		card:Hide()
	end)
	card.done = UI.CreateFlatButton(card, "Done", 24)
	card.done:SetWidth(90)
	card.done:SetPoint("RIGHT", card.close, "LEFT", -6, 0)
	card.done:SetScript("OnClick", function()
		local reminder = card.fresh[1]
		if reminder and not card.preview then
			reminders.SetDone(reminder.id, true)
		end
		card:Hide()
	end)
	card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.hint:SetPoint("LEFT", UI.PAD, 0)
	card.hint:SetPoint("RIGHT", card.done, "LEFT", -10, 0)
	card.hint:SetPoint("BOTTOM", 0, UI.PAD + 6)
	card.hint:SetJustifyH("LEFT")

	local function OnTick(row, checked)
		if row.preview then
			row.reminder.state = checked and "done" or "due" -- made up: nothing saved
		else
			reminders.SetDone(row.reminderID, checked)
		end
		card:Refresh()
	end

	-- Top: the reminders it popped up for. Below: the others still open, listed at login (it's
	-- the session's summary), otherwise one line (they're in the list on screen).
	function card:Refresh()
		self.pool:ReleaseAll()
		local fresh, older = self.fresh, self.older
		local listOlder = self.atLogin or #fresh == 0
		local single = #fresh == 1 and (#older == 0 or not listOlder)
		self.title:SetText(#fresh == 1 and "Reminder" or "Reminders")
		local y = -44
		for index, reminder in ipairs(fresh) do
			if index > MAX_FRESH then
				break
			end
			local row = AcquireFreshRow(OnTick)
			row.preview = self.preview
			FillRow(row, reminder, true)
			row.check:SetShown(not single)
			row.note:SetPoint("TOPLEFT", row.check, single and "TOPLEFT" or "TOPRIGHT", single and 0 or 8, 2)
			row:SetPoint("TOPLEFT", UI.PAD, y)
			row:SetPoint("RIGHT", -UI.PAD, 0)
			y = y - FRESH_ROW
		end
		if #fresh > MAX_FRESH then
			local more = AcquireLabel("GameFontDisableSmall")
			more:SetText(string.format("and %d more (/nra remind)", #fresh - MAX_FRESH))
			more:SetPoint("TOPLEFT", UI.PAD + 28, y)
			y = y - 18
		end
		local openOlder = 0
		for _, reminder in ipairs(older) do
			if reminder.state ~= "done" then
				openOlder = openOlder + 1
			end
		end
		if #older > 0 and listOlder then
			if #fresh > 0 then
				local line = self.pool:Acquire("line", function()
					local texture = card:CreateTexture(nil, "BORDER")
					texture:SetColorTexture(unpack(UI.EDGE))
					texture:SetHeight(1)
					return texture
				end)
				line:SetPoint("TOPLEFT", UI.PAD, y - 2)
				line:SetPoint("RIGHT", -UI.PAD, 0)
				y = y - 10
			end
			local label = AcquireLabel("GameFontNormalSmall")
			label:SetText(#fresh > 0 and "STILL OPEN" or "STILL OPEN FROM BEFORE")
			label:SetTextColor(unpack(UI.TEXT_DIM))
			label:SetPoint("TOPLEFT", UI.PAD, y)
			y = y - 18
			for index, reminder in ipairs(older) do
				if index > MAX_OLDER then
					break
				end
				local row = AcquireOlderRow(OnTick)
				row.preview = self.preview
				FillRow(row, reminder, false)
				row.text:SetAlpha(reminder.state == "done" and 0.4 or 0.75)
				row:SetPoint("TOPLEFT", UI.PAD + 4, y)
				row:SetPoint("RIGHT", -UI.PAD, 0)
				y = y - OLDER_ROW
			end
			if #older > MAX_OLDER then
				local more = AcquireLabel("GameFontDisableSmall")
				more:SetText(string.format("and %d more (/nra remind)", #older - MAX_OLDER))
				more:SetPoint("TOPLEFT", UI.PAD + 24, y)
				y = y - 18
			end
		elseif openOlder > 0 then
			local more = AcquireLabel("GameFontDisableSmall")
			more:SetText(string.format("%d more still open (%s)", openOlder,
				ns:GetOption("remindersTracker") and "in your list on screen" or "/nra remind"))
			more:SetPoint("TOPLEFT", UI.PAD + (single and 0 or 26), y - 2)
			y = y - 20
		end

		local open = 0
		for _, reminder in ipairs(fresh) do
			if reminder.state ~= "done" then
				open = open + 1
			end
		end
		if listOlder then
			open = open + openOlder
		end
		self.done:SetShown(single)
		self.hint:ClearAllPoints()
		self.hint:SetPoint("LEFT", UI.PAD, 0)
		self.hint:SetPoint("RIGHT", single and self.done or self.close, "LEFT", -10, 0)
		self.hint:SetPoint("BOTTOM", 0, UI.PAD + 6)
		if single then
			self.hint:SetText("")
			self.close.text:SetText("Later")
		elseif open == 0 then
			self.hint:SetText("All done!")
			self.close.text:SetText("Close")
		else
			self.hint:SetText(ns:GetOption("remindersTracker") and "Tick what you've done. The rest stay in your list and come back at your next login."
				or "Tick what you've done. The rest come back at your next login.")
			self.close.text:SetText("Later")
		end
		self:SetHeight(-y + 52)
	end

	card:HookScript("OnHide", function(self)
		self.preview = nil
	end)
end

-- Shows the card for `fresh`, the reminders that just came due, with your other due ones as
-- still open (listed at login). While it's up, new ones join the top. preview: made-up ones.
function CardShow(fresh, atLogin, older)
	if not card then
		CreateCard()
	end
	fresh = fresh or {}
	if older then
		card.preview, card.fresh, card.older, card.atLogin = true, fresh, older, atLogin
	else
		if not card:IsShown() or card.preview then
			card.fresh, card.atLogin = {}, atLogin
		end
		card.preview = nil
		card.atLogin = card.atLogin or atLogin
		local listed = {}
		for _, reminder in ipairs(card.fresh) do
			listed[reminder] = true
		end
		for _, reminder in ipairs(fresh) do
			if not listed[reminder] then
				table.insert(card.fresh, reminder)
				listed[reminder] = true
			end
		end
		card.older = {}
		for _, reminder in ipairs(reminders.Due(true)) do
			if not listed[reminder] then
				table.insert(card.older, reminder)
			end
		end
	end
	card:Show()
	card:Raise()
	card:Refresh()
end
reminders.ShowCard = CardShow

------------------------------------------------------------------------------
-- The tracker: what's due, on screen until you tick it
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
		tracker.ticked[row.reminder] = checked and GetTime() or nil
		reminders.SetDone(row.reminderID, checked)
		if checked then
			C_Timer.After(TICKED_STAY + TICKED_FADE, RefreshTracker)
		end
	end
	-- Ticked rows fade out, then the list closes up.
	tracker:SetScript("OnUpdate", function(self)
		local now = GetTime()
		for _, row in ipairs(self.rows) do
			local tickedAt = row:IsShown() and row.reminder and self.ticked[row.reminder]
			row:SetAlpha(tickedAt and math.max(0, 1 - (now - tickedAt - TICKED_STAY) / TICKED_FADE) or 1)
		end
	end)
	for index = 1, TRACKER_MAX_ROWS do
		local row = CreateRow(tracker, TRACKER_ROW, OnTick)
		reminders.AddReorder(row)
		row:SetPoint("TOPLEFT", 8, -30 - (index - 1) * TRACKER_ROW)
		row:SetPoint("RIGHT", -8, 0)
		tracker.rows[index] = row
	end
	tracker.more = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tracker.list = {}
	tracker.ticked = {} -- reminder -> GetTime() it was ticked here: it stays a moment, dimmed, then fades
end

-- The tracker lists your due reminders and to-dos, whether the card is up or not. One you tick
-- in it stays a moment, dimmed (to untick a slip), then fades out; ones done elsewhere go.
function RefreshTracker()
	local due = {}
	for _, reminder in ipairs(ns:IsModuleEnabled(module.key) and reminders.Due() or {}) do
		if reminder.quiet or ns:GetOption("remindersTracker") then
			table.insert(due, reminder)
		end
	end
	local fading = false
	if tracker then
		for reminder, tickedAt in pairs(tracker.ticked) do
			fading = fading or (reminder.state == "done" and GetTime() - tickedAt < TICKED_STAY + TICKED_FADE)
		end
	end
	local wanted = (#due > 0 or fading) and not trackerHidden
	if not wanted then
		if tracker then
			tracker:Hide()
			tracker.list, tracker.ticked = {}, {}
		end
		return
	end
	if not tracker then
		CreateTracker()
	end
	-- In your order, with the ones you ticked here where they were.
	local list = {}
	for _, reminder in ipairs(due) do
		table.insert(list, reminder)
	end
	local now = GetTime()
	for reminder, tickedAt in pairs(tracker.ticked) do
		if reminder.state == "done" and now - tickedAt < TICKED_STAY + TICKED_FADE and reminders.Find(reminder.id) then
			table.insert(list, reminder)
		else
			tracker.ticked[reminder] = nil
		end
	end
	table.sort(list, function(a, b)
		if (a.order or math.huge) ~= (b.order or math.huge) then
			return (a.order or math.huge) < (b.order or math.huge)
		end
		return a.id < b.id
	end)
	tracker.list = list
	local folded = NraKitDB.remindersTrackerFolded == true
	tracker.arrow:SetRotation(folded and 0 or -math.pi / 2)
	tracker.title:SetText(string.format("To do (%d)", #due))
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

reminders.RefreshTracker = function()
	RefreshTracker()
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
		ns:Print("Your to-do list is empty. /nra remind lists what's waiting to come due.")
		return
	end
	trackerHidden = false
	NraKitDB.remindersTrackerFolded = nil
	RefreshTracker()
	if not ns:GetOption("remindersTracker") and #reminders.Due(true) > 0 then
		CardShow({}, true) -- reminders aren't on the list then
	end
end

------------------------------------------------------------------------------
-- /nra remind
------------------------------------------------------------------------------

local function Confirm(reminder, spec)
	local text = reminder.text
	local whose = spec.character and (spec.character .. "'s") or "your"
	if spec.quiet then
		local list = whose .. " to-do list"
		if spec.kind == "time" then
			ns:Print(string.format("On %s in %s (at %s): %s", list, reminders.FormatDuration(spec.duration), date("%H:%M", reminder.at), text))
		elseif spec.kind == "zone" then
			ns:Print(string.format("On %s when %s %s: %s", list, spec.character and "they enter" or "you enter", spec.zone, text))
		elseif spec.kind == "level" then
			ns:Print(string.format("On %s at level %d: %s", list, spec.level, text))
		elseif spec.character then
			ns:Print(string.format("On %s at their next login: %s", list, text))
		else
			ns:Print(string.format("On your to-do list: %s", text))
		end
	elseif spec.kind == "time" then
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

-- Adds a checked spec (reminders.Validate) and says so in chat.
function reminders.Commit(spec)
	local reminder = reminders.Add(spec, spec.character)
	if spec.kind == "zone" and not spec.character then
		zonesBefore = CurrentZones() -- where you are now doesn't count as entering
	end
	if spec.quiet and spec.kind == "login" and not spec.character then
		MakeDue(reminder, reminders.List()) -- a plain to-do: on the list now
		Changed()
	end
	Confirm(reminder, spec)
	return reminder
end

-- Every zone name the map knows (for picking one in the form), sorted.
function reminders.ZoneNames()
	local names, seen = {}, {}
	local mapID = C_Map.GetBestMapForUnit("player")
	local top = mapID
	while mapID do
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			break
		end
		top = mapID
		mapID = info.parentMapID ~= 0 and info.parentMapID or nil
	end
	for _, info in ipairs(top and C_Map.GetMapChildrenInfo(top, Enum.UIMapType.Zone, true) or {}) do
		if info.name and info.name ~= "" and not seen[info.name] then
			seen[info.name] = true
			table.insert(names, info.name)
		end
	end
	table.sort(names)
	return names
end

-- The zone and subzone you're in now (either can be nil).
function reminders.Here()
	local zone = GetRealZoneText and GetRealZoneText()
	local subzone = GetSubZoneText and GetSubZoneText()
	zone = zone ~= "" and zone or nil
	subzone = subzone ~= "" and subzone ~= zone and subzone or nil
	return zone, subzone
end

local function OnSlashCommand(rest)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Reminders & to-dos first (/nra).")
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
	return reminders.Commit(spec)
end
reminders.OnSlashCommand = OnSlashCommand

-- /nra todo: the same words, as a to-do (on the list, no card). Alone, shows the list.
local function OnTodoCommand(rest)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Reminders & to-dos first (/nra).")
		return
	end
	if rest == "" or rest:lower() == "show" then
		reminders.ShowTracker()
		return
	end
	local spec, problem = reminders.Parse(rest)
	if not spec then
		ns:Print((problem:gsub("/nra remind", "/nra todo")))
		return
	end
	spec.quiet = true
	return reminders.Commit(spec)
end
reminders.OnTodoCommand = OnTodoCommand

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
_G["BINDING_NAME_NRAKIT_SHOW_REMINDERS"] = "Show the to-do list"
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
		return string.format("%d open on your to-do list", count)
	end,
	open = reminders.ShowTracker,
})

ns:RegisterMenuAction({
	module = module.key,
	label = function()
		local count = #reminders.Due()
		return count > 0 and string.format("To-do list |cffff9933(%d)|r", count) or nil
	end,
	onClick = reminders.ShowTracker,
})

ns:RegisterPreview("reminder", "Reminders: the card when one comes due", function()
	local now = time()
	CardShow({
		{ id = -1, text = "Hand in the turtle quests at Auberdine", kind = "zone", zone = "Darkshore", state = "due", dueAt = now },
	}, false, {
		{ id = -2, text = "Mail the bags to your main", kind = "login", from = "Bankalt", state = "due", dueAt = now },
	})
end)

ns:RegisterPreview("reminders", "Reminders: the card at login, with what came due and what's still open", function()
	local now = time()
	CardShow({
		{ id = -1, text = "Go to Darkshore and hand in the turtle quests", kind = "login", state = "due", dueAt = now },
		{ id = -2, text = "Check the auction house for |cff1eff00[Coarse Thread]|r", kind = "time", at = now - 3600, created = now - 7200, away = true, state = "due", dueAt = now },
	}, true, {
		{ id = -3, text = "Mail the bags to your main", kind = "login", from = "Bankalt", state = "due", dueAt = now },
		{ id = -4, text = "Train first aid", kind = "level", level = 20, state = "due", dueAt = now },
	})
end)

function module:OnInitialize()
	local help = {
		summary = "Reminders: notes to yourself that pop up at your next login, after a time, in a zone or at a level",
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
	local todoHelp = {
		summary = "To-dos: like reminders, but they go straight on the list on screen (no card, no sound)",
		usage = {
			"/nra todo <text> - on your to-do list now",
			"/nra todo - show the list (unfold it, or bring it back if you hid it)",
			"/nra todo in <zone>: / at <level>: / 30m / @<character>: <text> - on the list when that comes (like /nra remind)",
			"/nra todos - the same as /nra todo",
		},
	}
	ns:RegisterSlashCommand("todo", OnTodoCommand, todoHelp)
	ns:RegisterSlashCommand("todos", OnTodoCommand, todoHelp)
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
