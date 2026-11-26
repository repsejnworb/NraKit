local _, ns = ...

-- NraKit Button: NraKit's icon, on screen wherever you drag it. A badge counts what's waiting
-- for you (due reminders, and what's new if you want); the tooltip says what. Left-click and
-- shift-click do what you pick in the settings (by default: what's waiting, else the NraKit
-- window; and your reminders). Right-click is NraKit's menu, the same as the addon button's.
--
-- What counts on the badge comes from features (ns:RegisterBadge in Core.lua); each has an
-- option here. Saved: NraKitDB.nraButtonPosition, its centre in screen units (so a new size
-- keeps it in place).

local UI = ns.UI
local button

-- What a click can do: { key, label, run }. The windows come from the tabs.
local function Actions()
	local actions = {
		{ key = "waiting", label = "What's waiting, else the NraKit window" },
		{ key = "settings", label = "NraKit window", run = function()
			ns:OpenSettings()
		end },
		{ key = "menu", label = "NraKit's menu" },
		{ key = "reminders", label = "To-do list (else the Reminders & To-Do tab)", run = function()
			if ns:IsModuleEnabled("reminders") and #ns.reminders.Due() > 0 then
				ns.reminders.ShowTracker()
			else
				UI.ShowTab("reminders")
			end
		end },
	}
	for _, tab in ipairs(UI.GetTabs()) do
		if tab.key ~= "settings" and tab.key ~= "reminders" then
			table.insert(actions, { key = tab.key, label = (tab.menuLabel or tab.label) .. " window", run = function()
				UI.ShowTab(tab.key)
			end })
		end
	end
	table.insert(actions, { key = "turnin", label = "Quests to Turn In", run = function()
		if ns:IsModuleEnabled("turnInQuests") then
			ns.turnInQuests.Toggle()
		else
			ns:Print("Turn on Quests to Turn In first (/nra).")
		end
	end })
	table.insert(actions, { key = "whatsnew", label = "What's New", run = function()
		ns:OpenWhatsNew()
	end })
	table.insert(actions, { key = "none", label = "Nothing" })
	return actions
end

local function ActionChoices()
	local choices = {}
	for _, action in ipairs(Actions()) do
		table.insert(choices, { action.key, action.label })
	end
	return choices
end

local module = {
	key = "nraButton",
	section = "Tools",
	name = "NraKit Button",
	description = "NraKit's icon on screen, wherever you drag it. A badge counts what's waiting for you, like due reminders. Pick what left-click and shift-click do; right-click is NraKit's menu.",
	default = false,
	options = {
		{
			key = "nraButtonLock",
			header = "Button",
			name = "Lock in place",
			description = "Stop it being dragged by accident.",
			default = false,
		},
		{
			key = "nraButtonScale",
			type = "number",
			name = "Size",
			description = "How big the button is.",
			default = 1,
			min = 0.6,
			max = 2,
			step = 0.1,
			format = function(value)
				return math.floor(value * 100 + 0.5) .. "%"
			end,
		},
		{
			key = "nraButtonHideInCombat",
			name = "Hide in combat",
			description = "Hide the button while you're fighting.",
			default = false,
		},
		{
			key = "nraButtonLeftClick",
			header = "Clicks",
			type = "choice",
			name = "Left-click",
			description = "What a click on the button does.",
			default = "waiting",
			choices = ActionChoices,
		},
		{
			key = "nraButtonShiftClick",
			type = "choice",
			name = "Shift-click",
			description = "What a shift-click on the button does.",
			default = "reminders",
			choices = ActionChoices,
		},
		{
			key = "nraButtonBadge",
			header = "Badge",
			name = "Count what's waiting",
			description = "A small number on the button for what's waiting for you. The tooltip says what.",
			default = true,
		},
		{
			key = "nraButtonBadgeReminders",
			parent = "nraButtonBadge",
			requires = "reminders",
			name = "Reminders",
			description = "Reminders that came due and aren't ticked off. (Not to-dos: they're meant to stay on the list.)",
			default = true,
		},
		{
			key = "nraButtonBadgeWhatsNew",
			parent = "nraButtonBadge",
			name = "What's New",
			description = "Changes in NraKit you haven't looked at yet (/nra new).",
			default = false,
		},
	},
}

------------------------------------------------------------------------------
-- What's waiting
------------------------------------------------------------------------------

-- The badge sources that are on and have something: { { badge, count } }.
local function Waiting()
	local waiting = {}
	for _, badge in ipairs(ns.badges) do
		if ns:GetOption(badge.option) and (not badge.module or ns:IsModuleEnabled(badge.module)) then
			local count = badge.count() or 0
			if count > 0 then
				table.insert(waiting, { badge = badge, count = count })
			end
		end
	end
	return waiting
end

local function UpdateBadge()
	if not button then
		return
	end
	local total = 0
	if ns:GetOption("nraButtonBadge") then
		for _, entry in ipairs(Waiting()) do
			total = total + entry.count
		end
	end
	button.badge:SetShown(total > 0)
	button.badge.text:SetText(total > 9 and "9+" or total)
end

------------------------------------------------------------------------------
-- Clicks
------------------------------------------------------------------------------

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		ns:FillMenu(root)
		root:CreateDivider()
		root:CreateCheckbox("Lock the button", function()
			return ns:GetOption("nraButtonLock")
		end, function()
			ns:SetSetting("nraButtonLock", not ns:GetOption("nraButtonLock"))
		end)
	end)
end

local function FindAction(key)
	for _, action in ipairs(Actions()) do
		if action.key == key then
			return action
		end
	end
end

local function Run(key)
	if key == "waiting" then
		local first = Waiting()[1]
		if first then
			first.badge.open()
		else
			ns:OpenSettings()
		end
	elseif key == "menu" then
		OpenMenu(button)
	else
		local action = FindAction(key) or FindAction("settings")
		if action.run then
			action.run()
		end
	end
end

local function ActionLabel(key)
	local action = FindAction(key)
	return action and action.label or "?"
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, "NraKit")
	for _, entry in ipairs(Waiting()) do
		GameTooltip:AddLine(entry.badge.text(entry.count), 1, 0.6, 0.2)
	end
	local left, shift = ns:GetValue("nraButtonLeftClick"), ns:GetValue("nraButtonShiftClick")
	if left ~= "none" then
		GameTooltip_AddInstructionLine(GameTooltip, "Click: " .. ActionLabel(left))
	end
	if shift ~= "none" then
		GameTooltip_AddInstructionLine(GameTooltip, "Shift-click: " .. ActionLabel(shift))
	end
	GameTooltip_AddInstructionLine(GameTooltip, "Right-click: NraKit's menu")
	if not ns:GetOption("nraButtonLock") then
		GameTooltip_AddInstructionLine(GameTooltip, "Drag to move")
	end
	GameTooltip:Show()
end

------------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------------

local function CreateButton()
	-- Looks like a minimap button: a round icon in the tracking border.
	button = CreateFrame("Button", "NraKitButton", UIParent)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:SetMovable(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	function button:Place()
		local position = NraKitDB.nraButtonPosition
		self:ClearAllPoints()
		if position and position.screen then
			local scale = self:GetScale()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position[3] / scale, position[4] / scale)
		elseif position then
			self:SetPoint(position[1], UIParent, position[2], position[3], position[4])
		else
			self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -40)
		end
	end
	button:Place()

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\AddOns\\NraKit\\Media\\Icon.png")
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 7, -6)
	local mask = button:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	-- The badge: an orange dot with the count.
	local badge = CreateFrame("Frame", nil, button)
	badge:SetSize(16, 16)
	badge:SetPoint("CENTER", button, "TOPRIGHT", -5, -5)
	badge:SetFrameLevel(button:GetFrameLevel() + 2)
	local dot = badge:CreateTexture(nil, "ARTWORK")
	dot:SetAllPoints()
	dot:SetColorTexture(0.9, 0.4, 0.05)
	local dotMask = badge:CreateMaskTexture()
	dotMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	dotMask:SetAllPoints(dot)
	dot:AddMaskTexture(dotMask)
	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.text:SetPoint("CENTER", 0, 0)
	badge:Hide()
	button.badge = badge

	button:SetScript("OnClick", function(self, mouseButton)
		GameTooltip:Hide()
		if mouseButton == "RightButton" then
			OpenMenu(self)
		elseif IsShiftKeyDown() then
			Run(ns:GetValue("nraButtonShiftClick"))
		else
			Run(ns:GetValue("nraButtonLeftClick"))
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if not ns:GetOption("nraButtonLock") then
			GameTooltip:Hide()
			self:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		if x and y then
			local scale = self:GetScale()
			NraKitDB.nraButtonPosition = { "CENTER", "BOTTOMLEFT", x * scale, y * scale, screen = true }
			self:Place()
		end
	end)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			UI.FadeOut(self)
		else
			UI.FadeIn(self, 1)
		end
	end)
end

local function Apply()
	local enabled = ns:IsModuleEnabled(module.key)
	if not enabled then
		if button then
			button:Hide()
			button:UnregisterAllEvents()
		end
		return
	end
	if not button then
		CreateButton()
	end
	local scale = ns:GetValue("nraButtonScale") or 1
	if scale ~= button:GetScale() then
		if not (NraKitDB.nraButtonPosition and NraKitDB.nraButtonPosition.screen) then
			local x, y = button:GetCenter() -- an older saved place, or the first one: keep it
			if x and y then
				local old = button:GetScale()
				NraKitDB.nraButtonPosition = { "CENTER", "BOTTOMLEFT", x * old, y * old, screen = true }
			end
		end
		button:SetScale(scale)
		button:Place() -- the same centre, at the new size
	end
	if ns:GetOption("nraButtonHideInCombat") then
		button:RegisterEvent("PLAYER_REGEN_DISABLED")
		button:RegisterEvent("PLAYER_REGEN_ENABLED")
		button:SetShown(not InCombatLockdown())
	else
		button:UnregisterAllEvents()
		button:Show()
	end
	UpdateBadge()
end

ns.onBadgeChanged = UpdateBadge

function module:OnInitialize()
	Apply()
end

function module:OnEnabledChanged()
	Apply()
end

function module:OnOptionChanged()
	Apply()
end

ns:RegisterModule(module)
