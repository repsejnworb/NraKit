local _, ns = ...

-- Player notes window (/nra note, or Player note... in a player's right-click menu).
--
-- Sidebar: "+ Add player" (a page with a name box, and your target as a shortcut),
-- search (name, label or note text) and every noted player, newest change first;
-- typing a name nobody has offers "+ Add <name>" too. At the bottom, Labels.
--
-- A player's page: their label as chips (one click to change), a box to add a note
-- (saved with the date, zone and your character) and the log, newest first. A player
-- opened from a menu who has no notes yet isn't saved until a label or note is added.
--
-- Labels page: rename, change tone or color, delete, add. The tone decides what a
-- label does (PlayerNotes.lua): Hostile warns and alerts, Caution warns.

local UI = ns.UI
local notes = ns.playerNotes
local WIDTH, HEIGHT = 720, 520
local SIDEBAR_WIDTH = 230
local PAD = UI.PAD
local FOOTER_HEIGHT = 34
local BODY_WIDTH = WIDTH - SIDEBAR_WIDTH

local frame, searchBox, sidebarScroll, labelsButton, addButton
local playerPage, emptyPage, labelsPage, addPage
local sidebarPool, chipPool, logPool, labelPool = UI.CreatePool(), UI.CreatePool(), UI.CreatePool(), UI.CreatePool()

local page = "empty" -- "player", "empty", "add" or "labels"
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

local function ColorText(text, r, g, b)
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
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

local function Matches(record)
	if query == "" then
		return true
	end
	local function Has(text)
		return text and text:lower():find(query, 1, true) ~= nil
	end
	if Has(record.name) or Has(notes.RecordLabel(record).name) then
		return true
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

local function RenderSidebar()
	sidebarPool:ReleaseAll()
	local content = sidebarScroll.content
	local width = SIDEBAR_WIDTH - 2 * PAD
	local y = 0

	local function AddButton()
		local button = sidebarPool:Acquire("nav", function()
			local nav = UI.CreateNavButton(content, width, 38, "")
			nav:SetScript("OnClick", function(self)
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

	-- A typed name nobody has yet: offer to add it.
	if typedName ~= "" and not notes.Find(typedName) then
		local add = AddButton()
		add.key, add.addName = nil, Capitalize(typedName)
		add.text:SetText("+ Add " .. add.addName)
		add:SetSubtext("New player")
		add.count:SetText("")
		add:SetSelected(pending ~= nil and pending.name == add.addName, UI.ACCENT)
	end

	local shown = 0
	for _, entry in ipairs(notes.All()) do
		if Matches(entry.record) then
			shown = shown + 1
			local record = entry.record
			local button = AddButton()
			button.key, button.addName = entry.key, nil
			button.text:SetText(record.name)
			button:SetSubtext(notes.LabelText(notes.RecordLabel(record)))
			button.count:SetText(#record.notes > 0 and tostring(#record.notes) or "")
			button:SetSelected(page == "player" and selectedKey == entry.key, { ClassColor(record.class) })
		end
	end

	if shown == 0 and typedName == "" then
		local empty = sidebarPool:Acquire("empty", function()
			local text = MakeLabel(content, "", "GameFontDisableSmall")
			text:SetWidth(width - 8)
			return text
		end)
		empty:SetText(query ~= "" and "Nobody matches." or "No notes yet.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 4)
		y = y - 24
	end
	content:SetSize(width, -y)
	sidebarScroll:UpdateThumb()
	labelsButton:SetSelected(page == "labels")
end

------------------------------------------------------------------------------
-- Player page
------------------------------------------------------------------------------

local function SaveLabel(labelID)
	local name = CurrentName()
	if not name then
		return
	end
	local info = pending and pending.info
	AfterSave(notes.SetLabel(name, labelID, info))
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

local function RenderChips(record, y)
	chipPool:ReleaseAll()
	local current = record and record.label
	local x, maxX = PAD, BODY_WIDTH - PAD
	for _, label in ipairs(notes.SortedLabels()) do
		local chip = chipPool:Acquire("chip", function()
			local button = UI.CreateFlatButton(playerPage, "", 24)
			button:SetScript("OnClick", function(self)
				SaveLabel(self.labelID)
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Render()
			end)
			button:SetScript("OnEnter", function(self)
				local tone = notes.Tone(notes.GetLabel(self.labelID))
				local what = tone.scan and "Warnings, and Unit Scanner alerts when they're nearby."
					or tone.warn and "Warnings when they join your group, invite, whisper or trade you."
					or "Shown in their tooltip."
				UI.ShowTooltip(self, tone.name, what)
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			return button
		end)
		chip.labelID = label.id
		chip.text:SetText(notes.LabelText(label))
		chip:SetWidth(chip.text:GetStringWidth() + 20)
		chip:SetSelected(current == label.id)
		-- Keep the label's own color (SetSelected sets gold/grey).
		chip.text:SetTextColor(1, 1, 1)
		if x + chip:GetWidth() > maxX and x > PAD then
			x = PAD
			y = y - 28
		end
		chip:SetPoint("TOPLEFT", playerPage, "TOPLEFT", x, y)
		x = x + chip:GetWidth() + 4
	end
	return y - 28
end

local function DescribeNote(note)
	local parts = { FormatDate(note.time) }
	if note.zone then
		table.insert(parts, note.zone)
	end
	if note.by then
		table.insert(parts, "by " .. note.by)
	end
	return table.concat(parts, "  ·  ")
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
		row.meta:SetText(DescribeNote(note))
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
		p.sub:SetText("Not saved yet: pick a label or add a note.")
	end

	local y = -64
	p.labelHeading:SetPoint("TOPLEFT", PAD, y)
	y = RenderChips(record, y - 18)

	p.noteHeading:SetPoint("TOPLEFT", PAD, y - 8)
	p.noteBox:SetPoint("TOPLEFT", PAD + 6, y - 26)
	p.hint:SetPoint("TOPLEFT", PAD, y - 54)
	y = y - 78

	p.logHeading:SetPoint("TOPLEFT", PAD, y)
	p.scroll:ClearAllPoints()
	p.scroll:SetPoint("TOPLEFT", PAD, y - 18)
	p.scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, FOOTER_HEIGHT + 6)
	RenderLog(record, key)

	p.deleteButton:SetShown(record ~= nil)
	p.deleteButton.text:SetText(confirmDelete and "Click again to delete" or "Delete player")
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
	p.deleteButton = UI.CreateFlatButton(footer, "Delete player", 22)
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
		notes.DeletePlayer(key)
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
	"|cffffd100Right-click a player|r (their portrait, a party frame or their name in chat) and pick |cffffd100Player note...|r, or set a label straight from |cffffd100Player label|r.",
	"",
	"|cffffd100+ Add player|r (top left) adds someone by name, or your target.",
	"",
	"|cffffd100From chat:|r /nra note Bob Stone kos stole my node  (or /nra note kos ... for your target).",
	"",
	"Their label and latest note show in their tooltip. Players labelled Avoid or Kill on sight warn you when they join your group, invite, whisper or trade you, and Unit Scanner alerts you when a Kill on sight player is nearby.",
}, "\n")

local function CreateEmptyPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	emptyPage = p
	local title = MakeLabel(p, "Player notes", "GameFontNormalLarge")
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
	return name, "Adds " .. name .. ", then you can label them and write a note."
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
	local more = MakeLabel(p, "You can also right-click a player (portrait, party frame, chat name) and pick Player note..., or type /nra note Bob Stone kos stole my node.", "GameFontDisableSmall")
	more:SetPoint("TOPLEFT", PAD, -172)
	more:SetWidth(BODY_WIDTH - 2 * PAD)
	more:SetWordWrap(true)
end

------------------------------------------------------------------------------
-- Labels page
------------------------------------------------------------------------------

local function PlayersWithLabel(id)
	local count = 0
	for _, record in pairs(notes.GetData().players) do
		if record.label == id then
			count = count + 1
		end
	end
	return count
end

local function PickColor(label)
	if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
		return
	end
	local r, g, b = notes.LabelColor(label)
	local id = label.id
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		swatchFunc = function()
			local newR, newG, newB = ColorPickerFrame:GetColorRGB()
			notes.SetLabelColor(id, { newR, newG, newB })
		end,
		cancelFunc = function()
			notes.SetLabelColor(id, { r, g, b })
		end,
	})
end

local function CommitName(box)
	if box.labelID then
		notes.RenameLabel(box.labelID, box:GetText())
	end
end

local function CreateLabelRow(content)
	local row = CreateFrame("Frame", nil, content)
	row:SetHeight(30)
	row.swatch = CreateFrame("Button", nil, row)
	row.swatch:SetSize(16, 16)
	row.swatch:SetPoint("LEFT", 2, 0)
	row.swatch.color = row.swatch:CreateTexture(nil, "ARTWORK")
	row.swatch.color:SetAllPoints()
	row.swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.swatch:SetScript("OnClick", function(self, mouseButton)
		local label = notes.GetLabel(self.labelID)
		if not label then
			return
		end
		if mouseButton == "RightButton" then
			notes.SetLabelColor(label.id, nil)
		else
			PickColor(label)
		end
	end)
	row.swatch:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Color", "Click to pick a color. Right-click for the tone's color.")
	end)
	row.swatch:SetScript("OnLeave", GameTooltip_Hide)

	row.nameBox = MakeEditBox(row, 150)
	row.nameBox:SetPoint("LEFT", row.swatch, "RIGHT", 12, 0)
	row.nameBox:SetMaxLetters(30)
	row.nameBox:SetScript("OnEnterPressed", function(self)
		CommitName(self)
		self:ClearFocus()
	end)
	row.nameBox:SetScript("OnEditFocusLost", CommitName)

	row.tones = {}
	local anchor = row.nameBox
	for _, tone in ipairs(notes.TONES) do
		local chip = UI.CreateFlatButton(row, tone.name, 20)
		chip.tone = tone.key
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == row.nameBox and 10 or 2, 0)
		chip:SetScript("OnClick", function(self)
			notes.SetLabelTone(row.labelID, self.tone)
		end)
		anchor = chip
		table.insert(row.tones, chip)
	end

	row.count = MakeLabel(row, "", "GameFontDisableSmall")
	row.count:SetPoint("LEFT", anchor, "RIGHT", 8, 0)

	row.delete = CreateFrame("Button", nil, row)
	row.delete:SetSize(18, 18)
	row.delete:SetPoint("RIGHT", -2, 0)
	row.delete.text = MakeLabel(row.delete, "x", "GameFontDisable")
	row.delete.text:SetPoint("CENTER")
	row.delete:SetScript("OnClick", function()
		notes.DeleteLabel(row.labelID)
	end)
	row.delete:SetScript("OnEnter", function(self)
		local count = PlayersWithLabel(row.labelID)
		UI.ShowTooltip(self, "Delete this label", count > 0
			and string.format("Its %d %s get the first other label of the same tone.", count, count == 1 and "player" or "players")
			or nil)
	end)
	row.delete:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function RenderLabels()
	labelPool:ReleaseAll()
	local p = labelsPage
	local content = p.scroll.content
	local width = BODY_WIDTH - 2 * PAD - 14
	content:SetWidth(width)
	local y = 0
	local lastTone
	for _, label in ipairs(notes.SortedLabels()) do
		local tone = notes.Tone(label)
		if tone.key ~= lastTone then
			lastTone = tone.key
			local heading = labelPool:Acquire("heading", function()
				return MakeHeading(content, "")
			end)
			heading:SetText(ColorText(tone.name:upper(), unpack(tone.color)))
			heading:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y - 6)
			y = y - 24
		end
		local row = labelPool:Acquire("row", function()
			return CreateLabelRow(content)
		end)
		row.labelID = label.id
		row.swatch.labelID = label.id
		row.nameBox.labelID = label.id
		row.swatch.color:SetColorTexture(notes.LabelColor(label))
		row.nameBox:SetText(label.name)
		for _, chip in ipairs(row.tones) do
			chip:SetSelected(chip.tone == label.tone)
		end
		local count = PlayersWithLabel(label.id)
		row.count:SetText(count > 0 and (count .. (count == 1 and " player" or " players")) or "")
		row.delete:SetEnabled(notes.CanDeleteLabel(label.id))
		row.delete:SetAlpha(notes.CanDeleteLabel(label.id) and 1 or 0.3)
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		y = y - 32
	end
	content:SetHeight(-y)
	p.scroll:UpdateThumb()
end

local LABELS_TEXT = "Each label has a tone, and the tone decides what it does. |cffff4033Hostile|r: warnings, and Unit Scanner alerts when they're nearby. |cffff8c26Caution|r: warnings when they join your group, invite, whisper or trade you. Neutral and Friendly: shown in tooltips only."

local function CreateLabelsPage(body)
	local p = CreateFrame("Frame", nil, body)
	p:SetAllPoints()
	labelsPage = p
	local title = MakeLabel(p, "Labels", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD - 2)
	local text = MakeLabel(p, LABELS_TEXT, "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", PAD, -PAD - 28)
	text:SetWidth(BODY_WIDTH - 2 * PAD)
	text:SetWordWrap(true)

	p.scroll = UI.CreateScrollArea(p)
	p.scroll:SetPoint("TOPLEFT", PAD, -96)
	p.scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, FOOTER_HEIGHT + 6)

	local footer = CreateFrame("Frame", nil, p)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	local add = UI.CreateFlatButton(footer, "+ New label", 22)
	add:SetPoint("LEFT", PAD, 0)
	add:SetScript("OnClick", function()
		notes.AddLabel("New label", "neutral")
	end)
	local hint = MakeLabel(footer, "Click a name to rename it.", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -PAD, 0)
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
	elseif page == "labels" then
		RenderLabels()
	elseif page == "add" then
		RenderAdd()
	end
	playerPage:SetShown(page == "player")
	emptyPage:SetShown(page == "empty")
	labelsPage:SetShown(page == "labels")
	addPage:SetShown(page == "add")
	RenderSidebar()
end

local function CreateNotesWindow()
	frame = UI.CreateWindow("NraKitPlayerNotesFrame", "Player notes", WIDTH, HEIGHT, SIDEBAR_WIDTH)

	addButton = UI.CreateFlatButton(frame.sidebar, "+  Add player", 28)
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

	sidebarScroll = UI.CreateScrollArea(frame.sidebar)
	sidebarScroll:SetPoint("TOPLEFT", PAD, -PAD - 72)
	sidebarScroll:SetPoint("BOTTOMRIGHT", -PAD, PAD + 36)

	labelsButton = UI.CreateNavButton(frame.sidebar, SIDEBAR_WIDTH - 2 * PAD, 28, "Labels")
	labelsButton:SetPoint("BOTTOMLEFT", PAD, PAD)
	labelsButton:SetScript("OnClick", function()
		page = "labels"
		Render()
	end)

	CreatePlayerPage(frame.body)
	CreateEmptyPage(frame.body)
	CreateLabelsPage(frame.body)
	CreateAddPage(frame.body)

	frame:SetScript("OnShow", Render)
	notes.onChanged = Render
end

-- Opens the window: on a player (name, optional { guid, class }) or, with no name,
-- toggles it on the last page.
function ns:OpenPlayerNotes(name, info)
	if not ns:IsModuleEnabled("playerNotes") then
		ns:Print("Turn on Player notes first (/nra).")
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
