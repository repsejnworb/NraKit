local _, ns = ...

-- Warrior proc alerts (part of the Warrior module, Warrior.lua has its options): the game
-- shows no proc glow on Forever for Overpower, Revenge and Victory Rush, so NraKit glows
-- their action buttons while they can be used, with Blizzard's own proc-glow animation.
--
-- "Can be used" is C_Spell.IsSpellUsable, which isn't secret in combat (checked in game).
-- The spells are found by name, so whatever rank or ID you know is the one watched. While a
-- proc is up but you're short of rage, the glow dims instead of going away.
--
-- How long a proc lasts isn't on Wowhead's Forever pages, so it's measured: when one runs
-- out unused, its time is remembered (NraKitDB.warriorProcWindows, the longest seen; a stance
-- change cuts one short, which never lowers it) and the countdown ring uses it from then on.
--
-- Everything is NraKit's own frames over the buttons (which are protected): no clicks, and
-- the buttons themselves are never changed.

local PROCS = {
	{ option = "warriorProcOverpower", name = "Overpower" },
	{ option = "warriorProcRevenge", name = "Revenge" },
	{ option = "warriorProcVictoryRush", name = "Victory Rush" },
}
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
	"MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local DIM_ALPHA = 0.4 -- up, but short of rage
local FADE_SECONDS = 0.25
local CAST_GRACE = 0.5 -- used, not run out: cast this recently
local MIN_WINDOW, MAX_WINDOW = 1, 60 -- a measured time outside this is something else
local UNKNOWN_WINDOW = 30 -- a dimmed proc with no measured time ends after this
local ICON_SIZE = 24

local procs = {}
ns.warriorProcs = procs

local enabled = false
local states = {} -- name -> { spellID, state = "up"|"dim"|nil, since }
local lastCast = {} -- spellID -> GetTime() of its last cast
local glows = {} -- button -> our frame over it
local icons = {} -- name -> our icon by the rage bar

local function Windows()
	NraKitDB.warriorProcWindows = NraKitDB.warriorProcWindows or {}
	return NraKitDB.warriorProcWindows
end

-- How long a proc lasts, once measured.
function procs.Window(name)
	return Windows()[name]
end

local function IsWarrior()
	local _, class = UnitClass("player")
	return class == "WARRIOR"
end

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function SpellID(name)
	local info = C_Spell.GetSpellInfo(name)
	local spellID = info and info.spellID
	if not spellID or Secret(spellID) then
		return nil
	end
	return spellID
end

---------------------------------------------------------------------------
-- The glow over an action button, and the icon by the rage bar
---------------------------------------------------------------------------

local function NewCountdown(parent, anchor)
	local countdown = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	countdown:SetAllPoints(anchor)
	countdown:SetReverse(true)
	countdown:SetDrawEdge(true)
	countdown:SetSwipeColor(0, 0, 0, 0.45)
	return countdown
end

local function Glow(button)
	local glow = glows[button]
	if not glow then
		glow = CreateFrame("Frame", nil, button)
		glow:SetAllPoints()
		glow:EnableMouse(false)
		glow:SetFrameLevel(button:GetFrameLevel() + 10)
		glow:Hide()
		-- Blizzard's proc glow, at the size Blizzard gives it.
		glow.alert = CreateFrame("Frame", nil, glow, "ActionButtonSpellAlertTemplate")
		glow.alert:SetSize(button:GetWidth() * 1.4, button:GetHeight() * 1.4)
		glow.alert:SetPoint("CENTER")
		glow.countdown = NewCountdown(glow, button)
		glows[button] = glow
	end
	return glow
end

local function Icon(name, spellID)
	local icon = icons[name]
	local bar = PersonalResourceDisplayFrame and PersonalResourceDisplayFrame.PowerBar
	if not icon and bar then
		icon = CreateFrame("Frame", nil, bar)
		icon:SetSize(ICON_SIZE, ICON_SIZE)
		icon:EnableMouse(false)
		icon:Hide()
		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints()
		icon.alert = CreateFrame("Frame", nil, icon, "ActionButtonSpellAlertTemplate")
		icon.alert:SetSize(ICON_SIZE * 1.4, ICON_SIZE * 1.4)
		icon.alert:SetPoint("CENTER")
		icon.countdown = NewCountdown(icon, icon)
		icons[name] = icon
	end
	if icon then
		icon.texture:SetTexture(C_Spell.GetSpellTexture(spellID))
	end
	return icon
end

-- Shows a glow or icon: the start of Blizzard's animation the first time, then its loop.
local function Show(frame, state, since, window)
	frame.fadeTo = state == "up" and 1 or DIM_ALPHA
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
		local alert = frame.alert
		alert:Show()
		if alert.ProcStartAnim then
			alert.ProcStartAnim:Play()
		end
	end
	if window and ns:GetOption("warriorProcCountdown") then
		frame.countdown:SetCooldown(since, window)
		frame.countdown:Show()
	else
		frame.countdown:Hide()
	end
end

local function Hide(frame)
	frame.fadeTo = 0
end

-- While a proc is up, look again now and then too (a dimmed one ends without an event).
local function AnyUp()
	for _, info in pairs(states) do
		if info.state then
			return true
		end
	end
	return false
end

-- Fades every glow and icon to where it's going.
local CHECK_EVERY = 0.25
local sinceCheck = 0
local fader = CreateFrame("Frame")
fader:SetScript("OnUpdate", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK_EVERY then
		sinceCheck = 0
		if AnyUp() then
			procs.Check()
		end
	end
	local step = elapsed / FADE_SECONDS
	for _, list in ipairs({ glows, icons }) do
		for _, frame in pairs(list) do
			if frame:IsShown() and frame.fadeTo then
				local alpha = frame:GetAlpha()
				if alpha < frame.fadeTo then
					frame:SetAlpha(math.min(frame.fadeTo, alpha + step))
				elseif alpha > frame.fadeTo then
					alpha = math.max(frame.fadeTo, alpha - step)
					frame:SetAlpha(alpha)
					if alpha == 0 then
						frame:Hide()
						if frame.alert.ProcLoop then
							frame.alert.ProcLoop:Stop()
						end
					end
				end
			end
		end
	end
end)

-- The action buttons that hold a spell now (the bar's page follows your stance).
local function Buttons(spellID)
	local found = {}
	local slots = C_ActionBar.FindSpellActionButtons and C_ActionBar.FindSpellActionButtons(spellID)
	if type(slots) ~= "table" then
		return found
	end
	local wanted = {}
	for _, slot in ipairs(slots) do
		wanted[slot] = true
	end
	for _, bar in ipairs(BARS) do
		for index = 1, 12 do
			local button = _G[bar .. index]
			if button and button.action and wanted[button.action] and button:IsVisible() then
				table.insert(found, button)
			end
		end
	end
	return found
end

-- Draws every proc as it is now.
local function Draw()
	local lit = {} -- button -> true
	local iconIndex = 0
	for _, proc in ipairs(PROCS) do
		local info = states[proc.name]
		if info and info.state then
			local window = procs.Window(proc.name)
			for _, button in ipairs(Buttons(info.spellID)) do
				lit[button] = true
				Show(Glow(button), info.state, info.since, window)
			end
			local icon = ns:GetOption("warriorProcIcon") and Icon(proc.name, info.spellID)
			if icon then
				icon:ClearAllPoints()
				icon:SetPoint("LEFT", icon:GetParent(), "RIGHT", 6 + iconIndex * (ICON_SIZE + 4), 0)
				iconIndex = iconIndex + 1
				Show(icon, info.state, info.since, window)
				lit[icon] = true
			end
		end
	end
	for button, glow in pairs(glows) do
		if not lit[button] then
			Hide(glow)
		end
	end
	for _, icon in pairs(icons) do
		if not lit[icon] then
			Hide(icon)
		end
	end
end

---------------------------------------------------------------------------
-- Watching the procs
---------------------------------------------------------------------------

-- A proc went away: if it ran out unused (while usable, not dimmed for rage, which can
-- end on NraKit's own guess), remember how long it lasted.
local function Ended(name, info, now)
	local cast = lastCast[info.spellID]
	if info.since and info.state == "up" and not (cast and now - cast <= CAST_GRACE) then
		local lasted = math.floor((now - info.since) * 10 + 0.5) / 10
		if lasted >= MIN_WINDOW and lasted <= MAX_WINDOW and lasted > (Windows()[name] or 0) then
			Windows()[name] = lasted
		end
	end
end

-- Reads each proc's state and plays the sound for any that just came up. Redraws when one
-- changed, or always with redraw (the bars changed).
local function Check(redraw)
	local now = GetTime()
	local fresh, changed = false, redraw
	for _, proc in ipairs(PROCS) do
		local info = states[proc.name] or {}
		states[proc.name] = info
		local spellID = enabled and ns:GetOption("warriorProcs") and ns:GetOption(proc.option) and SpellID(proc.name)
		local state
		if spellID then
			info.spellID = spellID
			local usable, noRage = C_Spell.IsSpellUsable(spellID)
			if Secret(usable) or Secret(noRage) then
				usable, noRage = false, false
			end
			if usable then
				state = "up"
			elseif noRage and info.state and now - info.since < (procs.Window(proc.name) or UNKNOWN_WINDOW) then
				state = "dim" -- still up, waiting for rage
			end
		end
		if state and not info.state then
			info.since = now
			fresh = true
		elseif not state and info.state then
			Ended(proc.name, info, now)
			info.since = nil
		end
		if state ~= info.state then
			changed = true
		end
		info.state = state
	end
	if fresh and ns:GetOption("warriorProcSound") then
		ns.sounds.PlayOption("warriorProcSoundChoice", "kit:MAP_PING")
	end
	if changed then
		Draw()
	end
end

function procs.Refresh()
	Check(true)
end
procs.Check = Check


-- A proc's state now ("up", "dim" or nil), for tests.
function procs.State(name)
	return states[name] and states[name].state
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" and spellID and not Secret(spellID) then
			lastCast[spellID] = GetTime()
		end
		return
	end
	Check(event ~= "SPELL_UPDATE_USABLE" and event ~= "ACTIONBAR_UPDATE_USABLE" and event ~= "UNIT_POWER_FREQUENT")
end)

local EVENTS = {
	"SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
	"PLAYER_TARGET_CHANGED",
}

-- The Warrior module turned on or off.
function procs.SetEnabled(on)
	enabled = on and IsWarrior()
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	else
		eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
	end
	Check(true)
end
