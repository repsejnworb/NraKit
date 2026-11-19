local _, ns = ...

-- Remember mail recipient: after a mail is sent, the To box keeps the name instead of being
-- emptied, so mailing your bank alt five times means typing the name once. The name is
-- selected, so typing a different one replaces it. Optionally the last name is also filled
-- in when you open Send Mail (per character, NraKitDB.mailRecipientData).
--
-- Blizzard empties the box in SendMailFrame_Reset, which it calls only on MAIL_SEND_SUCCESS;
-- we put the name back right after. Replying still fills in the sender (Reply sets the name
-- after switching tabs, so after us).

local module = {
	key = "mailRecipient",
	section = "Utilities",
	name = "Remember mail recipient",
	description = "Keeps the name in the To box after you send a mail, so you can send several to the same player (like your bank alt) without typing it again.",
	default = false,
	options = {
		{
			key = "mailRecipientOnOpen",
			name = "Fill it in when opening Send Mail",
			description = "Also fill in the last player you mailed (from this character) when you open the Send Mail tab.",
			default = true,
		},
	},
}

local mailRecipient = {}
ns.mailRecipient = mailRecipient

local sending -- the name of the mail being sent, until it succeeds or fails

local function Me()
	local name, surname = UnitName("player")
	return surname and surname ~= "" and (name .. " " .. surname) or name or "?"
end

function mailRecipient.Last()
	local data = NraKitDB.mailRecipientData
	return data and data[Me()]
end

local function Fill(name)
	if name and name ~= "" then
		SendMailNameEditBox:SetText(name)
		SendMailNameEditBox:HighlightText()
	end
end

-- The Send button was clicked.
function mailRecipient.OnSend()
	sending = SendMailNameEditBox:GetText()
end

-- The mail went off and Blizzard emptied the form.
function mailRecipient.OnSent()
	local name = sending
	sending = nil
	if not name or name == "" or not ns:IsModuleEnabled(module.key) then
		return
	end
	NraKitDB.mailRecipientData = NraKitDB.mailRecipientData or {}
	NraKitDB.mailRecipientData[Me()] = name
	Fill(name)
end

-- A mail tab was clicked (tab 2 is Send Mail).
function mailRecipient.OnTab(tab, tabID)
	tabID = tabID or (tab and tab:GetID())
	if tabID == 2 and ns:IsModuleEnabled(module.key) and ns:GetOption("mailRecipientOnOpen")
		and SendMailNameEditBox:GetText() == "" then
		Fill(mailRecipient.Last())
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
	sending = nil -- MAIL_FAILED
end)

function module:OnInitialize()
	if not SendMailNameEditBox or not SendMailFrame_Reset then
		return
	end
	hooksecurefunc("SendMailFrame_SendMail", mailRecipient.OnSend)
	hooksecurefunc("SendMailFrame_Reset", mailRecipient.OnSent)
	hooksecurefunc("MailFrameTab_OnClick", mailRecipient.OnTab)
	eventFrame:RegisterEvent("MAIL_FAILED")
end

ns:RegisterModule(module)
