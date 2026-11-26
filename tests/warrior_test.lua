-- Warrior, Tactical Mastery mark: a tick on the warrior's rage bar (Personal Resource Display) at the
-- rage kept on changing stance: 10 with the passive, 5 more per Improved Tactical Mastery rank.

-- The Personal Resource Display's rage bar: 200 pixels wide, 0 to 100 rage.
local powerBar = CreateFrame("StatusBar")
powerBar:SetWidth(200)
rawset(powerBar, "GetMinMaxValues", function()
	return 0, 100
end)
PersonalResourceDisplayFrame = { PowerBar = powerBar }

Enum.PowerType = Enum.PowerType or {}
Enum.PowerType.Rage = 1
UnitPowerType = function()
	return Enum.PowerType.Rage
end

local known = {}
IsPlayerSpell = function(spellID)
	return known[spellID] == true
end

-- One talent tree: node 5 is Improved Tactical Mastery (entry 50, definition 500).
local rank = 0
C_ClassTalents = {
	GetActiveConfigID = function()
		return 1
	end,
}
C_Traits = {
	GetConfigInfo = function()
		return { treeIDs = { 9 } }
	end,
	GetTreeNodes = function()
		return { 4, 5 }
	end,
	GetNodeInfo = function(_, nodeID)
		if nodeID == 4 then
			return { entryIDs = { 40 }, activeRank = 1 }
		end
		return { entryIDs = { 50 }, activeRank = rank }
	end,
	GetEntryInfo = function(_, entryID)
		return { definitionID = entryID * 10 }
	end,
	GetDefinitionInfo = function(definitionID)
		return { spellID = definitionID == 500 and 12295 or 6673 }
	end,
}

return {
	enable = { "warrior" },
	run = function(t, ns, wow)
		local mark = ns.tacticalMastery

		t.test("no mark before you learn Tactical Mastery", function()
			wow.fire("SPELLS_CHANGED")
			wow.advance(1)
			local x, alpha = mark.Shown()
			t.equal(mark.Retained(), 0, "keeps nothing")
			t.equal(x, nil, "no mark")
			t.equal(alpha, 0, "nothing shown")
		end)

		t.test("learning it marks 10 rage, fading in", function()
			known[1310185] = true
			wow.fire("SPELLS_CHANGED")
			wow.advance(0.2)
			local x, alpha = mark.Shown()
			t.equal(x, 20, "10 of 100 rage on a 200 pixel bar")
			t.ok(alpha > 0 and alpha < 1, "fading in")
			wow.advance(1)
			t.equal(select(2, mark.Shown()), 1, "shown")
		end)

		t.test("each Improved Tactical Mastery rank adds 5, and the mark slides there", function()
			rank = 3
			wow.fire("TRAIT_CONFIG_UPDATED")
			t.equal(mark.Retained(), 25, "10 + 3 x 5")
			wow.advance(0.2)
			local x = mark.Shown()
			t.ok(x > 20 and x < 50, "sliding: " .. tostring(x))
			wow.advance(1)
			t.equal(mark.Shown(), 50, "at 25 rage")
			rank = 1
			wow.fire("TRAIT_CONFIG_UPDATED")
			t.equal(mark.Retained(), 15, "respecced to rank 1")
		end)

		t.test("turned off, the mark fades away", function()
			ns:SetSetting("warriorTacticalMastery", false)
			wow.advance(0.2)
			t.ok(select(2, mark.Shown()) > 0, "still fading")
			wow.advance(1)
			t.equal(select(2, mark.Shown()), 0, "gone")
			ns:SetSetting("warriorTacticalMastery", true)
			wow.advance(1)
			t.equal(select(2, mark.Shown()), 1, "back with the option")
			ns:SetSetting("warrior", false)
			wow.advance(1)
			t.equal(select(2, mark.Shown()), 0, "gone with the module")
			t.noErrors()
		end)
	end,
}
