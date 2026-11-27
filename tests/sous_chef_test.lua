-- Sous Chef: the open profession's recipes are saved when the window opens, when you learn
-- one and when your skill goes up; not after every craft (the list updates after each one).

local skill = 50
local reads, schematics = 0, 0
C_TradeSkillUI = {
	IsTradeSkillReady = function()
		return true
	end,
	IsTradeSkillLinked = function()
		return false
	end,
	IsTradeSkillGuild = function()
		return false
	end,
	IsNPCCrafting = function()
		return false
	end,
	GetBaseProfessionInfo = function()
		return { profession = 3, skillLevel = skill }
	end,
	GetAllRecipeIDs = function()
		return { 101, 102 }
	end,
	GetRecipeInfo = function(id)
		reads = reads + 1
		return { learned = true, name = "Recipe " .. id, relativeDifficulty = skill < 60 and 1 or 2 }
	end,
	GetRecipeSchematic = function()
		schematics = schematics + 1
		return { reagentSlotSchematics = { { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2589 } } } } }
	end,
}
Enum.CraftingReagentType = { Basic = 1 }
-- Saving waits half a second; here it runs at once. (Redrawing the profession window's rows,
-- next frame, isn't part of this.)
C_Timer.After = function(delay, fn)
	if delay > 0 then
		fn()
	end
end

return {
	enable = { "sousChef" },
	run = function(t, ns, wow)
		local function Saved()
			for _, character in pairs(NraKitDB.sousChefRecipes or {}) do
				return character[3]
			end
		end

		t.test("opening the window saves the recipes", function()
			wow.fire("TRADE_SKILL_SHOW")
			t.ok(Saved() and Saved()[101], "saved")
			t.equal(Saved()[101].reagents[1].quantity, 2, "with what it needs")
		end)

		t.test("crafting (the list updating) doesn't read them all again", function()
			reads, schematics = 0, 0
			for _ = 1, 5 do
				wow.fire("TRADE_SKILL_LIST_UPDATE")
			end
			t.equal(reads, 0, "skill unchanged: nothing read")
		end)

		t.test("a skill-up saves them again, the reagents kept", function()
			reads, schematics = 0, 0
			skill = 60
			wow.fire("TRADE_SKILL_LIST_UPDATE")
			t.equal(reads, 2, "read again")
			t.equal(schematics, 0, "the reagents never change: not read again")
			t.equal(Saved()[101].difficulty, 2, "the new colour")
		end)
	end,
}
