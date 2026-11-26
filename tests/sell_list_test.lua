-- Sell list: what in your bags is worth selling, the most valuable first, at the auction house
-- (Auctionator) and at a vendor; soulbound ones apart, kept ones off the list.

Enum.BagIndex = { Backpack = 0 }
-- The auction house window (its addon already loaded), and a merchant's.
CreateFrame("Frame", "AuctionHouseFrame")
CreateFrame("Frame", "MerchantFrame"):Hide()
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
C_Container.GetContainerNumSlots = function(bag)
	return bag == 0 and #BAG or 0
end
C_Container.GetContainerItemInfo = function(bag, slot)
	local item = bag == 0 and BAG[slot]
	if item then
		return { itemID = item.itemID, stackCount = item.stackCount, isBound = item.isBound,
			hyperlink = "item:" .. item.itemID, iconFileID = 1, quality = 1 }
	end
end
local picked
C_Container.PickupContainerItem = function(bag, slot)
	picked = { bag, slot }
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
}
C_Item.GetItemInfo = function(item)
	local id = tonumber(tostring(item):match("%d+"))
	local info = ITEMS[id]
	if info then
		return info[1], "item:" .. id, 1, 1, 1, "", "", 20, "", 1, info[2], 0, 0, info[3] or 0
	end
end

local AH = { [1001] = 450000, [1002] = 12000, [1003] = 10, [1006] = 20000 }
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
			local ok = wow.click("NraKit Sell list")
			t.ok(ok, "a button on the auction house")
			t.ok(_G.NraKitSellListFrame:IsShown(), "opens the list")
			t.ok(ns.UI.IsDocked(), "NraKit's window docks beside the auction house")
			local row = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "item") ~= nil
			end)[1]
			row.scripts.OnClick(row, "LeftButton")
			t.equal(picked and picked[1], 0, "clicking an item picks it up, to drop in the sell slot")
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
