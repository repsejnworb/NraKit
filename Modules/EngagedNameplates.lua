local _, ns = ...

-- Shows full enemy nameplates only for mobs that are actually fighting you
-- (or your group). Every other enemy NPC plate is hidden during combat.
--
-- Optionally the module turns enemy nameplates on when you enter combat and off
-- again when you leave it, so you see overhead names outside of combat. In
-- combat it filters which plates stay full.
-- Idle plates are hidden by setting the Blizzard UnitFrame's alpha to 0; nothing
-- else on Blizzard's frame is touched. Addons cannot change a plate's click area
-- in combat, so a hidden plate can still be clicked where its bar would be.
--
-- Optionally idle enemies keep a name. Overhead names (what you see with
-- nameplates off) are drawn by the engine, which stops drawing them for any unit
-- that has a nameplate, so we draw our own name text on the plate instead.
-- Blizzard's name can't be moved instead: nameplate regions are restricted, so
-- addons can't read their anchors to put them back.

local module = {
	key = "engagedNameplates",
	section = "Nameplates",
	name = "Engaged-only nameplates",
	description = "Shows full nameplates only for enemies that are fighting you. Other enemy NPCs are hidden during combat. Your target, focus and enemy players always get full nameplates.",
	default = false,
	options = {
		{
			key = "engagedNameplatesCombatToggle",
			header = "General",
			name = "Only during combat",
			description = "Turns enemy nameplates on when you enter combat and off when you leave it, so you see normal overhead names outside of combat. While this is on, it manages \"Enemy Units\" and \"Always Show Nameplates\" for you; your previous settings come back when it is turned off.",
			default = true,
		},
		{
			key = "engagedNameplatesIncludeGroup",
			name = "Include group's enemies",
			description = "Also show full nameplates for enemies that are fighting your party or raid members.",
			default = true,
		},
		{
			key = "engagedNameplatesFarScale",
			type = "number",
			name = "Far-away scale",
			description = "How small nameplates get at a distance, as a percentage of their close-up size. Lower values shrink distant idle names more, like the game's own overhead names. Blizzard's default is 80%. Applies to all nameplates, including engaged ones.",
			default = 70, min = 10, max = 100, step = 5, format = "%d%%",
		},
		{
			key = "engagedNameplatesShowIdleNames",
			header = "Idle enemies in combat",
			name = "Show names",
			description = "Instead of hiding idle enemies completely during combat, show just their name, styled to resemble overhead names. Real overhead names can't be shown for units that have a nameplate.",
			default = false,
		},
		{
			key = "engagedNameplatesNameSize",
			parent = "engagedNameplatesShowIdleNames",
			type = "number",
			name = "Name size",
			description = "Font size of idle enemy names.",
			default = 11, min = 6, max = 24, step = 1,
		},
		{
			key = "engagedNameplatesNameOffset",
			parent = "engagedNameplatesShowIdleNames",
			type = "number",
			name = "Name height",
			description = "Moves idle enemy names up or down relative to the unit's head.",
			default = 0, min = -40, max = 40, step = 1,
		},
		{
			key = "engagedNameplatesNameOutline",
			parent = "engagedNameplatesShowIdleNames",
			name = "Outline",
			description = "Draw a thin outline around idle enemy names.",
			default = false,
		},
		{
			key = "engagedNameplatesNameShadow",
			parent = "engagedNameplatesShowIdleNames",
			name = "Shadow",
			description = "Draw a drop shadow behind idle enemy names. Real overhead names have no visible shadow.",
			default = false,
		},
		{
			key = "engagedNameplatesNameFade",
			parent = "engagedNameplatesShowIdleNames",
			name = "Fade with distance",
			description = "Let idle enemy names fade out with distance and when hidden behind objects, like nameplates do. When off, they stay fully visible.",
			default = false,
		},
	},
}

-- Style for idle names, approximating the engine's overhead names.
-- UNIT_NAME_FONT is the font Blizzard hands the engine for those names, and
-- UnitSelectionColor matches their reaction color. The rest comes from settings.
local NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y = 1, -1
local TAPPED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

-- CVars managed by the combat toggle, as { out of combat, in combat }. Previous
-- values are saved and restored when the toggle or module is turned off.
local COMBAT_TOGGLE_CVARS = {
	nameplateShowEnemies = { "0", "1" },
	nameplateShowAll = { "1", "1" },
}

local SAVED_CVARS_KEY = "engagedNameplatesSavedCVars"

-- nameplate unit token -> Blizzard UnitFrame we have hidden
local hiddenFrames = {}
-- nameplate base frame -> our name overlay
local overlays = {}
local inCombat = false

local eventFrame = CreateFrame("Frame")

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Secret results are treated as "yes" so we never hide a plate we can't reason about.
local function Check(value)
	if IsSecret(value) then
		return true
	end
	return value and true or false
end

local function HasThreatOn(unit, mob)
	if not UnitExists(unit) then
		return false
	end
	local status = UnitThreatSituation(unit, mob)
	return IsSecret(status) or status ~= nil
end

local function IsEngagedWithGroup(mob)
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			if HasThreatOn("raid" .. i, mob) or HasThreatOn("raidpet" .. i, mob) then
				return true
			end
		end
	else
		for i = 1, GetNumSubgroupMembers() do
			if HasThreatOn("party" .. i, mob) or HasThreatOn("partypet" .. i, mob) then
				return true
			end
		end
	end
	return false
end

local function ShouldShowFullPlate(unit, unitFrame)
	if not Check(UnitCanAttack("player", unit)) then
		return true -- friendly plates are not ours to touch
	end
	if Check(UnitIsPlayer(unit)) then
		return true
	end
	-- Use Blizzard's cached flags; comparing unit tokens from addon code can be restricted.
	if Check(unitFrame.isTarget) or Check(unitFrame.isFocus) then
		return true
	end
	if HasThreatOn("player", unit) or HasThreatOn("pet", unit) then
		return true
	end
	if ns:GetOption("engagedNameplatesIncludeGroup") and IsEngagedWithGroup(unit) then
		return true
	end
	return false
end

local function GetOverlay(plate)
	local overlay = overlays[plate]
	if not overlay then
		overlay = CreateFrame("Frame", nil, plate)
		overlay:SetAllPoints(plate)
		overlay.text = overlay:CreateFontString(nil, "OVERLAY")
		overlays[plate] = overlay
	end
	return overlay
end

local function StyleOverlay(overlay, unit)
	local text = overlay.text
	local flags = ns:GetOption("engagedNameplatesNameOutline") and "OUTLINE" or ""
	text:SetFont(UNIT_NAME_FONT, ns:GetValue("engagedNameplatesNameSize") or 11, flags)
	if ns:GetOption("engagedNameplatesNameShadow") then
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y)
	else
		text:SetShadowOffset(0, 0)
	end
	-- The engine fades whole plates with distance and occlusion; opt out of that.
	overlay:SetIgnoreParentAlpha(not ns:GetOption("engagedNameplatesNameFade"))
	text:ClearAllPoints()
	-- The bottom of the plate sits just above the unit's head.
	text:SetPoint("BOTTOM", overlay, "BOTTOM", 0, ns:GetValue("engagedNameplatesNameOffset") or 0)

	-- Values may be secret; FontStrings accept those, we just never compare them.
	text:SetText(UnitName(unit))
	local tapped = UnitIsTapDenied(unit)
	if not IsSecret(tapped) and tapped then
		text:SetTextColor(TAPPED_COLOR.r, TAPPED_COLOR.g, TAPPED_COLOR.b)
	else
		text:SetTextColor(UnitSelectionColor(unit))
	end
end

local function HideOverlay(plate)
	local overlay = plate and overlays[plate]
	if overlay then
		overlay:Hide()
	end
end

local function RestorePlate(unit)
	local unitFrame = hiddenFrames[unit]
	if unitFrame then
		hiddenFrames[unit] = nil
		unitFrame:SetAlpha(1)
	end
	HideOverlay(C_NamePlate.GetNamePlateForUnit(unit))
end

local function UpdatePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local unitFrame = plate and plate.UnitFrame
	if not unitFrame or not ns:IsModuleEnabled(module.key) or ShouldShowFullPlate(unit, unitFrame) then
		RestorePlate(unit)
		return
	end
	-- The plate may have been handed a different pooled UnitFrame since we last saw it.
	if hiddenFrames[unit] and hiddenFrames[unit] ~= unitFrame then
		hiddenFrames[unit]:SetAlpha(1)
	end
	hiddenFrames[unit] = unitFrame
	unitFrame:SetAlpha(0)

	local showName = ns:GetOption("engagedNameplatesShowIdleNames")
		and Check(UnitShouldDisplayName(unit))
	if showName then
		local overlay = GetOverlay(plate)
		StyleOverlay(overlay, unit)
		overlay:Show()
	else
		HideOverlay(plate)
	end
end

local function UpdateAllPlates()
	for unit in pairs(hiddenFrames) do
		UpdatePlate(unit)
	end
	for _, plate in pairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.unitToken
		if unit then
			UpdatePlate(unit)
		end
	end
end

local function IsNamePlateUnit(unit)
	return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
end

local function ApplyCVars()
	-- CVar changes are deferred during lockdown; PLAYER_REGEN_ENABLED applies them.
	if InCombatLockdown() then
		return
	end

	local desired = {}
	if ns:IsModuleEnabled(module.key) then
		if ns:GetOption("engagedNameplatesCombatToggle") then
			for name, values in pairs(COMBAT_TOGGLE_CVARS) do
				desired[name] = values[inCombat and 2 or 1]
			end
		end
		-- The engine scales plates linearly between these by distance; our idle names
		-- are children of the plate, so they follow it.
		desired.nameplateMinScale = tostring((ns:GetValue("engagedNameplatesFarScale") or 70) / 100)
		desired.nameplateMaxScale = "1"
	end

	local saved = NraKitDB[SAVED_CVARS_KEY] or {}
	-- Put back anything we no longer manage.
	for name, value in pairs(saved) do
		if not desired[name] then
			SetCVar(name, value)
			saved[name] = nil
		end
	end
	for name, value in pairs(desired) do
		local current = GetCVar(name)
		if current ~= nil then
			if saved[name] == nil then
				saved[name] = current
			end
			SetCVar(name, value)
		end
	end
	NraKitDB[SAVED_CVARS_KEY] = next(saved) and saved or nil
end

local function OnEvent(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		UpdatePlate(unit)
		-- In case Blizzard's driver hasn't attached its UnitFrame to the plate yet.
		C_Timer.After(0, function()
			UpdatePlate(unit)
		end)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		RestorePlate(unit)
	elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_NAME_UPDATE" or event == "UNIT_FACTION" then
		if IsNamePlateUnit(unit) then
			UpdatePlate(unit)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before combat lockdown starts, so CVars can still be changed here.
		inCombat = true
		ApplyCVars()
		UpdateAllPlates()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		ApplyCVars()
		UpdateAllPlates()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		-- Wait a frame so Blizzard's plates have updated their isTarget/isFocus flags.
		C_Timer.After(0, UpdateAllPlates)
	else
		UpdateAllPlates()
	end
end

local EVENTS = {
	"NAME_PLATE_UNIT_ADDED",
	"NAME_PLATE_UNIT_REMOVED",
	"UNIT_THREAT_LIST_UPDATE",
	"UNIT_THREAT_SITUATION_UPDATE",
	"UNIT_NAME_UPDATE",
	"UNIT_FACTION",
	"PLAYER_TARGET_CHANGED",
	"PLAYER_FOCUS_CHANGED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED",
	"GROUP_ROSTER_UPDATE",
}

local function SetActive(active)
	for _, event in ipairs(EVENTS) do
		if active then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
end

eventFrame:SetScript("OnEvent", OnEvent)

function module:OnInitialize()
	inCombat = InCombatLockdown()
	-- Undo a deferred CVar change even if the module was switched off mid-combat.
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	SetActive(enabled)
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	ApplyCVars()
	UpdateAllPlates()
end

function module:OnOptionChanged(key)
	if key == "engagedNameplatesCombatToggle" or key == "engagedNameplatesFarScale" then
		ApplyCVars()
	end
	UpdateAllPlates()
end

ns:RegisterModule(module)
