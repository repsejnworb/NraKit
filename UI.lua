local _, ns = ...

-- Shared look for NraKit's windows (settings, inventory browser): a dark flat panel
-- with hairline borders and an orange accent, like the Campfire Timer bar.

local UI = {}
ns.UI = UI

UI.TITLE_HEIGHT = 34
UI.PAD = 12
-- NraKit's main windows (settings, inventory, goals, notes) share one size, so switching
-- tabs looks like one window changing pages.
UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT = 800, 560

UI.BG = { 0.04, 0.04, 0.06, 0.95 }
UI.EDGE = { 1, 1, 1, 0.1 }
UI.PANEL = { 1, 1, 1, 0.03 }
UI.ACCENT = { 1, 0.6, 0.2 }
UI.GOLD = { 1, 0.82, 0 }
UI.GREY = { 0.6, 0.6, 0.6 }
UI.TEXT = { 0.78, 0.78, 0.78 }
UI.TEXT_DIM = { 0.5, 0.5, 0.5 }

local function Edge(parent, layer)
	local texture = parent:CreateTexture(nil, layer or "BORDER")
	texture:SetColorTexture(unpack(UI.EDGE))
	return texture
end

function UI.AddBorder(parent)
	local top, bottom, left, right = Edge(parent), Edge(parent), Edge(parent), Edge(parent)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
	left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
	right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
end

-- A one-pixel line along one side of a frame ("TOP", "BOTTOM", "LEFT" or "RIGHT").
function UI.AddLine(parent, side)
	local line = Edge(parent)
	if side == "TOP" or side == "BOTTOM" then
		line:SetPoint(side .. "LEFT"); line:SetPoint(side .. "RIGHT"); line:SetHeight(1)
	else
		line:SetPoint("TOP" .. side); line:SetPoint("BOTTOM" .. side); line:SetWidth(1)
	end
	return line
end

function UI.ShowTooltip(owner, title, text)
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

-- Widget pools for content that is rebuilt on every render.
-- pool:Acquire(kind, create) reuses a released widget of that kind or calls create().
function UI.CreatePool()
	local kinds = {}
	local pool = {}
	function pool:Acquire(kind, create)
		local entry = kinds[kind]
		if not entry then
			entry = { free = {}, used = {} }
			kinds[kind] = entry
		end
		local widget = table.remove(entry.free) or create()
		table.insert(entry.used, widget)
		widget:ClearAllPoints()
		widget:Show()
		return widget
	end
	function pool:ReleaseAll()
		for _, entry in pairs(kinds) do
			for _, widget in ipairs(entry.used) do
				widget:Hide()
				table.insert(entry.free, widget)
			end
			wipe(entry.used)
		end
	end
	return pool
end

------------------------------------------------------------------------------
-- Tabs: NraKit's main windows act as one app. Each registers a tab (UI.RegisterTab);
-- a window made with a tab key gets "NraKit" and the tab strip in its title bar. Only
-- one is open at a time, always at the same place (NraKitDB.windowPosition, saved when
-- one is dragged), so switching tabs looks like one window changing pages.
--
-- Every tab is always there, so they keep their places and players find what they haven't
-- turned on. A tab whose feature is off is dimmed and opens a page saying what the feature
-- does, with a button to turn it on (which then opens the real window). The strips follow
-- features being switched on and off (UI.RefreshTabs, called by Settings.lua).
------------------------------------------------------------------------------

local tabs = {} -- { key, label, menuLabel, order, frameName, open, module }
local tabWindows = {} -- tab key -> frame
local RefreshTabStrip, ShowOffPage

-- tab = { key, label, richLabel? (with colour codes, shown while its feature is on), menuLabel?
--         (addon button menu), order, frameName,
--         open = function() shows the window end, module = key of the feature it belongs to (optional) }
function UI.RegisterTab(tab)
	table.insert(tabs, tab)
	table.sort(tabs, function(a, b)
		return a.order < b.order
	end)
end

function UI.IsTabOn(tab)
	return not tab.module or ns:IsModuleEnabled(tab.module)
end

-- Every tab, in order; with onlyOn, just those whose feature is on (the addon button's menu).
function UI.GetTabs(onlyOn)
	local list = {}
	for _, tab in ipairs(tabs) do
		if not onlyOn or UI.IsTabOn(tab) then
			table.insert(list, tab)
		end
	end
	return list
end

function UI.ShowTab(key)
	for _, tab in ipairs(tabs) do
		if tab.key == key then
			if not UI.IsTabOn(tab) then
				ShowOffPage(tab)
				return true
			end
			local frame = _G[tab.frameName]
			if not (frame and frame:IsShown()) then
				tab.open()
			end
			return true
		end
	end
	return false
end

-- A feature was switched on or off: redraw the open window's tabs. The "feature is off" page
-- turns into the real window when its feature comes on, and a window whose feature goes off
-- turns into that page.
function UI.RefreshTabs()
	for key, frame in pairs(tabWindows) do
		if frame:IsShown() then
			local tab
			for _, each in ipairs(tabs) do
				if each.key == frame.tabKey then
					tab = each
				end
			end
			if tab and key == "_off" and UI.IsTabOn(tab) then
				tab.open()
			elseif tab and key ~= "_off" and not UI.IsTabOn(tab) then
				ShowOffPage(tab)
			else
				RefreshTabStrip(frame)
			end
		end
	end
end

-- Docked: NraKit's windows open beside another frame (the auction house) instead of where
-- they usually are, whichever tab; dragging one while docked moves them for that visit only.
local dock -- { anchor, x (gap right of it), position = { point, relativePoint, x, y } after a drag }

local function SavePosition(frame)
	local point, _, relativePoint, x, y = frame:GetPoint()
	if dock then
		dock.position = point and { point, relativePoint, x, y }
		return
	end
	if point then
		NraKitDB.windowPosition = { point, relativePoint, x, y }
	end
end

local function ApplyPosition(frame)
	if dock then
		frame:ClearAllPoints()
		if dock.position then
			frame:SetPoint(dock.position[1], UIParent, dock.position[2], dock.position[3], dock.position[4])
		else
			frame:SetPoint("TOPLEFT", dock.anchor, "TOPRIGHT", dock.x or 4, 0)
		end
		return
	end
	local position = NraKitDB.windowPosition
	if position then
		frame:ClearAllPoints()
		frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	end
end

-- Docks NraKit's windows beside `anchor`, `x` right of it (default 4; e.g. past a window's
-- side tabs). See dock above.
function UI.Dock(anchor, x)
	dock = { anchor = anchor, x = x }
end

function UI.IsDocked()
	return dock ~= nil
end

-- What it's docked to, and how far right of it (nil when not docked).
function UI.DockAnchor()
	if dock then
		return dock.anchor, dock.x or 4
	end
end

-- Moves the dock to another frame (e.g. beside an open mail instead of the mailbox); the open
-- window follows, unless you've dragged it.
function UI.MoveDock(anchor, x)
	if not dock then
		return
	end
	dock.anchor, dock.x = anchor, x
	if not dock.position then
		for _, frame in pairs(tabWindows) do
			if frame:IsShown() then
				ApplyPosition(frame)
			end
		end
	end
end

-- Undocks: the open window closes (it went with what it was docked to), and the next one
-- opens where NraKit's windows usually are.
function UI.Undock()
	if not dock then
		return
	end
	dock = nil
	for _, frame in pairs(tabWindows) do
		if frame:IsShown() then
			frame:Hide()
		end
		if NraKitDB.windowPosition then
			ApplyPosition(frame)
		else
			frame:ClearAllPoints()
			frame:SetPoint("CENTER")
		end
	end
end

function RefreshTabStrip(frame)
	local strip = frame.tabStrip
	for _, button in ipairs(strip.buttons) do
		button:Hide()
	end
	local anchor
	for index, tab in ipairs(UI.GetTabs()) do
		local button = strip.buttons[index]
		if not button then
			button = UI.CreateFlatButton(frame.titleBar, "", 22)
			button:SetScript("OnClick", function(self)
				if UI.ShowTab(self.tabKey) then
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				end
			end)
			strip.buttons[index] = button
		end
		button.tabKey = tab.key
		-- richLabel: the label with colours, while its feature is on.
		button.text:SetText(tab.richLabel and UI.IsTabOn(tab) and tab.richLabel or tab.label)
		button:SetWidth(button.text:GetStringWidth() + 22)
		button:SetSelected(tab.key == frame.tabKey)
		if not UI.IsTabOn(tab) and tab.key ~= frame.tabKey then
			button.text:SetTextColor(unpack(UI.TEXT_DIM)) -- its feature is off
		end
		button:ClearAllPoints()
		if anchor then
			button:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
		else
			button:SetPoint("LEFT", frame.title, "RIGHT", 18, -1)
		end
		button:Show()
		anchor = button
	end
end

-- Showing one tab window closes the others and puts it where they were.
local function OnTabWindowShow(frame)
	for _, other in pairs(tabWindows) do
		if other ~= frame and other:IsShown() then
			other:Hide()
		end
	end
	ApplyPosition(frame)
	RefreshTabStrip(frame)
end

-- A movable window with a title bar and a left sidebar (none if sidebarWidth is 0). Esc closes it.
-- Returns the frame; frame.titleBar, frame.title, frame.sidebar and frame.body
-- (the area right of the sidebar) are for the caller to fill. With tabKey it's one of
-- NraKit's main windows: titled "NraKit" with the tab strip (see UI.RegisterTab).
-- Callers add OnShow/OnHide handlers with HookScript, not SetScript.
function UI.CreateWindow(globalName, titleText, width, height, sidebarWidth, tabKey)
	local frame = CreateFrame("Frame", globalName, UIParent)
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	-- HIGH: above the game's windows (bank, auction house...), below its pop-ups (DIALOG:
	-- "Clean up your bank?", delete confirmations), which must show in front.
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, globalName)

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(frame)

	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(UI.TITLE_HEIGHT)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		if tabKey then
			SavePosition(frame)
		end
	end)
	UI.AddLine(titleBar, "BOTTOM")
	frame.titleBar = titleBar

	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", UI.PAD + 2, 0)
	title:SetText(titleText)
	title:SetTextColor(unpack(UI.ACCENT))
	frame.title = title

	local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
	close:SetPoint("RIGHT", -4, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	if sidebarWidth > 0 then
		local sidebar = CreateFrame("Frame", nil, frame)
		sidebar:SetPoint("TOPLEFT", 0, -UI.TITLE_HEIGHT)
		sidebar:SetPoint("BOTTOMLEFT")
		sidebar:SetWidth(sidebarWidth)
		local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
		sidebarBg:SetAllPoints()
		sidebarBg:SetColorTexture(unpack(UI.PANEL))
		UI.AddLine(sidebar, "RIGHT")
		frame.sidebar = sidebar
	end

	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", sidebarWidth, -UI.TITLE_HEIGHT - 1)
	body:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.body = body

	if tabKey then
		title:SetText("NraKit")
		frame.tabKey = tabKey
		frame.tabStrip = { buttons = {} }
		tabWindows[tabKey] = frame
		frame:HookScript("OnShow", OnTabWindowShow)
	end

	return frame
end

------------------------------------------------------------------------------
-- The page a tab shows while its feature is off.
------------------------------------------------------------------------------

local offPage

local function CreateOffPage()
	offPage = UI.CreateWindow("NraKitFeatureOffFrame", "", UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT, 0, "_off")
	local body = offPage.body
	offPage.name = body:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	offPage.name:SetPoint("TOP", 0, -110)
	offPage.name:SetTextColor(unpack(UI.GOLD))
	offPage.status = body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	offPage.status:SetPoint("TOP", offPage.name, "BOTTOM", 0, -8)
	offPage.status:SetText("This feature is off.")
	offPage.description = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	offPage.description:SetPoint("TOP", offPage.status, "BOTTOM", 0, -24)
	offPage.description:SetWidth(520)
	offPage.description:SetJustifyH("CENTER")
	offPage.description:SetSpacing(3)
	offPage.turnOn = UI.CreateFlatButton(body, "", 32)
	offPage.turnOn:SetSelected(true)
	offPage.turnOn:SetPoint("TOP", offPage.description, "BOTTOM", 0, -30)
	offPage.turnOn:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns:SetSetting(offPage.module.key, true) -- UI.RefreshTabs then opens the real window
	end)
	offPage.settings = UI.CreateFlatButton(body, "Its Settings", 22)
	offPage.settings:SetPoint("TOP", offPage.turnOn, "BOTTOM", 0, -12)
	offPage.settings:SetScript("OnClick", function()
		ns:OpenSettings(offPage.module.name, offPage.module.key)
	end)
end

function ShowOffPage(tab)
	local module = ns.modules[tab.module]
	if not module then
		return
	end
	if not offPage then
		CreateOffPage()
	end
	offPage.module = module
	offPage.tabKey = tab.key
	offPage.name:SetText(module.name)
	offPage.description:SetText(module.description)
	offPage.turnOn.text:SetText("Turn on " .. module.name)
	offPage.turnOn:SetWidth(offPage.turnOn.text:GetStringWidth() + 40)
	if offPage:IsShown() then
		RefreshTabStrip(offPage) -- from one off tab to another
	else
		offPage:Show()
	end
end

-- A sidebar entry: label on the left, a small count on the right, an optional second
-- line (button:SetSubtext). button:SetSelected(on) shows the orange marker.
function UI.CreateNavButton(parent, width, height, label)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	button.selected = button:CreateTexture(nil, "BACKGROUND")
	button.selected:SetAllPoints()
	button.selected:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.12)
	button.bar = button:CreateTexture(nil, "ARTWORK")
	button.bar:SetColorTexture(unpack(UI.ACCENT))
	button.bar:SetPoint("TOPLEFT"); button.bar:SetPoint("BOTTOMLEFT"); button.bar:SetWidth(2)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.05)

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.text:SetPoint("LEFT", 10, 0)
	button.text:SetPoint("RIGHT", -40, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	button.text:SetText(label)
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	button.count:SetPoint("RIGHT", -8, 0)
	button.subtext = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	button.subtext:SetPoint("BOTTOMLEFT", 10, 5)
	button.subtext:SetPoint("RIGHT", -8, 0)
	button.subtext:SetJustifyH("LEFT")
	button.subtext:SetWordWrap(false)

	function button:SetSubtext(text)
		self.subtext:SetText(text or "")
		self.text:ClearAllPoints()
		if text and text ~= "" then
			self.text:SetPoint("TOPLEFT", 10, -5)
			self.count:ClearAllPoints()
			self.count:SetPoint("TOPRIGHT", -8, -6)
		else
			self.text:SetPoint("LEFT", 10, 0)
			self.count:ClearAllPoints()
			self.count:SetPoint("RIGHT", -8, 0)
		end
		self.text:SetPoint("RIGHT", -40, 0)
	end

	function button:SetSelected(on, color)
		self.selected:SetShown(on)
		self.bar:SetShown(on)
		if color then
			self.text:SetTextColor(unpack(color))
		else
			self.text:SetTextColor(unpack(on and UI.GOLD or UI.TEXT))
		end
	end

	button:SetSelected(false)
	return button
end

-- A flat text button for tabs, chips and toggles; button:SetSelected(on) highlights it.
function UI.CreateFlatButton(parent, label, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(height or 22)
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.06)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("CENTER")
	button.text:SetText(label)
	button:SetWidth(button.text:GetStringWidth() + 20)

	function button:SetSelected(on)
		self.isSelected = on and true or false
		if on then
			self.bg:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.25)
			self.text:SetTextColor(unpack(UI.GOLD))
		else
			self.bg:SetColorTexture(1, 1, 1, 0.05)
			self.text:SetTextColor(unpack(UI.TEXT))
		end
	end

	button:SetSelected(false)
	return button
end

-- Fading a frame in or out (e.g. hiding in combat), quickly.
UI.FADE_SECONDS = 0.25
local fading = {} -- frame -> { from, to, start, hide }
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self)
	local now = GetTime()
	for frame, fade in pairs(fading) do
		local progress = math.min(1, (now - fade.start) / UI.FADE_SECONDS)
		frame:SetAlpha(fade.from + (fade.to - fade.from) * progress)
		if progress >= 1 then
			fading[frame] = nil
			if fade.hide then
				frame:Hide()
			end
		end
	end
	if not next(fading) then
		self:Hide()
	end
end)

local function StartFade(frame, to, hide)
	fading[frame] = { from = frame:GetAlpha(), to = to, start = GetTime(), hide = hide }
	fader:Show()
end

-- Shows a frame (from see-through, if it was hidden) and fades it to `alpha`.
function UI.FadeIn(frame, alpha)
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
	end
	StartFade(frame, alpha or 1, false)
end

-- Fades a frame out, then hides it.
function UI.FadeOut(frame)
	if frame:IsShown() and not (fading[frame] and fading[frame].hide) then
		StartFade(frame, 0, true)
	end
end

function UI.IsFading(frame)
	return fading[frame] ~= nil
end

function UI.IsFadingOut(frame)
	return fading[frame] ~= nil and fading[frame].hide
end

function UI.StopFade(frame)
	fading[frame] = nil
end

-- A dropdown: a flat button showing the choice, opening a menu of them.
-- options = { get = fn() -> value, set = fn(value), choices = { { value, label }, ... } or a
-- function returning them, width = number }.
function UI.CreateChoiceSelect(parent, options)
	local button = UI.CreateFlatButton(parent, "", 22)
	button:SetWidth(options.width or 200)
	button.text:ClearAllPoints()
	button.text:SetPoint("LEFT", 8, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -4, -3)

	local function Choices()
		return type(options.choices) == "function" and options.choices() or options.choices
	end
	local function Set(value)
		options.set(value)
		button:Refresh()
	end
	button:SetScript("OnClick", function(self)
		local current = options.get()
		MenuUtil.CreateContextMenu(self, function(_, root)
			for _, choice in ipairs(Choices()) do
				root:CreateRadio(choice[2], function(value)
					return value == current
				end, Set, choice[1])
			end
		end)
	end)

	function button:Refresh()
		local value = options.get()
		local label = value
		for _, choice in ipairs(Choices()) do
			if choice[1] == value then
				label = choice[2]
			end
		end
		self.text:SetText(label or "")
	end

	local SetButtonEnabled = button.SetEnabled
	function button:SetEnabled(enabled)
		SetButtonEnabled(self, enabled)
		self.text:SetTextColor(unpack(enabled and UI.TEXT or UI.TEXT_DIM))
	end

	button:Refresh()
	return button
end

-- A "?" toggle for a window's how-to (what an empty list says), so it can be read again once
-- the list has something in it. onToggle(open) redraws; button.open is the state.
function UI.CreateHelpButton(parent, title, onToggle)
	local button = UI.CreateFlatButton(parent, "?", 22)
	button:SetWidth(22)
	button.open = false
	button:SetScript("OnClick", function(self)
		self.open = not self.open
		self:SetSelected(self.open)
		PlaySound(self.open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		onToggle(self.open)
	end)
	button:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, title, self.open and "Click to hide it." or "Click to show how, with examples.")
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	function button:SetOpen(open)
		self.open = open
		self:SetSelected(open)
	end
	return button
end

-- Thin dark notches at 25%, 50% and 75% of a progress bar (kept in place as it resizes).
function UI.AddMilestoneTicks(bar)
	local ticks = {}
	for index, fraction in ipairs({ 0.25, 0.5, 0.75 }) do
		local tick = bar:CreateTexture(nil, "OVERLAY")
		tick:SetColorTexture(0.04, 0.04, 0.06, 0.9)
		tick:SetWidth(1)
		tick.fraction = fraction
		ticks[index] = tick
	end
	local function Place(self, width)
		for _, tick in ipairs(ticks) do
			tick:ClearAllPoints()
			tick:SetPoint("TOP", self, "TOPLEFT", (width or self:GetWidth()) * tick.fraction, 0)
			tick:SetPoint("BOTTOM", self, "BOTTOMLEFT", (width or self:GetWidth()) * tick.fraction, 0)
		end
	end
	bar:HookScript("OnSizeChanged", Place)
	Place(bar)
	bar.ticks = ticks
end

-- A search box; onChange(text) gets the trimmed, lower-case text.
function UI.CreateSearchBox(parent, width, onChange)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(width, 22)
	local last = ""
	box:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or ""):lower()
		if text ~= last then
			last = text
			onChange(text)
		end
	end)
	return box
end

-- A mouse-wheel scroll area with a thin position marker on the right (only when there's
-- something to scroll; scroll.ShowMarker = function() -> bool can hide it more, then call
-- scroll:UpdateThumb()). Returns the ScrollFrame; scroll.content is the child to fill,
-- scroll:SetScroll(y) scrolls.
function UI.CreateScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll.content = content

	local thumb = parent:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(1, 1, 1, 0.2)
	thumb:SetWidth(3)
	scroll.thumb = thumb

	function scroll:UpdateThumb()
		local range = self:GetVerticalScrollRange()
		local visible = self:GetHeight()
		-- Less than a pixel is rounding, not something to scroll.
		if range < 1 or (self.ShowMarker and not self:ShowMarker()) then
			thumb:Hide()
			return
		end
		local track = visible - 8
		local thumbHeight = math.max(24, track * visible / (visible + range))
		local offset = (track - thumbHeight) * self:GetVerticalScroll() / range
		thumb:SetHeight(thumbHeight)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPLEFT", self, "TOPRIGHT", 5, -4 - offset)
		thumb:Show()
	end

	function scroll:SetScroll(value)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(math.min(math.max(value, 0), math.max(range, 0)))
		self:UpdateThumb()
	end

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetScroll(self:GetVerticalScroll() - delta * 60)
	end)
	scroll:SetScript("OnScrollRangeChanged", function(self)
		self:UpdateThumb()
	end)
	return scroll
end
