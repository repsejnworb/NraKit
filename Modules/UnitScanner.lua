local _, ns = ...

-- Unit Scanner: alerts you when a unit from your own list shows up nearby.
--
-- Addons can no longer probe for units by name (the old unitscan TargetUnit trick
-- is protected), so we only look at units the client already gives us: nameplates
-- as they appear, mouseover, target, focus, group members' targets, minimap markers
-- (vignettes, which only rares and special objects have) and NPC yells, says and
-- emotes (yells reach the whole zone). The combat log is closed to addons on this
-- client (COMBAT_LOG_EVENT_UNFILTERED is restricted). Units are matched by
-- name or by NPC ID (from the GUID). Names and GUIDs can be secret values when a
-- unit's identity is restricted (mostly in instances); those units are skipped.
--
-- Nameplates are the main source, so enemy nameplates must be on. Engaged-only
-- nameplates turns them off outside combat; it asks UnitScanWantsEnemyNameplates()
-- and keeps them on while there is something to scan for. Optionally the nameplate
-- range (nameplateMaxDistance) is raised while scanning; the user's value is saved
-- in NraKitDB and put back afterwards.
--
-- The list lives in NraKitDB.unitScanTargets (account-wide) as { name = , npcID = }
-- entries; either may be missing until the unit has been seen.

local MarkerLabel

local module = {
	key = "unitScanner",
	section = "Unit Scanner",
	name = "Unit Scanner",
	description = "Alerts you when a mob or player from your list shows up nearby (nameplate range, mouseover, targets and minimap markers). Manage the list with /nra scan: target a unit and type /nra scan, or /nra scan <name or NPC ID>, /nra scan list, /nra scan remove <# or name>.",
	default = false,
	options = {
		{
			key = "unitScanSound",
			header = "Alerts",
			name = "Play a sound",
			description = "Play the raid warning sound when a unit is found.",
			default = true,
		},
		{
			key = "unitScanScreenText",
			name = "Show on screen",
			description = "Show a large \"<name> found!\" message near the top of the screen.",
			default = true,
		},
		{
			key = "unitScanChat",
			name = "Print in chat",
			description = "Print a line in chat when a unit is found.",
			default = true,
		},
		{
			key = "unitScanFlash",
			name = "Flash the game's taskbar icon",
			description = "Flash the game's icon in the taskbar/dock when a unit is found while the game is in the background.",
			default = true,
		},
		{
			key = "unitScanCooldown",
			type = "number",
			name = "Alert again after",
			description = "Seconds before the same unit can alert again, so a unit that stays in view doesn't keep alerting.",
			default = 60, min = 10, max = 600, step = 10, format = "%ds",
		},
		{
			key = "unitScanMark",
			header = "When found",
			name = "Put a raid marker on it",
			description = "Mark the unit with a raid target icon when it's found, unless it already has one. Only possible when the unit itself was seen (nameplate, mouseover, a target), not from a minimap marker or a yell; targeting it with the button marks it then. In a raid you need to be leader or assistant.",
			default = true,
		},
		{
			key = "unitScanMarker",
			parent = "unitScanMark",
			type = "number",
			name = "Marker",
			description = "Which raid target icon to use.",
			default = 5, min = 1, max = 8, step = 1,
			format = function(value)
				return MarkerLabel(value)
			end,
		},
		{
			key = "unitScanButton",
			name = "Show a target button",
			description = "Show a button with the marker icon and the unit's name; click it to target the unit (it runs /targetexact <name>). Right-click to dismiss it, Shift-drag to move it. Can also be bound to a key under Keybindings -> AddOns -> NraKit. Buttons that target can't be changed in combat, so a unit found in combat gets its button when combat ends.",
			default = true,
		},
		{
			key = "unitScanVignettes",
			header = "Scanning",
			name = "Minimap markers",
			description = "Also check the markers rares and special objects get on the minimap. They show up from much further away than nameplates, but only units Blizzard gave a marker have one.",
			default = true,
		},
		{
			key = "unitScanChatSources",
			name = "NPC yells, says and emotes",
			description = "Also check who is talking: many rares and named mobs yell or emote, and yells reach the whole zone.",
			default = true,
		},
		{
			key = "unitScanMaxRange",
			name = "Maximize nameplate range",
			description = "While your list isn't empty, raise the nameplate range to the game's maximum so units are seen from further away. This applies to all nameplates. Your own setting comes back when the list is empty or this is turned off.",
			default = false,
		},
		{
			key = "unitScanKeepPlates",
			name = "Keep enemy nameplates on",
			description = "While your list isn't empty, keep enemy nameplates on outside combat when Engaged-only nameplates would turn them off: nameplates are the scanner's main way of seeing units. Idle enemies then show as that module draws them (hidden, or just their name if \"Show names\" is on).",
			default = true,
		},
	},
}

local SCREEN_TEXT_COLOR = { 1, 0.2, 0.1 }
local SCREEN_TEXT_SIZE = 28
local SCREEN_TEXT_Y = 300
local SCREEN_TEXT_HOLD = 5
local SCREEN_TEXT_FADE = 1.5

local ApplyRange

local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function MarkerTexture(index)
	return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index
end

MarkerLabel = function(index)
	return string.format("|T%s:0|t %s", MarkerTexture(index), MARKER_NAMES[index] or index)
end

-- Chat events from NPCs, and the source label for each.
local CHAT_SOURCES = {
	CHAT_MSG_MONSTER_YELL = "yell",
	CHAT_MSG_MONSTER_SAY = "say",
	CHAT_MSG_MONSTER_EMOTE = "emote",
	CHAT_MSG_RAID_BOSS_EMOTE = "emote",
}

local SOURCE_LABELS = {
	nameplate = "nearby",
	mouseover = "mouseover",
	target = "target",
	focus = "focus",
	group = "a group member's target",
	yell = "yell",
	say = "say",
	emote = "emote",
	vignette = "minimap marker",
}

-- entry -> GetTime() of its last alert
local lastAlert = {}

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function GetTargets()
	NraKitDB.unitScanTargets = NraKitDB.unitScanTargets or {}
	return NraKitDB.unitScanTargets
end

local function GetNpcID(guid)
	if not guid or IsSecret(guid) then
		return nil
	end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(npcID)
	end
	return nil
end

local function DisplayName(entry)
	if entry.name and entry.npcID then
		return string.format("%s (NPC %d)", entry.name, entry.npcID)
	end
	return entry.name or string.format("NPC %d", entry.npcID)
end

-- The entry matching a name and/or NPC ID, and its index.
local function FindEntry(name, npcID)
	local lowerName = name and name:lower()
	for index, entry in ipairs(GetTargets()) do
		if (npcID and entry.npcID == npcID) or (lowerName and entry.name and entry.name:lower() == lowerName) then
			return entry, index
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

local screenFrame

local function ShowScreenText(message)
	if not screenFrame then
		screenFrame = CreateFrame("Frame", nil, UIParent)
		screenFrame:SetSize(800, 50)
		screenFrame:SetPoint("CENTER", UIParent, "CENTER", 0, SCREEN_TEXT_Y)
		screenFrame:SetFrameStrata("HIGH")
		screenFrame:EnableMouse(false)
		local text = screenFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		local font, _, flags = text:GetFont()
		text:SetFont(font, SCREEN_TEXT_SIZE, flags)
		text:SetTextColor(unpack(SCREEN_TEXT_COLOR))
		text:SetAllPoints()
		screenFrame.text = text
		local fade = screenFrame:CreateAnimationGroup()
		local alpha = fade:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(0)
		alpha:SetStartDelay(SCREEN_TEXT_HOLD)
		alpha:SetDuration(SCREEN_TEXT_FADE)
		fade:SetScript("OnFinished", function()
			screenFrame:Hide()
		end)
		screenFrame.fade = fade
	end
	screenFrame.text:SetText(message)
	screenFrame.fade:Stop()
	screenFrame:Show()
	screenFrame.fade:Play()
end

---------------------------------------------------------------------------
-- Raid marker
---------------------------------------------------------------------------

-- GUIDs we've already handled, so we mark each unit once and never fight a
-- marker someone moved or removed afterwards.
local markedGUIDs = {}

local function TryMark(unit)
	if not ns:GetOption("unitScanMark") then
		return
	end
	local guid = UnitGUID(unit)
	if not guid or IsSecret(guid) or markedGUIDs[guid] then
		return
	end
	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		return
	end
	-- Setting the icon a unit already has removes it, so never touch marked units.
	local current = GetRaidTargetIndex(unit)
	local canMark = CanBeRaidTarget(unit)
	if IsSecret(current) or IsSecret(canMark) then
		return
	end
	markedGUIDs[guid] = true
	if current or not canMark then
		return
	end
	SetRaidTarget(unit, ns:GetValue("unitScanMarker") or 5)
end

---------------------------------------------------------------------------
-- Target button
---------------------------------------------------------------------------

local BUTTON_NAME = "NraKitScanTargetButton"
local BUTTON_SIZE = 36
local BUTTON_POSITION_KEY = "unitScanButtonPosition"
local DEFAULT_BUTTON_POSITION = { "CENTER", 0, 240 }

_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Target the unit Unit Scanner found"

local targetButton
-- Secure attributes, Show and Hide can't change in combat; these wait for REGEN_ENABLED.
local pendingName
local pendingHide = false

local function UpdateButtonIcon()
	if targetButton then
		targetButton.icon:SetTexture(MarkerTexture(ns:GetValue("unitScanMarker") or 5))
	end
end

-- A hidden button still answers its keybind, so forget the unit too.
local function ClearTarget()
	targetButton.name = nil
	targetButton:SetAttribute("macrotext", nil)
end

local function HideTargetButton()
	if not targetButton then
		return
	end
	pendingName = nil
	if InCombatLockdown() then
		-- Can't hide a secure button in combat; make it invisible until combat ends.
		targetButton:SetAlpha(0)
		pendingHide = true
	else
		targetButton:Hide()
		ClearTarget()
	end
end

local function SaveButtonPosition()
	local point, _, _, x, y = targetButton:GetPoint()
	NraKitDB[BUTTON_POSITION_KEY] = { point, x, y }
end

local function CreateTargetButton()
	local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("HIGH")
	button:SetClampedToScreen(true)
	button:SetMovable(true)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:RegisterForDrag("LeftButton")
	local position = NraKitDB[BUTTON_POSITION_KEY] or DEFAULT_BUTTON_POSITION
	button:SetPoint(position[1], UIParent, position[1], position[2], position[3])

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)

	button:SetAttribute("type", "macro")
	-- Right-click only dismisses (see PostClick); it must not target too.
	button:SetAttribute("type2", ATTRIBUTE_NOOP)

	button:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveButtonPosition()
	end)
	button:SetScript("PostClick", function(_, mouseButton, down)
		if mouseButton == "RightButton" and not down then
			HideTargetButton()
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Unit Scanner")
		GameTooltip:AddLine("Click to target: " .. (self.name or "?"), 1, 1, 1)
		GameTooltip:AddLine("Right-click to dismiss, Shift-drag to move.", 0.7, 0.7, 0.7)
		local key = GetBindingKey("CLICK " .. BUTTON_NAME .. ":LeftButton")
		if key then
			GameTooltip:AddLine("Key: " .. GetBindingText(key), 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	targetButton = button
	UpdateButtonIcon()
end

local function ShowTargetButton(name)
	if not targetButton then
		CreateTargetButton()
	end
	if InCombatLockdown() then
		pendingName = name
		return
	end
	pendingName = nil
	pendingHide = false
	targetButton.name = name
	targetButton:SetAttribute("macrotext", "/targetexact " .. name)
	targetButton.label:SetText(name)
	targetButton:SetAlpha(1)
	targetButton:Show()
end

local function OnCombatEnded()
	if pendingName then
		ShowTargetButton(pendingName)
	elseif pendingHide then
		pendingHide = false
		targetButton:Hide()
		targetButton:SetAlpha(1)
		ClearTarget()
	end
end

local function Alert(entry, source)
	local now = GetTime()
	if lastAlert[entry] and now - lastAlert[entry] < (ns:GetValue("unitScanCooldown") or 60) then
		return
	end
	lastAlert[entry] = now

	local name = entry.name or DisplayName(entry)
	if ns:GetOption("unitScanSound") then
		PlaySound(SOUNDKIT.RAID_WARNING, "Master")
	end
	if ns:GetOption("unitScanScreenText") then
		ShowScreenText(name .. " found!")
	end
	if ns:GetOption("unitScanChat") then
		ns:Print(string.format("|cffff4020%s|r found (%s).", name, SOURCE_LABELS[source] or source))
	end
	if ns:GetOption("unitScanFlash") then
		FlashClientIcon()
	end
	if ns:GetOption("unitScanButton") and entry.name then
		ShowTargetButton(entry.name)
	end
end

-- Checks one name / GUID pair against the list.
local function Check(name, guid, source, unit)
	if name and IsSecret(name) then
		name = nil
	end
	local npcID = GetNpcID(guid)
	if not name and not npcID then
		return
	end
	local entry = FindEntry(name, npcID)
	if not entry then
		return
	end
	-- Fill in what an entry added by ID (or by name) was missing, and take the
	-- unit's own spelling of the name (names match case-insensitively).
	if name then
		entry.name = name
	end
	if npcID and not entry.npcID then
		entry.npcID = npcID
	end
	if unit then
		TryMark(unit)
	end
	Alert(entry, source)
end

local function CheckUnit(unit, source)
	if not UnitExists(unit) then
		return
	end
	local dead = UnitIsDead(unit)
	if not IsSecret(dead) and dead then
		return
	end
	Check(UnitName(unit), UnitGUID(unit), source, unit)
end

local function CheckVignette(vignetteGUID)
	local info = vignetteGUID and C_VignetteInfo.GetVignetteInfo(vignetteGUID)
	if not info or IsSecret(info.onMinimap) or not info.onMinimap then
		return
	end
	if not IsSecret(info.isDead) and info.isDead then
		return
	end
	Check(info.name, info.objectGUID, "vignette")
end

local function ScanAll()
	if not ns:IsModuleEnabled(module.key) or #GetTargets() == 0 then
		return
	end
	for _, plate in pairs(C_NamePlate.GetNamePlates()) do
		if plate.unitToken then
			CheckUnit(plate.unitToken, "nameplate")
		end
	end
	if ns:GetOption("unitScanVignettes") then
		for _, vignetteGUID in ipairs(C_VignetteInfo.GetVignettes()) do
			CheckVignette(vignetteGUID)
		end
	end
end

---------------------------------------------------------------------------
-- Engaged-only nameplates integration
---------------------------------------------------------------------------

function ns:UnitScanWantsEnemyNameplates()
	return ns:IsModuleEnabled(module.key) and ns:GetOption("unitScanKeepPlates") and #GetTargets() > 0
end

---------------------------------------------------------------------------
-- Nameplate range
---------------------------------------------------------------------------

local RANGE_CVAR = "nameplateMaxDistance"
-- Above any client's limit; the game clamps it to its own maximum.
local MAX_RANGE = "100"
local SAVED_RANGE_KEY = "unitScanSavedPlateRange"

-- Raises the nameplate range while there's something to scan for, and puts the
-- user's value back otherwise. CVars can't change in combat; REGEN_ENABLED retries.
ApplyRange = function()
	if InCombatLockdown() or GetCVar(RANGE_CVAR) == nil then
		return
	end
	local want = ns:IsModuleEnabled(module.key) and ns:GetOption("unitScanMaxRange") and #GetTargets() > 0
	local saved = NraKitDB[SAVED_RANGE_KEY]
	if want then
		if saved == nil then
			NraKitDB[SAVED_RANGE_KEY] = GetCVar(RANGE_CVAR)
		end
		SetCVar(RANGE_CVAR, MAX_RANGE)
	elseif saved ~= nil then
		SetCVar(RANGE_CVAR, saved)
		NraKitDB[SAVED_RANGE_KEY] = nil
	end
end

local function NameplateNeedsChanged()
	if ns.RefreshEngagedNameplateCVars then
		ns:RefreshEngagedNameplateCVars()
	end
	ApplyRange()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local USAGE = {
	"/nra scan - add (or remove) your current target",
	"/nra scan <name> - add (or remove) a mob or player by exact name",
	"/nra scan <NPC ID> - add an NPC by its ID",
	"/nra scan list - show the list",
	"/nra scan remove <# or name> - remove from the list",
	"/nra scan clear - empty the list",
}

local function PrintUsage()
	ns:Print("Unit Scanner commands:")
	for _, line in ipairs(USAGE) do
		print("  " .. line)
	end
end

local function WarnIfInactive()
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Unit Scanner is turned off. Turn it on in /nra to start scanning.")
	elseif GetCVar("nameplateShowEnemies") == "0" and not ns:UnitScanWantsEnemyNameplates() then
		ns:Print("Enemy nameplates are off, so only mouseover, targets and minimap markers are scanned.")
	end
end

local function ListChanged()
	NameplateNeedsChanged()
	ScanAll()
end

local function Add(entry, quiet)
	table.insert(GetTargets(), entry)
	if quiet then
		-- Added from what you're looking at: don't alert for it right away.
		lastAlert[entry] = GetTime()
	end
	ns:Print("Scanning for " .. DisplayName(entry) .. ".")
	ListChanged()
	WarnIfInactive()
end

local function RemoveAt(index)
	local entry = table.remove(GetTargets(), index)
	lastAlert[entry] = nil
	if targetButton and entry.name and (targetButton.name == entry.name or pendingName == entry.name) then
		HideTargetButton()
	end
	ns:Print("No longer scanning for " .. DisplayName(entry) .. ".")
	NameplateNeedsChanged()
end

local function ToggleTarget()
	if not UnitExists("target") then
		PrintUsage()
		return
	end
	local name, guid = UnitName("target"), UnitGUID("target")
	if IsSecret(name) then
		ns:Print("Can't read your target's name here.")
		return
	end
	local npcID = GetNpcID(guid)
	local _, index = FindEntry(name, npcID)
	if index then
		RemoveAt(index)
	else
		Add({ name = name, npcID = npcID }, true)
	end
end

local function List()
	local targets = GetTargets()
	if #targets == 0 then
		ns:Print("The scan list is empty. Target a unit and type /nra scan, or /nra scan <name or NPC ID>.")
		return
	end
	ns:Print("Scanning for:")
	for index, entry in ipairs(targets) do
		print(string.format("  %d. %s", index, DisplayName(entry)))
	end
	WarnIfInactive()
end

local function Remove(argument)
	if argument == "" then
		PrintUsage()
		return
	end
	local index = tonumber(argument)
	if not index then
		local _
		_, index = FindEntry(argument, nil)
	end
	if index and GetTargets()[index] then
		RemoveAt(index)
	else
		ns:Print("Not on the list: " .. argument .. ". See /nra scan list.")
	end
end

local function Clear(argument)
	if argument:lower() ~= "confirm" then
		ns:Print(string.format("This removes all %d entries. Type /nra scan clear confirm to do it.", #GetTargets()))
		return
	end
	wipe(GetTargets())
	wipe(lastAlert)
	HideTargetButton()
	ns:Print("The scan list is now empty.")
	NameplateNeedsChanged()
end

local function OnSlashCommand(input)
	local command, rest = input:match("^(%S*)%s*(.-)$")
	command = command:lower()
	if input == "" then
		ToggleTarget()
	elseif command == "list" then
		List()
	elseif command == "remove" or command == "rm" or command == "del" then
		Remove(rest)
	elseif command == "clear" then
		Clear(rest)
	elseif command == "help" then
		PrintUsage()
	else
		if command == "add" and rest ~= "" then
			input = rest
		end
		local npcID = input:match("^%d+$") and tonumber(input)
		local entry, index = FindEntry(not npcID and input or nil, npcID)
		if entry then
			if command == "add" or npcID then
				ns:Print(DisplayName(entry) .. " is already on the list.")
			else
				RemoveAt(index)
			end
		elseif npcID then
			Add({ npcID = npcID })
		else
			Add({ name = input })
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
	local arg12 = select(10, ...)
	if event == "PLAYER_REGEN_ENABLED" then
		ApplyRange()
		OnCombatEnded()
		return
	end
	if #GetTargets() == 0 then
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" then
		CheckUnit(arg1, "nameplate")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		CheckUnit("mouseover", "mouseover")
	elseif event == "PLAYER_TARGET_CHANGED" then
		CheckUnit("target", "target")
	elseif event == "PLAYER_FOCUS_CHANGED" then
		CheckUnit("focus", "focus")
	elseif event == "UNIT_TARGET" then
		if type(arg1) == "string" and (arg1:match("^party%d$") or arg1:match("^raid%d+$")) then
			CheckUnit(arg1 .. "target", "group")
		end
	elseif CHAT_SOURCES[event] then
		if ns:GetOption("unitScanChatSources") then
			-- Payload: text, sender name, ..., sender GUID (12th).
			Check(arg2, arg12, CHAT_SOURCES[event])
		end
	elseif event == "VIGNETTE_MINIMAP_UPDATED" then
		if ns:GetOption("unitScanVignettes") then
			CheckVignette(arg1)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		ScanAll()
	end
end)

local EVENTS = {
	"NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
	"UNIT_TARGET", "VIGNETTE_MINIMAP_UPDATED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}
for event in pairs(CHAT_SOURCES) do
	table.insert(EVENTS, event)
end

function module:OnInitialize()
	ns:RegisterSlashCommand("scan", OnSlashCommand)
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
	-- Restore a deferred range change even if the module was switched off mid-combat.
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	if not enabled then
		HideTargetButton()
	end
	NameplateNeedsChanged()
	ScanAll()
end

function module:OnOptionChanged(key)
	if key == "unitScanKeepPlates" or key == "unitScanMaxRange" then
		NameplateNeedsChanged()
	elseif key == "unitScanMarker" then
		UpdateButtonIcon()
	elseif key == "unitScanButton" and not ns:GetOption("unitScanButton") then
		HideTargetButton()
	end
end

ns:RegisterModule(module)
