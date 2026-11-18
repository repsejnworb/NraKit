local _, ns = ...

-- Inventory Tracker: remembers what each of your characters has in their bags,
-- bank, mailbox and equipped, and lists it in item tooltips ("Bob: 12 (Bags 5,
-- Bank 7)").
--
-- Bags and equipment are read whenever they change. The bank and the mailbox can
-- only be read while they're open, so each character has to visit them once; after
-- that they're kept up to date while open. Items you mail to your own characters
-- (same realm) are added to their mail right away.
--
-- Saved account-wide in NraKitDB.inventory[realm][name] =
--   { class = "MAGE", bags = { [itemID] = count }, bank = {...}, mail = {...}, equipped = {...} }

local module = {
	key = "inventoryTracker",
	section = "Bags & Items",
	name = "Inventory Tracker",
	description = "Item tooltips show how many of the item each of your characters has, and where (bags, bank, mail, equipped). Visit the bank and the mailbox once on each character so they're known. /nra inv lists tracked characters; /nra inv forget <name> removes one.",
	default = false,
	options = {
		{
			key = "inventoryTrackerCurrent",
			header = "Tooltip",
			name = "Include this character",
			description = "Also list the character you're playing.",
			default = true,
		},
		{
			key = "inventoryTrackerEquipped",
			name = "Count equipped items",
			description = "Count items your characters are wearing.",
			default = true,
		},
		{
			key = "inventoryTrackerTotal",
			name = "Show a total",
			description = "Add a total line when more than one character has the item.",
			default = true,
		},
		{
			key = "inventoryTrackerAllRealms",
			name = "Characters on all realms",
			description = "List characters on other realms too, not just this one.",
			default = false,
		},
	},
}

local LOCATIONS = { "bags", "bank", "mail", "equipped" }
local LOCATION_LABELS = { bags = "Bags", bank = "Bank", mail = "Mail", equipped = "Equipped" }

local realm, playerName
local bankOpen = false

-- Bag index -> "bags" or "bank", from the names in Enum.BagIndex (they differ
-- between clients). The warband bank is shared, not a character's, so it's left out,
-- and so are the "all tabs" indexes, which would count the tabs twice.
local BAG_LOCATIONS = {}
for name, index in pairs(Enum.BagIndex or {}) do
	local lower = name:lower()
	if lower:find("account") or lower == "characterbanktab" then
		-- skip
	elseif lower:find("bank") then
		BAG_LOCATIONS[index] = "bank"
	elseif not BAG_LOCATIONS[index]
		and (lower == "backpack" or lower:find("^bag_") or lower == "reagentbag" or lower == "keyring") then
		BAG_LOCATIONS[index] = "bags"
	end
end

local function GetRealmData(realmName)
	NraKitDB.inventory = NraKitDB.inventory or {}
	NraKitDB.inventory[realmName] = NraKitDB.inventory[realmName] or {}
	return NraKitDB.inventory[realmName]
end

local function GetCharacter(realmName, name)
	local characters = GetRealmData(realmName)
	characters[name] = characters[name] or {}
	return characters[name]
end

local function GetMe()
	local me = GetCharacter(realm, playerName)
	me.class = select(2, UnitClass("player"))
	return me
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

local function ScanBags(location)
	local counts = {}
	for bag, bagLocation in pairs(BAG_LOCATIONS) do
		if bagLocation == location then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					counts[info.itemID] = (counts[info.itemID] or 0) + math.max(info.stackCount or 1, 1)
				end
			end
		end
	end
	GetMe()[location] = counts
end

local function ScanEquipped()
	local counts = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			counts[itemID] = (counts[itemID] or 0) + 1
		end
	end
	GetMe().equipped = counts
end

local function ScanMail()
	local counts = {}
	for index = 1, GetInboxNumItems() do
		local itemCount = select(8, GetInboxHeaderInfo(index))
		if itemCount and itemCount > 0 then
			for attachment = 1, ATTACHMENTS_MAX_RECEIVE do
				local _, itemID, _, count = GetInboxItem(index, attachment)
				if itemID then
					counts[itemID] = (counts[itemID] or 0) + math.max(count or 1, 1)
				end
			end
		end
	end
	GetMe().mail = counts
end

-- Mail sent to one of your own characters: what was attached, until it's sent.
local pendingMail

local function OnSendMail(recipient)
	pendingMail = nil
	if not recipient or recipient == "" then
		return
	end
	local name, recipientRealm = strsplit("-", recipient, 2)
	recipientRealm = recipientRealm and recipientRealm:gsub("[%s%-']", "") or realm
	local characters = NraKitDB.inventory and NraKitDB.inventory[recipientRealm]
	-- Names are stored as the game gives them (capitalised); match case-insensitively.
	local lowerName = name:lower()
	for storedName in pairs(characters or {}) do
		if storedName:lower() == lowerName then
			local items = {}
			for attachment = 1, ATTACHMENTS_MAX_SEND do
				local _, itemID, _, count = GetSendMailItem(attachment)
				if itemID then
					items[itemID] = (items[itemID] or 0) + math.max(count or 1, 1)
				end
			end
			pendingMail = { realm = recipientRealm, name = storedName, items = items }
			return
		end
	end
end

local function OnMailSent()
	if not pendingMail then
		return
	end
	local character = GetCharacter(pendingMail.realm, pendingMail.name)
	character.mail = character.mail or {}
	for itemID, count in pairs(pendingMail.items) do
		character.mail[itemID] = (character.mail[itemID] or 0) + count
	end
	pendingMail = nil
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Returns the total and "Bags 5, Bank 7" for one character, or nil.
local function Describe(character, itemID)
	local total, parts = 0, {}
	for _, location in ipairs(LOCATIONS) do
		local count = character[location] and character[location][itemID]
		if count and (location ~= "equipped" or ns:GetOption("inventoryTrackerEquipped")) then
			total = total + count
			table.insert(parts, LOCATION_LABELS[location] .. " " .. count)
		end
	end
	if total == 0 then
		return nil
	end
	return total, table.concat(parts, ", ")
end

local function AddRealmLines(lines, realmName, characters, itemID)
	for name, character in pairs(characters) do
		local isMe = realmName == realm and name == playerName
		if not isMe or ns:GetOption("inventoryTrackerCurrent") then
			local total, where = Describe(character, itemID)
			if total then
				local label = realmName == realm and name or (name .. "-" .. realmName)
				table.insert(lines, { label = label, class = character.class, total = total, where = where, isMe = isMe })
			end
		end
	end
end

local function OnItemTooltip(tooltip, data)
	if not ns:IsModuleEnabled(module.key) or not realm then
		return
	end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local itemID = data and data.id
	if not itemID or (issecretvalue and issecretvalue(itemID)) then
		return
	end

	local lines = {}
	if ns:GetOption("inventoryTrackerAllRealms") then
		for realmName, characters in pairs(NraKitDB.inventory or {}) do
			AddRealmLines(lines, realmName, characters, itemID)
		end
	else
		AddRealmLines(lines, realm, GetRealmData(realm), itemID)
	end
	if #lines == 0 then
		return
	end
	-- You first, then the others by count.
	table.sort(lines, function(a, b)
		if a.isMe ~= b.isMe then
			return a.isMe
		end
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.label < b.label
	end)

	tooltip:AddLine(" ")
	local sum = 0
	for _, line in ipairs(lines) do
		local r, g, b = ClassColor(line.class)
		tooltip:AddDoubleLine(line.label, string.format("%d (%s)", line.total, line.where), r, g, b, 1, 1, 1)
		sum = sum + line.total
	end
	if #lines > 1 and ns:GetOption("inventoryTrackerTotal") then
		tooltip:AddDoubleLine("Total", tostring(sum), 1, 0.82, 0, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function ListCharacters()
	ns:Print("Tracked characters:")
	for realmName, characters in pairs(NraKitDB.inventory or {}) do
		for name in pairs(characters) do
			print("  " .. name .. "-" .. realmName)
		end
	end
end

local function Forget(argument)
	local name, realmName = strsplit("-", argument, 2)
	realmName = realmName or realm
	local characters = NraKitDB.inventory and NraKitDB.inventory[realmName]
	for storedName in pairs(characters or {}) do
		if storedName:lower() == name:lower() then
			characters[storedName] = nil
			ns:Print("Forgot " .. storedName .. "-" .. realmName .. ".")
			if realmName == realm and storedName == playerName then
				ns:Print("That's you: your bags are tracked again on the next change.")
			end
			return
		end
	end
	ns:Print("No tracked character called " .. argument .. ". See /nra inv.")
end

local function OnSlashCommand(input)
	local command, rest = input:match("^(%S*)%s*(.-)$")
	if command:lower() == "forget" and rest ~= "" then
		Forget(rest)
	else
		ListCharacters()
		print("  /nra inv forget <name> - remove a character (e.g. a deleted one)")
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "BAG_UPDATE_DELAYED" then
		ScanBags("bags")
		if bankOpen then
			ScanBags("bank")
		end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		ScanBags("bank")
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERREAGENTBANKSLOTS_CHANGED" then
		if bankOpen then
			ScanBags("bank")
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		ScanEquipped()
	elseif event == "MAIL_INBOX_UPDATE" then
		ScanMail()
	elseif event == "MAIL_SEND_SUCCESS" then
		OnMailSent()
	elseif event == "MAIL_FAILED" then
		pendingMail = nil
	end
end)

local EVENTS = {
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"PLAYERREAGENTBANKSLOTS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "MAIL_INBOX_UPDATE",
	"MAIL_SEND_SUCCESS", "MAIL_FAILED",
}

local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

function module:OnInitialize()
	realm = GetNormalizedRealmName() or GetRealmName():gsub("[%s%-']", "")
	playerName = UnitName("player")
	ns:RegisterSlashCommand("inv", OnSlashCommand)
	ns:RegisterSlashCommand("inventory", OnSlashCommand)
	hooksecurefunc("SendMail", function(recipient)
		if ns:IsModuleEnabled(module.key) then
			OnSendMail(recipient)
		end
	end)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if IsEventValid(event) then
			if enabled then
				eventFrame:RegisterEvent(event)
			else
				eventFrame:UnregisterEvent(event)
			end
		end
	end
	if enabled then
		ScanBags("bags")
		ScanEquipped()
	end
	bankOpen = false
end

ns:RegisterModule(module)
