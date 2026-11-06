local addonName, ns = ...

-- Layout: the main NraKit page lists one on/off switch per module, grouped
-- under each module's section header. Modules with options also get their own
-- subpage (in the tree under NraKit), where options are grouped under headers.

local function RegisterSetting(category, key, name, varType, default, onChanged)
	local variable = addonName .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, NraKitDB, varType, name, default)

	setting:SetValueChangedCallback(function(_, value)
		onChanged(value)
	end)

	return setting
end

local function CreateControl(category, entry, onChanged)
	if entry.type == "number" then
		local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Number, entry.default, onChanged)
		local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
		local format = entry.format or "%d"
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format(format, value)
		end)
		return setting, Settings.CreateSlider(category, setting, options, entry.description)
	end

	local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Boolean,
		entry.default and true or false, onChanged)
	return setting, Settings.CreateCheckbox(category, setting, entry.description)
end

local function AddHeader(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function RegisterModuleOptions(category, module, moduleSetting, moduleInitializer)
	local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, module.section or module.name)

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

		local parent = option.parent and controls[option.parent]
		if parent then
			-- Parent is on this page, so Blizzard indents the option under it.
			initializer:SetParentInitializer(parent.initializer, function()
				return moduleSetting:GetValue() and parent.setting:GetValue()
			end)
		else
			-- Parent is the module switch on the main page: greys out without indenting.
			initializer:SetParentInitializer(moduleInitializer, function()
				return moduleSetting:GetValue()
			end)
		end
	end
	return subcategory, layout
end

function ns:RegisterSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

	for _, module in ipairs(self.moduleOrder) do
		AddHeader(layout, module.section or module.name)

		local moduleSetting, moduleInitializer = CreateControl(category, module, function(value)
			if module.OnEnabledChanged then
				module:OnEnabledChanged(value)
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
	end

	Settings.RegisterAddOnCategory(category)
	self.settingsCategory = category
end

function ns:OpenSettings()
	if self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory:GetID())
	end
end
