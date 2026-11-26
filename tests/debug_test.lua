-- Debug logging (Debug.lua): off by default, per feature, kept for the copy box, survives
-- /reload (saved), and costs nothing when off.

return {
	run = function(t, ns, wow)
		ns:RegisterDebug("demo", "a feature that logs")

		t.test("off by default: nothing logged, nothing formatted", function()
			local formatted = false
			local spy = setmetatable({}, { __tostring = function()
				formatted = true
				return "spy"
			end })
			ns:Debug("demo", "value %s", spy)
			t.equal(#ns:DebugLines(), 0, "nothing kept")
			t.ok(not formatted, "its text never built")
		end)

		t.test("/nra debug <name> turns it on: lines in chat and kept, saved", function()
			ns:RunSlashCommand("debug demo")
			t.ok(ns:IsDebugging("demo"), "on")
			t.equal(NraKitDB.debugOn.demo, true, "saved, for after /reload")
			wow.printed = {}
			ns:Debug("demo", "moved %d from %s", 4, "6:4")
			t.ok(table.concat(wow.printed, "\n"):find("moved 4 from 6:4", 1, true), "in chat")
			t.ok(ns:DebugLines()[1]:find("demo: moved 4 from 6:4", 1, true), "kept for copying")
		end)

		t.test("/nra debug lists them, copy shows the lines, off turns all off", function()
			wow.printed = {}
			ns:RunSlashCommand("debug")
			local listed = table.concat(wow.printed, "\n")
			t.ok(listed:find("demo", 1, true) and listed:find("sell", 1, true), "every feature that logs")
			ns:RunSlashCommand("debug copy")
			t.ok(_G.NraKitDebugCopyFrame:IsShown(), "the copy box")
			_G.NraKitDebugCopyFrame:Hide()
			ns:RunSlashCommand("debug off")
			t.ok(not ns:IsDebugging("demo"), "all off")
			t.noErrors()
		end)
	end,
}
