-- Unspent talent points: the reminder shows while points are unspent, and stays out of the
-- way of the talents window.

-- This module's timers run at once (set before the addon loads: it queues a refresh while
-- starting up). Other modules' timers don't run, as usual here.
C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("UnspentTalents", 1, true) then
		callback()
	end
end

-- Font strings remember their frame here, so "shown" means the frame is shown too.
local createFrame = CreateFrame
CreateFrame = function(...)
	local frame = createFrame(...)
	rawset(frame, "CreateFontString", function(self)
		local text = createFrame("Frame")
		rawset(text, "parent", self)
		return text
	end)
	return frame
end

-- The talents window doesn't exist until Blizzard_PlayerSpells loads.
PlayerSpellsFrame = false

return {
	enable = { "unspentTalents" },
	run = function(t, ns, wow)
		local points = 2
		C_ClassTalents.HasUnspentTalentPoints = function()
			return points > 0, points, 0
		end
		local function Shown()
			for _, frame in ipairs(wow.frames) do
				local text = rawget(frame, "text")
				if type(text) == "string" and text:find("^Unspent talent points") and wow.visible(frame) then
					return true
				end
			end
			return false
		end
		local talents = createFrame("Frame")
		talents:Hide()

		t.test("shows while points are unspent", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			t.ok(Shown(), "shown")
			points = 0
			wow.fire("TRAIT_CONFIG_UPDATED")
			t.ok(not Shown(), "hidden once spent")
			points = 2
			wow.fire("TRAIT_CONFIG_UPDATED")
		end)

		-- Regression: it showed on top of the talents window while you spent the points.
		t.test("hidden while the talents window is open", function()
			PlayerSpellsFrame = talents
			wow.fire("ADDON_LOADED", "Blizzard_PlayerSpells")
			talents:Show()
			t.ok(not Shown(), "hidden with the window open")
			talents:Hide()
			t.ok(Shown(), "back when it closes")
			t.noErrors()
		end)
	end,
}
