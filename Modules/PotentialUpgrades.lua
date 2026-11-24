local _, ns = ...

-- Potential Upgrades: marks items that are upgrades over what you have equipped,
-- in your bags, on quest rewards and in item tooltips.
--
-- Two levels of confidence:
--   clear  (green)  usable now, and at least as good on every stat that matters for
--                   your class (plus armor / weapon DPS), strictly better on one.
--                   Or the slot is empty. No weights involved.
--   likely (yellow) not better on everything, but scores higher using a simple
--                   per-class stat priority (1st > 2nd > 3rd).
-- Items you can't use yet only because of your level are marked grey ("later").
-- Common "Equip:" bonuses count like stats: attack power, spell power and healing, mana
-- per 5, and chance to hit or crit (a rough worth each, per class). It's a clue while
-- leveling, not a sim. Other effects (on use, procs, set bonuses) can't be judged:
-- an item with one is never called "clear".

local module = {
	key = "potentialUpgrades",
	section = "Bags & Items",
	name = "Potential Upgrades",
	description = "Marks items that are upgrades over what you have equipped: a green arrow for clear upgrades (better or equal on everything that matters for your class), yellow for likely upgrades (better by a simple per-class stat priority). Shown in bags, on quest rewards and in item tooltips.",
	default = false,
	options = {
		{
			key = "potentialUpgradesLikely",
			header = "What to mark",
			name = "Likely upgrades (yellow)",
			description = "Also mark items that aren't better on every stat, but come out ahead using your class's stat priority.",
			default = true,
		},
		{
			key = "potentialUpgradesLater",
			name = "Upgrades for a later level (grey)",
			description = "Mark items that would be an upgrade once you reach the required level.",
			default = true,
		},
		{
			key = "potentialUpgradesBags",
			header = "Where to show",
			name = "Bags",
			description = "Show arrows on items in your bags.",
			default = true,
		},
		{
			key = "potentialUpgradesQuests",
			name = "Quest rewards",
			description = "Show arrows on quest rewards.",
			default = true,
		},
		{
			key = "potentialUpgradesTooltip",
			name = "Item tooltips",
			description = "Add a line to item tooltips explaining the comparison, e.g. \"Clear upgrade (+3 Str, +12 Armor)\".",
			default = true,
		},
	},
}

---------------------------------------------------------------------------
-- Stats and class priorities
---------------------------------------------------------------------------

local STR = "ITEM_MOD_STRENGTH_SHORT"
local AGI = "ITEM_MOD_AGILITY_SHORT"
local STA = "ITEM_MOD_STAMINA_SHORT"
local INT = "ITEM_MOD_INTELLECT_SHORT"
local SPI = "ITEM_MOD_SPIRIT_SHORT"
local ARMOR = "RESISTANCE0_NAME"
local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
-- Equip bonuses, from the item's stats or its "Equip:" lines (our own names).
local AP, RAP, SP, HEAL, MP5 = "AP", "RAP", "SP", "HEAL", "MP5"
local HIT, CRIT, SPELL_HIT, SPELL_CRIT = "HIT", "CRIT", "SPELL_HIT", "SPELL_CRIT"

local STAT_LABELS = {
	[STR] = "Str", [AGI] = "Agi", [STA] = "Sta", [INT] = "Int", [SPI] = "Spi",
	[ARMOR] = "Armor", [DPS] = "DPS",
	[AP] = "AP", [RAP] = "Ranged AP", [SP] = "Spell Power", [HEAL] = "Healing", [MP5] = "MP5",
	[HIT] = "Hit", [CRIT] = "Crit", [SPELL_HIT] = "Spell Hit", [SPELL_CRIT] = "Spell Crit",
}
local PERCENT_STATS = { [HIT] = true, [CRIT] = true, [SPELL_HIT] = true, [SPELL_CRIT] = true }

-- Item stat keys for the same bonuses (the game's names vary a little), most specific first.
local STAT_KEYS = {
	{ "RANGED_ATTACK_POWER", RAP }, { "ATTACK_POWER", AP }, { "SPELL_HEALING", HEAL },
	{ "SPELL_DAMAGE", SP }, { "SPELL_POWER", SP }, { "MANA_REGENERATION", MP5 },
}

-- "Equip:" lines we understand, and what they give. Anything conditional ("when fighting
-- Undead", one school of magic) doesn't match and counts as a special effect.
local EQUIP_PATTERNS = {
	{ "^Equip: %+(%d+) ranged Attack Power%.?$", RAP },
	{ "^Equip: %+(%d+) Attack Power%.?$", AP },
	{ "^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.?$", SP },
	{ "^Equip: Increases healing done by spells and effects by up to (%d+)%.?$", HEAL },
	{ "^Equip: Restores (%d+) mana per 5 sec%.?$", MP5 },
	{ "^Equip: Improves your chance to hit with spells by (%d+)%%%.?$", SPELL_HIT },
	{ "^Equip: Improves your chance to get a critical strike with spells by (%d+)%%%.?$", SPELL_CRIT },
	{ "^Equip: Improves your chance to hit by (%d+)%%%.?$", HIT },
	{ "^Equip: Improves your chance to get a critical strike by (%d+)%%%.?$", CRIT },
}

-- Leveling priorities: 1st > 2nd > 3rd. Stats not listed don't count either way.
local CLASS_PRIORITIES = {
	WARRIOR = { STR, STA, AGI },
	PALADIN = { STR, STA, INT },
	ROGUE = { AGI, STA, STR },
	HUNTER = { AGI, STA, INT },
	SHAMAN = { STR, INT, STA },
	DRUID = { INT, STA, SPI },
	MAGE = { INT, STA, SPI },
	WARLOCK = { INT, STA, SPI },
	PRIEST = { INT, SPI, STA },
}
local PRIORITY_WEIGHTS = { 1.0, 0.6, 0.35 }

-- What equip bonuses are worth to each class, in points of its main stat: rough leveling
-- rules of thumb (2 attack power is about 1 Strength, 1% crit or hit about 10).
local BONUS_WEIGHTS = {
	WARRIOR = { [AP] = 0.5, [HIT] = 10, [CRIT] = 10 },
	PALADIN = { [AP] = 0.5, [HIT] = 8, [CRIT] = 8, [SP] = 0.3, [HEAL] = 0.2 },
	ROGUE = { [AP] = 0.5, [HIT] = 10, [CRIT] = 10 },
	HUNTER = { [RAP] = 0.5, [AP] = 0.15, [HIT] = 10, [CRIT] = 10 },
	SHAMAN = { [AP] = 0.5, [HIT] = 6, [CRIT] = 6, [SP] = 0.4, [HEAL] = 0.2, [MP5] = 1 },
	DRUID = { [SP] = 0.8, [HEAL] = 0.4, [MP5] = 1.5, [SPELL_HIT] = 6, [SPELL_CRIT] = 6 },
	MAGE = { [SP] = 1.0, [MP5] = 1, [SPELL_HIT] = 8, [SPELL_CRIT] = 8 },
	WARLOCK = { [SP] = 1.0, [MP5] = 1, [SPELL_HIT] = 8, [SPELL_CRIT] = 6 },
	PRIEST = { [SP] = 0.8, [HEAL] = 0.6, [MP5] = 2, [SPELL_CRIT] = 5 },
}

-- Weapon DPS matters for weapon users; casters only care about it on wands/ranged.
local MELEE_DPS_CLASSES = { WARRIOR = true, PALADIN = true, ROGUE = true, HUNTER = true, SHAMAN = true }
local DPS_WEIGHT = 3.0
local ARMOR_WEIGHT = 0.02
-- A likely upgrade has to beat the equipped item's score by this much.
local LIKELY_MARGIN = 0.05

---------------------------------------------------------------------------
-- Equipment slots
---------------------------------------------------------------------------

local SLOTS = {
	INVTYPE_HEAD = { INVSLOT_HEAD },
	INVTYPE_NECK = { INVSLOT_NECK },
	INVTYPE_SHOULDER = { INVSLOT_SHOULDER },
	INVTYPE_CHEST = { INVSLOT_CHEST },
	INVTYPE_ROBE = { INVSLOT_CHEST },
	INVTYPE_WAIST = { INVSLOT_WAIST },
	INVTYPE_LEGS = { INVSLOT_LEGS },
	INVTYPE_FEET = { INVSLOT_FEET },
	INVTYPE_WRIST = { INVSLOT_WRIST },
	INVTYPE_HAND = { INVSLOT_HAND },
	INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
	INVTYPE_CLOAK = { INVSLOT_BACK },
	INVTYPE_WEAPON = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONMAINHAND = { INVSLOT_MAINHAND },
	INVTYPE_2HWEAPON = { INVSLOT_MAINHAND },
	INVTYPE_WEAPONOFFHAND = { INVSLOT_OFFHAND },
	INVTYPE_SHIELD = { INVSLOT_OFFHAND },
	INVTYPE_HOLDABLE = { INVSLOT_OFFHAND },
	INVTYPE_RANGED = INVSLOT_RANGED and { INVSLOT_RANGED },
	INVTYPE_RANGEDRIGHT = INVSLOT_RANGED and { INVSLOT_RANGED },
	INVTYPE_THROWN = INVSLOT_RANGED and { INVSLOT_RANGED },
	-- Trinkets are almost all effects, which can't be judged; shirts/tabards have no stats.
}

local WEAPON_TYPES = {
	INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}
local RANGED_TYPES = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

---------------------------------------------------------------------------
-- Item analysis
---------------------------------------------------------------------------

local EFFECT_LINES = {}
local LEVEL_PATTERN
local playerClass

local function IsRed(color)
	return color and color.r and color.r > 0.9 and color.g < 0.3 and color.b < 0.3
end

-- The bonus an "Equip:" line gives (stat, amount), or nil if it's something else.
local function ParseEquipLine(text)
	if type(text) ~= "string" then
		return nil
	end
	for _, pattern in ipairs(EQUIP_PATTERNS) do
		local amount = text:match(pattern[1])
		if amount then
			return pattern[2], tonumber(amount)
		end
	end
	return nil
end

-- Reads the tooltip data: whether the player can use the item (red requirement
-- lines), whether only the level is in the way, whether it has special effects we
-- can't judge, and the bonuses from the "Equip:" lines we understand.
local function ReadTooltip(data)
	local blockedByOther, blockedByLevel, hasEffect = false, false, false
	local bonuses = {}
	for _, line in ipairs(data and data.lines or {}) do
		local stat, amount = ParseEquipLine(line.leftText)
		if stat then
			bonuses[stat] = (bonuses[stat] or 0) + amount
		elseif EFFECT_LINES[line.type] then
			hasEffect = true
		end
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			if LEVEL_PATTERN and line.leftText and line.leftText:match(LEVEL_PATTERN) then
				blockedByLevel = true
			else
				blockedByOther = true
			end
		end
	end
	return blockedByOther, blockedByLevel, hasEffect, bonuses
end

-- The item's stats, with equip bonuses under our names: from its stats or its "Equip:"
-- lines, whichever says more (the game may give both; nothing counts twice).
local function GetStats(link, tooltipData)
	if not link then
		return {}
	end
	local stats = {}
	for key, value in pairs(C_Item.GetItemStats(link) or {}) do
		local name = key
		for _, entry in ipairs(STAT_KEYS) do
			if key:find(entry[1], 1, true) then
				name = entry[2]
				break
			end
		end
		stats[name] = (stats[name] or 0) + value
	end
	local _, _, _, bonuses = ReadTooltip(tooltipData or C_TooltipInfo.GetHyperlink(link))
	for stat, amount in pairs(bonuses) do
		stats[stat] = math.max(stats[stat] or 0, amount)
	end
	return stats
end

-- The metrics compared for this item type, with their weights.
local function GetMetrics(equipLoc)
	local metrics = {}
	for i, stat in ipairs(CLASS_PRIORITIES[playerClass] or {}) do
		metrics[stat] = PRIORITY_WEIGHTS[i] or 0
	end
	for stat, weight in pairs(BONUS_WEIGHTS[playerClass] or {}) do
		metrics[stat] = weight
	end
	if WEAPON_TYPES[equipLoc] then
		if MELEE_DPS_CLASSES[playerClass] or RANGED_TYPES[equipLoc] then
			metrics[DPS] = DPS_WEIGHT
		end
	else
		metrics[ARMOR] = ARMOR_WEIGHT
	end
	return metrics
end

local function Score(stats, metrics)
	local score = 0
	for stat, weight in pairs(metrics) do
		score = score + (stats[stat] or 0) * weight
	end
	return score
end

local function SumStats(a, b)
	local sum = {}
	for stat, value in pairs(a) do
		sum[stat] = value
	end
	for stat, value in pairs(b) do
		sum[stat] = (sum[stat] or 0) + value
	end
	return sum
end

-- The equipped stats this item would replace, or nil if the comparison isn't meaningful.
-- Returns stats, isEmptySlot, equippedHasEffect.
local function GetEquippedStats(equipLoc, slots, metrics)
	local mainHand = GetInventoryItemLink("player", INVSLOT_MAINHAND)
	local mainHandLoc = mainHand and select(9, C_Item.GetItemInfo(mainHand))

	if equipLoc == "INVTYPE_2HWEAPON" then
		-- A two-hander replaces both hands.
		local offHand = GetInventoryItemLink("player", INVSLOT_OFFHAND)
		if not mainHand and not offHand then
			return nil, true
		end
		return SumStats(GetStats(mainHand), GetStats(offHand)), false
	end
	if slots[1] == INVSLOT_MAINHAND and mainHandLoc == "INVTYPE_2HWEAPON" then
		return nil -- one-hander vs two-hander: not comparable on its own
	end
	if slots[1] == INVSLOT_OFFHAND and mainHandLoc == "INVTYPE_2HWEAPON" then
		return nil
	end

	-- For two-slot items (rings), compare against the weaker one.
	local weakest, weakestScore
	for _, slot in ipairs(slots) do
		local link = GetInventoryItemLink("player", slot)
		if not link then
			return nil, true
		end
		local stats = GetStats(link)
		local score = Score(stats, metrics)
		if not weakestScore or score < weakestScore then
			weakest, weakestScore = stats, score
		end
	end
	return weakest, false
end

local cache = {}

-- Returns result ("clear", "likely", "later" or nil) and a short delta description.
-- tooltipData is optional (bag items pass theirs so the exact item state is used).
local function Evaluate(link, tooltipData)
	if not link then
		return nil
	end
	if cache[link] ~= nil then
		return cache[link].result, cache[link].delta
	end

	local _, _, _, _, minLevel, _, _, _, equipLoc = C_Item.GetItemInfo(link)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots then
		if equipLoc then
			cache[link] = {}
		end
		return nil
	end

	-- An item you're already wearing isn't an upgrade (matters for rings vs the other ring).
	for _, slot in ipairs(slots) do
		if GetInventoryItemLink("player", slot) == link then
			cache[link] = {}
			return nil
		end
	end

	tooltipData = tooltipData or C_TooltipInfo.GetHyperlink(link)
	local blockedByOther, blockedByLevel, hasEffect = ReadTooltip(tooltipData)
	if blockedByOther then
		cache[link] = {}
		return nil
	end

	local metrics = GetMetrics(equipLoc)
	local newStats = GetStats(link, tooltipData)
	local oldStats, emptySlot = GetEquippedStats(equipLoc, slots, metrics)

	local result, delta
	if emptySlot then
		result, delta = "clear", "empty slot"
	elseif oldStats then
		local better, worse = false, false
		local parts = {}
		for stat in pairs(metrics) do
			local diff = (newStats[stat] or 0) - (oldStats[stat] or 0)
			if diff > 0 then
				better = true
			elseif diff < 0 then
				worse = true
			end
			if diff ~= 0 then
				local amount = stat == DPS and string.format("%.1f", math.abs(diff)) or tostring(math.floor(math.abs(diff) + 0.5))
				if PERCENT_STATS[stat] then
					amount = amount .. "%"
				end
				table.insert(parts, (diff > 0 and "+" or "-") .. amount .. " " .. STAT_LABELS[stat])
			end
		end
		table.sort(parts)
		delta = table.concat(parts, ", ")

		if better and not worse and not hasEffect then
			result = "clear"
		elseif better then
			local newScore, oldScore = Score(newStats, metrics), Score(oldStats, metrics)
			if newScore > oldScore * (1 + LIKELY_MARGIN) and newScore - oldScore > 0.1 then
				result = "likely"
			end
		end
		if hasEffect and result then
			delta = delta .. (delta ~= "" and ", " or "") .. "has special effect"
		end
	end

	if result and blockedByLevel then
		result = "later"
		delta = string.format("at level %d", minLevel or 0) .. (delta and delta ~= "" and ", " .. delta or "")
	end
	cache[link] = { result = result, delta = delta }
	return result, delta
end

local function IsShown(result)
	if result == "clear" then
		return true
	elseif result == "likely" then
		return ns:GetOption("potentialUpgradesLikely")
	elseif result == "later" then
		return ns:GetOption("potentialUpgradesLater")
	end
	return false
end

local RESULT_COLORS = {
	clear = { 0.2, 1, 0.2 },
	likely = { 1, 0.85, 0.1 },
	later = { 0.6, 0.6, 0.6 },
}
local RESULT_LABELS = {
	clear = "Clear upgrade",
	likely = "Likely upgrade",
	later = "Upgrade later",
}

---------------------------------------------------------------------------
-- Arrows
---------------------------------------------------------------------------

local ARROW_ATLAS = "bags-greenarrow" -- Blizzard's own bag upgrade arrow
local arrows = {}

local function GetArrow(button, anchor)
	local arrow = arrows[button]
	if not arrow then
		-- Own frame above the button's children; never takes the mouse.
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints(button)
		holder:SetFrameLevel(button:GetFrameLevel() + 6)
		arrow = holder:CreateTexture(nil, "OVERLAY")
		arrow:SetAtlas(ARROW_ATLAS, true)
		arrow:SetPoint("TOPLEFT", anchor or button, "TOPLEFT", -2, 2)
		arrows[button] = arrow
	end
	return arrow
end

local function SetArrow(button, result, anchor)
	if not IsShown(result) then
		if arrows[button] then
			arrows[button]:Hide()
		end
		return
	end
	local arrow = GetArrow(button, anchor)
	-- Green stays as drawn; other levels are desaturated and recolored.
	if result == "clear" then
		arrow:SetDesaturated(false)
		arrow:SetVertexColor(1, 1, 1)
	else
		arrow:SetDesaturated(true)
		arrow:SetVertexColor(unpack(RESULT_COLORS[result]))
	end
	arrow:Show()
end

local function HideAllArrows()
	for _, arrow in pairs(arrows) do
		arrow:Hide()
	end
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

local function UpdateBags()
	ns:ForEachBagItemButton(function(itemButton)
		local result
		if ns:IsModuleEnabled(module.key) and ns:GetOption("potentialUpgradesBags") then
			local bag, slot = itemButton:GetBagID(), itemButton:GetID()
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link then
				result = Evaluate(link, C_TooltipInfo.GetBagItem(bag, slot))
			end
		end
		SetArrow(itemButton, result, itemButton.icon or itemButton.Icon)
	end)
end

---------------------------------------------------------------------------
-- Quest rewards
---------------------------------------------------------------------------

local function UpdateQuestRewards()
	local rewardsFrame = QuestInfoFrame.rewardsFrame
	if not rewardsFrame or not rewardsFrame.RewardButtons then
		return
	end
	local enabled = ns:IsModuleEnabled(module.key) and ns:GetOption("potentialUpgradesQuests")
	for _, button in ipairs(rewardsFrame.RewardButtons) do
		local result
		if enabled and button:IsShown() and button.objectType == "item" then
			local link
			if QuestInfoFrame.questLog then
				link = GetQuestLogItemLink(button.type, button:GetID())
			else
				link = GetQuestItemLink(button.type, button:GetID())
			end
			result = Evaluate(link)
		end
		SetArrow(button, result, button.Icon)
	end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("potentialUpgradesTooltip") then
		return
	end
	-- Only the main item tooltips; comparison tooltips show what you already wear.
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	local result, delta = Evaluate(link)
	if IsShown(result) then
		local text = RESULT_LABELS[result] .. (delta and delta ~= "" and (" (" .. delta .. ")") or "")
		local r, g, b = unpack(RESULT_COLORS[result])
		tooltip:AddLine("NraKit: " .. text, r, g, b, true)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local refreshQueued = false
local function Refresh()
	refreshQueued = false
	UpdateBags()
	UpdateQuestRewards()
end

local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, Refresh)
	end
end

local function InvalidateAndRefresh()
	wipe(cache)
	QueueRefresh()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "BAG_UPDATE_DELAYED" then
		QueueRefresh()
	else
		-- Equipment, level or newly loaded item data changes the comparisons.
		InvalidateAndRefresh()
	end
end)

local EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }

function module:OnInitialize()
	playerClass = select(2, UnitClass("player"))
	if ITEM_MIN_LEVEL then
		-- "Requires Level %d" -> pattern matching that line in any locale: escape
		-- pattern characters, then turn the %d placeholder into a number match.
		local escaped = ITEM_MIN_LEVEL:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		LEVEL_PATTERN = "^" .. escaped:gsub("%%d", "%%d+") .. "$"
	end
	local lineTypes = Enum.TooltipDataLineType
	for _, name in ipairs({ "ItemSpellTriggerOnUse", "ItemSpellTriggerOnEquip", "ItemSpellTriggerOnProc" }) do
		if lineTypes[name] then
			EFFECT_LINES[lineTypes[name]] = true
		end
	end

	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		if frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", QueueRefresh)
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
		hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", QueueRefresh)
	end
	hooksecurefunc("QuestInfo_Display", UpdateQuestRewards)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)

	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		InvalidateAndRefresh()
	else
		HideAllArrows()
	end
end

function module:OnOptionChanged()
	QueueRefresh()
end

ns:RegisterModule(module)
