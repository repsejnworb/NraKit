local _, ns = ...

-- Shows full enemy nameplates only for mobs that are actually fighting you
-- (or your group). Every other enemy NPC plate is hidden during combat.
--
-- Blizzard's "Always Show Nameplates" off already limits plates to when you are
-- in combat; this module turns that on and then filters which plates stay full.
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
	name = "Nameplates only for engaged enemies",
	description = "Turns off \"Always Show Nameplates\" so enemy nameplates only appear in combat, and shows full nameplates only for enemies that are fighting you. Other enemy NPCs are hidden during combat. Your target, focus and enemy players always get full nameplates.",
	default = false,
	options = {
		{
			key = "engagedNameplatesIncludeGroup",
			name = "Include enemies fighting my group",
			description = "Also show full nameplates for enemies that are fighting your party or raid members.",
			default = true,
		},
		{
			key = "engagedNameplatesShowIdleNames",
			name = "Show names of idle enemies in combat",
			description = "Instead of hiding idle enemies completely during combat, show just their name, styled to resemble overhead names. Real overhead names can't be shown for units that have a nameplate.",
			default = false,
		},
		{
			key = "engagedNameplatesNameSize",
			parent = "engagedNameplatesShowIdleNames",
			type = "number",
			name = "Idle name size",
			description = "Font size of idle enemy names.",
			default = 11, min = 6, max = 24, step = 1,
		},
		{
			key = "engagedNameplatesNameOffset",
			parent = "engagedNameplatesShowIdleNames",
			type = "number",
			name = "Idle name height",
			description = "Moves idle enemy names up or down relative to the unit's head.",
			default = 0, min = -40, max = 40, step = 1,
		},
		{
			key = "engagedNameplatesNameOutline",
			parent = "engagedNameplatesShowIdleNames",
			name = "Outline idle names",
			description = "Draw a thin outline around idle enemy names.",
			default = false,
		},
	},
}

-- Style for idle names, approximating the engine's overhead names.
-- UNIT_NAME_FONT is the font Blizzard hands the engine for those names. Size,
-- height and outline come from the settings.
local NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y = 1, -1
local TAPPED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

-- CVars this module takes over while enabled; previous values are restored when disabled.
local MANAGED_CVARS = {
	nameplateShowAll = "0",
	nameplateShowEnemies = "1",
}

local SAVED_CVARS_KEY = "engagedNameplatesSavedCVars"

-- nameplate unit token -> Blizzard UnitFrame we have hidden
local hiddenFrames = {}
-- nameplate base frame -> our name overlay
local overlays = {}
local pendingCVarUpdate = false

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
		overlay.text:SetShadowColor(0, 0, 0, 1)
		overlays[plate] = overlay
	end
	return overlay
end

local function StyleOverlay(overlay, unit)
	local text = overlay.text
	local flags = ns:GetOption("engagedNameplatesNameOutline") and "OUTLINE" or ""
	text:SetFont(UNIT_NAME_FONT, ns:GetValue("engagedNameplatesNameSize") or 11, flags)
	text:SetShadowOffset(NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y)
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
	if InCombatLockdown() then
		pendingCVarUpdate = true
		return
	end
	pendingCVarUpdate = false

	local desired = {}
	if ns:IsModuleEnabled(module.key) then
		for name, value in pairs(MANAGED_CVARS) do
			desired[name] = value
		end
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
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingCVarUpdate then
			ApplyCVars()
		end
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

function module:OnOptionChanged()
	UpdateAllPlates()
end

ns:RegisterModule(module)
