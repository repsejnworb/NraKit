-- Sell List: what in your bags is worth selling, the most valuable first, at the auction house
-- (Auctionator) and at a vendor; soulbound ones apart, kept ones off the list.

Enum.BagIndex = { Backpack = 0, Bag_1 = 1, CharacterBankTab_1 = 6 }
-- The auction house window (its addon already loaded), and a merchant's.
CreateFrame("Frame", "AuctionHouseFrame")
CreateFrame("Frame", "MerchantFrame"):Hide()
CreateFrame("Frame", "BankFrame"):Hide()
CreateFrame("Frame", "MailFrame"):Hide()
CreateFrame("Frame", "OpenMailFrame"):Hide()
-- The bank's page tabs down its right side, 50 wide (Forever's BankFrame.bankPageTabPool).
local bankTab = CreateFrame("Frame")
bankTab:SetWidth(50)
rawset(BankFrame, "bankPageTabPool", { EnumerateActive = function()
	local done = false
	return function()
		if not done then
			done = true
			return bankTab
		end
	end
end })
rawset(MerchantFrame, "page", 1)

-- Your bags: one bag with these slots.
local BAG = {
	{ itemID = 1001, stackCount = 3 }, -- Black Lotus: 45g each at the AH
	{ itemID = 1002, stackCount = 20 }, -- Mithril Bar: 1g20s at the AH, 50c at a vendor
	{ itemID = 1002, stackCount = 38 }, -- (a second stack)
	{ itemID = 1003, stackCount = 5 }, -- Wolf Meat: 3s at a vendor beats the AH's 10c
	{ itemID = 1004, stackCount = 1, isBound = true }, -- a soulbound ring: 50s at a vendor
	{ itemID = 1005, stackCount = 1 }, -- junk: 5c
	{ itemID = 1006, stackCount = 2 }, -- an old auction price: 2g, 6 days old
}
-- A second bag with 4 empty slots, and the bank's first tab (bag 6).
local BAG_SIZE = { [0] = #BAG, [1] = 4, [6] = 4 }
local CONTAINERS = { [0] = BAG, [1] = {}, [6] = {} }
C_Container.GetContainerNumSlots = function(bag)
	return BAG_SIZE[bag] or 0
end
C_Container.GetContainerItemInfo = function(bag, slot)
	local item = CONTAINERS[bag] and CONTAINERS[bag][slot]
	if item then
		return { itemID = item.itemID, stackCount = item.stackCount, isBound = item.isBound,
			hyperlink = "item:" .. item.itemID, iconFileID = 1, quality = 1 }
	end
end
C_Container.GetContainerItemID = function(bag, slot)
	local item = CONTAINERS[bag] and CONTAINERS[bag][slot]
	return item and item.itemID
end
C_Container.GetContainerNumFreeSlots = function()
	return 0, 0
end
-- The cursor, like the game: pick up from a slot, then put down in another (or split part).
local cursor, picked
C_Container.PickupContainerItem = function(bag, slot)
	picked = { bag, slot }
	local items = CONTAINERS[bag]
	if cursor then
		if not items[slot] then
			items[slot], cursor = cursor, nil
		end
	else
		cursor, items[slot] = items[slot], nil
	end
end
C_Container.SplitContainerItem = function(bag, slot, amount)
	local item = CONTAINERS[bag][slot]
	item.stackCount = item.stackCount - amount
	cursor = { itemID = item.itemID, stackCount = amount }
end
GetCursorInfo = function()
	return cursor and "item" or nil
end

-- The mailbox: a mail with two stacks of Thorium Bar, and a C.O.D. one with a third.
local INBOX = {}
GetInboxNumItems = function()
	return #INBOX
end
GetInboxHeaderInfo = function(index)
	local mail = INBOX[index]
	return nil, nil, "Bob", "Thorium", 0, mail.cod, 3, #mail.items
end
GetInboxItem = function(index, attachment)
	local item = INBOX[index] and INBOX[index].items[attachment]
	if item then
		return "Thorium Bar", item.itemID, 1, item.stackCount, 1
	end
end
TakeInboxItem = function(index, attachment)
	local item = table.remove(INBOX[index].items, attachment)
	for slot = 1, 4 do
		if not CONTAINERS[1][slot] then
			CONTAINERS[1][slot] = item
			return
		end
	end
end
-- Alt+click hands the item, with its bag slot, to HandleModifiedItemClick (Auctionator hooks it).
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot)
	return { bag = bag, slot = slot }
end }
local handed
HandleModifiedItemClick = function(link, location)
	handed = { link = link, location = location }
end

-- name, sell price, bind type
local ITEMS = {
	[1001] = { "Black Lotus", 0 }, [1002] = { "Mithril Bar", 50 }, [1003] = { "Wolf Meat", 300 },
	[1004] = { "Soulbound Ring", 5000, 1 }, [1005] = { "Broken Fang", 5 }, [1006] = { "Old Price", 100 },
	[1007] = { "Banked Gem", 100 }, [1008] = { "Pickup Trinket", 2000, 1 },
	[1009] = { "Thorium Bar", 100 }, [1010] = { "Arcane Crystal", 1000 },
}
C_Item.GetItemInfo = function(item)
	local id = tonumber(tostring(item):match("%d+"))
	local info = ITEMS[id]
	if info then
		return info[1], "item:" .. id, 1, 1, 1, "", "", 20, "", 1, info[2], 0, 0, info[3] or 0
	end
end

local AH = { [1001] = 450000, [1002] = 12000, [1003] = 10, [1006] = 20000, [1007] = 90000, [1008] = 70000,
	[1009] = 5000, [1010] = 900000 }
local AGE = { [1006] = 6 }
local function ID(link)
	return tonumber(tostring(link):match("%d+"))
end
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(_, id)
		return AH[id]
	end,
	GetAuctionPriceByItemLink = function(_, link)
		return AH[ID(link)]
	end,
	GetAuctionAgeByItemID = function(_, id)
		return AGE[id] or 0
	end,
	GetAuctionAgeByItemLink = function(_, link)
		return AGE[ID(link)] or 0
	end,
} } }

return {
	enable = { "sellList", "auctionatorPrices", "inventoryTracker" },
	run = function(t, ns, wow)
		local sell = ns.sellList
		local function Names(list)
			local names = {}
			for _, item in ipairs(list) do
				table.insert(names, item.name)
			end
			return table.concat(names, ", ")
		end

		t.test("split by where each sells best, the most valuable first", function()
			local groups = sell.Collect()
			t.equal(Names(groups.ah), "Black Lotus, Mithril Bar, Old Price", "to sell at the auction house")
			local bar = groups.ah[2]
			t.equal(bar.count, 58, "both stacks of Mithril Bar")
			t.equal(bar.ahTotal, 58 * 12000, "at the AH")
			t.equal(bar.groupEach, 12000, "each: the auction price of one")
			t.equal(groups.ah[3].age, 6, "how old the price is")
			t.equal(groups.ahTotal, 3 * 450000 + 58 * 12000 + 2 * 20000, "auction total")
			t.equal(Names(groups.vendor), "Soulbound Ring, Wolf Meat", "to sell at a vendor, soulbound too")
			t.equal(groups.vendor[2].groupEach, 300, "each: the vendor price of one")
			t.equal(groups.vendorTotal, 5000 + 5 * 300, "vendor total")
		end)

		t.test("junk below the minimum is left out", function()
			t.ok(not Names(sell.Collect().vendor):find("Broken Fang", 1, true), "5c is below 5s")
			ns:SetSetting("sellListMinValue", 0)
			t.ok(Names(sell.Collect().vendor):find("Broken Fang", 1, true), "listed with no minimum")
			ns:SetSetting("sellListMinValue", 5)
		end)

		t.test("kept items stay off the list", function()
			sell.SetKept(1002, true)
			local groups = sell.Collect()
			t.ok(not Names(groups.ah):find("Mithril", 1, true), "not to sell")
			t.equal(Names(groups.kept), "Mithril Bar", "but under Kept")
			sell.SetKept(1002, false)
			t.ok(Names(sell.Collect().ah):find("Mithril", 1, true), "listed again")
		end)

		t.test("click a column to sort by it, again to turn it around", function()
			sell.SetSort("name")
			t.equal(Names(sell.Collect().ah), "Black Lotus, Mithril Bar, Old Price", "A to Z")
			sell.SetSort("name")
			t.equal(Names(sell.Collect().ah), "Old Price, Mithril Bar, Black Lotus", "Z to A")
			sell.SetSort("vendor")
			t.equal(sell.Collect().ah[1].name, "Mithril Bar", "money columns start high (29s at a vendor)")
			sell.SetSort("value")
		end)

		t.test("the window lists them, with totals", function()
			ns:OpenSellList()
			t.ok(_G.NraKitSellListFrame:IsShown(), "open")
			local rows = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "item") ~= nil
			end)
			t.equal(#rows, 5, "a row for each item to sell, at the auction house and a vendor")
		end)

		t.test("at the auction house: a button, the list beside it, closing with it", function()
			_G.NraKitSellListFrame:Hide()
			wow.fire("AUCTION_HOUSE_SHOW")
			local ok = wow.click("NraKit Sell List")
			t.ok(ok, "a button on the auction house")
			t.ok(_G.NraKitSellListFrame:IsShown(), "opens the list")
			t.ok(ns.UI.IsDocked(), "NraKit's window docks beside the auction house")
			local row = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "item") ~= nil
			end)[1]
			row.scripts.OnClick(row, "LeftButton")
			t.equal(picked and picked[1], 0, "clicking an item picks it up, to drop in the sell slot")
			C_Container.PickupContainerItem(picked[1], picked[2]) -- (and put it back)
			IsModifiedClick = function()
				return true
			end
			row.scripts.OnClick(row, "LeftButton")
			IsModifiedClick = function() end
			t.equal(handed and handed.location and handed.location.bag, 0,
				"Alt+click hands it on with its bag slot, for Auctionator's Selling tab")
			ns.UI.ShowTab("settings")
			t.ok(ns.UI.IsDocked(), "another tab stays docked")
			wow.fire("AUCTION_HOUSE_CLOSED")
			t.ok(not ns.UI.IsDocked(), "undocked when the auction house closes")
			t.ok(not _G.NraKitOptionsFrame:IsShown(), "and the window closes with it")
		end)

		t.test("opening the auction house opens the list beside it, unless that's off", function()
			AuctionHouseFrame:Hide()
			AuctionHouseFrame:Show()
			t.ok(_G.NraKitSellListFrame:IsShown(), "opened by itself")
			t.ok(ns.UI.IsDocked(), "beside the auction house")
			local check = wow.findAll(function(frame)
				local label = rawget(frame, "Text")
				return wow.visible(frame) and label and label.text == "Open by itself at the auction house"
			end)[1]
			t.ok(check and check:GetChecked(), "a switch at the top of the list, on")
			check:SetChecked(false)
			check.scripts.OnClick(check)
			t.equal(NraKitDB.sellListAutoOpen, false, "turned off from the list")
			wow.fire("AUCTION_HOUSE_CLOSED")
			AuctionHouseFrame:Hide()
			AuctionHouseFrame:Show()
			t.ok(not _G.NraKitSellListFrame:IsShown(), "then it doesn't open by itself")
			wow.fire("AUCTION_HOUSE_CLOSED")
			ns:SetSetting("sellListAutoOpen", true)
		end)

		t.test("at the auction house the vendor group starts folded; each place remembers its own", function()
			wow.fire("AUCTION_HOUSE_SHOW")
			t.ok(sell.IsOpen("ah") and not sell.IsOpen("vendor"), "auctioning: vendor folded")
			sell.SetOpen("vendor", true)
			t.ok(sell.IsOpen("vendor"), "opened by hand")
			wow.fire("AUCTION_HOUSE_CLOSED")
			t.ok(sell.IsOpen("vendor") and sell.IsOpen("ah"), "away: both open")
			wow.fire("AUCTION_HOUSE_SHOW")
			t.ok(sell.IsOpen("vendor"), "back at the auction house: as you left it")
			wow.fire("AUCTION_HOUSE_CLOSED")
		end)

		t.test("at merchants (an option) it docks there, vendor group first", function()
			MerchantFrame:Hide()
			MerchantFrame:Show()
			t.ok(not _G.NraKitSellListFrame:IsShown(), "off by default")
			wow.fire("MERCHANT_CLOSED")
			ns:SetSetting("sellListMerchantOpen", true)
			MerchantFrame:Hide()
			MerchantFrame:Show()
			t.ok(_G.NraKitSellListFrame:IsShown(), "opens at the merchant")
			t.ok(ns.UI.IsDocked(), "beside it")
			t.ok(sell.IsOpen("vendor") and not sell.IsOpen("ah"), "vendor open, auction house folded")
			wow.fire("MERCHANT_CLOSED")
			t.ok(not ns.UI.IsDocked() and not _G.NraKitSellListFrame:IsShown(), "closes with the merchant")
			ns:SetSetting("sellListMerchantOpen", false)
		end)

		t.test("a fresh scan while it's open says prices have changed, until you refresh", function()
			ns:OpenSellList()
			t.ok(not ns.sellList.PricesChanged(), "the same as shown")
			AH[1001] = 470000
			t.ok(ns.sellList.PricesChanged(), "Black Lotus changed")
			wow.advance(2.5)
			local notice = wow.findAll(function(frame)
				return wow.visible(frame) and frame.text == "Prices have changed: refresh"
			end)
			t.equal(#notice, 1, "the notice by the refresh button")
			ns.sellList.onChanged() -- what the refresh button does
			t.ok(not ns.sellList.PricesChanged(), "refreshed")
			AH[1001] = 450000
			_G.NraKitSellListFrame:Hide()
		end)

		t.test("Bank and Mail switches mix those items in, marked, and not clickable", function()
			local me = NraKitDB.inventory[ns.inventory.GetRealm()][ns.inventory.GetPlayer()]
			me.bank = { [1007] = 2, [1008] = 1 } -- a gem, and a "binds when picked up" trinket
			me.mail = { [1001] = 1 } -- a Black Lotus bought at the auction house
			me.seen = me.seen or {}
			me.seen.bank = time() - 2 * 86400
			t.equal(#sell.Collect().ah, 3, "off by default: just your bags")

			ns:OpenSellList()
			t.ok(wow.click("Bank"), "the Bank switch")
			t.equal(NraKitDB.sellListBank, true, "remembered")
			local groups = sell.Collect()
			local gem
			for _, item in ipairs(groups.ah) do
				if item.name == "Banked Gem" then
					gem = item
				end
			end
			t.ok(gem and gem.where == "bank", "the gem, among the auction house ones")
			t.ok(Names(groups.vendor):find("Pickup Trinket", 1, true), "a binds-when-picked-up one only at a vendor")
			t.equal(groups.elsewhereTotal, 2 * 90000 + 2000, "counted apart")
			t.equal(groups.ahTotal, 3 * 450000 + 58 * 12000 + 2 * 20000, "the main total is still your bags'")

			wow.click("Mail")
			local lotus = 0
			for _, item in ipairs(sell.Collect().ah) do
				if item.name == "Black Lotus" then
					lotus = lotus + 1
				end
			end
			t.equal(lotus, 2, "Black Lotus twice: in your bags, and in your mail")

			sell.onChanged()
			local row = wow.findAll(function(frame)
				local item = wow.visible(frame) and rawget(frame, "item")
				return item and item.where == "bank"
			end)[1]
			t.ok(row and rawget(row, "place").shown, "a bank badge on its icon")
			picked = nil
			wow.fire("AUCTION_HOUSE_SHOW")
			row.scripts.OnClick(row, "LeftButton")
			t.equal(picked, nil, "a bank item can't be picked up from here")
			wow.fire("AUCTION_HOUSE_CLOSED")
			ns:SetSetting("sellListBank", false)
			ns:SetSetting("sellListMail", false)
		end)

		t.test("at the bank: click to take, a prompt for more than one stack", function()
			cursor = nil
			CONTAINERS[6] = {
				{ itemID = 1009, stackCount = 20 }, { itemID = 1009, stackCount = 20 }, { itemID = 1009, stackCount = 5 },
				{ itemID = 1010, stackCount = 1 },
			}
			ns:SetSetting("sellListBank", true)
			wow.fire("BANKFRAME_OPENED")
			ns:OpenSellList()
			local function Row(name)
				return wow.findAll(function(frame)
					local item = wow.visible(frame) and rawget(frame, "item")
					return item and item.where == "bank" and item.name == name
				end)[1]
			end
			local crystal = Row("Arcane Crystal")
			t.ok(crystal and crystal.item.slots, "read live from the bank")
			crystal.scripts.OnClick(crystal, "LeftButton")
			wow.advance(0.3)
			t.equal(C_Container.GetContainerItemID(1, 1), 1010, "one stack: taken at once")
			t.equal(CONTAINERS[6][4], nil, "out of the bank")
			wow.advance(0.3)

			sell.onChanged()
			local bars = Row("Thorium Bar")
			bars.scripts.OnClick(bars, "LeftButton")
			local prompt = sell.Prompt()
			t.ok(prompt and prompt:IsShown(), "three stacks: it asks")
			t.equal(prompt.stacks, 3, "starting at all that fits (3 free slots)")
			prompt.minus.scripts.OnClick(prompt.minus)
			prompt.take.scripts.OnClick(prompt.take)
			for _ = 1, 5 do
				wow.advance(0.3)
			end
			t.equal(CONTAINERS[1][2].stackCount + CONTAINERS[1][3].stackCount, 40, "two stacks in your bags")
			t.equal(CONTAINERS[6][3].stackCount, 5, "the rest still in the bank")
			t.ok(sell.TakeStatus():find("Took 40", 1, true), "says what it took")

			sell.onChanged()
			bars = Row("Thorium Bar")
			IsShiftKeyDown = function()
				return true
			end
			bars.scripts.OnClick(bars, "LeftButton")
			IsShiftKeyDown = function() end
			wow.advance(0.3)
			t.equal(CONTAINERS[1][4] and CONTAINERS[1][4].stackCount, 5, "Shift-click: the rest, without asking")
			wow.advance(0.3)
			wow.fire("BANKFRAME_CLOSED")
			ns:SetSetting("sellListBank", false)
		end)

		t.test("a button on the bank and mailbox opens the list beside them", function()
			CONTAINERS[6] = { { itemID = 1010, stackCount = 1 } }
			BankFrame:Show()
			wow.fire("BANKFRAME_OPENED")
			_G.NraKitSellListFrame:Hide()
			local buttons = wow.findAll(function(frame)
				return rawget(frame, "parent") == BankFrame and rawget(frame, "text") and frame.text.text == "NraKit Sell List"
			end)
			t.equal(#buttons, 1, "a button on the bank")
			buttons[1].scripts.OnClick(buttons[1])
			t.ok(_G.NraKitSellListFrame:IsShown() and ns.UI.IsDocked(), "the list, beside the bank")
			local anchor, x = ns.UI.DockAnchor()
			t.ok(anchor == BankFrame and x == 56, "past the bank's side tabs (50 wide): " .. tostring(x))
			local listed = false
			for _, item in ipairs(sell.Collect().ah) do
				listed = listed or item.where == "bank"
			end
			t.ok(listed, "at the bank, the bank is listed even with its switch off")
			wow.fire("BANKFRAME_CLOSED")
			BankFrame:Hide()
			t.ok(not ns.UI.IsDocked() and not _G.NraKitSellListFrame:IsShown(), "closes with the bank")
			local mailButtons = wow.findAll(function(frame)
				return rawget(frame, "parent") == MailFrame and rawget(frame, "text") and frame.text.text == "NraKit Sell List"
			end)
			t.equal(#mailButtons, 1, "and one on the mailbox")
			MailFrame:Show()
			wow.fire("MAIL_SHOW")
			mailButtons[1].scripts.OnClick(mailButtons[1])
			t.equal(ns.UI.DockAnchor(), MailFrame, "beside the mailbox")
			OpenMailFrame:Show()
			t.equal(ns.UI.DockAnchor(), OpenMailFrame, "opening a mail moves it past the mail")
			OpenMailFrame:Hide()
			t.equal(ns.UI.DockAnchor(), MailFrame, "and back when it closes")
			wow.fire("MAIL_CLOSED")
			MailFrame:Hide()
			CONTAINERS[6] = {}
		end)

		t.test("bags too full for it all: Take All says how many fit", function()
			CONTAINERS[1] = { { itemID = 1, stackCount = 1 }, { itemID = 1, stackCount = 1 }, { itemID = 1, stackCount = 1 } }
			CONTAINERS[6] = { { itemID = 1009, stackCount = 20 }, { itemID = 1009, stackCount = 20 } }
			ns:SetSetting("sellListBank", true)
			wow.fire("BANKFRAME_OPENED")
			local bars
			for _, item in ipairs(sell.Collect().ah) do
				if item.where == "bank" then
					bars = item
				end
			end
			sell.AskTake(bars, UIParent)
			t.equal(sell.Prompt().all.text.text, "Take 1 (All That Fit)", "room for one")
			-- Regression: it was on the list's own layer, so it drew behind it.
			t.equal(sell.Prompt():GetFrameStrata(), "FULLSCREEN_DIALOG", "above the list")
			sell.HidePrompt()
			wow.fire("BANKFRAME_CLOSED")
			ns:SetSetting("sellListBank", false)
			CONTAINERS[1] = {}
		end)

		t.test("at the mailbox: take its stacks one at a time; C.O.D. mail isn't listed", function()
			INBOX = {
				{ cod = 0, items = { { itemID = 1009, stackCount = 20 }, { itemID = 1009, stackCount = 20 } } },
				{ cod = 5000, items = { { itemID = 1009, stackCount = 20 } } },
			}
			ns:SetSetting("sellListMail", true)
			wow.fire("MAIL_SHOW")
			local bars
			for _, item in ipairs(sell.Collect().ah) do
				if item.where == "mail" then
					bars = item
				end
			end
			t.equal(bars.count, 40, "the C.O.D. stack left out")
			t.ok(sell.Take(bars), "take them")
			for _ = 1, 4 do
				wow.advance(0.6)
				wow.fire("MAIL_INBOX_UPDATE")
			end
			t.equal(#INBOX[1].items, 0, "both taken")
			t.equal(#INBOX[2].items, 1, "the C.O.D. one left alone")
			t.equal(CONTAINERS[1][1].stackCount + CONTAINERS[1][2].stackCount, 40, "in your bags")
			wow.fire("MAIL_CLOSED")
			ns:SetSetting("sellListMail", false)
		end)

		t.test("the Inventory tab values everyone's items at auction prices", function()
			local value = ns.auctionator.InventoryValue({ bags = { [1001] = 2 }, bank = { [1002] = 10 }, mail = { [1006] = 1 } })
			t.equal(value, 2 * 450000 + 10 * 12000 + 20000, "bags, bank and mail")
			ns:SetSetting("auctionatorInventoryValue", false)
			t.equal(ns.auctionator.InventoryValue({ bags = { [1001] = 2 } }), nil, "not with the option off")
			ns:SetSetting("auctionatorInventoryValue", true)
		end)

		t.test("without Auctionator it's vendor prices", function()
			local saved = Auctionator
			Auctionator = nil
			local groups = sell.Collect()
			t.equal(#groups.ah, 0, "nothing to sell at the auction house")
			t.equal(groups.vendor[1].best, "vendor", "vendor prices only")
			Auctionator = saved
			t.noErrors()
		end)
	end,
}
