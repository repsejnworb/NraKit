-- Inventory Tracker remembers which recipes each character knows, and recipes show which of
-- your characters know them ("Known by: ..."): recipe items by name (the game only says they
-- teach "Learning"), recipe links by their ID.

local BRACERS = 3501 -- the recipe Green Iron Bracers
local PLANS = 7000 -- the item "Plans: Green Iron Bracers"
local OTHER_PLANS = 7001 -- "Plans: Golden Scale Coif" (nobody knows it)

C_Spell.GetSpellName = function(id)
	return ({ [BRACERS] = "Green Iron Bracers", [3504] = "Golden Scale Coif" })[id]
end
-- You (Nra Kit) know the bracers.
IsPlayerSpell = function(id)
	return id == BRACERS
end
C_Item.GetItemInfoInstant = function(itemID)
	if itemID == PLANS or itemID == OTHER_PLANS then
		return itemID, "Recipe", "Blacksmithing", "", 134939, Enum.ItemClass.Recipe
	end
	return itemID, "Trade Goods", "Cloth", "", 132903, 7
end

return {
	enable = { "inventoryTracker" },
	db = {
		-- The recipes, as Lookup found them (this game version).
		recipeLookupData = { build = "nil.nil", filter = 2, ids = { BRACERS, 3504 } },

	},
	run = function(t, ns, wow)
		-- A bank alt of yours, with no recipes.
		NraKitDB.inventory[ns.inventory.GetRealm()]["Banker Nra"] = { class = "MAGE", recipes = {} }
		local me = ns.inventory.GetPlayer()
		wow.data.items[PLANS] = { name = "Plans: Green Iron Bracers", bags = 1, bank = 0 }
		wow.data.items[OTHER_PLANS] = { name = "Plans: Golden Scale Coif", bags = 0, bank = 0 }

		local function TooltipText(type, data)
			local lines = {}
			rawset(GameTooltip, "AddLine", function(_, text)
				table.insert(lines, text)
			end)
			rawset(GameTooltip, "AddDoubleLine", function() end)
			for _, call in ipairs(wow.tooltipCalls) do
				if call.type == type then
					call.callback(GameTooltip, data)
				end
			end
			return (table.concat(lines, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end

		t.test("your known recipes are remembered", function()
			wow.fire("SPELLS_CHANGED")
			local me = NraKitDB.inventory[ns.inventory.GetRealm()][ns.inventory.GetPlayer()]
			t.ok(me.recipes and me.recipes[BRACERS], "the bracers")
			t.equal(me.recipes[3504], nil, "not the coif")
		end)

		t.test("a recipe item says who knows it (matched by name)", function()
			local text = TooltipText(Enum.TooltipDataType.Item, { id = PLANS })
			t.ok(text:find("Known by: " .. me, 1, true), "Known by: you")
			t.ok(TooltipText(Enum.TooltipDataType.Item, { id = OTHER_PLANS }):find("None of your characters", 1, true),
				"nobody knows the coif")
		end)

		t.test("a recipe link says it too", function()
			rawset(GameTooltip, "GetPrimaryTooltipInfo", function()
				return { getterName = "GetHyperlink", getterArgs = { "enchant:" .. BRACERS } }
			end)
			t.ok(TooltipText(TooltipDataProcessor.AllTypes, {}):find("Known by: " .. me, 1, true), "on the link")
			rawset(GameTooltip, "GetPrimaryTooltipInfo", nil)
		end)

		t.test("turned off: nothing remembered or shown", function()
			ns:SetSetting("inventoryTrackerRecipes", false)
			t.equal(TooltipText(Enum.TooltipDataType.Item, { id = PLANS }):find("Known by", 1, true), nil, "no line")
			ns:SetSetting("inventoryTrackerRecipes", true)
			t.noErrors()
		end)
	end,
}
