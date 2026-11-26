-- Auctionator prices: Waylaid Crates (the crate tooltip prices each bundle; an Auctionator list
-- holds the bundles of the crates you carry), recipes (one craft's cost; shopping lists),
-- vendor prices, and the NraKit Shopping List.

local EXPERT_PARTS = 248710
local IRON_STRUT, MITHRIL_TUBE, UNSTABLE_TRIGGER, MITHRIL_CASING = 4387, 10559, 10560, 10561
local JOURNEYMAN_ORE = 248687
local SILVER_ORE, IRON_ORE = 2775, 2772

-- Auctionator's public API: prices by item ID, and the lists it was asked to make.
local ahPrices = {}
local lists = {}
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(caller, itemID)
		assert(caller == "NraKit", "caller")
		return ahPrices[itemID]
	end,
	ConvertToSearchString = function(_, term)
		return string.format("\"%s\";%s;%d", term.searchString, tostring(term.isExact), term.quantity)
	end,
	CreateShoppingList = function(_, name, terms)
		table.insert(lists, { name = name, terms = terms })
	end,
} } }

return {
	-- Turned on as "Waylaid Crate prices", which it was before it grew (moves over).
	db = { waylaidCrates = true },
	run = function(t, ns, wow)
		local prices = ns.auctionator
		local items = wow.data.items
		for id, name in pairs({
			[EXPERT_PARTS] = "Waylaid Crate: Expert Parts", [JOURNEYMAN_ORE] = "Waylaid Crate: Journeyman Ore",
			[IRON_STRUT] = "Iron Strut", [MITHRIL_TUBE] = "Mithril Tube", [UNSTABLE_TRIGGER] = "Unstable Trigger",
			[MITHRIL_CASING] = "Mithril Casing", [SILVER_ORE] = "Silver Ore", [IRON_ORE] = "Iron Ore",
		}) do
			items[id] = { name = name, bags = 0, bank = 0 }
		end
		GetMoneyString = false -- the plain formatting here

		local function Tooltip(itemID)
			local lines = {}
			rawset(GameTooltip, "AddLine", function(_, text)
				table.insert(lines, text)
			end)
			rawset(GameTooltip, "AddDoubleLine", function(_, left, right, r, g)
				table.insert(lines, left .. ": " .. right .. ((r == 0.3 and g == 1) and " (cheapest)" or ""))
			end)
			for _, call in ipairs(wow.tooltipCalls) do
				if call.type == Enum.TooltipDataType.Item then
					call.callback(GameTooltip, { id = itemID })
				end
			end
			rawset(GameTooltip, "AddLine", nil)
			rawset(GameTooltip, "AddDoubleLine", nil)
			return lines
		end

		t.test("was \"Waylaid Crate prices\": turned on, it's on as Auctionator prices", function()
			t.ok(ns:IsModuleEnabled("auctionatorPrices"), "on")
			t.equal(NraKitDB.waylaidCrates, nil, "old key gone")
		end)

		t.test("every crate's bundles are a count and a reagent", function()
			local n = 0
			for crateID, bundles in pairs(prices.CRATES) do
				n = n + 1
				t.ok(#bundles >= 2, "a choice in " .. crateID)
				for _, bundle in ipairs(bundles) do
					t.ok(bundle[1] > 0 and bundle[2] > 0, "count and item in " .. crateID)
				end
			end
			t.equal(n, 30, "all the labelled crates")
		end)

		t.test("the crate's tooltip prices each bundle and marks the cheapest", function()
			ahPrices[IRON_STRUT] = 1000        -- 8 = 80s
			ahPrices[MITHRIL_TUBE] = 1500      -- 5 = 75s
			ahPrices[UNSTABLE_TRIGGER] = 900   -- 12 = 1g 8s
			ahPrices[MITHRIL_CASING] = nil
			local lines = Tooltip(EXPERT_PARTS)
			t.equal(lines[2], "Cost at the Auction House", "heading")
			t.equal(lines[3], "8 Iron Strut  |cff999999have 0|r: 0g 80s 0c", "bundle total, and how many you have")
			t.equal(lines[4], "5 Mithril Tube  |cff999999have 0|r: 0g 75s 0c (cheapest)", "the cheapest in green")
			t.equal(lines[5], "12 Unstable Trigger  |cff999999have 0|r: 1g 8s 0c", "dearer")
			t.equal(lines[6], "5 Mithril Casing  |cff999999have 0|r: no price", "unscanned")
		end)

		t.test("the price of one, as an option", function()
			ns:SetSetting("auctionatorUnitPrice", true)
			local lines = Tooltip(EXPERT_PARTS)
			t.ok(lines[3]:find("0g 10s 0c each", 1, true), "each: " .. lines[3])
			ns:SetSetting("auctionatorUnitPrice", false)
		end)

		t.test("other items and no Auctionator: nothing added", function()
			t.equal(#Tooltip(IRON_STRUT), 0, "a reagent")
			local api = Auctionator
			Auctionator = nil
			t.equal(#Tooltip(EXPERT_PARTS), 0, "without Auctionator")
			Auctionator = api
		end)

		t.test("no crates, no list", function()
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 0, "nothing written")
		end)

		t.test("the shopping list holds every bundle of the crates you carry", function()
			items[EXPERT_PARTS].bags = 1
			items[JOURNEYMAN_ORE].bags = 2
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 1, "written")
			local list = lists[1]
			t.equal(list.name, "Waylaid Crates", "named")
			local text = table.concat(list.terms, " | ")
			t.equal(#list.terms, 6, "all bundles: " .. text)
			t.ok(text:find("\"Silver Ore\";true;20", 1, true), "exact, times the crates you carry: " .. text)
			t.ok(text:find("\"Iron Ore\";true;40", 1, true), text)
			t.ok(text:find("\"Iron Strut\";true;8", 1, true), text)
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 1, "unchanged crates: not rewritten")
		end)

		t.test("not while the auction house is open (it would search)", function()
			wow.fire("AUCTION_HOUSE_SHOW")
			items[JOURNEYMAN_ORE].bags = 0
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 1, "waits")
			wow.fire("AUCTION_HOUSE_CLOSED")
			t.equal(#lists, 2, "written on closing")
			t.equal(#lists[2].terms, 4, "only Expert Parts now")
		end)

		t.test("carrying none empties it; turning the option on writes it again", function()
			items[EXPERT_PARTS].bags = 0
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 3, "emptied")
			t.equal(#lists[3].terms, 0, "empty")
			items[EXPERT_PARTS].bags = 1
			ns:SetSetting("auctionatorCratesList", false)
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 3, "option off: left alone")
			ns:SetSetting("auctionatorCratesList", true)
			t.equal(#lists, 4, "on again: written")
			ns:SetSetting("auctionatorCratesList", false)
			ns:SetSetting("auctionatorCratesList", true)
			t.equal(#lists, 5, "rewritten even if unchanged (it may have been deleted)")
		end)

		-- The game's tooltip, as /run printed it for Expert Parts.
		local EXPERT_PARTS_USE = "Use: Fill the crate with any bundle from the following list:\n"
			.. "- 8 Iron Strut\n- 5 Mithril Tube\n- 12 Unstable Trigger\n- 5 Mithril Casing"

		t.test("reads the bundles off the game's crate tooltip", function()
			local bundles = prices.ParseBundles({ lines = {
				{ leftText = "Waylaid Crate: Expert Parts" },
				{ leftText = EXPERT_PARTS_USE },
				{ leftText = "Requires Level 20" },
			} })
			t.equal(table.concat(bundles, ", "), "12 Unstable Trigger, 5 Mithril Casing, 5 Mithril Tube, 8 Iron Strut", "all four")
		end)

		t.test("/nra crates check lists crates that differ from the game, and ones it doesn't know", function()
			-- Items load at once; every crate's tooltip lists Expert Parts' bundles, and
			-- 248800 is a crate NraKit doesn't have.
			items[248800] = { name = "Waylaid Crate: Grand Parts", bags = 0, bank = 0 }
			Item = { CreateFromItemID = function(_, id)
				return {
					IsItemEmpty = function() return false end,
					ContinueOnItemLoad = function(_, done) done() end,
					GetItemName = function() return items[id] and items[id].name end,
				}
			end }
			C_Item.DoesItemExistByID = function(id) return items[id] ~= nil end
			C_TooltipInfo.GetHyperlink = function()
				return { lines = { { leftText = EXPERT_PARTS_USE } } }
			end
			local after
			C_Timer.After = function(_, fn) after = fn end
			wow.printed = {}
			SlashCmdList.NRAKIT("crates check")
			after()
			local text = table.concat(wow.printed, "\n")
			t.ok(not text:find("Expert Parts|r (248710)", 1, true), "Expert Parts matches")
			t.ok(text:find("Waylaid Crate: Journeyman Ore|r (248687)", 1, true), "Journeyman Ore differs: " .. text)
			t.ok(text:find("NraKit: 10 Silver Ore, 20 Iron Ore", 1, true), "with NraKit's list")
			t.ok(text:find("Grand Parts|r (248800) isn't in NraKit", 1, true), "unknown crate")
			t.ok(text:find("30 of 30 crates loaded", 1, true), "summary: " .. text)
			t.noErrors()
		end)

		t.test("the check waits for crate text the game hasn't loaded yet", function()
			-- In game most crates' "Use:" text was missing on the first read (regression).
			local reads = 0
			C_TooltipInfo.GetHyperlink = function()
				reads = reads + 1
				if reads <= 30 then
					return { lines = { { leftText = "Waylaid Crate: Expert Parts" } } }
				end
				return { lines = { { leftText = EXPERT_PARTS_USE } } }
			end
			local retries, summary = {}, nil
			C_Timer.After = function(seconds, fn)
				if seconds == 1 then
					table.insert(retries, fn)
				else
					summary = fn
				end
			end
			wow.printed = {}
			SlashCmdList.NRAKIT("crates check")
			for _, fn in ipairs(retries) do
				fn()
			end
			summary()
			local text = table.concat(wow.printed, "\n")
			t.ok(not text:find("no list found", 1, true), "read again: " .. text)
			t.ok(not text:find("Expert Parts|r (248710)", 1, true), "Expert Parts matches")
			t.ok(text:find("30 of 30 crates loaded", 1, true), "summary: " .. text)
		end)

		t.test("waits for reagent names the client hasn't loaded", function()
			items[MITHRIL_TUBE].name = nil
			items[JOURNEYMAN_ORE].bags = 1
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 5, "not with a name missing")
			items[MITHRIL_TUBE].name = "Mithril Tube"
			wow.fire("ITEM_DATA_LOAD_RESULT", MITHRIL_TUBE, true)
			t.equal(#lists, 6, "written once it's loaded")
			t.noErrors()
		end)

		-- Recipes. Green Iron Bracers (3501): 6 Iron Bar and a Green Dye (vendor), plus an
		-- optional reagent that isn't counted.
		local IRON_BAR, GREEN_DYE, RECIPE = 3575, 2605, 3501
		items[IRON_BAR] = { name = "Iron Bar", bags = 2, bank = 1 }
		items[GREEN_DYE] = { name = "Green Dye", bags = 0, bank = 0 }
		C_TradeSkillUI.GetRecipeSchematic = function(recipeID)
			assert(recipeID == RECIPE, "unknown recipe")
			return { name = "Green Iron Bracers", reagentSlotSchematics = {
				{ required = true, quantityRequired = 6, reagents = { { itemID = IRON_BAR } } },
				{ required = true, quantityRequired = 1, reagents = { { itemID = GREEN_DYE } } },
				{ required = false, quantityRequired = 1, reagents = { { itemID = 999 } } },
			} }
		end
		ahPrices[IRON_BAR] = 2000
		ahPrices[GREEN_DYE] = 900 -- dearer at the AH than at the vendor

		-- The menu a right-click opens.
		local menu
		MenuUtil.CreateContextMenu = function(_, build)
			menu = wow.newMenu()
			build(nil, menu)
		end
		local function Click(text)
			local entry = wow.menuEntry(menu.entries, text)
			assert(entry, "no menu entry " .. text)
			entry.onClick()
		end
		local function Named(name)
			for index = #lists, 1, -1 do
				if lists[index].name == name then
					return lists[index], index
				end
			end
		end

		t.test("merchants' prices are remembered (sold in unlimited supply, for gold)", function()
			GetMerchantNumItems = function() return 2 end
			GetMerchantItemID = function(index) return index == 1 and GREEN_DYE or IRON_BAR end
			C_MerchantFrame = { GetItemInfo = function(index)
				if index == 1 then
					return { price = 250, stackCount = 5, numAvailable = -1, hasExtendedCost = false }
				end
				return { price = 1000, stackCount = 1, numAvailable = 3, hasExtendedCost = false } -- limited
			end }
			wow.fire("MERCHANT_SHOW")
			local unit, vendor = prices.Unit(GREEN_DYE)
			t.equal(unit, 50, "the price of one")
			t.ok(vendor, "a vendor's")
			unit, vendor = prices.Unit(IRON_BAR)
			t.equal(unit, 2000, "a limited one isn't a vendor price: the AH's")
			t.ok(not vendor, "not a vendor's")
		end)

		t.test("Auctionator's vendor prices fill the gaps", function()
			Auctionator.API.v1.GetVendorPriceByItemID = function(_, itemID)
				return itemID == MITHRIL_CASING and 300 or nil
			end
			local unit, vendor = prices.Unit(MITHRIL_CASING)
			t.equal(unit, 300, "Auctionator's")
			t.ok(vendor, "a vendor's")
			local lines = Tooltip(EXPERT_PARTS)
			t.ok(lines[6]:find("Mithril Casing |cff999999vendor|r  |cff999999have 0|r: 0g 15s 0c", 1, true), "tagged on the crate: " .. lines[6])
			Auctionator.API.v1.GetVendorPriceByItemID = nil
		end)

		local function RecipeTooltip(link)
			rawset(GameTooltip, "GetPrimaryTooltipInfo", function()
				return { getterName = "GetHyperlink", getterArgs = { link } }
			end)
			local lines = {}
			rawset(GameTooltip, "AddLine", function(_, text)
				table.insert(lines, text)
			end)
			rawset(GameTooltip, "AddDoubleLine", function(_, left, right)
				table.insert(lines, left .. ": " .. right)
			end)
			for _, call in ipairs(wow.tooltipCalls) do
				if call.type == TooltipDataProcessor.AllTypes then
					call.callback(GameTooltip, {})
				end
			end
			rawset(GameTooltip, "AddLine", nil)
			rawset(GameTooltip, "AddDoubleLine", nil)
			rawset(GameTooltip, "GetPrimaryTooltipInfo", nil)
			return lines
		end

		t.test("a recipe's tooltip shows what one craft costs", function()
			local lines = RecipeTooltip("enchant:" .. RECIPE)
			t.equal(lines[2], "Cost of one craft", "heading")
			t.equal(lines[3], "6 Iron Bar  |cff999999have 3|r: 1g 20s 0c", "6 Iron Bar, 3 of them yours (not enough: grey)")
			t.equal(lines[4], "      You 3 (Bags 2, Bank 1)", "where they are (not enough in your bags)")
			t.equal(lines[5], "1 Green Dye |cff999999vendor|r  |cff999999have 0|r: 0g 0s 50c", "the vendor's price, tagged; none, so no where")
			t.equal(lines[6], "Total: 1g 20s 50c", "total")
			t.equal(lines[7], "To buy: 0g 60s 50c", "what's missing: 3 bars and the dye")
			t.equal(#lines, 7, "the optional reagent left out")
			ahPrices[IRON_BAR] = nil
			lines = RecipeTooltip("enchant:" .. RECIPE)
			t.equal(lines[3], "6 Iron Bar  |cff999999have 3|r: no price", "unscanned")
			t.equal(lines[6], "Total: 0g 0s 50c+", "a total that's missing something says so")
			ahPrices[IRON_BAR] = 2000
			t.equal(#RecipeTooltip("item:" .. IRON_BAR), 0, "not a recipe: nothing")
			ns:SetSetting("auctionatorRecipes", false)
			t.equal(#RecipeTooltip("enchant:" .. RECIPE), 0, "option off")
			ns:SetSetting("auctionatorRecipes", true)
		end)

		t.test("have: green in your bags, yellow elsewhere; nothing to buy once you have it all", function()
			items[IRON_BAR].bags, items[IRON_BAR].bank = 2, 4
			local lines = RecipeTooltip("enchant:" .. RECIPE)
			t.ok(lines[3]:find("|cffffd100have 6|r", 1, true), "enough, some in the bank: yellow: " .. lines[3])
			items[IRON_BAR].bags = 6
			items[GREEN_DYE].bags = 1
			lines = RecipeTooltip("enchant:" .. RECIPE)
			t.ok(lines[3]:find("|cff4cff4chave 10|r", 1, true), "enough in your bags: green: " .. lines[3])
			t.equal(lines[4], "1 Green Dye |cff999999vendor|r  |cff4cff4chave 1|r: 0g 0s 50c", "green: no where line")
			t.equal(lines[6], "To buy: nothing, you have it all", "nothing to buy")
			ns:SetSetting("auctionatorHave", false)
			lines = RecipeTooltip("enchant:" .. RECIPE)
			t.equal(lines[3], "6 Iron Bar: 1g 20s 0c", "option off: no counts")
			t.equal(#lines, 5, "and no To buy")
			ns:SetSetting("auctionatorHave", true)
			items[IRON_BAR].bags, items[IRON_BAR].bank, items[GREEN_DYE].bags = 2, 1, 0
		end)

		t.test("where: with Inventory tracker, you first then your other characters, a few at most", function()
			NraKitDB.inventoryTracker = true
			local holders = function()
				return {
					{ label = "Nra Kit", isMe = true, total = 3, where = "Bags 2, Bank 1" },
					{ label = "Bankalt", class = "MAGE", total = 12 },
					{ label = "Twink", class = "MAGE", total = 2 },
					{ label = "Alt3", class = "MAGE", total = 1 },
					{ label = "Alt4", class = "MAGE", total = 1 },
					{ label = "Alt5", class = "MAGE", total = 1 },
				}
			end
			local saved = ns.inventory.Holders
			ns.inventory.Holders = holders
			local lines = RecipeTooltip("enchant:" .. RECIPE)
			t.ok(lines[3]:find("|cffffd100have 20|r", 1, true), "all yours counted, enough elsewhere: yellow: " .. lines[3])
			t.equal(lines[4], "      You 3 (Bags 2, Bank 1), |cffffffffBankalt|r 12, |cffffffffTwink|r 2, |cffffffffAlt3|r 1, +2 more", "where")
			ns.inventory.Holders = saved
			NraKitDB.inventoryTracker = false
		end)

		local function RightClickLink(link, button)
			menu = nil
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", nil, link, "[" .. link .. "]", button or "RightButton")
		end

		t.test("right-click a recipe link in chat: its shopping list menu", function()
			RightClickLink("enchant:" .. RECIPE)
			t.ok(menu, "a menu")
			t.equal(menu.entries[1].text, "Green Iron Bracers", "titled")
			t.ok(wow.menuEntry(menu.entries, "Create shopping list for this recipe"), "make a list")
			t.ok(wow.menuEntry(menu.entries, "Add to NraKit Shopping List"), "add to the big one")
			RightClickLink("enchant:" .. RECIPE, "LeftButton")
			t.equal(menu, nil, "a left-click just shows it")
			RightClickLink("item:" .. IRON_BAR)
			t.equal(menu, nil, "not a recipe")
		end)

		t.test("Create shopping list for this recipe: an Auctionator list named after it", function()
			RightClickLink("enchant:" .. RECIPE)
			Click("Create shopping list for this recipe")
			local list = Named("Green Iron Bracers")
			t.ok(list, "made")
			t.equal(table.concat(list.terms, " | "), "\"Iron Bar\";true;6", "one craft's, vendor items left out")
			t.ok(wow.printed[#wow.printed]:find("Green Iron Bracers", 1, true), "says so")
			ns:SetSetting("auctionatorSkipVendor", false)
			Click("Create shopping list for this recipe")
			t.equal(#Named("Green Iron Bracers").terms, 2, "vendor items too, with the option off")
			ns:SetSetting("auctionatorSkipVendor", true)
		end)

		local shopping = prices.shopping

		t.test("Add to NraKit Shopping List: one craft's reagents, adding up", function()
			RightClickLink("enchant:" .. RECIPE)
			Click("Add to NraKit Shopping List")
			Click("Add to NraKit Shopping List")
			local bars = shopping.Find(IRON_BAR)
			t.equal(bars.amount, 12, "two crafts' Iron Bars")
			t.equal(shopping.Find(GREEN_DYE).amount, 2, "and dye")
			t.equal(shopping.ForText(bars), "for Green Iron Bracers x2", "what it's for")
			t.equal(shopping.Find(999), nil, "not the optional reagent")
			local list = Named("NraKit Shopping List")
			t.ok(list, "Auctionator has a copy")
			t.equal(table.concat(list.terms, " | "), "\"Iron Bar\";true;12", "without the vendor items")
		end)

		t.test("amounts, removing and clearing; at the auction house the copy waits", function()
			shopping.SetAmount(IRON_BAR, 8)
			t.equal(Named("NraKit Shopping List").terms[1], "\"Iron Bar\";true;8", "copy follows")
			shopping.SetAmount(IRON_BAR, 0)
			t.equal(shopping.Find(IRON_BAR).amount, 8, "never below one")
			wow.fire("AUCTION_HOUSE_SHOW")
			local _, before = Named("NraKit Shopping List")
			shopping.SetAmount(IRON_BAR, 9)
			t.equal(select(2, Named("NraKit Shopping List")), before, "not rewritten at the AH (it would search)")
			shopping.Sync(true) -- Search at AH
			local list, after = Named("NraKit Shopping List")
			t.ok(after > before, "Search at AH writes it")
			t.equal(list.terms[1], "\"Iron Bar\";true;9", "as it is now")
			shopping.SetAmount(IRON_BAR, 10)
			wow.fire("AUCTION_HOUSE_CLOSED")
			t.equal(Named("NraKit Shopping List").terms[1], "\"Iron Bar\";true;10", "written on leaving")
			shopping.Remove(GREEN_DYE)
			t.equal(shopping.Find(GREEN_DYE), nil, "removed")
			shopping.Clear()
			t.equal(#shopping.GetData().items, 0, "cleared")
			t.equal(#Named("NraKit Shopping List").terms, 0, "and the copy emptied")
		end)

		t.test("the recipe list's right-click menu in the profession window", function()
			local root = wow.newMenu()
			local row = { GetElementData = function()
				return { recipeInfo = { recipeID = RECIPE } }
			end }
			for _, callback in ipairs(wow.menus.MENU_PROFESSIONS_RECIPE_LIST_FAVORITE or {}) do
				callback(row, root)
			end
			t.ok(wow.menuEntry(root.entries, "Add to NraKit Shopping List"), "added")
			ns:SetSetting("auctionatorShopping", false)
			root = wow.newMenu()
			for _, callback in ipairs(wow.menus.MENU_PROFESSIONS_RECIPE_LIST_FAVORITE or {}) do
				callback(row, root)
			end
			t.equal(#root.entries, 0, "option off")
			ns:SetSetting("auctionatorShopping", true)
		end)

		t.test("how many you have: bags and bank without Inventory tracker", function()
			t.equal(prices.Have(IRON_BAR), 3, "2 + 1")
		end)

		t.test("the Shopping list tab shows the list with its total", function()
			RightClickLink("enchant:" .. RECIPE)
			Click("Add to NraKit Shopping List")
			SlashCmdList.NRAKIT("shop")
			t.ok(NraKitShoppingListFrame and NraKitShoppingListFrame:IsShown(), "open")
			local found
			for _, object in ipairs(wow.frames) do
				if type(object.text) == "string" and object.text:find("Total", 1, true) and object.text:find("items", 1, true) then
					found = object.text
				end
			end
			t.ok(found and found:find("2 items", 1, true), "footer: " .. tostring(found))
			t.ok(found:find("1g 20s 50c", 1, true), "total: " .. tostring(found))
			t.noErrors()
		end)
	end,
}
