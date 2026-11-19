local _, ns = ...

-- Inspect anything: one key (Key Bindings > NraKit) for the unit under the mouse,
-- or your target. Players you can inspect get Blizzard's inspect window; NPCs (and players
-- you can't inspect) get a model viewer made to look like it: same frame, size and place,
-- with their 3D model to turn (drag), move (right-drag) and zoom (mouse wheel). It only
-- changes when you press the key again. Right-clicking an NPC or enemy player (target,
-- focus) also offers "View 3D model".
--
-- Addons can't open the inspect window in combat (it's a UI panel; the game blocks it with
-- "Interface action failed because of an AddOn"), so in combat a player gets the viewer, and
-- when combat ends, if it still shows them, the real inspect window takes its place (found
-- again by GUID among target, mouseover, focus, group and nameplates).
--
-- Under the title: level, classification and type, then max health and attack speed. The
-- game keeps an NPC's max health secret (always) and its attack speed in combat: a secret
-- value can still be shown as it is (a FontString takes it), but not formatted, so health
-- shows as a plain number. What can't be read at all is left out. Abilities aren't
-- available to addons (NPC casts are secret), so "Abilities on Wowhead" opens the copy-link
-- box with the NPC's Wowhead page instead.

local module = {
	key = "inspectAnything",
	section = "Utilities",
	name = "Inspect anything",
	description = "One key (Key Bindings > NraKit) inspects what's under the mouse or your target: players as normal, and NPCs in a model viewer where you can turn, move and zoom their 3D model.",
	default = false,
	options = {
		{
			key = "inspectAnythingMenu",
			name = "In the right-click menu",
			description = "Add \"View 3D model\" to the right-click menu of NPCs and enemy players (target and focus frames).",
			default = true,
		},
	},
}

-- Blizzard's inspect window is a standard panel: 338 x 424.
local WIDTH, HEIGHT = PANEL_DEFAULT_WIDTH or 338, PANEL_DEFAULT_HEIGHT or 424
-- Right-click menus that get "View 3D model": NPCs (target and focus) and enemy players.
local MENU_TAGS = { "TARGET", "FOCUS", "ENEMY_PLAYER" }
local TURN_SPEED = 0.02 -- radians per pixel dragged
local MOVE_SPEED = 0.005 -- model units per pixel dragged
local MIN_ZOOM, MAX_ZOOM, ZOOM_STEP = 0.3, 3, 0.1

local UI = ns.UI
local inspect = {}
ns.inspectAnything = inspect

local frame, model, subtitle, stats, wowheadButton
local npcID, npcName -- of the shown NPC, for its Wowhead page
local waitingGUID -- the player shown in combat, to inspect for real when combat ends
local view = { facing = 0, x = 0, y = 0, zoom = 1 }
local dragging, lastX, lastY

-- Secret values can't even be compared, so this is checked first.
local function Readable(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value ~= nil
end

-- "Level 32 Elite Beast", "Level 40 Human Warrior": what can be read of it.
local function Describe(unit)
	local parts = {}
	local level = UnitLevel(unit)
	if Readable(level) then
		table.insert(parts, level > 0 and ("Level " .. level) or "Level ??")
	end
	local classification = UnitClassification(unit)
	local labels = { elite = "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = "Boss" }
	if Readable(classification) and labels[classification] then
		table.insert(parts, labels[classification])
	end
	local isPlayer = UnitIsPlayer(unit)
	if Readable(isPlayer) and isPlayer then
		local race, class = UnitRace(unit), UnitClass(unit)
		if Readable(race) then
			table.insert(parts, race)
		end
		if Readable(class) then
			table.insert(parts, class)
		end
	else
		local creatureType = UnitCreatureType(unit)
		if Readable(creatureType) then
			table.insert(parts, creatureType)
		end
		local family = UnitCreatureFamily(unit) -- Wolf, Spider... (beasts)
		if Readable(family) and family ~= creatureType then
			table.insert(parts, "(" .. family .. ")")
		end
	end
	return table.concat(parts, " ")
end

-- "Health 1,234   Attack speed 2.0 s": label and value pairs, laid out left to right,
-- leaving out the ones that can't be shown.
local function UpdateStats(unit)
	local health = UnitHealthMax(unit)
	local speed = UnitAttackSpeed(unit)
	-- values[key] is only looked at when shown[key]: a secret can't even be compared to nil.
	local values, shown = {}, {}
	if issecretvalue and issecretvalue(health) then
		values.health, shown.health = health, true -- an NPC's: shown as it is
	elseif health and health > 0 then
		values.health, shown.health = BreakUpLargeNumbers and BreakUpLargeNumbers(health) or tostring(health), true
	end
	if Readable(speed) and speed > 0 then
		values.speed, shown.speed = string.format("%.1f s", speed), true
	end
	local anchor
	for _, key in ipairs({ "health", "speed" }) do
		local pair = stats[key]
		pair.label:SetShown(shown[key] == true)
		pair.value:SetShown(shown[key] == true)
		if shown[key] then
			pair.value:SetText(values[key])
			pair.label:ClearAllPoints()
			if anchor then
				pair.label:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
			else
				pair.label:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -4)
			end
			anchor = pair.value
		end
	end
end

local function UpdateWowheadButton(unit)
	npcID = ns.wowheadLink and ns.wowheadLink.NpcIDFromGUID(UnitGUID(unit))
	local name = UnitName(unit)
	npcName = Readable(name) and name or nil
	wowheadButton:SetShown(npcID ~= nil)
end

local function ApplyView()
	model:SetFacing(view.facing)
	model:SetPosition(0, view.x, view.y)
	model:SetCamDistanceScale(view.zoom)
end

function inspect.ResetView()
	view.facing, view.x, view.y, view.zoom = 0, 0, 0, 1
	ApplyView()
end

-- Where Blizzard puts the inspect window (a "left" panel), read from its panel layout.
local function PlaceLikeInspect()
	local left = GetUIPanelLayoutAttribute and GetUIPanelLayoutAttribute("LEFT_OFFSET") or 16
	local top = GetUIPanelLayoutAttribute and GetUIPanelLayoutAttribute("TOP_OFFSET") or -116
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, top)
end

local function CreateViewer()
	-- The inspect window's frame (portrait, title, inset, close button).
	frame = CreateFrame("Frame", "NraKitModelViewer", UIParent, "ButtonFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	table.insert(UISpecialFrames, "NraKitModelViewer")
	frame:HookScript("OnHide", function()
		waitingGUID = nil
	end)

	-- Level line and stats, under the title like the inspect window's level text.
	subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	subtitle:SetPoint("TOPLEFT", 64, -30)
	subtitle:SetPoint("RIGHT", -12, 0)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetWordWrap(false)

	stats = {}
	for _, info in ipairs({ { "health", "Health" }, { "speed", "Attack speed" } }) do
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetText(info[2])
		local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("LEFT", label, "RIGHT", 4, 0)
		stats[info[1]] = { label = label, value = value }
	end

	-- The model fills the inset, on a dark spotlight.
	local inset = frame.Inset
	local backdrop = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
	backdrop:SetPoint("TOPLEFT", 3, -3)
	backdrop:SetPoint("BOTTOMRIGHT", -3, 3)
	backdrop:SetColorTexture(1, 1, 1, 1)
	backdrop:SetGradient("VERTICAL", CreateColor(0.02, 0.02, 0.03, 1), CreateColor(0.14, 0.14, 0.17, 1))

	model = CreateFrame("PlayerModel", nil, inset)
	model:SetPoint("TOPLEFT", 3, -3)
	model:SetPoint("BOTTOMRIGHT", -3, 3)
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model:SetScript("OnMouseDown", function(_, button)
		dragging = button
		lastX, lastY = GetCursorPosition()
	end)
	model:SetScript("OnMouseUp", function()
		dragging = nil
	end)
	model:SetScript("OnHide", function()
		dragging = nil
	end)
	model:SetScript("OnUpdate", function(self)
		if not dragging then
			return
		end
		local x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		local dx, dy = (x - lastX) / scale, (y - lastY) / scale
		lastX, lastY = x, y
		if dragging == "LeftButton" then
			view.facing = view.facing + dx * TURN_SPEED
		elseif dragging == "RightButton" then
			view.x = view.x + dx * MOVE_SPEED
			view.y = view.y + dy * MOVE_SPEED
		end
		ApplyView()
	end)
	model:SetScript("OnMouseWheel", function(_, delta)
		view.zoom = math.min(math.max(view.zoom - delta * ZOOM_STEP, MIN_ZOOM), MAX_ZOOM)
		ApplyView()
	end)

	local hint = model:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 6)
	hint:SetText("Drag to turn, right-drag to move, wheel to zoom")

	-- Buttons along the bottom edge, like the inspect window's tabs area.
	local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reset:SetSize(100, 22)
	reset:SetPoint("BOTTOMRIGHT", -6, 3)
	reset:SetText("Reset view")
	reset:SetScript("OnClick", function()
		inspect.ResetView()
	end)

	wowheadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	wowheadButton:SetSize(150, 22)
	wowheadButton:SetPoint("BOTTOMLEFT", 4, 3)
	wowheadButton:SetText("Abilities on Wowhead")
	wowheadButton:SetScript("OnClick", function()
		if npcID then
			ns.wowheadLink.Show("npc", npcID, npcName)
		end
	end)
	wowheadButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Abilities on Wowhead",
			"The game doesn't tell addons what NPCs can do. This gives you a link to its Wowhead page (abilities, loot, where it is) to copy into your browser.")
	end)
	wowheadButton:SetScript("OnLeave", GameTooltip_Hide)
end

-- Shows a unit in the model viewer.
function inspect.ShowModel(unit)
	if not frame then
		CreateViewer()
	end
	local name, surname = UnitName(unit)
	if Readable(name) and Readable(surname) and surname ~= "" then
		frame:SetTitle(name .. " " .. surname)
	else
		frame:SetTitle(name) -- may be secret; the title text takes it as it is
	end
	frame:SetPortraitToUnit(unit)
	subtitle:SetText(Describe(unit))
	UpdateStats(unit)
	UpdateWowheadButton(unit)
	if not frame:IsShown() then
		PlaceLikeInspect() -- it can be dragged, but opens there each time
	end
	frame:Show()
	model:ClearModel()
	model:SetUnit(unit)
	inspect.ResetView()
	inspect.unit = unit
	waitingGUID = nil
end

-- The unit token that's now this player (target, mouseover, focus, group, nameplates).
local function FindUnit(guid)
	local tokens = { "target", "mouseover", "focus" }
	for index = 1, 4 do
		table.insert(tokens, "party" .. index)
	end
	for index = 1, 40 do
		table.insert(tokens, "raid" .. index)
		table.insert(tokens, "nameplate" .. index)
	end
	for _, token in ipairs(tokens) do
		local other = UnitGUID(token)
		if Readable(other) and other == guid then
			return token
		end
	end
end

-- Combat is over: swap the viewer for the real inspect window, if it still shows that player.
local function OnCombatEnded()
	local guid = waitingGUID
	waitingGUID = nil
	if not (guid and frame and frame:IsShown()) then
		return
	end
	local unit = FindUnit(guid)
	if unit and CanInspect(unit) then
		frame:Hide()
		InspectUnit(unit)
	else
		ns:Print("They're out of sight now, so the inspect window can't open. Press the key again when they're near.")
	end
end

-- The key: players you can inspect get the inspect window, everyone else the model viewer.
-- Addons can't open the inspect window in combat (it's a UI panel; the game blocks it with
-- "Interface action failed because of an AddOn"), so in combat players get the viewer too.
function inspect.Inspect()
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	local unit = (UnitExists("mouseover") and "mouseover") or (UnitExists("target") and "target")
	if not unit then
		ns:Print("Point at or target someone to inspect them.")
		return
	end
	if CanInspect(unit) then
		if not InCombatLockdown() then
			if frame then
				frame:Hide() -- one window: the inspect window takes the viewer's place
			end
			InspectUnit(unit)
			return
		end
		ns:Print("The inspect window can't open in combat: here's their model, and their gear once combat ends.")
		inspect.ShowModel(unit)
		local guid = UnitGUID(unit)
		waitingGUID = Readable(guid) and guid or nil
		return
	else
		-- NPCs simply get the viewer; a player you can't inspect is worth a word.
		local isPlayer = UnitIsPlayer(unit)
		if Readable(isPlayer) and isPlayer then
			ns:Print("You can't inspect them right now, so here's their model.")
		end
	end
	inspect.ShowModel(unit)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnCombatEnded) -- PLAYER_REGEN_ENABLED

local function OnUnitMenu(_, root, contextData)
	local unit = contextData and contextData.unit
	if not unit or not ns:IsModuleEnabled(module.key) or not ns:GetOption("inspectAnythingMenu") then
		return
	end
	root:CreateDivider()
	root:CreateButton("View 3D model", function()
		inspect.ShowModel(unit)
	end)
end

-- Key binding (Bindings.xml).
_G["BINDING_NAME_NRAKIT_INSPECT_ANYTHING"] = "Inspect anything (players as normal, NPCs as a 3D model)"
function NraKit_InspectAnything()
	inspect.Inspect()
end

function module:OnInitialize()
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(MENU_TAGS) do
			Menu.ModifyMenu("MENU_UNIT_" .. tag, OnUnitMenu)
		end
	end
end

function module:OnEnabledChanged(enabled)
	if not enabled and frame then
		frame:Hide()
	end
end

ns:RegisterModule(module)
