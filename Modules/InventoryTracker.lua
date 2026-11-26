local _, ns = ...

-- Inventory Tracker: remembers what each of your characters has in their bags,
-- bank, mailbox and equipped, and lists it in item tooltips ("Bob: 12 (Bags 5,
-- Bank 7)"). Hovering your gold in the bags lists every character's gold (an option).
--
-- Bags and equipment are read whenever they change. The bank and the mailbox can
-- only be read while they're open, so each character has to visit them once; after
-- that they're kept up to date while open. Items you mail to your own characters
-- are added to their mail right away.
--
-- Characters are saved by full name, "Firstname Surname" (ns:PlayerName), since two of
-- them can share a first name. Older versions saved the first name alone; a character's
-- entry is moved to its full name when it logs in (if the class matches), and until
-- then mail to "Bob Stone" still finds the old "Bob".
--
-- Saved account-wide in NraKitDB.inventory[realm][name] =
--   { class = "MAGE", level = 42, money = copper,
--     bags = { [itemID] = count }, bank = {...}, mail = {...}, equipped = {...},
--     seen = { bags = time(), bank = time(), ... } }   -- when each location was last read
--
-- The inventory browser (InventoryBrowser.lua) shows the same data; see ns.inventory.

local module = {
	key = "inventoryTracker",
	section = "Bags & Items",
	name = "Inventory Tracker",
	description = "Item tooltips show how many of the item each of your characters has, and where (bags, bank, mail, equipped). Visit the bank and the mailbox once on each character so they're known. /nra inv opens a browser of every character's bags, bank and mail.",
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
			key = "inventoryTrackerMoney",
			name = "Gold on all characters",
			description = "Hovering your gold at the bottom of your bags lists the gold of each of your characters, and the total.",
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

-- "Bob Stone", "bob-stone" -> "bob stone".
local function NameKey(name)
	return (strtrim(name):gsub("%-", " "):gsub("%s+", " "):lower())
end

-- The stored name of a character: "Bob Stone" (any case, "Bob-Stone" too) finds "Bob Stone",
-- and a first name finds a character that's the only one with it (on either side: "Bob"
-- finds "Bob Stone", and "Bob Stone" finds an old entry saved as "Bob").
local function FindCharacter(characters, name)
	local key = NameKey(name)
	local first = key:match("^%S*")
	local byFirstName, count = nil, 0
	for storedName in pairs(characters or {}) do
		local storedKey = NameKey(storedName)
		if storedKey == key then
			return storedName
		end
		if storedKey:match("^%S*") == first and (storedKey == first or key == first) then
			byFirstName, count = storedName, count + 1
		end
	end
	return count == 1 and byFirstName or nil
end

-- Moves this character's entry from its first name (older versions) to its full name.
local function MoveToFullName(firstName, class)
	local characters = NraKitDB.inventory and NraKitDB.inventory[realm]
	local old = characters and characters[firstName]
	if firstName == playerName or not old or characters[playerName] then
		return
	end
	-- Another character with this first name may have saved it; theirs stays for them.
	if old.class == nil or old.class == class then
		characters[playerName] = old
		characters[firstName] = nil
	end
end

local function GetMe()
	local me = GetCharacter(realm, playerName)
	me.class = select(2, UnitClass("player"))
	me.level = math.max(me.level or 0, UnitLevel("player"))
	return me
end

-- Lets the browser refresh while it's open.
local function Changed()
	if ns.inventory.onChanged then
		ns.inventory.onChanged()
	end
end

-- Stores what was read at one location of this character.
local function Store(location, counts)
	local me = GetMe()
	me[location] = counts
	me.seen = me.seen or {}
	me.seen[location] = time()
	Changed()
end

local function StoreMoney()
	GetMe().money = GetMoney()
	Changed()
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
	Store(location, counts)
end

local function ScanEquipped()
	local counts = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			counts[itemID] = (counts[itemID] or 0) + 1
		end
	end
	Store("equipped", counts)
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
	Store("mail", counts)
end

-- Mail sent to one of your own characters: what was attached, until it's sent.
local pendingMail

local function OnSendMail(recipient)
	pendingMail = nil
	if not recipient or recipient == "" then
		return
	end
	-- No realms on Forever: a "-" in a name is the surname ("Bob-Stone").
	local storedName = FindCharacter(NraKitDB.inventory and NraKitDB.inventory[realm], recipient)
	if not storedName then
		return
	end
	local items = {}
	for attachment = 1, ATTACHMENTS_MAX_SEND do
		local _, itemID, _, count = GetSendMailItem(attachment)
		if itemID then
			items[itemID] = (items[itemID] or 0) + math.max(count or 1, 1)
		end
	end
	pendingMail = { realm = realm, name = storedName, items = items }
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
	Changed()
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

local function AddRealmLines(lines, realmName, characters, itemID, includeMe)
	for name, character in pairs(characters) do
		local isMe = realmName == realm and name == playerName
		if not isMe or includeMe or ns:GetOption("inventoryTrackerCurrent") then
			local total, where = Describe(character, itemID)
			if total then
				local label = realmName == realm and name or (name .. " (" .. realmName .. ")")
				table.insert(lines, { label = label, class = character.class, total = total, where = where, isMe = isMe })
			end
		end
	end
end

-- Every character with the item, you included (all realms if that's the option):
-- { { label, class, total, where, isMe }, ... }, you first, then by count.
local function Holders(itemID)
	local lines = {}
	if ns:GetOption("inventoryTrackerAllRealms") then
		for realmName, characters in pairs(NraKitDB.inventory or {}) do
			AddRealmLines(lines, realmName, characters, itemID, true)
		end
	elseif realm then
		AddRealmLines(lines, realm, GetRealmData(realm), itemID, true)
	end
	table.sort(lines, function(a, b)
		if a.isMe ~= b.isMe then
			return a.isMe
		end
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.label < b.label
	end)
	return lines
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
-- Your gold in the bags
---------------------------------------------------------------------------

local function MoneyText(copper)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Each character whose gold is known (you with what you have now): { label, class, money, isMe }.
local function MoneyLines()
	local lines = {}
	local function Add(realmName, characters)
		for name, character in pairs(characters) do
			local isMe = realmName == realm and name == playerName
			local money = isMe and GetMoney() or character.money
			if money then
				local label = realmName == realm and name or (name .. " (" .. realmName .. ")")
				table.insert(lines, { label = label, class = character.class, money = money, isMe = isMe })
			end
		end
	end
	if ns:GetOption("inventoryTrackerAllRealms") then
		for realmName, characters in pairs(NraKitDB.inventory or {}) do
			Add(realmName, characters)
		end
	else
		Add(realm, GetRealmData(realm))
	end
	-- You first, then the richest.
	table.sort(lines, function(a, b)
		if a.isMe ~= b.isMe then
			return a.isMe
		end
		if a.money ~= b.money then
			return a.money > b.money
		end
		return a.label < b.label
	end)
	return lines
end

local moneyTooltipOwner
local function OnMoneyEnter(button)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("inventoryTrackerMoney") or not realm then
		return
	end
	local lines = MoneyLines()
	GameTooltip:SetOwner(button, "ANCHOR_TOPRIGHT")
	GameTooltip_SetTitle(GameTooltip, "Gold on your characters")
	local sum = 0
	for _, line in ipairs(lines) do
		local r, g, b = ClassColor(line.class)
		GameTooltip:AddDoubleLine(line.label, MoneyText(line.money), r, g, b, 1, 1, 1)
		sum = sum + line.money
	end
	if #lines > 1 then
		GameTooltip:AddDoubleLine("Total", MoneyText(sum), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
	moneyTooltipOwner = button
end

local function OnMoneyLeave(button)
	if moneyTooltipOwner == button then
		moneyTooltipOwner = nil
		GameTooltip:Hide()
	end
end

-- The gold, silver and copper of the money at the bottom of the backpack and of the combined
-- bags (only watched: Blizzard's own scripts stay as they are).
local function HookBagMoney()
	for _, moneyFrame in ipairs({ ContainerFrame1MoneyFrame, ContainerFrameCombinedBags and ContainerFrameCombinedBags.MoneyFrame }) do
		for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
			local button = moneyFrame[key]
			if button and button.HookScript then
				button:HookScript("OnEnter", OnMoneyEnter)
				button:HookScript("OnLeave", OnMoneyLeave)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function ListCharacters()
	ns:Print("Tracked characters:")
	for realmName, characters in pairs(NraKitDB.inventory or {}) do
		for name in pairs(characters) do
			print("  " .. name .. (realmName == realm and "" or (" (" .. realmName .. ")")))
		end
	end
end

-- Removes a stored character; returns false if there's no such character.
local function ForgetCharacter(realmName, name)
	local characters = NraKitDB.inventory and NraKitDB.inventory[realmName]
	if not (characters and characters[name]) then
		return false
	end
	characters[name] = nil
	Changed()
	return true
end

local function Forget(argument)
	-- This realm first, then the others.
	local realms = { realm }
	for realmName in pairs(NraKitDB.inventory or {}) do
		if realmName ~= realm then
			table.insert(realms, realmName)
		end
	end
	for _, realmName in ipairs(realms) do
		local storedName = FindCharacter(NraKitDB.inventory and NraKitDB.inventory[realmName], argument)
		if storedName then
			ForgetCharacter(realmName, storedName)
			ns:Print("Forgot " .. storedName .. ".")
			if realmName == realm and storedName == playerName then
				ns:Print("That's you: your bags are tracked again on the next change.")
			end
			return
		end
	end
	ns:Print("No tracked character called " .. argument .. ". See /nra inv list.")
end

local function OnSlashCommand(input)
	local command, rest = input:match("^(%S*)%s*(.-)$")
	command = command:lower()
	if command == "forget" and rest ~= "" then
		Forget(rest)
	elseif command == "list" then
		ListCharacters()
		print("  /nra inv forget <first name> <surname> - remove a character (e.g. a deleted one)")
	elseif not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Inventory Tracker first (/nra).")
	else
		ns:OpenInventoryBrowser()
	end
end

-- For the browser.
ns.inventory = {
	LOCATIONS = LOCATIONS,
	LOCATION_LABELS = LOCATION_LABELS,
	GetRealm = function()
		return realm
	end,
	GetPlayer = function()
		return playerName
	end,
	Forget = ForgetCharacter,
	ClassColor = ClassColor,
	Holders = Holders,
}

ns:AddOptionsButton(module.key, "Browse inventories", "Open the browser of every character's bags, bank, mail and equipped items (/nra inv).", function()
	ns:OpenInventoryBrowser()
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
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
	elseif event == "PLAYER_MONEY" then
		StoreMoney()
	elseif event == "PLAYER_LEVEL_UP" then
		GetMe().level = ... -- UnitLevel can still say the old level here
		Changed()
	end
end)

local EVENTS = {
	"BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"PLAYERREAGENTBANKSLOTS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "MAIL_INBOX_UPDATE",
	"MAIL_SEND_SUCCESS", "MAIL_FAILED", "PLAYER_MONEY", "PLAYER_LEVEL_UP",
}

local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

function module:OnInitialize()
	realm = GetNormalizedRealmName() or GetRealmName():gsub("[%s%-']", "")
	playerName = ns:PlayerName()
	MoveToFullName(UnitName("player"), select(2, UnitClass("player")))
	local help = {
		summary = "Inventory browser: every character's bags, bank, mail and equipped items",
		usage = {
			"/nra inv - open the inventory browser (also /nra bank, /nra inventory)",
			"/nra inv list - list the tracked characters in chat",
			"/nra inv forget <first name> <surname> - remove a character (e.g. a deleted one); also right-click it in the browser",
		},
	}
	ns:RegisterSlashCommand("inv", OnSlashCommand, help)
	ns:RegisterSlashCommand("inventory", OnSlashCommand, help)
	ns:RegisterSlashCommand("bank", OnSlashCommand, help)
	hooksecurefunc("SendMail", function(recipient)
		if ns:IsModuleEnabled(module.key) then
			OnSendMail(recipient)
		end
	end)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	HookBagMoney()
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
		StoreMoney()
	end
	bankOpen = false
end

ns:RegisterModule(module)
