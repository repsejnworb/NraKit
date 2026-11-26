-- Potential upgrades: rings compared for a warrior, with "Equip:" bonuses (attack power,
-- spell power, crit and hit rating) counted like stats, as a rough clue.

INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_MAINHAND, INVSLOT_OFFHAND = 11, 12, 16, 17
local EQUIP_LINE = 45
Enum.TooltipDataLineType = { ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = EQUIP_LINE, ItemSpellTriggerOnProc = 46 }

-- Items by link: stats (the game's keys, as Forever gives them) and their "Equip:" lines.
local items = {}
local equipped = {}
local function Item(link, stats, ...)
	local lines = {}
	for _, text in ipairs({ ... }) do
		table.insert(lines, { leftText = text, type = EQUIP_LINE })
	end
	items[link] = { stats = stats, lines = lines }
	return link
end

return {
	enable = { "potentialUpgrades" },
	run = function(t, ns, wow)
		C_Item.GetItemInfo = function(link)
			if items[link] then
				return link, link, 2, 30, 1, "Armor", "Miscellaneous", 1, "INVTYPE_FINGER"
			end
		end
		C_Item.GetItemStats = function(link)
			return items[link] and items[link].stats or {}
		end
		C_TooltipInfo.GetHyperlink = function(link)
			return { lines = items[link] and items[link].lines or {} }
		end
		GetInventoryItemLink = function(_, slot)
			return equipped[slot]
		end
		-- 14 crit rating is 1% (as Forever showed at level 30).
		GetCombatRatingBonusForCombatRatingValue = function(_, rating)
			return rating / 14
		end
		TooltipUtil.GetDisplayedItem = function(tooltip)
			return nil, tooltip.link
		end
		-- The NraKit line on an item's tooltip, or nil.
		local function Verdict(link)
			wow.fire("PLAYER_EQUIPMENT_CHANGED")
			local found
			rawset(GameTooltip, "link", link)
			rawset(GameTooltip, "AddLine", function(_, text)
				if text:find("^NraKit: ") then
					found = text
				end
			end)
			for _, call in ipairs(wow.tooltipCalls) do
				call.callback(GameTooltip, {})
			end
			return found
		end

		local seal = Item("Seal of Wrynn", { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_AGILITY_SHORT = 3,
			ITEM_MOD_STAMINA_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 3 })
		local root = Item("Malignant Root", { ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_ATTACK_POWER_SHORT = 8,
			ITEM_MOD_SPELL_POWER_SHORT = 4 }, "Equip: +8 Attack Power.",
			"Equip: Increases damage and healing done by magical spells and effects by up to 4.")
		local ruin = Item("Ring of Ruin", { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_AGILITY_SHORT = 6 })
		local band = Item("Band of Might", { ITEM_MOD_STRENGTH_SHORT = 12 })

		-- Regression: attack power on the worn ring was ignored, so Ring of Ruin looked better.
		t.test("attack power on a worn ring counts", function()
			equipped = { [INVSLOT_FINGER1] = band, [INVSLOT_FINGER2] = root }
			t.equal(Verdict(ruin), nil, "+4 Str +6 Agi isn't better than +7 Sta and +8 AP")
			equipped = { [INVSLOT_FINGER1] = seal, [INVSLOT_FINGER2] = root }
			t.equal(Verdict(ruin), nil, "nor than the Seal")
		end)

		t.test("attack power on a new ring counts, and shows in the line", function()
			equipped = { [INVSLOT_FINGER1] = band, [INVSLOT_FINGER2] = root }
			local power = Item("Ring of Power", { ITEM_MOD_ATTACK_POWER_SHORT = 20 }, "Equip: +20 Attack Power.")
			local verdict = Verdict(power)
			t.ok(verdict and verdict:find("Likely upgrade", 1, true), tostring(verdict))
			t.ok(verdict:find("+12 AP", 1, true) and verdict:find("-7 Sta", 1, true), "the difference")
			t.ok(not verdict:find("special effect", 1, true), "an understood bonus isn't a special effect")
		end)

		t.test("crit rating counts, as % at your level", function()
			equipped = { [INVSLOT_FINGER1] = band, [INVSLOT_FINGER2] = Item("Small Ring", { ITEM_MOD_STRENGTH_SHORT = 3 }) }
			local verdict = Verdict(Item("Keen Ring", { ITEM_MOD_CRIT_RATING_SHORT = 7 },
				"Equip: Improves your chance to get a critical strike by 0.5%."))
			t.ok(verdict and verdict:find("+0.5% Crit", 1, true), tostring(verdict))
			t.ok(not verdict:find("special effect", 1, true), "a stat's Equip line isn't a special effect")
		end)

		t.test("other effects can't be judged", function()
			equipped = { [INVSLOT_FINGER1] = band, [INVSLOT_FINGER2] = Item("Tiny Ring", { ITEM_MOD_STRENGTH_SHORT = 1 }) }
			local verdict = Verdict(Item("Undead Bane", { ITEM_MOD_STRENGTH_SHORT = 2 }, "Equip: +30 Attack Power when fighting Undead."))
			t.ok(verdict and verdict:find("has special effect", 1, true), tostring(verdict))
			t.ok(not verdict:find("Clear", 1, true), "never clear")
			t.noErrors()
		end)
	end,
}
