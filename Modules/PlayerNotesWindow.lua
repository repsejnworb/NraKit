local _, ns = ...

-- Player Notes window (/nra note, or Player note in a player's right-click menu).
--
-- Sidebar: "+ Add player" (a page with a name box, and your target as a shortcut),
-- search (name, label, tag or note text), a filter chip per label (any number on; they
-- reset when the window closes) and the players: in a section per tag
-- (foldable, Kill on sight first within each; shift-click folds all others), then those
-- without tags, with Fold all above. A search gives one list, newest change first.
-- Typing a name nobody has offers "+ Add <name>" too. At the bottom, Tags. Shift-click a
-- player links them in chat.
--
-- A player's page: their label as four chips (one click to change; Liked gets five stars
-- next to it, click a star's left half for a half star), their tags (click
-- one to remove it; "+ Tag" opens a menu of your tags to tick, and New tag...), a box to add a
-- note (saved with the date, zone and your character) and the log, newest first. A
-- player opened from a menu who has no notes yet isn't saved until something is added.
--
-- Tags page: add a tag, and every tag with how many players have it; rename (or merge)
-- and delete.

local UI = ns.UI
local notes = ns.playerNotes
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local SIDEBAR_WIDTH = 230
local PAD = UI.PAD
local FOOTER_HEIGHT = 34
local BODY_WIDTH = WIDTH - SIDEBAR_WIDTH

local frame, searchBox, sidebarScroll, tagsButton, addButton, filterChips
local playerPage, emptyPage, tagsPage, addPage
local sidebarPool, chipPool, logPool, tagPool = UI.CreatePool(), UI.CreatePool(), UI.CreatePool(), UI.CreatePool()
local newTagOpen = false -- the player page's "New tag" box is showing
local toneFilter = {} -- [tone key] = true: the labels the list is narrowed to (none: all)
local STAR_SIZE = 18

local page = "empty" -- "player", "empty", "add" or "tags"
local selectedKey -- the shown player's key, or nil
local pending -- { name, info } for a player opened before anything was saved
local query, typedName = "", ""
local confirmDelete = false

local Render

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function MakeHeading(parent, text)
	local heading = MakeLabel(parent, text:upper(), "GameFontNormalSmall")
	heading:SetTextColor(unpack(UI.ACCENT))
	return heading
end

local function MakeEditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(UI.TEXT)
end

local function FormatDate(timestamp)
	return date("%d %b %Y", timestamp)
end

-- "bob stone" -> "Bob Stone"
local function Capitalize(text)
	return (notes.Display(text):gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest
	end))
end

-- The shown player: record and key, or nil and the pending name.
local function Current()
	local record = selectedKey and notes.GetData().players[selectedKey]
	if record then
		return record, selectedKey
	end
	return nil
end

local function CurrentName()
	local record = Current()
	return record and record.name or (pending and pending.name)
end

local function Select(key)
	selectedKey, pending = key, nil
	page = key and "player" or "empty"
	confirmDelete = false
end

-- After the first label or note, the pending player is saved: show it by its key.
local function AfterSave(record)
	if record then
		local _, key = notes.Find(record.name)
		selectedKey, pending = key, nil
	end
end

local function Filtering()
	return next(toneFilter) ~= nil
end

local function Matches(record)
	if Filtering() and not toneFilter[record.tone] then
		return false
	end
	if query == "" then
		return true
	end
	local function Has(text)
		return text and text:lower():find(query, 1, true) ~= nil
	end
	if Has(record.name) or Has(notes.RecordTone(record).name) then
		return true
	end
	for _, tag in ipairs(record.tags) do
		if Has(tag) then
			return true
		end
	end
	for _, note in ipairs(record.notes) do
		if Has(note.text) or Has(note.zone) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------
-- Sidebar
------------------------------------------------------------------------------

-- Players with this tag (nil: without tags), Kill on sight first, then by name.
local function Section(tag)
	local list = {}
	for key, record in pairs(notes.GetData().players) do
		if ((tag and notes.HasTag(record, tag)) or (not tag and #record.tags == 0)) and Matches(record) then
			table.insert(list, { key = key, record = record })
		end
	end
	table.sort(list, function(a, b)
		local toneA, toneB = notes.RecordTone(a.record).order, notes.RecordTone(b.record).order
		if toneA ~= toneB then
			return toneA < toneB
		end
		local ratingA, ratingB = a.record.rating or 0, b.record.rating or 0
		if a.record.tone == "friendly" and ratingA ~= ratingB then
			return ratingA > ratingB -- best rated first
		end
		return a.key < b.key
	end)
	return list
end

-- Tags are trimmed, so a leading space can't clash with a tag's key.
local UNTAGGED = " untagged"

local function RenderSidebar()
	sidebarPool:ReleaseAll()
	local content = sidebarScroll.content
	local width = SIDEBAR_WIDTH - 2 * PAD
	local y = 0

	local function AddButton()
		local button = sidebarPool:Acquire("nav", function()
			local nav = UI.CreateNavButton(content, width, 38, "")
			nav:SetScript("OnClick", function(self)
				if self.key and IsModifiedClick("CHATLINK") then
					ns.playerNotesShare.Link(self.key)
					return
				end
				if self.key then
					Select(self.key)
				else
					Select(nil)
					pending = { name = self.addName }
					page = "player"
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Render()
			end)
			return nav
		end)
		button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - 40
		return button
	end

	local function AddPlayer(entry, withTags)
		local record = entry.record
		local button = AddButton()
		button.key, button.addName = entry.key, nil
		button.text:SetText(record.name)
		local subtext = notes.ToneText(notes.RecordTone(record))
		local stars = notes.RecordStars(record, 11)
		if stars ~= "" then
			subtext = subtext .. " " .. stars
		end
		if withTags and #record.tags > 0 then
			subtext = subtext .. "  " .. notes.TagsText(record)
		end
		button:SetSubtext(subtext)
		button.count:SetText(#record.notes > 0 and tostring(#record.notes) or "")
		button:SetSelected(page == "player" and selectedKey == entry.key, { ClassColor(record.class) })
	end

	local function AddHeader(text, count, collapseKey)
		local header = sidebarPool:Acquire("header", function()
			local button = CreateFrame("Button", nil, content)
			button:SetHeight(26)
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.05)
			UI.AddLine(button, "BOTTOM")
			button.arrow = button:CreateTexture(nil, "ARTWORK")
			button.arrow:SetSize(12, 12)
			button.arrow:SetPoint("LEFT", 4, 0)
			button.arrow:SetAtlas("common-icon-forwardarrow")
			button.text = MakeLabel(button, "", "GameFontNormal")
			button.text:SetPoint("LEFT", button.arrow, "RIGHT", 6, 0)
			button.text:SetPoint("RIGHT", -30, 0)
			button.text:SetWordWrap(false)
			button.count = MakeLabel(button, "", "GameFontDisable")
			button.count:SetPoint("RIGHT", -8, 0)
			button:SetScript("OnClick", function(self)
				local collapsed = notes.GetData().collapsed
				if IsShiftKeyDown() then
					-- Only this one open.
					for _, tag in ipairs(notes.AllTags()) do
						collapsed[tag.key] = true
					end
					collapsed[UNTAGGED] = true
					collapsed[self.collapseKey] = nil
				else
					collapsed[self.collapseKey] = not collapsed[self.collapseKey] or nil
				end
				Render()
			end)
			button:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, self.label, "Click to fold or unfold. Shift-click to fold all the others.")
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			return button
		end)
		local closed = notes.GetData().collapsed[collapseKey]
		header.collapseKey, header.label = collapseKey, text
		header.arrow:SetRotation(closed and 0 or -math.pi / 2)
		header.text:SetText(text)
		header.text:SetTextColor(unpack(UI.ACCENT))
		header.count:SetText(count)
		header:SetWidth(width)
		header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 2)
		y = y - 30
		return not closed
	end

	-- "Fold all" (or "Unfold all" when everything is folded) above the sections.
	local function AddFoldAll(keys)
		local collapsed = notes.GetData().collapsed
		local allClosed = true
		for _, key in ipairs(keys) do
			allClosed = allClosed and collapsed[key] == true
		end
		local button = sidebarPool:Acquire("foldall", function()
			local fold = CreateFrame("Button", nil, content)
			fold:SetHeight(16)
			fold.text = MakeLabel(fold, "", "GameFontDisableSmall")
			fold.text:SetPoint("RIGHT", -8, 0)
			local highlight = fold:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints(fold.text)
			highlight:SetColorTexture(1, 1, 1, 0.08)
			fold:SetScript("OnClick", function(self)
				local data = notes.GetData()
				for _, key in ipairs(self.keys) do
					data.collapsed[key] = not self.allClosed or nil
				end
				Render()
			end)
			return fold
		end)
		button.keys, button.allClosed = keys, allClosed
		button.text:SetText(allClosed and "Unfold All" or "Fold All")
		button:SetWidth(width)
		button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - 18
	end

	local function AddHint(text)
		local hint = sidebarPool:Acquire("hint", function()
			local label = MakeLabel(content, "", "GameFontDisableSmall")
			label:SetWidth(width - 12)
			label:SetWordWrap(true)
			return label
		end)
		hint:SetText(text)
		hint:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 2)
		y = y - hint:GetStringHeight() - 10
	end

	-- A typed name nobody has yet: offer to add it.
	if typedName ~= "" and not notes.Find(typedName) then
		local add = AddButton()
		add.key, add.addName = nil, Capitalize(typedName)
		add.text:SetText("+ Add " .. add.addName)
		add:SetSubtext("New player")
		add.count:SetText("")
		add:SetSelected(pending ~= nil and pending.name == add.addName, UI.ACCENT)
	end

	local tags = notes.AllTags()
	local shown = 0
	if query ~= "" then
		for _, entry in ipairs(notes.All()) do
			if Matches(entry.record) then
				shown = shown + 1
				AddPlayer(entry, true)
			end
		end
	elseif next(notes.GetData().players) then
		shown = 1
		-- Sections with players (with a filter on: matching ones), counting those.
		local used, sections = {}, {}
		local keys = { UNTAGGED }
		for _, tag in ipairs(tags) do
			sections[tag.key] = Section(tag.name)
			if #sections[tag.key] > 0 then
				table.insert(used, tag)
				table.insert(keys, tag.key)
			end
		end
		local untagged = Section(nil)
		if Filtering() and #used == 0 and #untagged == 0 then
			shown = 0
		else
			AddFoldAll(keys)
		end
		for _, tag in ipairs(used) do
			if AddHeader("#" .. tag.name, #sections[tag.key], tag.key) then
				for _, entry in ipairs(sections[tag.key]) do
					AddPlayer(entry, false)
				end
			end
		end
		-- Always there (unless filtered away), even empty: it shows that players can be grouped.
		if (not Filtering() or #untagged > 0) and AddHeader("No tags", #untagged, UNTAGGED) then
			if #used == 0 and not Filtering() then
				AddHint("Tag players on their page (Ninjalooter, Good tank, ...) to group them here.")
			end
			for _, entry in ipairs(untagged) do
				AddPlayer(entry, false)
			end
		end
	end

	if shown == 0 and typedName == "" then
		local empty = sidebarPool:Acquire("empty", function()
			local text = MakeLabel(content, "", "GameFontDisableSmall")
			text:SetWidth(width - 8)
			return text
		end)
		local filtered = query ~= "" or Filtering()
		empty:SetText(filtered and "Nobody matches." or "No notes yet.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 4)
		y = y - 24
		if Filtering() then
			local clear = sidebarPool:Acquire("clear", function()
				local button = UI.CreateFlatButton(content, "Clear Filters", 20)
				button:SetScript("OnClick", function()
					wipe(toneFilter)
					Render()
				end)
				return button
			end)
			clear:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 2)
			y = y - 28
		end
	end
	for _, chip in ipairs(filterChips) do
		local tone = notes.GetTone(chip.tone)
		chip:SetSelected(toneFilter[chip.tone] == true)
		chip.text:SetTextColor(notes.ToneColor(tone))
	end
	content:SetSize(width, -y)
	sidebarScroll:UpdateThumb()
	tagsButton:SetSelected(page == "tags")
end

------------------------------------------------------------------------------
-- Player page
------------------------------------------------------------------------------

local function SaveTone(toneKey)
	local name = CurrentName()
	if not name then
		return
	end
	local info = pending and pending.info
	AfterSave(notes.SetTone(name, toneKey, info))
end

local function AddTag(text)
	local name = CurrentName()
	if not name or not notes.CleanTag(text) then
		return
	end
	local info = pending and pending.info
	AfterSave(notes.AddTag(name, text, info))
	Render()
end

local function RemoveTag(tag)
	local record, key = Current()
	if record then
		notes.RemoveTag(key, tag)
	end
end

-- "+ Tag": every tag to tick (the menu stays open), then New tag...
local function OpenTagMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		for _, tag in ipairs(notes.AllTags()) do
			root:CreateCheckbox("#" .. tag.name, function()
				return notes.HasTag(Current(), tag.name)
			end, function()
				if notes.HasTag(Current(), tag.name) then
					RemoveTag(tag.name)
				else
					AddTag(tag.name)
				end
			end)
		end
		if #notes.AllTags() > 0 then
			root:CreateDivider()
		end
		root:CreateButton("New tag...", function()
			newTagOpen = true
			Render()
			playerPage.tagBox:SetFocus()
		end)
	end)
end

local function AddTypedNote()
	local box = playerPage.noteBox
	local text = strtrim(box:GetText() or "")
	local name = CurrentName()
	if text == "" or not name then
		return
	end
	local info = pending and pending.info
	box:SetText("")
	AfterSave(notes.AddNote(name, text, info))
	Render()
end

local TONE_HELP = {
	hostile = "Warnings when they join your group, invite, whisper or trade you, and Unit Scanner alerts when they're nearby.",
	caution = "Warnings when they join your group, invite, whisper or trade you.",
	neutral = "Shown in their tooltip.",
	friendly = "Shown in their tooltip, with a rating if you give them one (the stars next to Liked).",
}

-- Flat chips in rows from x = PAD, wrapping at the page's edge. Returns the next free x and y.
local function PlaceChip(chip, x, y)
	if x + chip:GetWidth() > BODY_WIDTH - PAD and x > PAD then
		x = PAD
		y = y - 28
	end
	chip:SetPoint("TOPLEFT", playerPage, "TOPLEFT", x, y)
	return x + chip:GetWidth() + 4, y
end

-- Fill one star: 0, 0.5 (its left half) or 1.
local function FillStar(star, fill)
	star.fill:SetShown(fill > 0)
	star.fill:SetAtlas(notes.STAR)
	star.fill:SetWidth(STAR_SIZE)
	if fill == 0.5 then
		local left, top, _, bottom, right = star.fill:GetTexCoord()
		if left and right then
			star.fill:SetTexCoord(left, (left + right) / 2, top, bottom)
			star.fill:SetWidth(STAR_SIZE / 2)
		end
	end
end

local function ShowStars(rating)
	for index, star in ipairs(playerPage.stars.list) do
		FillStar(star, rating >= index and 1 or (rating >= index - 0.5 and 0.5 or 0))
	end
end

local function SaveRating(rating)
	local record = Current()
	local name = CurrentName()
	if name then
		if record and record.rating == rating then
			rating = nil -- clicking the rating it has clears it
		end
		AfterSave(notes.SetRating(name, rating, pending and pending.info))
		Render()
	end
end

-- Five stars, each with a left (half) and right (full) half to click.
local function CreateStars(parent)
	local stars = CreateFrame("Frame", nil, parent)
	stars:SetSize(STAR_SIZE * 5 + 8, STAR_SIZE)
	stars.list = {}
	for index = 1, 5 do
		local star = CreateFrame("Frame", nil, stars)
		star:SetSize(STAR_SIZE, STAR_SIZE)
		star:SetPoint("LEFT", (index - 1) * (STAR_SIZE + 2), 0)
		star.empty = star:CreateTexture(nil, "ARTWORK")
		star.empty:SetAllPoints()
		star.empty:SetAtlas(notes.STAR_OFF)
		star.fill = star:CreateTexture(nil, "OVERLAY")
		star.fill:SetPoint("TOPLEFT")
		star.fill:SetHeight(STAR_SIZE)
		for half = 1, 2 do
			local button = CreateFrame("Button", nil, star)
			button:SetSize(STAR_SIZE / 2, STAR_SIZE)
			button:SetPoint("LEFT", (half - 1) * STAR_SIZE / 2, 0)
			button.rating = index - 1 + half / 2
			button:SetScript("OnClick", function(self)
				SaveRating(self.rating)
			end)
			button:SetScript("OnEnter", function(self)
				ShowStars(self.rating)
				UI.ShowTooltip(self, notes.RatingWords(self.rating), "Click to rate. Click their rating again to clear it.")
			end)
			button:SetScript("OnLeave", function()
				GameTooltip_Hide()
				local record = Current()
				ShowStars(record and record.rating or 0)
			end)
		end
		table.insert(stars.list, star)
	end
	return stars
end

local function RenderChips(record, y)
	chipPool:ReleaseAll()
	local current = record and record.tone
	local x = PAD
	for _, tone in ipairs(notes.TONES) do
		local chip = chipPool:Acquire("tone", function()
			local button = UI.CreateFlatButton(playerPage, "", 24)
			button:SetScript("OnClick", function(self)
				SaveTone(self.tone)
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Render()
			end)
			button:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, notes.GetTone(self.tone).name, TONE_HELP[self.tone])
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			return button
		end)
		chip.tone = tone.key
		chip.text:SetText(notes.ToneText(tone))
		chip:SetWidth(chip.text:GetStringWidth() + 20)
		chip:SetSelected(current == tone.key)
		chip.text:SetTextColor(1, 1, 1) -- keep the label's own color (SetSelected sets gold/grey)
		x, y = PlaceChip(chip, x, y)
	end
	-- Liked: the stars after the chips.
	local stars = playerPage.stars
	stars:SetShown(current == "friendly")
	if current == "friendly" then
		stars:ClearAllPoints()
		stars:SetPoint("TOPLEFT", playerPage, "TOPLEFT", x + 10, y - 3)
		ShowStars(record.rating or 0)
	end
	return y - 28
end

-- The player's tags (click to remove), then the box to add one and suggestions.
local function RenderTags(record, key, y)
	local x = PAD
	for _, tag in ipairs(record and record.tags or {}) do
		local chip = chipPool:Acquire("tag", function()
			local button = UI.CreateFlatButton(playerPage, "", 22)
			button:SetScript("OnClick", function(self)
				notes.RemoveTag(self.key, self.tag)
			end)
			button:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, "#" .. self.tag, "Click to remove this tag.")
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			return button
		end)
		chip.key, chip.tag = key, tag
		chip.text:SetText("#" .. tag .. "  |cff808080x|r")
		chip:SetWidth(chip.text:GetStringWidth() + 20)
		x, y = PlaceChip(chip, x, y)
	end
	-- "+ Tag" after the tags, or the box for a new one in its place.
	local add, box = playerPage.addTag, playerPage.tagBox
	add:SetShown(not newTagOpen)
	box:SetShown(newTagOpen)
	add:ClearAllPoints()
	box:ClearAllPoints()
	if newTagOpen then
		if x + box:GetWidth() + 8 > BODY_WIDTH - PAD and x > PAD then
			x, y = PAD, y - 28
		end
		box:SetPoint("TOPLEFT", playerPage, "TOPLEFT", x + 6, y)
	else
		PlaceChip(add, x, y)
	end
	return y - 30
end

local function RenderLog(record, key)
	logPool:ReleaseAll()
	local scroll = playerPage.scroll
	local content = scroll.content
	local width = BODY_WIDTH - 2 * PAD - 14
	content:SetWidth(width)
	local y = 0
	local list = record and record.notes or {}
	for index = #list, 1, -1 do
		local note = list[index]
		local row = logPool:Acquire("note", function()
			local entry = CreateFrame("Frame", nil, content)
			entry.meta = MakeLabel(entry, "", "GameFontDisableSmall")
			entry.meta:SetPoint("TOPLEFT")
			entry.text = MakeLabel(entry, "", "GameFontHighlight")
			entry.text:SetPoint("TOPLEFT", 0, -14)
			entry.text:SetWordWrap(true)
			entry.delete = CreateFrame("Button", nil, entry)
			entry.delete:SetSize(16, 16)
			entry.delete:SetPoint("TOPRIGHT", 0, 2)
			entry.delete.text = MakeLabel(entry.delete, "x", "GameFontDisableSmall")
			entry.delete.text:SetPoint("CENTER")
			entry.delete:SetScript("OnClick", function(self)
				notes.DeleteNote(self.key, self.index)
			end)
			entry.delete:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, "Delete this note")
			end)
			entry.delete:SetScript("OnLeave", GameTooltip_Hide)
			return entry
		end)
		row.meta:SetText(notes.DescribeNote(note))
		row.text:SetWidth(width - 20)
		row.text:SetText(note.text)
		row.delete.key, row.delete.index = key, index
		local height = 14 + row.text:GetStringHeight() + 4
		row:SetSize(width, height)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - height - 10
	end
	if #list == 0 then
		local empty = logPool:Acquire("empty", function()
			local text = MakeLabel(content, "", "GameFontDisable")
			text:SetWidth(width)
			text:SetWordWrap(true)
			return text
		end)
		empty:SetText("No notes yet. Write what happened above and press Enter.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		y = -20
	end
	content:SetHeight(math.max(-y, 1))
	scroll:UpdateThumb()
end

local function RenderPlayer()
	local record, key = Current()
	local name = CurrentName()
	if not name then
		page = "empty"
		return
	end
	local p = playerPage
	p.name:SetText(name)
	p.name:SetTextColor(ClassColor(record and record.class or (pending and pending.info and pending.info.class)))
	if record then
		local count = #record.notes
		p.sub:SetText(string.format("Noted since %s  ·  %d %s", FormatDate(record.created or time()), count,
			count == 1 and "note" or "notes"))
	else
		p.sub:SetText("Not saved yet: pick a label, add a tag or write a note.")
	end

	local y = -64
	p.labelHeading:SetPoint("TOPLEFT", PAD, y)
	y = RenderChips(record, y - 18)
	p.tagHeading:SetPoint("TOPLEFT", PAD, y - 4)
	y = RenderTags(record, key, y - 22)

	p.noteHeading:SetPoint("TOPLEFT", PAD, y - 8)
	p.noteBox:SetPoint("TOPLEFT", PAD + 6, y - 26)
	p.hint:SetPoint("TOPLEFT", PAD, y - 54)
	y = y - 78

	p.logHeading:SetPoint("TOPLEFT", PAD, y)
	p.scroll:ClearAllPoints()
	p.scroll:SetPoint("TOPLEFT", PAD, y - 18)
	p.scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, FOOTER_HEIGHT + 6)
	RenderLog(record, key)

	p.linkButton:SetShown(record ~= nil)
	p.deleteButton:SetShown(record ~= nil)
	p.deleteButton.text:SetText(confirmDelete and "Click Again to Delete" or "Delete Player")
	p.deleteButton:SetWidth(p.deleteButton.text:GetStringWidth() + 20)
end

local function CreatePlayerPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	playerPage = p

	p.name = MakeLabel(p, "", "GameFontNormalHuge")
	p.name:SetPoint("TOPLEFT", PAD, -PAD - 2)
	p.sub = MakeLabel(p, "", "GameFontDisableSmall")
	p.sub:SetPoint("TOPLEFT", PAD, -PAD - 30)

	p.labelHeading = MakeHeading(p, "Label")
	p.stars = CreateStars(p)
	p.tagHeading = MakeHeading(p, "Tags")
	p.addTag = UI.CreateFlatButton(p, "+ Tag", 22)
	p.addTag:SetScript("OnClick", OpenTagMenu)
	p.addTag:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Tags", "Your own words to group players by, like Ninjalooter or Good tank. Pick from your tags, or make a new one. The list on the left has a section per tag.")
	end)
	p.addTag:SetScript("OnLeave", GameTooltip_Hide)
	-- The new tag's name; it closes on Enter, Escape or clicking elsewhere.
	p.tagBox = MakeEditBox(p, 150)
	p.tagBox:SetMaxLetters(30)
	p.tagBox:Hide()
	local function CloseTagBox(self)
		self:SetText("")
		newTagOpen = false
		Render()
	end
	p.tagBox:SetScript("OnEnterPressed", function(self)
		local text = self:GetText()
		self:SetText("")
		newTagOpen = false
		self:ClearFocus()
		AddTag(text)
	end)
	p.tagBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	p.tagBox:SetScript("OnEditFocusLost", function(self)
		if newTagOpen then
			CloseTagBox(self)
		end
	end)
	p.noteHeading = MakeHeading(p, "Add a note")
	p.noteBox = MakeEditBox(p, BODY_WIDTH - 2 * PAD - 80)
	p.noteBox:SetMaxLetters(500)
	p.noteBox:SetScript("OnEnterPressed", AddTypedNote)
	p.addButton = UI.CreateFlatButton(p, "Add", 22)
	p.addButton:SetPoint("LEFT", p.noteBox, "RIGHT", 6, 0)
	p.addButton:SetWidth(60)
	p.addButton:SetScript("OnClick", AddTypedNote)
	p.hint = MakeLabel(p, "Saved with today's date, the zone and your character.", "GameFontDisableSmall")
	p.logHeading = MakeHeading(p, "Notes")
	p.scroll = UI.CreateScrollArea(p)

	local footer = CreateFrame("Frame", nil, p)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	p.linkButton = UI.CreateFlatButton(footer, "Link in Chat", 22)
	p.linkButton:SetPoint("LEFT", PAD, 0)
	p.linkButton:SetScript("OnClick", function()
		local _, key = Current()
		if key then
			ns.playerNotesShare.Link(key)
		end
	end)
	p.linkButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Link in chat", "Puts [NraKit note: " .. (CurrentName() or "") .. "] in your chat box. Others with NraKit can click it to see this player's label, tags and notes, and add them to theirs (while you're online). Shift-click a player in the list does the same.")
	end)
	p.linkButton:SetScript("OnLeave", GameTooltip_Hide)
	p.deleteButton = UI.CreateFlatButton(footer, "Delete Player", 22)
	p.deleteButton:SetPoint("RIGHT", -PAD, 0)
	p.deleteButton:SetScript("OnClick", function()
		local _, key = Current()
		if not key then
			return
		end
		if not confirmDelete then
			confirmDelete = true
			Render()
			return
		end
		Select(nil)
		local record = notes.DeletePlayer(key)
		if record then
			ns:Print(string.format("Removed %s (%s). |cffffd100/nra note !undo|r brings them back.", record.name, notes.CountText(record)))
		end
	end)
	p.deleteButton:SetScript("OnLeave", function()
		if confirmDelete then
			confirmDelete = false
			Render()
		end
	end)
end

------------------------------------------------------------------------------
-- Empty page
------------------------------------------------------------------------------

local EMPTY_TEXT = table.concat({
	"Keep notes on the players you meet: who stole your node, who ninja'd the loot, who was a great healer.",
	"",
	"|cffffd100Right-click a player|r (their portrait, a party frame or their name in chat): |cffffd100Player note|r labels them in one click, or opens their notes.",
	"",
	"|cffffd100Tags|r group players your way (Ninjalooter, Good tank, Guildie): add them on a player's page, and the list gets a section per tag.",
	"",
	"|cffffd100+ Add player|r (top left) adds someone by name, or your target.",
	"",
	"|cffffd100Shift-click a player|r in the list to link their note in chat. Others with NraKit can click the link to see it and add it to theirs.",
	"",
	"|cffffd100From chat:|r /nra note Bob Stone kos #ninjalooter stole my node  (or /nra note kos ... for your target).",
	"",
	"Their label and latest note show in their tooltip. Players labelled Avoid or Kill on sight warn you when they join your group, invite, whisper or trade you, and Unit Scanner alerts you when a Kill on sight player is nearby.",
}, "\n")

local function CreateEmptyPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	emptyPage = p
	local title = MakeLabel(p, "Player Notes", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD + 8, -PAD - 8)
	local text = MakeLabel(p, EMPTY_TEXT, "GameFontHighlight")
	text:SetPoint("TOPLEFT", PAD + 8, -PAD - 36)
	text:SetWidth(BODY_WIDTH - 2 * PAD - 16)
	text:SetWordWrap(true)
	text:SetSpacing(2)
end

------------------------------------------------------------------------------
-- Add page
------------------------------------------------------------------------------

-- What's in the name box: the name to add (nil if not valid yet) and a hint.
local function CheckTypedName()
	local text = strtrim(addPage.nameBox:GetText() or "")
	if text == "" then
		return nil, "First name and surname, the way they show in game (e.g. Bob Stone)."
	end
	local name = Capitalize(text)
	if not name:find(" ", 1, true) then
		return nil, "|cffff8c26Add their surname too|r: Forever names are first name and surname (e.g. Bob Stone)."
	end
	if notes.Find(name) then
		return name, "Already in your notes: Add opens them."
	end
	return name, "Adds " .. name .. ", then you can label and tag them and write a note."
end

local function RenderAdd()
	local name, hint = CheckTypedName()
	addPage.hint:SetText(hint)
	addPage.add:SetEnabled(name ~= nil)
	addPage.add:SetAlpha(name and 1 or 0.4)
	local targetName = notes.TargetPlayer()
	addPage.target:SetShown(targetName ~= nil)
	if targetName then
		addPage.target.text:SetText("Use your target: " .. targetName)
		addPage.target:SetWidth(addPage.target.text:GetStringWidth() + 20)
	end
end

local function AddTypedPlayer()
	local name = CheckTypedName()
	if not name then
		return
	end
	local targetName, targetInfo = notes.TargetPlayer()
	local info = targetName and notes.Key(targetName) == notes.Key(name) and targetInfo or nil
	local _, key = notes.AddPlayer(name, info)
	addPage.nameBox:SetText("")
	addPage.nameBox:ClearFocus()
	Select(key)
	Render()
	playerPage.noteBox:SetFocus()
end

local function CreateAddPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	addPage = p
	local title = MakeLabel(p, "Add a player", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD - 2)
	local heading = MakeHeading(p, "Name")
	heading:SetPoint("TOPLEFT", PAD, -60)
	p.nameBox = MakeEditBox(p, 260)
	p.nameBox:SetPoint("TOPLEFT", PAD + 6, -78)
	p.nameBox:SetMaxLetters(60)
	p.nameBox:SetScript("OnEnterPressed", AddTypedPlayer)
	p.nameBox:HookScript("OnTextChanged", RenderAdd)
	p.add = UI.CreateFlatButton(p, "Add", 22)
	p.add:SetWidth(60)
	p.add:SetPoint("LEFT", p.nameBox, "RIGHT", 6, 0)
	p.add:SetScript("OnClick", AddTypedPlayer)
	p.hint = MakeLabel(p, "", "GameFontDisableSmall")
	p.hint:SetPoint("TOPLEFT", PAD, -106)
	p.hint:SetWidth(BODY_WIDTH - 2 * PAD)
	p.hint:SetWordWrap(true)
	p.target = UI.CreateFlatButton(p, "", 22)
	p.target:SetPoint("TOPLEFT", PAD, -132)
	p.target:SetScript("OnClick", function()
		p.nameBox:SetText(notes.TargetPlayer() or "")
		p.nameBox:SetFocus()
	end)
	local more = MakeLabel(p, "You can also right-click a player (portrait, party frame, chat name) and pick Player note, or type /nra note Bob Stone kos stole my node.", "GameFontDisableSmall")
	more:SetPoint("TOPLEFT", PAD, -172)
	more:SetWidth(BODY_WIDTH - 2 * PAD)
	more:SetWordWrap(true)
end

------------------------------------------------------------------------------
-- Tags page
------------------------------------------------------------------------------

local function CommitRename(box)
	if box.tag and notes.CleanTag(box:GetText()) then
		notes.RenameTag(box.tag, box:GetText())
	end
end

local function CreateTagRow(content)
	local row = CreateFrame("Frame", nil, content)
	row:SetHeight(30)
	row.nameBox = MakeEditBox(row, 200)
	row.nameBox:SetPoint("LEFT", 6, 0)
	row.nameBox:SetMaxLetters(30)
	row.nameBox:SetScript("OnEnterPressed", function(self)
		CommitRename(self)
		self:ClearFocus()
	end)
	row.nameBox:SetScript("OnEditFocusLost", CommitRename)
	row.count = MakeLabel(row, "", "GameFontDisableSmall")
	row.count:SetPoint("LEFT", row.nameBox, "RIGHT", 12, 0)
	row.delete = CreateFrame("Button", nil, row)
	row.delete:SetSize(18, 18)
	row.delete:SetPoint("RIGHT", -2, 0)
	row.delete.text = MakeLabel(row.delete, "x", "GameFontDisable")
	row.delete.text:SetPoint("CENTER")
	row.delete:SetScript("OnClick", function()
		notes.DeleteTag(row.tag)
	end)
	row.delete:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Delete this tag", string.format("Takes #%s off %s. Their notes stay.", row.tag,
			row.players == 1 and "1 player" or (row.players .. " players")))
	end)
	row.delete:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function RenderTagsPage()
	tagPool:ReleaseAll()
	local p = tagsPage
	local content = p.scroll.content
	local width = BODY_WIDTH - 2 * PAD - 14
	content:SetWidth(width)
	local y = 0
	local tags = notes.AllTags()
	for _, tag in ipairs(tags) do
		local row = tagPool:Acquire("row", function()
			return CreateTagRow(content)
		end)
		row.tag, row.players = tag.name, tag.count
		row.nameBox.tag = tag.name
		row.nameBox:SetText(tag.name)
		row.count:SetText(tag.count == 1 and "1 player" or (tag.count .. " players"))
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - 32
	end
	if #tags == 0 then
		local empty = tagPool:Acquire("empty", function()
			local text = MakeLabel(content, "", "GameFontDisable")
			text:SetWidth(width)
			text:SetWordWrap(true)
			return text
		end)
		empty:SetText("No tags yet. Add one above, on a player's page (+ Tag), or with /nra note Bob Stone #tank.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		y = -20
	end
	content:SetHeight(math.max(-y, 1))
	p.scroll:UpdateThumb()
end

local TAGS_TEXT = "Tags are your own words for grouping players (Ninjalooter, Good tank, Guildie). A player can have any number, and the list on the left has a section for each tag in use. Add tags here, rename them (renaming one to another tag's name merges them) or delete them."

local function CreateTagsPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	tagsPage = p
	local title = MakeLabel(p, "Tags", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD - 2)
	local text = MakeLabel(p, TAGS_TEXT, "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", PAD, -PAD - 28)
	text:SetWidth(BODY_WIDTH - 2 * PAD)
	text:SetWordWrap(true)

	local function CreateTyped()
		if notes.CreateTag(p.newBox:GetText()) then
			p.newBox:SetText("")
		end
	end
	p.newBox = MakeEditBox(p, 200)
	p.newBox:SetPoint("TOPLEFT", PAD + 6, -96)
	p.newBox:SetMaxLetters(30)
	p.newBox:SetScript("OnEnterPressed", CreateTyped)
	p.newButton = UI.CreateFlatButton(p, "+ New Tag", 22)
	p.newButton:SetPoint("LEFT", p.newBox, "RIGHT", 6, 0)
	p.newButton:SetScript("OnClick", CreateTyped)

	p.scroll = UI.CreateScrollArea(p)
	p.scroll:SetPoint("TOPLEFT", PAD, -130)
	p.scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, PAD)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

Render = function()
	if not frame or not frame:IsShown() then
		return
	end
	if page == "player" and not CurrentName() then
		page = "empty"
	end
	if page == "player" then
		RenderPlayer()
	elseif page == "tags" then
		RenderTagsPage()
	elseif page == "add" then
		RenderAdd()
	end
	playerPage:SetShown(page == "player")
	emptyPage:SetShown(page == "empty")
	tagsPage:SetShown(page == "tags")
	addPage:SetShown(page == "add")
	RenderSidebar()
end

local function CreateNotesWindow()
	frame = UI.CreateWindow("NraKitPlayerNotesFrame", "Player Notes", WIDTH, HEIGHT, SIDEBAR_WIDTH, "notes")

	addButton = UI.CreateFlatButton(frame.sidebar, "+  Add Player", 28)
	addButton:SetWidth(SIDEBAR_WIDTH - 2 * PAD)
	addButton:SetPoint("TOPLEFT", PAD, -PAD)
	addButton:SetSelected(true)
	addButton:SetScript("OnClick", function()
		Select(nil)
		page = "add"
		Render()
		addPage.nameBox:SetFocus()
	end)

	searchBox = UI.CreateSearchBox(frame.sidebar, SIDEBAR_WIDTH - 2 * PAD - 6, function(text)
		query = text
		typedName = strtrim(searchBox:GetText() or "")
		Render()
	end)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD - 40)
	searchBox:HookScript("OnEnterPressed", function()
		-- Enter on a new name adds it; on a match opens the first one.
		if typedName == "" then
			return
		end
		local record, key = notes.Find(typedName)
		if record then
			Select(key)
		else
			Select(nil)
			pending = { name = Capitalize(typedName) }
			page = "player"
		end
		Render()
	end)

	-- A filter chip per label, sharing the row.
	filterChips = {}
	local chipX, chipGap = PAD, 4
	local chipWidth = (SIDEBAR_WIDTH - 2 * PAD - 3 * chipGap) / 4
	for _, tone in ipairs(notes.TONES) do
		local chip = UI.CreateFlatButton(frame.sidebar, tone.short, 20)
		chip.tone = tone.key
		chip:SetWidth(chipWidth)
		chip:SetPoint("TOPLEFT", chipX, -PAD - 72)
		chipX = chipX + chipWidth + chipGap
		chip:SetScript("OnClick", function(self)
			toneFilter[self.tone] = not toneFilter[self.tone] or nil
			Render()
		end)
		chip:SetScript("OnEnter", function(self)
			local count = 0
			for _, record in pairs(notes.GetData().players) do
				if record.tone == self.tone then
					count = count + 1
				end
			end
			UI.ShowTooltip(self, notes.GetTone(self.tone).name, string.format(
				"Show only players labelled %s (%d). Turn on more than one to see them together.",
				notes.GetTone(self.tone).name, count))
		end)
		chip:SetScript("OnLeave", GameTooltip_Hide)
		table.insert(filterChips, chip)
	end

	sidebarScroll = UI.CreateScrollArea(frame.sidebar)
	sidebarScroll:SetPoint("TOPLEFT", PAD, -PAD - 100)
	sidebarScroll:SetPoint("BOTTOMRIGHT", -PAD, PAD + 36)

	tagsButton = UI.CreateNavButton(frame.sidebar, SIDEBAR_WIDTH - 2 * PAD, 28, "Tags")
	tagsButton:SetPoint("BOTTOMLEFT", PAD, PAD)
	tagsButton:SetScript("OnClick", function()
		page = "tags"
		Render()
	end)

	CreatePlayerPage(frame.body)
	CreateEmptyPage(frame.body)
	CreateTagsPage(frame.body)
	CreateAddPage(frame.body)

	frame:HookScript("OnShow", Render)
	frame:HookScript("OnHide", function()
		wipe(toneFilter) -- a forgotten filter would make the list look broken next time
	end)
	notes.onChanged = Render
end

-- Opens the window: on a player (name, optional { guid, class }) or, with no name,
-- toggles it on the last page.
function ns:OpenPlayerNotes(name, info)
	if not ns:IsModuleEnabled("playerNotes") then
		ns:Print("Turn on Player Notes first (/nra).")
		return
	end
	if not frame then
		CreateNotesWindow()
	end
	if not name then
		frame:SetShown(not frame:IsShown())
		return
	end
	local record, key = notes.Find(name, info and info.guid)
	if record then
		local _
		_, key = notes.Ensure(name, info) -- learns the GUID/class, follows a rename
		Select(key)
	else
		Select(nil)
		pending = { name = notes.Display(name), info = info }
		page = "player"
	end
	if frame:IsShown() then
		Render()
	else
		frame:Show()
	end
	playerPage.noteBox:SetFocus()
end

UI.RegisterTab({
	key = "notes", label = "Notes", menuLabel = "Player Notes", order = 4, frameName = "NraKitPlayerNotesFrame",
	open = function()
		ns:OpenPlayerNotes()
	end,
	module = "playerNotes",
})

ns:AddOptionsButton("playerNotes", "Open Player Notes", "Everyone you have notes on, and your tags (/nra note).", function()
	ns:OpenPlayerNotes()
end)
