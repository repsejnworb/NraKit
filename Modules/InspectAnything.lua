local _, ns = ...

-- Inspect anything: one key (Key Bindings > NraKit) for the unit under the mouse, or your
-- target, opens NraKit's inspect window: the frame, size and place of Blizzard's, with the
-- 3D model to turn (drag), move (right-drag) and zoom (mouse wheel).
--
-- Players: their gear in slots around the model (tooltips, Shift-click to link), average
-- item level and spec. The gear is asked for (NotifyInspect) and copied when it arrives
-- (INSPECT_READY), so the window keeps showing it when they run off, change target or leave
-- your group: it only changes when you press the key again, and only closes when you close
-- it. The server doesn't always answer (and answers late in combat; players inspected
-- before answer at once), so it's asked again every couple of seconds while they're near,
-- for a while, and again when combat ends. "Blizzard's inspect" opens the real window (talents, PvP, guild) while they're near
-- and you're out of combat; "Dressing room" tries their outfit on.
--
-- NPCs: the model, level and type, max health and attack speed, and "Abilities on Wowhead"
-- (addons can't see NPC abilities: their casts are secret). An NPC's max health is always a
-- secret value and its attack speed is in combat: a secret can still be shown as it is (a
-- FontString takes it) but not formatted, so health shows as a plain number, and what
-- can't be read at all is left out.
--
-- Right-clicking an NPC or enemy player (target, focus) also offers "View 3D model".
--
-- The window is a UI panel (RegisterUIPanel, a "left" panel like the inspect window), so out
-- of combat it's opened with ShowUIPanel and other panels (the dressing room, your bags'
-- windows) push it aside instead of opening behind it. Addons can't show or hide panels in
-- combat (Blizzard blocks it), so in combat it's shown and hidden directly, in the same place.

local module = {
	key = "inspectAnything",
	section = "Utilities",
	name = "Inspect anything",
	description = "One key (Key Bindings > NraKit) inspects what's under the mouse or your target, in a window like the inspect window that stays open until you close it: players with their gear (it loads after combat if needed), and NPCs as a 3D model you can turn, move and zoom.",
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
local SLOT_SIZE, SLOT_GAP = 37, 4
local RETRY_EVERY, RETRIES = 2, 8 -- seconds between asking again for gear, and how often
-- Right-click menus that get "View 3D model": NPCs (target and focus) and enemy players.
local MENU_TAGS = { "TARGET", "FOCUS", "ENEMY_PLAYER" }
local TURN_SPEED = 0.02 -- radians per pixel dragged
local MOVE_SPEED = 0.005 -- model units per pixel dragged
local MIN_ZOOM, MAX_ZOOM, ZOOM_STEP = 0.3, 3, 0.1

-- The inspect window's slots: { slot name, inventory slot ID }, left column, right column,
-- then the weapons along the bottom.
local LEFT_SLOTS = {
	{ "HeadSlot", 1 }, { "NeckSlot", 2 }, { "ShoulderSlot", 3 }, { "BackSlot", 15 },
	{ "ChestSlot", 5 }, { "ShirtSlot", 4 }, { "TabardSlot", 19 }, { "WristSlot", 9 },
}
local RIGHT_SLOTS = {
	{ "HandsSlot", 10 }, { "WaistSlot", 6 }, { "LegsSlot", 7 }, { "FeetSlot", 8 },
	{ "Finger0Slot", 11 }, { "Finger1Slot", 12 }, { "Trinket0Slot", 13 }, { "Trinket1Slot", 14 },
}
-- Forever has the ranged slot (like Blizzard's "Camelot" inspect window it uses).
local WEAPON_SLOTS = { { "MainHandSlot", 16 }, { "SecondaryHandSlot", 17 }, { "RangedSlot", 18 } }

local UI = ns.UI
local inspect = {}
ns.inspectAnything = inspect

local frame, model, subtitle, statusText, stats, slotButtons, modelBorder
local wowheadButton, blizzardButton, dressUpButton
local shown -- what the window shows: { guid, isPlayer, npcID, name }
local gear = {} -- [guid] = { items = { [slotID] = link }, itemLevel, spec, outfit }, this session
local waitingGUID -- the player whose gear was asked for and hasn't arrived
local retries, sinceRetry = 0, 0
local retryFrame = CreateFrame("Frame")
retryFrame:Hide()
local view = { facing = 0, x = 0, y = 0, zoom = 1 }
local startFacing = 0 -- the model's own angle when shown, which Reset view goes back to
local dragging, lastX, lastY

-- Secret values can't even be compared, so this is checked first.
local function Readable(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value ~= nil
end

local function IsPlayerUnit(unit)
	local isPlayer = UnitIsPlayer(unit)
	return Readable(isPlayer) and isPlayer == true
end

-- "Level 32 Elite Beast (Wolf)", "Level 40 Human Warrior": what can be read of it.
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
	if IsPlayerUnit(unit) then
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

-- The unit token that's now this GUID (target, mouseover, focus, group, nameplates).
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

------------------------------------------------------------------------------
-- Header lines
------------------------------------------------------------------------------

-- "Health 1,234   Attack speed 2.0 s" (NPCs): label and value pairs, left to right, leaving
-- out the ones that can't be shown.
local function UpdateStats(unit)
	local values, show = {}, {} -- values[key] is only looked at when show[key]: a secret can't be compared to nil
	if unit then
		local health = UnitHealthMax(unit)
		local speed = UnitAttackSpeed(unit)
		if issecretvalue and issecretvalue(health) then
			values.health, show.health = health, true -- an NPC's: shown as it is
		elseif health and health > 0 then
			values.health, show.health = BreakUpLargeNumbers and BreakUpLargeNumbers(health) or tostring(health), true
		end
		if Readable(speed) and speed > 0 then
			values.speed, show.speed = string.format("%.1f s", speed), true
		end
	end
	local anchor
	for _, key in ipairs({ "health", "speed" }) do
		local pair = stats[key]
		pair.label:SetShown(show[key] == true)
		pair.value:SetShown(show[key] == true)
		if show[key] then
			pair.value:SetText(values[key])
			pair.label:ClearAllPoints()
			if anchor then
				pair.label:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
			else
				pair.label:SetPoint("TOPLEFT", model, "TOPLEFT", 10, -8)
			end
			anchor = pair.value
		end
	end
end

-- "Fury  ·  Item level 32.4" once their gear is in, else how it's going (players).
local function UpdateStatus()
	if not (shown and shown.isPlayer) then
		statusText:Hide()
		return
	end
	statusText:Show()
	statusText:SetFontObject(gear[shown.guid] and "GameFontNormal" or "GameFontHighlightSmall")
	local data = gear[shown.guid]
	if data then
		local parts = {}
		if data.spec and data.spec ~= shown.class then -- Forever has no specs: the game names the class
			table.insert(parts, data.spec)
		end
		if data.itemLevel and data.itemLevel > 0 then
			table.insert(parts, string.format("Item level %.1f", data.itemLevel))
		end
		statusText:SetText(table.concat(parts, "  ·  "))
		statusText:SetTextColor(1, 0.82, 0)
		statusText:SetShown(#parts > 0)
	elseif waitingGUID == shown.guid then
		statusText:SetText(InCombatLockdown() and "Their gear loads after combat..." or "Loading their gear...")
		statusText:SetTextColor(0.6, 0.6, 0.6)
	else
		statusText:SetText("Their gear can't be read now: too far away?")
		statusText:SetTextColor(0.6, 0.6, 0.6)
	end
end

------------------------------------------------------------------------------
-- Gear slots
------------------------------------------------------------------------------

local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
end

local function UpdateSlots()
	local data = shown and shown.isPlayer and gear[shown.guid]
	for _, button in ipairs(slotButtons) do
		button:SetShown(shown ~= nil and shown.isPlayer)
		local link = data and data.items[button.slotID]
		button.link = link
		if link then
			button.icon:SetTexture(select(5, C_Item.GetItemInfoInstant(link)) or 134400)
			local quality = select(3, C_Item.GetItemInfo(link)) -- nil until loaded; refreshed then
			local r, g, b = QualityColor(quality)
			button.border:SetShown(r ~= nil and quality >= (Enum.ItemQuality.Uncommon or 2))
			if r then
				button.border:SetVertexColor(r, g, b)
			end
		else
			button.icon:SetTexture(button.emptyTexture)
			button.border:Hide()
		end
	end
end

local function OnSlotEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.link then
		GameTooltip:SetHyperlink(self.link)
	else
		GameTooltip_SetTitle(GameTooltip, _G[string.upper(self.slotName)] or self.slotName)
	end
	GameTooltip:Show()
end

-- Shift-click links it in chat, Ctrl-click previews it, like your own gear.
local function OnSlotClick(self)
	if self.link then
		HandleModifiedItemClick(self.link)
	end
end

local function CreateSlot(info)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(SLOT_SIZE, SLOT_SIZE)
	button.slotName, button.slotID = info[1], info[2]
	local _, emptyTexture = GetInventorySlotInfo(info[1])
	button.emptyTexture = emptyTexture
	-- The inspect window's slot: a dark socket behind, the quick-slot frame around.
	local socket = button:CreateTexture(nil, "BACKGROUND")
	socket:SetAtlas("UI-Character-Info-GearSlot", true)
	socket:SetPoint("CENTER")
	button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	local normal = button:GetNormalTexture()
	if normal then
		normal:ClearAllPoints()
		normal:SetSize(64, 64)
		normal:SetPoint("CENTER", 0, -1)
	end
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	button.border:SetAllPoints()
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.15)
	button:SetScript("OnEnter", OnSlotEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", OnSlotClick)
	table.insert(slotButtons, button)
	return button
end

------------------------------------------------------------------------------
-- Model
------------------------------------------------------------------------------

local function ApplyView()
	model:SetFacing(view.facing)
	model:SetPosition(0, view.x, view.y)
	model:SetCamDistanceScale(view.zoom)
end

function inspect.ResetView()
	view.facing, view.x, view.y, view.zoom = startFacing, 0, 0, 1
	ApplyView()
end

-- Players: between the slot columns, above the weapons (where the inspect window has its
-- model). NPCs: the whole inset. The black backdrop and the frame around it follow.
local function LayoutModel(isPlayer)
	local inset = frame.Inset
	local left, right, top, bottom = 4, 4, 4, 4
	if isPlayer then
		left, right, bottom = 46, 47, SLOT_SIZE + 12
	end
	modelBorder:ClearAllPoints()
	modelBorder:SetPoint("TOPLEFT", inset, "TOPLEFT", left, -top)
	modelBorder:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -right, bottom)
	model:ClearAllPoints()
	model:SetPoint("TOPLEFT", modelBorder, "TOPLEFT", 4, -4)
	model:SetPoint("BOTTOMRIGHT", modelBorder, "BOTTOMRIGHT", -4, 4)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

-- Where Blizzard puts the inspect window (a "left" panel), read from its panel layout.
local function PlaceLikeInspect()
	local left = GetUIPanelLayoutAttribute and GetUIPanelLayoutAttribute("LEFT_OFFSET") or 16
	local top = GetUIPanelLayoutAttribute and GetUIPanelLayoutAttribute("TOP_OFFSET") or -116
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, top)
end

-- Opens it as a panel out of combat, directly in combat.
local function Open()
	if frame:IsShown() then
		return
	end
	if InCombatLockdown() then
		PlaceLikeInspect()
		frame:Show()
	else
		ShowUIPanel(frame)
	end
end

local function Close()
	if not frame:IsShown() then
		return
	end
	if InCombatLockdown() then
		frame:Hide()
	else
		HideUIPanel(frame)
	end
end

local function OpenBlizzardInspect()
	if not shown then
		return
	end
	if InCombatLockdown() then
		ns:Print("Blizzard's inspect window can't be opened by addons in combat.")
		return
	end
	local unit = FindUnit(shown.guid)
	if not (unit and CanInspect(unit)) then
		ns:Print("They need to be near you (and targeted or in sight) for Blizzard's inspect window.")
		return
	end
	Close() -- it opens in the same place
	InspectUnit(unit)
end

local function CreateButton(label, width, onClick, tooltip)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, label, tooltip)
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function CreateWindow()
	-- The inspect window's frame (portrait, title, inset, close button).
	frame = CreateFrame("Frame", "NraKitModelViewer", UIParent, "ButtonFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	RegisterUIPanel(frame, { area = "left", pushable = 1, whileDead = 1 })
	table.insert(UISpecialFrames, "NraKitModelViewer") -- Esc, also when shown in combat
	if type(frame.CloseButton) == "table" then
		frame.CloseButton:SetScript("OnClick", Close) -- the template's would use HideUIPanel even in combat
	end
	frame:SetScript("OnEvent", function()
		UpdateSlots() -- GET_ITEM_INFO_RECEIVED: an item's quality came in
	end)
	frame:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	end)
	frame:HookScript("OnHide", function(self)
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end)

	-- The title in white and the level line centred under it, as in the inspect window.
	if frame.GetTitleText and frame:GetTitleText() then
		frame:GetTitleText():SetFontObject("GameFontHighlight")
	end
	subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2Outline")
	subtitle:SetPoint("TOP", 0, -40)
	subtitle:SetWidth(WIDTH - 110)
	subtitle:SetWordWrap(false)
	stats = {}
	for _, info in ipairs({ { "health", "Health" }, { "speed", "Attack speed" } }) do
		local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetText(info[2])
		local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("LEFT", label, "RIGHT", 4, 0)
		stats[info[1]] = { label = label, value = value }
	end

	-- The model area: black, in the character frame's inner border (Blizzard's textures).
	local inset = frame.Inset
	modelBorder = CreateFrame("Frame", nil, inset)
	local backdrop = modelBorder:CreateTexture(nil, "BACKGROUND", nil, 1)
	backdrop:SetPoint("TOPLEFT", 3, -3)
	backdrop:SetPoint("BOTTOMRIGHT", -3, 3)
	backdrop:SetColorTexture(0, 0, 0, 1)
	local corners = {}
	for _, corner in ipairs({ { "UpperLeft", "TOPLEFT" }, { "UpperRight", "TOPRIGHT" },
		{ "LowerLeft", "BOTTOMLEFT" }, { "LowerRight", "BOTTOMRIGHT" } }) do
		local texture = modelBorder:CreateTexture(nil, "OVERLAY", "Char-Corner-" .. corner[1])
		texture:SetPoint(corner[2])
		corners[corner[2]] = texture
	end
	for _, side in ipairs({ { "Left", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", "TOPLEFT" },
		{ "Right", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", "TOPRIGHT" },
		{ "Top", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", "TOPLEFT" },
		{ "Bottom", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT" } }) do
		-- Between its two corners.
		local texture = modelBorder:CreateTexture(nil, "OVERLAY", "Char-Inner-" .. side[1])
		local horizontal = side[1] == "Top" or side[1] == "Bottom"
		texture:SetPoint(side[2], corners[side[2]], horizontal and side[3] or side[4])
		texture:SetPoint(side[4], corners[side[4]], horizontal and side[5] or side[2])
	end

	model = CreateFrame("PlayerModel", nil, modelBorder)
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
	-- Spec and item level (players), or how loading their gear is going, at the top of the model.
	statusText = model:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOP", 0, -8)
	statusText:SetWidth(WIDTH - 110)
	statusText:SetWordWrap(false)

	-- Gear slots, where the inspect window has them.
	slotButtons = {}
	local previous
	for _, info in ipairs(LEFT_SLOTS) do
		local button = CreateSlot(info)
		if previous then
			button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -SLOT_GAP)
		else
			button:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -2)
		end
		previous = button
	end
	previous = nil
	for _, info in ipairs(RIGHT_SLOTS) do
		local button = CreateSlot(info)
		if previous then
			button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -SLOT_GAP)
		else
			button:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -4, -2)
		end
		previous = button
	end
	-- The weapons, centred along the bottom.
	local weaponsWidth = #WEAPON_SLOTS * SLOT_SIZE + (#WEAPON_SLOTS - 1) * 5
	for index, info in ipairs(WEAPON_SLOTS) do
		local button = CreateSlot(info)
		button:SetPoint("BOTTOMLEFT", inset, "BOTTOM", -weaponsWidth / 2 + (index - 1) * (SLOT_SIZE + 5), 6)
	end

	-- Buttons along the bottom edge.
	local reset = CreateButton("Reset view", 90, inspect.ResetView,
		"Drag the model to turn it, right-drag to move it and use the mouse wheel to zoom. This puts it back.")
	reset:SetPoint("BOTTOMRIGHT", -6, 3)
	wowheadButton = CreateButton("Abilities on Wowhead", 150, function()
		if shown and shown.npcID then
			ns.wowheadLink.Show("npc", shown.npcID, shown.name)
		end
	end, "The game doesn't tell addons what NPCs can do. This gives you a link to its Wowhead page (abilities, loot, where it is) to copy into your browser.")
	wowheadButton:SetPoint("BOTTOMLEFT", 4, 3)
	blizzardButton = CreateButton("Blizzard's inspect", 118, OpenBlizzardInspect,
		"Open the game's own inspect window (talents, PvP, guild). Only while they're near you, and not in combat.")
	blizzardButton:SetPoint("BOTTOMLEFT", 4, 3)
	dressUpButton = CreateButton("Dressing room", 104, function()
		local data = shown and gear[shown.guid]
		if data and data.outfit and DressUpItemTransmogInfoList then
			DressUpItemTransmogInfoList(data.outfit)
		end
	end, "Try their outfit on in the dressing room.")
	dressUpButton:SetPoint("LEFT", blizzardButton, "RIGHT", 2, 0)
end

local function UpdateDressUpButton()
	local data = shown and shown.isPlayer and gear[shown.guid]
	dressUpButton:SetEnabled(data ~= nil and data ~= false and data.outfit ~= nil)
end

-- Fills the window from a unit: model, title, header lines, and gear or NPC buttons.
local function Show(unit)
	if not frame then
		CreateWindow()
	end
	local guid = UnitGUID(unit)
	local name, surname = UnitName(unit)
	local isPlayer = IsPlayerUnit(unit) and Readable(guid)
	shown = {
		guid = Readable(guid) and guid or nil,
		isPlayer = isPlayer,
		npcID = not isPlayer and ns.wowheadLink and ns.wowheadLink.NpcIDFromGUID(guid) or nil,
		name = Readable(name) and name or nil,
		class = isPlayer and UnitClass(unit) or nil,
	}
	if Readable(name) and Readable(surname) and surname ~= "" then
		frame:SetTitle(name .. " " .. surname)
	else
		frame:SetTitle(name) -- may be secret; the title text takes it as it is
	end
	frame:SetPortraitToUnit(unit)
	subtitle:SetText(Describe(unit))
	UpdateStats(not isPlayer and unit or nil)
	UpdateStatus()
	UpdateSlots()
	LayoutModel(isPlayer)
	wowheadButton:SetShown(shown.npcID ~= nil)
	blizzardButton:SetShown(isPlayer)
	dressUpButton:SetShown(isPlayer)
	UpdateDressUpButton()
	Open()
	model:ClearModel()
	model:SetUnit(unit)
	startFacing = model:GetFacing() or 0 -- the slight angle the game shows models at
	inspect.ResetView()
end

-- Shows a unit without asking for gear (NPCs, the right-click menu).
function inspect.ShowModel(unit)
	Show(unit)
end

-- Their gear arrived: copy it, it's only readable while the unit is around.
local function ReadGear(guid)
	local unit = FindUnit(guid)
	if not unit then
		return false
	end
	local data = { items = {} }
	for _, list in ipairs({ LEFT_SLOTS, RIGHT_SLOTS, WEAPON_SLOTS }) do
		for _, info in ipairs(list) do
			data.items[info[2]] = GetInventoryItemLink(unit, info[2])
		end
	end
	data.itemLevel = C_PaperDollInfo.GetInspectItemLevel(unit)
	local specID = GetInspectSpecialization(unit)
	if specID and specID > 0 then
		data.spec = select(2, GetSpecializationInfoByID(specID))
	end
	data.outfit = C_TransmogCollection.GetInspectItemTransmogInfoList()
	gear[guid] = data
	-- Blizzard's inspect window does the same when it closes; leave it be while it's open.
	if not (InspectFrame and InspectFrame:IsShown()) then
		ClearInspectPlayer()
	end
	return true
end

local function StopWaiting()
	waitingGUID = nil
	retryFrame:Hide()
end

-- Asks for their gear, and keeps asking every few seconds until it comes (or for a while).
local function StartWaiting(unit, guid)
	waitingGUID, retries, sinceRetry = guid, 0, 0
	retryFrame:Show()
	NotifyInspect(unit)
end

local function Refresh()
	if frame and frame:IsShown() and shown then
		UpdateStatus()
		UpdateSlots()
		UpdateDressUpButton()
	end
end

-- The key.
function inspect.Inspect()
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	local unit = (UnitExists("mouseover") and "mouseover") or (UnitExists("target") and "target")
	if not unit then
		ns:Print("Point at or target someone to inspect them.")
		return
	end
	Show(unit)
	StopWaiting()
	if not shown.isPlayer then
		return
	end
	if CanInspect(unit) then
		StartWaiting(unit, shown.guid)
		if InCombatLockdown() and not gear[shown.guid] then
			ns:Print("Their gear shows up after combat (the game answers late in combat).")
		end
	elseif not gear[shown.guid] then
		ns:Print("You can't inspect them right now (too far away?), so here's their model.")
	end
	UpdateStatus()
end

retryFrame:SetScript("OnUpdate", function(_, elapsed)
	sinceRetry = sinceRetry + elapsed
	if sinceRetry < RETRY_EVERY then
		return
	end
	sinceRetry = 0
	retries = retries + 1
	if retries > RETRIES then
		StopWaiting() -- given up; pressing the key again starts over
		Refresh()
		return
	end
	local unit = FindUnit(waitingGUID)
	if unit and CanInspect(unit) then
		NotifyInspect(unit)
	end
end)

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, guid)
	if event == "INSPECT_READY" then
		if guid and guid == waitingGUID and ReadGear(guid) then
			StopWaiting()
			Refresh()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Answers in combat are often dropped: ask again, with fresh retries.
		local unit = waitingGUID and FindUnit(waitingGUID)
		if unit and CanInspect(unit) then
			StartWaiting(unit, waitingGUID)
		end
		Refresh()
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
_G["BINDING_NAME_NRAKIT_INSPECT_ANYTHING"] = "Inspect anything (players with their gear, NPCs as a 3D model)"
function NraKit_InspectAnything()
	inspect.Inspect()
end

function module:OnInitialize()
	eventFrame:RegisterEvent("INSPECT_READY")
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs(MENU_TAGS) do
			Menu.ModifyMenu("MENU_UNIT_" .. tag, OnUnitMenu)
		end
	end
end

function module:OnEnabledChanged(enabled)
	if not enabled and frame then
		Close()
	end
end

ns:RegisterModule(module)
