local _, ns = ...

-- Player notes: a label and a dated log of notes per player. The label shows in unit
-- tooltips; the right-click menu on a player (unit frames, chat names, group, guild
-- and friends lists) opens the notes or sets the label.
--
-- Every label has a tone, and the tone decides what happens: Hostile and Caution
-- players trigger warnings when they join your group, invite you, whisper you or open
-- a trade, and Unit Scanner alerts for Hostile ones nearby (it asks ScanEntry). The
-- five built-in labels are only a starting set; they can be renamed, recolored or
-- deleted, and more added (PlayerNotesWindow.lua has the editor).
--
-- Forever has no realms: players are "Firstname Surname" (UnitName returns the two
-- parts). Names match case-insensitively, and "Firstname-Surname" (realm style, as
-- some events may give it) matches too. The GUID is kept once seen, so a player
-- still matches after a rename. Names and GUIDs can be secret values (combat,
-- instances); those players are skipped, the notes themselves are never touched.
--
-- Data (account-wide): NraKitDB.playerNotesData = {
--   players = { [key] = { name, guid, class, label, notes = { { text, time, zone, by } }, created, updated } },
--   labels = { { id, name, tone, color = { r, g, b }? }, ... }, nextLabel,
-- }

local module = {
	key = "playerNotes",
	section = "Utilities",
	name = "Player notes",
	description = "Keep notes on players: a label (Kill on sight, Avoid, Friend, or your own) and a dated log of what happened. Shown in their tooltip; right-click a player (portrait, party frame, chat name) for Player note. Warns you when a player you've marked Avoid or Kill on sight joins your group, invites, whispers or trades you. /nra note opens your notes.",
	default = false,
	options = {
		{
			key = "playerNotesTooltip",
			header = "Showing notes",
			name = "Show in tooltips",
			description = "Add the player's label and latest note to their tooltip.",
			default = true,
		},
		{
			key = "playerNotesWarnGroup",
			header = "Warnings",
			name = "When they join your group",
			description = "Warn when a player with a Caution or Hostile label (Avoid, Kill on sight, ...) is in a group you join, or joins yours.",
			default = true,
		},
		{
			key = "playerNotesWarnInvite",
			name = "When they invite you",
			description = "Warn when a player with a Caution or Hostile label invites you to a group.",
			default = true,
		},
		{
			key = "playerNotesWarnWhisper",
			name = "When they whisper you",
			description = "Warn when a player with a Caution or Hostile label whispers you (at most every few minutes per player).",
			default = true,
		},
		{
			key = "playerNotesWarnTrade",
			name = "When they open a trade",
			description = "Warn when a player with a Caution or Hostile label opens a trade with you.",
			default = true,
		},
		{
			key = "playerNotesWarnScreen",
			name = "Show on screen",
			description = "Show warnings in the middle of the screen, like a raid warning, as well as in chat.",
			default = true,
		},
		{
			key = "playerNotesWarnSound",
			name = "Play a sound",
			description = "Play a sound with each warning.",
			default = true,
		},
		{
			key = "playerNotesWarnSoundChoice",
			parent = "playerNotesWarnSound",
			type = "sound",
			name = "Sound",
			description = "Which sound to play with a warning.",
			default = "kit:UI_RAID_BOSS_WHISPER_WARNING",
		},
		{
			key = "playerNotesScanHostile",
			header = "Unit Scanner",
			requires = "unitScanner",
			name = "Alert when Hostile players are nearby",
			description = "Unit Scanner alerts you (with its sound, marker and target button) when a player with a Hostile label (Kill on sight, ...) shows up: nameplates, mouseover, targets. Needs Unit Scanner turned on. Players of your own faction are only seen on mouseover and as targets unless friendly nameplates are on.",
			default = true,
		},
	},
}

local notes = {}
ns.playerNotes = notes

-- Tones, in the order labels are listed. warn: group/whisper/... warnings; scan: Unit Scanner.
notes.TONES = {
	{ key = "hostile", name = "Hostile", color = { 1, 0.25, 0.2 }, warn = true, scan = true },
	{ key = "caution", name = "Caution", color = { 1, 0.55, 0.15 }, warn = true },
	{ key = "neutral", name = "Neutral", color = { 0.7, 0.7, 0.7 } },
	{ key = "friendly", name = "Friendly", color = { 0.3, 0.85, 0.35 } },
}
local TONE_BY_KEY = {}
for index, tone in ipairs(notes.TONES) do
	tone.order = index
	TONE_BY_KEY[tone.key] = tone
end

local DEFAULT_LABELS = {
	{ id = "kos", name = "Kill on sight", tone = "hostile" },
	{ id = "avoid", name = "Avoid", tone = "caution" },
	{ id = "neutral", name = "Neutral", tone = "neutral" },
	{ id = "good", name = "Good", tone = "friendly" },
	{ id = "friend", name = "Friend", tone = "friendly", color = { 0.35, 0.7, 1 } },
}

local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t "
local WARN_COOLDOWN = 300
local SNIPPET_LENGTH = 60

-- Unit popup menus that are about a player.
local MENU_TAGS = {
	"PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "FRIEND_OFFLINE", "TARGET", "FOCUS",
	"CHAT_ROSTER", "GUILD", "GUILD_OFFLINE", "COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER",
	"RECENT_ALLY", "RECENT_ALLY_OFFLINE", "WORLD_STATE_SCORE", "PVP_SCOREBOARD",
}

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local hasScanTargets -- cached; nil = work it out again

local function Changed()
	hasScanTargets = nil
	if ns.UnitScannerTargetsChanged then
		ns:UnitScannerTargetsChanged()
	end
	if notes.onChanged then
		notes.onChanged()
	end
end

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

-- "Bob-Stone" or " bob  stone " -> "Bob Stone" (display), "bob stone" (key).
function notes.Display(name)
	return (strtrim(name):gsub("%-", " "):gsub("%s+", " "))
end

function notes.Key(name)
	return notes.Display(name):lower()
end

-- A unit's full name ("Firstname Surname"), or nil if it's not readable.
function notes.UnitFullName(unit)
	local name, surname = UnitName(unit)
	if not name or IsSecret(name) or name == "" then
		return nil
	end
	if surname and not IsSecret(surname) and surname ~= "" then
		return name .. " " .. surname
	end
	return name
end

-- What we learn about a player from a unit: { guid, class }.
local function UnitInfo(unit)
	local guid = UnitGUID(unit)
	local _, class = UnitClass(unit)
	return {
		guid = guid and not IsSecret(guid) and guid or nil,
		class = class and not IsSecret(class) and class or nil,
	}
end

local function IsMe(name)
	local me = notes.UnitFullName("player")
	return me and notes.Key(me) == notes.Key(name)
end

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function CopyLabels()
	local labels = {}
	for index, label in ipairs(DEFAULT_LABELS) do
		labels[index] = { id = label.id, name = label.name, tone = label.tone, color = label.color and { unpack(label.color) } }
	end
	return labels
end

function notes.GetData()
	local data = NraKitDB.playerNotesData
	if not data then
		data = { players = {}, labels = CopyLabels(), nextLabel = 1 }
		NraKitDB.playerNotesData = data
	end
	return data
end

function notes.GetLabels()
	return notes.GetData().labels
end

function notes.GetLabel(id)
	for _, label in ipairs(notes.GetLabels()) do
		if label.id == id then
			return label
		end
	end
	return nil
end

function notes.Tone(label)
	return label and TONE_BY_KEY[label.tone] or TONE_BY_KEY.neutral
end

function notes.LabelColor(label)
	local color = label and label.color or notes.Tone(label).color
	return color[1], color[2], color[3]
end

-- The label as colored text, with a skull for Hostile ones.
function notes.LabelText(label)
	if not label then
		return ""
	end
	local r, g, b = notes.LabelColor(label)
	local icon = notes.Tone(label).scan and SKULL or ""
	return string.format("%s|cff%02x%02x%02x%s|r", icon, r * 255, g * 255, b * 255, label.name)
end

-- Labels sorted by tone (Hostile first), keeping their order within a tone.
function notes.SortedLabels()
	local list = {}
	for index, label in ipairs(notes.GetLabels()) do
		list[index] = label
	end
	local position = {}
	for index, label in ipairs(list) do
		position[label] = index
	end
	table.sort(list, function(a, b)
		local toneA, toneB = notes.Tone(a).order, notes.Tone(b).order
		if toneA ~= toneB then
			return toneA < toneB
		end
		return position[a] < position[b]
	end)
	return list
end

-- The first label of a tone (where players go when their label is deleted).
local function ToneDefault(toneKey)
	for _, label in ipairs(notes.SortedLabels()) do
		if label.tone == toneKey then
			return label
		end
	end
	return nil
end

local function DefaultLabel()
	return ToneDefault("neutral") or notes.SortedLabels()[1]
end

-- The player's record (and its key) by name and/or GUID.
function notes.Find(name, guid)
	local players = notes.GetData().players
	if name and not IsSecret(name) then
		local key = notes.Key(name)
		if players[key] then
			return players[key], key
		end
	end
	if guid and not IsSecret(guid) then
		for key, record in pairs(players) do
			if record.guid == guid then
				return record, key
			end
		end
	end
	return nil
end

function notes.FindUnit(unit)
	if not UnitExists(unit) then
		return nil
	end
	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) or not isPlayer then
		return nil
	end
	local name = notes.UnitFullName(unit)
	local guid = UnitGUID(unit)
	return notes.Find(name, not IsSecret(guid) and guid or nil)
end

-- Fills in what we learned (GUID, class) and follows a rename: a record found by
-- GUID under another name moves to the new name.
local function Learn(record, key, name, info)
	if info then
		record.guid = info.guid or record.guid
		record.class = info.class or record.class
	end
	if name and notes.Key(name) ~= key then
		local players = notes.GetData().players
		players[key] = nil
		key = notes.Key(name)
		players[key] = record
		record.name = notes.Display(name)
	end
	return record, key
end

-- The record for a player, created if new. info = { guid, class } (optional).
function notes.Ensure(name, info)
	local record, key = notes.Find(name, info and info.guid)
	if record then
		return Learn(record, key, name, info)
	end
	key = notes.Key(name)
	record = {
		name = notes.Display(name),
		label = DefaultLabel().id,
		notes = {},
		created = time(),
		updated = time(),
	}
	notes.GetData().players[key] = record
	return Learn(record, key, nil, info)
end

-- Adds a player with the default label (or keeps an existing one).
function notes.AddPlayer(name, info)
	local record, key = notes.Ensure(name, info)
	Changed()
	return record, key
end

function notes.SetLabel(name, labelID, info)
	local record = notes.Ensure(name, info)
	record.label = labelID
	record.updated = time()
	Changed()
	return record
end

local function MyName()
	return notes.UnitFullName("player") or UnitName("player")
end

function notes.AddNote(name, text, info)
	text = strtrim(text or "")
	if text == "" then
		return nil
	end
	local record = notes.Ensure(name, info)
	local zone = GetRealZoneText and GetRealZoneText()
	table.insert(record.notes, {
		text = text,
		time = time(),
		zone = zone ~= "" and zone or nil,
		by = MyName(),
	})
	record.updated = time()
	Changed()
	return record
end

function notes.DeleteNote(key, index)
	local record = notes.GetData().players[key]
	if record and record.notes[index] then
		table.remove(record.notes, index)
		record.updated = time()
		Changed()
	end
end

-- The last deleted player, for undo (this session only): { key, record }.
local lastDeleted

function notes.DeletePlayer(key)
	local record = notes.GetData().players[key]
	if not record then
		return nil
	end
	notes.GetData().players[key] = nil
	lastDeleted = { key = key, record = record }
	Changed()
	return record
end

-- Brings back the last deleted player. If they were added again since, their old
-- notes are merged in (oldest first) and the new label stays. Returns the record.
function notes.RestorePlayer()
	if not lastDeleted then
		return nil
	end
	local players = notes.GetData().players
	local old, current = lastDeleted.record, players[lastDeleted.key]
	lastDeleted = nil
	if current then
		for index, note in ipairs(old.notes) do
			table.insert(current.notes, index, note)
		end
		table.sort(current.notes, function(a, b)
			return (a.time or 0) < (b.time or 0)
		end)
		current.created = math.min(current.created or old.created, old.created or current.created)
	else
		players[notes.Key(old.name)] = old
		current = old
	end
	Changed()
	return current
end

function notes.CountText(record)
	local count = #record.notes
	return count == 1 and "1 note" or (count .. " notes")
end

-- All players: { key, record } sorted by last change, newest first.
function notes.All()
	local list = {}
	for key, record in pairs(notes.GetData().players) do
		table.insert(list, { key = key, record = record })
	end
	table.sort(list, function(a, b)
		if (a.record.updated or 0) ~= (b.record.updated or 0) then
			return (a.record.updated or 0) > (b.record.updated or 0)
		end
		return a.key < b.key
	end)
	return list
end

function notes.LatestNote(record)
	return record and record.notes[#record.notes]
end

function notes.Snippet(text, length)
	length = length or SNIPPET_LENGTH
	if #text > length then
		return text:sub(1, length - 3) .. "..."
	end
	return text
end

------------------------------------------------------------------------------
-- Labels
------------------------------------------------------------------------------

function notes.AddLabel(name, toneKey)
	local data = notes.GetData()
	local id = "custom" .. data.nextLabel
	data.nextLabel = data.nextLabel + 1
	local label = { id = id, name = name, tone = toneKey or "neutral" }
	table.insert(data.labels, label)
	Changed()
	return label
end

function notes.RenameLabel(id, name)
	local label = notes.GetLabel(id)
	name = strtrim(name or "")
	if label and name ~= "" then
		label.name = name
		Changed()
	end
end

function notes.SetLabelTone(id, toneKey)
	local label = notes.GetLabel(id)
	if label and TONE_BY_KEY[toneKey] then
		label.tone = toneKey
		Changed()
	end
end

-- color = { r, g, b }, or nil for the tone's color.
function notes.SetLabelColor(id, color)
	local label = notes.GetLabel(id)
	if label then
		label.color = color
		Changed()
	end
end

-- The last label can't go. Its players move to the first label of the same tone,
-- or to the default label if it was the last of its tone.
function notes.CanDeleteLabel(id)
	return #notes.GetLabels() > 1 and notes.GetLabel(id) ~= nil
end

function notes.DeleteLabel(id)
	if not notes.CanDeleteLabel(id) then
		return
	end
	local labels = notes.GetLabels()
	local deleted
	for index, label in ipairs(labels) do
		if label.id == id then
			deleted = table.remove(labels, index)
			break
		end
	end
	local replacement = ToneDefault(deleted.tone) or DefaultLabel()
	for _, record in pairs(notes.GetData().players) do
		if record.label == id then
			record.label = replacement.id
		end
	end
	Changed()
end

-- A label by what you'd type: its name without spaces ("killonsight"), its initials
-- ("kos"), or its ID.
function notes.LabelByWord(word)
	word = word and word:lower()
	if not word or word == "" then
		return nil
	end
	for _, label in ipairs(notes.GetLabels()) do
		local name = label.name:lower()
		local initials = name:gsub("(%w)%w*", "%1"):gsub("%s", "")
		if word == name:gsub("%s", "") or word == label.id or (#initials > 1 and word == initials) then
			return label
		end
	end
	return nil
end

function notes.RecordLabel(record)
	return record and (notes.GetLabel(record.label) or DefaultLabel())
end

------------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------------

local function OnUnitTooltip(tooltip)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("playerNotesTooltip") then
		return
	end
	if tooltip.IsForbidden and tooltip:IsForbidden() then
		return
	end
	local _, unit = tooltip:GetUnit()
	if not unit or IsSecret(unit) then
		return
	end
	local record = notes.FindUnit(unit)
	if not record then
		return
	end
	local label = notes.RecordLabel(record)
	local count = #record.notes
	local line = notes.LabelText(label)
	if count > 1 then
		line = line .. string.format("  |cff808080%d notes|r", count)
	end
	tooltip:AddLine(line)
	local latest = notes.LatestNote(record)
	if latest then
		tooltip:AddLine("\"" .. notes.Snippet(latest.text) .. "\"", 0.9, 0.9, 0.9)
	end
	tooltip:Show()
end

------------------------------------------------------------------------------
-- Right-click menu
------------------------------------------------------------------------------

-- The player a unit menu is about: full name and { guid, class }, or nil.
local function MenuPlayer(contextData)
	if not contextData then
		return nil
	end
	local unit = contextData.unit
	if unit and UnitExists(unit) then
		local isPlayer = UnitIsPlayer(unit)
		if IsSecret(isPlayer) or not isPlayer then
			return nil
		end
		local name = notes.UnitFullName(unit)
		if not name or IsSecret(name) or IsMe(name) then
			return nil
		end
		return name, UnitInfo(unit)
	end
	local name, surname = contextData.name, contextData.surname
	if not name or IsSecret(name) or name == "" then
		return nil
	end
	if surname and not IsSecret(surname) and surname ~= "" and not name:find("[%s%-]") then
		name = name .. " " .. surname
	end
	if IsMe(name) then
		return nil
	end
	local guid = contextData.guid
	return name, { guid = guid and not IsSecret(guid) and guid or nil }
end

local function OnUnitMenu(_, root, contextData)
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	local name, info = MenuPlayer(contextData)
	if not name then
		return
	end
	root:CreateDivider()
	local record = notes.Find(name, info.guid)
	root:CreateButton(record and "Player note..." or "Add player note...", function()
		ns:OpenPlayerNotes(name, info)
	end)
	local labelMenu = root:CreateButton("Player label")
	for _, label in ipairs(notes.SortedLabels()) do
		labelMenu:CreateRadio(notes.LabelText(label), function()
			local current = notes.Find(name, info.guid)
			return current ~= nil and current.label == label.id
		end, function()
			notes.SetLabel(name, label.id, info)
		end)
	end
end

------------------------------------------------------------------------------
-- Warnings
------------------------------------------------------------------------------

local REASONS = {
	group = { option = "playerNotesWarnGroup", text = "is in your group" },
	invite = { option = "playerNotesWarnInvite", text = "invited you to a group" },
	whisper = { option = "playerNotesWarnWhisper", text = "whispered you" },
	trade = { option = "playerNotesWarnTrade", text = "wants to trade" },
}

local lastWarn = {} -- key .. reason -> time()

-- Warns if the player has a Caution or Hostile label. Returns true if it did.
function notes.Warn(name, guid, reason)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption(REASONS[reason].option) then
		return false
	end
	local record, key = notes.Find(name, guid)
	local label = notes.RecordLabel(record)
	if not record or not notes.Tone(label).warn then
		return false
	end
	local now = time()
	local stamp = key .. ":" .. reason
	if lastWarn[stamp] and now - lastWarn[stamp] < WARN_COOLDOWN then
		return false
	end
	lastWarn[stamp] = now

	local r, g, b = notes.LabelColor(label)
	local latest = notes.LatestNote(record)
	local message = string.format("%s (%s) %s", record.name, notes.LabelText(label), REASONS[reason].text)
	if latest then
		message = message .. ": \"" .. notes.Snippet(latest.text) .. "\""
	end
	ns:Print("|cffff8040Heads up:|r " .. message)
	if ns:GetOption("playerNotesWarnScreen") and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, string.format("%s - %s", record.name, label.name),
			{ r = r, g = g, b = b })
	end
	if ns:GetOption("playerNotesWarnSound") then
		ns.sounds.PlayOption("playerNotesWarnSoundChoice", "kit:UI_RAID_BOSS_WHISPER_WARNING")
	end
	return true
end

-- Group members we've already seen (key -> true), so only newcomers warn.
local roster = {}

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			table.insert(units, "raid" .. index)
		end
	elseif IsInGroup() then
		for index = 1, GetNumSubgroupMembers() do
			table.insert(units, "party" .. index)
		end
	end
	return units
end

-- quiet: just remember who's there (after a reload or zoning).
local function CheckRoster(quiet)
	local seen = {}
	for _, unit in ipairs(GroupUnits()) do
		local name = notes.UnitFullName(unit)
		if name and not IsMe(name) then
			local key = notes.Key(name)
			seen[key] = true
			if not roster[key] and not quiet then
				local guid = UnitGUID(unit)
				notes.Warn(name, not IsSecret(guid) and guid or nil, "group")
			end
		end
	end
	roster = seen
end

------------------------------------------------------------------------------
-- Unit Scanner
------------------------------------------------------------------------------

local scanEntries = {} -- key -> entry, kept so the scanner's alert cooldown works per player

local function ScanEnabled()
	return ns:IsModuleEnabled(module.key) and ns:GetOption("playerNotesScanHostile")
end

-- Whether any player has a Hostile label (and scanning for them is on).
function notes.HasScanTargets()
	if not ScanEnabled() then
		return false
	end
	if hasScanTargets == nil then
		hasScanTargets = false
		for _, record in pairs(notes.GetData().players) do
			if notes.Tone(notes.RecordLabel(record)).scan then
				hasScanTargets = true
				break
			end
		end
	end
	return hasScanTargets
end

-- A Unit Scanner entry for a Hostile player, or nil: { name, label, noted = true }.
function notes.ScanEntry(name, guid)
	if not ScanEnabled() then
		return nil
	end
	local record, key = notes.Find(name, guid)
	local label = notes.RecordLabel(record)
	if not record or not notes.Tone(label).scan then
		return nil
	end
	local entry = scanEntries[key] or { noted = true }
	scanEntries[key] = entry
	entry.name = record.name
	entry.label = label.name
	return entry
end

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

local HELP = {
	summary = "Player notes: label players and keep notes on them",
	usage = {
		"/nra note - your target's notes, or the notebook",
		"/nra note <note> - add a note to your target (a player)",
		"/nra note <label> [note] - set your target's label (kos, avoid, neutral, good, friend, or yours), and add a note",
		"/nra note <First Last> [label] [note] - the same for anyone by name (no note: opens their notes)",
		"/nra note <first name> [label [note]] - someone you already have notes on (e.g. /nra note bob kos)",
		"/nra note !remove [First Last] - remove your target (or that player) from your notes; also !rm, !forget",
		"/nra note !undo - bring back the player you last removed",
		"/nra note !list - list the players you have notes on",
	},
}

function notes.TargetPlayer()
	if not UnitExists("target") then
		return nil
	end
	local isPlayer = UnitIsPlayer("target")
	if IsSecret(isPlayer) or not isPlayer then
		return nil
	end
	local name = notes.UnitFullName("target")
	if not name or IsMe(name) then
		return nil
	end
	return name, UnitInfo("target")
end

-- A noted player whose name starts with this text, if only one does.
local function FindByPrefix(text)
	local prefix, found = notes.Key(text), nil
	for key, record in pairs(notes.GetData().players) do
		if key:sub(1, #prefix) == prefix then
			if found then
				return nil
			end
			found = record
		end
	end
	return found
end

-- Sets the label and/or adds the note, and says what it did.
local function Apply(name, info, label, text)
	if not label and text == "" then
		ns:OpenPlayerNotes(name, info)
		return
	end
	if label then
		notes.SetLabel(name, label.id, info)
	end
	local record = text ~= "" and notes.AddNote(name, text, info) or notes.Find(name)
	local parts = {}
	if label then
		table.insert(parts, "label " .. notes.LabelText(label))
	end
	if text ~= "" then
		table.insert(parts, "note added")
	end
	ns:Print(string.format("%s: %s.", record.name, table.concat(parts, ", ")))
end

local function List()
	local players = notes.All()
	if #players == 0 then
		ns:Print("No player notes yet. Right-click a player and pick Player note, or /nra note <First Last> <label> <note>.")
		return
	end
	ns:Print(string.format("%d players:", #players))
	for _, entry in ipairs(players) do
		local latest = notes.LatestNote(entry.record)
		print(string.format("  %s - %s%s", entry.record.name, notes.LabelText(notes.RecordLabel(entry.record)),
			latest and (": " .. notes.Snippet(latest.text, 40)) or ""))
	end
end

-- "!" commands, so they never clash with note text: !remove, !undo, !list.
local REMOVE_WORDS = { remove = true, rm = true, del = true, delete = true, forget = true, clear = true }

local function RemoveCommand(argument)
	local record, key
	if argument == "" then
		local name, info = notes.TargetPlayer()
		if not name then
			ns:Print("Target a player, or name them: |cffffd100/nra note !remove <First Last>|r.")
			return
		end
		record, key = notes.Find(name, info.guid)
		if not record then
			ns:Print(name .. " isn't in your notes.")
			return
		end
	else
		record, key = notes.Find(argument)
		if not record and not argument:find("%s") then
			record = FindByPrefix(argument)
			key = record and notes.Key(record.name)
		end
		if not record then
			ns:Print("No notes on " .. argument .. ". See /nra note list.")
			return
		end
	end
	notes.DeletePlayer(key)
	ns:Print(string.format("Removed %s (%s). |cffffd100/nra note !undo|r brings them back.", record.name, notes.CountText(record)))
end

local function RunCommand(command, argument)
	if REMOVE_WORDS[command] then
		RemoveCommand(argument)
	elseif command == "undo" then
		local record = notes.RestorePlayer()
		ns:Print(record and ("Restored " .. record.name .. " (" .. notes.CountText(record) .. ").") or "Nothing to undo.")
	elseif command == "list" then
		List()
	else
		ns:Print("Unknown: !" .. command .. ". Try !remove, !undo or !list (/nra note help).")
	end
end

local function OnSlashCommand(input)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Player notes is turned off. Turn it on in /nra.")
		return
	end
	input = strtrim(input or "")
	if input == "" then
		local name, info = notes.TargetPlayer()
		ns:OpenPlayerNotes(name, info)
		return
	end
	local command, argument = input:match("^!(%S*)%s*(.-)$")
	if command then
		RunCommand(command:lower(), argument)
		return
	end
	if input:lower() == "list" and not notes.TargetPlayer() then
		List()
		return
	end
	local words = {}
	for word in input:gmatch("%S+") do
		table.insert(words, word)
	end
	local targetName, targetInfo = notes.TargetPlayer()
	local function RestFrom(index)
		local label = notes.LabelByWord(words[index])
		return label, table.concat(words, " ", label and index + 1 or index)
	end

	-- A player named in full: someone you have notes on, or your target by name.
	local twoWords = words[2] and (words[1] .. " " .. words[2])
	local named = twoWords and (notes.Find(twoWords)
		or (targetName and notes.Key(targetName) == notes.Key(twoWords)))
	if named then
		local isTarget = targetName and notes.Key(targetName) == notes.Key(twoWords)
		Apply(isTarget and targetName or twoWords, isTarget and targetInfo or nil, RestFrom(3))
		return
	end

	-- Otherwise, with a player targeted, it's all about them: "[label] [note]".
	if targetName then
		Apply(targetName, targetInfo, RestFrom(1))
		return
	end

	-- No target: a noted player by first name, followed by a label or nothing ("bob kos"
	-- -> Bob Stone; "bob smith kos" is a new Bob), or a new player's "First Last".
	local known = (#words == 1 or notes.LabelByWord(words[2])) and FindByPrefix(words[1])
	if known then
		Apply(known.name, nil, RestFrom(2))
	elseif notes.LabelByWord(words[1]) or #words == 1 then
		ns:Print(string.format("Who is that for? Target a player, or name them: |cffffd100/nra note <First Last> %s|r. (/nra note help)", input))
	else
		Apply(twoWords, nil, RestFrom(3))
	end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "GROUP_ROSTER_UPDATE" then
		CheckRoster(false)
	elseif event == "PLAYER_ENTERING_WORLD" then
		CheckRoster(true)
	elseif event == "PARTY_INVITE_REQUEST" then
		local name = ...
		local guid = select(7, ...)
		if name and not IsSecret(name) then
			notes.Warn(name, guid and not IsSecret(guid) and guid or nil, "invite")
		end
	elseif event == "CHAT_MSG_WHISPER" then
		local sender = select(2, ...)
		local guid = select(12, ...)
		if sender and not IsSecret(sender) then
			notes.Warn(sender, guid and not IsSecret(guid) and guid or nil, "whisper")
		end
	elseif event == "TRADE_SHOW" then
		local name = notes.UnitFullName("npc")
		if name then
			local guid = UnitGUID("npc")
			notes.Warn(name, not IsSecret(guid) and guid or nil, "trade")
		end
	end
end)

local EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PARTY_INVITE_REQUEST", "CHAT_MSG_WHISPER", "TRADE_SHOW" }

function module:OnInitialize()
	ns:RegisterSlashCommand("note", OnSlashCommand, HELP)
	ns:RegisterSlashCommand("notes", OnSlashCommand, HELP)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(MENU_TAGS) do
			Menu.ModifyMenu("MENU_UNIT_" .. tag, OnUnitMenu)
		end
	end
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		CheckRoster(true)
	end
	if ns.UnitScannerTargetsChanged then
		ns:UnitScannerTargetsChanged()
	end
end

function module:OnOptionChanged(key)
	if key == "playerNotesScanHostile" and ns.UnitScannerTargetsChanged then
		ns:UnitScannerTargetsChanged()
	end
end

-- Key binding (Bindings.xml).
_G["BINDING_NAME_NRAKIT_PLAYER_NOTES"] = "Open player notes (your target's, if it's a player)"
function NraKit_TogglePlayerNotes()
	if ns:IsModuleEnabled(module.key) then
		local name, info = notes.TargetPlayer()
		ns:OpenPlayerNotes(name, info)
	end
end

ns:RegisterModule(module)
