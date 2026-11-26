-- Proc alerts (ns.procAlerts), the shared part: any feature registers a set of spells with
-- its own option keys. Here a made-up set for a rogue's Riposte, with options borrowed from
-- the Warrior module (only their on/off values matter).

-- Riposte (timed, in slot 7) and Cold Blood's made-up twin "Finish" (untimed, slot 8).
local usable = {} -- spellID -> true
local cooldown = {} -- spellID -> { isActive, isOnGCD }
C_Spell.GetSpellInfo = function(name)
	local ids = { Riposte = 14251, Finish = 9999 }
	return ids[name] and { spellID = ids[name] }
end
C_Spell.IsSpellUsable = function(spellID)
	return usable[spellID] == true, false
end
C_Spell.GetSpellCooldown = function(spellID)
	return cooldown[spellID] or { isActive = false }
end
C_ActionBar = {
	FindSpellActionButtons = function(spellID)
		return ({ [14251] = { 7 }, [9999] = { 8 } })[spellID] or {}
	end,
}
local button = CreateFrame("CheckButton", "MultiBarBottomLeftButton1")
rawset(button, "action", 7)
local finishButton = CreateFrame("CheckButton", "MultiBarBottomLeftButton2")
rawset(finishButton, "action", 8)

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
			spells = { { name = "Riposte", option = "warriorProcs" }, { name = "Finish", option = "warriorProcs", timed = false } },
			options = { countdown = "warriorProcCountdown", icon = "warriorProcIcon", sound = "warriorProcSound",
				soundChoice = "warriorProcSoundChoice" },
		})
		alerts.Refresh()

		local function Glow(over)
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "parent") == (over or button) and frame.alert then
					return frame
				end
			end
		end

		t.test("times measured by the warrior-only version move over", function()
			t.equal(alerts.Window("Overpower"), 4.5, "kept")
			t.equal(NraKitDB.warriorProcWindows, nil, "old key gone")
		end)

		t.test("any registered set glows its spells' buttons", function()
			usable[14251] = true
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(alerts.State("Riposte"), "up", "up")
			wow.advance(0.5)
			t.ok(Glow() and Glow():IsShown(), "its button glows")
			t.ok(not Glow().timer:IsShown(), "no time bar before its time is known")
		end)

		t.test("on its own cooldown it dims; the global cooldown doesn't", function()
			cooldown[14251] = { isActive = true, isOnGCD = true }
			wow.fire("SPELL_UPDATE_COOLDOWN")
			t.equal(alerts.State("Riposte"), "up", "just the global cooldown")
			cooldown[14251] = { isActive = true, isOnGCD = false }
			wow.fire("SPELL_UPDATE_COOLDOWN")
			t.equal(alerts.State("Riposte"), "dim", "its own cooldown")
			wow.advance(1)
			t.equal(Glow():GetAlpha(), 0.4, "dimmed")
			cooldown[14251] = nil
			wow.fire("SPELL_UPDATE_COOLDOWN")
			t.equal(alerts.State("Riposte"), "up", "cooldown over: press it")
			usable[14251] = nil
			wow.fire("SPELL_UPDATE_USABLE")
		end)

		t.test("a known time shows as a draining bar, orange and pulsing at the end", function()
			NraKitDB.procAlertWindows.Riposte = 5
			usable[14251] = true
			wow.fire("SPELL_UPDATE_USABLE")
			wow.advance(1)
			local glow = Glow()
			t.ok(glow.timer:IsShown(), "the bar")
			t.equal(glow.timer:GetValue(), 0.8, "4 of 5 seconds left")
			t.equal(glow.alert:GetAlpha(), 1, "steady")
			wow.advance(3)
			t.equal(glow.timer:GetValue(), 0.2, "1 second left")
			t.equal(rawget(glow.timer, "color")[1], 1, "orange")
			t.ok(glow.alert:GetAlpha() < 1, "pulsing")
			usable[14251] = nil
			wow.fire("SPELL_UPDATE_USABLE")
		end)

		t.test("an untimed spell glows but has no bar and teaches no time", function()
			usable[9999] = true
			wow.fire("SPELL_UPDATE_USABLE")
			wow.advance(3)
			t.ok(Glow(finishButton):IsShown(), "glows")
			t.ok(not Glow(finishButton).timer:IsShown(), "no bar")
			usable[9999] = nil
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(alerts.Window("Finish"), nil, "nothing learned")
		end)

		t.test("a set that's off shows nothing", function()
			usable[14251] = true
			alerts.Refresh()
			on = false
			alerts.Refresh()
			t.equal(alerts.State("Riposte"), nil, "off")
			wow.advance(1)
			t.ok(not Glow():IsShown(), "the glow faded")
			t.noErrors()
		end)
	end,
}
