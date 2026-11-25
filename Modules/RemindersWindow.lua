local _, ns = ...

-- The Reminders window (/nra remind): a box to write a new one (same words as the command),
-- then your reminders in sections: Now (due, not ticked off), Waiting (with when they come
-- due), For your other characters (ones you left them) and Done (folded; the last few).
--
-- Tick a box to mark one done (untick to bring it back), click the text to edit it,
-- right-click for more (remind me again later, delete).

local UI = ns.UI
local reminders = ns.reminders
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 30
local HEADER_HEIGHT = 26
local TOP_HEIGHT = 48
local FOOTER_HEIGHT = 28

local HELP = "Write one in the box above (the same words as in chat), or in chat with /nra remind:\n"
	.. "  |cffffd100/nra remind <text>|r - for your next login\n"
	.. "  |cffffd100/nra remind 30m <text>|r - in 30 minutes (s, m, h, d: 2d, 1h30m)\n"
	.. "  |cffffd100/nra remind in Darkshore: <text>|r - when you enter a zone or subzone\n"
	.. "  |cffffd100/nra remind at 30: <text>|r - when you reach a level\n"
	.. "  |cffffd100/nra remind @Alt: <text>|r - on another character's next login (@Alt at 20: works too)\n\n"
	.. "Shift-clicked items and quests work in chat."

local frame, addBox, scroll, footerLeft, editBox, helpButton, showButton
local pool = UI.CreatePool()
local editingID
local doneOpen = false -- the Done section, folded until you open it

local Render

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function AddFromBox()
	local text = strtrim(addBox:GetText() or "")
	if text == "" then
		return
	end
	if reminders.OnSlashCommand(text) then
		addBox:SetText("") -- kept when it couldn't be read, to fix it
	end
	addBox:ClearFocus()
	Render()
end

local function EditText(id)
	editingID = id
	Render()
	editBox:SetFocus()
end

local function SaveText()
	if editingID then
		local id = editingID
		editingID = nil
		reminders.SetText(id, editBox:GetText()) -- redraws
	end
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function AcquireRow(content)
	return pool:Acquire("row", function()
		local row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		reminders.EnableLinks(row)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		row.check = reminders.CreateCheck(row, function(box)
			reminders.SetDone(box:GetParent().reminder.id, box:GetChecked())
		end)
		row.check:SetPoint("LEFT", 8, 0)
		row.when = MakeLabel(row, "", "GameFontHighlightSmall")
		row.when:SetPoint("RIGHT", -12, 0)
		row.when:SetJustifyH("RIGHT")
		row.text = MakeLabel(row, "")
		row.text:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
		row.text:SetPoint("RIGHT", row.when, "LEFT", -16, 0)
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				reminders.OpenRowMenu(self, self.reminder)
			else
				EditText(self.reminder.id)
			end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.reminder.text, 1, 1, 1, true)
			GameTooltip:AddLine("Click to edit, right-click for more", 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		return row
	end)
end

local function FillRow(row, reminder, when, index)
	row.reminder, row.reminderID = reminder, reminder.id
	local done = reminder.state == "done"
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.check:SetChecked(done)
	row.text:SetText(reminder.text)
	row.text:SetAlpha(done and 0.5 or 1)
	row.text:SetShown(editingID ~= reminder.id)
	row.when:SetText(when)
	row.when:SetTextColor(unpack(reminder.state == "due" and UI.GOLD or UI.TEXT_DIM))
	if editingID == reminder.id then
		editBox:ClearAllPoints()
		editBox:SetPoint("LEFT", row.check, "RIGHT", 14, 0)
		editBox:SetPoint("RIGHT", row.when, "LEFT", -16, 0)
		if not editBox:HasFocus() then
			editBox:SetText(reminder.text)
		end
		editBox:Show()
	end
end

local function AddHeader(content, label, count, y, width, onClick)
	local header = pool:Acquire("header", function()
		local button = CreateFrame("Button", nil, content)
		button:SetHeight(HEADER_HEIGHT)
		UI.AddLine(button, "BOTTOM")
		button.arrow = button:CreateTexture(nil, "ARTWORK")
		button.arrow:SetSize(12, 12)
		button.arrow:SetPoint("LEFT", 4, 0)
		button.arrow:SetAtlas("common-icon-forwardarrow")
		button.text = MakeLabel(button, "", "GameFontNormal")
		button.text:SetPoint("LEFT", 6, 0)
		button.count = MakeLabel(button, "", "GameFontDisable")
		button.count:SetPoint("LEFT", button.text, "RIGHT", 8, 0)
		return button
	end)
	header.text:SetText(label)
	header.text:SetTextColor(unpack(UI.ACCENT))
	header.count:SetText(count)
	header.text:ClearAllPoints()
	if onClick then
		header.arrow:Show()
		header.arrow:SetRotation(doneOpen and -math.pi / 2 or 0)
		header.text:SetPoint("LEFT", header.arrow, "RIGHT", 6, 0)
	else
		header.arrow:Hide()
		header.text:SetPoint("LEFT", 6, 0)
	end
	header:SetScript("OnClick", onClick)
	header:SetWidth(width)
	header:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
end

local function Message(content, text, y)
	local message = pool:Acquire("message", function()
		local fontString = MakeLabel(content, "", "GameFontDisable")
		fontString:SetSpacing(3)
		return fontString
	end)
	message:SetText(text)
	message:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y)
	message:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	local _, lines = text:gsub("\n", "")
	return (lines + 1) * 17 + 12 -- its height, roughly
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

-- The sections: { label, rows = { { reminder, when } }, foldable }.
local function Collect()
	local now, waiting, others, done = {}, {}, {}, {}
	for _, reminder in ipairs(reminders.List()) do
		if reminder.state == "due" then
			table.insert(now, { reminder = reminder, when = reminders.DueNote(reminder) })
		elseif reminder.state == "waiting" then
			table.insert(waiting, { reminder = reminder, when = reminders.Describe(reminder) })
		else
			table.insert(done, { reminder = reminder, when = reminder.doneAt and date("Done %b %d", reminder.doneAt) or "Done" })
		end
	end
	local me = ns:PlayerName()
	for name, character in pairs(NraKitDB.remindersData and NraKitDB.remindersData.characters or {}) do
		if name ~= me then
			for _, reminder in ipairs(character.list) do
				if reminder.from == me and reminder.state ~= "done" then
					local when = reminder.state == "due" and "due, not seen yet" or reminders.Describe(reminder):gsub("^%u", string.lower)
					table.insert(others, { reminder = reminder, when = name .. ": " .. when })
				end
			end
		end
	end
	local function ByID(a, b)
		return a.reminder.id < b.reminder.id
	end
	table.sort(now, ByID)
	table.sort(waiting, ByID)
	table.sort(others, ByID)
	table.sort(done, function(a, b)
		return (a.reminder.doneAt or 0) > (b.reminder.doneAt or 0)
	end)
	return {
		{ label = "Now", rows = now },
		{ label = "Waiting", rows = waiting },
		{ label = "For your other characters", rows = others },
		{ label = "Done", rows = done, foldable = true },
	}
end

function Render()
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	editBox:Hide()
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local sections = Collect()
	local y, open, total = -PAD, 0, 0
	for _, section in ipairs(sections) do
		total = total + #section.rows
	end
	if total == 0 then
		y = y - Message(content, "No reminders yet.\n\n" .. HELP, y - 4)
	elseif helpButton.open then
		y = y - Message(content, HELP, y - 4) - 4
	end
	helpButton:SetShown(total > 0)
	for _, section in ipairs(sections) do
		if #section.rows > 0 then
			local onClick = section.foldable and function()
				doneOpen = not doneOpen
				Render()
			end
			AddHeader(content, section.label, #section.rows, y, width, onClick)
			y = y - HEADER_HEIGHT - 2
			if not section.foldable or doneOpen then
				for index, entry in ipairs(section.rows) do
					local row = AcquireRow(content)
					row:SetWidth(width)
					row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
					FillRow(row, entry.reminder, entry.when, index)
					y = y - ROW_HEIGHT
				end
			end
			y = y - 8
			if not section.foldable then
				open = open + #section.rows
			end
		end
	end
	content:SetHeight(-y + PAD)
	scroll:SetScroll(scroll:GetVerticalScroll())
	footerLeft:SetText(string.format("%d open", open))
	showButton:SetShown(#reminders.Due() > 0)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateWindow()
	frame = UI.CreateWindow("NraKitRemindersFrame", "Reminders", WIDTH, HEIGHT, 0, "reminders")
	local body = frame.body

	addBox = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
	addBox:SetHeight(22)
	addBox:SetPoint("TOPLEFT", PAD + 8, -PAD - 1)
	addBox:SetPoint("RIGHT", -PAD - 100, 0)
	addBox:SetAutoFocus(false)
	addBox:SetMaxLetters(255)
	addBox:SetScript("OnEnterPressed", AddFromBox)
	addBox:SetScript("OnEscapePressed", addBox.ClearFocus)
	addBox.placeholder = MakeLabel(addBox, "New reminder: text, or 30m / in <zone>: / at <level>: / @<character>: first", "GameFontDisable")
	addBox.placeholder:SetPoint("LEFT", 2, 0)
	addBox:HookScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	local add = UI.CreateFlatButton(body, "Add", 22)
	add:SetWidth(56)
	add:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
	add:SetScript("OnClick", AddFromBox)
	helpButton = UI.CreateHelpButton(body, "How to write reminders", Render)
	helpButton:SetPoint("TOPRIGHT", -PAD, -PAD)

	local topLine = body:CreateTexture(nil, "BORDER")
	topLine:SetColorTexture(unpack(UI.EDGE))
	topLine:SetPoint("TOPLEFT", 0, -TOP_HEIGHT)
	topLine:SetPoint("TOPRIGHT", 0, -TOP_HEIGHT)
	topLine:SetHeight(1)

	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - 15)

	editBox = CreateFrame("EditBox", nil, scroll.content, "InputBoxTemplate")
	editBox:SetHeight(20)
	editBox:SetAutoFocus(false)
	editBox:SetMaxLetters(255)
	editBox:Hide()
	editBox:SetScript("OnEnterPressed", function(self)
		SaveText()
		self:ClearFocus()
	end)
	editBox:SetScript("OnEscapePressed", function(self)
		editingID = nil -- not saved
		self:ClearFocus()
		Render()
	end)
	editBox:SetScript("OnEditFocusLost", SaveText)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerLeft = MakeLabel(footer, "", "GameFontHighlightSmall")
	footerLeft:SetPoint("LEFT", PAD, 0)
	showButton = UI.CreateFlatButton(footer, "Show on screen", 20)
	showButton:SetPoint("LEFT", footerLeft, "RIGHT", 12, 0)
	showButton:SetScript("OnClick", function()
		reminders.ShowTracker()
	end)
	showButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Show on screen", "Shows the due reminders on screen again, after you hid or folded the list (also /nra remind show, or a key under Key Bindings > NraKit).")
	end)
	showButton:SetScript("OnLeave", GameTooltip_Hide)
	local hint = MakeLabel(footer, "Tick when done. Click to edit, right-click for more", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -PAD, 0)

	frame:HookScript("OnShow", Render)
	frame:HookScript("OnHide", function()
		editingID = nil
		helpButton:SetOpen(false)
	end)
	reminders.onChanged = Render
end

-- Toggles the window; with an id, shows it editing that reminder.
function ns:OpenReminders(editID)
	if not frame then
		CreateWindow()
	end
	if editID then
		frame:Show()
		EditText(editID)
	else
		frame:SetShown(not frame:IsShown())
	end
end

UI.RegisterTab({
	key = "reminders", label = "Reminders", menuLabel = "Reminders", order = 7, frameName = "NraKitRemindersFrame",
	open = function()
		if not frame then
			CreateWindow()
		end
		frame:Show()
	end,
	module = "reminders",
})

ns:AddOptionsButton("reminders", "Open reminders", "Your reminders (/nra remind).", function()
	ns:OpenReminders()
end)
