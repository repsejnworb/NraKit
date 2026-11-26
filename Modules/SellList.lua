local _, ns = ...

-- Sell list: what in your bags is worth selling, most valuable first, so you don't have to
-- hover every item. A tab in the NraKit window (SellListWindow.lua), opened from a button on
-- the auction house (NraKit's window then docks beside it), from the Inventory tab, or with
-- /nra sell.
--
-- Each item is priced at the auction house (Auctionator's last scan, with how old that is)
-- and at a vendor; the better of the two is its value. Without Auctionator it's vendor
-- prices only. Groups:
--   to sell      tradeable items worth at least the minimum
--   vendor only  soulbound ones (they can't go on the auction house), folded
--   bank         your bank as Inventory tracker last saw it (an option)
--   kept         items you marked "Keep, don't list" (potions, food...), shown on request
--
-- Saved: NraKitDB.sellListKept = { [itemID] = true }, sellListSort = { key, ascending },
-- sellListOpen = { [group] = true/false } (folded or not).

local module = {
	key = "sellList",
	section = "Auction House",
	name = "Sell list",
	description = "What in your bags is worth selling, most valuable first: auction house prices (from Auctionator, if you have it) and vendor prices, side by side. A button on the auction house opens it beside it; also in the Inventory tab and with /nra sell.",
	default = false,
	options = {
		{
			key = "sellListMinValue",
			type = "number",
			name = "Leave out items worth less than",
			description = "Items worth less than this (the whole stack, at the auction house or a vendor, whichever is more) aren't listed, so grey junk doesn't crowd the list.",
			default = 5,
			min = 0,
			max = 500,
			step = 5,
			format = function(value)
				if value == 0 then
					return "list everything"
				end
				return value >= 100 and string.format("%gg", value / 100) or (value .. "s")
			end,
		},
		{
			key = "sellListBank",
			name = "Also list your bank",
			description = "A separate group with what's in your bank (as Inventory tracker last saw it), so you know what to take out before you sell.",
			default = false,
			requires = "inventoryTracker",
		},
		{
			key = "sellListAHButton",
			header = "At the auction house",
			name = "Button on the auction house",
			description = "A \"Sell list\" button at the top of the auction house window.",
			default = true,
		},
		{
			key = "sellListDock",
			name = "Open beside the auction house",
			description = "At the auction house, the list opens right next to it instead of where NraKit's windows usually are.",
			default = true,
		},
	},
}

local CALLER = "NraKit"
local STALE_DAYS = 3 -- an auction price older than this is dimmed

local sell = { STALE_DAYS = STALE_DAYS }
ns.sellList = sell

local auctionHouseOpen = false

function sell.IsAuctionHouseOpen()
	return auctionHouseOpen
end

local function API()
	return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
end

function sell.HasAuctionator()
	return API() ~= nil
end

local function Kept()
	NraKitDB.sellListKept = NraKitDB.sellListKept or {}
	return NraKitDB.sellListKept
end

function sell.IsKept(itemID)
	return Kept()[itemID] == true
end

function sell.SetKept(itemID, kept)
	Kept()[itemID] = kept or nil
	if sell.onChanged then
		sell.onChanged()
	end
end

function sell.KeptCount()
	local count = 0
	for _ in pairs(Kept()) do
		count = count + 1
	end
	return count
end

-- Auction price of one, and how many days old Auctionator's scan of it is (nil if unknown).
-- Gear goes by its link (the same item can differ), the rest by ID.
function sell.AuctionPrice(itemID, link)
	local api = API()
	if not api then
		return nil
	end
	local price, age
	if link and api.GetAuctionPriceByItemLink then
		price = api.GetAuctionPriceByItemLink(CALLER, link)
		age = api.GetAuctionAgeByItemLink and api.GetAuctionAgeByItemLink(CALLER, link)
	end
	if not price then
		price = api.GetAuctionPriceByItemID(CALLER, itemID)
		age = api.GetAuctionAgeByItemID and api.GetAuctionAgeByItemID(CALLER, itemID)
	end
	return price, age
end

function sell.DisenchantPrice(link)
	local api = API()
	return api and link and api.GetDisenchantPriceByItemLink and api.GetDisenchantPriceByItemLink(CALLER, link) or nil
end

-- Prices an item { id, link, count }: fills name, quality, icon, each (auction), age, ahTotal,
-- vendorEach, vendorTotal, value (the better), best ("ah" or "vendor"), disenchant. Returns
-- false while the client hasn't loaded the item yet.
local function Price(item)
	local name, _, quality, _, _, _, _, _, equipLoc, icon, vendorEach, _, _, bindType = C_Item.GetItemInfo(item.link or item.id)
	if not name then
		C_Item.RequestLoadItemDataByID(item.id)
		return false
	end
	item.name, item.quality, item.icon = name, item.quality or quality, item.icon or icon
	item.bindType = bindType
	item.vendorEach = vendorEach or 0
	item.vendorTotal = item.vendorEach * item.count
	item.each, item.age = sell.AuctionPrice(item.id, item.link)
	item.ahTotal = item.each and item.each * item.count or nil
	if (item.ahTotal or 0) > item.vendorTotal then
		item.value, item.best = item.ahTotal, "ah"
	else
		item.value, item.best = item.vendorTotal, "vendor"
	end
	if not item.each and equipLoc and equipLoc ~= "" then
		item.disenchant = sell.DisenchantPrice(item.link)
	end
	return true
end

-- What's in your bags, one entry per item (gear per link, since two of one item can differ):
-- { id, link, count, bound, bag, slot }. A stack that isn't soulbound makes the item sellable.
local function BagItems()
	local byKey, items = {}, {}
	for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local gear = C_Item.IsEquippableItem and C_Item.IsEquippableItem(info.itemID)
				local key = gear and info.hyperlink or info.itemID
				local item = byKey[key]
				if not item then
					item = { id = info.itemID, link = info.hyperlink, count = 0, bound = true, bag = bag, slot = slot,
						icon = info.iconFileID, quality = info.quality }
					byKey[key] = item
					table.insert(items, item)
				end
				item.count = item.count + math.max(info.stackCount or 1, 1)
				item.bound = item.bound and info.isBound == true
			end
		end
	end
	return items
end

-- Your bank as Inventory tracker last saw it: { id, count } (no links: priced by ID).
local function BankItems()
	local inventory = ns.inventory
	local realm = inventory and inventory.GetRealm()
	local me = realm and NraKitDB.inventory and NraKitDB.inventory[realm] and NraKitDB.inventory[realm][inventory.GetPlayer()]
	local items = {}
	for itemID, count in pairs(me and me.bank or {}) do
		table.insert(items, { id = itemID, count = count, inBank = true })
	end
	return items
end

local SORTS = {
	name = function(a, b)
		return (a.name or "") < (b.name or "")
	end,
	count = function(a, b)
		return a.count < b.count
	end,
	each = function(a, b)
		return (a.each or 0) < (b.each or 0)
	end,
	ah = function(a, b)
		return (a.ahTotal or 0) < (b.ahTotal or 0)
	end,
	vendor = function(a, b)
		return a.vendorTotal < b.vendorTotal
	end,
	value = function(a, b)
		return a.value < b.value
	end,
}

function sell.GetSort()
	local sort = NraKitDB.sellListSort
	if not (sort and SORTS[sort.key]) then
		return "value", false
	end
	return sort.key, sort.ascending == true
end

-- Sorts by a column; the same column again flips the order (money columns start high).
function sell.SetSort(key)
	local current, ascending = sell.GetSort()
	if current == key then
		ascending = not ascending
	else
		ascending = key == "name"
	end
	NraKitDB.sellListSort = { key = key, ascending = ascending }
	if sell.onChanged then
		sell.onChanged()
	end
end

local function SortItems(items)
	local key, ascending = sell.GetSort()
	local less = SORTS[key]
	table.sort(items, function(a, b)
		if less(a, b) ~= less(b, a) then
			if ascending then
				return less(a, b)
			end
			return less(b, a)
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return (a.name or "") < (b.name or "")
	end)
end

-- Everything, grouped: { sell = {...}, vendor = {...}, bank = {...}, kept = {...},
-- sellTotal (auction), vendorTotal (vendor, of the sell group), loading }.
function sell.Collect()
	local min = (ns:GetValue("sellListMinValue") or 5) * 100
	local groups = { sell = {}, vendor = {}, bank = {}, kept = {}, sellTotal = 0, vendorTotal = 0, loading = false }
	local function Add(item)
		if not Price(item) then
			groups.loading = true
			return
		end
		if sell.IsKept(item.id) then
			table.insert(groups.kept, item)
		elseif item.value <= 0 or item.value < min then
			return
		elseif item.inBank then
			-- Soulbound in the bank isn't known: a "binds when picked up" item can't be sold there.
			if item.best == "vendor" or item.bindType ~= 1 then
				table.insert(groups.bank, item)
			end
		elseif item.bound then
			if item.vendorTotal >= min then
				item.value, item.best = item.vendorTotal, "vendor"
				table.insert(groups.vendor, item)
			end
		else
			table.insert(groups.sell, item)
			if item.best == "ah" then
				groups.sellTotal = groups.sellTotal + item.ahTotal
			else
				groups.vendorTotal = groups.vendorTotal + item.vendorTotal
			end
		end
	end
	for _, item in ipairs(BagItems()) do
		Add(item)
	end
	if ns:GetOption("sellListBank") and ns:IsModuleEnabled("inventoryTracker") then
		for _, item in ipairs(BankItems()) do
			Add(item)
		end
	end
	for _, list in ipairs({ groups.sell, groups.vendor, groups.bank, groups.kept }) do
		SortItems(list)
	end
	return groups
end

-- Whether a group is open (to sell and bank are, vendor only and kept start folded).
function sell.IsOpen(group)
	local open = NraKitDB.sellListOpen and NraKitDB.sellListOpen[group]
	if open == nil then
		return group == "sell" or group == "bank"
	end
	return open
end

function sell.SetOpen(group, open)
	NraKitDB.sellListOpen = NraKitDB.sellListOpen or {}
	NraKitDB.sellListOpen[group] = open
	if sell.onChanged then
		sell.onChanged()
	end
end

---------------------------------------------------------------------------
-- The button on the auction house
---------------------------------------------------------------------------

local ahButton

local function UpdateAHButton()
	if not ahButton then
		return
	end
	ahButton:SetShown(ns:IsModuleEnabled(module.key) and ns:GetOption("sellListAHButton"))
end

local function CreateAHButton()
	if ahButton or type(AuctionHouseFrame) ~= "table" then
		return
	end
	ahButton = ns.UI.CreateFlatButton(AuctionHouseFrame, "NraKit Sell list", 20)
	-- Above the window's border and title, which are drawn far above the window itself.
	local title = AuctionHouseFrame.TitleContainer
	ahButton:SetFrameLevel((title and title:GetFrameLevel() or AuctionHouseFrame:GetFrameLevel() + 500) + 5)
	ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
	ahButton:SetScript("OnClick", function()
		if sell.IsWindowShown and sell.IsWindowShown() then
			sell.HideWindow()
		else
			ns:OpenSellList()
		end
	end)
	ahButton:SetScript("OnEnter", function(self)
		ns.UI.ShowTooltip(self, "Sell list", "What in your bags is worth selling, most valuable first.")
	end)
	ahButton:SetScript("OnLeave", GameTooltip_Hide)
	UpdateAHButton()
end

-- Opens the list; at the auction house (if that's the option) NraKit's window docks beside
-- it, whichever tab you go to next, until the auction house closes.
function ns:OpenSellList()
	if auctionHouseOpen and ns:GetOption("sellListDock") and type(AuctionHouseFrame) == "table"
		and AuctionHouseFrame:IsShown() and not ns.UI.IsDocked() then
		ns.UI.Dock(AuctionHouseFrame)
	end
	if sell.ShowWindow then
		sell.ShowWindow()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" then
		if addonName == "Blizzard_AuctionHouseUI" then
			CreateAHButton()
		end
	elseif event == "AUCTION_HOUSE_SHOW" then
		auctionHouseOpen = true
		CreateAHButton()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		auctionHouseOpen = false
		ns.UI.Undock()
	end
end)

function module:OnInitialize()
	eventFrame:RegisterEvent("ADDON_LOADED")
	CreateAHButton()
	ns:RegisterSlashCommand("sell", function()
		if not ns:IsModuleEnabled(module.key) then
			ns:Print("Turn on Sell list first (/nra).")
			return
		end
		ns:OpenSellList()
	end, {
		summary = "The Sell list: what in your bags is worth selling",
		usage = { "/nra sell - open the Sell list" },
	})
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	UpdateAHButton()
end

function module:OnOptionChanged()
	UpdateAHButton()
	if sell.onChanged then
		sell.onChanged()
	end
end

ns:RegisterModule(module)
