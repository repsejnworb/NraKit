-- Lookup's Spells and Recipes modes: spells read from the client, yours first, linkable;
-- recipes found by their profession, with what a craft costs, sells for and earns.

local SPELLS = { [100] = "Charge", [7370] = "Charge", [6673] = "Battle Shout", [3501] = "Green Iron Bracers",
	[2580] = "Find Minerals", [7384] = "Overpower", [133] = "Fireball", [6603] = "Auto Attack" }

-- Your (warrior's) spellbook: General (Auto Attack: not a class spell), then Arms with Charge
-- and Overpower (not learned yet: a future spell).
local SPELLBOOK = {
	{ name = "General", items = { { id = 6603, type = 1 } } },
	{ name = "Arms", items = { { id = 100, type = 1 }, { id = 7384, type = 2 }, { id = 7369, type = 1 } } },
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return #SPELLBOOK
	end,
	GetSpellBookSkillLineInfo = function(line)
		local offset = 0
		for index = 1, line - 1 do
			offset = offset + #SPELLBOOK[index].items
		end
		return { name = SPELLBOOK[line].name, itemIndexOffset = offset, numSpellBookItems = #SPELLBOOK[line].items }
	end,
	GetSpellBookItemInfo = function(slot)
		for _, line in ipairs(SPELLBOOK) do
			if slot <= #line.items then
				local item = line.items[slot]
				return { actionID = item.id, spellID = item.id, itemType = item.type }
			end
			slot = slot - #line.items
		end
	end,
}
C_Spell.GetSpellName = function(id)
	return SPELLS[id]
end
C_Spell.GetSpellTexture = function()
	return 132337
end
C_Spell.GetSpellLink = function(id)
	return "|Hspell:" .. id .. "|h[" .. tostring(SPELLS[id]) .. "]|h"
end
-- You know your Charge, Cleave Rank 2 (845; Cleave in your spellbook is 7369), and the Green Iron
-- Bracers recipe and the Common language (both known, neither a class spell). 7370 is a pet's Charge.
SPELLS[845], SPELLS[7369], SPELLS[668] = "Cleave", "Cleave", "Common"
IsPlayerSpell = function(id)
	return id == 100 or id == 845 or id == 3501 or id == 668
end
local linked
ChatEdit_InsertLink = function(link)
	linked = link
end

-- One recipe: Green Iron Bracers (Blacksmithing), 6 Copper Bar + 1 Green Dye.
-- 2580 is a skill line's spell that isn't a profession (like a racial), and 2581 is a
-- profession's spell that isn't a recipe ("Find Herbs": no reagents, makes nothing).
SPELLS[2581] = "Find Herbs"
C_TradeSkillUI.GetProfessionInfoByRecipeID = function(id)
	if id == 3501 then
		return { professionName = "Blacksmithing", profession = 1 }
	elseif id == 2580 then
		return { professionName = "Racial - Troll" } -- no profession
	elseif id == 2581 then
		return { professionName = "Herbalism", profession = 4 }
	end
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
	-- Found with the old filter (racials and all): found again.
	-- And a mage of yours has logged in before: Fireball is a mage spell.
	db = { recipeLookupData = { build = "nil.nil", ids = { 2580, 3501 } }, spellClassData = { MAGE = { [133] = true } } },
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

		t.test("a number finds spells by ID: that one first, then IDs starting with it", function()
			local matches = ns.spellLookup.Search("7370", 10)
			t.equal(#matches, 1, "one spell has that ID")
			t.equal(matches[1].name, "Charge", "Charge, though it's not yours")
			matches = ns.spellLookup.Search("73", 10)
			local ids = {}
			for _, match in ipairs(matches) do
				t.ok(tostring(match.id):sub(1, 2) == "73", match.id .. " starts with 73")
				ids[match.id] = true
			end
			t.ok(ids[7369] and ids[7370], "both 7369 and 7370")
			t.equal(ns.spellLookup.Search(" 100 ", 10)[1].id, 100, "spaces around it are fine")
		end)

		t.test("each spell's class: from your spellbooks, General left out", function()
			local spells = ns.spellLookup
			t.equal(spells.ClassOf(100, true), "WARRIOR", "your Charge")
			t.equal(spells.ClassOf(7384), "WARRIOR", "Overpower: in your spellbook, not learned yet")
			t.equal(spells.ClassOf(133), "MAGE", "Fireball: your mage's")
			t.equal(spells.ClassOf(6603), nil, "Auto Attack (General): no class")
			t.equal(spells.ClassOf(7370), nil, "a pet's or mob's Charge: no class")
			t.equal(#spells.Search("charge", 10, "mine"), 1, "Mine: your Charge")
			-- Regression: every spell you know showed as your class's: recipes, languages...
			t.equal(spells.ClassOf(3501, true, "green iron bracers"), nil, "a known recipe: no class")
			t.equal(spells.ClassOf(668, true, "common"), nil, "a language: no class")
			t.equal(spells.ClassOf(845, true, "cleave"), "WARRIOR", "a lower rank you know: your class's")
			local mine = {}
			for _, match in ipairs(spells.Search("", 50, "mine")) do
				mine[#mine + 1] = match.name
			end
			table.sort(mine)
			t.equal(table.concat(mine, ","), "Charge,Cleave", "Mine: your class's spells you know (Charge, Cleave Rank 2), no recipe or language")
			t.equal(spells.ProfessionOf(3501), "Blacksmithing", "a known recipe shows its profession")
			t.equal(#spells.Search("charge", 10, "other"), 1, "Other: the other Charge")
			t.equal(spells.Search("", 10, "MAGE")[1].id, 133, "Mage: Fireball")
		end)

		t.test("class chips under the search box, and the class on each row", function()
			t.ok(wow.click("Mage"), "a Mage chip (a class of yours)")
			t.equal(NraKitDB.lookupSpellFilter, "MAGE", "filtering on it")
			t.ok(wow.click("All"), "All")
			local labels = {}
			for _, row in ipairs(Rows("spells")) do
				table.insert(labels, rawget(row.class, "text"))
			end
			t.equal(table.concat(labels, ","), "Warrior,other", "Charge: Warrior, then the other one: other")
		end)

		-- Regression: Mine or All with nothing typed showed nothing.
		t.test("with nothing typed, Spells lists what its button picks", function()
			local box = wow.findAll(function(frame)
				return frame.kind == "EditBox" and wow.visible(frame) and rawget(frame, "parent") == _G.NraKitItemLookupFrame.body
			end)[1]
			box:SetText("")
			t.ok(wow.click("Mine"), "Mine")
			t.equal(#Rows("spells"), 2, "your spells, with nothing typed (Charge, Cleave Rank 2)")
			t.ok(wow.click("All"), "All")
			t.ok(#Rows("spells") > 1, "everything, yours first")
			t.equal(ns.spellLookup.Search("", 10)[1].id, 100, "yours on top")
			box:SetText("charge")
		end)

		t.test("more than a page: pages in the footer", function()
			-- 250 more spells named "Charge ...".
			for id = 20001, 20250 do
				SPELLS[id] = "Charge " .. id
			end
			ns.spellLookup.Reset()
			ns:RunSlashCommand("spell charge")
			for _ = 1, 40 do
				wow.advance(0.1)
			end
			t.equal(#Rows("spells"), 100, "a page of 100")
			t.ok(wow.click("3"), "page 3")
			t.equal(#Rows("spells"), 52, "the last 52 (252 Charges)")
			t.ok(wow.click("<"), "back a page")
			t.equal(#Rows("spells"), 100, "page 2")
			-- Regression: every page click searched again (memory climbing as you paged).
			local searches = 0
			local search = ns.spellLookup.Search
			ns.spellLookup.Search = function(...)
				searches = searches + 1
				return search(...)
			end
			t.ok(wow.click(">"), "next page")
			t.ok(wow.click("1"), "page 1")
			ns.spellLookup.Search = search
			t.equal(searches, 0, "paging reuses the search")
			local box = wow.findAll(function(frame)
				return frame.kind == "EditBox" and wow.visible(frame) and rawget(frame, "parent") == _G.NraKitItemLookupFrame.body
			end)[1]
			box:SetText("charge 2001")
			t.equal(#Rows("spells"), 10, "a new search: page 1, all on it")
			for id = 20001, 20250 do
				SPELLS[id] = nil
			end
			ns.spellLookup.Reset()
			box:SetText("charge")
			for _ = 1, 40 do
				wow.advance(0.1)
			end
		end)

		t.test("closing Lookup lets go of the spell list; it's read again when needed", function()
			t.ok(ns.spellLookup.Count() > 0, "read")
			_G.NraKitItemLookupFrame:Hide()
			t.equal(ns.spellLookup.Count(), 0, "let go when closed")
			ns:RunSlashCommand("spell charge")
			for _ = 1, 40 do
				wow.advance(0.1)
			end
			t.ok(ns.spellLookup.Count() > 0, "read again")
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
			-- Regression: racial skills, Lockpicking, Riding... showed as professions.
			t.equal(ns.recipeLookup.Count(), 1, "one recipe: not the racial skill's spell, nor Find Herbs")
			t.ok(not ns.recipeLookup.IsRecipe(2580), "a racial skill isn't a profession")
			t.ok(not ns.recipeLookup.IsRecipe(2581), "a profession spell that makes nothing isn't a recipe")
			local professions = ns.recipeLookup.Professions()
			t.equal(table.concat(professions, ","), "Blacksmithing", "the only profession chip")
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
			-- Regression: the click called a Render not defined yet, so the list never redrew.
			local function Chip(name)
				return wow.findAll(function(frame)
					local text = rawget(frame, "text")
					return wow.visible(frame) and text and text.text == name and rawget(frame, "icon")
				end)[1]
			end
			t.ok(Chip("Blacksmithing").isSelected and not Chip("All").isSelected, "the list redrew: Blacksmithing lit")
			t.equal(select(2, ns.recipeLookup.Search("", 10, "name", "Blacksmithing")), 1, "its recipes")
			t.equal(select(2, ns.recipeLookup.Search("", 10, "name", "Alchemy")), 0, "not other professions'")
			local chip = wow.findAll(function(frame)
				local text = rawget(frame, "text")
				return wow.visible(frame) and text and text.text == "Blacksmithing" and rawget(frame, "icon")
			end)[1]
			t.ok(chip and chip.icon:GetTexture():find("Trade_BlackSmithing", 1, true), "with the Blacksmithing icon")
			t.ok(wow.click("All"), "All")
			t.equal(NraKitDB.lookupRecipeProfession, nil, "no filter")
			-- A remembered profession that's gone (made with the old filter): back to All.
			NraKitDB.lookupRecipeProfession = "Racial - Troll"
			ns:OpenLookup("recipes", "bracers")
			t.equal(NraKitDB.lookupRecipeProfession, nil, "a profession that's gone: All")
			-- Opening Lookup again starts on All.
			NraKitDB.lookupRecipeProfession = "Blacksmithing"
			_G.NraKitItemLookupFrame:Hide()
			_G.NraKitItemLookupFrame:Show()
			t.equal(NraKitDB.lookupRecipeProfession, nil, "opened again: All")
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
