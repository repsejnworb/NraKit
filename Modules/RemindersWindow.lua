local _, ns = ...

-- The Reminders window (/nra remind): a box to write a new one (same words as the command;
-- the Reminder / To-do switch next to it picks which), then your reminders and to-dos in sections:
-- Reminders and To do (due, not ticked off, each in your order: drag or use the arrows),
-- Waiting (with when they come due, and whether they pop up), For your other characters
-- (ones you left them) and Done (folded; the last few).
--
-- Tick a box to mark one done (untick to bring it back), click the text to edit it,
-- right-click for more (remind me again later, delete).
--
-- Add with the box empty opens a form instead: the text, when (next login, after a time,
-- in a zone picked from a list or typed, at a level) and which of your characters it's for.

local UI = ns.UI
local reminders = ns.reminders
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 30
local HEADER_HEIGHT = 26
local TOP_HEIGHT = 48
local FOOTER_HEIGHT = 28

local HELP = "Write one in the box above (the same words as in chat; click Add with it empty for a form), or in chat with /nra remind:\n"
	.. "  |cffffd100/nra remind <text>|r - for your next login\n"
	.. "  |cffffd100/nra remind 30m <text>|r - in 30 minutes (s, m, h, d: 2d, 1h30m)\n"
	.. "  |cffffd100/nra remind in Darkshore: <text>|r - when you enter a zone or subzone\n"
	.. "  |cffffd100/nra remind at 30: <text>|r - when you reach a level\n"
	.. "  |cffffd100/nra remind @Alt: <text>|r - on another character's next login (@Alt at 20: works too)\n\n"
	.. "Shift-clicked items and quests work in chat."

local WHEN = {
	{ key = "login", label = "Next login" },
	{ key = "time", label = "After a time" },
	{ key = "zone", label = "In a zone" },
	{ key = "level", label = "At a level" },
}
local UNITS = {
	{ key = "m", label = "minutes", seconds = 60 },
	{ key = "h", label = "hours", seconds = 3600 },
	{ key = "d", label = "days", seconds = 86400 },
}
local MAX_ZONE_MATCHES = 6

local KINDS = {
	{ quiet = false, label = "Reminder", tip = "Pops up on a card in the middle of the screen, with a sound, when it comes due. Then it waits on the list until you tick it." },
	{ quiet = true, label = "To-do", tip = "Goes straight on the list on screen (now, or when its trigger comes). No card, no sound." },
}

local frame, addBox, scroll, footerLeft, editBox, helpButton, showButton, form, kindChips

-- Whether new ones are to-dos (the switch next to the box; remembered).
local function AddingQuiet()
	return NraKitDB.remindersAddQuiet == true
end

-- A Reminder / To-do switch: two chips; onPick(quiet).
local function CreateKindSwitch(parent, onPick)
	local chips = {}
	for index, kind in ipairs(KINDS) do
		local chip = UI.CreateFlatButton(parent, kind.label, 22)
		chip.quiet = kind.quiet
		if index > 1 then
			chip:SetPoint("LEFT", chips[index - 1], "RIGHT", 2, 0)
		end
		chip:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			onPick(self.quiet)
		end)
		chip:SetScript("OnEnter", function(self)
			UI.ShowTooltip(self, kind.label, kind.tip)
		end)
		chip:SetScript("OnLeave", GameTooltip_Hide)
		chips[index] = chip
	end
	function chips:Select(quiet)
		for _, chip in ipairs(self) do
			chip:SetSelected(chip.quiet == quiet)
		end
	end
	return chips
end
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

local OpenForm

local function AddFromBox()
	local text = strtrim(addBox:GetText() or "")
	if text == "" then
		OpenForm()
		return
	end
	local add = AddingQuiet() and reminders.OnTodoCommand or reminders.OnSlashCommand
	if add(text) then
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
		reminders.AddReorder(row)
		-- What it is (in the sections that mix them): Reminder or To-do, in colour.
		row.kind = MakeLabel(row, "", "GameFontNormalSmall")
		row.kind:SetPoint("RIGHT", -30, 0)
		row.kind:SetJustifyH("RIGHT")
		row.when = MakeLabel(row, "", "GameFontHighlightSmall")
		row.when:SetPoint("RIGHT", row.kind, "LEFT", -10, 0)
		row.when:SetJustifyH("RIGHT")
		row.text = MakeLabel(row, "")
		row.text:SetPoint("LEFT", row.check, "RIGHT", 10, 0)
		row.text:SetPoint("RIGHT", row.when, "LEFT", -16, 0)
		row.text:SetWordWrap(false)
		row:SetScript("OnMouseDown", function(self)
			self.justDragged = nil
		end)
		row:SetScript("OnClick", function(self, button)
			if self.justDragged then
				self.justDragged = nil -- a drag, not a click
			elseif button == "RightButton" then
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

local KIND_COLOURS = { reminder = { 1, 0.6, 0.2 }, todo = { 0.4, 0.75, 1 } }

local function FillRow(row, reminder, when, index, showKind)
	row.reminder, row.reminderID = reminder, reminder.id
	row.canMove = reminder.state == "due"
	local done = reminder.state == "done"
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.check:SetChecked(done)
	row.text:SetText(reminder.text)
	row.text:SetAlpha(done and 0.5 or 1)
	row.text:SetShown(editingID ~= reminder.id)
	row.when:SetText(when)
	row.when:SetTextColor(unpack(reminder.state == "due" and UI.GOLD or UI.TEXT))
	row.kind:SetText(showKind and (reminder.quiet and "To-do" or "Reminder") or "")
	row.kind:SetTextColor(unpack(reminder.quiet and KIND_COLOURS.todo or KIND_COLOURS.reminder))
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
	local now, todo, waiting, others, done = {}, {}, {}, {}, {}
	for _, reminder in ipairs(reminders.List()) do
		if reminder.state == "due" then
			table.insert(reminder.quiet and todo or now, { reminder = reminder, when = reminders.DueNote(reminder) })
		elseif reminder.state == "waiting" then
			local when = reminders.Describe(reminder)
			table.insert(waiting, { reminder = reminder, when = when })
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
	local function ByOrder(a, b)
		if (a.reminder.order or math.huge) ~= (b.reminder.order or math.huge) then
			return (a.reminder.order or math.huge) < (b.reminder.order or math.huge)
		end
		return a.reminder.id < b.reminder.id
	end
	table.sort(now, ByOrder)
	table.sort(todo, ByOrder)
	table.sort(waiting, ByID)
	table.sort(others, ByID)
	table.sort(done, function(a, b)
		return (a.reminder.doneAt or 0) > (b.reminder.doneAt or 0)
	end)
	return {
		{ label = "Reminders", rows = now },
		{ label = "To do", rows = todo },
		{ label = "Waiting", rows = waiting, mixed = true },
		{ label = "For your other characters", rows = others, mixed = true },
		{ label = "Done", rows = done, foldable = true, mixed = true },
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
					FillRow(row, entry.reminder, entry.when, index, section.mixed)
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
	local anyDue = #reminders.Due() > 0
	showButton:SetEnabled(anyDue)
	showButton.text:SetTextColor(unpack(anyDue and UI.TEXT or UI.TEXT_DIM))
end

------------------------------------------------------------------------------
-- The form: a reminder without the command words
------------------------------------------------------------------------------

local function FormLabel(text, y)
	local label = MakeLabel(form, text, "GameFontNormal")
	label:SetPoint("TOPLEFT", PAD + 8, y)
	label:SetTextColor(unpack(UI.TEXT))
	return label
end

local function FormBox(width, numeric)
	local box = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(numeric == true)
	box:SetMaxLetters(numeric and 4 or 255)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		form:Hide() -- Escape cancels the form
	end)
	return box
end

-- Selects one chip of a row: chips[i].value.
local function SelectChip(chips, value)
	for _, chip in ipairs(chips) do
		chip:SetSelected(chip.value == value)
	end
end

local function CharacterChoices()
	local me = ns:PlayerName()
	local choices = { { me, "Me (" .. me .. ")" } }
	for _, name in ipairs(reminders.KnownCharacters()) do
		if name ~= me then
			table.insert(choices, { name, name })
		end
	end
	return choices
end

local function RefreshForm()
	local kind = form.kind
	SelectChip(form.whenChips, kind)
	SelectChip(form.unitChips, form.unit)
	for _, each in ipairs(WHEN) do
		form.details[each.key]:SetShown(each.key == kind)
	end
	local other = form.character ~= ns:PlayerName()
	local quiet = form.quiet
	form.kindChips:Select(quiet)
	-- A to-do for you with no trigger goes on the list now.
	form.whenChips[1].text:SetText(quiet and not other and "Now" or "Next login")
	form.loginNote:SetText(quiet and not other and "On your to-do list right away."
		or other and "The next time they log in." or "The next time you log in.")
	form.title:SetText(quiet and "New to-do" or "New reminder")
	local stayShown = quiet and ns:GetOption("remindersZoneLeave") == true
	form.stay:SetShown(stayShown)
	form.stayLabel:SetShown(stayShown)
	form.addButton.text:SetText(quiet and "Add to-do" or "Add reminder")

	-- Zones: here, then the ones whose name has what you typed.
	local zone, subzone = reminders.Here()
	form.hereZone.value, form.hereSubzone.value = zone, subzone
	form.hereZone.text:SetText(zone and ("Here: " .. zone) or "")
	form.hereZone:SetWidth(form.hereZone.text:GetStringWidth() + 20)
	form.hereZone:SetShown(zone ~= nil)
	form.hereSubzone.text:SetText(subzone and ("Here: " .. subzone) or "")
	form.hereSubzone:SetWidth(form.hereSubzone.text:GetStringWidth() + 20)
	form.hereSubzone:SetShown(subzone ~= nil)
	local typed = strtrim(form.zoneBox:GetText() or ""):lower()
	local matches = {}
	if typed ~= "" then
		for _, name in ipairs(form.zoneNames) do
			if #matches < MAX_ZONE_MATCHES and name:lower():find(typed, 1, true) and name:lower() ~= typed then
				table.insert(matches, name)
			end
		end
	end
	for index, button in ipairs(form.zoneMatches) do
		local name = matches[index]
		button:SetShown(name ~= nil)
		if name then
			button.value = name
			button.text:SetText(name)
			button:SetWidth(button.text:GetStringWidth() + 20)
		end
	end
	form.characterSelect:Refresh()
end

local function SubmitForm()
	local spec = { text = strtrim(form.textBox:GetText() or ""), kind = form.kind }
	if spec.kind == "time" then
		local amount = tonumber(form.amountBox:GetText())
		for _, unit in ipairs(UNITS) do
			if unit.key == form.unit and amount then
				spec.duration = amount * unit.seconds
				spec.at = time() + spec.duration
			end
		end
	elseif spec.kind == "zone" then
		spec.zone = strtrim(form.zoneBox:GetText() or "")
		spec.stay = form.quiet and form.stay:GetChecked() or nil
	elseif spec.kind == "level" then
		spec.level = tonumber(form.levelBox:GetText())
	end
	if form.character ~= ns:PlayerName() then
		spec.character, spec.known = form.character, true
	end
	spec.quiet = form.quiet or nil
	local checked, problem = reminders.Validate(spec)
	if not checked then
		form.problem:SetText(problem)
		return
	end
	reminders.Commit(checked)
	form:Hide()
end

local function CreateForm()
	local body = frame.body
	form = CreateFrame("Frame", "NraKitReminderForm", body)
	form:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	form:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT + 1)
	form:EnableMouse(true)
	form:SetFrameLevel(scroll:GetFrameLevel() + 10)
	local bg = form:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	form:Hide()

	form.title = MakeLabel(form, "New reminder", "GameFontNormalLarge")
	form.title:SetPoint("TOPLEFT", PAD + 8, -PAD - 4)
	form.title:SetTextColor(unpack(UI.ACCENT))
	form.kindChips = CreateKindSwitch(form, function(quiet)
		form.quiet = quiet
		RefreshForm()
	end)
	form.kindChips[1]:SetPoint("TOPLEFT", 180, -PAD - 1)
	local back = UI.CreateFlatButton(form, "< Back to the list", 22)
	back:SetPoint("TOPRIGHT", -PAD, -PAD)
	back:SetScript("OnClick", function()
		form:Hide()
	end)
	back:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Back to the list", "Closes the form without adding anything (also Cancel, or Escape while typing).")
	end)
	back:SetScript("OnLeave", GameTooltip_Hide)
	local LEFT = 130

	FormLabel("Reminder", -56)
	form.textBox = FormBox(560)
	form.textBox:SetPoint("TOPLEFT", LEFT + 6, -52)
	form.textBox:SetScript("OnEnterPressed", SubmitForm)

	FormLabel("When", -96)
	form.whenChips = {}
	local anchor
	for _, each in ipairs(WHEN) do
		local chip = UI.CreateFlatButton(form, each.label, 22)
		chip.value = each.key
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", LEFT, -92)
		end
		chip:SetScript("OnClick", function(self)
			form.kind = self.value
			form.problem:SetText("")
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			RefreshForm()
		end)
		table.insert(form.whenChips, chip)
		anchor = chip
	end

	-- What goes with each choice, under the chips.
	form.details = {}
	local function Details()
		local details = CreateFrame("Frame", nil, form)
		details:SetPoint("TOPLEFT", LEFT, -124)
		details:SetPoint("RIGHT", -PAD, 0)
		details:SetHeight(110)
		return details
	end

	local login = Details()
	form.loginNote = MakeLabel(login, "", "GameFontDisable")
	form.loginNote:SetPoint("TOPLEFT", 2, -4)
	form.details.login = login

	local timed = Details()
	form.amountBox = FormBox(50, true)
	form.amountBox:SetParent(timed)
	form.amountBox:SetPoint("TOPLEFT", 6, 0)
	form.amountBox:SetScript("OnEnterPressed", SubmitForm)
	form.unitChips = {}
	anchor = form.amountBox
	for _, unit in ipairs(UNITS) do
		local chip = UI.CreateFlatButton(timed, unit.label, 22)
		chip.value = unit.key
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == form.amountBox and 10 or 4, 0)
		chip:SetScript("OnClick", function(self)
			form.unit = self.value
			RefreshForm()
		end)
		table.insert(form.unitChips, chip)
		anchor = chip
	end
	local quick = MakeLabel(timed, "Or:", "GameFontDisableSmall")
	quick:SetPoint("TOPLEFT", 2, -34)
	anchor = quick
	for _, each in ipairs({ { "15 min", 15, "m" }, { "1 hour", 1, "h" }, { "3 hours", 3, "h" }, { "1 day", 1, "d" } }) do
		local chip = UI.CreateFlatButton(timed, each[1], 20)
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == quick and 8 or 4, 0)
		chip:SetScript("OnClick", function()
			form.amountBox:SetText(each[2])
			form.unit = each[3]
			RefreshForm()
		end)
		anchor = chip
	end
	form.details.time = timed

	local zoned = Details()
	form.zoneBox = FormBox(260)
	form.zoneBox:SetParent(zoned)
	form.zoneBox:SetPoint("TOPLEFT", 6, 0)
	form.zoneBox:SetScript("OnEnterPressed", SubmitForm)
	form.zoneBox:HookScript("OnTextChanged", function()
		RefreshForm()
	end)
	local function PickZone(self)
		form.zoneBox:SetText(self.value)
		form.zoneBox:ClearFocus()
		RefreshForm()
	end
	form.hereZone = UI.CreateFlatButton(zoned, "", 22)
	form.hereZone:SetPoint("LEFT", form.zoneBox, "RIGHT", 10, 0)
	form.hereZone:SetScript("OnClick", PickZone)
	form.hereSubzone = UI.CreateFlatButton(zoned, "", 22)
	form.hereSubzone:SetPoint("LEFT", form.hereZone, "RIGHT", 4, 0)
	form.hereSubzone:SetScript("OnClick", PickZone)
	local zoneHint = MakeLabel(zoned, "Type a zone or subzone (any you like), or pick one.", "GameFontDisableSmall")
	zoneHint:SetPoint("TOPLEFT", 2, -30)
	form.zoneMatches = {}
	anchor = nil
	for index = 1, MAX_ZONE_MATCHES do
		local button = UI.CreateFlatButton(zoned, "", 20)
		if index == 1 then
			button:SetPoint("TOPLEFT", 0, -50)
		elseif index == 4 then
			button:SetPoint("TOPLEFT", 0, -74)
		else
			button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		end
		button:SetScript("OnClick", PickZone)
		form.zoneMatches[index] = button
		anchor = button
	end
	-- A to-do for a zone: whether it stays on the list when you leave.
	form.stay = reminders.CreateCheck(zoned, function() end)
	form.stay:SetPoint("TOPLEFT", 2, -100)
	form.stayLabel = MakeLabel(zoned, "Keep it on the list when I leave the zone", "GameFontHighlightSmall")
	form.stayLabel:SetPoint("LEFT", form.stay, "RIGHT", 8, 0)
	form.details.zone = zoned

	local leveled = Details()
	form.levelBox = FormBox(50, true)
	form.levelBox:SetParent(leveled)
	form.levelBox:SetPoint("TOPLEFT", 6, 0)
	form.levelBox:SetScript("OnEnterPressed", SubmitForm)
	local levelHint = MakeLabel(leveled, "When you reach this level.", "GameFontDisable")
	levelHint:SetPoint("LEFT", form.levelBox, "RIGHT", 12, 0)
	form.details.level = leveled

	FormLabel("For", -246)
	form.characterSelect = UI.CreateChoiceSelect(form, {
		width = 260,
		get = function()
			return form.character
		end,
		set = function(value)
			form.character = value
			RefreshForm()
		end,
		choices = CharacterChoices,
	})
	form.characterSelect:SetPoint("TOPLEFT", LEFT, -242)

	local add = UI.CreateFlatButton(form, "Add reminder", 26)
	add:SetWidth(120)
	add:SetPoint("TOPLEFT", LEFT, -292)
	form.addButton = add
	add:SetScript("OnClick", SubmitForm)
	local cancel = UI.CreateFlatButton(form, "Cancel", 26)
	cancel:SetWidth(80)
	cancel:SetPoint("LEFT", add, "RIGHT", 8, 0)
	cancel:SetScript("OnClick", function()
		form:Hide()
	end)
	form.problem = MakeLabel(form, "", "GameFontNormal")
	form.problem:SetPoint("LEFT", cancel, "RIGHT", 16, 0)
	form.problem:SetTextColor(1, 0.35, 0.3)

	form:HookScript("OnShow", function()
		scroll:Hide()
	end)
	form:HookScript("OnHide", function()
		scroll:Show()
		Render()
	end)
end

-- Opens the form, empty: next login (or now, for a to-do), for you.
function OpenForm()
	if not form then
		CreateForm()
	end
	form.kind, form.unit, form.character = "login", "m", ns:PlayerName()
	form.quiet = AddingQuiet() -- like the switch at the top
	form.textBox:SetText("")
	form.stay:SetChecked(false)
	form.amountBox:SetText("30")
	form.zoneBox:SetText("")
	form.levelBox:SetText(math.min((UnitLevel("player") or 1) + 1, GetMaxPlayerLevel and GetMaxPlayerLevel() or 999))
	form.problem:SetText("")
	form.zoneNames = reminders.ZoneNames()
	form:Show()
	RefreshForm()
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateWindow()
	frame = UI.CreateWindow("NraKitRemindersFrame", "Reminders & To-do", WIDTH, HEIGHT, 0, "reminders")
	local body = frame.body

	addBox = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
	addBox:SetHeight(22)
	addBox:SetPoint("TOPLEFT", PAD + 8, -PAD - 1)
	addBox:SetPoint("RIGHT", -PAD - 230, 0)
	addBox:SetAutoFocus(false)
	addBox:SetMaxLetters(255)
	addBox:SetScript("OnEnterPressed", AddFromBox)
	addBox:SetScript("OnEscapePressed", addBox.ClearFocus)
	addBox.placeholder = MakeLabel(addBox, "Type one (like /nra remind), or click Add for a form", "GameFontDisable")
	addBox.placeholder:SetPoint("LEFT", 2, 0)
	addBox:HookScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	local add = UI.CreateFlatButton(body, "Add", 22)
	add:SetWidth(56)
	kindChips = CreateKindSwitch(body, function(quiet)
		NraKitDB.remindersAddQuiet = quiet or nil
		kindChips:Select(quiet)
	end)
	kindChips[1]:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
	kindChips:Select(AddingQuiet())
	add:SetPoint("LEFT", kindChips[#kindChips], "RIGHT", 8, 0)
	add:SetScript("OnClick", AddFromBox)
	add:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Add", "Adds what you typed as a reminder or a to-do (the switch to the left), in the same words as /nra remind. With nothing typed, opens a form to pick when it comes due.")
	end)
	add:SetScript("OnLeave", GameTooltip_Hide)
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
	showButton = UI.CreateFlatButton(footer, "Show list", 20)
	showButton:SetPoint("LEFT", footerLeft, "RIGHT", 12, 0)
	showButton:SetScript("OnClick", function()
		reminders.ShowTracker()
	end)
	showButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Show list", "Shows the list on screen, unfolded, also after you hid it (or /nra todo, or a key under Key Bindings > NraKit). Greyed out while nothing is due.")
	end)
	showButton:SetScript("OnLeave", GameTooltip_Hide)
	local settings = UI.CreateFlatButton(footer, "Settings", 20)
	settings:SetPoint("RIGHT", -PAD + 4, 0)
	settings:SetScript("OnClick", function()
		ns:OpenSettings("Reminders & to-dos", "reminders")
	end)
	settings:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Settings", "Sound, and how the list on screen looks: size, opacity, background, hide in combat, lock...")
	end)
	settings:SetScript("OnLeave", GameTooltip_Hide)
	local hint = MakeLabel(footer, "Tick when done. Click to edit, right-click for more", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", settings, "LEFT", -12, 0)

	frame:HookScript("OnShow", Render)
	frame:HookScript("OnHide", function()
		editingID = nil
		helpButton:SetOpen(false)
		if form then
			form:Hide()
		end
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
	key = "reminders", label = "Reminders & To-do", menuLabel = "Reminders & To-do", order = 7, frameName = "NraKitRemindersFrame",
	open = function()
		if not frame then
			CreateWindow()
		end
		frame:Show()
	end,
	module = "reminders",
})

ns:AddOptionsButton("reminders", "Open reminders & to-do", "Your reminders and to-dos (/nra remind).", function()
	ns:OpenReminders()
end)
