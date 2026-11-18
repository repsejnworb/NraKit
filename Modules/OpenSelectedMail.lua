local _, ns = ...

-- Open selected mail: a checkbox on each mail in the inbox. While any are ticked,
-- Blizzard's "Open All" button only opens those ("Open Selected (N)").
--
-- Open All walks the inbox and asks itself ShouldSkipCurrentMail() for each mail; we
-- wrap that one method on the button so unticked mails are skipped too. Taking mail
-- isn't protected, so running our code inside Blizzard's loop is harmless.
--
-- Mail indexes shift as emptied mails disappear, so a selection is remembered by
-- sender, subject and expiry time instead of by index.

local module = {
	key = "openSelectedMail",
	section = "Utilities",
	name = "Open selected mail",
	description = "Adds a checkbox to each mail in your inbox. Tick some and the Open All button only opens those.",
	default = false,
}

-- Two reads of the same mail's days left can differ slightly; this is about a minute.
local DAYS_TOLERANCE = 0.001

local selected = {} -- list of { sender, subject, daysLeft }
local checkboxes = {}

local function Signature(index)
	local _, _, sender, subject, money, CODAmount, daysLeft, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
	return sender, subject, daysLeft, (money or 0) > 0 or (itemCount or 0) > 0, isGM or (CODAmount or 0) > 0
end

-- The selection entry matching the mail at index, and its position in the list.
local function FindSelection(index)
	local sender, subject, daysLeft = Signature(index)
	if not daysLeft then
		return nil
	end
	for position, entry in ipairs(selected) do
		if entry.sender == sender and entry.subject == subject and math.abs(entry.daysLeft - daysLeft) < DAYS_TOLERANCE then
			return entry, position
		end
	end
	return nil
end

local function IsActive()
	return ns:IsModuleEnabled(module.key) and #selected > 0
end

local function UpdateOpenAllText()
	if not OpenAllMail:IsEnabled() then
		return -- opening: Blizzard shows its own "Opening..."
	end
	if IsActive() then
		OpenAllMail:SetText(string.format("Open Selected (%d)", #selected))
	else
		OpenAllMail:SetText(OPEN_ALL_MAIL_BUTTON)
	end
end

-- Forget selected mails that are gone or have nothing left to take.
local function Prune()
	local keep = {}
	for index = 1, GetInboxNumItems() do
		local entry = FindSelection(index)
		local _, _, _, hasContents = Signature(index)
		if entry and hasContents then
			keep[entry] = true
		end
	end
	for position = #selected, 1, -1 do
		if not keep[selected[position]] then
			table.remove(selected, position)
		end
	end
end

local function UpdateCheckboxes()
	local enabled = ns:IsModuleEnabled(module.key)
	for i = 1, INBOXITEMS_TO_DISPLAY do
		local checkbox = checkboxes[i]
		local button = _G["MailItem" .. i .. "Button"]
		if checkbox and button then
			local show = false
			if enabled and button:IsShown() and button.index then
				local _, _, _, hasContents, mustOpenByHand = Signature(button.index)
				show = hasContents and not mustOpenByHand
			end
			checkbox:SetShown(show)
			checkbox:SetChecked(show and FindSelection(button.index) ~= nil)
		end
	end
	UpdateOpenAllText()
end

local function OnCheckboxClick(checkbox)
	local button = _G["MailItem" .. checkbox.row .. "Button"]
	local index = button and button.index
	if not index then
		return
	end
	local entry, position = FindSelection(index)
	if entry then
		table.remove(selected, position)
	else
		local sender, subject, daysLeft = Signature(index)
		table.insert(selected, { sender = sender, subject = subject, daysLeft = daysLeft })
	end
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
	OpenAllMail.ShouldSkipCurrentMail = function(self, ...)
		if IsActive() and not FindSelection(self.mailIndex) then
			return true
		end
		return original(self, ...)
	end
	-- After a run (finished, bags full or mailbox closed), drop what was opened.
	hooksecurefunc(OpenAllMail, "StopOpening", function()
		if #selected > 0 then
			Prune()
		end
		UpdateCheckboxes()
	end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
	-- MAIL_CLOSED: a new visit starts with nothing selected.
	wipe(selected)
end)

function module:OnInitialize()
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
end

function module:OnEnabledChanged()
	if checkboxes[1] then
		UpdateCheckboxes()
	end
end

ns:RegisterModule(module)
