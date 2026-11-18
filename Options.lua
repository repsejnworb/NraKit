local addonName, ns = ...

-- NraKit's own settings window (/nra), next to Blizzard's Options > AddOns page.
--
-- Left: a search box, "All features" and one entry per section (with enabled/total
-- counts). Right: a card per feature with its on/off switch and description; a card's
-- options open inline under it. Everything is built from the module definitions and
-- changed through ns:SetSetting, so it stays in step with the Blizzard page.
--
-- The look matches the Campfire timer bar: dark flat panel, hairline borders, orange accent.

local WIDTH, HEIGHT = 780, 540
local TITLE_HEIGHT = 34
local SIDEBAR_WIDTH = 190
local PAD = 12
local CARD_GAP = 8
local INDENT = 20

local BG = { 0.04, 0.04, 0.06, 0.95 }
local EDGE = { 1, 1, 1, 0.1 }
local PANEL = { 1, 1, 1, 0.03 }
local ACCENT = { 1, 0.6, 0.2 }
local NAME_ON = { 1, 0.82, 0 }
local NAME_OFF = { 0.6, 0.6, 0.6 }
local TEXT = { 0.78, 0.78, 0.78 }
local TEXT_DIM = { 0.5, 0.5, 0.5 }

local frame, content, scrollFrame, scrollThumb, searchBox, enabledOnlyCheck
local navButtons = {}
local selectedSection -- nil = all features
local query = ""
local expanded = {} -- module key -> true
local newModules = {} -- module key -> true for features added since the window was last opened

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function AddBorder(parent)
	local edges = {}
	for i = 1, 4 do
		edges[i] = parent:CreateTexture(nil, "BORDER")
		edges[i]:SetColorTexture(unpack(EDGE))
	end
	edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
end

local function ShowTooltip(owner, title, text)
	if not title then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, title)
	if text then
		GameTooltip_AddNormalLine(GameTooltip, text, true)
	end
	GameTooltip:Show()
end

local function IsOn(key)
	return NraKitDB[key] == true
end

-- Whether an option can be changed: its module is on and every parent option is on.
local function IsOptionActive(module, option, byKey)
	if not IsOn(module.key) then
		return false
	end
	local parent = option.parent and byKey[option.parent]
	while parent do
		if not IsOn(parent.key) then
			return false
		end
		parent = parent.parent and byKey[parent.parent]
	end
	return true
end

local function OptionDepth(option, byKey)
	local depth, parent = 0, option.parent and byKey[option.parent]
	while parent do
		depth = depth + 1
		parent = parent.parent and byKey[parent.parent]
	end
	return depth
end

local function Matches(text)
	return text and text:lower():find(query, 1, true) ~= nil
end

-- "module" if the feature itself matches the search, "options" if only an option does.
local function MatchModule(module, section)
	if query == "" then
		return "module"
	end
	if Matches(module.name) or Matches(module.description) or Matches(section) then
		return "module"
	end
	for _, option in ipairs(module.options or {}) do
		if Matches(option.name) or Matches(option.description) or Matches(option.header) then
			return "options"
		end
	end
end

------------------------------------------------------------------------------
-- Widget pools: everything in the scroll area is rebuilt on each Render()
------------------------------------------------------------------------------

local pools = {}

local function Acquire(kind, create)
	local pool = pools[kind]
	if not pool then
		pool = { free = {}, used = {} }
		pools[kind] = pool
	end
	local widget = table.remove(pool.free) or create()
	table.insert(pool.used, widget)
	widget:ClearAllPoints()
	widget:Show()
	return widget
end

local function ReleaseAll()
	for _, pool in pairs(pools) do
		for _, widget in ipairs(pool.used) do
			widget:Hide()
			table.insert(pool.free, widget)
		end
		wipe(pool.used)
	end
end

local Render

local function AcquireText(font)
	local text = Acquire("text:" .. font, function()
		local fs = content:CreateFontString(nil, "OVERLAY", font)
		fs:SetJustifyH("LEFT")
		fs:SetJustifyV("TOP")
		return fs
	end)
	text:SetWidth(0)
	text:SetWordWrap(true)
	text:SetTextColor(1, 1, 1)
	return text
end

local function AcquireTexture()
	local texture = Acquire("texture", function()
		return content:CreateTexture(nil, "BACKGROUND")
	end)
	return texture
end

local function AcquireCheck()
	return Acquire("check", function()
		local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		check:SetFrameLevel(content:GetFrameLevel() + 3)
		check:SetScript("OnClick", function(self)
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			ns:SetSetting(self.settingKey, self:GetChecked() and true or false)
			Render()
		end)
		check:SetScript("OnEnter", function(self)
			ShowTooltip(self, self.tooltipTitle, self.tooltipText)
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		return check
	end)
end

local function AcquireSlider()
	return Acquire("slider", function()
		local slider = CreateFrame("Frame", nil, content, "MinimalSliderWithSteppersTemplate")
		slider:SetFrameLevel(content:GetFrameLevel() + 3)
		slider:SetSize(250, 30)
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			local option = slider.option
			if not option then
				return
			end
			value = option.min + math.floor((value - option.min) / option.step + 0.5) * option.step
			if NraKitDB[option.key] ~= value then
				ns:SetSetting(option.key, value)
			end
		end, slider)
		slider:SetScript("OnEnter", function(self)
			ShowTooltip(self, self.option and self.option.name, self.option and self.option.description)
		end)
		slider:SetScript("OnLeave", GameTooltip_Hide)
		return slider
	end)
end

local function AcquireButton()
	return Acquire("button", function()
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetFrameLevel(content:GetFrameLevel() + 3)
		button:SetHeight(22)
		button:SetScript("OnEnter", function(self)
			ShowTooltip(self, self:GetText(), self.tooltipText)
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		return button
	end)
end

-- Invisible button over a card's top row: click to open or close its options.
local function AcquireCardHeader()
	return Acquire("cardHeader", function()
		local header = CreateFrame("Button", nil, content)
		header:SetFrameLevel(content:GetFrameLevel() + 1)
		header.highlight = header:CreateTexture(nil, "HIGHLIGHT")
		header.highlight:SetAllPoints()
		header.highlight:SetColorTexture(1, 1, 1, 0.03)
		header.toggle = header:CreateTexture(nil, "ARTWORK")
		header.toggle:SetSize(14, 14)
		header.toggle:SetPoint("TOPRIGHT", -10, -12)
		header.label = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		header.label:SetPoint("RIGHT", header.toggle, "LEFT", -4, 0)
		header:SetScript("OnClick", function(self)
			if self.moduleKey then
				expanded[self.moduleKey] = not expanded[self.moduleKey] or nil
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Render()
			end
		end)
		return header
	end)
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

-- Lays out one option row at (x, y); returns the new y.
local function AddOption(module, option, byKey, x, y, width)
	local active = IsOptionActive(module, option, byKey)
	x = x + OptionDepth(option, byKey) * INDENT

	if option.header then
		local header = AcquireText("GameFontNormalSmall")
		header:SetText(option.header:upper())
		header:SetTextColor(unpack(ACCENT))
		header:SetPoint("TOPLEFT", content, "TOPLEFT", x - OptionDepth(option, byKey) * INDENT, y - 6)
		y = y - 22
	end

	if option.type == "number" then
		local label = AcquireText("GameFontHighlight")
		label:SetText(option.name)
		label:SetWidth(200)
		label:SetWordWrap(false)
		label:SetTextColor(unpack(active and TEXT or TEXT_DIM))
		label:SetPoint("TOPLEFT", content, "TOPLEFT", x + 4, y - 9)

		local slider = AcquireSlider()
		slider.option = nil -- no saving while Init sets the value
		local steps = math.max(1, math.floor((option.max - option.min) / option.step + 0.5))
		slider:Init(NraKitDB[option.key] or option.default, option.min, option.max, steps, {
			[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
				return ns:FormatOptionValue(option, value)
			end,
		})
		slider:SetEnabled(active)
		slider.option = option
		slider:SetPoint("TOPLEFT", content, "TOPLEFT", math.min(x + 210, x + width - 300), y)
		return y - 32
	end

	local check = AcquireCheck()
	check:SetSize(22, 22)
	check:SetPoint("TOPLEFT", content, "TOPLEFT", x, y - 1)
	check:SetChecked(IsOn(option.key))
	check:SetEnabled(active)
	check.settingKey = option.key
	check.tooltipTitle, check.tooltipText = option.name, option.description

	local label = AcquireText("GameFontHighlight")
	label:SetText(option.name)
	label:SetWordWrap(false)
	label:SetTextColor(unpack(active and TEXT or TEXT_DIM))
	label:SetPoint("LEFT", check, "RIGHT", 4, 1)
	check:SetHitRectInsets(0, -(label:GetStringWidth() + 8), 0, 0)
	return y - 26
end

-- Lays out one feature card at y; returns the new y.
local function AddCard(module, x, y, width, forceOpen)
	local top = y
	local enabled = IsOn(module.key)
	local hasOptions = (module.options and #module.options > 0) or ns.optionsButtons[module.key]
	local open = hasOptions and (expanded[module.key] or forceOpen)

	local check = AcquireCheck()
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", content, "TOPLEFT", x + 8, y - 8)
	check:SetChecked(enabled)
	check:SetEnabled(true)
	check.settingKey = module.key
	check.tooltipTitle, check.tooltipText = nil, nil

	local name = AcquireText("GameFontNormal")
	name:SetText(module.name)
	name:SetWordWrap(false)
	name:SetTextColor(unpack(enabled and NAME_ON or NAME_OFF))
	name:SetPoint("TOPLEFT", content, "TOPLEFT", x + 40, y - 14)
	check:SetHitRectInsets(0, -(name:GetStringWidth() + 10), 0, 0)

	if newModules[module.key] then
		local badge = AcquireText("GameFontNormalSmall")
		badge:SetText("NEW")
		badge:SetTextColor(unpack(ACCENT))
		badge:SetPoint("LEFT", name, "RIGHT", 6, 0)
	end

	local description = AcquireText("GameFontHighlightSmall")
	description:SetWidth(width - 40 - 16)
	description:SetText(module.description or "")
	description:SetTextColor(unpack(enabled and TEXT or TEXT_DIM))
	description:SetPoint("TOPLEFT", content, "TOPLEFT", x + 40, y - 32)
	y = y - 32 - description:GetStringHeight() - 10

	if hasOptions then
		local header = AcquireCardHeader()
		header.moduleKey = module.key
		header:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
		header:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", x + width, y)
		header.toggle:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
		header.label:SetText("Options")
	end

	if open then
		local divider = AcquireTexture()
		divider:SetDrawLayer("BORDER")
		divider:SetColorTexture(unpack(EDGE))
		divider:SetHeight(1)
		divider:SetPoint("TOPLEFT", content, "TOPLEFT", x + 40, y + 2)
		divider:SetPoint("TOPRIGHT", content, "TOPLEFT", x + width - 12, y + 2)
		y = y - 6

		local byKey = {}
		for _, option in ipairs(module.options or {}) do
			byKey[option.key] = option
		end
		for _, option in ipairs(module.options or {}) do
			y = AddOption(module, option, byKey, x + 40, y, width - 52)
		end
		for _, info in ipairs(ns.optionsButtons[module.key] or {}) do
			local button = AcquireButton()
			button:SetText(info.label)
			button:SetWidth(button:GetTextWidth() + 30)
			button.tooltipText = info.description
			button:SetPoint("TOPLEFT", content, "TOPLEFT", x + 40, y - 6)
			button:SetScript("OnClick", function()
				frame:Hide()
				info.onClick()
			end)
			y = y - 34
		end
		y = y - 6
	end

	local background = AcquireTexture()
	background:SetDrawLayer("BACKGROUND")
	background:SetColorTexture(unpack(PANEL))
	background:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
	background:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", x + width, y)
	return y - CARD_GAP
end

local function UpdateScrollThumb()
	local range = scrollFrame:GetVerticalScrollRange()
	local visible = scrollFrame:GetHeight()
	if range <= 0 then
		scrollThumb:Hide()
		return
	end
	local trackHeight = visible - 8
	local thumbHeight = math.max(24, trackHeight * visible / (visible + range))
	local offset = (trackHeight - thumbHeight) * scrollFrame:GetVerticalScroll() / range
	scrollThumb:SetHeight(thumbHeight)
	scrollThumb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 10, -4 - offset)
	scrollThumb:Show()
end

local function SetScroll(value)
	local range = scrollFrame:GetVerticalScrollRange()
	scrollFrame:SetVerticalScroll(math.min(math.max(value, 0), range))
	UpdateScrollThumb()
end

local function UpdateNav()
	local searching = query ~= ""
	for _, button in ipairs(navButtons) do
		local on, total = 0, 0
		for _, module in ipairs(button.modules) do
			total = total + 1
			if IsOn(module.key) then
				on = on + 1
			end
		end
		button.count:SetText(on .. "/" .. total)
		local selected = not searching and button.section == selectedSection
		button.selected:SetShown(selected)
		button.bar:SetShown(selected)
		button.text:SetTextColor(unpack(selected and NAME_ON or TEXT))
	end
end

function Render()
	if not frame then
		return
	end
	local scroll = scrollFrame:GetVerticalScroll()
	ReleaseAll()

	local width = content:GetWidth() - 2 * PAD
	local x, y = PAD, -PAD
	local shown = 0
	local enabledOnly = enabledOnlyCheck:GetChecked()

	for _, section in ipairs(ns:GetSections()) do
		if query ~= "" or not selectedSection or selectedSection == section.name then
			local cards = {}
			for _, module in ipairs(section.modules) do
				local match = MatchModule(module, section.name)
				if match and (not enabledOnly or IsOn(module.key)) then
					table.insert(cards, { module = module, forceOpen = match == "options" })
				end
			end
			if #cards > 0 then
				if shown > 0 then
					y = y - 10
				end
				local heading = AcquireText("GameFontNormalLarge")
				heading:SetText(section.name)
				heading:SetTextColor(1, 1, 1)
				heading:SetPoint("TOPLEFT", content, "TOPLEFT", x + 2, y)
				y = y - 28
				for _, card in ipairs(cards) do
					y = AddCard(card.module, x, y, width, card.forceOpen)
					shown = shown + 1
				end
			end
		end
	end

	if shown == 0 then
		local empty = AcquireText("GameFontDisable")
		empty:SetText(query ~= "" and string.format("No features match \"%s\".", query) or "No features to show.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", x + 2, y - 4)
		y = y - 30
	end

	content:SetHeight(-y + PAD)
	UpdateNav()
	SetScroll(scroll)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateNavButton(parent, label, section, modules)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(SIDEBAR_WIDTH - 2 * PAD, 26)
	button.section, button.modules = section, modules

	button.selected = button:CreateTexture(nil, "BACKGROUND")
	button.selected:SetAllPoints()
	button.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
	button.bar = button:CreateTexture(nil, "ARTWORK")
	button.bar:SetColorTexture(unpack(ACCENT))
	button.bar:SetPoint("TOPLEFT"); button.bar:SetPoint("BOTTOMLEFT"); button.bar:SetWidth(2)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.05)

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.text:SetPoint("LEFT", 10, 0)
	button.text:SetText(label)
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	button.count:SetPoint("RIGHT", -8, 0)

	button:SetScript("OnClick", function(self)
		selectedSection = self.section
		if query ~= "" then
			searchBox:SetText("") -- also re-renders
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetScroll(0)
		Render()
	end)
	table.insert(navButtons, button)
	return button
end

local function MarkNewModules()
	wipe(newModules)
	local firstOpen = NraKitDB.seenModules == nil
	NraKitDB.seenModules = NraKitDB.seenModules or {}
	for _, module in ipairs(ns.moduleOrder) do
		if not firstOpen and not NraKitDB.seenModules[module.key] then
			newModules[module.key] = true
		end
		NraKitDB.seenModules[module.key] = true
	end
end

local function CreateWindow()
	frame = CreateFrame("Frame", "NraKitOptionsFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, "NraKitOptionsFrame") -- Esc closes it

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BG))
	AddBorder(frame)

	-- Title bar (drag to move)
	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_HEIGHT)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
	end)
	local titleLine = titleBar:CreateTexture(nil, "BORDER")
	titleLine:SetColorTexture(unpack(EDGE))
	titleLine:SetPoint("BOTTOMLEFT"); titleLine:SetPoint("BOTTOMRIGHT"); titleLine:SetHeight(1)

	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", PAD + 2, 0)
	title:SetText("NraKit")
	title:SetTextColor(unpack(ACCENT))
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if version and not version:find("@", 1, true) then
		local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		versionText:SetPoint("LEFT", title, "RIGHT", 8, -1)
		versionText:SetText(version)
	end

	local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
	close:SetPoint("RIGHT", -4, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- Sidebar
	local sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT)
	sidebar:SetPoint("BOTTOMLEFT")
	sidebar:SetWidth(SIDEBAR_WIDTH)
	local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
	sidebarBg:SetAllPoints()
	sidebarBg:SetColorTexture(unpack(PANEL))
	local sidebarLine = sidebar:CreateTexture(nil, "BORDER")
	sidebarLine:SetColorTexture(unpack(EDGE))
	sidebarLine:SetPoint("TOPRIGHT"); sidebarLine:SetPoint("BOTTOMRIGHT"); sidebarLine:SetWidth(1)

	searchBox = CreateFrame("EditBox", nil, sidebar, "SearchBoxTemplate")
	searchBox:SetSize(SIDEBAR_WIDTH - 2 * PAD - 6, 22)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD)
	searchBox:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or ""):lower()
		if text ~= query then
			query = text
			SetScroll(0)
			Render()
		end
	end)

	local anchor = CreateNavButton(sidebar, "All features", nil, ns.moduleOrder)
	anchor:SetPoint("TOPLEFT", PAD, -PAD - 34)
	for _, section in ipairs(ns:GetSections()) do
		local button = CreateNavButton(sidebar, section.name, section.name, section.modules)
		button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		anchor = button
	end

	enabledOnlyCheck = CreateFrame("CheckButton", nil, sidebar, "UICheckButtonTemplate")
	enabledOnlyCheck:SetSize(22, 22)
	enabledOnlyCheck:SetPoint("BOTTOMLEFT", PAD, 44)
	enabledOnlyCheck.Text:SetFontObject("GameFontHighlightSmall")
	enabledOnlyCheck.Text:SetText("Enabled only")
	enabledOnlyCheck:SetHitRectInsets(0, -80, 0, 0)
	enabledOnlyCheck:SetScript("OnClick", function()
		SetScroll(0)
		Render()
	end)

	local blizzard = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
	blizzard:SetSize(SIDEBAR_WIDTH - 2 * PAD, 22)
	blizzard:SetPoint("BOTTOMLEFT", PAD, PAD)
	blizzard:SetText("Blizzard settings")
	blizzard:SetScript("OnClick", function()
		frame:Hide()
		ns:OpenBlizzardSettings()
	end)

	-- Feature list
	scrollFrame = CreateFrame("ScrollFrame", nil, frame)
	scrollFrame:SetPoint("TOPLEFT", SIDEBAR_WIDTH, -TITLE_HEIGHT - 1)
	scrollFrame:SetPoint("BOTTOMRIGHT", -14, 1)
	content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(WIDTH - SIDEBAR_WIDTH - 14, 1)
	scrollFrame:SetScrollChild(content)
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function(self, delta)
		SetScroll(self:GetVerticalScroll() - delta * 60)
	end)
	scrollFrame:SetScript("OnScrollRangeChanged", UpdateScrollThumb)

	scrollThumb = frame:CreateTexture(nil, "OVERLAY")
	scrollThumb:SetColorTexture(1, 1, 1, 0.2)
	scrollThumb:SetWidth(3)

	frame:SetScript("OnShow", function()
		MarkNewModules()
		Render()
	end)
	frame:SetScript("OnHide", function()
		wipe(newModules)
	end)
end

-- /nra (and the button on the Blizzard page) toggles the window.
function ns:OpenSettings()
	if not frame then
		CreateWindow()
	end
	frame:SetShown(not frame:IsShown())
end
