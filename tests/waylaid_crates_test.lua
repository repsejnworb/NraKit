-- Waylaid Crate prices: the crate tooltip prices each bundle from Auctionator, and an
-- Auctionator shopping list holds the bundles of the crates you carry.

local EXPERT_PARTS = 248710
local IRON_STRUT, MITHRIL_TUBE, UNSTABLE_TRIGGER, MITHRIL_CASING = 4387, 10559, 10560, 10561
local JOURNEYMAN_ORE = 248687
local SILVER_ORE, IRON_ORE = 2775, 2772

-- Auctionator's public API: prices by item ID, and the lists it was asked to make.
local prices = {}
local lists = {}
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(caller, itemID)
		assert(caller == "NraKit", "caller")
		return prices[itemID]
	end,
	ConvertToSearchString = function(_, term)
		return string.format("\"%s\";%s;%d", term.searchString, tostring(term.isExact), term.quantity)
	end,
	CreateShoppingList = function(_, name, terms)
		table.insert(lists, { name = name, terms = terms })
	end,
} } }

return {
	enable = { "waylaidCrates" },
	run = function(t, ns, wow)
		local crates = ns.waylaidCrates
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

		t.test("every crate's bundles are a count and a reagent", function()
			local n = 0
			for crateID, bundles in pairs(crates.CRATES) do
				n = n + 1
				t.ok(#bundles >= 2, "a choice in " .. crateID)
				for _, bundle in ipairs(bundles) do
					t.ok(bundle[1] > 0 and bundle[2] > 0, "count and item in " .. crateID)
				end
			end
			t.equal(n, 30, "all the labelled crates")
		end)

		t.test("the crate's tooltip prices each bundle and marks the cheapest", function()
			prices[IRON_STRUT] = 1000        -- 8 = 80s
			prices[MITHRIL_TUBE] = 1500      -- 5 = 75s
			prices[UNSTABLE_TRIGGER] = 900   -- 12 = 1g 8s
			prices[MITHRIL_CASING] = nil
			local lines = Tooltip(EXPERT_PARTS)
			t.equal(lines[2], "Cost at the Auction House", "heading")
			t.equal(lines[3], "8 Iron Strut: 0g 80s 0c", "bundle total")
			t.equal(lines[4], "5 Mithril Tube: 0g 75s 0c (cheapest)", "the cheapest in green")
			t.equal(lines[5], "12 Unstable Trigger: 1g 8s 0c", "dearer")
			t.equal(lines[6], "5 Mithril Casing: no price", "unscanned")
		end)

		t.test("the price of one, as an option", function()
			ns:SetSetting("waylaidCratesUnitPrice", true)
			local lines = Tooltip(EXPERT_PARTS)
			t.ok(lines[3]:find("0g 10s 0c each", 1, true), "each: " .. lines[3])
			ns:SetSetting("waylaidCratesUnitPrice", false)
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
			ns:SetSetting("waylaidCratesList", false)
			wow.fire("BAG_UPDATE_DELAYED")
			t.equal(#lists, 3, "option off: left alone")
			ns:SetSetting("waylaidCratesList", true)
			t.equal(#lists, 4, "on again: written")
			ns:SetSetting("waylaidCratesList", false)
			ns:SetSetting("waylaidCratesList", true)
			t.equal(#lists, 5, "rewritten even if unchanged (it may have been deleted)")
		end)

		-- The game's tooltip, as /run printed it for Expert Parts.
		local EXPERT_PARTS_USE = "Use: Fill the crate with any bundle from the following list:\n"
			.. "- 8 Iron Strut\n- 5 Mithril Tube\n- 12 Unstable Trigger\n- 5 Mithril Casing"

		t.test("reads the bundles off the game's crate tooltip", function()
			local bundles = ns.waylaidCrates.ParseBundles({ lines = {
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
	end,
}
