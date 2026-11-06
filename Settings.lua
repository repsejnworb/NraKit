local addonName, ns = ...

function ns:RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(addonName)

	for _, module in ipairs(self.moduleOrder) do
		local variable = addonName .. "_" .. module.key
		local setting = Settings.RegisterAddOnSetting(category, variable, module.key, NraKitDB,
			Settings.VarType.Boolean, module.name, module.default and true or false)

		setting:SetValueChangedCallback(function(_, value)
			if module.OnEnabledChanged then
				module:OnEnabledChanged(value)
			end
		end)

		Settings.CreateCheckbox(category, setting, module.description)
	end

	Settings.RegisterAddOnCategory(category)
	self.settingsCategory = category
end

function ns:OpenSettings()
	if self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory:GetID())
	end
end
