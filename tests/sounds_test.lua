-- Sound choices: labels, validity, fallbacks, and the sound rows in both settings UIs.

return {
	enable = { "campfireTimer", "unitScanner", "farmGoals" },
	run = function(t, ns, wow)
		local sounds = ns.sounds

		t.test("labels: curated names, readable Blizzard names, None", function()
			t.equal(sounds.Label("kit:UI_EPICLOOT_TOAST"), "Epic loot", "curated")
			t.equal(sounds.Label("kit:UI_SOME_THING"), "Some thing", "other Blizzard sound")
			t.equal(sounds.Label("none"), "None", "none")
			t.equal(sounds.Label("lsm:Bell"), "Bell", "shared media")
		end)

		t.test("validity", function()
			t.ok(sounds.IsValid("kit:READY_CHECK"), "known Blizzard sound")
			t.ok(sounds.IsValid("none"), "none")
			t.ok(not sounds.IsValid("kit:NOT_A_SOUND"), "unknown Blizzard sound")
			t.ok(not sounds.IsValid("lsm:Bell"), "shared media without the library")
			t.ok(not sounds.IsValid(true), "an old on/off value")
			t.ok(not sounds.IsValid(nil), "nothing")
		end)

		t.test("options default to the old sounds", function()
			t.equal(NraKitDB.campfireTimerSoundChoice, "kit:READY_CHECK", "campfire")
			t.equal(NraKitDB.unitScanSoundChoice, "kit:RAID_WARNING", "scanner")
			t.equal(NraKitDB.farmGoalsCompleteSoundChoice, "kit:UI_EPICLOOT_TOAST", "goal done")
		end)

		t.test("a chosen sound plays, a missing one falls back to the default", function()
			wow.played = {}
			ns:SetSetting("unitScanSoundChoice", "kit:MAP_PING")
			wow.played = {} -- choosing it plays a preview
			sounds.PlayOption("unitScanSoundChoice", "kit:RAID_WARNING")
			t.equal(wow.played[1], SOUNDKIT.MAP_PING, "chosen sound")
			NraKitDB.unitScanSoundChoice = "lsm:Gone"
			wow.played = {}
			sounds.PlayOption("unitScanSoundChoice", "kit:RAID_WARNING")
			t.equal(wow.played[1], SOUNDKIT.RAID_WARNING, "fallback")
		end)

		t.test("None plays nothing", function()
			ns:SetSetting("unitScanSoundChoice", "none")
			wow.played = {}
			sounds.PlayOption("unitScanSoundChoice", "kit:RAID_WARNING")
			t.equal(#wow.played, 0, "sounds played")
		end)

		t.test("the settings window shows a sound row per sound option", function()
			ns:OpenSettings()
			local search = wow.findAll(function(frame)
				return frame.template == "SearchBoxTemplate" and frame.scripts.OnTextChanged
			end)[1]
			wow.type(search, "sound")
			local rows = {}
			for _, frame in ipairs(wow.findAll(function(frame)
				return rawget(frame, "optionKey") ~= nil and frame.shown
			end)) do
				rows[frame.optionKey] = frame.button.text.text
			end
			t.equal(rows.campfireTimerSoundChoice, "Ready check", "campfire row")
			t.equal(rows.farmGoalsMilestoneSoundChoice, "Rolling forward", "milestone row")
			t.equal(rows.unitScanSoundChoice, "None", "scanner row")
		end)

		t.test("the full list opens", function()
			sounds.OpenPicker("kit:READY_CHECK", function() end)
			t.ok(NraKitSoundPicker:IsShown(), "picker shown")
			t.ok(#sounds.All() >= 5, "sounds listed")
		end)
	end,
}
