-- Shortcuts: /goal = /nra goal and so on, but only commands nobody else has. Here the game's
-- command tables are set up the way the client keeps them.

-- The game's lookup tables: Blizzard's /scan (made up), an emote /wish, and another addon's
-- /note that the game hasn't moved into its tables yet.
hash_ChatTypeInfoList = { ["/SCAN"] = "BLIZZARDSCAN" }
hash_SlashCmdList = {}
hash_EmoteTokenList = { ["/WISH"] = "WISH" }
SLASH_OTHERNOTES1 = "/note"
SlashCmdList.OTHERNOTES = function() end

return {
	enable = { "shortcuts", "farmGoals", "playerNotes", "unitScanner", "wishlist" },
	run = function(t, ns, wow)
		local shortcuts = ns.shortcuts
		local ran = {}
		local run = ns.RunSlashCommand
		ns.RunSlashCommand = function(self, input)
			table.insert(ran, input)
		end

		t.test("nothing is taken until a few seconds after entering the world", function()
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, nil, "not yet")
			wow.fire("PLAYER_ENTERING_WORLD")
			wow.advance(3.5)
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, "/goal", "/goal is ours now")
		end)

		t.test("a shortcut runs its /nra command", function()
			SlashCmdList.NRAKITSHORTCUT_GOAL("20 linen")
			t.equal(ran[#ran], "goal 20 linen", "with what follows")
			SlashCmdList.NRAKITSHORTCUT_GOAL("")
			t.equal(ran[#ran], "goal", "or alone")
		end)

		t.test("ones in use elsewhere are left alone", function()
			t.equal(SLASH_NRAKITSHORTCUT_NOTE1, nil, "another addon's /note")
			t.equal(select(2, shortcuts.State("note")), "OTHERNOTES", "says whose")
			t.equal(SLASH_NRAKITSHORTCUT_SCAN1, nil, "the game's /scan")
			t.equal(shortcuts.State("wish"), "taken", "an emote's /wish")
		end)

		t.test("a feature that's off gets no shortcut", function()
			t.equal(SLASH_NRAKITSHORTCUT_REMIND1, nil, "Reminders is off")
			t.equal(shortcuts.State("remind"), "feature off", "and says so")
			t.equal(SLASH_NRAKITSHORTCUT_DPS1, "/dps", "/dps needs no feature")
		end)

		t.test("turning a shortcut off takes it back out of the game's tables", function()
			-- As if the game had moved it into its tables.
			hash_ChatTypeInfoList["/GOAL"] = "NRAKITSHORTCUT_GOAL"
			hash_SlashCmdList["/GOAL"] = SlashCmdList.NRAKITSHORTCUT_GOAL
			ns:SetSetting("shortcutGoal", false)
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, nil, "unregistered")
			t.equal(hash_SlashCmdList["/GOAL"], nil, "out of the lookup")
			t.equal(hash_ChatTypeInfoList["/GOAL"], nil, "and the owner table")
			ns:SetSetting("shortcutGoal", true)
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, "/goal", "back")
		end)

		t.test("turning its feature off takes it back too", function()
			ns:SetSetting("farmGoals", false)
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, nil, "gone with Farm goals")
			ns:SetSetting("farmGoals", true)
			t.equal(SLASH_NRAKITSHORTCUT_GOAL1, "/goal", "back with it")
		end)

		t.test("an addon that registers the command later gets it", function()
			local theirs
			SLASH_LATEGOALS1 = "/goal"
			SlashCmdList.LATEGOALS = function(input)
				theirs = input
			end
			local count = #ran
			SlashCmdList.NRAKITSHORTCUT_GOAL("hello")
			t.equal(theirs, "hello", "handed on to them")
			t.equal(#ran, count, "not run as /nra goal")
		end)

		t.test("/nra shortcuts lists them", function()
			ns.RunSlashCommand = run
			wow.printed = {}
			ns:RunSlashCommand("shortcuts")
			local text = table.concat(wow.printed, "\n")
			t.ok(text:find("/dps", 1, true) and text:find("active", 1, true), "active ones")
			t.ok(text:find("in use by OTHERNOTES", 1, true), "and whose the taken ones are")
			t.noErrors()
		end)
	end,
}
