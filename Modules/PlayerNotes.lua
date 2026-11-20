local _, ns = ...

-- Player notes: per player a label, any number of tags and a dated log of notes. The
-- label and tags show in unit tooltips; the right-click menu on a player (unit frames,
-- chat names, group, guild and friends lists) opens the notes or sets the label.
--
-- The label is one of four fixed ones (called "tone" in the code), and it decides what
-- happens: Kill on sight and Avoid players trigger warnings when they join your group,
-- invite you, whisper you or open a trade, and Unit Scanner alerts for Kill on sight
-- ones nearby (it asks ScanEntry). Tags are your own words ("Ninjalooter", "Good tank")
-- for grouping players; the window lists players by tag.
--
-- Forever has no realms: players are "Firstname Surname" (UnitName returns the two
-- parts). Names match case-insensitively, and "Firstname-Surname" (realm style, as
-- some events may give it) matches too. The GUID is kept once seen, so a player
-- still matches after a rename. Names and GUIDs can be secret values (combat,
-- instances); those players are skipped, the notes themselves are never touched.
--
-- Notes can be linked in chat and added from someone else's link (PlayerNotesShare.lua).
--
-- Data (account-wide): NraKitDB.playerNotesData = {
--   players = { [key] = { name, guid, class, tone, tags = { "Tag", ... },
--     notes = { { text, time, zone, by, sharedBy? } }, created, updated } },
--   tags = { "Tag", ... }, -- every tag, including ones nobody has (yet)
--   collapsed = { [tag key] = true }, -- tag sections closed in the window's list
-- }
-- Before tags, players had one of a list of editable labels (labels, nextLabel and
-- record.label); GetData turns those into a tone plus, for your own labels, a tag.

local module = {
	key = "playerNotes",
	section = "Utilities",
	name = "Player notes",
	description = "Keep notes on players: a label (Kill on sight, Avoid, Neutral or Liked), tags of your own to group them (Ninjalooter, Good tank, ...) and a dated log of what happened. Shown in their tooltip; right-click a player (portrait, party frame, chat name) for Player note to label them or write a note. Warns you when a player you've marked Avoid or Kill on sight joins your group, invites, whispers or trades you. /nra note opens your notes.",
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
			description = "Warn when a player labelled Avoid or Kill on sight is in a group you join, or joins yours.",
			default = true,
		},
		{
			key = "playerNotesWarnInvite",
			name = "When they invite you",
			description = "Warn when a player labelled Avoid or Kill on sight invites you to a group.",
			default = true,
		},
		{
			key = "playerNotesWarnWhisper",
			name = "When they whisper you",
			description = "Warn when a player labelled Avoid or Kill on sight whispers you (at most every few minutes per player).",
			default = true,
		},
		{
			key = "playerNotesWarnTrade",
			name = "When they open a trade",
			description = "Warn when a player labelled Avoid or Kill on sight opens a trade with you.",
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
			key = "playerNotesShareLinks",
			header = "Sharing",
			name = "Note links in chat",
			description = "Show [NraKit note: Name] in chat as a link: click it to see that player's label, tags and notes and add them to yours. Share your own by shift-clicking a player in your notes.",
			default = true,
		},
		{
			key = "playerNotesScanHostile",
			header = "Unit Scanner",
			requires = "unitScanner",
			name = "Alert when Hostile players are nearby",
			description = "Unit Scanner alerts you (with its sound, marker and target button) when a player labelled Kill on sight shows up: nameplates, mouseover, targets. Needs Unit Scanner turned on. Players of your own faction are only seen on mouseover and as targets unless friendly nameplates are on.",
			default = true,
		},
	},
}

local notes = {}
ns.playerNotes = notes

-- The four labels ("tones"), in the order they're listed. warn: group/whisper/... warnings;
-- scan: Unit Scanner. words: what you can type for them in /nra note.
notes.TONES = {
	{ key = "hostile", name = "Kill on sight", color = { 1, 0.25, 0.2 }, warn = true, scan = true,
		words = { "kos", "killonsight", "hostile" } },
	{ key = "caution", name = "Avoid", color = { 1, 0.55, 0.15 }, warn = true, words = { "avoid", "caution" } },
	{ key = "neutral", name = "Neutral", color = { 0.7, 0.7, 0.7 }, words = { "neutral" } },
	{ key = "friendly", name = "Liked", color = { 0.3, 0.85, 0.35 }, words = { "liked", "like", "good", "friend", "friendly" } },
}
local TONE_BY_KEY, TONE_BY_WORD = {}, {}
for index, tone in ipairs(notes.TONES) do
	tone.order = index
	TONE_BY_KEY[tone.key] = tone
	for _, word in ipairs(tone.words) do
		TONE_BY_WORD[word] = tone
	end
end

-- The built-in labels from before tags; these names become just a tone, others a tag too.
local OLD_LABEL_NAMES = { ["kill on sight"] = true, avoid = true, neutral = true, good = true, friend = true }

local MAX_TAG_LENGTH = 30

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
-- Labels (tones)
------------------------------------------------------------------------------

function notes.GetTone(key)
	return TONE_BY_KEY[key] or TONE_BY_KEY.neutral
end

function notes.RecordTone(record)
	return notes.GetTone(record and record.tone)
end

function notes.ToneColor(tone)
	return tone.color[1], tone.color[2], tone.color[3]
end

-- The label as colored text, with a skull for Kill on sight.
function notes.ToneText(tone)
	if not tone then
		return ""
	end
	local r, g, b = notes.ToneColor(tone)
	return string.format("%s|cff%02x%02x%02x%s|r", tone.scan and SKULL or "", r * 255, g * 255, b * 255, tone.name)
end

-- A label by what you'd type ("kos", "Kill on sight", "avoid", "good"), or nil.
function notes.ToneByWord(word)
	word = word and word:lower():gsub("%s", "")
	return word and TONE_BY_WORD[word] or nil
end

-- A label from before tags (or from an older NraKit's shared note): its tone, and a tag
-- for a label of your own (the built-in names need none).
function notes.FromOldLabel(name, toneKey)
	local tag = name and notes.CleanTag(name)
	if tag and (OLD_LABEL_NAMES[tag:lower()] or notes.ToneByWord(tag)) then
		tag = nil
	end
	return TONE_BY_KEY[toneKey] and toneKey or "neutral", tag
end

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function Migrate(data)
	if data.labels then
		local labels = {}
		for _, label in ipairs(data.labels) do
			labels[label.id] = label
		end
		for _, record in pairs(data.players) do
			local label = labels[record.label]
			local tone, tag = notes.FromOldLabel(label and label.name, label and label.tone)
			record.tone = record.tone or tone
			record.tags = record.tags or {}
			if tag then
				table.insert(record.tags, tag)
			end
			record.label = nil
		end
		data.labels, data.nextLabel = nil, nil
	end
	local known = {}
	data.tags = data.tags or {}
	for _, tag in ipairs(data.tags) do
		known[tag:lower()] = true
	end
	for _, record in pairs(data.players) do
		record.tone = TONE_BY_KEY[record.tone] and record.tone or "neutral"
		record.tags = record.tags or {}
		for _, tag in ipairs(record.tags) do
			if not known[tag:lower()] then
				known[tag:lower()] = true
				table.insert(data.tags, tag)
			end
		end
	end
	data.collapsed = data.collapsed or {}
end

function notes.GetData()
	local data = NraKitDB.playerNotesData
	if not data then
		data = { players = {}, tags = {}, collapsed = {} }
		NraKitDB.playerNotesData = data
	end
	if not data.migrated or not data.tags then
		Migrate(data)
		data.migrated = true
	end
	return data
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
		tone = "neutral",
		tags = {},
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

function notes.SetTone(name, toneKey, info)
	local record = notes.Ensure(name, info)
	record.tone = notes.GetTone(toneKey).key
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

-- "12 Mar 2026  ·  Westfall  ·  by Bob Stone  ·  shared by Ann Lee"
function notes.DescribeNote(note)
	local parts = { date("%d %b %Y", note.time) }
	if note.zone then
		table.insert(parts, note.zone)
	end
	if note.by then
		table.insert(parts, "by " .. note.by)
	end
	if note.sharedBy and note.sharedBy ~= note.by then
		table.insert(parts, "shared by " .. note.sharedBy)
	end
	return table.concat(parts, "  ·  ")
end

function notes.Snippet(text, length)
	length = length or SNIPPET_LENGTH
	if #text > length then
		return text:sub(1, length - 3) .. "..."
	end
	return text
end

------------------------------------------------------------------------------
-- Tags
------------------------------------------------------------------------------

-- What's typed, as a tag: no "#" in front, no commas, single spaces, at most 30 letters.
function notes.CleanTag(text)
	text = strtrim((tostring(text or ""):gsub("^%s*#+", ""):gsub(",", " "):gsub("%s+", " ")))
	text = strtrim(text:sub(1, MAX_TAG_LENGTH))
	return text ~= "" and text or nil
end

function notes.TagKey(tag)
	return tag:lower()
end

function notes.HasTag(record, tag)
	local key = notes.TagKey(tag)
	for _, mine in ipairs(record and record.tags or {}) do
		if notes.TagKey(mine) == key then
			return true
		end
	end
	return false
end

-- Every tag: { { name, key, count } } (count: players with it, can be 0), by name.
function notes.AllTags()
	local data = notes.GetData()
	local byKey, list = {}, {}
	for _, tag in ipairs(data.tags) do
		local key = notes.TagKey(tag)
		byKey[key] = { name = tag, key = key, count = 0 }
		table.insert(list, byKey[key])
	end
	for _, record in pairs(data.players) do
		for _, tag in ipairs(record.tags) do
			local entry = byKey[notes.TagKey(tag)]
			if entry then
				entry.count = entry.count + 1
			end
		end
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

-- The tag as it's already spelled ("tank" -> "Tank"), so one tag stays one; a new
-- tag is added to the list.
local function Remember(tag)
	local tags = notes.GetData().tags
	local key = notes.TagKey(tag)
	for _, known in ipairs(tags) do
		if notes.TagKey(known) == key then
			return known
		end
	end
	table.insert(tags, tag)
	return tag
end

-- A tag nobody has yet (from the Tags page). Returns its name, or nil if not valid.
function notes.CreateTag(text)
	local tag = notes.CleanTag(text)
	if tag then
		tag = Remember(tag)
		Changed()
	end
	return tag
end

local function ForgetTag(tag)
	local tags = notes.GetData().tags
	for index = #tags, 1, -1 do
		if notes.TagKey(tags[index]) == notes.TagKey(tag) then
			table.remove(tags, index)
		end
	end
end

-- Adds a tag to a player (created if new). Returns the record.
function notes.AddTag(name, text, info)
	local tag = notes.CleanTag(text)
	local record = notes.Ensure(name, info)
	if tag and not notes.HasTag(record, tag) then
		table.insert(record.tags, Remember(tag))
		table.sort(record.tags, function(a, b)
			return a:lower() < b:lower()
		end)
		record.updated = time()
		Changed()
	end
	return record
end

local function Without(record, tag)
	local key = notes.TagKey(tag)
	for index = #record.tags, 1, -1 do
		if notes.TagKey(record.tags[index]) == key then
			table.remove(record.tags, index)
		end
	end
end

function notes.RemoveTag(key, tag)
	local record = notes.GetData().players[key]
	if record and notes.HasTag(record, tag) then
		Without(record, tag)
		record.updated = time()
		Changed()
	end
end

-- Renames a tag on everyone (into another tag, if that name is taken: they merge).
function notes.RenameTag(tag, text)
	local newTag = notes.CleanTag(text)
	if not newTag or newTag == tag then
		return
	end
	ForgetTag(tag)
	local merged = Remember(newTag)
	for _, record in pairs(notes.GetData().players) do
		if notes.HasTag(record, tag) then
			Without(record, tag)
			Without(record, merged)
			table.insert(record.tags, merged)
			table.sort(record.tags, function(a, b)
				return a:lower() < b:lower()
			end)
		end
	end
	local collapsed = notes.GetData().collapsed
	collapsed[notes.TagKey(merged)] = collapsed[notes.TagKey(tag)]
	Changed()
end

function notes.DeleteTag(tag)
	for _, record in pairs(notes.GetData().players) do
		Without(record, tag)
	end
	ForgetTag(tag)
	Changed()
end

-- "#Ninjalooter #Tank" in grey, or "".
function notes.TagsText(record)
	if not record or #record.tags == 0 then
		return ""
	end
	return "|cff9a9a9a#" .. table.concat(record.tags, "  #") .. "|r"
end

-- Whether the record already has this note (same text and time).
function notes.HasNote(record, note)
	for _, mine in ipairs(record and record.notes or {}) do
		if mine.text == note.text and mine.time == note.time then
			return true
		end
	end
	return false
end

-- Adds a shared note: shared = { name, tone, tags, notes = { { text, time, zone, by } }, from }.
-- A new player gets their label; someone you have keeps yours unless useTone. tags: the
-- ones to add (default all of theirs). Notes you already have are skipped; the rest keep
-- their author and say who shared them. Returns the record and how many notes were added.
function notes.Import(shared, useTone, tags)
	local isNew = notes.Find(shared.name) == nil
	local record = notes.Ensure(shared.name)
	if isNew or useTone then
		record.tone = notes.GetTone(shared.tone).key
	end
	for _, tag in ipairs(tags or shared.tags or {}) do
		tag = notes.CleanTag(tag)
		if tag and not notes.HasTag(record, tag) then
			table.insert(record.tags, Remember(tag))
		end
	end
	table.sort(record.tags, function(a, b)
		return a:lower() < b:lower()
	end)
	local added = 0
	for _, note in ipairs(shared.notes) do
		if not notes.HasNote(record, note) then
			table.insert(record.notes, {
				text = note.text,
				time = note.time,
				zone = note.zone,
				by = note.by or shared.from,
				sharedBy = shared.from,
			})
			added = added + 1
		end
	end
	-- By time, keeping the order of notes from the same second.
	local order = {}
	for index, note in ipairs(record.notes) do
		order[note] = index
	end
	table.sort(record.notes, function(a, b)
		if (a.time or 0) ~= (b.time or 0) then
			return (a.time or 0) < (b.time or 0)
		end
		return order[a] < order[b]
	end)
	record.updated = time()
	Changed()
	return record, added
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
	local count = #record.notes
	local line = notes.ToneText(notes.RecordTone(record))
	if #record.tags > 0 then
		line = line .. "  " .. notes.TagsText(record)
	end
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
	local noteMenu = root:CreateButton("Player note")
	noteMenu:CreateButton(record and "Open notes..." or "Add a note...", function()
		ns:OpenPlayerNotes(name, info)
	end)
	noteMenu:CreateDivider()
	for _, tone in ipairs(notes.TONES) do
		noteMenu:CreateRadio(notes.ToneText(tone), function()
			local current = notes.Find(name, info.guid)
			return current ~= nil and current.tone == tone.key
		end, function()
			notes.SetTone(name, tone.key, info)
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

-- Warns if the player is labelled Avoid or Kill on sight. Returns true if it did.
function notes.Warn(name, guid, reason)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption(REASONS[reason].option) then
		return false
	end
	local record, key = notes.Find(name, guid)
	local tone = notes.RecordTone(record)
	if not record or not tone.warn then
		return false
	end
	local now = time()
	local stamp = key .. ":" .. reason
	if lastWarn[stamp] and now - lastWarn[stamp] < WARN_COOLDOWN then
		return false
	end
	lastWarn[stamp] = now

	local r, g, b = notes.ToneColor(tone)
	local latest = notes.LatestNote(record)
	local message = string.format("%s (%s) %s", record.name, notes.ToneText(tone), REASONS[reason].text)
	if latest then
		message = message .. ": \"" .. notes.Snippet(latest.text) .. "\""
	end
	ns:Print("|cffff8040Heads up:|r " .. message)
	if ns:GetOption("playerNotesWarnScreen") and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, string.format("%s - %s", record.name, tone.name),
			{ r = r, g = g, b = b })
	end
	if ns:GetOption("playerNotesWarnSound") then
		ns.sounds.PlayOption("playerNotesWarnSoundChoice", "kit:UI_RAID_BOSS_WHISPER_WARNING")
	end
	return true
end

-- /nra preview warning: the warning for a made-up Kill on sight player.
ns:RegisterPreview("warning", "Player notes: the warning when a player you've marked joins your group", function()
	ns:Print("|cffff8040Heads up:|r Bob Stone (Kill on sight) is in your group: \"stole my mining node\"")
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, "Bob Stone - Kill on sight", { r = 1, g = 0.2, b = 0.2 })
	end
	ns.sounds.PlayOption("playerNotesWarnSoundChoice", "kit:UI_RAID_BOSS_WHISPER_WARNING")
end)

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

-- Whether any player is labelled Kill on sight (and scanning for them is on).
function notes.HasScanTargets()
	if not ScanEnabled() then
		return false
	end
	if hasScanTargets == nil then
		hasScanTargets = false
		for _, record in pairs(notes.GetData().players) do
			if notes.RecordTone(record).scan then
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
	local tone = notes.RecordTone(record)
	if not record or not tone.scan then
		return nil
	end
	local entry = scanEntries[key] or { noted = true }
	scanEntries[key] = entry
	entry.name = record.name
	entry.label = tone.name
	return entry
end

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

local HELP = {
	summary = "Player notes: label and tag players and keep notes on them",
	usage = {
		"/nra note - your target's notes, or the notebook",
		"/nra note <note> - add a note to your target (a player)",
		"/nra note <label> [#tags] [note] - set your target's label (kos, avoid, neutral, liked), add tags (#tank), and a note",
		"/nra note <First Last> [label] [#tags] [note] - the same for anyone by name (nothing else: opens their notes)",
		"/nra note <first name> [label or #tag ...] - someone you already have notes on (e.g. /nra note bob kos #ninja)",
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

-- Sets the label, adds the tags and/or the note, and says what it did.
local function Apply(name, info, tone, tags, text)
	if not tone and #tags == 0 and text == "" then
		ns:OpenPlayerNotes(name, info)
		return
	end
	if tone then
		notes.SetTone(name, tone.key, info)
	end
	for _, tag in ipairs(tags) do
		notes.AddTag(name, tag, info)
	end
	local record = text ~= "" and notes.AddNote(name, text, info) or notes.Find(name)
	local parts = {}
	if tone then
		table.insert(parts, "label " .. notes.ToneText(tone))
	end
	if #tags > 0 then
		table.insert(parts, "tagged " .. notes.TagsText({ tags = tags }))
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
		local tags = #entry.record.tags > 0 and (" " .. notes.TagsText(entry.record)) or ""
		print(string.format("  %s - %s%s%s", entry.record.name, notes.ToneText(notes.RecordTone(entry.record)), tags,
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
	-- "[label] [#tag ...] [note]" from a word on.
	local function RestFrom(index)
		local tone = notes.ToneByWord(words[index])
		if tone then
			index = index + 1
		end
		local tags = {}
		while words[index] and words[index]:match("^#.") do
			table.insert(tags, notes.CleanTag(words[index]))
			index = index + 1
		end
		return tone, tags, table.concat(words, " ", index)
	end
	local function LabelOrTag(word)
		return word and (notes.ToneByWord(word) or word:match("^#."))
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

	-- Otherwise, with a player targeted, it's all about them: "[label] [#tags] [note]".
	if targetName then
		Apply(targetName, targetInfo, RestFrom(1))
		return
	end

	-- No target: a noted player by first name, followed by a label, a tag or nothing ("bob kos"
	-- -> Bob Stone; "bob smith kos" is a new Bob), or a new player's "First Last".
	local known = (#words == 1 or LabelOrTag(words[2])) and FindByPrefix(words[1])
	if known then
		Apply(known.name, nil, RestFrom(2))
	elseif LabelOrTag(words[1]) or #words == 1 then
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
