local _, ns = ...

-- Player notes in chat: shift-click a player in your notes (or Link in chat on their
-- page) to put "[NraKit note: Name]" in your chat box. For others with NraKit the text
-- becomes a link; clicking it asks your client for the note over hidden addon whispers,
-- and a window shows the name, label, tags and notes with Add and Cancel.
--
-- What you send in chat is plain text (the server strips addon links from chat); each
-- client turns it into a link itself. Only players you linked this session are sent,
-- and only while you're online. Addon messages can arrive out of order, so the note goes
-- as one text cut into numbered pieces, put back together by number.
--
-- Messages (prefix NraKitNote, whispers, fields split by tabs):
--   REQ <id> <name>            send me the note you linked on <name>
--   DENY <id>                  not linked by me (or gone)
--   PART <id> <i> <n> <data>   piece i of n of the note
-- The note: lines split by "\n", fields by "\t" (both escaped inside fields):
--   <name> <label name> <tone> <how many notes you have> <tags, comma-separated> <rating>
--   <time> <by> <zone> <text>  per note, oldest first (the oldest are left out past MAX_BYTES)
-- NraKit 0.22.0 had editable labels and no tags: its header has no tags, and its label
-- name becomes a tag unless it's a built-in one (notes.FromOldLabel). It reads our label
-- name ("Kill on sight", ...) as a label of its own.

local notes = ns.playerNotes
local UI = ns.UI

local PREFIX = "NraKitNote"
local LINK_TEXT = "[NraKit note: %s]"
local LINK_PATTERN = "%[NraKit note: ([^%]]+)%]"
local LINK_COLOR = "ff33ccaa"
local PIECE_BYTES = 220 -- an addon message holds 255
local MAX_BYTES = 4000 -- the newest notes that fit; a few seconds to send
local TIMEOUT = 10
local SEND_GAP = 0.1
local RESULT_THROTTLED, RESULT_OFFLINE = 3, 12 -- Enum.SendAddonMessageResult
local WIDTH, HEIGHT = 460, 450
local PAD = UI.PAD

local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local share = {}
ns.playerNotesShare = share

local linked = {} -- [key] = true: players you linked this session (only these are sent)
local requests = {} -- [id] = { from, name, parts = {}, count, heard }: notes being fetched
local nextRequest = 1
local queue = {} -- { message, target }: pieces waiting to go out
local sending = false
local frame, pool -- the review window
local shown -- the note in the review window: { name, label, tone, total, notes, from }
local useTheirLabel = false
local pickedTags = {} -- [tag] = true: their tags to add

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function Enabled()
	return ns:IsModuleEnabled("playerNotes")
end

local function LinksOn()
	return Enabled() and ns:GetOption("playerNotesShareLinks")
end

local function MyName()
	return notes.UnitFullName("player") or UnitName("player")
end

local function IsMe(name)
	local me = MyName()
	return me ~= nil and notes.Key(me) == notes.Key(name)
end

------------------------------------------------------------------------------
-- The note as text
------------------------------------------------------------------------------

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["|"] = "\\p" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n", p = "|" }

local function Escape(text)
	return (tostring(text or ""):gsub("[\\\t\n|]", ESCAPES))
end

local function Unescape(text)
	return (text:gsub("\\(.)", UNESCAPES))
end

local function Optional(text)
	return text ~= "" and text or nil
end

-- A player's record as text: the header line and as many of the newest notes as fit.
function share.Encode(record)
	local tone = notes.RecordTone(record)
	local header = table.concat({ Escape(record.name), Escape(tone.name), tone.key, #record.notes,
		Escape(table.concat(record.tags, ",")), record.rating or "" }, "\t")
	local lines, size = {}, #header
	for index = #record.notes, 1, -1 do
		local note = record.notes[index]
		local line = table.concat({ note.time or 0, Escape(note.by), Escape(note.zone), Escape(note.text) }, "\t")
		if size + #line + 1 > MAX_BYTES and #lines > 0 then
			break
		end
		table.insert(lines, 1, line)
		size = size + #line + 1
	end
	table.insert(lines, 1, header)
	return table.concat(lines, "\n")
end

-- The text back to { name, tone, tags, total, notes = { { time, by, zone, text } } }, or nil.
function share.Decode(text)
	local lines = { strsplit("\n", text) }
	local name, label, toneKey, total, tagText, rating = strsplit("\t", lines[1] or "")
	if not name or name == "" then
		return nil
	end
	local tone, tags = notes.GetTone(toneKey).key, {}
	if tagText then
		for _, tag in ipairs({ strsplit(",", Unescape(tagText)) }) do
			table.insert(tags, notes.CleanTag(tag))
		end
	else
		local oldTag
		tone, oldTag = notes.FromOldLabel(Unescape(label or ""), toneKey)
		tags[1] = oldTag
	end
	local shared = { name = Unescape(name), tone = tone, tags = tags, rating = notes.CleanRating(rating),
		total = tonumber(total) or 0, notes = {} }
	for index = 2, #lines do
		local stamp, by, zone, noteText = strsplit("\t", lines[index])
		if noteText then
			table.insert(shared.notes, { time = tonumber(stamp), by = Optional(Unescape(by)),
				zone = Optional(Unescape(zone)), text = Unescape(noteText) })
		end
	end
	return shared
end

-- Cuts text into pieces of at most PIECE_BYTES, never inside a UTF-8 character.
function share.Cut(text)
	local pieces, start = {}, 1
	while start <= #text do
		local stop = math.min(start + PIECE_BYTES - 1, #text)
		while stop < #text and stop > start do
			local nextByte = text:byte(stop + 1)
			if nextByte < 0x80 or nextByte >= 0xC0 then
				break
			end
			stop = stop - 1 -- the next byte continues a character: cut before it
		end
		table.insert(pieces, text:sub(start, stop))
		start = stop + 1
	end
	return pieces
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------

local function Blocked()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local Pump
Pump = function()
	local item = queue[1]
	if not item then
		sending = false
		return
	end
	local result = C_ChatInfo.SendAddonMessage(PREFIX, item.message, "WHISPER", item.target)
	if result == RESULT_THROTTLED then
		C_Timer.After(1, Pump) -- try the same piece again
		return
	end
	table.remove(queue, 1)
	C_Timer.After(SEND_GAP, Pump)
end

local function Queue(message, target)
	table.insert(queue, { message = message, target = target })
	if not sending then
		sending = true
		Pump()
	end
end

-- Puts "[NraKit note: Name]" in your chat box, and lets that note be fetched.
function share.Link(key)
	local record = notes.GetData().players[key]
	if not record then
		return
	end
	linked[key] = true
	local text = LINK_TEXT:format(record.name)
	if not ChatFrameUtil.InsertLink(text) then
		ChatFrameUtil.OpenChat(text)
	end
end

local function Answer(id, name, sender)
	local record, key = notes.Find(name)
	if not Enabled() or not record or not linked[key] then
		Queue("DENY\t" .. id, sender)
		return
	end
	local pieces = share.Cut(share.Encode(record))
	for index, piece in ipairs(pieces) do
		Queue(table.concat({ "PART", id, index, #pieces, piece }, "\t"), sender)
	end
end

------------------------------------------------------------------------------
-- Fetching
------------------------------------------------------------------------------

local ShowReview

local function CheckTimeout(id)
	local request = requests[id]
	if request and GetTime() - request.heard >= TIMEOUT - 0.01 then
		requests[id] = nil
		ns:Print(string.format("No answer from %s about %s. They may be offline, or not have NraKit with Player notes on.",
			request.from, request.name))
	end
end

-- Asks whoever linked it for the note.
function share.Request(from, name)
	if IsMe(from) then
		ns:OpenPlayerNotes(name)
		return
	end
	if Blocked() then
		ns:Print("Notes can't be fetched right now (combat or an instance). Try again in a moment.")
		return
	end
	local id = tostring(nextRequest)
	nextRequest = nextRequest + 1
	local result = C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "REQ", id, name }, "\t"), "WHISPER", from)
	if result == RESULT_OFFLINE then
		ns:Print(from .. " is offline: ask them to link the note again when they're on.")
		return
	end
	requests[id] = { from = from, name = name, parts = {}, heard = GetTime() }
	ns:Print(string.format("Asking %s for their note on %s...", from, name))
	C_Timer.After(TIMEOUT, function()
		CheckTimeout(id)
	end)
end

local function OnPiece(id, index, count, data, sender)
	local request = requests[id]
	if not request or notes.Key(sender) ~= notes.Key(request.from) then
		return
	end
	index, count = tonumber(index), tonumber(count)
	if not index or not count or index < 1 or index > count then
		return
	end
	request.parts[index] = data
	request.count = count
	request.heard = GetTime()
	C_Timer.After(TIMEOUT, function()
		CheckTimeout(id)
	end)
	for part = 1, count do
		if not request.parts[part] then
			return
		end
	end
	requests[id] = nil
	local shared = share.Decode(table.concat(request.parts, "", 1, count))
	if shared then
		shared.from = request.from
		ShowReview(shared)
	end
end

function share.OnMessage(text, sender)
	if not Enabled() or IsSecret(text) or IsSecret(sender) then
		return
	end
	local kind, id, a, b, c = strsplit("\t", text, 5)
	if kind == "REQ" and a then
		Answer(id, a, sender)
	elseif kind == "PART" then
		OnPiece(id, a, b, c or "", sender)
	elseif kind == "DENY" and requests[id] then
		local request = requests[id]
		requests[id] = nil
		ns:Print(string.format("%s hasn't linked a note on %s since they logged in. Ask them to link it again.",
			request.from, request.name))
	end
end

------------------------------------------------------------------------------
-- Chat links
------------------------------------------------------------------------------

local function Filter(_, event, message, author, ...)
	if not LinksOn() or IsSecret(message) or IsSecret(author) or type(message) ~= "string" then
		return false
	end
	if not message:find("[NraKit note: ", 1, true) then
		return false
	end
	-- A whisper you send shows the receiver as its author.
	local owner = event == "CHAT_MSG_WHISPER_INFORM" and MyName() or author
	if not owner or owner:find(":", 1, true) then
		return false
	end
	local linkedText = message:gsub(LINK_PATTERN, function(name)
		return string.format("|c%s|Haddon:nrakit:note:%s:%s|h[NraKit note: %s]|h|r", LINK_COLOR, owner, name, name)
	end)
	return false, linkedText, author, ...
end

local function OnLinkClicked(_, link)
	if type(link) ~= "string" then
		return
	end
	local from, name = link:match("^addon:nrakit:note:([^:]+):(.+)$")
	if from and LinksOn() then
		share.Request(from, name)
	end
end

------------------------------------------------------------------------------
-- Review window
------------------------------------------------------------------------------

local function NewNotes(record)
	local count = 0
	for _, note in ipairs(shown.notes) do
		if not notes.HasNote(record, note) then
			count = count + 1
		end
	end
	return count
end

local function Render()
	pool:ReleaseAll()
	local record = notes.Find(shown.name)
	local mine = notes.RecordTone(record)
	local theirs = notes.GetTone(shown.tone)
	frame.name:SetText(shown.name)
	local theirStars = notes.RecordStars(shown, 12)
	frame.from:SetText(string.format("Shared by %s  ·  their label: %s%s", shown.from, notes.ToneText(theirs),
		theirStars ~= "" and (" " .. theirStars) or ""))

	local differs = record and mine.key ~= theirs.key
	frame.keep:SetShown(differs)
	frame.use:SetShown(differs)
	if differs then
		frame.status:SetText("In your notes as " .. notes.ToneText(mine) .. ".")
		frame.keep.text:SetText("Keep " .. notes.ToneText(mine))
		frame.keep:SetWidth(frame.keep.text:GetStringWidth() + 20)
		frame.use.text:SetText("Use " .. notes.ToneText(theirs))
		frame.use:SetWidth(frame.use.text:GetStringWidth() + 20)
		frame.keep:SetSelected(not useTheirLabel)
		frame.use:SetSelected(useTheirLabel)
		frame.keep.text:SetTextColor(1, 1, 1)
		frame.use.text:SetTextColor(1, 1, 1)
	elseif record then
		frame.status:SetText("In your notes as " .. notes.ToneText(mine) .. ".")
	else
		frame.status:SetText("New to your notes: they'll be " .. notes.ToneText(theirs) .. ".")
	end

	-- Their tags: click to leave one out; ones you already have are just shown.
	local x, newTags = 0, 0
	frame.tagsLabel:SetShown(#shown.tags > 0)
	for _, tag in ipairs(shown.tags) do
		local chip = pool:Acquire("tag", function()
			local button = UI.CreateFlatButton(frame.body, "", 22)
			button:SetScript("OnClick", function(self)
				pickedTags[self.tag] = not pickedTags[self.tag] or nil
				Render()
			end)
			return button
		end)
		local have = notes.HasTag(record, tag)
		chip.tag = tag
		chip:SetEnabled(not have)
		chip.text:SetText("#" .. tag .. (have and "  (have it)" or ""))
		chip:SetWidth(chip.text:GetStringWidth() + 20)
		chip:SetSelected(not have and pickedTags[tag])
		if have then
			chip.text:SetTextColor(unpack(UI.TEXT_DIM))
		elseif pickedTags[tag] then
			newTags = newTags + 1
		end
		chip:SetPoint("LEFT", frame.tagsLabel, "RIGHT", 8 + x, 0)
		x = x + chip:GetWidth() + 4
	end

	local content = frame.scroll.content
	local width = WIDTH - 2 * PAD - 14
	content:SetWidth(width)
	local y = 0
	for index = #shown.notes, 1, -1 do
		local note = shown.notes[index]
		local row = pool:Acquire("note", function()
			local entry = CreateFrame("Frame", nil, content)
			entry.meta = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			entry.meta:SetPoint("TOPLEFT")
			entry.meta:SetJustifyH("LEFT")
			entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			entry.text:SetPoint("TOPLEFT", 0, -14)
			entry.text:SetJustifyH("LEFT")
			entry.text:SetWordWrap(true)
			return entry
		end)
		local have = notes.HasNote(record, note)
		row.meta:SetText(notes.DescribeNote(note) .. (have and "  ·  already in your notes" or ""))
		row.text:SetWidth(width)
		row.text:SetText(note.text)
		row.text:SetAlpha(have and 0.5 or 1)
		local height = 14 + row.text:GetStringHeight() + 4
		row:SetSize(width, height)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - height - 10
	end
	local left = shown.total - #shown.notes
	if left > 0 or #shown.notes == 0 then
		local more = pool:Acquire("more", function()
			local text = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			text:SetJustifyH("LEFT")
			return text
		end)
		more:SetText(#shown.notes == 0 and "No notes, just the label."
			or string.format("%d older %s weren't sent.", left, left == 1 and "note" or "notes"))
		more:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - 20
	end
	content:SetHeight(math.max(-y, 1))
	frame.scroll:UpdateThumb()

	local count = NewNotes(record)
	local changes = count > 0 or newTags > 0 or not record or (differs and useTheirLabel)
	frame.add.text:SetText(count > 0 and string.format("Add %d %s", count, count == 1 and "note" or "notes") or "Add")
	frame.add:SetWidth(frame.add.text:GetStringWidth() + 24)
	frame.add:SetEnabled(changes)
	frame.add:SetAlpha(changes and 1 or 0.4)
end

local function AddShown()
	local tags = {}
	for _, tag in ipairs(shown.tags) do
		if pickedTags[tag] then
			table.insert(tags, tag)
		end
	end
	local record, added = notes.Import(shown, useTheirLabel, tags)
	ns:Print(string.format("%s: %d %s added from %s.", record.name, added, added == 1 and "note" or "notes", shown.from))
	frame:Hide()
end

local function CreateReviewWindow()
	frame = UI.CreateWindow("NraKitNoteShareFrame", "Shared player note", WIDTH, HEIGHT, 0)
	pool = UI.CreatePool()
	local body = frame.body

	frame.name = body:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.name:SetPoint("TOPLEFT", PAD, -PAD)
	frame.from = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.from:SetPoint("TOPLEFT", PAD, -PAD - 30)
	frame.status = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("TOPLEFT", PAD, -PAD - 48)

	frame.keep = UI.CreateFlatButton(body, "", 22)
	frame.keep:SetPoint("TOPLEFT", PAD, -PAD - 66)
	frame.keep:SetScript("OnClick", function()
		useTheirLabel = false
		Render()
	end)
	frame.use = UI.CreateFlatButton(body, "", 22)
	frame.use:SetPoint("LEFT", frame.keep, "RIGHT", 4, 0)
	frame.use:SetScript("OnClick", function()
		useTheirLabel = true
		Render()
	end)

	frame.tagsLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.tagsLabel:SetPoint("TOPLEFT", PAD, -PAD - 104)
	frame.tagsLabel:SetText("Their tags:")

	frame.scroll = UI.CreateScrollArea(body)
	frame.scroll:SetPoint("TOPLEFT", PAD, -PAD - 128)
	frame.scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, 44)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(34)
	UI.AddLine(footer, "TOP")
	frame.add = UI.CreateFlatButton(footer, "Add", 22)
	frame.add:SetPoint("RIGHT", -PAD, 0)
	frame.add:SetSelected(true)
	frame.add:SetScript("OnClick", AddShown)
	frame.cancel = UI.CreateFlatButton(footer, "Cancel", 22)
	frame.cancel:SetPoint("RIGHT", frame.add, "LEFT", -6, 0)
	frame.cancel:SetScript("OnClick", function()
		frame:Hide()
	end)
end

ShowReview = function(shared)
	if not frame then
		CreateReviewWindow()
	end
	shown = shared
	useTheirLabel = false
	pickedTags = {}
	for _, tag in ipairs(shared.tags or {}) do
		pickedTags[tag] = true
	end
	shared.tags = shared.tags or {}
	frame:Show()
	Render()
end
share.ShowReview = ShowReview

------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------

for _, event in ipairs(CHAT_EVENTS) do
	ChatFrameUtil.AddMessageEventFilter(event, Filter)
end
EventRegistry:RegisterCallback("SetItemRef", OnLinkClicked, share)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, _, sender = ...
		if prefix == PREFIX then
			share.OnMessage(text, sender)
		end
	else
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	end
end)
