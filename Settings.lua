local addonName, ns = ...

local function RegisterCheckbox(category, key, name, description, default, onChanged)
	local variable = addonName .. "_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, NraKitDB,
		Settings.VarType.Boolean, name, default and true or false)

	setting:SetValueChangedCallback(function(_, value)
		onChanged(value)
	end)

	return setting, Settings.CreateCheckbox(category, setting, description)
end

function ns:RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(addonName)

	for _, module in ipairs(self.moduleOrder) do
		local moduleSetting, moduleInitializer = RegisterCheckbox(category, module.key, module.name,
			module.description, module.default, function(value)
				if module.OnEnabledChanged then
					module:OnEnabledChanged(value)
				end
			end)

		for _, option in ipairs(module.options or {}) do
			local _, optionInitializer = RegisterCheckbox(category, option.key, option.name,
				option.description, option.default, function(value)
					if module.OnOptionChanged then
						module:OnOptionChanged(option.key, value)
					end
				end)
			optionInitializer:Indent()
			optionInitializer:SetParentInitializer(moduleInitializer, function()
				return moduleSetting:GetValue()
			end)
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
