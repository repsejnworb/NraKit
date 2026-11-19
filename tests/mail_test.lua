-- Sending mail: Fill in mail subject (the subject text, and when it may replace what's in
-- the box) and Remember mail recipient.

-- A stand-in Send Mail frame, made before the addon loads so the modules hook it like in
-- game. hooksecurefunc really hooks here (the stand-in client's does nothing).
local mail = { attached = {}, cod = false }
hooksecurefunc = function(name, hook)
	local original = _G[name]
	if original then
		_G[name] = function(...)
			original(...)
			hook(...)
		end
	end
end
SendMailNameEditBox = CreateFrame("EditBox")
SendMailSubjectEditBox = CreateFrame("EditBox")
SendMailMoney = CreateFrame("Frame")
for _, key in ipairs({ "gold", "silver", "copper" }) do
	SendMailMoney[key] = CreateFrame("EditBox", nil, SendMailMoney)
end
SendMailCODButton = { GetChecked = function()
	return mail.cod
end }
SendMailFrame = {}
ATTACHMENTS_MAX_SEND = 12
HasSendMailItem = function(index)
	return mail.attached[index] ~= nil
end
GetSendMailItem = function(index)
	local item = mail.attached[index]
	return item.name, item.id, 0, item.count
end
MoneyInputFrame_GetCopper = function(moneyFrame)
	local function Number(box)
		return tonumber(box:GetText()) or 0
	end
	return Number(moneyFrame.gold) * 10000 + Number(moneyFrame.silver) * 100 + Number(moneyFrame.copper)
end
-- Like Blizzard's: an update after attachments change, sending, and emptying the form after it's sent.
function SendMailFrame_Update() end
function SendMailRadioButton_OnClick() end
function SendMailFrame_SendMail() end
function SendMailFrame_Reset()
	SendMailNameEditBox:SetText("")
	SendMailSubjectEditBox:SetText("")
	for _, key in ipairs({ "gold", "silver", "copper" }) do
		SendMailMoney[key]:SetText("")
	end
	mail.attached = {}
	SendMailFrame_Update()
end
function MailFrameTab_OnClick() end

return {
	enable = { "mailSubject", "mailRecipient" },
	run = function(t, ns, wow)
		local mailSubject = ns.mailSubject
		local function Items(...)
			local list = {}
			for index = 1, select("#", ...), 2 do
				table.insert(list, { name = select(index, ...), count = select(index + 1, ...) })
			end
			return list
		end

		t.test("money text", function()
			t.equal(mailSubject.MoneyText(250000), "25g", "gold")
			t.equal(mailSubject.MoneyText(52010), "5g 20s 10c", "gold, silver, copper")
			t.equal(mailSubject.MoneyText(305), "3s 5c", "no gold")
		end)

		t.test("subjects", function()
			t.equal(mailSubject.Subject({}, 0, false), "", "empty mail")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 1), 0, false), "Linen Cloth", "one item")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20, "Linen Cloth", 20), 0, false), "Linen Cloth (40)", "stacks add up")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20, "Wool Cloth", 5), 0, false), "Linen Cloth (20), Wool Cloth (5)", "two kinds")
			t.equal(mailSubject.Subject({}, 250000, false), "25g", "gold only")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20), 50000, false), "Linen Cloth (20) + 5g", "items and gold")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20), 50000, true), "Linen Cloth (20) (C.O.D. 5g)", "C.O.D.")
			t.equal(mailSubject.Subject({}, 50000, true), "", "C.O.D. without items says nothing")
		end)

		t.test("too many kinds: the first ones and how many more", function()
			local subject = mailSubject.Subject(Items("Heavy Mageweave Bandage", 20, "Runecloth Bandage", 20,
				"Mageweave Bandage", 20, "Silk Bandage", 20), 0, false)
			t.ok(#subject <= 64, "fits: " .. subject)
			t.ok(subject:find(" more$"), "says more: " .. subject)
			t.ok(subject:find("^Heavy Mageweave Bandage %(20%)"), "starts with the first item: " .. subject)
		end)

		local box = SendMailSubjectEditBox

		t.test("fills an empty subject and follows the attachments", function()
			mail.attached = { { name = "Linen Cloth", id = 2589, count = 20 } }
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth (20)", "item")
			mail.attached[2] = { name = "Linen Cloth", id = 2589, count = 20 }
			SendMailMoney.gold:SetText("5")
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth (40) + 5g", "more items and gold")
			mail.attached = {}
			SendMailMoney.gold:SetText("")
			mailSubject.Update()
			t.equal(box:GetText(), "", "cleared again")
		end)

		t.test("replaces Blizzard's own subject", function()
			box:SetText("Linen Cloth")
			SendMailFrame.previousItem = "Linen Cloth"
			mail.attached = { { name = "Linen Cloth", id = 2589, count = 1 }, { name = "Wool Cloth", id = 2592, count = 1 } }
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth, Wool Cloth", "replaced")
		end)

		t.test("never touches a subject you typed", function()
			box:SetText("Mats for the shoulders")
			SendMailMoney.gold:SetText("1")
			mailSubject.Update()
			t.equal(box:GetText(), "Mats for the shoulders", "kept")
			mail.attached = {}
			SendMailMoney.gold:SetText("")
			mailSubject.Update()
			t.equal(box:GetText(), "Mats for the shoulders", "kept after removing everything")
		end)

		t.test("waits for an item name that isn't loaded yet", function()
			box:SetText("")
			mail.attached = { { id = 4338, count = 10 } }
			mailSubject.Update()
			t.equal(box:GetText(), "", "nothing yet")
			wow.data.items[4338] = { name = "Mageweave Cloth", bags = 0, bank = 0 }
			wow.fire("GET_ITEM_INFO_RECEIVED", 4338, true)
			t.equal(box:GetText(), "Mageweave Cloth (10)", "filled once loaded")
		end)

		-- Regression: typing only money didn't set the subject (the global hook never ran).
		t.test("typing silver and copper alone sets the subject", function()
			mail.attached = {}
			box:SetText("")
			SendMailMoney.silver:SetText("20")
			t.equal(box:GetText(), "20s", "silver")
			SendMailMoney.copper:SetText("5")
			t.equal(box:GetText(), "20s 5c", "and copper")
			SendMailMoney.silver:SetText("")
			SendMailMoney.copper:SetText("")
			t.equal(box:GetText(), "", "cleared with the money")
		end)

		local to = SendMailNameEditBox

		t.test("the recipient stays after sending", function()
			to:SetText("Bank Alt")
			SendMailFrame_SendMail()
			SendMailFrame_Reset() -- MAIL_SEND_SUCCESS
			t.equal(to:GetText(), "Bank Alt", "name kept")
			t.equal(ns.mailRecipient.Last(), "Bank Alt", "remembered")
		end)

		t.test("a failed mail isn't remembered", function()
			to:SetText("Someone Else")
			SendMailFrame_SendMail()
			wow.fire("MAIL_FAILED")
			t.equal(ns.mailRecipient.Last(), "Bank Alt", "still the last one sent")
		end)

		t.test("opening Send Mail fills in the last recipient, unless switched off", function()
			to:SetText("")
			MailFrameTab_OnClick(nil, 2)
			t.equal(to:GetText(), "Bank Alt", "filled in")
			to:SetText("Typed Name")
			MailFrameTab_OnClick(nil, 2)
			t.equal(to:GetText(), "Typed Name", "a typed name stays")
			to:SetText("")
			MailFrameTab_OnClick(nil, 1)
			t.equal(to:GetText(), "", "not on the inbox tab")
			ns:SetSetting("mailRecipientOnOpen", false)
			MailFrameTab_OnClick(nil, 2)
			t.equal(to:GetText(), "", "option off")
		end)

		t.test("does nothing while the feature is off", function()
			ns:SetSetting("mailRecipient", false)
			to:SetText("Bank Alt")
			SendMailFrame_SendMail()
			SendMailFrame_Reset()
			t.equal(to:GetText(), "", "emptied like Blizzard does")
			ns:SetSetting("mailSubject", false)
			box:SetText("")
			mail.attached = { { name = "Linen Cloth", id = 2589, count = 1 } }
			mailSubject.Update()
			t.equal(box:GetText(), "", "untouched")
			t.noErrors()
		end)
	end,
}
