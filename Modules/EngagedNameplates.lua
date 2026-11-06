local _, ns = ...

-- Shows full enemy nameplates only for mobs that are actually fighting you
-- (or your group). Every other enemy NPC plate is reduced to just its name.
--
-- Blizzard's "Always Show Nameplates" off already limits plates to when you are
-- in combat; this module turns that on and then filters which plates stay full.
-- Plate parts are faded with SetAlpha rather than hidden, because Blizzard's own
-- code keeps re-showing them. Addons cannot change a plate's click area in
-- combat, so a name-only plate can still be clicked where its bar would be.

local module = {
	key = "engagedNameplates",
	name = "Nameplates only for engaged enemies",
	description = "Turns off \"Always Show Nameplates\" so enemy nameplates only appear in combat, and shows full nameplates only for enemies that are fighting you. Other enemy NPCs show just their name. Your target, focus and enemy players always get full nameplates.",
	default = false,
	options = {
		{
			key = "engagedNameplatesIncludeGroup",
			name = "Include enemies fighting my group",
			description = "Also show full nameplates for enemies that are fighting your party or raid members.",
			default = true,
		},
	},
}

-- Parts of Blizzard's nameplate unit frame that are faded out on name-only plates.
-- The name, raid marker, widgets and soft-target icon are left alone.
local FADED_PARTS = {
	"HealthBarsContainer",
	"CastBarsContainer",
	"AurasFrame",
	"ClassificationFrame",
	"LevelFrame",
	"PlayerLevelDiffFrame",
}

-- CVars this module takes over while enabled; previous values are restored when disabled.
local MANAGED_CVARS = {
	nameplateShowAll = "0",
	nameplateShowEnemies = "1",
}

local SAVED_CVARS_KEY = "engagedNameplatesSavedCVars"

-- nameplate unit token -> UnitFrame we have faded
local fadedFrames = {}
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

local function SetPartsAlpha(unitFrame, alpha)
	for _, key in ipairs(FADED_PARTS) do
		local part = unitFrame[key]
		if part then
			part:SetAlpha(alpha)
		end
	end
end

local function RestorePlate(unit)
	local unitFrame = fadedFrames[unit]
	if unitFrame then
		fadedFrames[unit] = nil
		SetPartsAlpha(unitFrame, 1)
	end
end

local function UpdatePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local unitFrame = plate and plate.UnitFrame
	if not unitFrame or not ns:IsModuleEnabled(module.key) or ShouldShowFullPlate(unit, unitFrame) then
		RestorePlate(unit)
		return
	end
	-- The plate may have been handed a different pooled UnitFrame since we last saw it.
	if fadedFrames[unit] and fadedFrames[unit] ~= unitFrame then
		RestorePlate(unit)
	end
	fadedFrames[unit] = unitFrame
	SetPartsAlpha(unitFrame, 0)
end

local function UpdateAllPlates()
	for unit in pairs(fadedFrames) do
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

	if ns:IsModuleEnabled(module.key) then
		if not NraKitDB[SAVED_CVARS_KEY] then
			local saved = {}
			for name in pairs(MANAGED_CVARS) do
				saved[name] = GetCVar(name)
			end
			NraKitDB[SAVED_CVARS_KEY] = saved
		end
		for name, value in pairs(MANAGED_CVARS) do
			SetCVar(name, value)
		end
	elseif NraKitDB[SAVED_CVARS_KEY] then
		for name, value in pairs(NraKitDB[SAVED_CVARS_KEY]) do
			SetCVar(name, value)
		end
		NraKitDB[SAVED_CVARS_KEY] = nil
	end
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
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
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
