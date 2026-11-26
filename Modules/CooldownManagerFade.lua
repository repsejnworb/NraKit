local _, ns = ...

-- Cooldown Manager fade: the game's Cooldown Manager bars (Essential and Utility Cooldowns,
-- Tracked Buffs, Tracked Bars) show in combat and fade out a while after it, instead of the
-- game's on/off "In combat". Optionally also with a hostile target and while the mouse is
-- over a bar. Every change is an animated fade.
--
-- The bars are set to Always in Edit Mode, and this only changes their opacity: visible is
-- the Edit Mode opacity (read after the game sets it), faded is that times "Faded opacity".
-- The Cooldown Manager shows secret values in combat, so its Lua methods and fields are never
-- written: only SetAlpha on its frames, and a post-hook to learn the Edit Mode opacity.

local module = {
	key = "cooldownManagerFade",
	section = "Utilities",
	name = "Cooldown Manager fade",
	description = "The game's Cooldown Manager bars show in combat and fade out a while after it (animated), instead of just vanishing. Set the bars to \"Always\" in Edit Mode: one set to \"In combat\" is hidden by the game before it can fade.",
	default = false,
	options = {
		{
			key = "cooldownFadeEssential",
			header = "Bars",
			name = "Essential Cooldowns",
			description = "Fade the Essential Cooldowns bar.",
			default = true,
		},
		{
			key = "cooldownFadeUtility",
			name = "Utility Cooldowns",
			description = "Fade the Utility Cooldowns bar.",
			default = true,
		},
		{
			key = "cooldownFadeBuffs",
			name = "Tracked Buffs",
			description = "Fade the Tracked Buffs icons.",
			default = false,
		},
		{
			key = "cooldownFadeBuffBars",
			name = "Tracked Bars",
			description = "Fade the Tracked Bars.",
			default = false,
		},
		{
			key = "cooldownFadeStay",
			header = "Fading",
			type = "number",
			name = "Stay after combat",
			description = "How long the bars stay after combat before they start to fade.",
			default = 10,
			min = 0,
			max = 120,
			step = 1,
			format = function(value)
				return value .. " sec"
			end,
		},
		{
			key = "cooldownFadeDuration",
			type = "number",
			name = "Fade over",
			description = "How long fading out takes.",
			default = 2,
			min = 0.5,
			max = 60,
			step = 0.5,
			format = function(value)
				return value .. " sec"
			end,
		},
		{
			key = "cooldownFadeOpacity",
			type = "number",
			name = "Faded opacity",
			description = "How visible the bars are once faded: 0% is gone, more leaves a faint trace of them.",
			default = 0,
			min = 0,
			max = 0.8,
			step = 0.05,
			format = function(value)
				return math.floor(value * 100 + 0.5) .. "%"
			end,
		},
		{
			key = "cooldownFadeTarget",
			header = "Also show",
			name = "With a hostile target",
			description = "Show the bars while you have a living enemy targeted, out of combat too (lining up a pull).",
			default = true,
		},
		{
			key = "cooldownFadeTargetNow",
			parent = "cooldownFadeTarget",
			name = "Fade right away when you lose it",
			description = "Out of combat, dropping the target starts the fade at once, instead of after \"Stay after combat\".",
			default = true,
		},
		{
			key = "cooldownFadeHover",
			name = "While the mouse is over a bar",
			description = "A faded bar comes back while the mouse is over it.",
			default = true,
		},
	},
}

local VIEWERS = {
	{ option = "cooldownFadeEssential", frame = "EssentialCooldownViewer" },
	{ option = "cooldownFadeUtility", frame = "UtilityCooldownViewer" },
	{ option = "cooldownFadeBuffs", frame = "BuffIconCooldownViewer" },
	{ option = "cooldownFadeBuffBars", frame = "BuffBarCooldownViewer" },
}
local FADE_IN_SECONDS = 0.4
local HOVER_GRACE = 0.5 -- passing over a bar doesn't make it blink

local fade = {}
ns.cooldownFade = fade

local inCombat = false
local holdUntil = 0 -- shown until then (after combat, after losing the target)
local hadTarget = false

-- Per frame: { base = Edit Mode opacity, amount = 0 (faded) .. 1 (shown), hoverUntil, hooked }.
local states = {}

local function HostileTarget()
	if not UnitExists("target") then
		return false
	end
	local canAttack, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
	if issecretvalue and (issecretvalue(canAttack) or issecretvalue(dead)) then
		return false
	end
	return canAttack and not dead
end

local function Editing(viewer)
	return viewer.isEditing == true
		or (type(CooldownViewerSettings) == "table" and CooldownViewerSettings:IsVisible() == true)
end

-- The frame's state, learning its Edit Mode opacity the first time and whenever the game sets
-- it again.
local function GetState(viewer)
	local state = states[viewer]
	if not state then
		state = { base = viewer:GetAlpha(), amount = 1, hoverUntil = 0 }
		states[viewer] = state
		if viewer.UpdateSystemSettingOpacity then
			hooksecurefunc(viewer, "UpdateSystemSettingOpacity", function(self)
				states[self].base = self:GetAlpha()
				states[self].applied = nil
			end)
		end
	end
	return state
end

local function Apply(viewer, state, alpha)
	if state.applied ~= alpha then
		state.applied = alpha
		viewer:SetAlpha(alpha)
	end
end

-- Whether a bar should be shown now.
function fade.ShouldShow(viewer, state, now, hostile)
	if inCombat or now < holdUntil or hostile or Editing(viewer) then
		return true
	end
	if ns:GetOption("cooldownFadeHover") then
		if viewer:IsMouseOver() then
			state.hoverUntil = now + HOVER_GRACE
		end
		if now < state.hoverUntil then
			return true
		end
	end
	return false
end

local function Step(elapsed)
	local now = GetTime()
	local faded = ns:GetValue("cooldownFadeOpacity") or 0
	local duration = math.max(ns:GetValue("cooldownFadeDuration") or 2, 0.1)
	local hostile = ns:GetOption("cooldownFadeTarget") and HostileTarget()
	for _, each in ipairs(VIEWERS) do
		local viewer = _G[each.frame]
		if viewer and ns:GetOption(each.option) then
			local state = GetState(viewer)
			if fade.ShouldShow(viewer, state, now, hostile) then
				state.amount = math.min(1, state.amount + elapsed / FADE_IN_SECONDS)
			else
				state.amount = math.max(0, state.amount - elapsed / duration)
			end
			Apply(viewer, state, state.base * (faded + (1 - faded) * state.amount))
		elseif viewer and states[viewer] then
			-- Turned off for this bar: back to its own opacity.
			Apply(viewer, states[viewer], states[viewer].base)
			states[viewer].amount = 1
		end
	end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
	Step(elapsed)
end)

local function OnTargetChanged()
	local hostile = HostileTarget()
	if hadTarget and not hostile and not inCombat then
		if ns:GetOption("cooldownFadeTargetNow") then
			holdUntil = 0
		else
			holdUntil = GetTime() + (ns:GetValue("cooldownFadeStay") or 10)
		end
	end
	hadTarget = hostile
end

driver:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		holdUntil = GetTime() + (ns:GetValue("cooldownFadeStay") or 10)
	elseif event == "PLAYER_TARGET_CHANGED" then
		OnTargetChanged()
	end
end)

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }

-- Every bar back to its own opacity (the module turned off).
local function Restore()
	for viewer, state in pairs(states) do
		Apply(viewer, state, state.base)
		state.amount = 1
	end
end

function module:OnInitialize()
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			driver:RegisterEvent(event)
		else
			driver:UnregisterEvent(event)
		end
	end
	if enabled then
		inCombat = InCombatLockdown() or UnitAffectingCombat("player") == true
		hadTarget = HostileTarget()
		holdUntil = 0
		driver:Show()
	else
		driver:Hide()
		Restore()
	end
end

ns:RegisterModule(module)
