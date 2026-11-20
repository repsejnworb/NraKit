-- A stand-in for the WoW client, enough to load NraKit and click through its windows
-- outside the game. Frames are tables whose unknown methods do nothing (Get*Width and
-- friends return 100), so code paths run without drawing anything. APIs the tests care
-- about return fixed data you can change per test (wow.data).
--
-- This catches Lua errors and logic mistakes, not how things look. Check those in game.

local wow = { frames = {}, errors = {}, played = {}, printed = {} }

wow.data = {
	level = 30, xp = 100, xpMax = 1000, money = 5000,
	factions = {
		{ factionID = 501, name = "Timbermaw Hold", reaction = 5, currentStanding = 4000, currentReactionThreshold = 3000, nextReactionThreshold = 9000 },
		{ factionID = 502, name = "Argent Dawn", reaction = 4, currentStanding = 100, currentReactionThreshold = 0, nextReactionThreshold = 3000 },
	},
	watchedFaction = 501,
	skills = {
		{ isHeader = true, name = "Weapon Skills" },
		{ skillID = 43, name = "Swords", rank = 245, maxRank = 300 },
	},
	currencies = {
		{ currencyID = 1901, name = "Honor", quantity = 120, iconFileID = 1 },
	},
	items = { [4306] = { name = "Silk Cloth", bags = 0, bank = 0 } },
	-- Units by token: { name, surname?, guid?, class?, isPlayer? }. Unlisted units don't exist,
	-- except "player" (Nra, a warrior).
	units = {},
	party = {}, -- unit tokens of the other group members ("party1", ...)
	zone = "Elwynn Forest",
}

------------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------------

local Frame = {}

local function NewObject(kind)
	local object = setmetatable({ scripts = {}, shown = true, kind = kind, text = "", enabled = true }, Frame)
	table.insert(wow.frames, object)
	return object
end

local methods = {
	Show = function(self)
		local was = self.shown
		self.shown = true
		if not was and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end,
	Hide = function(self)
		local was = self.shown
		self.shown = false
		if was and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end,
	SetShown = function(self, shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end,
	IsShown = function(self)
		return self.shown
	end,
	IsVisible = function(self)
		return self.shown
	end,
	SetScript = function(self, name, fn)
		self.scripts[name] = fn
	end,
	GetScript = function(self, name)
		return self.scripts[name]
	end,
	-- Textures remember their file and alpha, for tests that look at them.
	SetTexture = function(self, file)
		rawset(self, "file", file)
	end,
	GetTexture = function(self)
		return rawget(self, "file")
	end,
	SetAlpha = function(self, alpha)
		rawset(self, "alpha", alpha)
	end,
	GetAlpha = function(self)
		return rawget(self, "alpha") or 1
	end,
	SetAttribute = function(self, name, value)
		rawset(self, "attributes", rawget(self, "attributes") or {})
		self.attributes[name] = value
	end,
	GetAttribute = function(self, name)
		return rawget(self, "attributes") and self.attributes[name]
	end,
	HookScript = function(self, name, fn)
		local old = self.scripts[name]
		self.scripts[name] = function(...)
			if old then
				old(...)
			end
			fn(...)
		end
	end,
	SetText = function(self, text)
		self.text = text
		if self.scripts.OnTextChanged then
			self.scripts.OnTextChanged(self, false)
		end
	end,
	GetText = function(self)
		return self.text
	end,
	SetEnabled = function(self, enabled)
		self.enabled = enabled and true or false
	end,
	Enable = function(self)
		self.enabled = true
	end,
	Disable = function(self)
		self.enabled = false
	end,
	IsEnabled = function(self)
		return self.enabled
	end,
	SetNumeric = function(self, numeric)
		rawset(self, "numeric", numeric)
		if numeric then
			rawset(self, "everNumeric", true)
		end
	end,
	SetChecked = function(self, checked)
		self.checked = checked and true or false
	end,
	GetChecked = function(self)
		return rawget(self, "checked") or false
	end,
	RegisterEvent = function(self, event)
		local events = rawget(self, "events") or {}
		rawset(self, "events", events)
		events[event] = true
	end,
	UnregisterEvent = function(self, event)
		local events = rawget(self, "events")
		if events then
			events[event] = nil
		end
	end,
	RegisterUnitEvent = function(self, event)
		local events = rawget(self, "events") or {}
		rawset(self, "events", events)
		events[event] = true
	end,
	SetWidth = function(self, width)
		rawset(self, "width", width)
	end,
	SetHeight = function(self, height)
		rawset(self, "height", height)
	end,
	SetSize = function(self, width, height)
		rawset(self, "width", width)
		rawset(self, "height", height)
	end,
	GetWidth = function(self)
		return rawget(self, "width") or 100
	end,
	GetHeight = function(self)
		return rawget(self, "height") or 100
	end,
	GetParent = function(self)
		return rawget(self, "parent")
	end,
	GetPoint = function()
		return "CENTER", nil, "CENTER", 0, 0
	end,
	-- Focus (edit boxes): remembered, so tests can check what has the keyboard.
	SetFocus = function(self)
		rawset(self, "focused", true)
	end,
	ClearFocus = function(self)
		rawset(self, "focused", false)
	end,
	HasFocus = function(self)
		return rawget(self, "focused") == true
	end,
	IsForbidden = function()
		return false
	end,
	IsMouseOver = function(self)
		return rawget(self, "mouseOver") == true
	end,
	-- Click areas (a checkbox widened over its label), for tests that check what covers what.
	SetHitRectInsets = function(self, left, right, top, bottom)
		rawset(self, "hitRect", { left, right, top, bottom })
	end,
	GetHitRectInsets = function(self)
		local insets = rawget(self, "hitRect") or { 0, 0, 0, 0 }
		return insets[1], insets[2], insets[3], insets[4]
	end,
	-- Roughly as wide as the game would draw it (6 pixels a letter).
	GetStringWidth = function(self)
		return #tostring(rawget(self, "text") or "") * 6
	end,
}

-- Method names start with a verb; other capitalised keys (NotificationOverlay, Items,
-- Text...) are child frames, created on first use.
local VERBS = { "Set", "Get", "Is", "Has", "Can", "Create", "Register", "Unregister", "Enable", "Disable",
	"Show", "Hide", "Clear", "Start", "Stop", "Hook", "Raise", "Lower", "Add", "Init", "Update", "Play",
	"Refresh", "Release", "Acquire", "Insert", "Remove", "Highlight", "Lock", "Unlock", "Trigger", "Layout",
	"Adjust", "Apply", "Reset", "Toggle", "Select", "Scroll", "Fade", "Click", "Open", "Close", "Mark",
	"Evaluate", "Load", "Save", "Should", "Generate", "Notify", "On", "Do", "Enumerate", "Find", "Use" }

local function IsMethodName(key)
	for _, verb in ipairs(VERBS) do
		if key:sub(1, #verb) == verb and (#key == #verb or key:sub(#verb + 1, #verb + 1):match("[A-Z]")) then
			return true
		end
	end
	return false
end

Frame.__index = function(self, key)
	-- Lowercase keys are plain fields: unset means nil.
	if type(key) ~= "string" or key:match("^[a-z_]") then
		return nil
	end
	if methods[key] then
		return methods[key]
	end
	if type(key) == "string" and key:match("^[A-Z]") and not IsMethodName(key) then
		local child = NewObject(key)
		rawset(self, key, child)
		return child
	end
	if key:match("^Create") then
		return function()
			return NewObject(key)
		end
	end
	if key:match("Width$") or key:match("Height$") or key:match("Scroll") or key:match("^GetFrameLevel")
		or key:match("Scale$") then
		return function()
			return 100
		end
	end
	return function() end
end

------------------------------------------------------------------------------
-- API namespaces: unknown functions return nil
------------------------------------------------------------------------------

local function Namespace(fields)
	return setmetatable(fields or {}, { __index = function()
		return function() end
	end })
end

local function FindItem(itemID)
	return wow.data.items[itemID]
end

function wow.install()
	local G = _G
	-- Any other WoW function (CamelCase global) does nothing and returns nil; constants
	-- (ALL_CAPS) stay nil. Tests add real stand-ins below where the result matters.
	wow.missing = {}
	-- Blizzard frames and mixins (names like QuestFrame..., OpenAllMail, LegacyMicroButton)
	-- become empty frames, created once.
	local FRAME_WORDS = { "Frame", "Button", "Container", "Panel", "Tooltip", "Mixin", "Mail", "Bar", "Box", "Bags" }
	setmetatable(G, { __index = function(_, name)
		if type(name) ~= "string" or not name:match("^[A-Z]") or not name:match("[a-z]") then
			return nil
		end
		wow.missing[name] = true
		for _, word in ipairs(FRAME_WORDS) do
			if name:find(word, 1, true) and not name:find("_") then
				local frame = NewObject(name)
				frame.shown = false -- Blizzard windows are closed at login
				rawset(G, name, frame)
				return frame
			end
		end
		return function() end
	end })
	G.CreateFrame = function(kind, name, parent, template)
		local frame = NewObject(kind)
		frame.template = template
		frame.parent = parent
		if kind == "CheckButton" then
			frame.Text = NewObject("FontString")
		end
		if name then
			G[name] = frame
		end
		return frame
	end
	G.UIParent = NewObject("UIParent")
	G.GameTooltip = NewObject("GameTooltip")
	G.GameFontNormalLarge = NewObject("Font") -- a font object some features copy their font from
	G.ItemRefTooltip = NewObject("ItemRefTooltip")
	G.UISpecialFrames = {}
	G.SlashCmdList = {}
	G.RAID_CLASS_COLORS = {}
	G.ITEM_QUALITY_COLORS = {}
	G.SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, UI_EPICLOOT_TOAST = 31578, UI_WORLDQUEST_COMPLETE = 73277, LOOT_WINDOW_COIN_SOUND = 120,
		UI_QUEST_ROLLING_FORWARD_01 = 3, IG_QUEST_LIST_COMPLETE = 878, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
		IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, MAP_PING = 3175,
		UI_RAID_BOSS_WHISPER_WARNING = 37666 }
	G.Enum = setmetatable({}, { __index = function(enums, name)
		local enum = setmetatable({}, { __index = function()
			return 1
		end })
		rawset(enums, name, enum)
		return enum
	end })
	G.MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = 1 }, Label = { Right = 2 } }
	for index, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
		G["FACTION_STANDING_LABEL" .. index] = label
	end
	G.LOOT_ITEM_SELF = "You receive loot: %s."
	G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	G.LOOT_ITEM_CREATED_SELF = "You create: %s."
	G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
	G.OPEN_ALL_MAIL_BUTTON = "Open All"
	-- Nothing attached to a mail being written (names with "Mail" would otherwise become frames).
	G.HasSendMailItem = function()
		return false
	end
	G.GetSendMailItem = function() end

	G.C_Timer = { After = function() end, NewTicker = function()
		return { Cancel = function() end }
	end }
	G.C_Item = Namespace({
		GetItemCount = function(itemID, includeBank)
			local item = FindItem(itemID)
			if not item then
				return 0
			end
			return item.bags + (includeBank and item.bank or 0)
		end,
		GetItemNameByID = function(itemID)
			local item = FindItem(itemID)
			return item and item.name
		end,
		GetItemInfoInstant = function(itemID)
			return itemID, "Trade Goods", "Cloth", "", 132903, 7
		end,
	})
	G.C_Reputation = Namespace({
		GetNumFactions = function()
			return #wow.data.factions
		end,
		GetFactionDataByIndex = function(index)
			return wow.data.factions[index]
		end,
		GetFactionDataByID = function(id)
			for _, faction in ipairs(wow.data.factions) do
				if faction.factionID == id then
					return faction
				end
			end
		end,
		GetWatchedFactionData = function()
			return { factionID = wow.data.watchedFaction }
		end,
	})
	G.C_SkillInfo = Namespace({
		GetNumSkillLines = function()
			return #wow.data.skills
		end,
		GetSkillLineInfo = function(index)
			return wow.data.skills[index]
		end,
		GetSkillLineInfoByID = function(id)
			for _, skill in ipairs(wow.data.skills) do
				if skill.skillID == id then
					return skill
				end
			end
		end,
	})
	G.C_CurrencyInfo = Namespace({
		GetCurrencyListSize = function()
			return #wow.data.currencies
		end,
		GetCurrencyListInfo = function(index)
			return wow.data.currencies[index]
		end,
		GetCurrencyListLink = function(index)
			local currency = wow.data.currencies[index]
			return currency and ("|Hcurrency:" .. currency.currencyID .. "|h[" .. currency.name .. "]|h")
		end,
		GetCurrencyInfo = function(id)
			for _, currency in ipairs(wow.data.currencies) do
				if currency.currencyID == id then
					return currency
				end
			end
		end,
	})
	for _, name in ipairs({ "C_Spell", "C_AddOns", "C_UnitAuras", "C_Container", "C_TooltipInfo", "C_Traits",
		"C_MajorFactions", "C_QuestLog", "C_NamePlate", "C_ClassTalents", "C_TradeSkillUI", "C_MountJournal",
		"C_Map", "C_VignetteInfo", "C_Engraving", "MenuUtil", "C_EventUtils", "C_PlayerInfo",
		"C_CatalogShop", "C_StorePublic", "C_CVar", "TooltipDataProcessor", "C_ChatInfo" }) do
		G[name] = Namespace()
	end
	G.TooltipDataProcessor.AllTypes = "ALL"
	-- UI panels (Blizzard's window manager): shown and hidden as asked, and remembered.
	wow.panels = {}
	G.RegisterUIPanel = function(frame, attributes)
		wow.panels[frame] = attributes
	end
	G.ShowUIPanel = function(frame)
		wow.panelShown = frame
		frame:Show()
	end
	G.HideUIPanel = function(frame)
		frame:Hide()
	end
	G.C_EventUtils.IsEventValid = function()
		return true
	end
	G.TooltipDataProcessor.AddTooltipPostCall = function(dataType, callback)
		table.insert(wow.tooltipCalls, { type = dataType, callback = callback })
	end
	G.C_QuestLog.GetNumQuestLogEntries = function()
		return 0 -- an empty quest log unless a test fills one in
	end
	G.C_Container.GetContainerNumSlots = function()
		return 0
	end
	G.C_NamePlate.GetNamePlates = function()
		return {}
	end
	G.C_VignetteInfo.GetVignettes = function()
		return {}
	end

	-- Blizzard settings: setting objects save into the addon's table and call back, like
	-- the real ones; everything else (categories, layouts, initializers) is inert.
	G.Settings = Namespace({
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function()
			return NewObject("Category"), NewObject("Layout")
		end,
		RegisterVerticalLayoutSubcategory = function()
			return NewObject("Category"), NewObject("Layout")
		end,
		RegisterCanvasLayoutSubcategory = function()
			return NewObject("Category")
		end,
		RegisterAddOnSetting = function(_, _, key, tbl, _, _, default)
			local setting = { key = key }
			if tbl[key] == nil then
				tbl[key] = default
			end
			function setting:GetValue()
				return tbl[key]
			end
			function setting:SetValue(value)
				if tbl[key] ~= value then
					tbl[key] = value
					if self.callback then
						self.callback(self, value)
					end
				end
			end
			function setting:SetValueChangedCallback(callback)
				self.callback = callback
			end
			return setting
		end,
		CreateCheckbox = function()
			return NewObject("Initializer")
		end,
		CreateSlider = function()
			return NewObject("Initializer")
		end,
		CreateDropdown = function()
			return NewObject("Initializer")
		end,
		CreateSliderOptions = function()
			return NewObject("SliderOptions")
		end,
		CreateControlTextContainer = function()
			local container = { data = {} }
			function container:Add(value, label)
				table.insert(self.data, { value = value, label = label })
			end
			function container:GetData()
				return self.data
			end
			return container
		end,
	})
	G.CreateSettingsListSectionHeaderInitializer = function()
		return NewObject("Initializer")
	end
	G.CreateSettingsButtonInitializer = function()
		return NewObject("Initializer")
	end
	G.ChatFrameUtil = { InsertLink = function() end }

	local function Unit(unit)
		return wow.data.units[unit]
	end
	G.UnitName = function(unit)
		local data = Unit(unit)
		if data then
			return data.name, data.surname
		end
		return "Nra"
	end
	G.UnitClass = function(unit)
		local data = Unit(unit)
		if data and data.class then
			return data.class, data.class:upper()
		end
		return "Warrior", "WARRIOR"
	end
	G.UnitExists = function(unit)
		return unit == "player" or Unit(unit) ~= nil
	end
	G.UnitIsPlayer = function(unit)
		local data = Unit(unit)
		return unit == "player" or (data ~= nil and data.isPlayer ~= false)
	end
	G.UnitGUID = function(unit)
		local data = Unit(unit)
		return data and data.guid
	end
	G.LE_PARTY_CATEGORY_HOME, G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
	G.IsInGroup = function(category)
		return category ~= G.LE_PARTY_CATEGORY_INSTANCE and #wow.data.party > 0
	end
	G.IsInRaid = function()
		return false
	end
	G.GetNumSubgroupMembers = function()
		return #wow.data.party
	end
	G.GetNumGroupMembers = function()
		return #wow.data.party > 0 and #wow.data.party + 1 or 0
	end
	G.GetRealZoneText = function()
		return wow.data.zone
	end
	wow.raidNotices = {}
	G.RaidNotice_AddMessage = function(_, text)
		table.insert(wow.raidNotices, text)
	end
	-- Unit popup menus: Menu.ModifyMenu callbacks by tag; wow.openMenu runs them.
	wow.menus = {}
	G.Menu = { ModifyMenu = function(tag, callback)
		wow.menus[tag] = wow.menus[tag] or {}
		table.insert(wow.menus[tag], callback)
	end }
	-- Tooltip post-calls by data type (TooltipDataProcessor.AddTooltipPostCall).
	wow.tooltipCalls = {}
	G.UnitLevel = function()
		return wow.data.level
	end
	G.UnitXP = function()
		return wow.data.xp
	end
	G.UnitXPMax = function()
		return wow.data.xpMax
	end
	G.GetMoney = function()
		return wow.data.money
	end
	G.GetNormalizedRealmName = function()
		return "Realm"
	end
	G.GetRealmName = G.GetNormalizedRealmName
	G.InCombatLockdown = function()
		return wow.data.inCombat == true
	end
	G.GetInboxNumItems = function()
		return 0
	end
	G.PlaySound = function(id)
		table.insert(wow.played, id)
	end
	G.PlaySoundFile = function(file)
		table.insert(wow.played, file)
	end
	G.GetTime = function()
		return wow.now or 1000
	end
	G.time = os.time
	G.date = os.date
	G.debugprofilestop = os.clock
	G.issecretvalue = function()
		return false
	end
	G.hooksecurefunc = function() end
	G.strtrim = function(text)
		return (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	G.strsplit = function(separator, text, limit)
		local parts, pattern = {}, "([^" .. separator:gsub("%p", "%%%0") .. "]*)"
		for part in (text .. separator):gmatch(pattern .. separator:gsub("%p", "%%%0")) do
			table.insert(parts, part)
		end
		if limit and #parts > limit then
			parts[limit] = table.concat(parts, separator, limit)
			for index = #parts, limit + 1, -1 do
				parts[index] = nil
			end
		end
		return (unpack or table.unpack)(parts)
	end
	G.strfind = string.find
	G.format = string.format
	G.tinsert = table.insert
	G.unpack = unpack or table.unpack
	G.wipe = function(t)
		for key in pairs(t) do
			t[key] = nil
		end
		return t
	end
	G.print = function(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[index] = tostring(select(index, ...))
		end
		table.insert(wow.printed, table.concat(parts, " "))
	end
	G.geterrorhandler = function()
		return function(message)
			table.insert(wow.errors, debug.traceback(tostring(message), 2))
		end
	end
	G.EventRegistry = NewObject("EventRegistry")
	G.GetCursorInfo = function()
		if wow.data.cursorItem then
			return "item", wow.data.cursorItem
		end
	end
	G.INVSLOT_FIRST_EQUIPPED, G.INVSLOT_LAST_EQUIPPED = 1, 19
	G.ATTACHMENTS_MAX_RECEIVE, G.ATTACHMENTS_MAX_SEND = 16, 12
	G.INBOXITEMS_TO_DISPLAY = 7
	G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
	G.MERCHANT_ITEMS_PER_PAGE, G.BUYBACK_ITEMS_PER_PAGE = 10, 12
	G.GetMouseFoci = function()
		return {}
	end
	G.LibStub = nil
	G.IsMacClient = function()
		return true
	end
	G.GameTooltip_Hide = function() end
	G.GameTooltip_SetTitle = function() end
	G.GameTooltip_AddNormalLine = function() end
	G.GameTooltip_AddInstructionLine = function() end
	G.BreakUpLargeNumbers = function(value)
		local text = tostring(math.floor(value))
		local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (result:gsub("^,", ""))
	end
end

------------------------------------------------------------------------------
-- Driving the UI
------------------------------------------------------------------------------

-- Sends an event to every frame registered for it (or every frame with OnEvent if
-- `all` is set, for ADDON_LOADED/PLAYER_LOGIN before registration matters).
function wow.fire(event, ...)
	for _, frame in ipairs(wow.frames) do
		local handler = frame.scripts.OnEvent
		local events = rawget(frame, "events")
		if handler and events and events[event] then
			handler(frame, event, ...)
		end
	end
end

local function TextOf(frame)
	local text = rawget(frame, "text")
	if type(text) == "table" then
		text = rawget(text, "text")
	end
	return text
end

-- Whether a frame and all its parents are shown.
function wow.visible(frame)
	while frame do
		if not frame.shown then
			return false
		end
		frame = rawget(frame, "parent")
	end
	return true
end

-- Clicks the visible button with this label. Returns false if there's none.
function wow.click(label, mouseButton)
	for _, frame in ipairs(wow.frames) do
		if frame.scripts.OnClick and wow.visible(frame) and TextOf(frame) == label then
			if frame.enabled == false then
				return false, "disabled"
			end
			frame.scripts.OnClick(frame, mouseButton or "LeftButton")
			return true
		end
	end
	return false, "not found"
end

-- Clicks a picker row (goals window) by the name of its entry.
function wow.clickEntry(name)
	for _, frame in ipairs(wow.frames) do
		local entry = rawget(frame, "entry")
		if frame.scripts.OnClick and type(entry) == "table" and entry.name == name then
			frame.scripts.OnClick(frame)
			return true
		end
	end
	return false
end

-- Types into the shown edit box created from a template (e.g. the goal amount box).
function wow.type(frame, text)
	frame.text = text
	if frame.scripts.OnTextChanged then
		frame.scripts.OnTextChanged(frame, true)
	end
end

function wow.findAll(predicate)
	local found = {}
	for _, frame in ipairs(wow.frames) do
		if predicate(frame) then
			table.insert(found, frame)
		end
	end
	return found
end


-- Moves the clock on and runs every shown frame's OnUpdate, like frames being drawn.
function wow.advance(seconds)
	wow.now = (wow.now or 1000) + seconds
	for _, frame in ipairs(wow.frames) do
		local onUpdate = frame.shown and frame.scripts.OnUpdate
		if onUpdate then
			onUpdate(frame, seconds)
		end
	end
end

-- Opens a unit popup menu (e.g. "MENU_UNIT_PLAYER") with contextData, running every
-- addon's Menu.ModifyMenu callback. Returns the entries: { text, onClick, entries,
-- isSelected, kind }. Find one with wow.menuEntry(entries, text).
-- A menu description that records what's added (like Blizzard's root description).
function wow.newMenu()
	local function Description()
		local description = { entries = {} }
		local function Add(kind, text, a, b)
			local entry = Description()
			entry.kind, entry.text = kind, text
			if kind == "radio" then
				entry.isSelected, entry.onClick = a, b
			else
				entry.onClick = a
			end
			table.insert(description.entries, entry)
			return entry
		end
		function description:SetEnabled(on) self.enabled = on end
		function description:SetTooltip(fn) self.tooltip = fn end
		function description:CreateDivider() return Add("divider") end
		function description:CreateTitle(text) return Add("title", text) end
		function description:CreateButton(text, onClick) return Add("button", text, onClick) end
		function description:CreateRadio(text, isSelected, onClick) return Add("radio", text, isSelected, onClick) end
		function description:CreateCheckbox(text, isSelected, onClick) return Add("checkbox", text, isSelected, onClick) end
		return description
	end
	return Description()
end

function wow.openMenu(tag, contextData)
	local root = wow.newMenu()
	for _, callback in ipairs(wow.menus[tag] or {}) do
		callback(nil, root, contextData)
	end
	return root.entries
end

function wow.menuEntry(entries, text)
	for _, entry in ipairs(entries) do
		if entry.text == text or (type(entry.text) == "string" and entry.text:find(text, 1, true)) then
			return entry
		end
	end
end

-- Builds the tooltip for a unit and returns its added lines.
function wow.unitTooltip(unit)
	local tooltip = NewObject("GameTooltip")
	local lines = {}
	rawset(tooltip, "lines", lines)
	rawset(tooltip, "GetUnit", function()
		return nil, unit
	end)
	rawset(tooltip, "AddLine", function(_, text)
		table.insert(lines, text)
	end)
	for _, call in ipairs(wow.tooltipCalls) do
		call.callback(tooltip, {})
	end
	return lines
end

-- The goal amount box: the edit box created for numbers (it takes text for money goals).
function wow.amountBox()
	for _, frame in ipairs(wow.frames) do
		if frame.template == "InputBoxTemplate" and rawget(frame, "everNumeric") then
			return frame
		end
	end
end

-- Ticks the checkbox whose label is `label` and fires its click.
function wow.tick(label)
	for _, frame in ipairs(wow.frames) do
		local text = rawget(frame, "Text")
		if frame.kind == "CheckButton" and frame.shown and text and rawget(text, "text") == label then
			frame:SetChecked(true)
			frame.scripts.OnClick(frame)
			return true
		end
	end
	return false
end

-- Drops an item (by ID) on the goal form's item slot.
function wow.dropItem(itemID)
	wow.data.cursorItem = itemID
	for _, frame in ipairs(wow.frames) do
		if frame.scripts.OnReceiveDrag then
			frame.scripts.OnReceiveDrag(frame)
		end
	end
	wow.data.cursorItem = nil
end

return wow
