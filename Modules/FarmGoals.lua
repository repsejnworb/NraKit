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
			default = "kit:UI_EPICLOOT_TOAST",
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
			name = "Width",
			description = "Width of the tracker.",
			default = 260, min = 180, max = 420, step = 10,
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
	complete = { "farmGoalsCompleteSound", "farmGoalsCompleteSoundChoice", "kit:UI_EPICLOOT_TOAST" },
	tick = { "farmGoalsTickSound", "farmGoalsTickSoundChoice", "kit:LOOT_WINDOW_COIN_SOUND" },
}

local characterKey
local lastXP, lastXPMax, lastLevel, lastMoney
local tracker, toast
local rows = {}
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

local function OpenMenu(row)
	local goal = row.goal and FindGoal(row.goal.id)
	if not (goal and MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MenuUtil.CreateContextMenu(row, function(_, root)
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

local function CreateRow(index)
	local row = CreateFrame("Button", nil, tracker)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- Dragging a row moves the whole tracker.
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function()
		tracker:GetScript("OnDragStart")(tracker)
	end)
	row:SetScript("OnDragStop", function()
		tracker:GetScript("OnDragStop")(tracker)
	end)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.flash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.flash:SetAllPoints()
	row.flash:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.18)
	row.flash:SetAlpha(0)

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

	row.track = CreateFrame("StatusBar", nil, row)
	row.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	row.track:SetMinMaxValues(0, 1)
	row.track:SetHeight(4)
	row.track:SetPoint("LEFT", row.icon, "RIGHT", 8, -2)
	row.track:SetPoint("RIGHT", -8, 0)
	row.track.bg = row.track:CreateTexture(nil, "BACKGROUND")
	row.track.bg:SetAllPoints()
	row.track.bg:SetColorTexture(1, 1, 1, 0.12)

	row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -2)
	row.info:SetPoint("RIGHT", -8, 0)
	row.info:SetJustifyH("LEFT")
	row.info:SetWordWrap(false)

	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenMenu(self)
		elseif IsModifiedClick("CHATLINK") and self.goal and self.goal.itemID then
			local link = select(2, C_Item.GetItemInfo(self.goal.itemID))
			if link then
				ChatFrameUtil.InsertLink(link)
			end
		end
	end)
	row:SetScript("OnEnter", function(self)
		local goal = self.goal
		if not goal then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if goal.itemID then
			GameTooltip:SetItemByID(goal.itemID)
			GameTooltip:AddLine(" ")
		else
			GameTooltip_SetTitle(GameTooltip, (Describe(goal)))
		end
		if goal.start and goal.start > 0 then
			GameTooltip:AddDoubleLine("Started from", TYPES[goal.type].format(goal.start), 1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Running for", FormatDuration(goal.active or 0), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnUpdate", function(self)
		local flashAt = self.goal and self.goal.flashAt
		local age = flashAt and GetTime() - flashAt
		self.flash:SetAlpha(age and age < 0.6 and (1 - age / 0.6) or 0)
	end)
	return row
end

local function SavePosition()
	local point, _, relativePoint, x, y = tracker:GetPoint()
	NraKitDB.farmGoalsPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
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

	local add = UI.CreateFlatButton(header, "+", 16)
	add:SetWidth(18)
	add:SetPoint("RIGHT", -3, 0)
	add:SetScript("OnClick", function()
		ns:OpenGoalsWindow("new")
	end)
	add:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "New goal", "Open the goals window.")
	end)
	add:SetScript("OnLeave", GameTooltip_Hide)

	local collapse = UI.CreateFlatButton(header, "-", 16)
	collapse:SetWidth(18)
	collapse:SetPoint("RIGHT", add, "LEFT", -2, 0)
	collapse:SetScript("OnClick", function()
		NraKitDB.farmGoalsCollapsed = not NraKitDB.farmGoalsCollapsed or nil
		UpdateTracker()
	end)
	tracker.collapse = collapse

	tracker.more = tracker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tracker.more:SetPoint("BOTTOM", 0, 4)
end

-- Unfinished goals first (pinned order otherwise), then finished ones.
local function SortedGoals()
	local list = {}
	for _, goal in ipairs(GetData().goals) do
		table.insert(list, goal)
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
	local goals = SortedGoals()
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

	local width = ns:GetValue("farmGoalsWidth") or 260
	tracker:SetWidth(width)
	tracker:SetScale((ns:GetValue("farmGoalsScale") or 100) / 100)

	local running = 0
	for _, goal in ipairs(goals) do
		if not goal.completed then
			running = running + 1
		end
	end
	tracker.title:SetText(string.format("GOALS  |cff808080%d/%d|r", #goals - running, #goals))
	local collapsed = NraKitDB.farmGoalsCollapsed
	tracker.collapse.text:SetText(collapsed and "+" or "-")

	local shown = collapsed and 0 or math.min(#goals, MAX_ROWS)
	for index = 1, math.max(shown, #rows) do
		local row = rows[index]
		local goal = goals[index]
		if index <= shown then
			row = row or CreateRow(index)
			rows[index] = row
			row.goal = goal
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
			row:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)

			local name, icon = Describe(goal)
			local fraction, value = GetProgress(goal)
			row.icon:SetTexture(icon)
			row.icon:SetDesaturated(goal.paused and true or false)
			row.name:SetText(name)
			row.value:SetText(value)
			row.track:SetValue(math.min(math.max(fraction, 0), 1))
			row.info:SetText(DescribeRate(goal))
			if goal.completed then
				row.track:SetStatusBarColor(unpack(DONE_COLOR))
				row.name:SetTextColor(unpack(DONE_COLOR))
			elseif goal.paused then
				row.track:SetStatusBarColor(unpack(PAUSED_COLOR))
				row.name:SetTextColor(unpack(UI.GREY))
			else
				row.track:SetStatusBarColor(unpack(UI.ACCENT))
				row.name:SetTextColor(unpack(UI.GOLD))
			end
			row:Show()
		elseif row then
			row:Hide()
		end
	end

	local hidden = collapsed and 0 or #goals - shown
	tracker.more:SetText(hidden > 0 and string.format("+%d more  (/nra goal)", hidden) or "")
	tracker:SetHeight(HEADER_HEIGHT + shown * ROW_HEIGHT + (hidden > 0 and 18 or 0))
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

-- /nra goal 4000 [Silk Cloth] | /nra goal level 40 | /nra goal xp 50000 | /nra goal gold 100
local function OnSlashCommand(input)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Farm goals first (/nra).")
		return
	end
	local first, rest = input:match("^(%S*)%s*(.-)$")
	first = first:lower()
	local amount = tonumber(rest and rest:match("^(%d+)"))
	if first == "level" and amount then
		AddGoal({ type = "level", target = amount })
	elseif first == "xp" and amount then
		AddGoal({ type = "xp", target = amount })
	elseif first == "gold" and amount then
		AddGoal({ type = "gold", target = amount * 10000 })
	elseif tonumber(first) and rest ~= "" then
		local itemID = tonumber(rest:match("item:(%d+)")) or C_Item.GetItemInfoInstant(rest)
		if not itemID then
			ns:Print("Unknown item \"" .. rest .. "\". Shift-click the item to paste its link, or use the goals window.")
			return
		end
		AddGoal({ type = "item", itemID = itemID, target = tonumber(first) })
	else
		ns:OpenGoalsWindow()
		return
	end
	ns:Print("Goal added. Right-click it in the tracker for options.")
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
	ns:RegisterSlashCommand("goal", OnSlashCommand)
	ns:RegisterSlashCommand("goals", OnSlashCommand)
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
