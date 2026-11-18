-- Chat commands: /nra help, per-command help, and /nra goal in all its forms.

local function Chat(wow, command)
	wow.printed = {}
	SlashCmdList.NRAKIT(command)
	return table.concat(wow.printed, "\n")
end

local function Has(text, part)
	return text:find(part, 1, true) ~= nil
end

return {
	enable = { "farmGoals", "inventoryTracker", "unitScanner", "campfireTimer" },
	db = { farmGoalsCompleteSoundChoice = "kit:UI_EPICLOOT_TOAST" }, -- the old default, saved
	run = function(t, ns, wow)
		local goals = ns.goals.GetData().goals

		t.test("the old default finish sound is moved to the new one", function()
			t.equal(NraKitDB.farmGoalsCompleteSoundChoice, "kit:UI_WORLDQUEST_COMPLETE", "finish sound")
		end)

		t.test("/nra help lists every command", function()
			local text = Chat(wow, "help")
			for _, command in ipairs({ "/nra goal", "/nra inv", "/nra scan", "/nra campfire" }) do
				t.ok(Has(text, command), "lists " .. command)
			end
			t.equal(Chat(wow, "?"), text, "/nra ? is the same")
		end)

		t.test("/nra goal help and ? show the goal commands", function()
			local text = Chat(wow, "goal help")
			t.ok(Has(text, "/nra goal rep <standing> <faction>"), "rep usage")
			t.ok(Has(text, "/nra goal skill"), "skill usage")
			t.equal(Chat(wow, "goal ?"), text, "? is the same")
			t.equal(Chat(wow, "help goal"), text, "/nra help goal is the same")
		end)

		t.test("unknown commands point to help", function()
			t.ok(Has(Chat(wow, "frobnicate"), "/nra help"), "points to help")
		end)

		t.test("/nra goal level / xp / gold", function()
			Chat(wow, "goal level 40")
			t.equal(goals[#goals].type, "level", "level goal")
			t.equal(goals[#goals].target, 40, "level")
			Chat(wow, "goal xp 50000")
			t.equal(goals[#goals].target, 50000, "xp")
			Chat(wow, "goal gold 100")
			t.equal(goals[#goals].target, 1000000, "gold in copper")
			t.ok(Has(Chat(wow, "goal level 10"), "already level"), "refuses a lower level")
		end)

		t.test("/nra goal <count> <item link or name>", function()
			Chat(wow, "goal 4000 |cffffffff|Hitem:4306::::::::30:::::|h[Silk Cloth]|h|r")
			t.equal(goals[#goals].itemID, 4306, "item from a link")
			t.equal(goals[#goals].target, 4000, "count")
		end)

		t.test("/nra goal rep, by standing or +amount, partial names", function()
			Chat(wow, "goal rep revered timber")
			local goal = goals[#goals]
			t.equal(goal.type, "rep", "type")
			t.equal(goal.key, 501, "Timbermaw Hold")
			t.equal(goal.target, 7, "Revered")
			Chat(wow, "goal rep +5000 argent")
			t.equal(goals[#goals].mode, "gain", "gain mode")
			t.equal(goals[#goals].target, 5000, "amount")
			t.ok(Has(Chat(wow, "goal rep friendly timbermaw"), "already Friendly"), "refuses a standing you have")
			t.ok(Has(Chat(wow, "goal rep revered nobody"), "No faction"), "unknown faction")
			t.ok(Has(Chat(wow, "goal rep sideways timbermaw"), "isn't a standing"), "bad standing")
		end)

		t.test("/nra goal skill, to max or a rank", function()
			Chat(wow, "goal skill swords")
			t.equal(goals[#goals].toMax, true, "to max without a rank")
			Chat(wow, "goal skill swo 280")
			t.equal(goals[#goals].target, 280, "rank")
			t.equal(goals[#goals].toMax, false, "not to max")
			t.ok(Has(Chat(wow, "goal skill swords 100"), "already"), "refuses a rank you have")
		end)

		t.test("/nra goal currency, reach or +gain", function()
			Chat(wow, "goal currency 2000 honor")
			t.equal(goals[#goals].mode, "reach", "reach")
			Chat(wow, "goal currency +500 hon")
			t.equal(goals[#goals].mode, "gain", "gain")
			t.equal(goals[#goals].target, 500, "amount")
		end)

		t.test("/nra goal list numbers the goals", function()
			local text = Chat(wow, "goal list")
			t.ok(Has(text, "1. Reach level 40"), "first goal listed")
			t.ok(Has(text, "Timbermaw Hold"), "rep goal listed")
		end)

		t.test("nonsense gets a helpful error", function()
			t.ok(Has(Chat(wow, "goal banana"), "/nra goal help"), "points to goal help")
		end)
	end,
}
