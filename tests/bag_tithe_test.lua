-- Bag Tithe: the least valuable bag slots, priced at a vendor or (Auctionator) the auction
-- house when that's more; soulbound items at vendor price.

Enum.BagIndex = { Backpack = 0 }
local BAG = {
	{ itemID = 1, stackCount = 20 }, -- Silk Cloth: 1s50c at a vendor, 30s at the auction house
	{ itemID = 2, stackCount = 1 }, -- a grey: 5s at a vendor, no auction price
	{ itemID = 3, stackCount = 1, isBound = true }, -- soulbound: 1s at a vendor (its auction price doesn't count)
}
C_Container.GetContainerNumSlots = function(bag)
	return bag == 0 and #BAG or 0
end
C_Container.GetContainerItemInfo = function(bag, slot)
	local item = bag == 0 and BAG[slot]
	if item then
		return { itemID = item.itemID, stackCount = item.stackCount, isBound = item.isBound, hyperlink = "item:" .. item.itemID }
	end
end
local VENDOR = { [1] = 150, [2] = 500, [3] = 100 }
C_Item.GetItemInfo = function(item)
	local id = tonumber(tostring(item):match("%d+"))
	return "Item " .. id, "item:" .. id, 1, 1, 1, "", "", 20, "", 1, VENDOR[id]
end
local AH = { [1] = 3000, [3] = 999999 }
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(_, id)
		return AH[id]
	end,
	GetAuctionPriceByItemLink = function(_, link)
		return AH[tonumber(tostring(link):match("%d+"))]
	end,
} } }

return {
	enable = { "bagTithe" },
	run = function(t, ns)
		local function Ranks()
			local ranked = ns.BagTithe.RankSlots()
			return ranked[1], ranked[2], ranked[3] -- slot keys are bag * 1000 + slot: bag 0
		end

		t.test("with auction prices, a valuable trade good isn't junk", function()
			local silk, grey, bound = Ranks()
			t.equal(bound.rank, 1, "the soulbound item: 1s at a vendor (its auction price doesn't count)")
			t.equal(grey.rank, 2, "the grey: 5s")
			t.equal(silk.rank, 3, "the Silk Cloth last: 20 x 30s at the auction house")
			t.equal(silk.value, 20 * 3000, "worth its auction price")
		end)

		t.test("with the option off, vendor prices only", function()
			ns:SetSetting("bagTitheAuction", false)
			local silk, grey = Ranks()
			t.equal(silk.value, 20 * 150, "Silk Cloth at vendor price")
			t.ok(grey.rank < silk.rank, "the grey (5s) still under 20 Silk Cloth (30s)")
			ns:SetSetting("bagTitheAuction", true)
			t.noErrors()
		end)
	end,
}
