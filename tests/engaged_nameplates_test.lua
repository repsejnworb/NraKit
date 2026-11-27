-- Engaged Nameplates: threat and group updates (many a second in a group fight) look at the
-- plates once a frame at most.

local lookedAt = 0
C_NamePlate = {
	GetNamePlates = function()
		lookedAt = lookedAt + 1
		return {}
	end,
	GetNamePlateForUnit = function() end,
}

return {
	enable = { "engagedNameplates" },
	run = function(t, ns, wow)
		t.test("a burst of threat updates looks at the plates once", function()
			wow.advance(0.1)
			lookedAt = 0
			for _ = 1, 20 do
				wow.fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
				wow.fire("GROUP_ROSTER_UPDATE")
			end
			t.equal(lookedAt, 0, "not on each one")
			wow.advance(0.1)
			t.equal(lookedAt, 1, "once, the next frame")
			wow.advance(0.1)
			t.equal(lookedAt, 1, "and then rests")
			t.noErrors()
		end)
	end,
}
