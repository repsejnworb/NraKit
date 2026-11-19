-- Mail: the Open All menu (auction gold, purchases, expired auctions, money only).

-- The inbox: { subject, money, items, invoice?, cod?, gm? }; mails with nothing left vanish.
local inbox
local function FreshInbox()
	inbox = {
		{ subject = "Auction successful: Linen Cloth", money = 50000, items = 0, invoice = "seller" },
		{ subject = "Outbid on Silk Cloth", money = 20000, items = 0 },
		{ subject = "Auction won: Mageweave Cloth", money = 0, items = 1, invoice = "buyer" },
		{ subject = "Auction expired: Wool Cloth", money = 0, items = 1 },
		{ subject = "Auction cancelled: Iron Ore", money = 0, items = 1 },
		{ subject = "Mats for you", money = 30000, items = 2 }, -- from a player
		{ subject = "Pay me", money = 0, items = 1, cod = 10000 },
		{ subject = "Restored items", money = 10000, items = 1, gm = true },
	}
end
FreshInbox()

GetInboxNumItems = function()
	return #inbox
end
GetInboxHeaderInfo = function(index)
	local mail = inbox[index]
	return nil, nil, "Someone", mail.subject, mail.money, mail.cod or 0, 30, mail.items, false, false, false, true, mail.gm == true
end
GetInboxInvoiceInfo = function(index)
	return inbox[index].invoice
end
TakeInboxMoney = function(index)
	inbox[index].money = 0
	if inbox[index].items == 0 then
		table.remove(inbox, index)
	end
end

C_Mail = { IsCommandPending = function()
	return false
end }

-- Blizzard's Open All button, with hooksecurefunc really hooking its methods here.
local clicked = 0
OpenAllMail = CreateFrame("Button")
rawset(OpenAllMail, "ShouldSkipCurrentMail", function(self)
	local mail = inbox[self.mailIndex]
	return mail.gm or (mail.cod or 0) > 0 -- Blizzard's own rules
end)
rawset(OpenAllMail, "StopOpening", function() end)
rawset(OpenAllMail, "Click", function()
	clicked = clicked + 1
end)
rawset(OpenAllMail, "IsEnabled", function()
	return true
end)
local hook = hooksecurefunc
hooksecurefunc = function(target, name, fn)
	if type(target) == "table" then
		local original = target[name]
		rawset(target, name, function(...)
			original(...)
			fn(...)
		end)
	else
		hook(target, name, fn)
	end
end

return {
	enable = { "mail" },
	run = function(t, ns, wow)
		local menu
		MenuUtil.CreateContextMenu = function(_, generator)
			menu = wow.newMenu()
			generator(nil, menu)
		end
		local arrow
		for _, frame in ipairs(wow.frames) do
			if rawget(frame, "scripts") and frame.scripts.OnClick and rawget(frame, "kind") == "Button"
				and frame ~= OpenAllMail and frame:GetParent() == OpenAllMail:GetParent() then
				arrow = frame
			end
		end
		local function Open()
			arrow.scripts.OnClick(arrow)
			return menu.entries
		end
		local function Entry(label)
			for _, entry in ipairs(Open()) do
				if type(entry.text) == "string" and entry.text:find(label, 1, true) == 1 then
					return entry
				end
			end
		end
		-- Which mails Blizzard's Open All would open now.
		local function Opened()
			local list = {}
			for index, mail in ipairs(inbox) do
				OpenAllMail.mailIndex = index
				if not OpenAllMail:ShouldSkipCurrentMail() then
					table.insert(list, mail.subject)
				end
			end
			return table.concat(list, " | ")
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
		end

		t.test("the menu says what each entry would take", function()
			t.ok(arrow, "an arrow next to Open All")
			t.ok(Entry("Collect auction gold").text:find("(2 mails, 7g)", 1, true), "sold and outbid: " .. Entry("Collect auction gold").text)
			t.ok(Entry("Collect auction purchases").text:find("(1 mail)", 1, true), "won")
			t.ok(Entry("Collect expired auctions").text:find("(2 mails)", 1, true), "expired and cancelled")
			t.ok(Entry("Take money only").text:find("(3 mails, 10g)", 1, true), "every mail with gold, not C.O.D. or GM")
			t.ok(Entry("Collect auction gold").enabled, "enabled")
		end)

		t.test("auction gold: the sold and outbid mails' gold, nothing else", function()
			Entry("Collect auction gold").onClick()
			for _ = 1, 6 do
				wow.advance(0.3)
			end
			t.equal(#inbox, 6, "the two emptied mails are gone")
			t.equal(inbox[4].money, 30000, "a player's gold left alone")
			t.ok(Printed("Collected 7g from 2 mails"), "says what it took")
			t.equal(clicked, 0, "Blizzard's Open All not used")
			t.equal(Entry("Collect auction gold").enabled, false, "nothing left: greyed out")
		end)

		t.test("money only: the gold, and the items stay", function()
			Entry("Take money only").onClick()
			for _ = 1, 6 do
				wow.advance(0.3)
			end
			t.equal(inbox[4].money, 0, "gold taken")
			t.equal(inbox[4].items, 2, "items still there")
			t.equal(inbox[6].money, 10000, "GM mail untouched")
		end)

		t.test("purchases and expired auctions run Open All on just those mails", function()
			FreshInbox()
			t.equal(Opened(), "Auction successful: Linen Cloth | Outbid on Silk Cloth | Auction won: Mageweave Cloth"
				.. " | Auction expired: Wool Cloth | Auction cancelled: Iron Ore | Mats for you", "Open All alone")
			Entry("Collect auction purchases").onClick()
			t.equal(clicked, 1, "Open All started")
			t.equal(Opened(), "Auction won: Mageweave Cloth", "only the purchase")
			OpenAllMail:StopOpening()
			t.ok(Opened():find("Mats for you", 1, true), "back to normal when it stops")
			Entry("Collect expired auctions").onClick()
			t.equal(Opened(), "Auction expired: Wool Cloth | Auction cancelled: Iron Ore", "only the expired and cancelled")
			OpenAllMail:StopOpening()
		end)

		t.test("the arrow goes with the option", function()
			ns:SetSetting("mailOpenMenu", false)
			t.ok(not arrow:IsShown(), "hidden")
			ns:SetSetting("mailOpenMenu", true)
			t.ok(arrow:IsShown(), "back")
			t.noErrors()
		end)
	end,
}
