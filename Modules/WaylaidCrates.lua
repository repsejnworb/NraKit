local _, ns = ...

-- Waylaid Crates: a crate takes any one bundle from its list (8 Iron Strut or 5 Mithril
-- Tube...), all at once. The crate's tooltip prices each bundle with Auctionator's last
-- scan and marks the cheapest, and an Auctionator shopping list ("Waylaid Crates") holds
-- every bundle of the crates in your bags, with the amounts, for looking them up at the AH.
--
-- Only Auctionator's public API (Auctionator.API.v1) is used. Creating a list while the
-- auction house is open starts a search, so the list is only rewritten while it's closed.

local module = {
	key = "waylaidCrates",
	section = "Professions",
	name = "Waylaid Crate prices",
	description = "Needs the Auctionator addon. A Waylaid Crate's tooltip shows what each bundle it takes costs at the auction house (from Auctionator's last scan), with the cheapest in green.",
	default = false,
	options = {
		{
			key = "waylaidCratesList",
			header = "General",
			name = "Auctionator shopping list",
			description = "Keep an Auctionator shopping list called \"Waylaid Crates\" with every bundle the crates in your bags take, in the amounts they need. It's rewritten when your crates change (not while the auction house is open).",
			default = true,
		},
		{
			key = "waylaidCratesUnitPrice",
			name = "Show the price of one",
			description = "In the crate's tooltip, also show what one of each reagent costs.",
			default = false,
		},
	},
}

local CALLER = "NraKit"
local LIST_NAME = "Waylaid Crates"

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

local crates = { CRATES = CRATES, LIST_NAME = LIST_NAME }
ns.waylaidCrates = crates

local function API()
	return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
end

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID)
end

local function MoneyText(copper)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Each bundle of a crate priced: { count, itemID, unit, total } (unit and total nil without a
-- price), and the index of the cheapest (nil if none has a price).
function crates.Price(crateID)
	local bundles = CRATES[crateID]
	local api = API()
	if not bundles or not api then
		return nil
	end
	local priced, cheapest = {}, nil
	for index, bundle in ipairs(bundles) do
		local count, itemID = bundle[1], bundle[2]
		local unit = api.GetAuctionPriceByItemID(CALLER, itemID)
		local entry = { count = count, itemID = itemID, unit = unit, total = unit and unit * count }
		priced[index] = entry
		if entry.total and (not cheapest or entry.total < priced[cheapest].total) then
			cheapest = index
		end
	end
	return priced, cheapest
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip, data)
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local crateID = data and data.id
	if not crateID or (issecretvalue and issecretvalue(crateID)) then
		return
	end
	local priced, cheapest = crates.Price(crateID)
	if not priced then
		return
	end
	local unitPrice = ns:GetOption("waylaidCratesUnitPrice")
	tooltip:AddLine(" ")
	tooltip:AddLine("Cost at the Auction House", 1, 0.82, 0)
	for index, entry in ipairs(priced) do
		local name = ItemName(entry.itemID) or ("item " .. entry.itemID)
		local left = entry.count .. " " .. name
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
	end
end

---------------------------------------------------------------------------
-- Shopping list
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local auctionHouseOpen = false
local waitingForNames = false

-- The search strings for every bundle of the crates in your bags: one per reagent, exact,
-- with the amount (the bundle size times how many of that crate you carry). Returns nil if
-- a reagent's name isn't loaded yet (it's requested; ITEM_DATA_LOAD_RESULT tries again).
function crates.ListTerms()
	local api = API()
	local amounts, order = {}, {}
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
					table.insert(order, itemID)
				end
				amounts[itemID] = (amounts[itemID] or 0) + bundle[1] * carried
			end
		end
	end
	local terms, missing = {}, false
	for _, itemID in ipairs(order) do
		local name = ItemName(itemID)
		if not name then
			missing = true
			if C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(itemID)
			end
		else
			table.insert(terms, api.ConvertToSearchString(CALLER, {
				searchString = name, isExact = true, quantity = amounts[itemID],
			}))
		end
	end
	if missing then
		return nil
	end
	return terms
end

-- Rewrites the list when the crates you carry change. Nothing is written for someone who
-- never had a crate; once there was one, carrying none empties the list.
function crates.UpdateList()
	waitingForNames = false
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("waylaidCratesList") then
		return
	end
	local api = API()
	if not api or not api.CreateShoppingList or auctionHouseOpen then
		return
	end
	local terms = crates.ListTerms()
	if not terms then
		waitingForNames = true
		return
	end
	local signature = table.concat(terms, "\n")
	if signature == (NraKitDB.waylaidCratesListed or "") then
		return
	end
	api.CreateShoppingList(CALLER, LIST_NAME, terms)
	NraKitDB.waylaidCratesListed = signature
end

eventFrame:SetScript("OnEvent", function(_, event)
	if event == "AUCTION_HOUSE_SHOW" then
		auctionHouseOpen = true
	elseif event == "AUCTION_HOUSE_CLOSED" then
		auctionHouseOpen = false
		crates.UpdateList()
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		if waitingForNames then
			crates.UpdateList()
		end
	else
		crates.UpdateList()
	end
end)

---------------------------------------------------------------------------
-- /nra crates check: the game's own crate tooltips against the table above
---------------------------------------------------------------------------

-- Crate item IDs are around here; anything called "Waylaid Crate: ..." in this range that
-- the table doesn't have is reported.
local SCAN_FROM, SCAN_TO = 248500, 248800

-- "8 Iron Strut" for each "- 8 Iron Strut" line the tooltip lists.
function crates.ParseBundles(tooltipData)
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
					local game = crates.ParseBundles(CrateTooltip(crateID))
					report(crateID, crateName, game, ours)
				end
			end)
		end
	end)
end

function crates.Check()
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
						local game = crates.ParseBundles(CrateTooltip(itemID))
						ns:Print(string.format("|cffff6666%s|r (%d) isn't in NraKit\n  game: %s", name, itemID,
							table.concat(game, ", ")))
					end
				end)
			end
		end
	end
	ns:Print("checking " .. total .. " Waylaid Crates against the game...")
	C_Timer.After(5, function()
		ns:Print(string.format("crate check done: %d of %d crates loaded, %d problem(s).", checked, total, wrong))
	end)
end

local function OnSlashCommand(rest)
	if rest:lower() == "check" then
		crates.Check()
	else
		ns:PrintCommandHelp("crates")
	end
end

local EVENTS = { "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ITEM_DATA_LOAD_RESULT" }

local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

function module:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	ns:RegisterSlashCommand("crates", OnSlashCommand, {
		summary = "Waylaid Crate prices: check NraKit's crate list against the game",
		usage = { "/nra crates check - compare every crate's bundles with the game's tooltips and list differences" },
	})
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
	if enabled then
		crates.UpdateList()
	end
end

function module:OnOptionChanged(key, value)
	if key == "waylaidCratesList" and value then
		-- Turning it back on writes the list again, even if it was deleted in Auctionator.
		NraKitDB.waylaidCratesListed = nil
		crates.UpdateList()
	end
end

ns:RegisterModule(module)
