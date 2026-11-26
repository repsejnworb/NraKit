local _, ns = ...

-- Farm Goals: "loot 4000 Silk Cloth", "reach level 40", "gain 50,000 XP", "have 100g",
-- "reach Revered with Timbermaw Hold", "Swords to 300", "2,000 of a currency".
--
-- Goals count what you gain after making them: items you loot (from the loot chat
-- line, so banking, mailing, trading or selling never changes a goal), XP gained and
-- money gained. An item or gold goal can start from what you already have (bags, bank,
-- mail, other characters); that starting count is fixed when the goal is made.
--
-- A movable tracker shows each goal's progress, rate per hour and time left (based on
-- the time the goal has been running while you're online). Milestones (25/50/75%) chime,
-- and finishing one plays a fanfare and shows a message in the middle of the screen.
-- Item goals also show what they're worth (an option): at the auction house with Auctionator
-- (the same prices as the Sell List), else at a vendor, and gold per hour.
-- The Goals window (FarmGoalsWindow.lua) adds goals and shows the history.
--
-- Saved per character in NraKitDB.farmGoalsData["Name-Realm"] (not "farmGoals": that's the
-- module's on/off setting) = { goals = {...}, history = {...} }:
--   goal = { id, type = "item"|"level"|"xp"|"gold"|"rep"|"skill"|"currency", target, itemID,
--            key (factionID/skillID/currencyID), mode ("reach"|"gain"), toMax, name, start,
--            gained, last, startLevel, created, active (seconds), paused, completed, milestone }

local module = {
	key = "farmGoals",
	section = "Trackers & Reminders",
	name = "Farm Goals",
	description = "Set farming goals (loot 4000 Silk Cloth, reach level 40, earn 100 gold, reach Revered, Swords to 300, a currency) and track them in a small movable window with rate per hour, time left and a fanfare when done. /nra goal opens the goals window.",
	default = false,
	options = {
		{
			key = "farmGoalsMilestoneSound",
			header = "Sounds",
			name = "Milestone chimes",
			description = "Play a sound at 25%, 50% and 75% of a goal. A goal can have its own sound (Edit in the goals window).",
			default = false,
		},
		{
			key = "farmGoalsMilestoneSoundChoice",
			parent = "farmGoalsMilestoneSound",
			type = "sound",
			name = "Sound",
			description = "Which sound plays at milestones.",
			default = "kit:UI_QUEST_ROLLING_FORWARD_01",
		},
		{
			key = "farmGoalsCompleteSound",
			name = "Fanfare when a goal is done",
			description = "Play a sound when you finish a goal. A goal can have its own sound (Edit in the goals window).",
			default = true,
		},
		{
			key = "farmGoalsCompleteSoundChoice",
			parent = "farmGoalsCompleteSound",
			type = "sound",
			name = "Sound",
			description = "Which sound plays when a goal is done.",
			default = "kit:UI_WORLDQUEST_COMPLETE",
		},
		{
			key = "farmGoalsTickSound",
			name = "Sound on every gain",
			description = "Play a sound whenever a goal goes up. Gets busy when farming fast.",
			default = false,
		},
		{
			key = "farmGoalsTickSoundChoice",
			parent = "farmGoalsTickSound",
			type = "sound",
			name = "Sound",
			description = "Which sound plays on every gain.",
			default = "kit:LOOT_WINDOW_COIN_SOUND",
		},
		{
			key = "farmGoalsMilestoneMessage",
			header = "Messages",
			name = "Milestone message",
			description = "Show a small message (\"Silk Cloth · 50%\") at 25%, 50% and 75% of a goal.",
			default = false,
		},
		{
			key = "farmGoalsToastSize",
			type = "number",
			name = "Finish message size",
			description = "Size of the \"Goal complete\" message in the middle of the screen.",
			default = 100, min = 60, max = 200, step = 10, format = "%d%%",
		},
		{
			key = "farmGoalsToastDuration",
			type = "number",
			name = "Finish message time",
			description = "How long the message stays before it fades (longer while the mouse is on it). A goal finished in combat is shown again when the fight ends.",
			default = 6, min = 2, max = 15, step = 1, format = "%d s",
		},
		{
			key = "farmGoalsCountCrafted",
			header = "Counting",
			name = "Count crafted items",
			description = "Items you make (\"You create: ...\") count towards item goals, not just looted ones.",
			default = false,
		},
		{
			key = "farmGoalsValue",
			name = "Show what item goals are worth",
			description = "Item goals show what you've farmed is worth and gold per hour (\"18/h · ~38g/h\"), and the finished message what the goal is worth: at the auction house (with Auctionator), else at a vendor. The tooltip has the price of one and how old it is.",
			default = true,
		},
		{
			key = "farmGoalsAutoClear",
			name = "Clear finished goals",
			description = "Move a finished goal to the history a few seconds after it's done, instead of keeping it in the tracker until you clear it.",
			default = false,
		},
		{
			key = "farmGoalsHideInCombat",
			header = "Tracker",
			name = "Hide in combat",
			description = "Hide the tracker while you're in combat.",
			default = false,
		},
		{
			key = "farmGoalsLocked",
			name = "Lock position",
			description = "Stop the tracker from being dragged.",
			default = false,
		},
		{
			key = "farmGoalsWidth",
			type = "number",
			name = "Width (Full view)",
			description = "Width of the tracker in the Full view. Switch views with the tracker's view menu (the arrow in its header).",
			default = 260, min = 180, max = 420, step = 10,
		},
		{
			key = "farmGoalsCompactWidth",
			type = "number",
			name = "Width (Compact view)",
			description = "Width of the tracker in the Compact view (one line per goal).",
			default = 210, min = 150, max = 400, step = 10,
		},
		{
			key = "farmGoalsIconSize",
			type = "number",
			name = "Icon size (Icons view)",
			description = "Size of each goal's icon in the Icons view.",
			default = 32, min = 20, max = 56, step = 2,
		},
		{
			key = "farmGoalsIconsPerRow",
			type = "number",
			name = "Icons per row",
			description = "How many goals side by side in the Icons view before it starts a new row.",
			default = 3, min = 1, max = 12, step = 1,
		},
		{
			key = "farmGoalsScale",
			type = "number",
			name = "Scale",
			description = "Size of the tracker.",
			default = 100, min = 60, max = 160, step = 5, format = "%d%%",
		},
	},
}

local UI = ns.UI
local ROW_HEIGHT = 50
local HEADER_HEIGHT = 22
local MAX_ROWS = 5
local DONE_COLOR = { 0.3, 0.85, 0.3 }
local PAUSED_COLOR = { 0.5, 0.5, 0.5 }

local ICON_PATH = "Interface\\Icons\\"
local ICONS = {
	xp = ICON_PATH .. "XP_Icon", -- the "XP" icon Blizzard uses for XP rewards
	rep = ICON_PATH .. "Achievement_Reputation_01",
	skill = ICON_PATH .. "Ability_Warrior_WeaponMastery",
	currency = ICON_PATH .. "INV_Misc_Token_ArgentDawn",
}

-- Skill line ID -> icon: weapon skills show the weapon, professions their tool. Others
-- get ICONS.skill.
local SKILL_ICONS = {
	[44] = "INV_Axe_01", [172] = "INV_Axe_04", -- Axes, Two-Handed Axes
	[43] = "INV_Sword_04", [55] = "INV_Sword_06", -- Swords, Two-Handed Swords
	[54] = "INV_Mace_01", [160] = "INV_Hammer_04", -- Maces, Two-Handed Maces
	[173] = "INV_Weapon_ShortBlade_01", [136] = "INV_Staff_08", [229] = "INV_Spear_06", -- Daggers, Staves, Polearms
	[45] = "INV_Weapon_Bow_05", [46] = "INV_Weapon_Rifle_01", [226] = "INV_Weapon_Crossbow_01", -- Bows, Guns, Crossbows
	[176] = "INV_ThrowingKnife_02", [228] = "INV_Wand_01", [473] = "INV_Gauntlets_04", -- Thrown, Wands, Fist Weapons
	[95] = "Ability_Defend", -- Defense
	[186] = "Trade_Mining", [182] = "Trade_Herbalism", [393] = "INV_Misc_Pelt_Wolf_01",
	[164] = "Trade_BlackSmithing", [165] = "Trade_LeatherWorking", [171] = "Trade_Alchemy",
	[197] = "Trade_Tailoring", [202] = "Trade_Engineering", [333] = "Trade_Engraving", -- Enchanting
	[185] = "INV_Misc_Food_15", [129] = "Spell_Holy_SealOfSacrifice", [356] = "Trade_Fishing", -- Cooking, First Aid, Fishing
	[633] = "INV_Misc_Key_03", [762] = "Ability_Mount_RidingHorse", -- Lockpicking, Riding
}

-- Faction ID -> icon, for the few with an obvious one. Others get ICONS.rep.
local FACTION_ICONS = {
	[576] = "Achievement_Reputation_Timbermaw", -- Timbermaw Hold
	[529] = "INV_Misc_Token_ArgentDawn", -- Argent Dawn
}

-- Level 10 to 60 achievement icons, by the target's tens.
local function LevelIcon(target)
	return ICON_PATH .. "Achievement_Level_" .. math.max(1, math.min(6, math.floor((target or 10) / 10))) * 10
end

-- Silver coins under 1g, gold coins, and a pile of gold from 100g.
local function GoldIcon(copper)
	copper = copper or 0
	if copper < 10000 then
		return ICON_PATH .. "INV_Misc_Coin_03"
	end
	return ICON_PATH .. (copper < 1000000 and "INV_Misc_Coin_01" or "INV_Misc_Coin_02")
end

-- Goal sounds: which -> { on/off option, sound option, default sound }.
local SOUNDS = {
	milestone = { "farmGoalsMilestoneSound", "farmGoalsMilestoneSoundChoice", "kit:UI_QUEST_ROLLING_FORWARD_01" },
	complete = { "farmGoalsCompleteSound", "farmGoalsCompleteSoundChoice", "kit:UI_WORLDQUEST_COMPLETE" },
	tick = { "farmGoalsTickSound", "farmGoalsTickSoundChoice", "kit:LOOT_WINDOW_COIN_SOUND" },
}

local characterKey
local lastXP, lastXPMax, lastLevel, lastMoney
local tracker
local nextID = 0

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function GetData()
	NraKitDB.farmGoalsData = NraKitDB.farmGoalsData or {}
	local data = NraKitDB.farmGoalsData[characterKey]
	if not data then
		data = { goals = {}, history = {} }
		NraKitDB.farmGoalsData[characterKey] = data
	end
	return data
end

-- A goal's own sound wins ("none" silences it); "default" (or no choice) follows the settings.
local function PlayGoalSound(goal, which)
	local own = goal and goal.sounds and goal.sounds[which]
	if own and own ~= "default" and ns.sounds.IsValid(own) then
		ns.sounds.Play(own)
		return
	end
	local toggle, choice, default = unpack(SOUNDS[which])
	if ns:GetOption(toggle) then
		ns.sounds.PlayOption(choice, default)
	end
end

-- "Default (Epic loot)" / "Default (off)", for the per-goal sound pickers.
local function DefaultSoundLabel(which)
	local toggle, choice, default = unpack(SOUNDS[which])
	if not ns:GetOption(toggle) then
		return "Default (off)"
	end
	local value = ns:GetValue(choice)
	return "Default (" .. ns.sounds.Label(ns.sounds.IsValid(value) and value or default) .. ")"
end

local function DefaultSound(which)
	local toggle, choice, default = unpack(SOUNDS[which])
	if not ns:GetOption(toggle) then
		return "none"
	end
	local value = ns:GetValue(choice)
	return ns.sounds.IsValid(value) and value or default
end

local function FormatNumber(value)
	value = math.floor(value + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- Compact, no icons, the two largest units: "12g 30s", "45s 20c", "7c", "0c".
local function FormatGold(copper)
	copper = math.max(math.floor(copper), 0)
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if gold > 0 then
		return silver > 0 and string.format("%sg %ds", FormatNumber(gold), silver) or FormatNumber(gold) .. "g"
	elseif silver > 0 then
		return rest > 0 and string.format("%ds %dc", silver, rest) or silver .. "s"
	end
	return rest .. "c"
end

-- A worth, rounded (it's an estimate): to the gold, or to the silver under 1g.
local function Rounded(copper)
	if copper >= 10000 then
		return math.floor(copper / 10000 + 0.5) * 10000
	end
	return math.max(math.floor(copper / 100 + 0.5), 1) * 100
end

-- "68g", "4s" in gold: for the tracker's lines. (No "~": the game font draws it as a squiggle.)
local function RoughMoney(copper)
	return "|cffffd100" .. FormatGold(Rounded(copper)) .. "|r"
end

-- The same with the game's coin icons: for tooltips and messages.
local function RoughCoins(copper)
	return GetMoneyString and GetMoneyString(Rounded(copper), true) or FormatGold(Rounded(copper))
end

-- What one of an item goal's items is worth: the auction house price (Auctionator, as the Sell
-- List reads it), else the vendor's; and where ("ah" / "vendor"), and the price's age in days.
-- nil with the option off, or nothing known.
local function ItemWorth(goal)
	if goal.type ~= "item" or not goal.itemID or not ns:GetOption("farmGoalsValue") then
		return nil
	end
	local auction, age
	if ns.sellList and ns.sellList.AuctionPrice then
		auction, age = ns.sellList.AuctionPrice(goal.itemID)
	end
	if auction and auction > 0 then
		return auction, "ah", age
	end
	local vendor = select(11, C_Item.GetItemInfo(goal.itemID))
	if vendor and vendor > 0 then
		return vendor, "vendor"
	end
end

-- "100" (gold), "100g", "50s", "1g 50s", "1g50s20c", "75c", "1,234g" -> copper, or nil.
local MONEY_UNITS = { g = 10000, s = 100, c = 1 }
local function ParseMoney(text)
	text = (text or ""):lower():gsub("[%s,]", "")
	if text:match("^%d+$") then
		return tonumber(text) * 10000
	end
	if text == "" or text:gsub("%d+[gsc]", "") ~= "" then
		return nil
	end
	local copper = 0
	for amount, unit in text:gmatch("(%d+)([gsc])") do
		copper = copper + tonumber(amount) * MONEY_UNITS[unit]
	end
	return copper > 0 and copper or nil
end

local function FormatDuration(seconds)
	seconds = math.floor(seconds)
	if seconds < 60 then
		return "<1m"
	end
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return minutes .. "m"
end

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

-- Total reputation at the start of each standing (1 = Hated ... 8 = Exalted).
local REP_THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }

local function StandingLabel(reaction)
	return _G["FACTION_STANDING_LABEL" .. reaction] or ("Standing " .. reaction)
end

-- Progress of a "gain N" goal: just what was gained since it was made.
local function GainProgress(goal, format)
	local gained = goal.gained or 0
	return gained / goal.target, "+" .. format(gained) .. " / " .. format(goal.target), goal.target - gained
end

-- Progress of a "reach N" goal from its starting value.
local function ReachFraction(current, start, target)
	if current >= target then
		return 1
	end
	return math.max(0, (current - start) / math.max(target - start, 1))
end

-- Goal types. Each has describe(goal) -> name, icon and progress(goal) -> fraction,
-- value text, amount still to go (in the units the rate counts). format() formats those
-- units. Types with read(goal) are re-read when their event fires, and increases are
-- added to goal.gained (rep, skill, currency); goals with mode "gain" count only that.
local TYPES = {}

TYPES.item = {
	format = FormatNumber,
	gainedSuffix = " looted",
	describe = function(goal)
		return ItemName(goal.itemID), select(5, C_Item.GetItemInfoInstant(goal.itemID)) or 134400
	end,
	progress = function(goal)
		local current = (goal.start or 0) + (goal.gained or 0)
		return current / goal.target, FormatNumber(current) .. " / " .. FormatNumber(goal.target), goal.target - current
	end,
}

TYPES.gold = {
	format = FormatGold,
	describe = function(goal)
		return "Have " .. FormatGold(goal.target), GoldIcon(goal.target)
	end,
	progress = function(goal)
		local current = (goal.start or 0) + (goal.gained or 0)
		return current / goal.target, FormatGold(current) .. " / " .. FormatGold(goal.target), goal.target - current
	end,
}

TYPES.xp = {
	format = FormatNumber,
	describe = function(goal)
		return "Gain " .. FormatNumber(goal.target) .. " XP", ICONS.xp
	end,
	progress = function(goal)
		return GainProgress(goal, FormatNumber)
	end,
}

TYPES.level = {
	format = FormatNumber,
	describe = function(goal)
		return "Reach level " .. goal.target, LevelIcon(goal.target)
	end,
	progress = function(goal)
		local level, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
		local now = level + (max > 0 and xp / max or 0)
		local start = goal.startLevel or level
		local fraction = level >= goal.target and 1 or ReachFraction(now, start, goal.target)
		local remaining = math.max(0, (max - xp) + (goal.target - level - 1) * max)
		return fraction, string.format("Level %d (%d%%) / %d", level, math.floor(max > 0 and xp / max * 100 or 0), goal.target), remaining
	end,
}

TYPES.rep = {
	format = FormatNumber,
	event = "UPDATE_FACTION",
	read = function(goal)
		local data = C_Reputation.GetFactionDataByID(goal.key)
		return data and data.currentStanding
	end,
	describe = function(goal)
		local data = C_Reputation.GetFactionDataByID(goal.key)
		local name = data and data.name or goal.name or "Reputation"
		if goal.mode == "gain" then
			name = name .. " +" .. FormatNumber(goal.target)
		end
		local icon = FACTION_ICONS[goal.key]
		return name, icon and (ICON_PATH .. icon) or ICONS.rep
	end,
	progress = function(goal)
		if goal.mode == "gain" then
			return GainProgress(goal, FormatNumber)
		end
		local data = C_Reputation.GetFactionDataByID(goal.key)
		if not data then
			return 0, "?", 0
		end
		local target = REP_THRESHOLDS[goal.target] or 0
		local current = data.currentStanding
		local span = data.nextReactionThreshold - data.currentReactionThreshold
		local text = StandingLabel(data.reaction)
		if current < target and span > 0 then
			text = string.format("%s %s/%s  to %s", text, FormatNumber(current - data.currentReactionThreshold),
				FormatNumber(span), StandingLabel(goal.target))
		end
		return ReachFraction(current, goal.start or current, target), text, target - current
	end,
}

TYPES.skill = {
	format = FormatNumber,
	event = "SKILL_LINES_CHANGED",
	read = function(goal)
		local info = C_SkillInfo.GetSkillLineInfoByID(goal.key)
		return info and info.rank
	end,
	describe = function(goal)
		local info = C_SkillInfo.GetSkillLineInfoByID(goal.key)
		local name = info and info.name or goal.name or "Skill"
		if goal.mode == "gain" then
			name = name .. " +" .. goal.target
		end
		local icon = SKILL_ICONS[goal.key]
		return name, icon and (ICON_PATH .. icon) or ICONS.skill
	end,
	progress = function(goal)
		if goal.mode == "gain" then
			return GainProgress(goal, FormatNumber)
		end
		local info = C_SkillInfo.GetSkillLineInfoByID(goal.key)
		if not info then
			return 0, "?", 0
		end
		-- "To max" follows the skill's cap as it rises.
		local target = goal.toMax and info.maxRank or goal.target
		return ReachFraction(info.rank, goal.start or info.rank, target), info.rank .. " / " .. target, target - info.rank
	end,
}

TYPES.currency = {
	format = FormatNumber,
	event = "CURRENCY_DISPLAY_UPDATE",
	read = function(goal)
		local info = C_CurrencyInfo.GetCurrencyInfo(goal.key)
		return info and info.quantity
	end,
	describe = function(goal)
		local info = C_CurrencyInfo.GetCurrencyInfo(goal.key)
		local name = info and info.name or goal.name or "Currency"
		if goal.mode == "gain" then
			name = name .. " +" .. FormatNumber(goal.target)
		end
		return name, info and info.iconFileID or ICONS.currency
	end,
	progress = function(goal)
		if goal.mode == "gain" then
			return GainProgress(goal, FormatNumber)
		end
		local info = C_CurrencyInfo.GetCurrencyInfo(goal.key)
		local current = info and info.quantity or 0
		return ReachFraction(current, goal.start or current, goal.target),
			FormatNumber(current) .. " / " .. FormatNumber(goal.target), goal.target - current
	end,
}

-- The icon a goal gets unless you pick one (goal.icon). Works on a half-filled goal too
-- (the goals window's form shows it before an item or faction is picked).
local function AutoIcon(goal)
	if goal.type == "item" and not goal.itemID then
		return 134400 -- question mark
	elseif goal.type == "level" then
		return LevelIcon(goal.target)
	elseif goal.type == "gold" then
		return GoldIcon(goal.target)
	elseif ICONS[goal.type] and not goal.key then
		return ICONS[goal.type] -- xp, or nothing picked yet
	end
	return select(2, TYPES[goal.type].describe(goal))
end

-- Name and icon of a goal, for the tracker, window and messages. A chosen icon
-- (goal.icon, from the goals window) wins over the automatic one.
local function Describe(goal)
	local name, icon = TYPES[goal.type].describe(goal)
	return name, goal.icon or icon
end

-- Fraction done (0..1), "1,512 / 4,000" and the amount still to go.
local function GetProgress(goal)
	return TYPES[goal.type].progress(goal)
end
-- The parts of a goal's rate: gained ("+312 looted"), per hour ("820/h"), gold per hour
-- (worth of the item goal's per hour, "38g/h"), time left ("3h 22m"); nil where there isn't one.
local function RateParts(goal)
	local goalType = TYPES[goal.type]
	local format = goalType.format
	local gained = goal.gained or 0
	local parts = { gained = "+" .. format(gained) .. (goalType.gainedSuffix or "") }
	local active = goal.active or 0
	if active >= 60 and gained > 0 then
		local perHour = gained / active * 3600
		parts.perHour = format(perHour) .. "/h"
		local each = ItemWorth(goal)
		if each then
			parts.goldPerHour = RoughMoney(perHour * each) .. "|cffffd100/h|r"
		end
		local _, _, remaining = GetProgress(goal)
		if remaining > 0 then
			parts.left = FormatDuration(remaining / perHour * 3600)
		end
	end
	return parts
end

-- "+312 looted · 820/h · 38g/h · ~3h 22m left"
local function DescribeRate(goal)
	if goal.completed then
		return "Done in " .. FormatDuration(goal.active or 0)
	end
	local rate = RateParts(goal)
	local parts = { rate.gained, rate.perHour, rate.goldPerHour, rate.left and ("~" .. rate.left .. " left") }
	local shown = {}
	for index = 1, 4 do
		if parts[index] then
			table.insert(shown, parts[index])
		end
	end
	if goal.paused then
		table.insert(shown, "paused")
	end
	return table.concat(shown, "  ·  ")
end

------------------------------------------------------------------------------
-- Completion message
------------------------------------------------------------------------------

-- NraKit's big toast (Toast.lua). A goal finished in combat is shown again when the fight ends.
local combatFinished = {} -- goals finished during the current fight

-- Shows the message for a goal (or a summary for several finished in one fight).
local function ShowToast(goal, detail, count)
	local name, icon = Describe(goal)
	if goal.type == "item" then
		name = FormatNumber(goal.target) .. " " .. name
	end
	if not detail then
		detail = "in " .. FormatDuration(goal.active or 0)
		local each = ItemWorth(goal)
		if each then
			detail = detail .. "  ·  worth " .. RoughCoins(each * goal.target)
		end
	end
	ns.toast.Show({
		style = "big",
		heading = count and count > 1 and (count .. " GOALS COMPLETE") or "GOAL COMPLETE",
		headingColor = DONE_COLOR,
		text = name,
		icon = icon,
		detail = detail or ("in " .. FormatDuration(goal.active or 0)),
		size = (ns:GetValue("farmGoalsToastSize") or 100) / 100,
		duration = ns:GetValue("farmGoalsToastDuration") or 6,
	})
end

-- The milestone message: a quieter cousin of the finish message, never over another message.
local function ShowMilestone(goal, percent)
	local name, icon = Describe(goal)
	ns.toast.Show({
		style = "small",
		heading = "MILESTONE",
		text = name .. "  ·  " .. percent .. "%",
		icon = icon,
		duration = 2.5,
		skipIfBusy = true,
	})
end

-- /nra preview goal, goals, milestone: the messages with a made-up goal (4,000 Silk Cloth).
local function SampleGoal()
	return { type = "item", itemID = ns.previewSample.itemID, target = 4000, active = 4520 }
end
ns:RegisterPreview("goal", "Farm Goals: the \"Goal complete\" message", function()
	ShowToast(SampleGoal())
end)
ns:RegisterPreview("goals", "Farm Goals: several goals finished in one fight", function()
	ShowToast(SampleGoal(), "and 2 more, while you were fighting", 3)
end)
ns:RegisterPreview("milestone", "Farm Goals: the small 25/50/75% message", function()
	ShowMilestone(SampleGoal(), 50)
end)

-- Called when combat ends: show again what finished during the fight.
local function ReplayCombatToasts()
	local last = combatFinished[#combatFinished]
	if last then
		local count = #combatFinished
		ShowToast(last, count > 1 and ("and " .. (count - 1) .. " more, while you were fighting")
			or "while you were fighting", count)
		wipe(combatFinished)
	end
end

------------------------------------------------------------------------------
-- Goal bookkeeping
------------------------------------------------------------------------------

local UpdateTracker

local function FindGoal(id)
	for index, goal in ipairs(GetData().goals) do
		if goal.id == id then
			return goal, index
		end
	end
end

-- Moves a goal out of the list; finished goals go to the history.
-- Records a finished run in the history. A cleared goal keeps a copy so it can be
-- restored from there; a "Go again" run is just a record.
local function Archive(goal, restorable)
	local copy
	if restorable then
		copy = {}
		for key, value in pairs(goal) do
			copy[key] = value
		end
	end
	table.insert(GetData().history, 1, {
		type = goal.type, name = (Describe(goal)), target = goal.target, itemID = goal.itemID, key = goal.key,
		mode = goal.mode, toMax = goal.toMax, icon = goal.icon, created = goal.created, completed = goal.completed,
		active = goal.active, goal = copy,
	})
end

-- Moves a goal out of the list; finished goals go to the history.
local function RemoveGoal(id)
	local data = GetData()
	local goal, index = FindGoal(id)
	if not goal then
		return
	end
	table.remove(data.goals, index)
	if goal.completed then
		Archive(goal, true)
	end
	UpdateTracker()
end

-- Puts a cleared goal back from the history, as it was.
local function RestoreGoal(entry)
	local data = GetData()
	for index, candidate in ipairs(data.history) do
		if candidate == entry and entry.goal then
			table.remove(data.history, index)
			entry.goal.seen = true
			table.insert(data.goals, entry.goal)
			UpdateTracker()
			return true
		end
	end
	return false
end

-- Gain-type goals ("loot 1000", "+5000 rep", "50k XP") can simply go again; "reach"
-- goals (level 40, Revered, Swords 300) need a new target instead.
local function CanGoAgain(goal)
	return goal.type == "item" or goal.type == "xp" or goal.type == "gold" or goal.mode == "gain"
end

-- "1,000 Silk Cloth", "50,000 XP", "100g", "5,000 Timbermaw Hold rep": what one more run is.
local function GoAgainAmount(goal)
	local amount = TYPES[goal.type].format(goal.target)
	if goal.type == "item" then
		return amount .. " " .. ItemName(goal.itemID)
	elseif goal.type == "xp" then
		return amount .. " XP"
	elseif goal.type == "gold" then
		return amount
	end
	return amount .. " " .. (goal.name or "")
end

-- "Go again": the finished run goes to the history and the same goal starts from zero.
local function GoAgain(goal)
	Archive(goal, false)
	goal.completed, goal.seen, goal.flashAt = nil, nil, nil
	goal.gained, goal.active, goal.milestone, goal.start = 0, 0, 0, 0
	local read = TYPES[goal.type].read
	if read then
		goal.last = read(goal)
	end
	goal.created = time()
	UpdateTracker()
end

-- Checks milestones and completion after a goal changed.
local function Evaluate(goal)
	if goal.completed then
		return
	end
	local fraction = GetProgress(goal)
	if fraction >= 1 then
		goal.completed = time()
		PlayGoalSound(goal, "complete")
		ShowToast(goal)
		if InCombatLockdown() then
			table.insert(combatFinished, goal)
		end
		local name = Describe(goal)
		ns:Print("Goal complete: " .. name .. " (" .. FormatDuration(goal.active or 0) .. ").")
		if ns:GetOption("farmGoalsAutoClear") then
			local id = goal.id
			C_Timer.After(6, function()
				RemoveGoal(id)
			end)
		end
		return
	end
	local milestone = math.min(3, math.floor(fraction * 4))
	if milestone > (goal.milestone or 0) then
		goal.milestone = milestone
		PlayGoalSound(goal, "milestone")
		if ns:GetOption("farmGoalsMilestoneMessage") then
			ShowMilestone(goal, milestone * 25)
		end
	end
end

-- Adds an amount to every running goal of a type (and item).
local function Gain(goalType, amount, itemID)
	if amount <= 0 then
		return
	end
	local changed = false
	for _, goal in ipairs(GetData().goals) do
		if goal.type == goalType and not goal.paused and not goal.completed
			and (goalType ~= "item" or goal.itemID == itemID) then
			goal.gained = (goal.gained or 0) + amount
			goal.flashAt = GetTime()
			changed = true
			Evaluate(goal)
		end
	end
	if changed then
		PlayGoalSound(nil, "tick")
		UpdateTracker()
	end
end

------------------------------------------------------------------------------
-- Counting
------------------------------------------------------------------------------

-- Turns a loot message format ("You receive loot: %sx%d.") into a Lua pattern.
local function ToPattern(format)
	if not format then
		return nil
	end
	local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = pattern:gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

-- Multiple-item formats first: the single-item pattern would also match them.
local LOOT_PATTERNS = {
	{ pattern = ToPattern(LOOT_ITEM_SELF_MULTIPLE) },
	{ pattern = ToPattern(LOOT_ITEM_SELF) },
	{ pattern = ToPattern(LOOT_ITEM_CREATED_SELF_MULTIPLE), crafted = true },
	{ pattern = ToPattern(LOOT_ITEM_CREATED_SELF), crafted = true },
}

local function OnLootMessage(text)
	if not text or (issecretvalue and issecretvalue(text)) then
		return
	end
	for _, entry in ipairs(LOOT_PATTERNS) do
		if entry.pattern then
			local link, count = text:match(entry.pattern)
			if link then
				if entry.crafted and not ns:GetOption("farmGoalsCountCrafted") then
					return
				end
				local itemID = tonumber(link:match("item:(%d+)"))
				if itemID then
					Gain("item", tonumber(count) or 1, itemID)
				end
				return
			end
		end
	end
end

local function OnXPUpdate()
	local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if lastXP then
		local gained
		if level > lastLevel then
			gained = (lastXPMax - lastXP) + xp
		else
			gained = xp - lastXP
		end
		Gain("xp", gained)
		Gain("level", gained)
	end
	lastXP, lastXPMax, lastLevel = xp, max, level
	-- Level goals also finish on the level itself, gained XP or not.
	for _, goal in ipairs(GetData().goals) do
		if goal.type == "level" and not goal.paused then
			Evaluate(goal)
		end
	end
	UpdateTracker()
end

-- Re-reads every goal of a type (rep, skill, currency) and counts increases.
local function Poll(goalType)
	local read = TYPES[goalType].read
	local any, changed = false, false
	for _, goal in ipairs(GetData().goals) do
		if goal.type == goalType then
			any = true
			local current = read(goal)
			if current then
				if goal.last and current > goal.last and not goal.paused and not goal.completed then
					goal.gained = (goal.gained or 0) + (current - goal.last)
					goal.flashAt = GetTime()
					changed = true
				end
				goal.last = current
				if not goal.paused then
					Evaluate(goal)
				end
			end
		end
	end
	if changed then
		PlayGoalSound(nil, "tick")
	end
	if any then
		UpdateTracker()
	end
end

-- Event -> goal type it updates.
local POLL_EVENTS = {}
for key, goalType in pairs(TYPES) do
	if goalType.event then
		POLL_EVENTS[goalType.event] = key
	end
end

-- Reading the current values again after a reload/login, so changes made while the
-- addon wasn't running (or the module was off) don't count as gains.
local function ResyncPolled()
	for _, goal in ipairs(GetData().goals) do
		local read = TYPES[goal.type] and TYPES[goal.type].read
		if read then
			goal.last = read(goal) or goal.last
		end
	end
end

local function OnMoney()
	local money = GetMoney()
	if lastMoney then
		Gain("gold", money - lastMoney)
	end
	lastMoney = money
end

------------------------------------------------------------------------------
-- Tracker
------------------------------------------------------------------------------

-- Views, cycled with the header's view button: one-line-per-goal sizes and how many fit.
local VIEWS = { "full", "compact", "icons" }
local VIEW_LABELS = { full = "Full", compact = "Compact", icons = "Icons" }
local VIEW_DESCRIPTIONS = { full = "Full", compact = "Compact  (one line per goal)", icons = "Icons  (a tile per goal)" }
local COMPACT_HEIGHT = 24
local HEADER_LINGER, HEADER_FADE = 2.5, 0.4 -- Icons view: the floating header after the mouse leaves
local HEADER_MARGIN = 12 -- Icons view: extra hover area around the tiles and the header
local MAX_COMPACT_ROWS = 12
local MAX_ICONS = 30

local function GetView()
	local view = NraKitDB.farmGoalsView
	return VIEW_LABELS[view] and view or "full"
end

local function SetView(view)
	NraKitDB.farmGoalsView = view
	UpdateTracker()
end

local function SetShelved(goal, shelved)
	goal.shelved = shelved or nil
	goal.paused = shelved or nil
	UpdateTracker()
end

-- Short amount for the icon view: "1.5k", "12g", "Lv 31".
local function ShortAmount(goal)
	local value
	if goal.type == "level" then
		return "Lv " .. UnitLevel("player")
	elseif goal.mode == "gain" or goal.type == "xp" then
		value = goal.gained or 0
	elseif goal.type == "item" or goal.type == "gold" then
		value = (goal.start or 0) + (goal.gained or 0)
	elseif TYPES[goal.type].read then
		value = TYPES[goal.type].read(goal) or 0
		if goal.type == "rep" then
			local data = C_Reputation.GetFactionDataByID(goal.key)
			value = data and value - data.currentReactionThreshold or value
		end
	end
	if goal.type == "gold" then
		-- One unit, the largest there is: "12g", "45s", "20c".
		if value >= 10000 then
			return FormatNumber(math.floor(value / 10000)) .. "g"
		end
		return value >= 100 and (math.floor(value / 100) .. "s") or (math.floor(value) .. "c")
	elseif value >= 10000 then
		return math.floor(value / 1000) .. "k"
	elseif value >= 1000 then
		return string.format("%.1fk", value / 1000)
	end
	return tostring(math.floor(value))
end

local function OpenMenu(widget)
	local goal = widget.goal and FindGoal(widget.goal.id)
	if not (goal and MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MenuUtil.CreateContextMenu(widget, function(_, root)
		root:CreateTitle((Describe(goal)))
		if goal.completed then
			if CanGoAgain(goal) then
				root:CreateButton("Go again (another " .. GoAgainAmount(goal) .. ")", function()
					GoAgain(goal)
				end)
			else
				root:CreateButton("New target...", function()
					ns:OpenGoalsWindow("edit", goal.id)
				end)
			end
			root:CreateButton("Clear (move to history)", function()
				RemoveGoal(goal.id)
			end)
			return
		end
		root:CreateButton(goal.paused and "Resume" or "Pause", function()
			goal.paused = not goal.paused or nil
			UpdateTracker()
		end)
		root:CreateButton("Shelve (hide and pause)", function()
			SetShelved(goal, true)
			ns:Print((Describe(goal)) .. " is shelved. Find it in the goals window (/nra goal) to bring it back.")
		end)
		root:CreateButton("Edit goal...", function()
			ns:OpenGoalsWindow("edit", goal.id)
		end)
		root:CreateButton("Reset progress", function()
			goal.gained, goal.active, goal.milestone = 0, 0, 0
			if goal.type == "level" then
				goal.startLevel = UnitLevel("player") + UnitXP("player") / math.max(UnitXPMax("player"), 1)
			end
			UpdateTracker()
		end)
		root:CreateDivider()
		root:CreateButton("|cffff6060Remove goal|r", function()
			RemoveGoal(goal.id)
		end)
	end)
end

-- "1,512 / 4,000  (38%)"
local function ProgressWithPercent(goal)
	local fraction, value = GetProgress(goal)
	return string.format("%s  (%d%%)", value, math.floor(math.min(math.max(fraction, 0), 1) * 100))
end

local function ShowGoalTooltip(widget)
	local goal = widget.goal
	if not goal then
		return
	end
	-- Beside the goal, top-aligned: never over the space above the tracker (the Icons
	-- view's header shows there).
	GameTooltip:SetOwner(widget, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", widget, "TOPLEFT", -6, 0)
	if goal.itemID then
		GameTooltip:SetItemByID(goal.itemID)
		GameTooltip:AddLine(" ")
	else
		GameTooltip_SetTitle(GameTooltip, (Describe(goal)))
	end
	GameTooltip:AddDoubleLine("Progress", ProgressWithPercent(goal), 1, 0.82, 0, 1, 1, 1)
	-- Label and value, like the rest of the tooltip: the gold per hour stands out.
	if goal.completed then
		GameTooltip:AddDoubleLine("Done in", FormatDuration(goal.active or 0), 1, 0.82, 0, 0.3, 0.85, 0.3)
	else
		local rate = RateParts(goal)
		GameTooltip:AddDoubleLine(goal.type == "item" and "Looted" or "Gained", (rate.gained:gsub(" looted$", "")), 1, 0.82, 0, 1, 1, 1)
		if rate.perHour then
			GameTooltip:AddDoubleLine("Rate", rate.perHour .. (rate.goldPerHour and ("  ·  " .. rate.goldPerHour) or ""),
				1, 0.82, 0, 1, 1, 1)
		end
		if rate.left then
			GameTooltip:AddDoubleLine("Time left", rate.left, 1, 0.82, 0, 1, 1, 1)
		end
		if goal.paused then
			GameTooltip:AddDoubleLine("Paused", "", 1, 0.82, 0, 1, 1, 1)
		end
	end
	if goal.start and goal.start > 0 then
		GameTooltip:AddDoubleLine("Started from", TYPES[goal.type].format(goal.start), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Running for", FormatDuration(goal.active or 0), 1, 0.82, 0, 1, 1, 1)
	-- What it's worth (the price of one is already in the tooltip, Auctionator's or the vendor's).
	local each, where, age = ItemWorth(goal)
	if each then
		local have = (goal.start or 0) + (goal.gained or 0)
		local at = where == "ah" and " (auction house)" or " (vendor)"
		GameTooltip:AddDoubleLine("Worth now" .. at, RoughCoins(each * have), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("Worth at " .. FormatNumber(goal.target), RoughCoins(each * goal.target), 1, 0.82, 0, 1, 1, 1)
		if age and age > 3 then
			GameTooltip:AddLine(string.format("Auction price %d days old: it may have changed.", age), 1, 0.6, 0.2, true)
		end
	end
	if goal.completed then
		GameTooltip:AddLine("Click to clear it (it goes to the history). Right-click to go again.", 0.3, 0.85, 0.3, true)
	else
		GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
	end
	GameTooltip:Show()
	-- The glow has done its job once you've looked.
	if goal.completed and not goal.seen then
		goal.seen = true
	end
end

-- A pulsing green frame for finished goals nobody has looked at yet.
local function MakeGlow(parent)
	local glow = CreateFrame("Frame", nil, parent)
	glow:SetAllPoints()
	glow:SetFrameLevel(parent:GetFrameLevel() + 4)
	local fill = glow:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(DONE_COLOR[1], DONE_COLOR[2], DONE_COLOR[3], 0.12)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = UI.AddLine(glow, side)
		line:SetColorTexture(DONE_COLOR[1], DONE_COLOR[2], DONE_COLOR[3], 1)
		if side == "TOP" or side == "BOTTOM" then
			line:SetHeight(2)
		else
			line:SetWidth(2)
		end
	end
	glow:Hide()
	return glow
end

local function Pulse(glow, on)
	glow:SetShown(on)
	if on then
		glow:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.sin(GetTime() * 4)))
	end
end

-- What every goal widget does, whatever the view: menu, tooltip, chat link, drag, flash.
local function SetupGoalWidget(widget)
	widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- Dragging a goal moves the whole tracker.
	widget:RegisterForDrag("LeftButton")
	widget:SetScript("OnDragStart", function()
		tracker:GetScript("OnDragStart")(tracker)
	end)
	widget:SetScript("OnDragStop", function()
		tracker:GetScript("OnDragStop")(tracker)
	end)
	widget:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenMenu(self)
		elseif self.goal and self.goal.completed and not IsModifiedClick() then
			-- A finished goal is cleared with a click; the history can restore it.
			local name = Describe(self.goal)
			RemoveGoal(self.goal.id)
			GameTooltip_Hide()
			ns:Print(name .. " moved to the history. Restore it there (/nra goal) if that was a mistake.")
		elseif IsModifiedClick("CHATLINK") and self.goal and self.goal.itemID then
			local link = select(2, C_Item.GetItemInfo(self.goal.itemID))
			if link then
				ChatFrameUtil.InsertLink(link)
			end
		end
	end)
	widget:SetScript("OnEnter", ShowGoalTooltip)
	widget:SetScript("OnLeave", GameTooltip_Hide)
	widget.flash = widget:CreateTexture(nil, "BACKGROUND", nil, 1)
	widget.flash:SetAllPoints()
	widget.flash:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.25)
	widget.flash:SetAlpha(0)
	widget.glow = MakeGlow(widget)
	widget:SetScript("OnUpdate", function(self)
		local goal = self.goal
		local flashAt = goal and goal.flashAt
		local age = flashAt and GetTime() - flashAt
		self.flash:SetAlpha(age and age < 0.6 and (1 - age / 0.6) or 0)
		Pulse(self.glow, goal ~= nil and goal.completed ~= nil and not goal.seen)
	end)
end

local function MakeTrack(parent, height)
	local track = CreateFrame("StatusBar", nil, parent)
	track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	track:SetMinMaxValues(0, 1)
	track:SetHeight(height)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints()
	track.bg:SetColorTexture(1, 1, 1, 0.12)
	UI.AddMilestoneTicks(track)
	return track
end

-- Colours a widget's name and bar for done / paused / running.
local function ApplyState(widget, goal)
	local fraction = GetProgress(goal)
	widget.track:SetValue(math.min(math.max(fraction, 0), 1))
	widget.icon:SetDesaturated(goal.paused and true or false)
	local color = goal.completed and DONE_COLOR or goal.paused and PAUSED_COLOR or UI.ACCENT
	widget.track:SetStatusBarColor(unpack(color))
	if widget.name then
		widget.name:SetTextColor(unpack(goal.completed and DONE_COLOR or goal.paused and UI.GREY or UI.GOLD))
	end
end

-- Full: icon, name, value, bar, rate line.
local function CreateFullRow(index)
	local row = CreateFrame("Button", nil, tracker)
	row:SetHeight(ROW_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	SetupGoalWidget(row)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(30, 30)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("TOPRIGHT", -8, -7)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.track = MakeTrack(row, 4)
	row.track:SetPoint("LEFT", row.icon, "RIGHT", 8, -2)
	row.track:SetPoint("RIGHT", -8, 0)
	row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -2)
	row.info:SetPoint("RIGHT", -8, 0)
	row.info:SetJustifyH("LEFT")
	row.info:SetWordWrap(false)
	return row
end

-- Compact: one line (small icon, name, value) with a hairline bar under it.
local function CreateCompactRow(index)
	local row = CreateFrame("Button", nil, tracker)
	row:SetHeight(COMPACT_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	SetupGoalWidget(row)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 6, 1)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -6, 1)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.track = MakeTrack(row, 2)
	row.track:SetPoint("BOTTOMLEFT", 6, 2)
	row.track:SetPoint("BOTTOMRIGHT", -6, 2)
	return row
end

-- Icons: the goal's icon with a bar along its bottom edge and the amount under it.
local function CreateIconTile()
	local tile = CreateFrame("Button", nil, tracker)
	SetupGoalWidget(tile)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetPoint("TOPLEFT")
	tile.icon:SetPoint("TOPRIGHT")
	tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tile.track = MakeTrack(tile, 3)
	tile.track:SetPoint("BOTTOMLEFT", tile.icon, "BOTTOMLEFT")
	tile.track:SetPoint("BOTTOMRIGHT", tile.icon, "BOTTOMRIGHT")
	tile.track:SetFrameLevel(tile:GetFrameLevel() + 2)
	tile.glow:ClearAllPoints()
	tile.glow:SetAllPoints(tile.icon)
	tile.count = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.count:SetPoint("BOTTOM", 0, 0)
	-- Green frame when done.
	tile.done = CreateFrame("Frame", nil, tile)
	tile.done:SetAllPoints(tile.icon)
	tile.done:SetFrameLevel(tile:GetFrameLevel() + 3)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = UI.AddLine(tile.done, side)
		line:SetColorTexture(DONE_COLOR[1], DONE_COLOR[2], DONE_COLOR[3], 1)
	end
	return tile
end

local widgets = { full = {}, compact = {}, icons = {} }
local CREATE = { full = CreateFullRow, compact = CreateCompactRow, icons = CreateIconTile }

local function GetWidget(view, index)
	local list = widgets[view]
	list[index] = list[index] or CREATE[view](index)
	return list[index]
end

-- Lays out the goals in a view; returns the tracker's width and the height below the header.
local LAYOUT = {}

function LAYOUT.full(goals, top)
	local shown = math.min(#goals, MAX_ROWS)
	for index = 1, shown do
		local goal, row = goals[index], GetWidget("full", index)
		row.goal = goal
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -top - (index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -top - (index - 1) * ROW_HEIGHT)
		local name, icon = Describe(goal)
		local _, value = GetProgress(goal)
		local each = ItemWorth(goal)
		if each then
			value = value .. "  |cffffd100" .. RoughMoney(each * ((goal.start or 0) + (goal.gained or 0))) .. "|r"
		end
		row.icon:SetTexture(icon)
		row.name:SetText(name)
		row.value:SetText(value)
		row.info:SetText(DescribeRate(goal))
		ApplyState(row, goal)
		row:Show()
	end
	return ns:GetValue("farmGoalsWidth") or 260, shown * ROW_HEIGHT, shown
end

function LAYOUT.compact(goals, top)
	local shown = math.min(#goals, MAX_COMPACT_ROWS)
	for index = 1, shown do
		local goal, row = goals[index], GetWidget("compact", index)
		row.goal = goal
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -top - (index - 1) * COMPACT_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -top - (index - 1) * COMPACT_HEIGHT)
		local name, icon = Describe(goal)
		local _, value = GetProgress(goal)
		row.icon:SetTexture(icon)
		row.name:SetText(name)
		row.value:SetText(value)
		ApplyState(row, goal)
		row:Show()
	end
	return ns:GetValue("farmGoalsCompactWidth") or 210, shown * COMPACT_HEIGHT, shown
end

-- Just the tiles: one goal is one icon wide; it grows sideways up to "Icons per row", then wraps.
function LAYOUT.icons(goals, top)
	local size = ns:GetValue("farmGoalsIconSize") or 32
	local perRow = ns:GetValue("farmGoalsIconsPerRow") or 3
	local gap, pad, labelHeight = 6, 6, 13
	local shown = math.min(#goals, MAX_ICONS)
	local columns = math.min(perRow, math.max(shown, 1))
	for index = 1, shown do
		local goal, tile = goals[index], GetWidget("icons", index)
		tile.goal = goal
		tile:SetSize(size, size + labelHeight)
		tile.icon:SetHeight(size)
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", pad + column * (size + gap), -top - pad - row * (size + labelHeight + gap))
		local _, icon = Describe(goal)
		tile.icon:SetTexture(icon)
		tile.icon:SetAlpha(goal.paused and 0.6 or 1)
		tile.count:SetText(ShortAmount(goal))
		tile.done:SetShown(goal.completed ~= nil)
		ApplyState(tile, goal)
		tile:Show()
	end
	local rows = math.ceil(shown / columns)
	local width = pad * 2 + columns * size + (columns - 1) * gap
	return width, pad * 2 + rows * (size + labelHeight) + math.max(rows - 1, 0) * gap, shown
end

local function SavePosition()
	local point, _, relativePoint, x, y = tracker:GetPoint()
	NraKitDB.farmGoalsPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function HeaderButton(header, label, tooltipTitle, tooltipText, onClick)
	local button = UI.CreateFlatButton(header, label, 16)
	button:SetWidth(18)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, type(tooltipTitle) == "function" and tooltipTitle() or tooltipTitle,
			type(tooltipText) == "function" and tooltipText() or tooltipText)
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function CreateTracker()
	tracker = CreateFrame("Frame", "NraKitGoalsTracker", UIParent)
	tracker:SetFrameStrata("MEDIUM")
	tracker:SetClampedToScreen(true)
	tracker:SetMovable(true)
	tracker:EnableMouse(true)
	tracker:RegisterForDrag("LeftButton")
	tracker:SetScript("OnDragStart", function(self)
		if not ns:GetOption("farmGoalsLocked") then
			self:StartMoving()
		end
	end)
	tracker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	local position = NraKitDB.farmGoalsPosition
	if position then
		tracker:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		tracker:SetPoint("TOPLEFT", UIParent, "CENTER", 300, 200)
	end

	local bg = tracker:CreateTexture(nil, "BACKGROUND", nil, -1)
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.04, 0.06, 0.75)
	UI.AddBorder(tracker)

	local header = CreateFrame("Frame", nil, tracker)
	header:SetHeight(HEADER_HEIGHT)
	UI.AddLine(header, "BOTTOM")
	-- In the Icons view the header floats above the tiles (shown on hover) and needs its own background.
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.bg:SetColorTexture(0.04, 0.04, 0.06, 0.85)
	tracker.header = header
	tracker.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tracker.title:SetPoint("LEFT", 8, 0)
	tracker.title:SetTextColor(unpack(UI.ACCENT))

	local add = HeaderButton(header, "+", "New goal", "Open the goals window.", function()
		ns:OpenGoalsWindow("new")
	end)
	add:SetPoint("RIGHT", -3, 0)

	tracker.collapse = HeaderButton(header, "-", function()
		return NraKitDB.farmGoalsCollapsed and "Expand" or "Collapse"
	end, "Show just this header, or the goals again.", function()
		NraKitDB.farmGoalsCollapsed = not NraKitDB.farmGoalsCollapsed or nil
		UpdateTracker()
	end)
	tracker.collapse:SetPoint("RIGHT", add, "LEFT", -2, 0)

	-- View menu: Full / Compact / Icons, plus the tracker's other handy bits.
	tracker.view = HeaderButton(header, "", function()
		return "View: " .. VIEW_LABELS[GetView()]
	end, "Choose how the tracker looks, lock it, or open its settings.", function(self)
		GameTooltip_Hide()
		if not (MenuUtil and MenuUtil.CreateContextMenu) then
			return
		end
		MenuUtil.CreateContextMenu(self, function(_, root)
			root:CreateTitle("Tracker view")
			local function IsView(view)
				return GetView() == view
			end
			for _, view in ipairs(VIEWS) do
				root:CreateRadio(VIEW_DESCRIPTIONS[view], IsView, SetView, view)
			end
			root:CreateDivider()
			root:CreateCheckbox("Lock position", function()
				return ns:GetOption("farmGoalsLocked")
			end, function()
				ns:SetSetting("farmGoalsLocked", not ns:GetOption("farmGoalsLocked"))
			end)
			root:CreateButton("Open goals window", function()
				ns:OpenGoalsWindow("active")
			end)
			root:CreateButton("Tracker settings...", function()
				ns:OpenSettings("farm goals", module.key)
			end)
		end)
	end)
	tracker.view:SetPoint("RIGHT", tracker.collapse, "LEFT", -2, 0)
	local arrow = tracker.view:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(12, 12)
	arrow:SetPoint("CENTER", 0, -2)

	tracker.more = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tracker.more:SetPoint("BOTTOM", 0, 4)

	-- When collapsed, the header glows for unseen finished goals; hovering it counts as seeing them.
	tracker.headerGlow = MakeGlow(header)
	tracker:SetScript("OnUpdate", function(self)
		Pulse(self.headerGlow, self.unseenWhileCollapsed == true)
		if self.floatingHeader then
			-- Shown while the mouse is on the tiles or the header, then lingers a moment and
			-- fades, so it can still be reached past a goal's tooltip.
			-- The hover area is generous: the tiles plus the strip above them where the header
			-- sits, and a margin around the header, so reaching for a button never hides it.
			local now = GetTime()
			local margin = HEADER_MARGIN
			if self:IsMouseOver(HEADER_HEIGHT + margin, -margin, -margin, margin)
				or (self.header:IsShown() and self.header:IsMouseOver(margin, -margin, -margin, margin)) then
				self.headerHoverAt = now
			end
			local since = now - (self.headerHoverAt or -math.huge)
			if since < HEADER_LINGER then
				self.header:SetAlpha(1)
				self.header:Show()
			elseif since < HEADER_LINGER + HEADER_FADE then
				self.header:SetAlpha(1 - (since - HEADER_LINGER) / HEADER_FADE)
			else
				self.header:Hide()
			end
		end
	end)
	tracker:SetScript("OnEnter", function(self)
		if self.unseenWhileCollapsed then
			for _, goal in ipairs(GetData().goals) do
				if goal.completed then
					goal.seen = true
				end
			end
			self.unseenWhileCollapsed = nil
		end
	end)
end

-- Unfinished goals first (in the order they were made), then finished ones. Shelved
-- goals aren't shown.
local function TrackedGoals()
	local list = {}
	for _, goal in ipairs(GetData().goals) do
		if not goal.shelved then
			table.insert(list, goal)
		end
	end
	table.sort(list, function(a, b)
		if (a.completed ~= nil) ~= (b.completed ~= nil) then
			return a.completed == nil
		end
		return a.id < b.id
	end)
	return list
end

function UpdateTracker()
	if ns.goals.onChanged then
		ns.goals.onChanged()
	end
	if not characterKey then
		return
	end
	local goals = TrackedGoals()
	local show = ns:IsModuleEnabled(module.key) and #goals > 0
		and not (ns:GetOption("farmGoalsHideInCombat") and InCombatLockdown())
	if not show then
		if tracker then
			tracker:Hide()
		end
		return
	end
	if not tracker then
		CreateTracker()
	end
	tracker:SetScale((ns:GetValue("farmGoalsScale") or 100) / 100)

	local done = 0
	for _, goal in ipairs(goals) do
		if goal.completed then
			done = done + 1
		end
	end
	local view = GetView()
	tracker.title:SetText(string.format(view == "icons" and "GOALS" or "GOALS  |cff808080%d/%d|r", done, #goals))
	local collapsed = NraKitDB.farmGoalsCollapsed
	tracker.collapse.text:SetText(collapsed and "+" or "-")
	local unseen = false
	for _, goal in ipairs(goals) do
		if goal.completed and not goal.seen then
			unseen = true
		end
	end
	tracker.unseenWhileCollapsed = collapsed and unseen or nil

	-- Icons: the box is just the tiles, with the header floating above them on hover.
	local floating = view == "icons" and not collapsed
	local header = tracker.header
	header:ClearAllPoints()
	if floating then
		header:SetPoint("BOTTOMLEFT", tracker, "TOPLEFT", 0, 1)
		header:SetWidth(64)
		if not tracker.headerHoverAt then
			header:Hide()
		end
	else
		header:SetPoint("TOPLEFT")
		header:SetPoint("TOPRIGHT")
		header:Show()
	end
	header.bg:SetShown(floating)
	tracker.title:SetShown(not floating)
	tracker.floatingHeader = floating
	local top = floating and 0 or HEADER_HEIGHT

	local width, height, shown = 0, 0, 0
	if not collapsed then
		width, height, shown = LAYOUT[view](goals, top)
	end
	-- Hide what the layout didn't use (other views, and rows past the last goal).
	for name, list in pairs(widgets) do
		for index, widget in ipairs(list) do
			if collapsed or name ~= view or index > shown then
				widget:Hide()
				widget.goal = nil
			end
		end
	end

	local hidden = collapsed and 0 or #goals - shown
	tracker.more:SetText(hidden > 0 and string.format("+%d more  (/nra goal)", hidden) or "")
	if collapsed then
		width = view == "icons" and 120 or (ns:GetValue(view == "compact" and "farmGoalsCompactWidth" or "farmGoalsWidth") or 260)
	end
	tracker:SetWidth(width)
	tracker:SetHeight(top + height + (hidden > 0 and 18 or 0))
	tracker:Show()
end

------------------------------------------------------------------------------
-- API for the goals window and slash command
------------------------------------------------------------------------------

-- What you have of an item (or gold), for "start from what I have".
-- Returns { bags, bank, mail, others = { { name, class, count }, ... }, othersTotal, trackerOn }.
local function GetHoldings(itemID)
	local trackerOn = ns:IsModuleEnabled("inventoryTracker") and NraKitDB.inventory ~= nil
	local result = { bags = 0, bank = 0, mail = 0, others = {}, othersTotal = 0, trackerOn = trackerOn }
	local realm, player = ns.inventory and ns.inventory.GetRealm(), ns.inventory and ns.inventory.GetPlayer()
	local me = trackerOn and realm and NraKitDB.inventory[realm] and NraKitDB.inventory[realm][player]

	if itemID then
		result.bags = C_Item.GetItemCount(itemID, false)
		local withBank = C_Item.GetItemCount(itemID, true)
		result.bank = math.max(withBank - result.bags, me and me.bank and me.bank[itemID] or 0)
		result.mail = me and me.mail and me.mail[itemID] or 0
	else
		result.bags = GetMoney()
	end

	if trackerOn then
		for realmName, characters in pairs(NraKitDB.inventory) do
			for name, character in pairs(characters) do
				if not (realmName == realm and name == player) then
					local count = 0
					if itemID then
						for _, where in ipairs(ns.inventory.LOCATIONS) do
							count = count + (character[where] and character[where][itemID] or 0)
						end
					else
						count = character.money or 0
					end
					if count > 0 then
						table.insert(result.others, { name = name, class = character.class, count = count })
						result.othersTotal = result.othersTotal + count
					end
				end
			end
		end
		table.sort(result.others, function(a, b)
			return a.count > b.count
		end)
	end
	return result
end

local function AddGoal(goal)
	nextID = math.max(nextID, time() * 100) + 1
	goal.id = nextID
	goal.created = time()
	goal.gained, goal.active, goal.milestone = 0, 0, 0
	local read = TYPES[goal.type].read
	if read then
		goal.last = read(goal)
		goal.start = goal.start or goal.last
	end
	goal.start = goal.start or 0
	if goal.type == "level" then
		goal.startLevel = UnitLevel("player") + UnitXP("player") / math.max(UnitXPMax("player"), 1)
	end
	-- Starting at 30% shouldn't chime for 25%.
	local fraction = GetProgress(goal)
	goal.milestone = math.min(3, math.floor(math.max(fraction, 0) * 4))
	table.insert(GetData().goals, goal)
	Evaluate(goal)
	UpdateTracker()
	return goal
end

-- Applies the goals window's Edit form. If the tracked thing (item, faction, skill,
-- currency or gain/reach mode) changed, progress starts over; otherwise it's kept and
-- only the target, sounds, icon and (if recount) the starting count change.
local function EditGoal(id, changes, recount)
	local goal = FindGoal(id)
	if not goal then
		return
	end
	local changedThing = goal.itemID ~= changes.itemID or goal.key ~= changes.key
		or (goal.mode or "reach") ~= (changes.mode or "reach")
	goal.itemID, goal.key, goal.name, goal.mode = changes.itemID, changes.key, changes.name or goal.name, changes.mode
	goal.target, goal.toMax, goal.sounds, goal.icon = changes.target, changes.toMax, changes.sounds, changes.icon
	local read = TYPES[goal.type].read
	if changedThing then
		goal.gained, goal.active, goal.flashAt = 0, 0, nil
		goal.last = read and read(goal) or nil
		goal.start = changes.start or goal.last or 0
	elseif recount and changes.start then
		goal.start = changes.start
	end
	-- Re-check where it stands, without chiming for milestones it was already past.
	local fraction = GetProgress(goal)
	if goal.completed and fraction < 1 then
		goal.completed = nil
	end
	goal.milestone = math.min(3, math.floor(math.max(fraction, 0) * 4))
	Evaluate(goal)
	UpdateTracker()
end

ns.goals = {
	EditGoal = EditGoal,
	SetView = function(view)
		SetView(view)
	end,
	GoAgain = GoAgain,
	GoAgainAmount = GoAgainAmount,
	ProgressWithPercent = function(goal)
		return ProgressWithPercent(goal)
	end,
	CanGoAgain = CanGoAgain,
	RestoreGoal = RestoreGoal,
	SetShelved = function(goal, shelved)
		SetShelved(goal, shelved)
	end,
	GetData = function()
		return GetData()
	end,
	TYPES = TYPES,
	DefaultSoundLabel = DefaultSoundLabel,
	DefaultSound = DefaultSound,
	REP_THRESHOLDS = REP_THRESHOLDS,
	StandingLabel = StandingLabel,
	Describe = Describe,
	AutoIcon = AutoIcon,
	GetProgress = GetProgress,
	DescribeRate = DescribeRate,
	FormatNumber = FormatNumber,
	FormatGold = FormatGold,
	ParseMoney = ParseMoney,
	FormatDuration = FormatDuration,
	GetHoldings = GetHoldings,
	AddGoal = AddGoal,
	RemoveGoal = RemoveGoal,
	FindGoal = FindGoal,
	Update = function()
		UpdateTracker()
	end,
}

-- Finds a faction, skill or currency by name: an exact match first, else the first that
-- contains the text. Returns the API's data table and its ID.
local function FindByName(text, count, get, idOf)
	text = text:lower()
	local partial, partialID
	for index = 1, count do
		local data = get(index)
		local id = data and idOf(data, index)
		if id and data.name then
			local name = data.name:lower()
			if name == text then
				return data, id
			elseif not partial and name:find(text, 1, true) then
				partial, partialID = data, id
			end
		end
	end
	return partial, partialID
end

local function FindFaction(text)
	return FindByName(text, C_Reputation.GetNumFactions(), C_Reputation.GetFactionDataByIndex, function(data)
		return (not data.isHeader or data.isHeaderWithRep) and data.factionID and data.factionID > 0 and data.factionID or nil
	end)
end

local function FindSkill(text)
	return FindByName(text, C_SkillInfo.GetNumSkillLines(), C_SkillInfo.GetSkillLineInfo, function(data)
		return not data.isHeader and data.skillID or nil
	end)
end

local function FindCurrency(text)
	return FindByName(text, C_CurrencyInfo.GetCurrencyListSize(), C_CurrencyInfo.GetCurrencyListInfo, function(data, index)
		local link = not data.isHeader and C_CurrencyInfo.GetCurrencyListLink(index)
		return link and tonumber(link:match("currency:(%d+)"))
	end)
end

-- "revered" (or "Revered", in the game's language) -> 7
local function FindStanding(text)
	text = text:lower()
	for reaction = 1, #REP_THRESHOLDS do
		if StandingLabel(reaction):lower() == text then
			return reaction
		end
	end
end

-- Prints the goals, numbered, with where they stand.
local function ListGoals()
	local goals = GetData().goals
	if #goals == 0 then
		ns:Print("No goals yet. /nra goal help shows how to add one.")
		return
	end
	ns:Print("Your goals:")
	for index, goal in ipairs(goals) do
		local _, value = GetProgress(goal)
		local state = goal.shelved and "  |cff808080(shelved)|r" or goal.paused and "  |cff808080(paused)|r"
			or goal.completed and "  |cff4cd94c(done)|r" or ""
		print(string.format("  %d. %s  |cffffffff%s|r%s", index, (Describe(goal)), value, state))
	end
end

local SLASH_HELP = {
	summary = "Farm Goals: open the goals window, or add a goal straight from chat",
	usage = {
		"/nra goal - open the goals window",
		"/nra goal list - list your goals and where they stand",
		"/nra goal <count> <item> - loot that many of an item (shift-click the item to paste it)",
		"/nra goal level <level> - reach a level",
		"/nra goal xp <amount> - gain that much XP",
		"/nra goal gold <amount> - have that much money (counting what you gain from now): 100, 50s, 1g 50s",
		"/nra goal rep <standing> <faction> - reach a standing, e.g. /nra goal rep revered timbermaw",
		"/nra goal rep +<amount> <faction> - gain that much reputation",
		"/nra goal skill <skill> [rank] - raise a skill to a rank, or to its cap if no rank, e.g. /nra goal skill swords",
		"/nra goal currency <amount> <currency> - have that much of a currency (+<amount> to gain it)",
		"Names can be partial; the goals window can do everything here and more (starting counts, sounds).",
	},
}

local function SlashError(message)
	ns:Print(message .. " See /nra goal help.")
end

local function OnSlashCommand(input)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Farm Goals first (/nra).")
		return
	end
	local first, rest = input:match("^(%S*)%s*(.-)$")
	first = first:lower()
	local goal

	if first == "" then
		ns:OpenGoalsWindow()
		return
	elseif first == "list" then
		ListGoals()
		return
	elseif first == "gold" then
		local copper = ParseMoney(rest)
		if not copper then
			SlashError("Give an amount like 100 (gold), 50s or 1g 50s.")
			return
		end
		goal = { type = "gold", target = copper }
	elseif first == "level" or first == "xp" then
		local amount = tonumber(rest:match("^(%d+)"))
		if not amount then
			SlashError("Give a number, e.g. /nra goal " .. first .. " " .. (first == "level" and "40" or "100") .. ".")
			return
		elseif first == "level" and amount <= UnitLevel("player") then
			SlashError("You're already level " .. UnitLevel("player") .. ".")
			return
		end
		goal = { type = first, target = amount }
	elseif first == "rep" then
		local target, name = rest:match("^(%S+)%s+(.+)$")
		if not target then
			SlashError("Give a standing (or +amount) and a faction.")
			return
		end
		local data, id = FindFaction(name)
		if not data then
			SlashError("No faction called \"" .. name .. "\" in your reputation list.")
			return
		end
		local gain = tonumber(target:match("^%+(%d+)$"))
		local standing = FindStanding(target)
		if gain then
			goal = { type = "rep", key = id, name = data.name, mode = "gain", target = gain }
		elseif standing then
			if standing <= data.reaction then
				SlashError("You're already " .. StandingLabel(data.reaction) .. " with " .. data.name .. ".")
				return
			end
			goal = { type = "rep", key = id, name = data.name, mode = "reach", target = standing }
		else
			SlashError("\"" .. target .. "\" isn't a standing (friendly, honored, revered, exalted) or +amount.")
			return
		end
	elseif first == "skill" then
		local name, target = rest:match("^(.-)%s+(%S+)$")
		if not (target and (tonumber(target) or target:lower() == "max")) then
			name, target = rest, nil
		end
		local data, id
		if name ~= "" then
			data, id = FindSkill(name)
		end
		if not data then
			SlashError("No skill called \"" .. rest .. "\" in your skills.")
			return
		end
		local rank = tonumber(target or "")
		if rank and rank <= data.rank then
			SlashError(data.name .. " is already " .. data.rank .. ".")
			return
		end
		goal = { type = "skill", key = id, name = data.name, mode = "reach", target = rank or data.maxRank, toMax = not rank }
	elseif first == "currency" then
		local amount, name = rest:match("^(%+?%d+)%s+(.+)$")
		if not amount then
			SlashError("Give an amount and a currency.")
			return
		end
		local data, id = FindCurrency(name)
		if not data then
			SlashError("No currency called \"" .. name .. "\".")
			return
		end
		local gain = amount:sub(1, 1) == "+"
		goal = { type = "currency", key = id, name = data.name, mode = gain and "gain" or "reach", target = tonumber(amount:match("%d+")) }
	else
		-- /nra goal [item] <count> <item link or name>
		if first == "item" then
			first, rest = rest:match("^(%S*)%s*(.-)$")
		end
		local count = tonumber(first)
		if not count or rest == "" then
			SlashError("Unknown goal \"" .. input .. "\".")
			return
		end
		local itemID = tonumber(rest:match("item:(%d+)")) or C_Item.GetItemInfoInstant(rest)
		if not itemID then
			SlashError("Unknown item \"" .. rest .. "\". Shift-click the item to paste its link.")
			return
		end
		goal = { type = "item", itemID = itemID, target = count }
	end

	AddGoal(goal)
	ns:Print("Goal added: " .. (Describe(goal)) .. ". Right-click it in the tracker for options.")
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local ticker

-- Counts each running goal's online time and refreshes rates once a second.
local function Tick()
	local any = false
	for _, goal in ipairs(GetData().goals) do
		if not goal.paused and not goal.completed then
			goal.active = (goal.active or 0) + 1
			any = true
		end
	end
	if any then
		UpdateTracker()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_LOOT" then
		OnLootMessage(...)
	elseif event == "PLAYER_XP_UPDATE" then
		OnXPUpdate()
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif POLL_EVENTS[event] then
		Poll(POLL_EVENTS[event])
	else -- combat start/end
		if event == "PLAYER_REGEN_ENABLED" then
			ReplayCombatToasts()
		end
		UpdateTracker()
	end
end)

-- PLAYER_XP_UPDATE also fires on a level up (with the new level), so PLAYER_LEVEL_UP isn't needed.
local EVENTS = { "CHAT_MSG_LOOT", "PLAYER_XP_UPDATE", "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
for event in pairs(POLL_EVENTS) do
	table.insert(EVENTS, event)
end

function module:OnInitialize()
	local realm = GetNormalizedRealmName() or GetRealmName()
	characterKey = ns:PlayerName() .. "-" .. realm
	-- Goals used to be saved under the first name alone, which two characters can share.
	local oldKey = UnitName("player") .. "-" .. realm
	local saved = NraKitDB.farmGoalsData
	if saved and oldKey ~= characterKey and saved[oldKey] and not saved[characterKey] then
		saved[characterKey], saved[oldKey] = saved[oldKey], nil
	end
	-- The finish sound's default changed from Epic loot to World quest complete; move
	-- anyone still on the old default (once).
	-- Milestone chimes are now off by default; turn off the old default once.
	if not NraKitDB.farmGoalsMilestoneSoundUpdated then
		NraKitDB.farmGoalsMilestoneSound = false
		NraKitDB.farmGoalsMilestoneSoundUpdated = true
	end
	-- Icons per row's default went from 6 to 3, likewise.
	if not NraKitDB.farmGoalsIconsPerRowUpdated then
		if NraKitDB.farmGoalsIconsPerRow == 6 then
			NraKitDB.farmGoalsIconsPerRow = 3
		end
		NraKitDB.farmGoalsIconsPerRowUpdated = true
	end
	if not NraKitDB.farmGoalsFinishSoundUpdated then
		if NraKitDB.farmGoalsCompleteSoundChoice == "kit:UI_EPICLOOT_TOAST" then
			NraKitDB.farmGoalsCompleteSoundChoice = "kit:UI_WORLDQUEST_COMPLETE"
		end
		NraKitDB.farmGoalsFinishSoundUpdated = true
	end
	ns:RegisterSlashCommand("goal", OnSlashCommand, SLASH_HELP)
	ns:RegisterSlashCommand("goals", OnSlashCommand, SLASH_HELP)
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
		lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
		lastMoney = GetMoney()
		ResyncPolled()
		ticker = ticker or C_Timer.NewTicker(1, Tick)
	elseif ticker then
		ticker:Cancel()
		ticker = nil
	end
	UpdateTracker()
end

function module:OnOptionChanged()
	UpdateTracker()
end

ns:RegisterModule(module)
