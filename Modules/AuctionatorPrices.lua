local _, ns = ...

-- Auctionator prices: what things cost, from Auctionator's last scan (and vendor prices).
--
--   Waylaid Crates   A crate takes any one bundle from its list (8 Iron Strut or 5 Mithril
--                    Tube...), all at once. Its tooltip prices each bundle and marks the
--                    cheapest; an Auctionator list, "Waylaid Crates", holds every bundle of
--                    the crates in your bags.
--   Recipes          A recipe's tooltip (a recipe link) shows what one craft's reagents cost.
--                    Right-click a recipe (chat link, profession window) to make an
--                    Auctionator list of its reagents, or add them to the NraKit Shopping
--                    List (a tab in the NraKit window, ShoppingListWindow.lua), which
--                    Auctionator gets a copy of.
--   Vendor prices    Bought from merchants, remembered when you visit one (Auctionator's
--                    vendor prices fill the gaps). A reagent sold by a vendor is priced at
--                    that and tagged "vendor", and is left out of Auctionator lists.
--
-- Only Auctionator's public API (Auctionator.API.v1) is used. Creating a list while the
-- auction house is open starts a search, so lists made by themselves (the crates, the copy of
-- the Shopping List) are only written while it's closed.

local module = {
	key = "auctionatorPrices",
	section = "Professions",
	name = "Auctionator prices",
	description = "Needs the Auctionator addon. What Waylaid Crates and recipes cost at the auction house (from Auctionator's last scan, or the vendor's price), shopping lists for Auctionator from recipes, and the NraKit Shopping List for everything you're crafting.",
	default = false,
	options = {
		{
			key = "auctionatorCrates",
			header = "Waylaid Crates",
			name = "Prices on Waylaid Crates",
			description = "A Waylaid Crate's tooltip shows what each bundle it takes costs, with the cheapest in green.",
			default = true,
		},
		{
			key = "auctionatorCratesList",
			parent = "auctionatorCrates",
			name = "\"Waylaid Crates\" shopping list",
			description = "Keep an Auctionator shopping list called \"Waylaid Crates\" with every bundle the crates in your bags take, in the amounts they need. It's rewritten when your crates change (not while the auction house is open).",
			default = true,
		},
		{
			key = "auctionatorRecipes",
			header = "Recipes",
			name = "Cost of one craft on recipes",
			description = "A recipe's tooltip (click a recipe link in chat) shows what the reagents for one craft cost, and the total.",
			default = true,
		},
		{
			key = "auctionatorShopping",
			name = "Shopping lists from recipes",
			description = "Right-click a recipe link in chat or a recipe in your profession window (or use the Shopping list button there) to make an Auctionator shopping list of its reagents, or to add them to the NraKit Shopping List.",
			default = true,
		},
		{
			key = "auctionatorUnitPrice",
			header = "General",
			name = "Show the price per item",
			description = "In tooltips, also show what one of each reagent costs.",
			default = false,
		},
		{
			key = "auctionatorHave",
			name = "Show how many you have",
			description = "In tooltips, how many of each reagent you have on all your characters (with Inventory Tracker on; else in your bags and bank): green if your bags hold enough, yellow if you have enough elsewhere (bank, other characters), grey if not. A recipe also shows what's left to buy.",
			default = true,
		},
		{
			key = "auctionatorSkipVendor",
			name = "Leave vendor items out of Auctionator lists",
			description = "Reagents sold by a vendor (thread, dye, vials...) aren't searched for at the auction house. They still show in tooltips and the NraKit Shopping List.",
			default = true,
		},
	},
}

local CALLER = "NraKit"
local CRATES_LIST = "Waylaid Crates"
local SHOPPING_LIST = "NraKit Shopping List"
local VENDOR_TAG = " |cff999999vendor|r"
local HAVE_HERE, HAVE_ELSEWHERE, HAVE_SHORT = "ff4cff4c", "ffffd100", "ff999999"


-- Crate item ID -> its bundles, { count, reagent item ID }, in the order the tooltip lists them.
local CRATES = {
	-- Herbs
	[248682] = { { 20, 2447 }, { 20, 765 }, { 10, 2449 }, { 10, 785 }, { 10, 2450 } },
	[248686] = { { 10, 3820 }, { 10, 2453 }, { 10, 3355 }, { 10, 3369 }, { 10, 3356 } },
	[248690] = { { 20, 3357 }, { 10, 3818 }, { 10, 3821 }, { 10, 3358 } },
	[248691] = { { 10, 3819 }, { 10, 4625 }, { 20, 8831 }, { 10, 8836 } },
	[248695] = { { 10, 13464 }, { 20, 8838 }, { 10, 8839 }, { 10, 8845 }, { 10, 8846 } },
	[248696] = { { 20, 13463 }, { 20, 13465 }, { 20, 13466 }, { 20, 13467 } },
	-- Ore
	[248683] = { { 20, 2770 }, { 20, 2771 } },
	[248687] = { { 10, 2775 }, { 20, 2772 } },
	[248692] = { { 10, 2776 }, { 20, 3858 } },
	[248697] = { { 10, 7911 }, { 20, 10620 }, { 20, 11370 } },
	-- Ingots
	[248703] = { { 20, 2840 }, { 20, 3576 }, { 10, 2841 } },
	[248706] = { { 10, 2842 }, { 20, 3575 } },
	[248709] = { { 20, 3860 }, { 15, 3859 }, { 10, 3577 } },
	[248712] = { { 2, 11371 }, { 10, 6037 }, { 20, 12359 } },
	-- Parts
	[248704] = { { 16, 4359 }, { 16, 4361 }, { 4, 4363 } },
	[248707] = { { 8, 4371 }, { 7, 4375 }, { 4, 4382 }, { 45, 10558 } },
	[248710] = { { 8, 4387 }, { 5, 10559 }, { 12, 10560 }, { 5, 10561 } },
	[248713] = { { 5, 15994 }, { 5, 18631 }, { 2, 16000 } },
	-- Textiles
	[248684] = { { 40, 2589 }, { 20, 2318 } },
	[248688] = { { 20, 2592 }, { 40, 4306 }, { 20, 2319 } },
	[248693] = { { 40, 4338 }, { 20, 4234 } },
	[248698] = { { 40, 14047 }, { 20, 4304 }, { 20, 8170 } },
	-- Curiosities
	[248685] = { { 20, 10940 }, { 4, 10939 }, { 6, 10978 }, { 2, 11084 } },
	[248689] = { { 20, 11083 }, { 4, 11082 }, { 6, 11138 }, { 2, 11139 } },
	[248694] = { { 20, 11137 }, { 4, 11135 }, { 6, 11177 }, { 2, 11178 } },
	[248699] = { { 20, 11176 }, { 4, 11175 }, { 6, 14343 }, { 2, 14344 } },
	-- Fabrics
	[248702] = { { 2, 4231 }, { 20, 2996 } },
	[248705] = { { 6, 2997 }, { 10, 4305 }, { 2, 4233 } },
	[248708] = { { 8, 4339 }, { 2, 4236 } },
	[248711] = { { 8, 14048 }, { 2, 8172 } },
}

local prices = { CRATES = CRATES, CRATES_LIST = CRATES_LIST, SHOPPING_LIST = SHOPPING_LIST }
ns.auctionator = prices

-- Settings and data that were "Waylaid Crate prices" before it grew into this (never released,
-- but some have it on).
function module:Migrate(db)
	local moved = {
		waylaidCrates = "auctionatorPrices", waylaidCratesList = "auctionatorCratesList",
		waylaidCratesUnitPrice = "auctionatorUnitPrice", waylaidCratesListed = "auctionatorCratesListed",
	}
	for old, new in pairs(moved) do
		if db[old] ~= nil then
			if db[new] == nil then
				db[new] = db[old]
			end
			db[old] = nil
		end
	end
end

local function API()
	return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
end

local function IsOn(option)
	return ns:IsModuleEnabled(module.key) and (not option or ns:GetOption(option)) and API() ~= nil
end

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID)
end

function prices.MoneyText(copper)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end
local MoneyText = prices.MoneyText

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- What one costs, and whether that's a vendor's price: a vendor's if one is known (what you
-- saw at a merchant, else Auctionator's), the auction house's otherwise. nil if neither.
function prices.Unit(itemID)
	local vendor = NraKitDB.vendorPrices and NraKitDB.vendorPrices[itemID]
	local api = API()
	if not api then
		return vendor, vendor ~= nil
	end
	if not vendor and api.GetVendorPriceByItemID then
		vendor = api.GetVendorPriceByItemID(CALLER, itemID)
	end
	if vendor and vendor > 0 then
		return vendor, true
	end
	return api.GetAuctionPriceByItemID(CALLER, itemID), false
end

-- Prices a list of { count, itemID }: { count, itemID, unit, total, vendor } each (unit and
-- total nil without a price).
local function PriceAll(bundles)
	local priced = {}
	for index, bundle in ipairs(bundles) do
		local unit, vendor = prices.Unit(bundle[2])
		priced[index] = { count = bundle[1], itemID = bundle[2], unit = unit, vendor = vendor,
			total = unit and unit * bundle[1] }
	end
	return priced
end

-- Remember what merchants sell for gold in unlimited supply, at the price of one.
local function LearnVendorPrices()
	NraKitDB.vendorPrices = NraKitDB.vendorPrices or {}
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		local price, stack, available, extended
		if type(C_MerchantFrame) == "table" and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(index)
			if info then
				price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
			end
		else
			local _
			_, _, price, stack, available, _, _, extended = GetMerchantItemInfo(index)
		end
		if itemID and price and price > 0 and available == -1 and not extended then
			NraKitDB.vendorPrices[itemID] = math.floor(price / math.max(stack or 1, 1) + 0.5)
		end
	end
end

-- Tooltip lines for priced reagents: "6 Iron Bar   1g 20s" (the cheapest in green, when
-- `cheapest` is given).
-- "have 9" after a reagent: green if this character's bags hold enough, yellow if your
-- characters do (in the bank, on others), grey if not.
function prices.HaveText(itemID, need)
	local have = prices.Have(itemID)
	local colour = HAVE_SHORT
	if (C_Item.GetItemCount(itemID) or 0) >= need then
		colour = HAVE_HERE
	elseif have >= need then
		colour = HAVE_ELSEWHERE
	end
	return string.format("  |c%shave %d|r", colour, have), have, colour == HAVE_HERE
end

local WHERE_MAX = 4

-- Where you have an item: "You 3 (Bags 2, Bank 1), Bankalt 12" (others in class colours, at
-- most WHERE_MAX, then "+2 more"). nil if you have none.
function prices.WhereText(itemID)
	local have, holders = prices.Have(itemID)
	if have == 0 then
		return nil
	end
	if not holders then
		-- Without Inventory Tracker: your bags and bank.
		local bags = C_Item.GetItemCount(itemID) or 0
		local parts = {}
		if bags > 0 then
			table.insert(parts, "Bags " .. bags)
		end
		if have > bags then
			table.insert(parts, "Bank " .. (have - bags))
		end
		return string.format("You %d (%s)", have, table.concat(parts, ", "))
	end
	local parts = {}
	for index, holder in ipairs(holders) do
		if index > WHERE_MAX then
			table.insert(parts, "+" .. (#holders - WHERE_MAX) .. " more")
			break
		end
		if holder.isMe then
			table.insert(parts, string.format("You %d (%s)", holder.total, holder.where))
		else
			local r, g, b = ns.inventory.ClassColor(holder.class)
			table.insert(parts, string.format("|cff%02x%02x%02x%s|r %d", r * 255, g * 255, b * 255, holder.label, holder.total))
		end
	end
	return table.concat(parts, ", ")
end

local function AddPriceLines(tooltip, priced, cheapest)
	local unitPrice = ns:GetOption("auctionatorUnitPrice")
	local showHave = ns:GetOption("auctionatorHave")
	for index, entry in ipairs(priced) do
		local left = entry.count .. " " .. (ItemName(entry.itemID) or ("item " .. entry.itemID))
		if entry.vendor then
			left = left .. VENDOR_TAG
		end
		local where
		if showHave then
			local text, have, inBags = prices.HaveText(entry.itemID, entry.count)
			left, entry.have = left .. text, have
			-- Where they are, when there's something to fetch.
			where = not inBags and prices.WhereText(entry.itemID)
		end
		if not entry.total then
			tooltip:AddDoubleLine(left, "no price", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		else
			local right = MoneyText(entry.total)
			if unitPrice then
				right = string.format("%s  |cff999999(%s each)|r", right, MoneyText(entry.unit))
			end
			if index == cheapest then
				tooltip:AddDoubleLine(left, right, 0.3, 1, 0.3, 1, 1, 1)
			else
				tooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
			end
		end
		if where then
			tooltip:AddLine("      " .. where, 0.6, 0.6, 0.6)
		end
	end
end

---------------------------------------------------------------------------
-- Auctionator lists
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local auctionHouseOpen = false

function prices.IsAuctionHouseOpen()
	return auctionHouseOpen
end

-- Search strings for { { itemID, amount }, ... }: exact, with the amount; vendor items left
-- out if that's the option. Returns nil (and asks the client for them) while a name isn't
-- loaded yet.
local function SearchTerms(wanted)
	local api = API()
	local terms, missing = {}, false
	local skipVendor = ns:GetOption("auctionatorSkipVendor")
	for _, each in ipairs(wanted) do
		local itemID, amount = each[1], each[2]
		local _, vendor = prices.Unit(itemID)
		if not (skipVendor and vendor) then
			local name = ItemName(itemID)
			if not name then
				missing = true
				if C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(itemID)
				end
			else
				table.insert(terms, api.ConvertToSearchString(CALLER, {
					searchString = name, isExact = true, quantity = amount,
				}))
			end
		end
	end
	if missing then
		return nil
	end
	return terms
end

-- Lists waiting for item names: name -> function that tries again.
local waiting = {}

-- Writes an Auctionator list now, or once the names are loaded. `ifChanged` skips writing
-- the same thing again (remembered under NraKitDB[ifChanged]).
local function WriteList(name, wanted, ifChanged)
	local terms = SearchTerms(wanted)
	if not terms then
		waiting[name] = function()
			WriteList(name, wanted, ifChanged)
		end
		return false
	end
	waiting[name] = nil
	if ifChanged then
		local signature = table.concat(terms, "\n")
		if signature == (NraKitDB[ifChanged] or "") then
			return true
		end
		NraKitDB[ifChanged] = signature
	end
	API().CreateShoppingList(CALLER, name, terms)
	return true
end

---------------------------------------------------------------------------
-- Waylaid Crates
---------------------------------------------------------------------------

-- Each bundle of a crate priced (see PriceAll), and the index of the cheapest (nil if none has
-- a price).
function prices.CratePrice(crateID)
	local bundles = CRATES[crateID]
	if not bundles or not API() then
		return nil
	end
	local priced, cheapest = PriceAll(bundles), nil
	for index, entry in ipairs(priced) do
		if entry.total and (not cheapest or entry.total < priced[cheapest].total) then
			cheapest = index
		end
	end
	return priced, cheapest
end

local function OnItemTooltip(tooltip, data)
	if not IsOn("auctionatorCrates") or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
		return
	end
	local crateID = data and data.id
	if not crateID or (issecretvalue and issecretvalue(crateID)) then
		return
	end
	local priced, cheapest = prices.CratePrice(crateID)
	if priced then
		tooltip:AddLine(" ")
		tooltip:AddLine("Cost at the Auction House", 1, 0.82, 0)
		AddPriceLines(tooltip, priced, cheapest)
	end
end

-- Every bundle of the crates in your bags: { { itemID, amount }, ... }, the amount being the
-- bundle size times how many of that crate you carry.
function prices.CrateWants()
	local amounts, wanted = {}, {}
	local crateIDs = {}
	for crateID in pairs(CRATES) do
		table.insert(crateIDs, crateID)
	end
	table.sort(crateIDs)
	for _, crateID in ipairs(crateIDs) do
		local carried = C_Item.GetItemCount(crateID) or 0
		if carried > 0 then
			for _, bundle in ipairs(CRATES[crateID]) do
				local itemID = bundle[2]
				if not amounts[itemID] then
					amounts[itemID] = { itemID, 0 }
					table.insert(wanted, amounts[itemID])
				end
				amounts[itemID][2] = amounts[itemID][2] + bundle[1] * carried
			end
		end
	end
	return wanted
end

-- Rewrites the list when the crates you carry change. Nothing is written for someone who
-- never had a crate; once there was one, carrying none empties the list.
function prices.UpdateCrateList()
	if not IsOn("auctionatorCrates") or not ns:GetOption("auctionatorCratesList") or auctionHouseOpen then
		return
	end
	local wanted = prices.CrateWants()
	if #wanted == 0 and not NraKitDB.auctionatorCratesListed then
		return
	end
	WriteList(CRATES_LIST, wanted, "auctionatorCratesListed")
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- A recipe's name and the reagents for one craft, { { count, itemID }, ... } (optional
-- reagents left out); nil if the game has none for it.
function prices.RecipeReagents(recipeID)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
		return nil
	end
	local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
		return nil
	end
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local first = slot.reagents and slot.reagents[1]
		if slot.required ~= false and first and first.itemID and (slot.quantityRequired or 0) > 0 then
			table.insert(reagents, { slot.quantityRequired, first.itemID })
		end
	end
	if #reagents == 0 then
		return nil
	end
	local name = schematic.name or (C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)) or ("Recipe " .. recipeID)
	return name, reagents
end

-- The recipe a tooltip shows, from its link ("enchant:3501", what a recipe link in chat is).
local function TooltipRecipe(tooltip)
	local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
	local args = info and info.getterName == "GetHyperlink" and info.getterArgs
	local link = args and args[1]
	return type(link) == "string" and tonumber(link:match("enchant:(%d+)")) or nil
end

local function OnAnyTooltip(tooltip)
	if not IsOn("auctionatorRecipes") or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
		return
	end
	local recipeID = TooltipRecipe(tooltip)
	if not recipeID then
		return
	end
	local _, reagents = prices.RecipeReagents(recipeID)
	if not reagents then
		return
	end
	local priced = PriceAll(reagents)
	tooltip:AddLine(" ")
	tooltip:AddLine("Cost of one craft", 1, 0.82, 0)
	AddPriceLines(tooltip, priced)
	local total, unpriced = 0, 0
	for _, entry in ipairs(priced) do
		if entry.total then
			total = total + entry.total
		else
			unpriced = unpriced + 1
		end
	end
	if unpriced == #priced then
		return
	end
	tooltip:AddDoubleLine("Total", MoneyText(total) .. (unpriced > 0 and "+" or ""), 1, 0.82, 0, 1, 1, 1)
	if not ns:GetOption("auctionatorHave") then
		return
	end
	-- What's missing, at its price: only when you have some of it.
	local toBuy, toBuyUnpriced, short = 0, false, false
	for _, entry in ipairs(priced) do
		local missing = math.max(0, entry.count - (entry.have or 0))
		if missing > 0 then
			short = true
			if entry.unit then
				toBuy = toBuy + missing * entry.unit
			else
				toBuyUnpriced = true
			end
		end
	end
	if not short then
		tooltip:AddDoubleLine("To buy", "nothing, you have it all", 1, 0.82, 0, 0.3, 1, 0.3)
	elseif toBuy ~= total or toBuyUnpriced ~= (unpriced > 0) then
		tooltip:AddDoubleLine("To buy", MoneyText(toBuy) .. (toBuyUnpriced and "+" or ""), 1, 0.82, 0, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- The NraKit Shopping List: { items = { { id, amount, crafts = { [recipe name] = n } }, ... } }
---------------------------------------------------------------------------

local shopping = {}
prices.shopping = shopping
local shoppingDirty = false

function shopping.GetData()
	NraKitDB.shoppingListData = NraKitDB.shoppingListData or { items = {} }
	return NraKitDB.shoppingListData
end

function shopping.Find(itemID)
	for index, entry in ipairs(shopping.GetData().items) do
		if entry.id == itemID then
			return entry, index
		end
	end
end

-- Auctionator's copy: written while the auction house is closed (at it, writing searches, so
-- Search at AH does it there), and when it closes if something changed meanwhile.
function shopping.Sync(search)
	if not IsOn() then
		return
	end
	if auctionHouseOpen and not search then
		shoppingDirty = true
		return
	end
	shoppingDirty = false
	local wanted = {}
	for _, entry in ipairs(shopping.GetData().items) do
		table.insert(wanted, { entry.id, entry.amount })
	end
	if search then
		NraKitDB.auctionatorShoppingListed = nil -- write it even if it's the same, to search
	end
	if #wanted == 0 and not NraKitDB.auctionatorShoppingListed then
		return
	end
	WriteList(SHOPPING_LIST, wanted, "auctionatorShoppingListed")
end

local function ShoppingChanged()
	if shopping.onChanged then
		shopping.onChanged()
	end
	shopping.Sync()
end

-- Adds one craft's reagents; returns the recipe's name (nil if it has none).
function shopping.AddRecipe(recipeID)
	local name, reagents = prices.RecipeReagents(recipeID)
	if not reagents then
		return nil
	end
	local items = shopping.GetData().items
	for _, reagent in ipairs(reagents) do
		local count, itemID = reagent[1], reagent[2]
		local entry = shopping.Find(itemID)
		if not entry then
			entry = { id = itemID, amount = 0, crafts = {} }
			table.insert(items, entry)
		end
		entry.amount = entry.amount + count
		entry.crafts[name] = (entry.crafts[name] or 0) + 1
	end
	ShoppingChanged()
	return name
end

function shopping.SetAmount(itemID, amount)
	local entry = shopping.Find(itemID)
	amount = math.floor(tonumber(amount) or 0)
	if entry and amount >= 1 and amount ~= entry.amount then
		entry.amount = amount
		ShoppingChanged()
	end
end

function shopping.Remove(itemID)
	local _, index = shopping.Find(itemID)
	if index then
		table.remove(shopping.GetData().items, index)
		ShoppingChanged()
	end
end

function shopping.Clear()
	wipe(shopping.GetData().items)
	ShoppingChanged()
end

-- How many you have: the total over your characters (Inventory Tracker's data, with who has
-- how many: { { label, class, total, where }, ... }), or your bags and bank without it.
function prices.Have(itemID)
	if ns.inventory and ns.inventory.Holders and ns:IsModuleEnabled("inventoryTracker") then
		local holders = ns.inventory.Holders(itemID)
		local total = 0
		for _, holder in ipairs(holders) do
			total = total + holder.total
		end
		return total, holders
	end
	return C_Item.GetItemCount(itemID, true) or 0
end

---------------------------------------------------------------------------
-- Recipe menus: right-click a recipe link in chat or a recipe in the profession window
---------------------------------------------------------------------------

function prices.CreateRecipeList(recipeID)
	local name, reagents = prices.RecipeReagents(recipeID)
	if not reagents then
		return
	end
	local wanted, fromVendor = {}, 0
	for _, reagent in ipairs(reagents) do
		table.insert(wanted, { reagent[2], reagent[1] })
		if select(2, prices.Unit(reagent[2])) then
			fromVendor = fromVendor + 1
		end
	end
	if fromVendor == #wanted and ns:GetOption("auctionatorSkipVendor") then
		ns:Print("Everything " .. name .. " needs is sold by vendors.")
		return
	end
	WriteList(name, wanted)
	ns:Print(string.format("Made an Auctionator shopping list, \"%s\", with one craft's reagents.", name))
end

function prices.AddRecipeToShopping(recipeID)
	local name = shopping.AddRecipe(recipeID)
	if name then
		ns:Print("Added " .. name .. " to your NraKit Shopping List (|cffffd100/nra shop|r).")
	end
end

-- The two entries, at the end of a menu.
function prices.FillRecipeMenu(root, recipeID)
	if not IsOn("auctionatorShopping") or not prices.RecipeReagents(recipeID) then
		return false
	end
	root:CreateButton("Create shopping list for this recipe", function()
		prices.CreateRecipeList(recipeID)
	end)
	root:CreateButton("Add to NraKit Shopping List", function()
		prices.AddRecipeToShopping(recipeID)
	end)
	return true
end

local function OpenRecipeMenu(owner, recipeID)
	local name = prices.RecipeReagents(recipeID)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(name)
		prices.FillRecipeMenu(root, recipeID)
	end)
end

-- Right-click a recipe link in chat (left-click still shows it, as always).
local function OnChatLinkClick(_, _, link, _, button)
	if button ~= "RightButton" or IsModifiedClick() or not IsOn("auctionatorShopping") then
		return
	end
	local recipeID = type(link) == "string" and tonumber(link:match("^enchant:(%d+)"))
	if recipeID and prices.RecipeReagents(recipeID) then
		OpenRecipeMenu(UIParent, recipeID)
	end
end

-- The profession window: the recipe list's right-click menu, and a button by the reagents.
local professionButton

local function CurrentRecipe()
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
	return info and info.recipeID
end

local function UpdateProfessionButton()
	if not professionButton then
		return
	end
	local recipeID = CurrentRecipe()
	local label = professionButton.label
	local show = label and IsOn("auctionatorShopping") and recipeID and prices.RecipeReagents(recipeID) ~= nil
	professionButton:SetShown(show and true or false)
	if show then
		professionButton:ClearAllPoints()
		professionButton:SetPoint("LEFT", label, "LEFT", math.ceil(label:GetStringWidth()) + 8, 0)
	end
end

local function HookProfessions()
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if professionButton or not form then
		return
	end
	-- Not a child of the reagents frame: that one sizes itself to its children.
	professionButton = ns.UI.CreateFlatButton(form, "Shopping list", 18)
	professionButton.label = form.Reagents and form.Reagents.Label
	professionButton:SetFrameLevel(form:GetFrameLevel() + 10)
	professionButton:Hide()
	professionButton:SetScript("OnClick", function(self)
		local recipeID = CurrentRecipe()
		if recipeID then
			OpenRecipeMenu(self, recipeID)
		end
	end)
	professionButton:SetScript("OnEnter", function(self)
		ns.UI.ShowTooltip(self, "Shopping list", "Make an Auctionator shopping list of this recipe's reagents, or add them to the NraKit Shopping List.")
	end)
	professionButton:SetScript("OnLeave", GameTooltip_Hide)
	if form.Init then
		hooksecurefunc(form, "Init", UpdateProfessionButton)
	end
	UpdateProfessionButton()
end

local function OnRecipeListMenu(owner, root)
	local data = owner and owner.GetElementData and owner:GetElementData()
	local recipeID = data and data.recipeInfo and data.recipeInfo.recipeID
	if recipeID and IsOn("auctionatorShopping") and prices.RecipeReagents(recipeID) then
		root:CreateDivider()
		prices.FillRecipeMenu(root, recipeID)
	end
end

---------------------------------------------------------------------------
-- /nra crates check: the game's own crate tooltips against the table above
---------------------------------------------------------------------------

-- Crate item IDs are around here; anything called "Waylaid Crate: ..." in this range that
-- the table doesn't have is reported.
local SCAN_FROM, SCAN_TO = 248500, 248800
local CHECK_TRIES = 6 -- one a second

-- "8 Iron Strut" for each "- 8 Iron Strut" line the tooltip lists.
function prices.ParseBundles(tooltipData)
	local bundles = {}
	for _, line in ipairs(tooltipData and tooltipData.lines or {}) do
		local text = (line.leftText or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		for count, name in (text .. "\n"):gmatch("%-%s*(%d+)%s+([^\n]-)%s*\n") do
			table.insert(bundles, count .. " " .. name)
		end
	end
	table.sort(bundles)
	return bundles
end

-- Calls done(name) once the item's data is loaded (never for an item that doesn't exist).
local function WithItem(itemID, done)
	local item = Item:CreateFromItemID(itemID)
	if item:IsItemEmpty() then
		return
	end
	item:ContinueOnItemLoad(function()
		done(item:GetItemName())
	end)
end

local function CrateTooltip(crateID)
	return C_TooltipInfo.GetHyperlink("item:" .. crateID)
end

local function CheckCrate(crateID, report)
	WithItem(crateID, function(crateName)
		local bundles = CRATES[crateID]
		local ours, left = {}, #bundles
		for _, bundle in ipairs(bundles) do
			WithItem(bundle[2], function(name)
				table.insert(ours, bundle[1] .. " " .. (name or ("item " .. bundle[2])))
				left = left - 1
				if left == 0 then
					table.sort(ours)
					-- The "Use:" text (an item spell) loads after the item; ask again a few times.
					local tries = 0
					local function Compare()
						tries = tries + 1
						local game = prices.ParseBundles(CrateTooltip(crateID))
						if #game == 0 and tries < CHECK_TRIES then
							C_Timer.After(1, Compare)
						else
							report(crateID, crateName, game, ours)
						end
					end
					Compare()
				end
			end)
		end
	end)
end

function prices.CheckCrates()
	local checked, wrong = 0, 0
	local function Report(crateID, crateName, game, ours)
		checked = checked + 1
		local gameText, ourText = table.concat(game, ", "), table.concat(ours, ", ")
		if gameText ~= ourText then
			wrong = wrong + 1
			ns:Print(string.format("|cffff6666%s|r (%d)\n  game: %s\n  NraKit: %s", crateName or "?", crateID,
				gameText ~= "" and gameText or "(no list found)", ourText))
		end
	end
	local total = 0
	for crateID in pairs(CRATES) do
		total = total + 1
		CheckCrate(crateID, Report)
	end
	-- Crates the table doesn't know.
	if C_Item.DoesItemExistByID then
		for itemID = SCAN_FROM, SCAN_TO do
			if not CRATES[itemID] and C_Item.DoesItemExistByID(itemID) then
				WithItem(itemID, function(name)
					if name and name:find("^Waylaid Crate:") then
						wrong = wrong + 1
						local game = prices.ParseBundles(CrateTooltip(itemID))
						ns:Print(string.format("|cffff6666%s|r (%d) isn't in NraKit\n  game: %s", name, itemID,
							table.concat(game, ", ")))
					end
				end)
			end
		end
	end
	ns:Print("checking " .. total .. " Waylaid Crates against the game...")
	C_Timer.After(CHECK_TRIES + 2, function()
		ns:Print(string.format("crate check done: %d of %d crates loaded, %d problem(s).", checked, total, wrong))
	end)
end

local function OnCratesCommand(rest)
	if rest:lower() == "check" then
		prices.CheckCrates()
	else
		ns:PrintCommandHelp("crates")
	end
end

local function OnShopCommand()
	ns.UI.ShowTab("shopping")
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "AUCTION_HOUSE_SHOW" then
		auctionHouseOpen = true
	elseif event == "AUCTION_HOUSE_CLOSED" then
		auctionHouseOpen = false
		prices.UpdateCrateList()
		if shoppingDirty then
			shopping.Sync()
		end
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		for _, retry in pairs(waiting) do
			retry()
		end
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		LearnVendorPrices()
	elseif event == "ADDON_LOADED" then
		if arg1 == "Blizzard_Professions" then
			HookProfessions()
		end
	else
		prices.UpdateCrateList()
	end
end)

local EVENTS = {
	"BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ITEM_DATA_LOAD_RESULT",
	"MERCHANT_SHOW", "MERCHANT_UPDATE",
}

local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

function module:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, OnAnyTooltip)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", OnChatLinkClick, module)
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_PROFESSIONS_RECIPE_LIST_FAVORITE", OnRecipeListMenu)
	end
	eventFrame:RegisterEvent("ADDON_LOADED")
	HookProfessions()
	ns:RegisterSlashCommand("crates", OnCratesCommand, {
		summary = "Waylaid Crates: check NraKit's crate list against the game",
		usage = { "/nra crates check - compare every crate's bundles with the game's tooltips and list differences" },
	})
	local shopHelp = {
		summary = "Open the NraKit Shopping List (needs Auctionator prices)",
		usage = { "/nra shop - open the NraKit Shopping List (also /nra shopping)" },
	}
	ns:RegisterSlashCommand("shop", OnShopCommand, shopHelp)
	ns:RegisterSlashCommand("shopping", OnShopCommand, shopHelp)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if IsEventValid(event) then
			if enabled then
				eventFrame:RegisterEvent(event)
			else
				eventFrame:UnregisterEvent(event)
			end
		end
	end
	UpdateProfessionButton()
	if enabled then
		prices.UpdateCrateList()
	end
end

function module:OnOptionChanged(key, value)
	if key == "auctionatorCratesList" and value then
		-- Turning it back on writes the list again, even if it was deleted in Auctionator.
		NraKitDB.auctionatorCratesListed = nil
		prices.UpdateCrateList()
	elseif key == "auctionatorCrates" and value then
		prices.UpdateCrateList()
	elseif key == "auctionatorShopping" then
		UpdateProfessionButton()
	end
end

ns:RegisterModule(module)
