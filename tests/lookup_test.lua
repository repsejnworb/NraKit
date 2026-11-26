-- Lookup's Spells and Recipes modes: spells read from the client, yours first, linkable;
-- recipes found by their profession, with what a craft costs, sells for and earns.

local SPELLS = { [100] = "Charge", [7370] = "Charge", [6673] = "Battle Shout", [3501] = "Green Iron Bracers",
	[2580] = "Find Minerals" }
C_Spell.GetSpellName = function(id)
	return SPELLS[id]
end
C_Spell.GetSpellTexture = function()
	return 132337
end
C_Spell.GetSpellLink = function(id)
	return "|Hspell:" .. id .. "|h[" .. tostring(SPELLS[id]) .. "]|h"
end
IsPlayerSpell = function(id)
	return id == 100 -- your Charge; 7370 is a pet's
end
local linked
ChatEdit_InsertLink = function(link)
	linked = link
end

-- One recipe: Green Iron Bracers (Blacksmithing), 6 Copper Bar + 1 Green Dye.
C_TradeSkillUI.GetProfessionInfoByRecipeID = function(id)
	return id == 3501 and { professionName = "Blacksmithing" } or nil
end
C_TradeSkillUI.GetRecipeSchematic = function(id)
	if id == 3501 then
		return { name = "Green Iron Bracers", outputItemID = 3835, quantityMin = 1, reagentSlotSchematics = {
			{ quantityRequired = 6, required = true, reagents = { { itemID = 3575 } } },
			{ quantityRequired = 1, required = true, reagents = { { itemID = 2605 } } },
		} }
	end
	return { name = "", reagentSlotSchematics = {} } -- it answers anything
end
-- Prices: Copper Bar 10s, Green Dye 50c, the bracers 90s at the auction house.
local AH = { [3575] = 1000, [2605] = 50, [3835] = 9000 }
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(_, id)
		return AH[id]
	end,
	GetAuctionPriceByItemLink = function()
		return nil
	end,
} } }

return {
	enable = { "itemLookup" },
	run = function(t, ns, wow)
		local function Settle()
			for _ = 1, 40 do
				wow.advance(0.1)
			end
		end
		local function Rows(kind)
			local rows = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "kind") == kind
			end)
			table.sort(rows, function(a, b)
				return select(5, a:GetPoint()) > select(5, b:GetPoint())
			end)
			return rows
		end

		t.test("/nra spell charge: every Charge, yours first, marked Known", function()
			ns:RunSlashCommand("spell charge")
			Settle()
			t.equal(NraKitDB.lookupMode, "spells", "Lookup in Spells mode")
			local matches = ns.spellLookup.Search("charge", 10)
			t.equal(#matches, 2, "both Charges")
			t.equal(matches[1].id, 100, "yours first")
			t.ok(matches[1].known and not matches[2].known, "yours is known")
			local rows = Rows("spells")
			t.equal(#rows, 2, "two rows")
		end)

		t.test("Shift-click links a spell in chat", function()
			local row = Rows("spells")[1]
			IsModifiedClick = function(what)
				return what == "CHATLINK"
			end
			row.scripts.OnClick(row, "LeftButton")
			IsModifiedClick = function() end
			t.ok(linked and linked:find("spell:", 1, true), "linked: " .. tostring(linked))
		end)

		t.test("Recipes: found by profession, with cost, sells for and profit", function()
			ns:RunSlashCommand("recipe bracers")
			Settle()
			t.equal(ns.recipeLookup.Count(), 1, "one recipe (the other spells have no profession)")
			local recipe = ns.recipeLookup.Get(3501)
			t.equal(recipe.profession, "Blacksmithing", "its profession")
			t.equal(#recipe.reagents, 2, "its reagents")
			local cost, sells, profit = ns.recipeLookup.Value(recipe)
			t.equal(cost, 6 * 1000 + 50, "cost of one craft")
			t.equal(sells, 9000, "sells for")
			t.equal(profit, 9000 - 6050, "profit")
			t.equal(#Rows("recipes"), 1, "listed")
			t.equal(NraKitDB.recipeLookupData.ids[1], 3501, "the recipes found are saved")
			t.noErrors()
		end)

		t.test("Recipes: a chip per profession under the search box, with its icon", function()
			t.ok(wow.click("Blacksmithing"), "a Blacksmithing chip")
			t.equal(NraKitDB.lookupRecipeProfession, "Blacksmithing", "filtering on it, remembered")
			t.equal(select(2, ns.recipeLookup.Search("", 10, "name", "Blacksmithing")), 1, "its recipes")
			t.equal(select(2, ns.recipeLookup.Search("", 10, "name", "Alchemy")), 0, "not other professions'")
			local chip = wow.findAll(function(frame)
				local text = rawget(frame, "text")
				return wow.visible(frame) and text and text.text == "Blacksmithing" and rawget(frame, "icon")
			end)[1]
			t.ok(chip and chip.icon:GetTexture():find("Trade_BlackSmithing", 1, true), "with the Blacksmithing icon")
			t.ok(wow.click("All"), "All")
			t.equal(NraKitDB.lookupRecipeProfession, nil, "no filter")
		end)

		t.test("sort recipes by profit, and search by profession", function()
			t.ok(wow.click("Profit"), "the Profit sort")
			t.equal(NraKitDB.lookupRecipeSort, "profit", "remembered")
			local matches = ns.recipeLookup.Search("blacksmith", 10, "profit")
			t.equal(#matches, 1, "by profession name")
			t.noErrors()
		end)
	end,
}
