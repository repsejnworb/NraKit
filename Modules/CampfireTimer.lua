local _, ns = ...

-- Campfire timer: a progress bar in the middle of the screen while you rest at a
-- campfire (the "Welcoming Campfire" buff), so you can see when you're done without
-- watching the buff icon. When the rest finishes you get "Camp Benefits"; the bar then
-- turns green, says so for a few seconds and fades out. Walking away early just hides it.
-- The look is borrowed from Leatrix Plus's flight progress bar.
--
-- Sleeping bags too: while you're in one ("Resting") you gain stacks of Well-Rested, and the
-- bar waits for 3. The game doesn't say how often a stack comes, so the bar counts stacks
-- and learns the time between them from your rests (saved), then shows the time left too.

local module = {
	key = "campfireTimer",
	section = "Trackers & Reminders",
	name = "Campfire timer",
	description = "Show a progress bar in the middle of the screen while you rest at a Welcoming Campfire or in a sleeping bag.",
	default = false,
	options = {
		{
			key = "campfireTimerSleepingBag",
			header = "General",
			name = "Sleeping bags",
			description = "Also show the bar while you rest in a sleeping bag, until you have 3 stacks of Well-Rested.",
			default = true,
		},
		{
			key = "campfireTimerSound",
			name = "Sound when done",
			description = "Play a sound when the rest is finished.",
			default = true,
		},
		{
			key = "campfireTimerSoundChoice",
			parent = "campfireTimerSound",
			type = "sound",
			name = "Sound",
			description = "Which sound to play when the rest is finished.",
			default = "kit:READY_CHECK",
		},
		{
			key = "campfireTimerWidth",
			header = "Appearance",
			type = "number",
			name = "Width",
			description = "Width of the bar.",
			default = 260, min = 120, max = 600, step = 10,
		},
		{
			key = "campfireTimerOffsetY",
			type = "number",
			name = "Height on screen",
			description = "How far above (or below, if negative) the middle of the screen the bar is shown.",
			default = 160, min = -400, max = 400, step = 10,
		},
	},
}

-- Two spells carry the name "Welcoming Campfire"; 1229739 is the rest buff.
local REST_SPELLS = { 1229739, 1289723 }
local CAMP_BENEFITS = 1229741
local SLEEPING_BAG = 1331671 -- "Resting": while you're in a sleeping bag
local WELL_RESTED = 429959
local WELL_RESTED_GOAL = 3

local TITLE = "Welcoming Campfire"
local DONE_TEXT = "Camp Benefits ready"
local BAG_TITLE = "Well-Rested"
local BAG_DONE_TEXT = "Fully Well-Rested"
local FILL_COLOR = { 1, 0.6, 0.2 }
local DONE_COLOR = { 0.3, 0.85, 0.3 }
local DONE_SHOW_SECONDS = 3
local FADE_SECONDS = 1
local PREVIEW_SECONDS = 10
local PREVIEW_STACK_SECONDS = 3

local bar
-- While the bar counts down (or a preview runs):
--   campfire: { start, finish }
--   bag:      { bag = true, stacks, changedAt (when the last stack came, or you got in), interval? }
local resting
local doneAt -- GetTime() when the "done" message started
local inBag -- in a sleeping bag at the last look

-- Seconds between Well-Rested stacks, learned from your rests; nil until one is seen.
local function StackInterval()
	return NraKitDB.campfireTimerData and NraKitDB.campfireTimerData.wellRestedInterval
end

local function LearnStackInterval(seconds)
	NraKitDB.campfireTimerData = NraKitDB.campfireTimerData or {}
	NraKitDB.campfireTimerData.wellRestedInterval = seconds
end

local function Plain(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

local function GetRestAura()
	for _, spellID in ipairs(REST_SPELLS) do
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
		if aura then
			return aura
		end
	end
end

local function FormatTime(seconds)
	seconds = math.ceil(math.max(seconds, 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function MakeText(justify)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH(justify)
	text:SetWordWrap(false)
	return text
end

local function OnUpdateBag(now)
	local interval = resting.interval or StackInterval()
	local count = string.format("%d/%d", resting.stacks, WELL_RESTED_GOAL)
	if interval and interval > 0 then
		local into = math.min((now - resting.changedAt) / interval, 0.99)
		bar.track:SetValue((resting.stacks + into) / WELL_RESTED_GOAL)
		local left = interval * (WELL_RESTED_GOAL - resting.stacks) - (now - resting.changedAt)
		bar.time:SetText(count .. "  " .. FormatTime(left))
	else
		bar.track:SetValue(resting.stacks / WELL_RESTED_GOAL)
		bar.time:SetText(count)
	end
end

local function OnUpdate()
	local now = GetTime()
	if resting and resting.bag then
		OnUpdateBag(now)
	elseif resting then
		local total = resting.finish - resting.start
		local progress = total > 0 and (now - resting.start) / total or 1
		bar.track:SetValue(math.min(math.max(progress, 0), 1))
		bar.time:SetText(FormatTime(resting.finish - now))
	elseif doneAt then
		local fade = now - doneAt - DONE_SHOW_SECONDS
		if fade >= FADE_SECONDS then
			doneAt = nil
			bar:Hide()
		elseif fade > 0 then
			bar:SetAlpha(1 - fade / FADE_SECONDS)
		end
	end
end

local function EnsureBar()
	if bar then
		return
	end
	bar = CreateFrame("Frame", nil, UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar:SetHeight(38)
	bar:EnableMouse(false)
	bar:Hide()

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.04, 0.04, 0.06, 0.75)

	-- Hairline border
	local edges = {}
	for i = 1, 4 do
		edges[i] = bar:CreateTexture(nil, "BORDER")
		edges[i]:SetColorTexture(1, 1, 1, 0.1)
	end
	edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)

	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetSize(26, 26)
	bar.icon:SetPoint("LEFT", 6, 0)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	bar.title = MakeText("LEFT")
	bar.title:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 8, -1)
	bar.time = MakeText("RIGHT")
	bar.time:SetPoint("TOPRIGHT", -8, -7)
	bar.time:SetTextColor(0.9, 0.9, 0.9)
	bar.title:SetPoint("RIGHT", bar.time, "LEFT", -6, 0)

	bar.track = CreateFrame("StatusBar", nil, bar)
	bar.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar.track:SetMinMaxValues(0, 1)
	bar.track:SetHeight(5)
	bar.track:SetPoint("BOTTOMLEFT", bar.icon, "BOTTOMRIGHT", 8, 1)
	bar.track:SetPoint("RIGHT", -8, 0)
	bar.track.bg = bar.track:CreateTexture(nil, "BACKGROUND")
	bar.track.bg:SetAllPoints()
	bar.track.bg:SetColorTexture(1, 1, 1, 0.12)

	bar.spark = bar.track:CreateTexture(nil, "OVERLAY")
	bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	bar.spark:SetBlendMode("ADD")
	bar.spark:SetSize(12, 20)
	bar.spark:SetPoint("CENTER", bar.track:GetStatusBarTexture(), "RIGHT")

	bar:SetScript("OnUpdate", OnUpdate)
end

local function ApplyLayout()
	bar:SetWidth(ns:GetValue("campfireTimerWidth") or 260)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", 0, ns:GetValue("campfireTimerOffsetY") or 160)
end

local function ShowBar(state, title, icon)
	EnsureBar()
	ApplyLayout()
	resting = state
	doneAt = nil
	bar.icon:SetTexture(icon)
	bar.title:SetText(title)
	bar.title:SetTextColor(1, 0.82, 0)
	bar.track:SetStatusBarColor(unpack(FILL_COLOR))
	bar.spark:Show()
	bar:SetAlpha(1)
	bar:Show()
	if state then
		OnUpdate()
	end
end

local function ShowResting(start, finish, icon)
	ShowBar({ start = start, finish = finish }, TITLE, icon or C_Spell.GetSpellTexture(REST_SPELLS[1]))
end

local function ShowBag(stacks)
	ShowBar({ bag = true, stacks = stacks, changedAt = GetTime() }, BAG_TITLE, C_Spell.GetSpellTexture(WELL_RESTED))
end

-- silent: no sound (already done when you got in, so nothing was waited for).
local function ShowDone(text, silent)
	if not bar or not bar:IsShown() then
		ShowBar(nil, "", C_Spell.GetSpellTexture(WELL_RESTED))
	end
	resting = nil
	doneAt = GetTime()
	bar:SetAlpha(1)
	bar.title:SetText(text or DONE_TEXT)
	bar.title:SetTextColor(unpack(DONE_COLOR))
	bar.time:SetText("")
	bar.track:SetValue(1)
	bar.track:SetStatusBarColor(unpack(DONE_COLOR))
	bar.spark:Hide()
	if not silent and ns:GetOption("campfireTimerSound") then
		ns.sounds.PlayOption("campfireTimerSoundChoice", "kit:READY_CHECK")
	end
end

local function Stop()
	resting = nil
	doneAt = nil
	if bar then
		bar:Hide()
	end
end

local function WellRestedStacks()
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(WELL_RESTED)
	if not aura then
		return 0
	end
	return math.max(Plain(aura.applications) or 0, 1)
end

-- In a sleeping bag: count Well-Rested stacks up to the goal.
local function UpdateBag()
	local stacks = WellRestedStacks()
	local gotIn = not inBag
	inBag = true
	local watching = resting and resting.bag
	if watching and stacks > resting.stacks then
		LearnStackInterval(GetTime() - resting.changedAt)
	end
	if stacks >= WELL_RESTED_GOAL then
		if watching then
			ShowDone(BAG_DONE_TEXT)
		elseif gotIn then
			ShowDone(BAG_DONE_TEXT, true)
		end
	elseif not watching then
		ShowBag(stacks)
	elseif stacks ~= resting.stacks then
		resting.stacks = stacks
		resting.changedAt = GetTime()
	end
end

local function Update()
	if not ns:IsModuleEnabled(module.key) then
		inBag = nil
		Stop()
		return
	end
	if resting and resting.preview then
		return
	end
	if ns:GetOption("campfireTimerSleepingBag") and C_UnitAuras.GetPlayerAuraBySpellID(SLEEPING_BAG) then
		UpdateBag()
		return
	end
	inBag = nil
	if resting and resting.bag then
		Stop() -- got out before the last stack
		return
	end
	local aura = GetRestAura()
	local finish = aura and Plain(aura.expirationTime)
	local duration = aura and Plain(aura.duration)
	if finish and duration and finish > 0 and duration > 0 then
		if not resting or resting.finish ~= finish then
			ShowResting(finish - duration, finish, Plain(aura.icon))
		end
	elseif resting then
		-- The buff is gone: finished if it ran out (or Camp Benefits arrived), else we left early.
		local finished = GetTime() >= resting.finish - 1 or C_UnitAuras.GetPlayerAuraBySpellID(CAMP_BENEFITS) ~= nil
		if finished then
			ShowDone()
		else
			Stop()
		end
	end
end

-- /nra campfire: a short fake rest, to see (and place) the bar.
local function Preview()
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Campfire timer is turned off.")
		return
	end
	local now = GetTime()
	ShowResting(now, now + PREVIEW_SECONDS)
	resting.preview = true
	C_Timer.After(PREVIEW_SECONDS, function()
		if resting and resting.preview then
			ShowDone()
		end
	end)
end

ns:RegisterPreview("campfire", "Campfire timer: a 10-second rest (same as /nra campfire)", Preview)

-- A sleeping bag rest with a stack every few seconds.
local function PreviewBag()
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Campfire timer is turned off.")
		return
	end
	ShowBag(0)
	resting.preview = true
	resting.interval = PREVIEW_STACK_SECONDS
	local function NextStack()
		if not (resting and resting.preview and resting.bag) then
			return
		end
		resting.stacks = resting.stacks + 1
		resting.changedAt = GetTime()
		if resting.stacks >= WELL_RESTED_GOAL then
			ShowDone(BAG_DONE_TEXT)
		else
			C_Timer.After(PREVIEW_STACK_SECONDS, NextStack)
		end
	end
	C_Timer.After(PREVIEW_STACK_SECONDS, NextStack)
end

ns:RegisterPreview("sleepingbag", "Campfire timer: resting in a sleeping bag until 3 stacks of Well-Rested", PreviewBag)

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", Update)

function module:OnInitialize()
	eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	ns:RegisterSlashCommand("campfire", Preview, {
		summary = "Campfire timer: show a 10-second preview of the bar",
		usage = { "/nra campfire - preview the campfire bar (to check its look and position)" },
	})
	Update()
end

function module:OnEnabledChanged()
	Update()
end

function module:OnOptionChanged()
	if bar then
		ApplyLayout()
	end
end

ns:RegisterModule(module)
