local addonName, ns = ...

local function RegisterSetting(category, key, name, varType, default, onChanged)
	local variable = addonName .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, NraKitDB, varType, name, default)

	setting:SetValueChangedCallback(function(_, value)
		onChanged(value)
	end)

	return setting
end

local function FormatNumber(value)
	return string.format("%d", value)
end

local function CreateControl(category, entry, onChanged)
	if entry.type == "number" then
		local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Number, entry.default, onChanged)
		local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatNumber)
		return setting, Settings.CreateSlider(category, setting, options, entry.description)
	end

	local setting = RegisterSetting(category, entry.key, entry.name, Settings.VarType.Boolean,
		entry.default and true or false, onChanged)
	return setting, Settings.CreateCheckbox(category, setting, entry.description)
end

function ns:RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(addonName)

	for _, module in ipairs(self.moduleOrder) do
		local moduleSetting, moduleInitializer = CreateControl(category, module, function(value)
			if module.OnEnabledChanged then
				module:OnEnabledChanged(value)
			end
		end)

		-- option key -> { setting, initializer }, so options can nest under other options
		local controls = {}
		for _, option in ipairs(module.options or {}) do
			local setting, initializer = CreateControl(category, option, function(value)
				if module.OnOptionChanged then
					module:OnOptionChanged(option.key, value)
				end
			end)
			controls[option.key] = { setting = setting, initializer = initializer }

			local parent = option.parent and controls[option.parent]
			initializer:Indent()
			if parent then
				initializer:SetParentInitializer(parent.initializer, function()
					return moduleSetting:GetValue() and parent.setting:GetValue()
				end)
			else
				initializer:SetParentInitializer(moduleInitializer, function()
					return moduleSetting:GetValue()
				end)
			end
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
