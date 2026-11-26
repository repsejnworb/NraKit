local _, ns = ...

-- Proc alerts, for any class (ns.procAlerts): spells that become usable for a moment (after
-- a dodge, a kill, ...) and that the game shows no proc glow for on Forever. While one can
-- be used, its action buttons glow with Blizzard's own proc-glow animation, dimmed while
-- you're short of power, with a countdown ring; optionally a sound and an icon next to the
-- Personal Resource Display's power bar.
--
-- A feature registers a set of spells with its own option keys:
--   ns.procAlerts.Register({
--     key = "warrior",                        -- unique
--     IsEnabled = function() ... end,         -- the whole set on (module, class, option)
--     spells = { { name = "Overpower", option = "warriorProcOverpower" }, ... },
--     options = { countdown = <key>, icon = <key>, sound = <key>, soundChoice = <key> },
--   })
-- and calls ns.procAlerts.Refresh() when its module or options change.
--
-- "Can be used" is C_Spell.IsSpellUsable, which isn't secret in combat (checked in game).
-- Spells are found by name, so whatever rank or ID the player knows is the one watched.
--
-- How long a proc lasts is measured, not looked up: when one runs out unused (while usable,
-- not cast), its time is remembered (NraKitDB.procAlertWindows[name], the longest seen; a
-- stance change cutting one short never lowers it) and the countdown ring uses it from then on.
--
-- Everything is NraKit's own frames over the buttons (which are protected): no clicks, and
-- the buttons themselves are never changed.

local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
	"MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local DIM_ALPHA = 0.4 -- up, but short of power
local FADE_SECONDS = 0.25
local CHECK_EVERY = 0.25 -- while a proc is up (a dimmed one ends without an event)
local CAST_GRACE = 0.5 -- used, not run out: cast this recently
local MIN_WINDOW, MAX_WINDOW = 1, 60 -- a measured time outside this is something else
local UNKNOWN_WINDOW = 30 -- a dimmed proc with no measured time ends after this
local ICON_SIZE = 24
local DEFAULT_SOUND = "kit:MAP_PING"

local alerts = {}
ns.procAlerts = alerts

local sets = {} -- registered sets, in order
local states = {} -- spell name -> { spellID, state = "up"|"dim"|nil, since, set }
local lastCast = {} -- spellID -> GetTime() of its last cast
local glows = {} -- button -> our frame over it
local icons = {} -- spell name -> our icon by the power bar

local function Windows()
	NraKitDB.procAlertWindows = NraKitDB.procAlertWindows or {}
	-- Measured by the first, warrior-only version.
	for name, seconds in pairs(NraKitDB.warriorProcWindows or {}) do
		NraKitDB.procAlertWindows[name] = math.max(NraKitDB.procAlertWindows[name] or 0, seconds)
	end
	NraKitDB.warriorProcWindows = nil
	return NraKitDB.procAlertWindows
end

-- How long a proc lasts, once measured.
function alerts.Window(name)
	return Windows()[name]
end

-- A proc's state now ("up", "dim" or nil).
function alerts.State(name)
	return states[name] and states[name].state
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

local function AnyUp()
	for _, info in pairs(states) do
		if info.state then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The glow over an action button, and the icon by the power bar
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
	if window then
		frame.countdown:SetCooldown(since, window)
		frame.countdown:Show()
	else
		frame.countdown:Hide()
	end
end

local function Hide(frame)
	frame.fadeTo = 0
end

-- The action buttons that hold a spell now (a bar's page can follow your stance or form).
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
	local lit = {} -- button or icon -> true
	local iconIndex = 0
	for _, set in ipairs(sets) do
		for _, spell in ipairs(set.spells) do
			local info = states[spell.name]
			if info and info.state then
				local window = ns:GetOption(set.options.countdown) and alerts.Window(spell.name) or nil
				for _, button in ipairs(Buttons(info.spellID)) do
					lit[button] = true
					Show(Glow(button), info.state, info.since, window)
				end
				local icon = ns:GetOption(set.options.icon) and Icon(spell.name, info.spellID)
				if icon then
					icon:ClearAllPoints()
					icon:SetPoint("LEFT", icon:GetParent(), "RIGHT", 6 + iconIndex * (ICON_SIZE + 4), 0)
					iconIndex = iconIndex + 1
					Show(icon, info.state, info.since, window)
					lit[icon] = true
				end
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

-- A proc went away: if it ran out unused (while usable, not dimmed for power, which can
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

-- Reads each proc's state and plays a set's sound for any that just came up. Redraws when
-- one changed, or always with redraw (the bars or options changed).
local function Check(redraw)
	local now = GetTime()
	local changed = redraw
	for _, set in ipairs(sets) do
		local setOn = set.IsEnabled()
		local fresh = false
		for _, spell in ipairs(set.spells) do
			local info = states[spell.name] or {}
			states[spell.name] = info
			local spellID = setOn and ns:GetOption(spell.option) and SpellID(spell.name)
			local state
			if spellID then
				info.spellID = spellID
				local usable, noPower = C_Spell.IsSpellUsable(spellID)
				if Secret(usable) or Secret(noPower) then
					usable, noPower = false, false
				end
				if usable then
					state = "up"
				elseif noPower and info.state and now - info.since < (alerts.Window(spell.name) or UNKNOWN_WINDOW) then
					state = "dim" -- still up, waiting for power
				end
			end
			if state and not info.state then
				info.since = now
				fresh = true
			elseif not state and info.state then
				Ended(spell.name, info, now)
				info.since = nil
			end
			if state ~= info.state then
				changed = true
			end
			info.state = state
		end
		if fresh and ns:GetOption(set.options.sound) then
			ns.sounds.PlayOption(set.options.soundChoice, DEFAULT_SOUND)
		end
	end
	if changed then
		Draw()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local EVENTS = {
	"SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
	"PLAYER_TARGET_CHANGED",
}
-- Only these can change whether a proc is up; the others can move it to other buttons.
local USABLE_EVENTS = { SPELL_UPDATE_USABLE = true, ACTIONBAR_UPDATE_USABLE = true, UNIT_POWER_FREQUENT = true }

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" and spellID and not Secret(spellID) then
			lastCast[spellID] = GetTime()
		end
		return
	end
	Check(not USABLE_EVENTS[event])
end)

-- Fades every glow and icon to where it's going, and looks again now and then while a
-- proc is up.
local sinceCheck = 0
local fader = CreateFrame("Frame")
fader:SetScript("OnUpdate", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK_EVERY then
		sinceCheck = 0
		if AnyUp() then
			Check()
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

local listening = false

-- Listens to events only while some set is on.
local function Listen()
	local any = false
	for _, set in ipairs(sets) do
		if set.IsEnabled() then
			any = true
		end
	end
	if any == listening then
		return
	end
	listening = any
	for _, event in ipairs(EVENTS) do
		if any then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if any then
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	else
		eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
	end
end

-- A set's module or options changed: look again and redraw.
function alerts.Refresh()
	Listen()
	Check(true)
end

function alerts.Register(set)
	table.insert(sets, set)
end
