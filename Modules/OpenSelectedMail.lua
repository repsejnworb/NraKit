local _, ns = ...

-- Open selected mail: a checkbox on each mail in the inbox. While any are ticked,
-- Blizzard's "Open All" button only opens those ("Open Selected (N)").
--
-- Open All walks the inbox and asks itself ShouldSkipCurrentMail() for each mail; we
-- wrap that one method on the button so unticked mails are skipped too. Taking mail
-- isn't protected, so running our code inside Blizzard's loop is harmless.
--
-- Mails can be identical (a batch your alt sent itself: same sender, subject and expiry), so a
-- selection is kept on our own list of the inbox, one entry per mail in order. When mails
-- disappear (emptied, deleted, returned) or arrive, the list is lined up with the inbox again;
-- which mail went is the one last taken from, which tells identical neighbours apart.
--
-- Shift-click a checkbox: every mail from the one clicked before to this one gets its tick.


-- Two reads of the same mail's days left can differ slightly; this is about a minute.
local DAYS_TOLERANCE = 0.001
local feature = { key = "openSelectedMail" } -- an option of the Mail feature (Mail.lua)

local mails = {} -- the inbox as last read: { sender, subject, daysLeft, readAt, selected } per mail
local touched -- the mail last taken from, deleted or returned: where one disappears from
local anchor -- the mail (an entry of mails) last ticked or unticked, for Shift-click
local checkboxes = {}

ns:RegisterDebug("mail", "Mail: ticking mails for Open All, and keeping the ticks on the right mails")

local function Header(index)
	local _, _, sender, subject, money, CODAmount, daysLeft, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
	return sender, subject, daysLeft, (money or 0) > 0 or (itemCount or 0) > 0, isGM or (CODAmount or 0) > 0
end

local function Read(index)
	local sender, subject, daysLeft = Header(index)
	return { sender = sender, subject = subject, daysLeft = daysLeft, readAt = GetTime() }
end

-- Whether an entry we had is (likely) the mail read now: same sender and subject, and the same
-- days left, or gone down by the time since (in case the game counts it down between reads).
local function Same(entry, mail)
	if entry.sender ~= mail.sender or entry.subject ~= mail.subject or not (entry.daysLeft and mail.daysLeft) then
		return false
	end
	local expected = entry.daysLeft - (mail.readAt - entry.readAt) / 86400
	return math.abs(entry.daysLeft - mail.daysLeft) < DAYS_TOLERANCE or math.abs(expected - mail.daysLeft) < DAYS_TOLERANCE
end

-- Whether every entry of list lines up with the mail `offset` places further down in now.
local function LinesUp(list, now, offset)
	for position, entry in ipairs(list) do
		if not (now[position + offset] and Same(entry, now[position + offset])) then
			return false
		end
	end
	return true
end

local function Without(list, position)
	local copy = {}
	for i, entry in ipairs(list) do
		if i ~= position then
			table.insert(copy, entry)
		end
	end
	return copy
end

-- Our list after one mail went: the one last taken from if that lines up, else the first that does.
local function RemoveOne(list, now)
	if touched and list[touched] then
		local rest = Without(list, touched)
		if LinesUp(rest, now, 0) then
			return rest
		end
	end
	for position = 1, #list do
		local rest = Without(list, position)
		if LinesUp(rest, now, 0) then
			return rest
		end
	end
end

-- Lines our list up with the inbox. Mails that went are dropped, new ones (at the top, or the
-- end as the server fills the inbox) start unticked; anything else starts over unticked.
local function Sync()
	local count = GetInboxNumItems()
	local now = {}
	for index = 1, count do
		now[index] = Read(index)
	end
	local list = mails
	if #list == count + 1 then
		list = RemoveOne(list, now)
	elseif #list > count + 1 then
		-- Several at once: keep the ones that line up in order.
		local kept, j = {}, 1
		for _, entry in ipairs(list) do
			if now[j] and Same(entry, now[j]) then
				table.insert(kept, entry)
				j = j + 1
			end
		end
		list = #kept == count and kept or nil
	end
	local offset = 0
	if list and #list < count then
		offset = LinesUp(list, now, count - #list) and count - #list or 0
	end
	if not (list and LinesUp(list, now, offset)) then
		list = {}
		if anchor then
			ns:Debug("mail", "inbox changed past lining up: selection cleared")
		end
		anchor = nil
	end
	for index, mail in ipairs(now) do
		local entry = list[index - offset]
		if entry then
			entry.daysLeft, entry.readAt = mail.daysLeft, mail.readAt
			now[index] = entry
		end
	end
	mails = now
	touched = nil
end

-- Our entry for the mail at index (in step with the inbox).
local function EntryAt(index)
	if #mails ~= GetInboxNumItems() then
		Sync()
	end
	return mails[index]
end

local function SelectedCount()
	local count = 0
	for _, entry in ipairs(mails) do
		if entry.selected then
			count = count + 1
		end
	end
	return count
end

local function Selectable(index)
	if index > GetInboxNumItems() then
		return false
	end
	local _, _, _, hasContents, mustOpenByHand = Header(index)
	return hasContents and not mustOpenByHand
end

local function IsActive()
	return ns.mail.IsOn(feature.key) and SelectedCount() > 0
end

local function UpdateOpenAllText()
	if not OpenAllMail:IsEnabled() then
		return -- opening: Blizzard shows its own "Opening..."
	end
	if IsActive() then
		OpenAllMail:SetText(string.format("Open Selected (%d)", SelectedCount()))
	else
		OpenAllMail:SetText(OPEN_ALL_MAIL_BUTTON)
	end
end

-- Untick mails that have nothing left to take.
local function Prune()
	Sync()
	for index, entry in ipairs(mails) do
		if entry.selected and not Selectable(index) then
			entry.selected = nil
		end
	end
end

local function UpdateCheckboxes()
	local enabled = ns.mail.IsOn(feature.key)
	Sync()
	for i = 1, INBOXITEMS_TO_DISPLAY do
		local checkbox = checkboxes[i]
		local button = _G["MailItem" .. i .. "Button"]
		if checkbox and button then
			local show = false
			if enabled and button:IsShown() and button.index then
				show = Selectable(button.index)
			end
			checkbox:SetShown(show)
			checkbox:SetChecked(show and mails[button.index] ~= nil and mails[button.index].selected == true)
		end
	end
	UpdateOpenAllText()
end

local function OnCheckboxClick(checkbox)
	local button = _G["MailItem" .. checkbox.row .. "Button"]
	local index = button and button.index
	local entry = index and EntryAt(index)
	if not entry then
		return
	end
	local selected = not entry.selected
	-- Shift-click: every mail between the one clicked before and this one gets this tick.
	local from
	if IsShiftKeyDown() and anchor then
		for i, other in ipairs(mails) do
			if other == anchor then
				from = i
			end
		end
	end
	if from then
		local step = from <= index and 1 or -1
		for i = from, index, step do
			if Selectable(i) then
				mails[i].selected = selected or nil
			end
		end
	end
	entry.selected = selected or nil
	anchor = entry
	ns:Debug("mail", "%s mail %d (from %s): %d selected", selected and "ticked" or "unticked", index, tostring(from),
		SelectedCount())
	UpdateCheckboxes()
end

local function CreateCheckboxes()
	for i = 1, INBOXITEMS_TO_DISPLAY do
		local row = _G["MailItem" .. i]
		if row then
			local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			checkbox:SetSize(22, 22)
			checkbox:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
			checkbox.row = i
			checkbox:SetScript("OnClick", OnCheckboxClick)
			checkbox:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Select for Open All")
				GameTooltip:AddLine("While any mail is selected, Open All only opens the selected ones.", 1, 1, 1, true)
				GameTooltip:AddLine("Shift-click to tick (or untick) every mail from the one you clicked before.", 0.5, 0.5, 0.5, true)
				GameTooltip:Show()
			end)
			checkbox:SetScript("OnLeave", GameTooltip_Hide)
			checkbox:Hide()
			checkboxes[i] = checkbox
		end
	end
end

local function WrapOpenAll()
	local original = OpenAllMail.ShouldSkipCurrentMail
	-- A run (the button is disabled while it opens) that started with mails selected opens only
	-- those, also once the last of them is gone.
	local selective = false
	OpenAllMail.ShouldSkipCurrentMail = function(self, ...)
		local entry = EntryAt(self.mailIndex)
		if IsActive() then
			selective = not self:IsEnabled()
		end
		if (selective or IsActive()) and not (entry and entry.selected) then
			return true
		end
		return original(self, ...)
	end
	-- After a run (finished, bags full or mailbox closed), drop what was opened.
	hooksecurefunc(OpenAllMail, "StopOpening", function()
		selective = false
		Prune()
		UpdateCheckboxes()
	end)
end

local eventFrame = CreateFrame("Frame")
-- A new visit starts with nothing selected.
local function Forget()
	wipe(mails)
	anchor, touched = nil, nil
end
eventFrame:SetScript("OnEvent", Forget) -- MAIL_CLOSED

-- Where a mail may disappear from: the one last taken from, deleted or returned.
local function Touched(index)
	touched = index
end

function feature.OnInitialize()
	if not OpenAllMail or not OpenAllMail.ShouldSkipCurrentMail then
		return
	end
	CreateCheckboxes()
	WrapOpenAll()
	-- Forever's inbox is InboxMixin:Update(); older clients have a global InboxFrame_Update().
	if InboxFrame and InboxFrame.Update then
		hooksecurefunc(InboxFrame, "Update", UpdateCheckboxes)
	elseif InboxFrame_Update then
		hooksecurefunc("InboxFrame_Update", UpdateCheckboxes)
	end
	eventFrame:RegisterEvent("MAIL_CLOSED")
	-- Forever opens and closes the mailbox through its interaction system: MAIL_CLOSED may not come.
	if MailFrame then
		MailFrame:HookScript("OnHide", Forget)
	end
	for _, name in ipairs({ "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem", "DeleteInboxItem", "ReturnInboxItem" }) do
		if _G[name] then
			hooksecurefunc(name, Touched)
		end
	end
end

function feature.OnEnabledChanged()
	if checkboxes[1] then
		UpdateCheckboxes()
	end
end

ns.mail.Register(feature)
