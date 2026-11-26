local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.moduleOrder = {}

-- Modules register themselves at file load. A module is a table with:
--   key         unique id, also the SavedVariables key for its enabled flag
--   section     group in both settings UIs; one of ns.sectionOrder (Settings.lua)
--   subsection  optional; a group inside the section (e.g. "Warrior" in "Classes"): the NraKit
--               window lists it under the section in its sidebar, showing just its features
--   name        label shown in the settings panel
--   description tooltip shown in the settings panel
--   default     whether the module is enabled on a fresh install (always false: every
--               feature is opt-in)
--   options     optional list of sub-options, shown indented under the module's checkbox:
--               { key, name, description, default }                 checkbox
--               { key, name, description, default = "kit:READY_CHECK",
--                 type = "sound" }                                  sound picker (Sounds.lua)
--               { key, name, description, default = "a",
--                 type = "choice", choices = { { "a", "A" }, ... } }  dropdown (choices can be a
--                                                                   function returning the list)
--               { key, name, description, default, type = "number",
--                 min, max, step, format? }                         slider (format: a
--                                                                   string.format pattern, or
--                                                                   a function(value) -> label)
--               An option with `parent = <option key>` is nested under that checkbox,
--               `header = "..."` starts a new sub-section before the option (`headerColor =
--               { r, g, b }` colours it in the NraKit window), and
--               `requires = <module key>` greys it out while that other module is off, and
--               `disabledBy = <option key>` greys it out while that other option is on (it
--               takes this one's place).
--   Migrate(self, db)                    optional; called on load before defaults are filled
--                                        in, to carry over settings that moved (see Mail.lua)
--   OnInitialize(self)                   called once on PLAYER_LOGIN
--   OnEnabledChanged(self, on)           called when the module is toggled
--   OnOptionChanged(self, key, value)    called when a sub-option changes
--   OnSettingsRegistered(self, rootCategory, subcategory, sublayout)
--                                        optional; add custom settings controls/pages.
--                                        Buttons added with ns:AddOptionsButton show in both UIs.
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

local function SetDefault(key, default, optionType)
	if optionType == "number" then
		if type(NraKitDB[key]) ~= "number" then
			NraKitDB[key] = default
		end
	elseif optionType == "sound" or optionType == "choice" then
		if type(NraKitDB[key]) ~= "string" then
			NraKitDB[key] = default
		end
	elseif NraKitDB[key] == nil then
		NraKitDB[key] = default and true or false
	end
end

local function InitializeDB()
	NraKitDB = NraKitDB or {}
	-- Settings moved or renamed are carried over first, so the defaults don't fill them in.
	for _, module in ipairs(ns.moduleOrder) do
		if module.Migrate then
			module:Migrate(NraKitDB)
		end
	end
	for _, module in ipairs(ns.moduleOrder) do
		SetDefault(module.key, module.default)
		for _, option in ipairs(module.options or {}) do
			SetDefault(option.key, option.default, option.type)
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
				-- One module's error (e.g. a Blizzard function missing on this client)
				-- must not stop the modules after it from starting.
				xpcall(module.OnInitialize, geterrorhandler(), module)
			end
		end
	end
end)

function ns:Print(message)
	print("|cff33ccffNraKit|r: " .. message)
end

-- Your character's name, "Firstname Surname" (Forever has no realms; UnitName gives
-- the two parts). Two of your characters can share a first name, so per-character
-- data is saved under this, never the first name alone.
function ns:PlayerName()
	local name, surname = UnitName("player")
	if surname and surname ~= "" then
		return name .. " " .. surname
	end
	return name
end

-- Subcommands of /nrakit and /nra, e.g. "/nra scan list". Registered by modules:
-- handler(rest) gets everything after the subcommand, trimmed.
--
-- help = { summary = "one line for /nra help", usage = { "/nra goal level <n> - reach a level", ... } }.
-- Aliases pass the same help table; "/nra <name> help" (or "?") prints it.
local slashCommands, slashHelp, helpOrder = {}, {}, {}

function ns:RegisterSlashCommand(name, handler, help)
	name = name:lower()
	slashCommands[name] = handler
	if help then
		slashHelp[name] = help
		if not help.name then
			help.name = name
			table.insert(helpOrder, help)
		end
	end
end

-- "/nra goal level <n> - reach a level" -> command in gold, description in white.
local function PrintUsageLine(line)
	local command, description = line:match("^(.-) %- (.+)$")
	if command then
		print("  |cffffd100" .. command .. "|r  " .. description)
	else
		print("  " .. line)
	end
end

function ns:PrintCommandHelp(name)
	local help = slashHelp[name]
	if not help then
		return false
	end
	ns:Print(help.summary)
	for _, line in ipairs(help.usage or {}) do
		PrintUsageLine(line)
	end
	return true
end

local function PrintAllHelp()
	ns:Print("commands (add |cffffd100help|r after one for details, e.g. /nra goal help):")
	PrintUsageLine("/nra - open the NraKit settings window")
	for _, help in ipairs(helpOrder) do
		PrintUsageLine("/nra " .. help.name .. " - " .. help.summary)
	end
end

-- Runs a /nra command line ("goal 20 linen"), as typed after /nra (Shortcuts.lua uses it too).
function ns:RunSlashCommand(input)
	local command, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	command = command:lower()
	local handler = slashCommands[command]
	if command == "" then
		ns:OpenSettings()
	elseif command == "help" or command == "?" then
		if rest == "" or not ns:PrintCommandHelp(rest:lower()) then
			PrintAllHelp()
		end
	elseif handler and (rest:lower() == "help" or rest == "?") and slashHelp[command] then
		ns:PrintCommandHelp(command)
	elseif handler then
		handler(rest)
	else
		ns:Print("Unknown command \"" .. command .. "\". Type /nra help for the list.")
	end
end

SLASH_NRAKIT1 = "/nrakit"
SLASH_NRAKIT2 = "/nra"
SlashCmdList.NRAKIT = function(input)
	ns:RunSlashCommand(input)
end

-- Things waiting for you, counted on the NraKit button's badge (Modules/NraKitButton.lua):
-- badge = { key, label, option = <NraKit button option that turns it on>, module = <feature
-- that must be on>?, count = function() -> number, text = function(count) -> tooltip line,
-- open = function() shows it }. Call ns:BadgeChanged() when a count changes.
ns.badges = {}

function ns:RegisterBadge(badge)
	table.insert(self.badges, badge)
end

function ns:BadgeChanged()
	if self.onBadgeChanged then
		self.onBadgeChanged()
	end
end

-- Actions in NraKit's menus (the addon button's and the NraKit button's), after the windows:
-- action = { label = text or function() -> text (nil leaves it out), module = <feature that
-- must be on>?, onClick }.
ns.menuActions = {}

function ns:RegisterMenuAction(action)
	table.insert(self.menuActions, action)
end

local function UnseenCount()
	return ns.whatsNew and ns.whatsNew.UnseenCount() or 0
end

-- NraKit's menu: the windows of features that are on, their actions, What's new and Settings.
function ns:FillMenu(root)
	root:CreateTitle(addonName)
	local windows = 0
	for _, tab in ipairs(ns.UI.GetTabs(true)) do
		if tab.key ~= "settings" then
			windows = windows + 1
			root:CreateButton(tab.menuLabel or tab.label, function()
				ns.UI.ShowTab(tab.key)
			end)
		end
	end
	local actions = {}
	for _, action in ipairs(ns.menuActions) do
		local label = action.label
		if type(label) == "function" then
			label = label()
		end
		if label and (not action.module or ns:IsModuleEnabled(action.module)) then
			table.insert(actions, { label = label, onClick = action.onClick })
		end
	end
	if windows > 0 and #actions > 0 then
		root:CreateDivider()
	end
	for _, action in ipairs(actions) do
		root:CreateButton(action.label, action.onClick)
	end
	if windows + #actions > 0 then
		root:CreateDivider()
	end
	local unseen = UnseenCount()
	root:CreateButton(unseen > 0 and string.format("What's new |cffff9933(%d)|r", unseen) or "What's new", function()
		ns:OpenWhatsNew()
	end)
	root:CreateButton("Settings", function()
		ns.UI.ShowTab("settings")
	end)
end

-- Addon compartment (the addon button by the minimap); wired up in the TOC.
-- Left-click: the NraKit window. Right-click: NraKit's menu.
local function OpenCompartmentMenu()
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		ns:FillMenu(root)
	end)
end

function NraKit_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		OpenCompartmentMenu()
	else
		ns:OpenSettings()
	end
end

function NraKit_OnCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, addonName)
	GameTooltip_AddInstructionLine(GameTooltip, "Left-click: settings")
	local names = {}
	for _, tab in ipairs(ns.UI.GetTabs(true)) do
		if tab.key ~= "settings" then
			table.insert(names, tab.menuLabel or tab.label)
		end
	end
	table.insert(names, "What's new")
	GameTooltip_AddInstructionLine(GameTooltip, "Right-click: " .. table.concat(names, ", "))
	local unseen = UnseenCount()
	if unseen > 0 then
		GameTooltip_AddNormalLine(GameTooltip, string.format("What's new: %d %s since you last looked (/nra new)",
			unseen, unseen == 1 and "change" or "changes"))
	end
	GameTooltip:Show()
end

function NraKit_OnCompartmentLeave()
	GameTooltip:Hide()
end
