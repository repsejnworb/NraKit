local _, ns = ...

-- Farm goals: "loot 4000 Silk Cloth", "reach level 40", "gain 50,000 XP", "have 100g",
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
	name = "Farm goals",
	description = "Set farming goals (loot 4000 Silk Cloth, reach level 40, earn 100 gold, reach Revered, Swords to 300, a currency) and track them in a small movable window with rate per hour, time left and a fanfare when done. /nra goal opens the goals window.",
	default = false,
	options = {
		{
			key = "farmGoalsMilestoneSound",
			header = "Sounds",
			name = "Milestone chimes",
			description = "Play a sound at 25%, 50% and 75% of a goal. A goal can have its own sound (Edit in the goals window).",
			default = true,
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
			key = "farmGoalsCountCrafted",
			header = "Counting",
			name = "Count crafted items",
			description = "Items you make (\"You create: ...\") count towards item goals, not just looted ones.",
			default = false,
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
			description = "Width of the tracker in the Full view. Switch views with the tracker's F / C / I button.",
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
			description = "How many goals per row in the Icons view before it wraps.",
			default = 6, min = 2, max = 12, step = 1,
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

local ICONS = {
	level = "Interface\\Icons\\Achievement_Level_10",
	xp = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
	gold = "Interface\\Icons\\INV_Misc_Coin_02",
	rep = "Interface\\Icons\\Achievement_Reputation_01",
	skill = "Interface\\Icons\\Ability_Warrior_WeaponMastery",
	currency = "Interface\\Icons\\INV_Misc_Token_ArgentDawn",
}

-- Goal sounds: which -> { on/off option, sound option, default sound }.
local SOUNDS = {
	milestone = { "farmGoalsMilestoneSound", "farmGoalsMilestoneSoundChoice", "kit:UI_QUEST_ROLLING_FORWARD_01" },
	complete = { "farmGoalsCompleteSound", "farmGoalsCompleteSoundChoice", "kit:UI_WORLDQUEST_COMPLETE" },
	tick = { "farmGoalsTickSound", "farmGoalsTickSoundChoice", "kit:LOOT_WINDOW_COIN_SOUND" },
}

local characterKey
local lastXP, lastXPMax, lastLevel, lastMoney
local tracker, toast
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

-- "12g 30s", "45s", "7c": compact, no icons.
local function FormatGold(copper)
	copper = math.floor(copper)
	local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
	if gold > 0 then
		return silver > 0 and string.format("%sg %ds", FormatNumber(gold), silver) or FormatNumber(gold) .. "g"
	elseif silver > 0 then
		return silver .. "s"
	end
	return (copper % 100) .. "c"
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
		return "Have " .. FormatGold(goal.target), ICONS.gold
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
		return "Reach level " .. goal.target, ICONS.level
	end,
	progress = function(goal)
		local level, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
		local now = level + (max > 0 and xp / max or 0)
		local start = goal.startLevel or level
		local fraction = level >= goal.target and 1 or ReachFraction(now, start, goal.target)
		local remaining = math.max(0, (max - xp) + (goal.target - level - 1) * max)
		return fraction, string.format("Level %d (%d%%) / %d", level, max > 0 and xp / max * 100 or 0, goal.target), remaining
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
		return name, ICONS.rep
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
		return name, ICONS.skill
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

-- Name and icon of a goal, for the tracker, window and messages.
local function Describe(goal)
	return TYPES[goal.type].describe(goal)
end

-- Fraction done (0..1), "1,512 / 4,000" and the amount still to go.
local function GetProgress(goal)
	return TYPES[goal.type].progress(goal)
end

-- "+312 looted · 820/h · ~3h 22m left"
local function DescribeRate(goal)
	if goal.completed then
		return "Done in " .. FormatDuration(goal.active or 0)
	end
	local goalType = TYPES[goal.type]
	local format = goalType.format
	local gained = goal.gained or 0
	local parts = { "+" .. format(gained) .. (goalType.gainedSuffix or "") }
	local active = goal.active or 0
	if active >= 60 and gained > 0 then
		local perHour = gained / active * 3600
		table.insert(parts, format(perHour) .. "/h")
		local _, _, remaining = GetProgress(goal)
		if remaining > 0 then
			table.insert(parts, "~" .. FormatDuration(remaining / perHour * 3600) .. " left")
		end
	end
	if goal.paused then
		table.insert(parts, "paused")
	end
	return table.concat(parts, "  ·  ")
end

------------------------------------------------------------------------------
-- Completion message
------------------------------------------------------------------------------

local function ShowToast(goal)
	if not toast then
		toast = CreateFrame("Frame", nil, UIParent)
		toast:SetSize(600, 80)
		toast:SetPoint("CENTER", 0, 260)
		toast:SetFrameStrata("HIGH")
		toast.heading = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		toast.heading:SetPoint("TOP")
		toast.heading:SetTextColor(unpack(DONE_COLOR))
		toast.heading:SetText("GOAL COMPLETE")
		toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		toast.text:SetPoint("TOP", toast.heading, "BOTTOM", 0, -6)
		toast.text:SetTextColor(1, 1, 1)
		toast.detail = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		toast.detail:SetPoint("TOP", toast.text, "BOTTOM", 0, -6)
		toast.detail:SetTextColor(unpack(UI.TEXT))
		toast:SetScript("OnUpdate", function(self)
			local age = GetTime() - self.shownAt
			if age > 5 then
				self:Hide()
			elseif age > 4 then
				self:SetAlpha(5 - age)
			end
		end)
	end
	local name = Describe(goal)
	if goal.type == "item" then
		name = FormatNumber(goal.target) .. " " .. name
	end
	toast.text:SetText(name)
	toast.detail:SetText("in " .. FormatDuration(goal.active or 0))
	toast.shownAt = GetTime()
	toast:SetAlpha(1)
	toast:Show()
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
local function RemoveGoal(id)
	local data = GetData()
	local goal, index = FindGoal(id)
	if not goal then
		return
	end
	table.remove(data.goals, index)
	if goal.completed then
		local name = Describe(goal)
		table.insert(data.history, 1, {
			type = goal.type, name = name, target = goal.target, itemID = goal.itemID, key = goal.key,
			mode = goal.mode, toMax = goal.toMax, created = goal.created, completed = goal.completed,
			active = goal.active,
		})
	end
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
local VIEW_LETTERS = { full = "F", compact = "C", icons = "I" }
local COMPACT_HEIGHT = 24
local MAX_COMPACT_ROWS = 12
local MAX_ICONS = 30

local function GetView()
	local view = NraKitDB.farmGoalsView
	return VIEW_LABELS[view] and view or "full"
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
		return FormatNumber(math.floor(value / 10000)) .. "g"
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

local function ShowGoalTooltip(widget)
	local goal = widget.goal
	if not goal then
		return
	end
	GameTooltip:SetOwner(widget, "ANCHOR_LEFT")
	if goal.itemID then
		GameTooltip:SetItemByID(goal.itemID)
		GameTooltip:AddLine(" ")
	else
		GameTooltip_SetTitle(GameTooltip, (Describe(goal)))
	end
	local _, value = GetProgress(goal)
	GameTooltip:AddDoubleLine("Progress", value, 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(DescribeRate(goal), 0.8, 0.8, 0.8, true)
	if goal.start and goal.start > 0 then
		GameTooltip:AddDoubleLine("Started from", TYPES[goal.type].format(goal.start), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Running for", FormatDuration(goal.active or 0), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
	GameTooltip:Show()
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
	widget:SetScript("OnUpdate", function(self)
		local flashAt = self.goal and self.goal.flashAt
		local age = flashAt and GetTime() - flashAt
		self.flash:SetAlpha(age and age < 0.6 and (1 - age / 0.6) or 0)
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

function LAYOUT.full(goals)
	local shown = math.min(#goals, MAX_ROWS)
	for index = 1, shown do
		local goal, row = goals[index], GetWidget("full", index)
		row.goal = goal
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
		local name, icon = Describe(goal)
		local _, value = GetProgress(goal)
		row.icon:SetTexture(icon)
		row.name:SetText(name)
		row.value:SetText(value)
		row.info:SetText(DescribeRate(goal))
		ApplyState(row, goal)
		row:Show()
	end
	return ns:GetValue("farmGoalsWidth") or 260, shown * ROW_HEIGHT, shown
end

function LAYOUT.compact(goals)
	local shown = math.min(#goals, MAX_COMPACT_ROWS)
	for index = 1, shown do
		local goal, row = goals[index], GetWidget("compact", index)
		row.goal = goal
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - (index - 1) * COMPACT_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT - (index - 1) * COMPACT_HEIGHT)
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

function LAYOUT.icons(goals)
	local size = ns:GetValue("farmGoalsIconSize") or 32
	local perRow = ns:GetValue("farmGoalsIconsPerRow") or 6
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
		tile:SetPoint("TOPLEFT", pad + column * (size + gap), -HEADER_HEIGHT - pad - row * (size + labelHeight + gap))
		local _, icon = Describe(goal)
		tile.icon:SetTexture(icon)
		tile.icon:SetAlpha(goal.paused and 0.6 or 1)
		tile.count:SetText(ShortAmount(goal))
		tile.done:SetShown(goal.completed ~= nil)
		ApplyState(tile, goal)
		tile:Show()
	end
	local rows = math.ceil(shown / columns)
	local width = math.max(120, pad * 2 + columns * size + (columns - 1) * gap)
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
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_HEIGHT)
	UI.AddLine(header, "BOTTOM")
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

	tracker.view = HeaderButton(header, "F", function()
		return "View: " .. VIEW_LABELS[GetView()]
	end, "Click to switch between Full, Compact (one line per goal) and Icons.", function()
		local current = GetView()
		for index, view in ipairs(VIEWS) do
			if view == current then
				NraKitDB.farmGoalsView = VIEWS[index % #VIEWS + 1]
			end
		end
		UpdateTracker()
		GameTooltip_Hide()
	end)
	tracker.view:SetPoint("RIGHT", tracker.collapse, "LEFT", -2, 0)

	tracker.more = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tracker.more:SetPoint("BOTTOM", 0, 4)
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
	tracker.view.text:SetText(VIEW_LETTERS[view])

	local width, height, shown = 0, 0, 0
	if not collapsed then
		width, height, shown = LAYOUT[view](goals)
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
	tracker:SetHeight(HEADER_HEIGHT + height + (hidden > 0 and 18 or 0))
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
-- only the target, sounds and (if recount) the starting count change.
local function EditGoal(id, changes, recount)
	local goal = FindGoal(id)
	if not goal then
		return
	end
	local changedThing = goal.itemID ~= changes.itemID or goal.key ~= changes.key
		or (goal.mode or "reach") ~= (changes.mode or "reach")
	goal.itemID, goal.key, goal.name, goal.mode = changes.itemID, changes.key, changes.name or goal.name, changes.mode
	goal.target, goal.toMax, goal.sounds = changes.target, changes.toMax, changes.sounds
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
	GetProgress = GetProgress,
	DescribeRate = DescribeRate,
	FormatNumber = FormatNumber,
	FormatGold = FormatGold,
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
	summary = "Farm goals: open the goals window, or add a goal straight from chat",
	usage = {
		"/nra goal - open the goals window",
		"/nra goal list - list your goals and where they stand",
		"/nra goal <count> <item> - loot that many of an item (shift-click the item to paste it)",
		"/nra goal level <level> - reach a level",
		"/nra goal xp <amount> - gain that much XP",
		"/nra goal gold <amount> - have that much gold (counting what you gain from now)",
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
		ns:Print("Turn on Farm goals first (/nra).")
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
	elseif first == "level" or first == "xp" or first == "gold" then
		local amount = tonumber(rest:match("^(%d+)"))
		if not amount then
			SlashError("Give a number, e.g. /nra goal " .. first .. " " .. (first == "level" and "40" or "100") .. ".")
			return
		elseif first == "level" and amount <= UnitLevel("player") then
			SlashError("You're already level " .. UnitLevel("player") .. ".")
			return
		end
		goal = { type = first, target = first == "gold" and amount * 10000 or amount }
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
		UpdateTracker()
	end
end)

-- PLAYER_XP_UPDATE also fires on a level up (with the new level), so PLAYER_LEVEL_UP isn't needed.
local EVENTS = { "CHAT_MSG_LOOT", "PLAYER_XP_UPDATE", "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
for event in pairs(POLL_EVENTS) do
	table.insert(EVENTS, event)
end

function module:OnInitialize()
	characterKey = UnitName("player") .. "-" .. (GetNormalizedRealmName() or GetRealmName())
	-- The finish sound's default changed from Epic loot to World quest complete; move
	-- anyone still on the old default (once).
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
