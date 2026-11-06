local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.moduleOrder = {}

-- Modules register themselves at file load. A module is a table with:
--   key         unique id, also the SavedVariables key for its enabled flag
--   name        label shown in the settings panel
--   description tooltip shown in the settings panel
--   default     whether the module is enabled on a fresh install
--   options     optional list of sub-options, shown indented under the module's checkbox:
--               { key, name, description, default }                 checkbox
--               { key, name, description, default, type = "number",
--                 min, max, step }                                  slider
--               An option with `parent = <option key>` is nested under that checkbox.
--   OnInitialize(self)                   called once on PLAYER_LOGIN
--   OnEnabledChanged(self, on)           called when the module is toggled
--   OnOptionChanged(self, key, value)    called when a sub-option changes
function ns:RegisterModule(module)
	assert(module.key and not self.modules[module.key], "NraKit: invalid or duplicate module key")
	self.modules[module.key] = module
	table.insert(self.moduleOrder, module)
end

function ns:IsModuleEnabled(key)
	return NraKitDB and NraKitDB[key] == true
end

function ns:GetOption(key)
	return NraKitDB and NraKitDB[key] == true
end

function ns:GetValue(key)
	return NraKitDB and NraKitDB[key]
end

local function SetDefault(key, default, isNumber)
	if isNumber then
		if type(NraKitDB[key]) ~= "number" then
			NraKitDB[key] = default
		end
	elseif NraKitDB[key] == nil then
		NraKitDB[key] = default and true or false
	end
end

local function InitializeDB()
	NraKitDB = NraKitDB or {}
	for _, module in ipairs(ns.moduleOrder) do
		SetDefault(module.key, module.default)
		for _, option in ipairs(module.options or {}) do
			SetDefault(option.key, option.default, option.type == "number")
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		self:UnregisterEvent("ADDON_LOADED")
		InitializeDB()
		ns:RegisterSettings()
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		for _, module in ipairs(ns.moduleOrder) do
			if module.OnInitialize then
				module:OnInitialize()
			end
		end
	end
end)

SLASH_NRAKIT1 = "/nrakit"
SLASH_NRAKIT2 = "/nra"
SlashCmdList.NRAKIT = function()
	ns:OpenSettings()
end
