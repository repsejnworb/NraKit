-- Unlearned Abilities: a warrior respecs from Protection to Fury. Concussion Blow stays on
-- the bar unlearned: it gets a mark, a tooltip line and a message that takes it off.

local CONCUSSION_BLOW, SLAM, BLOODTHIRST = 100, 200, 300
local NAMES = { [CONCUSSION_BLOW] = "Concussion Blow", [SLAM] = "Slam", [BLOODTHIRST] = "Bloodthirst" }

local book = { CONCUSSION_BLOW, SLAM } -- the spellbook
local actions = { [1] = CONCUSSION_BLOW, [2] = SLAM } -- action slot -> spell
local picked = {}

-- hooksecurefunc really hooks methods here, so button updates and tooltips reach the module.
local hook = hooksecurefunc
hooksecurefunc = function(target, name, fn)
	if type(target) == "table" then
		local original = target[name]
		rawset(target, name, function(...)
			original(...)
			fn(...)
		end)
	else
		hook(target, name, fn)
	end
end
-- This module's timers run at once; other modules' don't run, as usual here.
C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("UnlearnedAbilities", 1, true) then
		callback()
	end
end

Enum.SpellBookItemType = { Spell = 1 }
Enum.SpellBookSpellBank = { Player = 0 }
C_SpellBook = {
	IsSpellKnownOrInSpellBook = function(spellID)
		for _, known in ipairs(book) do
			if known == spellID then
				return true
			end
		end
		return false
	end,
	FindBaseSpellByID = function(spellID)
		return spellID
	end,
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = #book }
	end,
	GetSpellBookItemInfo = function(index)
		return { itemType = 1, actionID = book[index], isPassive = false, isOffSpec = false }
	end,
}
C_ActionBar = {
	FindSpellActionButtons = function(spellID)
		local slots = {}
		for slot = 1, 12 do
			if actions[slot] == spellID then
				table.insert(slots, slot)
			end
		end
		return slots
	end,
}
GetActionInfo = function(slot)
	if actions[slot] then
		return "spell", actions[slot], "spell"
	end
end
PickupAction = function(slot)
	table.insert(picked, slot)
	actions[slot] = nil
end

-- Confirmations: the one shown, and its dialog.
StaticPopupDialogs = {}
local popup
StaticPopup_Show = function(name, text)
	popup = { dialog = StaticPopupDialogs[name], text = text }
end

-- Two bar buttons.
for index = 1, 2 do
	local button = CreateFrame("Button")
	rawset(button, "action", index)
	rawset(button, "Update", function() end)
	_G["ActionButton" .. index] = button
end

return {
	enable = { "unlearnedAbilities" },
	run = function(t, ns, wow)
		C_Spell.GetSpellName = function(spellID)
			return NAMES[spellID]
		end
		C_Spell.DoesSpellExist = function()
			return true
		end
		local toasts = {}
		ns.toast.Show = function(spec)
			table.insert(toasts, spec)
		end
		local function Marked(index)
			local button = _G["ActionButton" .. index]
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "cross") and rawget(frame, "parent") == button then
					return frame.shown
				end
			end
			return false
		end
		local function TooltipLine(slot)
			local found
			rawset(GameTooltip, "AddLine", function(_, text)
				if text:find("^NraKit: Not learned") then
					found = text
				end
			end)
			GameTooltip:SetAction(slot)
			return found
		end

		t.test("nothing to say while you know everything", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			t.ok(not Marked(1) and not Marked(2), "no marks")
			t.equal(#toasts, 0, "no message")
			t.equal(TooltipLine(1), nil, "no tooltip line")
		end)

		t.test("an empty spellbook (still loading) isn't a change", function()
			local saved = book
			book = {}
			wow.fire("SPELLS_CHANGED")
			book = saved
			wow.fire("SPELLS_CHANGED")
			t.equal(#toasts, 0, "nothing lost or new")
		end)

		t.test("after a respec: lost abilities on your bars are marked and listed, new ones too", function()
			-- You respec in the talents window: the messages wait until it's closed (they'd sit on
			-- top of it and take a click meant for it).
			PlayerSpellsFrame:Show()
			book = { SLAM, BLOODTHIRST }
			wow.fire("SPELLS_CHANGED")
			t.equal(#toasts, 0, "no message while the talents window is open")
			PlayerSpellsFrame:Hide()
			t.ok(Marked(1), "Concussion Blow marked")
			t.ok(not Marked(2), "Slam isn't")
			t.ok(TooltipLine(1), "tooltip line")
			t.equal(#toasts, 2, "two messages")
			t.ok(toasts[1].text:find("Concussion Blow", 1, true), "lost: " .. toasts[1].text)
			t.ok(toasts[2].text:find("Bloodthirst", 1, true), "new, not on your bars: " .. toasts[2].text)
		end)

		t.test("clicking the message asks first, then takes them off your bars, after combat if you're fighting", function()
			toasts[1].onClick()
			t.ok(popup and popup.text:find("Concussion Blow", 1, true), "asks, naming them")
			t.equal(#picked, 0, "nothing taken off yet")
			wow.data.inCombat = true
			popup.dialog.OnAccept()
			t.equal(#picked, 0, "not in combat")
			wow.data.inCombat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			t.equal(picked[1], 1, "taken off after combat")
			t.ok(actions[1] == nil and actions[2] == SLAM, "only the unlearned one")
			t.ok(not Marked(1), "no mark left")
		end)

		t.test("/nra unlearned lists them; the mark can be turned off", function()
			actions[3] = CONCUSSION_BLOW
			wow.printed = {}
			SlashCmdList.NRAKIT("unlearned")
			t.ok(wow.printed[#wow.printed]:find("Concussion Blow", 1, true), "listed")
			actions[1] = CONCUSSION_BLOW
			wow.fire("ACTIONBAR_SLOT_CHANGED", 1)
			t.ok(Marked(1), "marked")
			ns:SetSetting("unlearnedAbilitiesMark", false)
			t.ok(not Marked(1), "option off")
			t.noErrors()
		end)
	end,
}
