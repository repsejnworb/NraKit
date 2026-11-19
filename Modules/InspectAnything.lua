local _, ns = ...

-- Inspect anything: one key (Key Bindings > NraKit) for the unit under the mouse,
-- or your target. Players you can inspect get Blizzard's inspect window; NPCs (and players
-- you can't inspect) get a model viewer: their 3D model to turn (drag), move (right-drag)
-- and zoom (mouse wheel). While it's open it can follow your target. It opens where the
-- inspect window does. Right-clicking an NPC or enemy player (target, focus) also offers
-- "View 3D model".
--
-- Names, levels and types can be secret values (instances, combat); the model still shows,
-- the line under the title just leaves out what it can't read.

local module = {
	key = "inspectAnything",
	section = "Utilities",
	name = "Inspect anything",
	description = "One key (Key Bindings > NraKit) inspects what's under the mouse or your target: players as normal, and NPCs in a model viewer where you can turn, move and zoom their 3D model.",
	default = false,
	options = {
		{
			key = "inspectAnythingFollowTarget",
			name = "Follow your target",
			description = "While the model viewer is open, show whoever you target next.",
			default = true,
		},
		{
			key = "inspectAnythingMenu",
			name = "In the right-click menu",
			description = "Add \"View 3D model\" to the right-click menu of NPCs and enemy players (target and focus frames).",
			default = true,
		},
	},
}

local WIDTH, HEIGHT = 380, 520
local SUBTITLE_HEIGHT = 26
-- Right-click menus that get "View 3D model": NPCs (target and focus) and enemy players.
local MENU_TAGS = { "TARGET", "FOCUS", "ENEMY_PLAYER" }
local FOOTER_HEIGHT = 30
local TURN_SPEED = 0.02 -- radians per pixel dragged
local MOVE_SPEED = 0.005 -- model units per pixel dragged
local MIN_ZOOM, MAX_ZOOM, ZOOM_STEP = 0.3, 3, 0.1

local UI = ns.UI
local inspect = {}
ns.inspectAnything = inspect

local frame, model, subtitle
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
	end
	return table.concat(parts, " ")
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
	frame = UI.CreateWindow("NraKitModelViewer", "", WIDTH, HEIGHT, 0)
	local body = frame.body

	subtitle = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	subtitle:SetPoint("TOPLEFT", UI.PAD + 2, -8)
	subtitle:SetPoint("RIGHT", -UI.PAD, 0)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetWordWrap(false)

	-- A soft spotlight behind the model.
	local backdrop = body:CreateTexture(nil, "BACKGROUND")
	backdrop:SetPoint("TOPLEFT", 1, -SUBTITLE_HEIGHT)
	backdrop:SetPoint("BOTTOMRIGHT", -1, FOOTER_HEIGHT)
	backdrop:SetColorTexture(1, 1, 1, 1)
	backdrop:SetGradient("VERTICAL", CreateColor(0.02, 0.02, 0.03, 1), CreateColor(0.12, 0.12, 0.15, 1))

	model = CreateFrame("PlayerModel", nil, body)
	model:SetPoint("TOPLEFT", 1, -SUBTITLE_HEIGHT)
	model:SetPoint("BOTTOMRIGHT", -1, FOOTER_HEIGHT)
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

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	local hint = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", UI.PAD, 0)
	hint:SetText("Drag to turn, right-drag to move, wheel to zoom")
	local reset = UI.CreateFlatButton(footer, "Reset view", 20)
	reset:SetPoint("RIGHT", -UI.PAD + 4, 0)
	reset:SetScript("OnClick", function()
		inspect.ResetView()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
end

-- Shows a unit in the model viewer.
function inspect.ShowModel(unit)
	if not frame then
		CreateViewer()
	end
	local name, surname = UnitName(unit)
	if Readable(name) and Readable(surname) and surname ~= "" then
		frame.title:SetText(name .. " " .. surname)
	else
		frame.title:SetText(name) -- may be secret; FontStrings take it as it is
	end
	subtitle:SetText(Describe(unit))
	if not frame:IsShown() then
		PlaceLikeInspect() -- it can be dragged, but opens there each time
	end
	frame:Show()
	model:ClearModel()
	model:SetUnit(unit)
	inspect.ResetView()
	inspect.unit = unit
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
			InspectUnit(unit)
			return
		end
		ns:Print("The inspect window can't open in combat, so here's their model.")
	end
	inspect.ShowModel(unit)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
	-- PLAYER_TARGET_CHANGED
	if frame and frame:IsShown() and ns:IsModuleEnabled(module.key) and ns:GetOption("inspectAnythingFollowTarget")
		and UnitExists("target") then
		inspect.ShowModel("target")
	end
end)

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
	eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
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
