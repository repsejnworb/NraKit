local _, ns = ...

-- Shortcuts: short slash commands for NraKit's everyday /nra commands (/goal = /nra goal).
-- Only ones nobody else has: a shortcut another addon, Blizzard or an emote already uses is
-- left alone (/nra still works), so NraKit never takes a command from anyone.
--
-- How the game finds a command: whenever one is typed, it first moves every newly registered
-- command (SlashCmdList.X with SLASH_X1..n) into its lookup tables: hash_SlashCmdList (the
-- command -> its function) and hash_ChatTypeInfoList (every command, Blizzard's too -> its
-- owner's key); registrations it has moved stay readable through SlashCmdList's metatable.
-- When two register the same command, the one moved last wins.
--
-- So: a few seconds after entering the world (addons register at load, at login or just
-- after), each free shortcut is registered. An addon that loads later and registers the same
-- command is moved after ours and wins by itself; if it lands in the same move and ours still
-- runs, ours hands the command on to it. A shortcut turned off (or its feature) is taken
-- out of the lookup tables again, as Blizzard's comments say addons do.

local module = {
	key = "shortcuts",
	section = "Tools",
	name = "Shortcuts",
	description = "Short commands for NraKit's everyday ones: /remind for /nra remind, /goal for /nra goal and so on. Only ones no other addon (or the game) uses: those are left alone, and /nra always works. /nra shortcuts lists them and which are in use elsewhere.",
	default = false,
	options = {},
}

-- { command, the /nra command it runs, the feature it needs (nil: always there) }
local SHORTCUTS = {
	{ "remind", "remind", "reminders" },
	{ "todo", "todo", "reminders" },
	{ "item", "item", "itemLookup" },
	{ "dps", "dps", nil },
	{ "shop", "shop", "auctionatorPrices" },
	{ "bank", "bank", "inventoryTracker" },
	{ "goal", "goal", "farmGoals" },
	{ "note", "note", "playerNotes" },
	{ "wish", "wish", "wishlist" },
	{ "scan", "scan", "unitScanner" },
	{ "done", "done", "turnInQuests" },
}
local CLAIM_DELAY = 3 -- seconds after entering the world

local shortcuts = {}
ns.shortcuts = shortcuts

local KEY_PREFIX = "NRAKITSHORTCUT_"

local function OptionKey(command)
	return "shortcut" .. command:sub(1, 1):upper() .. command:sub(2)
end

for _, entry in ipairs(SHORTCUTS) do
	local command, nra, feature = entry[1], entry[2], entry[3]
	table.insert(module.options, {
		key = OptionKey(command),
		name = "/" .. command,
		description = "Same as /nra " .. nra .. "." .. (feature and " Only while its feature is on." or ""),
		default = true,
		requires = feature,
	})
end

local claimed = {} -- command -> true while registered by us
local ready = false -- the claim delay after entering the world has passed

-- Who else has a command ("/GOAL"): an owner key, "emote", or nil if nobody.
function shortcuts.Owner(command)
	local tag = ("/" .. command):upper()
	local ours = KEY_PREFIX .. command:upper()
	if type(hash_ChatTypeInfoList) == "table" then
		local owner = hash_ChatTypeInfoList[tag]
		if owner and owner ~= ours then
			return owner
		end
	end
	if type(hash_EmoteTokenList) == "table" and hash_EmoteTokenList[tag] then
		return "emote"
	end
	-- Registrations not moved into the lookup tables yet, and those that were (the metatable).
	local lists = { SlashCmdList }
	local meta = getmetatable(SlashCmdList)
	if meta and type(meta.__index) == "table" then
		table.insert(lists, meta.__index)
	end
	for _, list in ipairs(lists) do
		for key in pairs(list) do
			if key ~= ours then
				local i = 1
				local each = _G["SLASH_" .. key .. i]
				while each do
					if type(each) == "string" and each:upper() == tag then
						return key
					end
					i = i + 1
					each = _G["SLASH_" .. key .. i]
				end
			end
		end
	end
	return nil
end

-- Another addon's function for a command, to hand it on to.
local function OtherHandler(owner)
	local handler = rawget(SlashCmdList, owner)
	local meta = getmetatable(SlashCmdList)
	if not handler and meta and type(meta.__index) == "table" then
		handler = meta.__index[owner]
	end
	return type(handler) == "function" and handler or nil
end

local function Wanted(entry)
	local feature = entry[3]
	return ready and ns:IsModuleEnabled(module.key) and ns:GetOption(OptionKey(entry[1]))
		and (not feature or ns:IsModuleEnabled(feature))
end

local function Claim(entry)
	local command, nra = entry[1], entry[2]
	local key = KEY_PREFIX .. command:upper()
	_G["SLASH_" .. key .. "1"] = "/" .. command
	SlashCmdList[key] = function(input, editBox)
		-- Someone registered it since: theirs, not ours.
		local owner = shortcuts.Owner(command)
		local other = owner and OtherHandler(owner)
		if other then
			other(input, editBox)
			return
		end
		ns:RunSlashCommand(nra .. (input ~= "" and (" " .. input) or ""))
	end
	claimed[command] = true
end

local function Release(command)
	local key = KEY_PREFIX .. command:upper()
	local tag = ("/" .. command):upper()
	SlashCmdList[key] = nil
	local meta = getmetatable(SlashCmdList)
	if meta and type(meta.__index) == "table" then
		meta.__index[key] = nil
	end
	_G["SLASH_" .. key .. "1"] = nil
	if type(hash_ChatTypeInfoList) == "table" and hash_ChatTypeInfoList[tag] == key then
		hash_ChatTypeInfoList[tag] = nil
		if type(hash_SlashCmdList) == "table" then
			hash_SlashCmdList[tag] = nil
		end
	end
	claimed[command] = nil
end

-- Registers the shortcuts that are wanted and free; takes back the ones no longer wanted.
function shortcuts.Update()
	for _, entry in ipairs(SHORTCUTS) do
		local command = entry[1]
		if Wanted(entry) then
			if not claimed[command] and not shortcuts.Owner(command) then
				Claim(entry)
			end
		elseif claimed[command] then
			Release(command)
		end
	end
end

-- A shortcut's state: "active", "taken" (with its owner), "feature off" or "off".
function shortcuts.State(command)
	for _, entry in ipairs(SHORTCUTS) do
		if entry[1] == command then
			if claimed[command] then
				return "active"
			end
			local owner = shortcuts.Owner(command)
			if owner then
				return "taken", owner
			end
			if entry[3] and not ns:IsModuleEnabled(entry[3]) then
				return "feature off"
			end
			return "off"
		end
	end
end

local function ListShortcuts()
	ns:Print(ns:IsModuleEnabled(module.key) and "shortcuts:" or "shortcuts (turned off; turn Shortcuts on in /nra):")
	for _, entry in ipairs(SHORTCUTS) do
		local command, nra = entry[1], entry[2]
		local state, owner = shortcuts.State(command)
		local text
		if state == "active" then
			text = "|cff4cff4cactive|r"
		elseif state == "taken" then
			text = "|cffffd100in use by " .. (owner == "emote" and "an emote" or owner) .. "|r (/nra " .. nra .. " still works)"
		elseif state == "feature off" then
			text = "|cff808080its feature is off|r"
		else
			text = "|cff808080off|r"
		end
		print(string.format("  |cffffd100/%s|r = /nra %s: %s", command, nra, text))
	end
end

-- The claim delay: a frame that counts once after entering the world, then hides.
local waiter = CreateFrame("Frame")
waiter:Hide()
waiter:SetScript("OnUpdate", function(self, elapsed)
	self.left = self.left - elapsed
	if self.left <= 0 then
		self:Hide()
		ready = true
		shortcuts.Update()
	end
end)
waiter:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if not ready then
		self.left = CLAIM_DELAY
		self:Show()
	end
end)
waiter:RegisterEvent("PLAYER_ENTERING_WORLD")

function module:OnInitialize()
	ns:RegisterSlashCommand("shortcuts", ListShortcuts, {
		summary = "List the short commands (/goal, /remind, ...) and which are in use by other addons",
		usage = { "/nra shortcuts - list them" },
	})
	-- A feature turned on or off adds or takes back its shortcut.
	table.insert(ns.moduleToggledCallbacks, function()
		shortcuts.Update()
	end)
end

function module:OnEnabledChanged()
	shortcuts.Update()
end

function module:OnOptionChanged()
	shortcuts.Update()
end

ns:RegisterModule(module)
