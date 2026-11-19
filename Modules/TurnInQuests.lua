local _, ns = ...

-- Quests to turn in: a small window (/nra done, or a key) listing your finished quests by the
-- zone you turn them in ("Wetlands: The Doomed Fleet, Seeking Caitlin"), the zone you're in
-- first, each with its level and in its difficulty colour as in the quest log ("[32] Malin's
-- Request" in yellow). Click a quest to open the map on it (its turn-in shows there); right-click
-- it, or click its round quest icon (the objective tracker's, drawn with the same textures), to
-- make it your waypoint; Shift-click to link it. Entering a zone with turn-ins says so (a small
-- toast you can click to open the list, and/or a chat line), and can open the window.
--
-- Zones are sorted by how far they are: the one you're in, then the others on your continent
-- nearest first (their map's centre, in world coordinates), then other continents.
--
-- For a finished quest, GetQuestUiMapID gives the turn-in's map on Forever (Hemet Nesingwary
-- shows Stranglethorn Vale, not where it's picked up); the quest log's heading is the fallback.
-- The map can't be opened by addons in combat, so a click then just says so.

local module = {
	key = "turnInQuests",
	section = "Quests",
	name = "Quests to turn in",
	description = "A small window (/nra done, or a key under Key Bindings > NraKit) listing your finished quests by the zone you turn them in. Click one to see it on the map, right-click to make it your waypoint. Entering a zone where you have quests to turn in says so in chat.",
	default = false,
	options = {
		{
			key = "turnInQuestsReminder",
			name = "Remind me when I enter the zone",
			description = "Say so when you enter a zone where you have finished quests to turn in.",
			default = true,
		},
		{
			key = "turnInQuestsToast",
			parent = "turnInQuestsReminder",
			name = "On screen",
			description = "A small message in the middle of the screen; click it to open the list.",
			default = true,
		},
		{
			key = "turnInQuestsChat",
			parent = "turnInQuestsReminder",
			name = "In chat",
			description = "A line in chat with the quests' names.",
			default = false,
		},
		{
			key = "turnInQuestsAutoOpen",
			name = "Open the window there",
			description = "Also open the window when you enter a zone where you have finished quests to turn in.",
			default = false,
		},
	},
}

local WIDTH = 300
local MAX_HEIGHT = 420
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 22
local TITLE_HEIGHT = 28
local PAD = 10

local UI = ns.UI
local turnIn = {}
ns.turnInQuests = turnIn

local frame, scroll
local pool = UI.CreatePool()
local lastZone -- the zone last reminded about, so moving around inside it says nothing new
local refreshQueued = false

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function CurrentZone()
	return GetRealZoneText and GetRealZoneText() or ""
end

-- Where a map is in the world: its continent and the world position of its centre (or the
-- player's own, for the player). nil when the game won't say.
local function WorldPosition(mapID, x, y)
	if not (mapID and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local continent, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x or 0.5, y or 0.5))
	if continent and position then
		local wx, wy = position:GetXY()
		return { continent = continent, x = wx, y = wy }
	end
end

local function PlayerPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		return WorldPosition(mapID, position:GetXY())
	end
end

-- Finished quests by turn-in zone: { { zone, mapID, quests = { { id, title, level } } } }, the
-- current zone first, then the nearest (same continent before others), then by name.
function turnIn.Zones()
	local byZone, zones, header = {}, {}, nil
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and info.isHeader then
			header = info.title
		elseif info and info.questID and C_QuestLog.IsComplete(info.questID) then
			local mapID = GetQuestUiMapID and GetQuestUiMapID(info.questID)
			local map = mapID and mapID > 0 and C_Map.GetMapInfo(mapID)
			local zone = map and map.name or header or "Other"
			if not byZone[zone] then
				byZone[zone] = { zone = zone, mapID = map and mapID or nil, quests = {} }
				table.insert(zones, byZone[zone])
			end
			local level = C_QuestLog.GetQuestDifficultyLevel(info.questID) or info.level
			table.insert(byZone[zone].quests, { id = info.questID, title = info.title, level = level })
		end
	end
	local here = CurrentZone()
	local player = PlayerPosition()
	for _, zone in ipairs(zones) do
		local position = player and WorldPosition(zone.mapID)
		if position and position.continent == player.continent then
			zone.distance = math.sqrt((position.x - player.x) ^ 2 + (position.y - player.y) ^ 2)
		end
	end
	table.sort(zones, function(a, b)
		if (a.zone == here) ~= (b.zone == here) then
			return a.zone == here
		end
		if (a.distance ~= nil) ~= (b.distance ~= nil) then
			return a.distance ~= nil -- this continent before the others
		end
		if a.distance and a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.zone < b.zone
	end)
	return zones
end

function turnIn.Count()
	local count = 0
	for _, zone in ipairs(turnIn.Zones()) do
		count = count + #zone.quests
	end
	return count
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function ShowOnMap(questID)
	if InCombatLockdown() then
		ns:Print("The map can't be opened by addons in combat.")
		return
	end
	if QuestMapFrame_OpenToQuestDetails then
		QuestMapFrame_OpenToQuestDetails(questID)
	end
end

-- Makes the quest your waypoint (the arrow points to its turn-in), or clears it if it was.
local function ToggleWaypoint(questID)
	local current = C_SuperTrack.GetSuperTrackedQuestID()
	C_SuperTrack.SetSuperTrackedQuestID(current == questID and 0 or questID)
	PlaySound(current == questID and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	turnIn.Refresh()
end

local function OnQuestClick(row, mouseButton)
	if mouseButton == "RightButton" then
		ToggleWaypoint(row.questID)
	elseif IsModifiedClick("CHATLINK") then
		local link = GetQuestLink(row.questID)
		if link then
			ChatFrameUtil.InsertLink(link)
		end
	else
		ShowOnMap(row.questID)
	end
end

local function OnQuestEnter(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, row.title)
	GameTooltip_AddInstructionLine(GameTooltip, "Click: show it on the map")
	GameTooltip_AddInstructionLine(GameTooltip, "Right-click or its round icon: make it your waypoint (again to clear)")
	GameTooltip_AddInstructionLine(GameTooltip, "Shift-click: link it in chat")
	GameTooltip:Show()
end

local function AcquireText(kind, font)
	return pool:Acquire(kind, function()
		local text = scroll.content:CreateFontString(nil, "OVERLAY", font)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		return text
	end)
end

local function AcquireRow()
	return pool:Acquire("quest", function()
		local row = CreateFrame("Button", nil, scroll.content)
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		-- The objective tracker's round quest icon (a turn-in "?"), lit up while it's your waypoint.
		local poi = CreateFrame("Button", nil, row)
		poi:SetSize(20, 20)
		poi:SetPoint("LEFT", 1, 0)
		poi.glow = poi:CreateTexture(nil, "BACKGROUND")
		poi.glow:SetAtlas("UI-QuestPoi-OuterGlow", true)
		poi.glow:SetPoint("CENTER")
		poi.normal = poi:CreateTexture(nil, "ARTWORK")
		poi.normal:SetPoint("CENTER")
		poi.icon = poi:CreateTexture(nil, "OVERLAY")
		poi.icon:SetAtlas("UI-QuestIcon-TurnIn-Normal", true)
		poi.icon:SetPoint("CENTER")
		local glow = poi:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAtlas("UI-QuestPoi-InnerGlow", true)
		glow:SetPoint("CENTER")
		glow:SetBlendMode("ADD")
		poi:SetScript("OnClick", function(self)
			ToggleWaypoint(self:GetParent().questID)
		end)
		poi:SetScript("OnMouseDown", function(self)
			self.normal:SetAtlas(self.selected and "UI-QuestPoi-QuestNumber-Pressed-SuperTracked" or "UI-QuestPoi-QuestNumber-Pressed", true)
		end)
		poi:SetScript("OnMouseUp", function(self)
			self:SetSelected(self.selected)
		end)
		poi:SetScript("OnEnter", function(self)
			OnQuestEnter(self:GetParent())
		end)
		poi:SetScript("OnLeave", GameTooltip_Hide)
		function poi:SetSelected(selected)
			self.selected = selected
			self.normal:SetAtlas(selected and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber", true)
			self.glow:SetShown(selected)
		end
		row.poi = poi
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", 26, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", OnQuestClick)
		row:SetScript("OnEnter", OnQuestEnter)
		row:SetScript("OnLeave", GameTooltip_Hide)
		return row
	end)
end

function turnIn.Refresh()
	refreshQueued = false
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	local zones = turnIn.Zones()
	local here = CurrentZone()
	local waypoint = C_SuperTrack.GetSuperTrackedQuestID()
	local width = WIDTH - 2 * PAD - 8
	local y, count = 0, 0
	for _, zone in ipairs(zones) do
		local header = AcquireText("zone", "GameFontNormal")
		local isHere = zone.zone == here
		header:SetText(string.format("%s  |cff999999(%d)|r%s", zone.zone, #zone.quests, isHere and "  |cff66dd66you're here|r" or ""))
		header:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y - 4)
		header:SetWidth(width)
		y = y + HEADER_HEIGHT
		for _, quest in ipairs(zone.quests) do
			local row = AcquireRow()
			row.questID, row.title = quest.id, quest.title
			-- "[32] Malin's Request", coloured by difficulty like the quest log.
			local text = quest.level and quest.level > 0 and string.format("[%d] %s", quest.level, quest.title) or quest.title
			row.text:SetText(text)
			local color = quest.level and quest.level > 0 and GetQuestDifficultyColor(quest.level)
			if color then
				row.text:SetTextColor(color.r, color.g, color.b)
			else
				row.text:SetTextColor(1, 1, 1)
			end
			row.poi:SetSelected(quest.id == waypoint)
			row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
			row:SetWidth(width)
			y = y + ROW_HEIGHT
			count = count + 1
		end
		y = y + 4
	end
	if count == 0 then
		local empty = AcquireText("empty", "GameFontDisable")
		empty:SetText("No finished quests to turn in.")
		empty:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -4)
		y = 24
	end
	frame.title:SetText(string.format("Ready to turn in (%d)", count))
	scroll.content:SetSize(width, y)
	frame:SetHeight(math.min(TITLE_HEIGHT + PAD * 2 + y, MAX_HEIGHT))
	scroll:SetScroll(scroll:GetVerticalScroll())
end

local function QueueRefresh()
	if not refreshQueued and frame and frame:IsShown() then
		refreshQueued = true
		C_Timer.After(0.2, turnIn.Refresh)
	end
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	if point then
		NraKitDB.turnInQuestsPosition = { point, relativePoint, x, y }
	end
end

local function CreateWindow()
	frame = CreateFrame("Frame", "NraKitTurnInFrame", UIParent)
	frame:SetSize(WIDTH, 120)
	frame:SetFrameStrata("DIALOG") -- above the world map, so it stays in view when a quest opens it
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	local position = NraKitDB.turnInQuestsPosition
	if position then
		frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220)
	end
	frame:Hide()
	table.insert(UISpecialFrames, "NraKitTurnInFrame")

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(frame)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", PAD, -8)
	frame.title:SetTextColor(unpack(UI.ACCENT))
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	local line = UI.AddLine(frame, "TOP")
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT)
	line:SetPoint("TOPRIGHT", 0, -TITLE_HEIGHT)

	scroll = UI.CreateScrollArea(frame)
	scroll:SetPoint("TOPLEFT", PAD, -TITLE_HEIGHT - PAD / 2)
	scroll:SetPoint("BOTTOMRIGHT", -PAD - 6, PAD)
	scroll.content:SetWidth(WIDTH - 2 * PAD - 8)

	frame:HookScript("OnShow", function(self)
		self:RegisterEvent("QUEST_LOG_UPDATE")
		self:RegisterEvent("SUPER_TRACKING_CHANGED")
		turnIn.Refresh()
	end)
	frame:HookScript("OnHide", function(self)
		self:UnregisterAllEvents()
	end)
	frame:SetScript("OnEvent", QueueRefresh)
end

-- Opens the window, or closes it (show = nil toggles).
function turnIn.Toggle(show)
	if not frame then
		CreateWindow()
	end
	if show == nil then
		show = not frame:IsShown()
	end
	frame:SetShown(show)
end

------------------------------------------------------------------------------
-- Entering a zone
------------------------------------------------------------------------------

local function OnZoneChanged()
	local here = CurrentZone()
	if here == lastZone then
		return
	end
	lastZone = here
	for _, zone in ipairs(turnIn.Zones()) do
		if zone.zone == here then
			if ns:GetOption("turnInQuestsReminder") then
				local titles = {}
				for _, quest in ipairs(zone.quests) do
					table.insert(titles, quest.title)
				end
				local count = string.format("%d %s", #zone.quests, #zone.quests == 1 and "quest" or "quests")
				if ns:GetOption("turnInQuestsToast") then
					ns.toast.Show({
						style = "small",
						heading = "QUESTS TO TURN IN",
						text = here .. "  ·  " .. count,
						atlas = "UI-QuestIcon-TurnIn-Normal",
						detail = table.concat(titles, ", "),
						duration = 6,
						onClick = function()
							turnIn.Toggle(true)
						end,
					})
				end
				if ns:GetOption("turnInQuestsChat") then
					ns:Print(string.format("%s to turn in here in %s: %s (/nra done)", count, here, table.concat(titles, ", ")))
				end
			end
			if ns:GetOption("turnInQuestsAutoOpen") then
				turnIn.Toggle(true)
			end
			return
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "ZONE_CHANGED_NEW_AREA" then
		OnZoneChanged()
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastZone = CurrentZone() -- no reminder for where you log in
	end
end)

-- Key binding (Bindings.xml).
_G["BINDING_NAME_NRAKIT_TURN_IN_QUESTS"] = "Show quests to turn in"
function NraKit_ToggleTurnInQuests()
	if ns:IsModuleEnabled(module.key) then
		turnIn.Toggle()
	end
end

function module:OnInitialize()
	local help = {
		summary = "Quests to turn in: your finished quests by the zone you turn them in",
		usage = { "/nra done - show or hide the list (also /nra turnin)" },
	}
	local function OnSlashCommand()
		if not ns:IsModuleEnabled(module.key) then
			ns:Print("Turn on Quests to turn in first (/nra).")
			return
		end
		turnIn.Toggle()
	end
	ns:RegisterSlashCommand("done", OnSlashCommand, help)
	ns:RegisterSlashCommand("turnin", OnSlashCommand, help)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	if enabled then
		eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		lastZone = CurrentZone()
	else
		eventFrame:UnregisterAllEvents()
		if frame then
			frame:Hide()
		end
	end
end

ns:RegisterModule(module)
