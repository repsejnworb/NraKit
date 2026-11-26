-- Cooldown Manager Fade: the bars show in combat (and with a hostile target, and under the
-- mouse) and fade out, animated, a while after; visible is their Edit Mode opacity.

-- hooksecurefunc really hooks here on tables (for the Edit Mode opacity).
local noHook = hooksecurefunc
hooksecurefunc = function(target, name, hook)
	if type(target) ~= "table" then
		return noHook(target, name, hook)
	end
	local original = target[name]
	target[name] = function(...)
		original(...)
		hook(...)
	end
end

-- The Cooldown Manager's bars: Edit Mode opacity 80%, which the game sets with SetAlpha.
local function Viewer(name)
	local viewer = CreateFrame("Frame", name)
	viewer:SetAlpha(0.8)
	rawset(viewer, "UpdateSystemSettingOpacity", function(self)
		self:SetAlpha(rawget(self, "editModeOpacity") or 0.8)
	end)
	return viewer
end
local essential = Viewer("EssentialCooldownViewer")
local utility = Viewer("UtilityCooldownViewer")
local buffs = Viewer("BuffIconCooldownViewer")

local hostile = false
UnitCanAttack = function(_, unit)
	return unit == "target" and hostile
end
UnitIsDead = function()
	return false
end

return {
	enable = { "cooldownManagerFade" },
	run = function(t, ns, wow)
		local function Near(actual, expected, message)
			t.ok(math.abs(actual - expected) < 0.001, string.format("%s: expected %.3f, got %.3f", message, expected, actual))
		end
		local function Target(on)
			hostile = on
			wow.data.units.target = on and { name = "Defias Thug" } or nil
			wow.fire("PLAYER_TARGET_CHANGED")
		end

		t.test("out of combat the bars fade out, over the fade time", function()
			wow.advance(1)
			Near(essential:GetAlpha(), 0.4, "halfway after 1 of 2 seconds")
			Near(utility:GetAlpha(), 0.4, "Utility too")
			wow.advance(1.5)
			Near(essential:GetAlpha(), 0, "gone")
			Near(buffs:GetAlpha(), 0.8, "Tracked Buffs (off by default) keep their own opacity")
		end)

		t.test("combat fades them in quickly, still animated, to their Edit Mode opacity", function()
			wow.fire("PLAYER_REGEN_DISABLED")
			wow.advance(0.2)
			Near(essential:GetAlpha(), 0.4, "half way in")
			wow.advance(0.3)
			Near(essential:GetAlpha(), 0.8, "full: the Edit Mode opacity")
		end)

		t.test("after combat they stay a while, then fade", function()
			wow.fire("PLAYER_REGEN_ENABLED")
			wow.advance(9)
			Near(essential:GetAlpha(), 0.8, "still there after 9 of 10 seconds")
			wow.advance(1.5) -- 0.5 past the stay
			Near(essential:GetAlpha(), 0.2, "fading")
			wow.fire("PLAYER_REGEN_DISABLED")
			wow.advance(0.5)
			Near(essential:GetAlpha(), 0.8, "combat again: straight back")
			wow.fire("PLAYER_REGEN_ENABLED")
			wow.advance(20)
			Near(essential:GetAlpha(), 0, "faded")
		end)

		t.test("faded opacity leaves a trace", function()
			ns:SetSetting("cooldownFadeOpacity", 0.25)
			wow.advance(0.1)
			Near(essential:GetAlpha(), 0.2, "25% of 80%")
			ns:SetSetting("cooldownFadeOpacity", 0)
			wow.advance(0.1)
		end)

		t.test("a hostile target shows them; losing it fades at once (or after the stay)", function()
			Target(true)
			wow.advance(0.4)
			Near(essential:GetAlpha(), 0.8, "shown with a target")
			Target(false)
			wow.advance(1)
			Near(essential:GetAlpha(), 0.4, "fading at once")
			wow.advance(2)
			ns:SetSetting("cooldownFadeTargetNow", false)
			Target(true)
			wow.advance(0.4)
			Target(false)
			wow.advance(5)
			Near(essential:GetAlpha(), 0.8, "option off: waits the stay")
			wow.advance(20)
			ns:SetSetting("cooldownFadeTargetNow", true)
			ns:SetSetting("cooldownFadeTarget", false)
			Target(true)
			wow.advance(1)
			Near(essential:GetAlpha(), 0, "showing with a target off")
			Target(false)
			ns:SetSetting("cooldownFadeTarget", true)
		end)

		t.test("the mouse over a bar brings it back, with a moment's grace on leaving", function()
			rawset(essential, "mouseOver", true)
			wow.advance(0.4)
			Near(essential:GetAlpha(), 0.8, "shown under the mouse")
			Near(utility:GetAlpha(), 0, "only that bar")
			rawset(essential, "mouseOver", false)
			wow.advance(0.3)
			Near(essential:GetAlpha(), 0.8, "not blinking out at once")
			wow.advance(0.3) -- past the grace: 0.3 of the 2 seconds' fade
			Near(essential:GetAlpha(), 0.68, "then fading")
			wow.advance(2)
		end)

		t.test("Edit Mode opacity changes are followed; editing shows them", function()
			rawset(essential, "editModeOpacity", 0.5)
			essential:UpdateSystemSettingOpacity()
			rawset(essential, "isEditing", true)
			wow.advance(0.4)
			Near(essential:GetAlpha(), 0.5, "the new opacity, shown while editing")
			rawset(essential, "isEditing", nil)
			wow.advance(3)
			Near(essential:GetAlpha(), 0, "faded again")
		end)

		t.test("a bar turned off, or the feature, gets its own opacity back", function()
			ns:SetSetting("cooldownFadeUtility", false)
			wow.advance(0.1)
			Near(utility:GetAlpha(), 0.8, "Utility back")
			ns:SetSetting("cooldownManagerFade", false)
			Near(essential:GetAlpha(), 0.5, "Essential back to its own")
			wow.advance(1)
			Near(essential:GetAlpha(), 0.5, "and left alone")
			t.noErrors()
		end)
	end,
}
