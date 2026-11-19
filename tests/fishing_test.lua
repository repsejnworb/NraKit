-- Double-click fishing: when a double right-click binds right-click to the Fishing button,
-- and when it leaves right-click alone.

local POLE = 6256
local state = { mainHand = POLE, spells = { [7620] = true, [7731] = true, [7732] = true }, mouseover = false }
local binding -- what BUTTON2 is bound to, or nil

GetInventoryItemID = function(_, slot)
	return slot == 16 and state.mainHand or nil
end
IsPlayerSpell = function(spellID)
	return state.spells[spellID] == true
end
SetOverrideBindingClick = function(_, _, key, buttonName)
	if key == "BUTTON2" then
		binding = buttonName
	end
end
ClearOverrideBindings = function()
	binding = nil
end

return {
	enable = { "doubleClickFishing" },
	run = function(t, ns, wow)
		-- The stand-in's Enum gives 1 for everything: a pole is class 1, subclass 1 here.
		C_Item.GetItemInfoInstant = function(itemID)
			if itemID == POLE then
				return itemID, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 132932, 1, 1
			end
			return itemID, "Weapon", "Swords", "INVTYPE_WEAPON", 135274, 1, 7
		end
		local unitExists = UnitExists
		UnitExists = function(unit)
			if unit == "mouseover" then
				return state.mouseover
			end
			return unitExists(unit)
		end
		local button = NraKitFishingButton

		local function RightClick(after)
			wow.advance(after or 1)
			WorldFrame.scripts.OnMouseDown(WorldFrame, "RightButton")
		end
		local function Release()
			binding = nil
		end

		t.test("a double right-click casts your highest Fishing", function()
			RightClick()
			t.equal(binding, nil, "one click does nothing")
			RightClick(0.2)
			t.equal(binding, "NraKitFishingButton", "right-click bound to the Fishing button")
			t.equal(button:GetAttribute("spell"), 7732, "highest rank")
			t.equal(button:GetAttribute("type"), "spell", "casts a spell")
			button.scripts.PostClick(button)
			t.equal(binding, nil, "binding removed after the cast")
		end)

		t.test("slow clicks and a third click don't cast", function()
			RightClick()
			RightClick(0.6)
			t.equal(binding, nil, "too slow")
			RightClick(0.2)
			Release()
			RightClick(0.2)
			t.equal(binding, nil, "the third click starts over")
		end)

		t.test("the double-click time is a setting", function()
			ns:SetSetting("doubleClickFishingSpeed", 700)
			RightClick()
			RightClick(0.6)
			t.equal(binding, "NraKitFishingButton", "slower double-click counts")
			Release()
			ns:SetSetting("doubleClickFishingSpeed", 400)
		end)

		t.test("does nothing without a pole, over a unit, in combat or without Fishing", function()
			local function Double()
				RightClick()
				RightClick(0.2)
				local bound = binding
				Release()
				return bound
			end
			state.mainHand = 1234
			t.equal(Double(), nil, "a sword in your hand")
			state.mainHand = nil
			t.equal(Double(), nil, "nothing in your hand")
			state.mainHand = POLE
			state.mouseover = true
			t.equal(Double(), nil, "over an NPC")
			state.mouseover = false
			wow.data.inCombat = true
			t.equal(Double(), nil, "in combat")
			wow.data.inCombat = false
			state.spells = {}
			t.equal(Double(), nil, "Fishing not learned")
			state.spells = { [7620] = true }
			t.equal(Double(), "NraKitFishingButton", "back on")
		end)

		t.test("entering combat removes the binding", function()
			RightClick()
			RightClick(0.2)
			wow.fire("PLAYER_REGEN_DISABLED")
			t.equal(binding, nil, "removed")
		end)

		t.test("does nothing while off", function()
			ns:SetSetting("doubleClickFishing", false)
			RightClick()
			RightClick(0.2)
			t.equal(binding, nil, "off")
			t.noErrors()
		end)
	end,
}
