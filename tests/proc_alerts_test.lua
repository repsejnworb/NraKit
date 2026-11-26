-- Proc alerts (ns.procAlerts), the shared part: any feature registers a set of spells with
-- its own option keys. Here a made-up set for a rogue's Riposte, with options borrowed from
-- the Warrior module (only their on/off values matter).

local usable = false
C_Spell.GetSpellInfo = function(name)
	return name == "Riposte" and { spellID = 14251 } or nil
end
C_Spell.IsSpellUsable = function()
	return usable, false
end
C_ActionBar = {
	FindSpellActionButtons = function(spellID)
		return spellID == 14251 and { 7 } or {}
	end,
}
local button = CreateFrame("CheckButton", "MultiBarBottomLeftButton1")
rawset(button, "action", 7)

local on = true

return {
	db = { procAlertWindows = {}, warriorProcWindows = { Overpower = 4.5 } },
	run = function(t, ns, wow)
		local alerts = ns.procAlerts
		ns.procAlerts.Register({
			key = "test",
			IsEnabled = function()
				return on
			end,
			spells = { { name = "Riposte", option = "warriorProcs" } },
			options = { countdown = "warriorProcCountdown", icon = "warriorProcIcon", sound = "warriorProcSound",
				soundChoice = "warriorProcSoundChoice" },
		})
		alerts.Refresh()

		local function Glow()
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "parent") == button and frame.alert then
					return frame
				end
			end
		end

		t.test("times measured by the warrior-only version move over", function()
			t.equal(alerts.Window("Overpower"), 4.5, "kept")
			t.equal(NraKitDB.warriorProcWindows, nil, "old key gone")
		end)

		t.test("any registered set glows its spells' buttons", function()
			usable = true
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(alerts.State("Riposte"), "up", "up")
			wow.advance(0.5)
			t.ok(Glow() and Glow():IsShown(), "its button glows")
		end)

		t.test("a set that's off shows nothing", function()
			on = false
			alerts.Refresh()
			t.equal(alerts.State("Riposte"), nil, "off")
			wow.advance(1)
			t.ok(not Glow():IsShown(), "the glow faded")
			t.noErrors()
		end)
	end,
}
