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

-- The tracker's goal rows or tiles that are showing.
local function TrackedWidgets(wow)
	return wow.findAll(function(frame)
		return frame.shown and type(rawget(frame, "goal")) == "table" and rawget(frame, "flash") ~= nil
	end)
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
			t.ok(not Played(wow, SOUNDKIT.UI_WORLDQUEST_COMPLETE), "default fanfare not played")
			local before = #ns.goals.GetData().history
			ns.goals.RemoveGoal(goal.id)
			t.equal(#ns.goals.GetData().history, before + 1, "history entries")
		end)

		t.test("default finish sound follows the setting, and None silences a goal", function()
			wow.played = {}
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1 })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			t.ok(Played(wow, SOUNDKIT.UI_WORLDQUEST_COMPLETE), "default fanfare (World quest complete)")
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

		t.test("shelving hides a goal from the tracker and stops counting", function()
			ClearGoals(ns)
			local kept = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1000 })
			local shelved = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 2000 })
			ns.goals.SetShelved(shelved, true)
			t.ok(shelved.paused, "shelved goals are paused")
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. "x5.")
			t.equal(kept.gained, 5, "the other goal counts")
			t.equal(shelved.gained, 0, "the shelved goal doesn't")
			local shown = TrackedWidgets(wow)
			t.equal(#shown, 1, "goals in the tracker")
			t.equal(shown[1].goal, kept, "the unshelved one")
			ns:OpenGoalsWindow("active")
			t.ok(wow.click("Unshelve"), "Unshelve button in the goals window")
			t.ok(not shelved.shelved and not shelved.paused, "back and counting")
			t.equal(#TrackedWidgets(wow), 2, "both in the tracker again")
		end)

		t.test("all three tracker views show the goals", function()
			for _, view in ipairs({ "compact", "icons", "full" }) do
				t.ok(wow.click(NraKitDB.farmGoalsView == nil and "F" or ({ full = "F", compact = "C", icons = "I" })[NraKitDB.farmGoalsView]), "clicked the view button")
				t.equal(NraKitDB.farmGoalsView, view, "switched view")
				t.equal(#TrackedWidgets(wow), 2, view .. ": goals shown")
			end
		end)

		t.test("the icons view shows short amounts", function()
			ClearGoals(ns)
			NraKitDB.farmGoalsView = "icons"
			ns.goals.AddGoal({ type = "item", itemID = SILK, target = 4000, start = 1500 })
			local tile = TrackedWidgets(wow)[1]
			t.equal(tile.count.text, "1.5k", "count under the icon")
			NraKitDB.farmGoalsView = "full"
		end)

		t.test("go again: the run goes to the history and the goal starts over", function()
			ClearGoals(ns)
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 3 })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. "x3.")
			t.ok(goal.completed, "finished")
			t.equal(ns.goals.GoAgainAmount(goal), "3 Silk Cloth", "menu label amount")
			local before = #ns.goals.GetData().history
			ns:OpenGoalsWindow("active")
			t.ok(wow.click("Go again"), "Go again button")
			t.equal(#ns.goals.GetData().history, before + 1, "run recorded")
			t.equal(ns.goals.GetData().history[1].goal, nil, "a run record isn't restorable")
			t.ok(not goal.completed, "running again")
			t.equal(goal.gained, 0, "from zero")
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			t.equal(goal.gained, 1, "counting again")
		end)

		t.test("a finished reach goal offers a new target instead", function()
			ClearGoals(ns)
			wow.data.level = 31
			local goal = ns.goals.AddGoal({ type = "level", target = 31 })
			t.ok(goal.completed, "already reached")
			t.ok(not ns.goals.CanGoAgain(goal), "can't go again")
			ns:OpenGoalsWindow("active")
			t.ok(wow.click("New target"), "New target button")
			wow.type(wow.amountBox(), "35")
			t.ok(wow.click("Save changes"), "saved")
			t.equal(goal.target, 35, "new target")
			t.ok(not goal.completed, "running again")
		end)

		t.test("a finished goal glows until you hover it, and a click clears it", function()
			ClearGoals(ns)
			NraKitDB.farmGoalsView = "full"
			local goal = ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1 })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			local row = TrackedWidgets(wow)[1]
			row.scripts.OnUpdate(row)
			t.ok(row.glow.shown, "glowing")
			row.scripts.OnEnter(row)
			row.scripts.OnUpdate(row)
			t.ok(not row.glow.shown, "glow stops once seen")
			row.scripts.OnClick(row, "LeftButton")
			t.equal(#Goals(ns), 0, "cleared")
			local entry = ns.goals.GetData().history[1]
			t.ok(entry.goal ~= nil, "restorable")
			ns:OpenGoalsWindow("history")
			t.ok(wow.click("Restore"), "Restore button")
			t.equal(#Goals(ns), 1, "back")
			t.ok(Goals(ns)[1].completed, "still finished")
		end)

		t.test("a goal finished in combat is shown again after the fight", function()
			ClearGoals(ns)
			wow.data.inCombat = true
			ns.goals.AddGoal({ type = "item", itemID = SILK, target = 1 })
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. SILK_LINK .. ".")
			wow.data.inCombat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			local found = wow.findAll(function(frame)
				return frame.text == "while you were fighting"
			end)
			t.equal(#found, 1, "replayed message")
		end)

		t.test("a money goal from the form takes silver, and edits back to the same text", function()
			ClearGoals(ns)
			ns:OpenGoalsWindow("new")
			wow.click("Gold")
			wow.type(wow.amountBox(), "1g 50s")
			t.ok(wow.click("Create goal"), "clicked Create goal")
			local goal = Newest(ns)
			t.equal(goal.target, 15000, "copper")
			ns:OpenGoalsWindow("edit", goal.id)
			t.equal(wow.amountBox().text, "1g 50s", "edit shows the amount")
			t.ok(wow.click("Save changes"), "saves unchanged")
			t.equal(goal.target, 15000, "still the same")
		end)

		t.test("a 1g goal counts up in silver and copper", function()
			ClearGoals(ns)
			wow.data.money = 0
			wow.fire("PLAYER_MONEY")
			local goal = ns.goals.AddGoal({ type = "gold", target = 10000 })
			wow.data.money = 4520
			wow.fire("PLAYER_MONEY")
			local fraction, text = ns.goals.GetProgress(goal)
			t.equal(text, "45s 20c / 1g", "progress text")
			t.ok(math.abs(fraction - 0.452) < 0.0001, "bar at 45.2%")
			NraKitDB.farmGoalsView = "icons"
			ns.goals.Update()
			t.equal(TrackedWidgets(wow)[1].count.text, "45s", "icon amount")
			NraKitDB.farmGoalsView = "full"
		end)

		t.test("money parsing", function()
			local parse = ns.goals.ParseMoney
			t.equal(parse("100"), 1000000, "plain number is gold")
			t.equal(parse("50s"), 5000, "silver")
			t.equal(parse("1,234g"), 12340000, "thousands separator")
			t.equal(parse("75c"), 75, "copper")
			t.equal(parse("1g 50x"), nil, "junk")
			t.equal(parse(""), nil, "empty")
		end)

		t.test("active and history pages render", function()
			ns:OpenGoalsWindow("active")
			ns:OpenGoalsWindow("history")
		end)
	end,
}
