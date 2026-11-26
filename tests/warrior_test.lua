-- Warrior, Tactical Mastery mark: a tick on the warrior's rage bar (Personal Resource Display) at the
-- rage kept on changing stance: 10 with the passive, 5 more per Improved Tactical Mastery rank.

-- The Personal Resource Display's rage bar.
PersonalResourceDisplayFrame = { PowerBar = CreateFrame("StatusBar") }

-- Procs: Overpower is spell 7384 in action slot 5 (ActionButton5). Usable is as set here.
local usable = {} -- spellID -> "up" | "rage" (short of rage) | nil
C_Spell.GetSpellInfo = function(name)
	local ids = { Overpower = 7384, Revenge = 6572 }
	return ids[name] and { spellID = ids[name] }
end
C_Spell.IsSpellUsable = function(spellID)
	return usable[spellID] == "up", usable[spellID] == "rage"
end
C_ActionBar = {
	FindSpellActionButtons = function(spellID)
		return spellID == 7384 and { 5 } or {}
	end,
}
local button = CreateFrame("CheckButton", "ActionButton5")
rawset(button, "action", 5)

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
			t.equal(x, 10, "at 10 rage")
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
			t.ok(x > 10 and x < 25, "sliding: " .. tostring(x))
			wow.advance(1)
			t.equal(mark.Shown(), 25, "at 25 rage")
			rank = 1
			wow.fire("TRAIT_CONFIG_UPDATED")
			t.equal(mark.Retained(), 15, "respecced to rank 1")
		end)

		t.test("max rage is secret: the bar gets it as is, no maths on it", function()
			local maxGiven
			local overlay = wow.frames[#wow.frames]
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "parent") == PersonalResourceDisplayFrame.PowerBar then
					overlay = frame
				end
			end
			rawset(overlay, "SetMinMaxValues", function(_, _, max)
				maxGiven = max
			end)
			UnitPowerMax = function()
				return "secret max"
			end
			wow.advance(0.1)
			t.equal(maxGiven, "secret max", "passed straight to the bar")
		end)

		t.test("the arrows: top, bottom or both, and their size", function()
			local top, bottom = mark.Arrows()
			t.ok(top:IsShown() and not bottom:IsShown(), "top by default")
			ns:SetSetting("warriorTacticalMasteryPosition", "both")
			t.ok(top:IsShown() and bottom:IsShown(), "both")
			ns:SetSetting("warriorTacticalMasteryPosition", "bottom")
			t.ok(not top:IsShown() and bottom:IsShown(), "bottom")
			ns:SetSetting("warriorTacticalMasterySize", 1.5)
			t.equal(bottom:GetWidth(), 15, "bigger")
			ns:SetSetting("warriorTacticalMasterySize", 1)
			ns:SetSetting("warriorTacticalMasteryPosition", "top")
		end)

		local procs = ns.warriorProcs
		local function Glow()
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "parent") == button and frame.alert then
					return frame
				end
			end
		end

		t.test("a proc lights its action button, with a sound if you want one", function()
			ns:SetSetting("warriorProcSound", true)
			ns:SetSetting("warriorProcSoundChoice", "kit:READY_CHECK")
			local sounds = #wow.played
			usable[7384] = "up"
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(procs.State("Overpower"), "up", "Overpower is up")
			t.equal(#wow.played, sounds + 1, "a sound")
			wow.advance(0.5)
			t.ok(Glow() and Glow():IsShown(), "the button glows")
			t.equal(Glow():GetAlpha(), 1, "brightly")
		end)

		t.test("short of rage, the glow dims instead of going", function()
			usable[7384] = "rage"
			wow.fire("UNIT_POWER_FREQUENT", "player")
			t.equal(procs.State("Overpower"), "dim", "still up")
			wow.advance(1)
			t.equal(Glow():GetAlpha(), 0.4, "dimmed")
			usable[7384] = "up"
			wow.fire("UNIT_POWER_FREQUENT", "player")
			wow.advance(1)
			t.equal(Glow():GetAlpha(), 1, "bright again")
		end)

		t.test("a proc that runs out unused teaches its time; a used one doesn't", function()
			wow.advance(2) -- up for 4.5 seconds now
			usable[7384] = nil
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(procs.State("Overpower"), nil, "gone")
			t.equal(procs.Window("Overpower"), 4.5, "learned: 4.5 seconds")
			wow.advance(1)
			t.ok(not Glow():IsShown(), "the glow faded away")

			usable[7384] = "up"
			wow.fire("SPELL_UPDATE_USABLE")
			wow.advance(6)
			wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 7384)
			usable[7384] = nil
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(procs.Window("Overpower"), 4.5, "used after 6: not its time")
		end)

		t.test("a proc that's turned off doesn't glow", function()
			ns:SetSetting("warriorProcOverpower", false)
			usable[7384] = "up"
			wow.fire("SPELL_UPDATE_USABLE")
			t.equal(procs.State("Overpower"), nil, "off")
			ns:SetSetting("warriorProcOverpower", true)
			t.equal(procs.State("Overpower"), "up", "back on")
			usable[7384] = nil
			wow.fire("SPELL_UPDATE_USABLE")
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
