local addonName, ns = ...

-- NraKit's own settings window (/nra), next to Blizzard's Options > AddOns page.
--
-- Left: a search box, "What's new" (with a dot while there's something you haven't
-- seen), "All features" and one entry per section (with enabled/total counts). Right: a
-- card per feature with its on/off switch and description; a card's options open inline
-- under it. What's new lists Changelog.lua by version, with an on/off switch and a
-- Settings link next to each new feature. Everything is built from the module definitions and
-- changed through ns:SetSetting, so it stays in step with the Blizzard page.
--
-- The look matches the Campfire timer bar: dark flat panel, hairline borders, orange accent.

local UI = ns.UI
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local SIDEBAR_WIDTH = 190
local PAD = UI.PAD
local CARD_GAP = 8
local INDENT = 20

local EDGE, PANEL, ACCENT = UI.EDGE, UI.PANEL, UI.ACCENT
local NAME_ON, NAME_OFF = UI.GOLD, UI.GREY
local TEXT, TEXT_DIM = UI.TEXT, UI.TEXT_DIM

local frame, content, scrollFrame, searchBox, enabledOnlyCheck, whatsNewButton
local navButtons = {}
local selectedSection -- nil = all features
local showWhatsNew = false
local unseenEntries = {} -- changelog entries new to you, marked until the window closes
local openVersions = {} -- version -> true/false once you've opened or closed it
local query = ""
local expanded = {} -- module key -> true
local newModules = {} -- module key -> true for features added since the window was last opened
local pool = UI.CreatePool()

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local ShowTooltip = UI.ShowTooltip

local function IsOn(key)
	return NraKitDB[key] == true
end

-- Whether an option can be changed: its module is on, every parent option is on, and
-- the module it needs (option.requires) is on.
local function IsOptionActive(module, option, byKey)
	if not IsOn(module.key) or (option.requires and not IsOn(option.requires))
		or (option.disabledBy and IsOn(option.disabledBy)) then
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

local function Acquire(kind, create)
	return pool:Acquire(kind, create)
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

-- Checkboxes are pooled: the click area each use widens over its label is reset here, or a
-- reused one could cover whatever is next to it (it covered What's new's Settings buttons).
local function AcquireCheck()
	local check = Acquire("check", function()
		local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		check:SetFrameLevel(content:GetFrameLevel() + 3)
		check:SetScript("OnClick", function(self)
			PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			if ns.settings[self.settingKey] then
				ns:SetSetting(self.settingKey, self:GetChecked() and true or false)
			else
				-- Not a module option (e.g. What's new's chat line): just saved.
				NraKitDB[self.settingKey] = self:GetChecked() and true or false
			end
			Render()
		end)
		check:SetScript("OnEnter", function(self)
			ShowTooltip(self, self.tooltipTitle, self.tooltipText)
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		return check
	end)
	check:SetHitRectInsets(0, 0, 0, 0)
	return check
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
		header:SetTextColor(unpack(option.headerColor or ACCENT))
		header:SetPoint("TOPLEFT", content, "TOPLEFT", x - OptionDepth(option, byKey) * INDENT, y - 6)
		y = y - 22
	end

	if option.type == "choice" then
		local label = AcquireText("GameFontHighlight")
		label:SetText(option.name)
		label:SetWidth(200)
		label:SetWordWrap(false)
		label:SetTextColor(unpack(active and TEXT or TEXT_DIM))
		label:SetPoint("TOPLEFT", content, "TOPLEFT", x + 4, y - 7)

		local select = Acquire("choice", function()
			local widget
			widget = UI.CreateChoiceSelect(content, {
				width = 238,
				get = function()
					return widget and widget.option and NraKitDB[widget.option.key]
				end,
				set = function(value)
					ns:SetSetting(widget.option.key, value)
				end,
				choices = function()
					local choices = widget and widget.option and widget.option.choices or {}
					return type(choices) == "function" and choices() or choices
				end,
			})
			widget:SetFrameLevel(content:GetFrameLevel() + 3)
			widget:SetScript("OnEnter", function(self)
				ShowTooltip(self, self.option and self.option.name, self.option and self.option.description)
			end)
			widget:SetScript("OnLeave", GameTooltip_Hide)
			return widget
		end)
		select.option = option
		select:Refresh()
		select:SetEnabled(active)
		select:SetPoint("TOPLEFT", content, "TOPLEFT", math.min(x + 210, x + width - 300), y - 2)
		return y - 30
	end

	if option.type == "sound" then
		local label = AcquireText("GameFontHighlight")
		label:SetText(option.name)
		label:SetWidth(200)
		label:SetWordWrap(false)
		label:SetTextColor(unpack(active and TEXT or TEXT_DIM))
		label:SetPoint("TOPLEFT", content, "TOPLEFT", x + 4, y - 7)

		local select = Acquire("sound", function()
			local widget
			widget = UI.CreateSoundSelect(content, {
				width = 190,
				get = function()
					-- Also called while the widget is being created, before it has a key.
					return widget and widget.optionKey and NraKitDB[widget.optionKey]
				end,
				set = function(value)
					ns:SetSetting(widget.optionKey, value)
				end,
			})
			widget:SetFrameLevel(content:GetFrameLevel() + 3)
			return widget
		end)
		select.optionKey = option.key
		select:Refresh()
		select:SetEnabled(active)
		select:SetPoint("TOPLEFT", content, "TOPLEFT", math.min(x + 210, x + width - 300), y - 2)
		return y - 30
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

------------------------------------------------------------------------------
-- What's new
------------------------------------------------------------------------------

local KINDS = { { "new", "New" }, { "improved", "Improved" }, { "fixed", "Fixed" } }
local CONTROLS_WIDTH = 150
local SUMMARY_NAMES = 3

-- Remembers what's new to you (to mark it while the window is open), then counts it as seen.
local function EnterWhatsNew()
	if not next(unseenEntries) then
		local entries = ns.whatsNew.Entries()
		for index = 1, ns.whatsNew.UnseenCount() do
			unseenEntries[entries[index]] = true
		end
	end
	ns.whatsNew.MarkSeen()
end

-- "2026-11-18" -> "18 Nov 2026"
local function FormatDate(text)
	local year, month, day = (text or ""):match("^(%d+)-(%d+)-(%d+)$")
	if not year then
		return text or ""
	end
	return date("%d %b %Y", time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }))
end

-- Entries grouped by version, newest first: { version, date, entries }.
local function Releases()
	local releases = {}
	for _, entry in ipairs(ns.whatsNew.Entries()) do
		local last = releases[#releases]
		if not last or last.version ~= entry.version then
			last = { version = entry.version, date = entry.date, entries = {} }
			table.insert(releases, last)
		end
		table.insert(last.entries, entry)
	end
	return releases
end

-- One line for a closed version: its new features, and how many changes in all.
local function ReleaseSummary(release)
	local names = {}
	for _, entry in ipairs(release.entries) do
		local module = entry.kind == "new" and entry.module and ns.modules[entry.module]
		if module then
			table.insert(names, module.name)
		end
	end
	local count = #release.entries
	local changes = count == 1 and "1 change" or (count .. " changes")
	if #names == 0 then
		return changes
	end
	local shown = {}
	for index = 1, math.min(#names, SUMMARY_NAMES) do
		shown[index] = names[index]
	end
	local text = table.concat(shown, ", ")
	if #names > SUMMARY_NAMES then
		text = text .. string.format(" + %d more", #names - SUMMARY_NAMES)
	end
	return text .. "  ·  " .. changes
end

local function AcquireVersionHeader()
	return Acquire("versionHeader", function()
		local header = CreateFrame("Button", nil, content)
		header:SetFrameLevel(content:GetFrameLevel() + 1)
		header.highlight = header:CreateTexture(nil, "HIGHLIGHT")
		header.highlight:SetAllPoints()
		header.highlight:SetColorTexture(1, 1, 1, 0.03)
		header.toggle = header:CreateTexture(nil, "ARTWORK")
		header.toggle:SetSize(14, 14)
		header.toggle:SetPoint("TOPRIGHT", -10, -11)
		header:SetScript("OnClick", function(self)
			openVersions[self.version] = not self.isOpen
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Render()
		end)
		return header
	end)
end

local function AcquireSettingsLink()
	return Acquire("settingsLink", function()
		local link = UI.CreateFlatButton(content, "Settings", 20)
		link:SetFrameLevel(content:GetFrameLevel() + 3)
		link:SetScript("OnClick", function(self)
			ns:OpenSettings(self.search, self.moduleKey)
		end)
		link:SetScript("OnEnter", function(self)
			ShowTooltip(self, self.search, "Show this feature's settings.")
		end)
		link:SetScript("OnLeave", GameTooltip_Hide)
		return link
	end)
end

-- A new feature's on/off switch and Settings link, at the right of its line.
local function AddFeatureControls(module, x, y)
	local check = AcquireCheck()
	check:SetSize(22, 22)
	check:SetPoint("TOPLEFT", content, "TOPLEFT", x, y + 3)
	check:SetChecked(IsOn(module.key))
	check:SetEnabled(true)
	check.settingKey = module.key
	check.tooltipTitle, check.tooltipText = module.name, "Turn this feature on or off."
	local label = AcquireText("GameFontHighlightSmall")
	label:SetText(IsOn(module.key) and "On" or "Off")
	label:SetWordWrap(false)
	label:SetTextColor(unpack(IsOn(module.key) and NAME_ON or TEXT_DIM))
	label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	check:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0) -- "On"/"Off" too, not the Settings button
	local link = AcquireSettingsLink()
	link.search, link.moduleKey = module.name, module.key
	link:SetPoint("TOPLEFT", content, "TOPLEFT", x + 62, y + 1)
end

local function RenderWhatsNew(x, y, width)
	local title = AcquireText("GameFontNormalLarge")
	title:SetText("What's new")
	title:SetTextColor(1, 1, 1)
	title:SetPoint("TOPLEFT", content, "TOPLEFT", x + 2, y)

	local chat = AcquireCheck()
	chat:SetSize(22, 22)
	chat:SetPoint("TOPLEFT", content, "TOPLEFT", x + width - 210, y + 3)
	chat:SetChecked(ns.whatsNew.ChatEnabled())
	chat:SetEnabled(true)
	chat.settingKey = "whatsNewChat"
	chat.tooltipTitle, chat.tooltipText = "Tell me in chat after an update",
		"One line in chat after NraKit has been updated, saying what's new."
	local chatLabel = AcquireText("GameFontHighlightSmall")
	chatLabel:SetText("Tell me in chat after an update")
	chatLabel:SetWordWrap(false)
	chatLabel:SetTextColor(unpack(TEXT))
	chatLabel:SetPoint("LEFT", chat, "RIGHT", 2, 1)
	chat:SetHitRectInsets(0, -(chatLabel:GetStringWidth() + 4), 0, 0)

	local share = AcquireCheck()
	share:SetSize(22, 22)
	share:SetPoint("TOPLEFT", content, "TOPLEFT", x + width - 210, y - 21)
	share:SetChecked(ns.versionCheck.Enabled())
	share:SetEnabled(true)
	share.settingKey = "versionCheck"
	share.tooltipTitle, share.tooltipText = "Tell me when a newer NraKit is out",
		"NraKit shares its version with other NraKit users in your guild and group (hidden addon messages), and says so in chat when one of them has a newer release. Also needed for /nra who. Off: nothing is sent."
	local shareLabel = AcquireText("GameFontHighlightSmall")
	shareLabel:SetText("Tell me when a newer NraKit is out")
	shareLabel:SetWordWrap(false)
	shareLabel:SetTextColor(unpack(TEXT))
	shareLabel:SetPoint("LEFT", share, "RIGHT", 2, 1)
	share:SetHitRectInsets(0, -(shareLabel:GetStringWidth() + 4), 0, 0)
	y = y - 56

	local newer = ns.versionCheck.Newer()
	if newer then
		local notice = AcquireText("GameFontNormal")
		notice:SetWidth(width - 4)
		notice:SetText(string.format("NraKit %s is out (you have %s). Update through CurseForge or your addon manager.",
			newer, ns.versionCheck.MyVersion()))
		notice:SetTextColor(unpack(ACCENT))
		notice:SetPoint("TOPLEFT", content, "TOPLEFT", x + 2, y)
		y = y - notice:GetStringHeight() - 12
	end

	for index, release in ipairs(Releases()) do
		local hasUnseen = false
		for _, entry in ipairs(release.entries) do
			hasUnseen = hasUnseen or unseenEntries[entry] == true
		end
		local open = openVersions[release.version]
		if open == nil then
			open = index <= 2 or hasUnseen
		end
		local top = y

		local header = AcquireVersionHeader()
		header.version, header.isOpen = release.version, open
		header:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
		header:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", x + width, top - 34)
		header.toggle:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")

		local unreleased = release.version == "Unreleased"
		local name = AcquireText("GameFontNormalLarge")
		name:SetText(unreleased and "Next version" or release.version)
		name:SetWordWrap(false)
		name:SetTextColor(unpack(NAME_ON))
		name:SetPoint("TOPLEFT", content, "TOPLEFT", x + 12, y - 10)
		local when = AcquireText("GameFontDisableSmall")
		when:SetText(unreleased and "not released yet: you're running a development version" or FormatDate(release.date))
		when:SetWordWrap(false)
		when:SetPoint("LEFT", name, "RIGHT", 8, -1)
		if hasUnseen then
			local badge = AcquireText("GameFontNormalSmall")
			badge:SetText("NEW TO YOU")
			badge:SetWordWrap(false)
			badge:SetTextColor(unpack(ACCENT))
			badge:SetPoint("LEFT", when, "RIGHT", 8, 0)
		end
		y = y - 34

		if not open then
			local summary = AcquireText("GameFontHighlightSmall")
			summary:SetWidth(width - 24)
			summary:SetText(ReleaseSummary(release))
			summary:SetTextColor(unpack(TEXT_DIM))
			summary:SetPoint("TOPLEFT", content, "TOPLEFT", x + 12, y + 4)
			y = y - summary:GetStringHeight() - 6
		else
			for _, kind in ipairs(KINDS) do
				local shownHeading = false
				for _, entry in ipairs(release.entries) do
					if entry.kind == kind[1] then
						if not shownHeading then
							shownHeading = true
							local heading = AcquireText("GameFontNormalSmall")
							heading:SetText(kind[2]:upper())
							heading:SetTextColor(unpack(ACCENT))
							heading:SetPoint("TOPLEFT", content, "TOPLEFT", x + 12, y - 2)
							y = y - 20
						end
						local module = entry.kind == "new" and entry.module and ns.modules[entry.module]
						if unseenEntries[entry] then
							local dot = AcquireTexture()
							dot:SetDrawLayer("ARTWORK")
							dot:SetColorTexture(unpack(ACCENT))
							dot:SetSize(6, 6)
							dot:SetPoint("TOPLEFT", content, "TOPLEFT", x + 14, y - 5)
						end
						local text = AcquireText("GameFontHighlight")
						text:SetWidth(width - 40 - (module and CONTROLS_WIDTH or 0))
						text:SetText(entry.text)
						text:SetTextColor(unpack(unseenEntries[entry] and { 1, 1, 1 } or TEXT))
						text:SetPoint("TOPLEFT", content, "TOPLEFT", x + 26, y)
						local height = text:GetStringHeight()
						if module then
							AddFeatureControls(module, x + width - CONTROLS_WIDTH + 4, y)
							height = math.max(height, 20)
						end
						y = y - height - 8
					end
				end
			end
		end
		y = y - 6

		local background = AcquireTexture()
		background:SetDrawLayer("BACKGROUND")
		background:SetColorTexture(unpack(PANEL))
		background:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
		background:SetPoint("BOTTOMRIGHT", content, "TOPLEFT", x + width, y)
		y = y - CARD_GAP
	end
	return y
end

local function SetScroll(value)
	scrollFrame:SetScroll(value)
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
		button:SetSelected(not searching and not showWhatsNew and button.section == selectedSection)
	end
	local unseen = ns.whatsNew.UnseenCount()
	whatsNewButton:SetSelected(not searching and showWhatsNew)
	whatsNewButton.dot:SetShown(unseen > 0)
	whatsNewButton.count:SetText(unseen > 0 and tostring(unseen) or "")
end

function Render()
	if not frame then
		return
	end
	local scroll = scrollFrame:GetVerticalScroll()
	pool:ReleaseAll()

	local width = content:GetWidth() - 2 * PAD
	local x, y = PAD, -PAD
	local shown = 0
	local enabledOnly = enabledOnlyCheck:GetChecked()

	if showWhatsNew and query == "" then
		EnterWhatsNew()
		y = RenderWhatsNew(x, y, width)
		content:SetHeight(-y + PAD)
		UpdateNav()
		SetScroll(scroll)
		return
	end

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
	local button = UI.CreateNavButton(parent, SIDEBAR_WIDTH - 2 * PAD, 26, label)
	button.section, button.modules = section, modules

	button:SetScript("OnClick", function(self)
		selectedSection = self.section
		showWhatsNew = false
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
	frame = UI.CreateWindow("NraKitOptionsFrame", "NraKit", WIDTH, HEIGHT, SIDEBAR_WIDTH, "settings")
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if version and not version:find("@", 1, true) then
		local versionText = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		versionText:SetPoint("RIGHT", frame.titleBar, "RIGHT", -36, 0)
		versionText:SetText(version)
	end
	local sidebar = frame.sidebar

	searchBox = UI.CreateSearchBox(sidebar, SIDEBAR_WIDTH - 2 * PAD - 6, function(text)
		query = text
		SetScroll(0)
		Render()
	end)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD)

	whatsNewButton = UI.CreateNavButton(sidebar, SIDEBAR_WIDTH - 2 * PAD, 26, "What's new")
	whatsNewButton:SetPoint("TOPLEFT", PAD, -PAD - 34)
	whatsNewButton.dot = whatsNewButton:CreateTexture(nil, "OVERLAY")
	whatsNewButton.dot:SetColorTexture(unpack(ACCENT))
	whatsNewButton.dot:SetSize(6, 6)
	whatsNewButton.dot:SetPoint("RIGHT", whatsNewButton.count, "LEFT", -5, 0)
	whatsNewButton:SetScript("OnClick", function()
		ns:OpenWhatsNew()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)

	local anchor = CreateNavButton(sidebar, "All features", nil, ns.moduleOrder)
	anchor:SetPoint("TOPLEFT", whatsNewButton, "BOTTOMLEFT", 0, -10)
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
	scrollFrame = UI.CreateScrollArea(frame.body)
	scrollFrame:SetPoint("TOPLEFT")
	scrollFrame:SetPoint("BOTTOMRIGHT", -13, 0)
	content = scrollFrame.content
	content:SetWidth(WIDTH - SIDEBAR_WIDTH - 15)

	frame:HookScript("OnShow", function()
		MarkNewModules()
		Render()
	end)
	frame:HookScript("OnHide", function()
		wipe(newModules)
		wipe(unseenEntries)
	end)
end

-- /nra (and the button on the Blizzard page) toggles the window.
-- With a search (e.g. "farm goals"), always shows the window filtered to it, with
-- expandKey's options open; without, toggles.
function ns:OpenSettings(search, expandKey)
	if not frame then
		CreateWindow()
	end
	if search then
		if expandKey then
			expanded[expandKey] = true
		end
		showWhatsNew = false
		frame:Show()
		searchBox:SetText(search)
		Render()
	else
		frame:SetShown(not frame:IsShown())
	end
end

-- /nra new: the window on What's new (always shown, never toggled closed).
function ns:OpenWhatsNew()
	if not frame then
		CreateWindow()
	end
	showWhatsNew = true
	if query ~= "" then
		searchBox:SetText("") -- also re-renders
	end
	SetScroll(0)
	if frame:IsShown() then
		Render()
	else
		frame:Show()
	end
end

UI.RegisterTab({
	key = "settings", label = "Settings", menuLabel = "Settings", order = 1, frameName = "NraKitOptionsFrame",
	open = function()
		ns:OpenSettings()
	end,
})
