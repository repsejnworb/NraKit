local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.moduleOrder = {}

-- Modules register themselves at file load. A module is a table with:
--   key         unique id, also the SavedVariables key for its enabled flag
--   section     header on the main settings page, and the name of the module's subpage
--   name        label shown in the settings panel
--   description tooltip shown in the settings panel
--   default     whether the module is enabled on a fresh install (always false: every
--               feature is opt-in)
--   options     optional list of sub-options, shown indented under the module's checkbox:
--               { key, name, description, default }                 checkbox
--               { key, name, description, default, type = "number",
--                 min, max, step, format? }                         slider
--               An option with `parent = <option key>` is nested under that checkbox,
--               and `header = "..."` starts a new sub-section before the option.
--   OnInitialize(self)                   called once on PLAYER_LOGIN
--   OnEnabledChanged(self, on)           called when the module is toggled
--   OnOptionChanged(self, key, value)    called when a sub-option changes
--   OnSettingsRegistered(self, rootCategory, subcategory, sublayout)
--                                        optional; add custom settings controls/pages
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

-- Calls fn(itemButton) for every item button in the open bags (separate or combined).
-- Reads Blizzard's frames directly instead of using ContainerFrameUtil_EnumerateContainerFrames
-- or frame:EnumerateValidItems(): both fill lazy caches (the frame list, frame.size) when
-- first called, and if our code is the one filling them they're tainted. Blizzard's own
-- bag code then reads them, and using an item from the bags gets blocked as "NraKit".
function ns:ForEachBagItemButton(fn)
	local seen = {}
	local function visit(frame)
		if not frame or not frame:IsShown() or not frame.Items then
			return
		end
		for _, itemButton in ipairs(frame.Items) do
			if not seen[itemButton] and itemButton:IsShown() and itemButton:GetBagID() then
				seen[itemButton] = true
				fn(itemButton)
			end
		end
	end
	visit(ContainerFrameCombinedBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		visit(frame)
	end
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
