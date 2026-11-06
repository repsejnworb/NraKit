local _, ns = ...

-- Shows full enemy nameplates only for mobs that are actually fighting you
-- (or your group). Every other enemy NPC plate is reduced to just its name.
--
-- Blizzard's "Always Show Nameplates" off already limits plates to when you are
-- in combat; this module turns that on and then filters which plates stay full.
-- Plate parts are faded with SetAlpha rather than hidden, because Blizzard's own
-- code keeps re-showing them. Addons cannot change a plate's click area in
-- combat, so a name-only plate can still be clicked where its bar would be.
--
-- Overhead names (what you see with nameplates off) are drawn by the engine, and
-- the engine stops drawing them for any unit that has a nameplate. So name-only
-- plates restyle the plate's own name text to look like an overhead name instead.

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
		{
			key = "engagedNameplatesFixedSize",
			name = "Don't shrink or fade nameplates with distance",
			description = "Keeps all nameplates at full size and opacity regardless of distance, like overhead names. Affects every nameplate, not just name-only ones.",
			default = true,
		},
	},
}

-- Style for name-only plates, approximating the engine's overhead names.
-- UNIT_NAME_FONT is the font Blizzard hands the engine for those names.
local NAME_FONT_SIZE = 13
local NAME_FONT_FLAGS = ""
local NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y = 1, -1
local NAME_SHADOW_COLOR = { r = 0, g = 0, b = 0, a = 1 }

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

-- Additional CVars managed while the fixed-size option is on.
local FIXED_SIZE_CVARS = {
	nameplateMinScale = "1",
	nameplateMaxScale = "1",
	nameplateMinAlpha = "1",
}

local SAVED_CVARS_KEY = "engagedNameplatesSavedCVars"

-- nameplate unit token -> UnitFrame we have faded
local fadedFrames = {}
-- UnitFrame -> Blizzard's original name font, for frames whose name we restyled
local styledNames = {}
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

local function SaveNameFont(unitFrame)
	local name = unitFrame.name
	local path, size, flags = name:GetFont()
	local r, g, b, a = name:GetShadowColor()
	local x, y = name:GetShadowOffset()
	styledNames[unitFrame] = {
		fontObject = name:GetFontObject(),
		path = path, size = size, flags = flags,
		shadowColor = { r, g, b, a },
		shadowX = x, shadowY = y,
	}
end

local function StyleName(unitFrame)
	local name = unitFrame.name
	name:SetFont(UNIT_NAME_FONT, NAME_FONT_SIZE, NAME_FONT_FLAGS)
	name:SetShadowOffset(NAME_SHADOW_OFFSET_X, NAME_SHADOW_OFFSET_Y)
	name:SetShadowColor(NAME_SHADOW_COLOR.r, NAME_SHADOW_COLOR.g, NAME_SHADOW_COLOR.b, NAME_SHADOW_COLOR.a)
end

local function UnstyleName(unitFrame)
	local saved = styledNames[unitFrame]
	if not saved then
		return
	end
	styledNames[unitFrame] = nil
	local name = unitFrame.name
	if saved.fontObject then
		name:SetFontObject(saved.fontObject)
	end
	if saved.path then
		name:SetFont(saved.path, saved.size, saved.flags)
	end
	name:SetShadowOffset(saved.shadowX, saved.shadowY)
	name:SetShadowColor(unpack(saved.shadowColor))
end

local function FadePlate(unitFrame)
	SetPartsAlpha(unitFrame, 0)
	if unitFrame.name and not styledNames[unitFrame] then
		SaveNameFont(unitFrame)
		StyleName(unitFrame)
	end
end

local function RestorePlate(unit)
	local unitFrame = fadedFrames[unit]
	if unitFrame then
		fadedFrames[unit] = nil
		SetPartsAlpha(unitFrame, 1)
		UnstyleName(unitFrame)
	end
end

-- Blizzard resets the name font whenever it reapplies a plate's options; take
-- that as the new original and restyle on top of it.
if CompactUnitFrame_SetUpFrame then
	hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
		if styledNames[frame] then
			SaveNameFont(frame)
			StyleName(frame)
		end
	end)
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
	FadePlate(unitFrame)
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

	local desired = {}
	if ns:IsModuleEnabled(module.key) then
		for name, value in pairs(MANAGED_CVARS) do
			desired[name] = value
		end
		if ns:GetOption("engagedNameplatesFixedSize") then
			for name, value in pairs(FIXED_SIZE_CVARS) do
				desired[name] = value
			end
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

function module:OnOptionChanged(key)
	if key == "engagedNameplatesFixedSize" then
		ApplyCVars()
	end
	UpdateAllPlates()
end

ns:RegisterModule(module)
