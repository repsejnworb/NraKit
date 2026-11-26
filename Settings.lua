local addonName, ns = ...

-- Two settings UIs share this file's settings: Blizzard's (Options > AddOns > NraKit)
-- and our own window (Options.lua, opened with /nra).
--
-- Blizzard layout: the main NraKit page lists one on/off switch per module, grouped
-- under section headers. Modules with options also get their own subpage (in the
-- tree under NraKit), where options are grouped under headers.
--
-- Every module and option gets a Blizzard Setting object (ns.settings[key]); changing a
-- value through it saves it to NraKitDB and calls the module's OnEnabledChanged or
-- OnOptionChanged, whichever UI did it.

-- Section order, in both UIs. Sections not listed here go last.
ns.sectionOrder = { "Units & Nameplates", "Classes", "Quests", "Bags & Items", "Professions", "Trackers & Reminders", "Mail", "Utilities" }

ns.settings = {}
-- Functions called with (moduleKey, on) after any module is turned on or off (e.g. Shortcuts
-- adds or takes back a feature's short command).
ns.moduleToggledCallbacks = {}
ns.optionsButtons = {} -- module key -> list of { label, description, onClick }

-- { { name = section, modules = { module, ... }, subsections = { { name, modules }, ... } }, ... }
-- in display order; subsections in the order their first module registered.
function ns:GetSections()
	local byName, sections = {}, {}
	for _, name in ipairs(self.sectionOrder) do
		byName[name] = { name = name, modules = {} }
		table.insert(sections, byName[name])
	end
	for _, module in ipairs(self.moduleOrder) do
		local name = module.section or module.name
		if not byName[name] then
			byName[name] = { name = name, modules = {} }
			table.insert(sections, byName[name])
		end
		local section = byName[name]
		table.insert(section.modules, module)
		section.subsections = section.subsections or {}
		if module.subsection then
			local subsection
			for _, each in ipairs(section.subsections) do
				if each.name == module.subsection then
					subsection = each
				end
			end
			if not subsection then
				subsection = { name = module.subsection, modules = {} }
				table.insert(section.subsections, subsection)
			end
			table.insert(subsection.modules, module)
		end
	end
	for i = #sections, 1, -1 do
		if #sections[i].modules == 0 then
			table.remove(sections, i)
		end
	end
	return sections
end

-- Sets a module's enabled flag or an option, with the same effects as the settings UI.
function ns:SetSetting(key, value)
	local setting = self.settings[key]
	if setting then
		setting:SetValue(value)
	end
end

-- Adds a button to a module's options (both UIs show it), e.g. to open a list page.
function ns:AddOptionsButton(moduleKey, label, description, onClick)
	self.optionsButtons[moduleKey] = self.optionsButtons[moduleKey] or {}
	table.insert(self.optionsButtons[moduleKey], { label = label, description = description, onClick = onClick })
end

local function RegisterSetting(category, key, name, varType, default, onChanged)
	local variable = addonName .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, NraKitDB, varType, name, default)

	setting:SetValueChangedCallback(function(_, value)
		onChanged(value)
	end)
	ns.settings[key] = setting

	return setting
end

-- Dropdown choices for a sound option: the curated sounds, plus the current one if it
-- came from "More sounds..." in the NraKit window.
local function SoundOptions(key)
	return function()
		local container = Settings.CreateControlTextContainer()
		container:Add("none", "None")
		local current = NraKitDB[key]
		local found = current == "none"
		for _, group in ipairs(ns.sounds.CURATED) do
			for _, entry in ipairs(group.entries) do
				local value = "kit:" .. entry[2]
				if SOUNDKIT[entry[2]] then
					container:Add(value, group.group .. ": " .. entry[1])
					found = found or value == current
				end
			end
		end
		if not found and type(current) == "string" then
			container:Add(current, ns.sounds.Label(current))
		end
		return container:GetData()
	end
end

-- Dropdown choices for a choice option (its list, or what its function returns now).
local function ChoiceOptions(entry)
	return function()
		local container = Settings.CreateControlTextContainer()
		local choices = type(entry.choices) == "function" and entry.choices() or entry.choices
		for _, choice in ipairs(choices) do
			container:Add(choice[1], choice[2])
		end
		return container:GetData()
	end
end

local function CreateControl(category, entry, onChanged)
	if entry.type == "choice" then
		local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.String, entry.default, onChanged)
		return setting, Settings.CreateDropdown(category, setting, ChoiceOptions(entry), entry.description)
	end
	if entry.type == "sound" then
		local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.String, entry.default, function(value)
			ns.sounds.Play(value)
			onChanged(value)
		end)
		return setting, Settings.CreateDropdown(category, setting, SoundOptions(entry.key), entry.description)
	end
	if entry.type == "number" then
		local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Number, entry.default, onChanged)
		local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return ns:FormatOptionValue(entry, value)
		end)
		return setting, Settings.CreateSlider(category, setting, options, entry.description)
	end

	local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Boolean,
		entry.default and true or false, onChanged)
	return setting, Settings.CreateCheckbox(category, setting, entry.description)
end

-- A slider option's value as shown next to the slider.
function ns:FormatOptionValue(option, value)
	local format = option.format or "%d"
	if type(format) == "function" then
		return format(value)
	end
	return string.format(format, value)
end

local function AddHeader(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function RegisterModuleOptions(category, module, moduleSetting, moduleInitializer)
	local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, module.name)

	-- option key -> { setting, initializer }, so options can nest under other options
	local controls = {}
	for _, option in ipairs(module.options) do
		if option.header then
			AddHeader(layout, option.header)
		end
		local setting, initializer = CreateControl(subcategory, option, function(value)
			if module.OnOptionChanged then
				module:OnOptionChanged(option.key, value)
			end
		end)
		controls[option.key] = { setting = setting, initializer = initializer }

		-- An option that needs another module (option.requires) greys out while it's off, and
		-- one another option takes the place of (option.disabledBy) while that one is on.
		local function RequiredOn()
			return (not option.requires or NraKitDB[option.requires] == true)
				and not (option.disabledBy and NraKitDB[option.disabledBy] == true)
		end
		-- Re-check (grey out or not) when the option that takes its place changes.
		if option.disabledBy and initializer.AddEvaluateStateCVar then
			initializer:AddEvaluateStateCVar(addonName .. "_" .. option.disabledBy)
		end
		local parent = option.parent and controls[option.parent]
		if parent then
			-- Parent is on this page, so Blizzard indents the option under it.
			initializer:SetParentInitializer(parent.initializer, function()
				return moduleSetting:GetValue() and parent.setting:GetValue() and RequiredOn()
			end)
		else
			-- Parent is the module switch on the main page: greys out without indenting.
			initializer:SetParentInitializer(moduleInitializer, function()
				return moduleSetting:GetValue() and RequiredOn()
			end)
		end
	end
	return subcategory, layout
end

function ns:RegisterSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

	layout:AddInitializer(CreateSettingsButtonInitializer("", "Open NraKit window", function()
		ns:OpenSettings()
	end, "The same settings in NraKit's own window, with search. Also opens with /nra.", true))

	for _, section in ipairs(self:GetSections()) do
		AddHeader(layout, section.name)
		for _, module in ipairs(section.modules) do
			local moduleSetting, moduleInitializer = CreateControl(category, module, function(value)
				if module.OnEnabledChanged then
					module:OnEnabledChanged(value)
				end
				ns.UI.RefreshTabs() -- its tab brightens or dims, its page turns into its window
				for _, callback in ipairs(ns.moduleToggledCallbacks) do
					callback(module.key, value)
				end
			end)

			local subcategory, sublayout
			if module.options and #module.options > 0 then
				subcategory, sublayout = RegisterModuleOptions(category, module, moduleSetting, moduleInitializer)
			end
			-- Lets a module add custom controls or pages (e.g. a canvas page for a list).
			if module.OnSettingsRegistered then
				module:OnSettingsRegistered(category, subcategory, sublayout)
			end
			if sublayout then
				for _, button in ipairs(self.optionsButtons[module.key] or {}) do
					sublayout:AddInitializer(CreateSettingsButtonInitializer("", button.label, button.onClick,
						button.description, true))
				end
			end
		end
	end

	Settings.RegisterAddOnCategory(category)
	self.settingsCategory = category
end

function ns:OpenBlizzardSettings(category)
	category = category or self.settingsCategory
	if category then
		Settings.OpenToCategory(category:GetID())
	end
end
