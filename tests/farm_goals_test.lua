-- Farm goals: the goals window form, counting, completion, sounds and editing.

local SILK = 4306
local SILK_LINK = "|cffffffff|Hitem:4306::::::::30:::::|h[Silk Cloth]|h|r"

local function Goals(ns)
	return ns.goals.GetData().goals
end

local function Newest(ns)
	local goals = Goals(ns)
	return goals[#goals]
end

local function ClearGoals(ns)
	for _, goal in ipairs(Goals(ns)) do
		goal.completed = nil
	end
	while #Goals(ns) > 0 do
		ns.goals.RemoveGoal(Goals(ns)[1].id)
	end
end

local function Played(wow, id)
	for _, played in ipairs(wow.played) do
		if played == id then
			return true
		end
	end
	return false
end

return {
	enable = { "farmGoals", "inventoryTracker" },
	run = function(t, ns, wow)
		t.test("goal data doesn't overwrite the module setting", function()
			ns.goals.GetData()
			t.equal(NraKitDB.farmGoals, true, "farmGoals setting")
			t.equal(type(NraKitDB.farmGoalsData), "table", "goal data table")
		end)

		t.test("opens on New goal when there are none, and Create waits for an item", function()
			ns:OpenGoalsWindow()
			local ok, why = wow.click("Create goal")
			t.equal(ok, false, "Create clicked")
			t.equal(why, "disabled", "Create button state")
		end)

		t.test("item goal from the form, starting from bags and bank", function()
			wow.data.items[SILK].bags, wow.data.items[SILK].bank = 40, 10
			ns:OpenGoalsWindow("new")
			wow.click("Item")
			wow.dropItem(SILK)
			wow.type(wow.amountBox(), "100")
			t.ok(wow.tick("Bags"), "ticked Bags")
			t.ok(wow.tick("Bank"), "ticked Bank")
			t.ok(wow.click("Create goal"), "clicked Create goal")
			local goal = Newest(ns)
			t.equal(goal.type, "item", "type")
			t.equal(goal.itemID, SILK, "item")
			t.equal(goal.target, 100, "target")
			t.equal(goal.start, 50, "starting count (bags + bank)")
		end)

		t.test("looting counts, crafting doesn't unless turned on", function()
			local goal = Newest(ns)
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. "x3.")
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			t.equal(goal.gained, 4, "after looting 3 + 1")
			wow.fire("CHAT_MSG_LOOT", "You create: " .. SILK_LINK .. "x2.")
			t.equal(goal.gained, 4, "crafted ignored by default")
			ns:SetSetting("farmGoalsCountCrafted", true)
			wow.fire("CHAT_MSG_LOOT", "You create: " .. SILK_LINK .. "x2.")
			t.equal(goal.gained, 6, "crafted counted when turned on")
			ns:SetSetting("farmGoalsCountCrafted", false)
			local _, text = ns.goals.GetProgress(goal)
			t.equal(text, "56 / 100", "progress text")
		end)

		t.test("edit keeps progress when only the target changes", function()
			local goal = Newest(ns)
			ns:OpenGoalsWindow("edit", goal.id)
			wow.type(wow.amountBox(), "200")
			t.ok(wow.click("Save changes"), "clicked Save changes")
			t.equal(goal.target, 200, "new target")
			t.equal(goal.gained, 6, "progress kept")
			t.equal(goal.start, 50, "starting count kept")
		end)

		t.test("edit refuses an empty target", function()
			local goal = Newest(ns)
			ns:OpenGoalsWindow("edit", goal.id)
			wow.type(wow.amountBox(), "")
			local ok, why = wow.click("Save changes")
			t.equal(why, "disabled", "Save with no amount")
			t.equal(goal.target, 200, "target unchanged")
			wow.click("Cancel")
		end)

		t.test("edit to another item starts progress over", function()
			wow.data.items[2589] = { name = "Linen Cloth", bags = 0, bank = 0 }
			local goal = Newest(ns)
			ns:OpenGoalsWindow("edit", goal.id)
			wow.dropItem(2589)
			t.ok(wow.click("Save changes"), "clicked Save changes")
			t.equal(goal.itemID, 2589, "item changed")
			t.equal(goal.gained, 0, "progress reset")
			t.equal(goal.start, 0, "starting count reset")
		end)

		t.test("finishing plays the goal's own sound and moves to history", function()
			ClearGoals(ns)
			wow.played = {}
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 2, sounds = { complete = "kit:MAP_PING" } })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. "x2.")
			t.ok(goal.completed, "completed")
			t.ok(Played(wow, SOUNDKIT.MAP_PING), "own sound played")
			t.ok(not Played(wow, SOUNDKIT.UI_EPICLOOT_TOAST), "default fanfare not played")
			local before = #ns.goals.GetData().history
			ns.goals.RemoveGoal(goal.id)
			t.equal(#ns.goals.GetData().history, before + 1, "history entries")
		end)

		t.test("default finish sound follows the setting, and None silences a goal", function()
			wow.played = {}
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1 })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			t.ok(Played(wow, SOUNDKIT.UI_EPICLOOT_TOAST), "default fanfare")
			ns.goals.RemoveGoal(goal.id)
			wow.played = {}
			goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1, sounds = { complete = "none" } })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			t.ok(goal.completed, "completed")
			t.equal(#wow.played, 0, "sounds played")
			ns.goals.RemoveGoal(goal.id)
		end)

		t.test("milestones chime once each, not for ones already passed", function()
			wow.played = {}
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 100, start = 30 })
			t.equal(goal.milestone, 1, "starts past 25%")
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. "x25.")
			t.equal(goal.milestone, 2, "reached 50%")
			t.ok(Played(wow, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01), "milestone chime")
			ns.goals.RemoveGoal(goal.id)
		end)

		t.test("reputation goal: reach a standing from the form", function()
			ClearGoals(ns)
			ns:OpenGoalsWindow("new")
			wow.click("Reputation")
			t.ok(wow.clickEntry("Timbermaw Hold"), "picked the faction")
			t.ok(wow.click("Revered"), "picked Revered")
			t.ok(wow.click("Create goal"), "clicked Create goal")
			local goal = Newest(ns)
			t.equal(goal.type, "rep", "type")
			t.equal(goal.target, 7, "target standing")
			local _, text = ns.goals.GetProgress(goal)
			t.equal(text, "Friendly 1,000/6,000  to Revered", "progress text")
			wow.data.factions[1].currentStanding = 4500
			wow.fire("UPDATE_FACTION")
			t.equal(goal.gained, 500, "rep gained")
		end)

		t.test("skill goal to max follows gains", function()
			ns:OpenGoalsWindow("new")
			wow.click("Skill")
			t.ok(wow.clickEntry("Swords"), "picked Swords")
			t.ok(wow.click("Create goal"), "clicked Create goal")
			local goal = Newest(ns)
			t.equal(goal.toMax, true, "to max")
			wow.data.skills[2].rank = 250
			wow.fire("SKILL_LINES_CHANGED")
			t.equal(goal.gained, 5, "skill points gained")
			local _, text = ns.goals.GetProgress(goal)
			t.equal(text, "250 / 300", "progress text")
		end)

		t.test("currency gain goal ignores spending", function()
			ns:OpenGoalsWindow("new")
			wow.click("Currency")
			t.ok(wow.clickEntry("Honor"), "picked Honor")
			wow.click("Gain an amount")
			wow.type(wow.amountBox(), "100")
			t.ok(wow.click("Create goal"), "clicked Create goal")
			local goal = Newest(ns)
			t.equal(goal.mode, "gain", "mode")
			wow.data.currencies[1].quantity = 150
			wow.fire("CURRENCY_DISPLAY_UPDATE")
			wow.data.currencies[1].quantity = 20
			wow.fire("CURRENCY_DISPLAY_UPDATE")
			wow.data.currencies[1].quantity = 40
			wow.fire("CURRENCY_DISPLAY_UPDATE")
			t.equal(goal.gained, 50, "gained (30 + 20, spending ignored)")
		end)

		t.test("XP counts across a level up", function()
			local goal = ns.goals.AddGoal({ type = "xp", target = 5000 })
			wow.data.xp = 900
			wow.fire("PLAYER_XP_UPDATE")
			wow.data.level, wow.data.xp, wow.data.xpMax = 31, 200, 1200
			wow.fire("PLAYER_XP_UPDATE")
			-- 100 -> 900 (+800), the last 100 of the level, then 200 into the next one.
			t.equal(goal.gained, 1100, "XP gained")
		end)

		t.test("gold counts gains only", function()
			local goal = ns.goals.AddGoal({ type = "gold", target = 100000 })
			wow.data.money = 9000
			wow.fire("PLAYER_MONEY")
			wow.data.money = 2000
			wow.fire("PLAYER_MONEY")
			t.equal(goal.gained, 4000, "gained")
		end)

		t.test("active and history pages render", function()
			ns:OpenGoalsWindow("active")
			ns:OpenGoalsWindow("history")
		end)
	end,
}
