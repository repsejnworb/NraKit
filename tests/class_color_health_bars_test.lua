-- Class-Colored Health Bars: a player's bar in their class colour, read once per class (bars
-- update on every health change).

local hooks = {}
hooksecurefunc = function(name, fn)
	if type(name) == "string" then
		hooks[name] = fn
	end
end
function UnitFrameHealthBar_Update() end
UnitIsPlayer = function()
	return true
end
UnitIsConnected = function()
	return true
end
UnitClass = function()
	return "Warrior", "WARRIOR"
end
local reads = 0
C_ClassColor = { GetClassColor = function()
	reads = reads + 1
	return { r = 0.78, g = 0.61, b = 0.43 }
end }

return {
	enable = { "classColorHealthBars" },
	run = function(t, ns, wow)
		t.test("a player's bar is class coloured, the colour read once", function()
			local bar = CreateFrame("StatusBar")
			rawset(bar, "unit", "target")
			for _ = 1, 10 do
				hooks.UnitFrameHealthBar_Update(bar)
			end
			t.equal(rawget(bar, "color")[1], 0.78, "warrior brown")
			t.equal(reads, 1, "read once, not a new table per health change")
		end)
	end,
}
