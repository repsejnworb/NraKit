-- Unit Scanner alerts for players with a Hostile label (Player notes), with an empty scan list.

return {
	enable = { "playerNotes", "unitScanner" },
	run = function(t, ns, wow)
		local notes = ns.playerNotes
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end
		wow.data.units.nameplate1 = { name = "Ann", surname = "Lee", guid = "Player-1-0003" }

		t.test("no alert for a player without a Hostile label", function()
			notes.SetLabel("Ann Lee", "avoid")
			wow.printed = {}
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			t.ok(not Printed("found"), "no alert")
		end)

		t.test("a Kill on sight player on a nameplate alerts", function()
			notes.SetLabel("Ann Lee", "kos")
			wow.printed = {}
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			t.ok(Printed("Ann Lee") and Printed("Kill on sight") and Printed("found"), "alerted")
			t.equal(#NraKitDB.unitScanTargets, 0, "not added to the scan list")
		end)

		t.test("the scanner's cooldown applies per player", function()
			wow.printed = {}
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			t.ok(not Printed("found"), "no second alert right away")
		end)

		t.test("the option turns it off", function()
			ns:SetSetting("playerNotesScanHostile", false)
			wow.advance(600)
			wow.printed = {}
			wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			t.ok(not Printed("found"), "no alert")
			ns:SetSetting("playerNotesScanHostile", true)
		end)

		t.test("the option is greyed out without Unit Scanner", function()
			ns:SetSetting("unitScanner", false)
			ns:OpenSettings("player notes", "playerNotes")
			local check
			for _, frame in ipairs(wow.findAll(function(frame)
				return frame.shown and rawget(frame, "settingKey") == "playerNotesScanHostile"
			end)) do
				check = frame
			end
			t.ok(check, "option shown")
			t.ok(not check:IsEnabled(), "greyed out")
			ns:SetSetting("unitScanner", true)
			ns:OpenSettings("player notes", "playerNotes")
			t.ok(check:IsEnabled(), "enabled again with Unit Scanner on")
		end)
	end,
}
