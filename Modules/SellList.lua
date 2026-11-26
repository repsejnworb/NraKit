local _, ns = ...

-- Sell List: what in your bags is worth selling, most valuable first, so you don't have to
-- hover every item. A tab in the NraKit window (SellListWindow.lua), opened from a button on
-- the auction house (NraKit's window then docks beside it), from the Inventory tab, or with
-- /nra sell.
--
-- Each item is priced at the auction house (Auctionator's last scan, with how old that is)
-- and at a vendor; the better of the two is its value. Without Auctionator it's vendor
-- prices only. Groups, by where each item sells best:
--   To Sell: Auction House   tradeable items the auction house pays more for
--   To Sell: Vendor          the rest, soulbound ones too (folded at the auction house)
--   Kept                     items you marked "Keep, don't list" (potions, food...), folded
-- Your bank and mail can be listed too (switches at the top): mixed in, marked, not clickable.
-- It can also open at merchants (an option), docked beside them, vendor group first.
--
-- Saved: NraKitDB.sellListKept = { [itemID] = true }, sellListSort = { key, ascending },
-- sellListOpen = { [group] = true/false } (folded or not).

local module = {
	key = "sellList",
	section = "Auction House",
	name = "Sell List",
	description = "What in your bags is worth selling, most valuable first: auction house prices (from Auctionator, if you have it) and vendor prices, side by side. A button on the auction house opens it beside it; also in the Inventory tab and with /nra sell.",
	default = false,
	options = {
		{
			key = "sellListMinValue",
			type = "number",
			name = "Leave out items worth less than",
			description = "Items worth less than this (the whole stack, at the auction house or a vendor, whichever is more) aren't listed, so grey junk doesn't crowd the list.",
			default = 5,
			min = 0,
			max = 500,
			step = 5,
			format = function(value)
				if value == 0 then
					return "list everything"
				end
				return value >= 100 and string.format("%gg", value / 100) or (value .. "s")
			end,
		},
		{
			key = "sellListBags",
			name = "Show your bags",
			description = "List what's in your bags (the Bags switch at the top of the list). At the bank or mailbox they're hidden, to see what to take out; click Bags there to show them for that visit.",
			default = true,
		},
		{
			key = "sellListBank",
			name = "Show your bank",
			description = "Also list what's in your bank (as Inventory Tracker last saw it), marked, so you know what to take out before you sell. The same as the Bank switch at the top of the list.",
			default = false,
			requires = "inventoryTracker",
		},
		{
			key = "sellListMail",
			name = "Show your mail",
			description = "Also list what's waiting in your mailbox (as Inventory Tracker last saw it, with what you've bought at the auction house since), marked. The same as the Mail switch at the top of the list.",
			default = false,
			requires = "inventoryTracker",
		},
		{
			key = "sellListAutoOpen",
			header = "Automatically Open At (This Character)",
			name = "The auction house",
			description = "The Sell List opens by itself beside the auction house when you open it. Per character (also in the list's \"Automatically Open At\" menu).",
			default = true,
		},
		{
			key = "sellListMerchantOpen",
			name = "Merchants",
			description = "The Sell List opens by itself beside a merchant's window, with what sells best to a vendor first. Click an item, then click the merchant's window to sell it. Per character.",
			default = false,
		},
		{
			key = "sellListBankOpen",
			name = "The bank",
			description = "The Sell List opens by itself beside your bank, with what's in it listed to take out. Per character (say, your bank alt).",
			default = false,
		},
		{
			key = "sellListMailOpen",
			name = "The mailbox",
			description = "The Sell List opens by itself beside the mailbox, with what's in your mail listed to take. Per character.",
			default = false,
		},
		{
			key = "sellListAHButton",
			header = "Buttons and Docking",
			name = "Button on the auction house",
			description = "A \"NraKit Sell List\" button at the top of the auction house window.",
			default = true,
		},
		{
			key = "sellListPlaceButtons",
			name = "Buttons on the bank and mailbox",
			description = "A \"NraKit Sell List\" button at the top of the bank and mailbox windows: the list opens beside them, to take what's worth selling.",
			default = true,
		},
		{
			key = "sellListDock",
			name = "Open beside the auction house, bank or mailbox",
			description = "There, the list opens right next to its window instead of where NraKit's windows usually are.",
			default = true,
		},
	},
}

local CALLER = "NraKit"
local STALE_DAYS = 3 -- an auction price older than this is dimmed

local sell = { STALE_DAYS = STALE_DAYS }
local Changed
ns.sellList = sell

local auctionHouseOpen = false
local merchantOpen = false
local placeOpen = { bank = false, mail = false } -- at the bank, at the mailbox

function sell.IsAuctionHouseOpen()
	return auctionHouseOpen
end

function sell.IsMerchantOpen()
	return merchantOpen
end

-- The window that says you're at the bank or the mailbox.
local PLACE_FRAMES = { bank = "BankFrame", mail = "MailFrame" }

-- Whether you're at the bank or the mailbox ("bank", "mail"): then it's read live and you
-- can take from it. Its window being shown is what counts: on Forever the mailbox opens and
-- closes through the player interaction system, and MAIL_CLOSED can't be relied on.
function sell.IsPlaceOpen(where)
	local frame = _G[PLACE_FRAMES[where]]
	return placeOpen[where] == true and type(frame) == "table" and frame:IsShown() == true
end

local function API()
	return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
end

function sell.HasAuctionator()
	return API() ~= nil
end

local function Kept()
	NraKitDB.sellListKept = NraKitDB.sellListKept or {}
	return NraKitDB.sellListKept
end

function sell.IsKept(itemID)
	return Kept()[itemID] == true
end

function sell.SetKept(itemID, kept)
	Kept()[itemID] = kept or nil
	if sell.onChanged then
		sell.onChanged()
	end
end

function sell.KeptCount()
	local count = 0
	for _ in pairs(Kept()) do
		count = count + 1
	end
	return count
end

-- Auction price of one, and how many days old Auctionator's scan of it is (nil if unknown).
-- Gear goes by its link (the same item can differ), the rest by ID.
function sell.AuctionPrice(itemID, link)
	local api = API()
	if not api then
		return nil
	end
	local price, age
	if link and api.GetAuctionPriceByItemLink then
		price = api.GetAuctionPriceByItemLink(CALLER, link)
		age = api.GetAuctionAgeByItemLink and api.GetAuctionAgeByItemLink(CALLER, link)
	end
	if not price then
		price = api.GetAuctionPriceByItemID(CALLER, itemID)
		age = api.GetAuctionAgeByItemID and api.GetAuctionAgeByItemID(CALLER, itemID)
	end
	return price, age
end

function sell.DisenchantPrice(link)
	local api = API()
	return api and link and api.GetDisenchantPriceByItemLink and api.GetDisenchantPriceByItemLink(CALLER, link) or nil
end

-- Prices an item { id, link, count }: fills name, quality, icon, each (auction), age, ahTotal,
-- vendorEach, vendorTotal, value (the better), best ("ah" or "vendor"), disenchant. Returns
-- false while the client hasn't loaded the item yet.
local function Price(item)
	local name, _, quality, _, _, _, _, _, equipLoc, icon, vendorEach, _, _, bindType = C_Item.GetItemInfo(item.link or item.id)
	if not name then
		C_Item.RequestLoadItemDataByID(item.id)
		return false
	end
	item.name, item.quality, item.icon = name, item.quality or quality, item.icon or icon
	item.bindType = bindType
	item.vendorEach = vendorEach or 0
	item.vendorTotal = item.vendorEach * item.count
	item.each, item.age = sell.AuctionPrice(item.id, item.link)
	item.ahTotal = item.each and item.each * item.count or nil
	if (item.ahTotal or 0) > item.vendorTotal then
		item.value, item.best = item.ahTotal, "ah"
	else
		item.value, item.best = item.vendorTotal, "vendor"
	end
	if not item.each and equipLoc and equipLoc ~= "" then
		item.disenchant = sell.DisenchantPrice(item.link)
	end
	return true
end

-- What's in your bags, one entry per item (gear per link, since two of one item can differ):
-- { id, link, count, bound, bag, slot }. A stack that isn't soulbound makes the item sellable.
local function BagItems()
	local byKey, items = {}, {}
	for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local gear = C_Item.IsEquippableItem and C_Item.IsEquippableItem(info.itemID)
				local key = gear and info.hyperlink or info.itemID
				local item = byKey[key]
				if not item then
					item = { id = info.itemID, link = info.hyperlink, count = 0, bound = true, bag = bag, slot = slot,
						icon = info.iconFileID, quality = info.quality }
					byKey[key] = item
					table.insert(items, item)
				end
				item.count = item.count + math.max(info.stackCount or 1, 1)
				item.bound = item.bound and info.isBound == true
			end
		end
	end
	return items
end

-- Your saved inventory (Inventory Tracker's data), or nil.
local function MyInventory()
	local inventory = ns.inventory
	local realm = inventory and inventory.GetRealm()
	return realm and NraKitDB.inventory and NraKitDB.inventory[realm] and NraKitDB.inventory[realm][inventory.GetPlayer()]
end

-- Your bank, read live (you're at it): one entry per item (gear per link), with every slot
-- it's in: { id, link, count, bound, where = "bank", slots = { { bag, slot, count } } }.
local function LiveBankItems()
	local byKey, items = {}, {}
	for _, bag in ipairs(ns.inventory and ns.inventory.BagsAt("bank") or {}) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local gear = C_Item.IsEquippableItem and C_Item.IsEquippableItem(info.itemID)
				local key = gear and info.hyperlink or info.itemID
				local item = byKey[key]
				if not item then
					item = { id = info.itemID, link = info.hyperlink, count = 0, bound = true, where = "bank", slots = {},
						icon = info.iconFileID, quality = info.quality }
					byKey[key] = item
					table.insert(items, item)
				end
				local count = math.max(info.stackCount or 1, 1)
				item.count = item.count + count
				item.bound = item.bound and info.isBound == true
				table.insert(item.slots, { bag = bag, slot = slot, count = count })
			end
		end
	end
	return items
end

-- Your mail, read live (you're at the mailbox): one entry per item, with every attachment it's
-- in: { id, link, count, where = "mail", attachments = { { mail, attachment, count } } }.
-- C.O.D. mail is left out: it isn't yours until you pay.
local function LiveMailItems()
	local byKey, items = {}, {}
	for mail = 1, GetInboxNumItems() do
		local _, _, _, _, _, cod, _, itemCount = GetInboxHeaderInfo(mail)
		if itemCount and itemCount > 0 and not (cod and cod > 0) then
			for attachment = 1, ATTACHMENTS_MAX_RECEIVE do
				local _, itemID, icon, count, quality = GetInboxItem(mail, attachment)
				if itemID then
					local link = GetInboxItemLink and GetInboxItemLink(mail, attachment)
					local gear = C_Item.IsEquippableItem and C_Item.IsEquippableItem(itemID)
					local key = gear and link or itemID
					local item = byKey[key]
					if not item then
						item = { id = itemID, link = link, count = 0, where = "mail", attachments = {}, icon = icon, quality = quality }
						byKey[key] = item
						table.insert(items, item)
					end
					count = math.max(count or 1, 1)
					item.count = item.count + count
					table.insert(item.attachments, { mail = mail, attachment = attachment, count = count })
				end
			end
		end
	end
	return items
end
sell.LiveMailItems = LiveMailItems

-- What's in your bank or mail ("bank", "mail"): read live while you're there, else as
-- Inventory Tracker last saw it ({ id, count, where }, no links: priced by ID).
local function ElsewhereItems(where)
	if sell.IsPlaceOpen(where) then
		return where == "bank" and LiveBankItems() or LiveMailItems()
	end
	local me = MyInventory()
	local items = {}
	for itemID, count in pairs(me and me[where] or {}) do
		table.insert(items, { id = itemID, count = count, where = where })
	end
	return items
end

-- When the bank or mail ("bank", "mail") was last read, as time(), or nil.
function sell.LastSeen(where)
	local me = MyInventory()
	return me and me.seen and me.seen[where]
end

-- What's listed: your bags, bank and mail (the Bags, Bank and Mail switches). Away, those are
-- your settings. At the bank or mailbox the list focuses on that place: only it is listed, and
-- the switches change what's shown for that visit only (`visit`), back to your settings when
-- you leave.
local visit -- { bags, bank, mail } while you're at the bank or mailbox

local SWITCH_OPTIONS = { bags = "sellListBags", bank = "sellListBank", mail = "sellListMail" }

function sell.AtBankOrMailbox()
	return sell.IsPlaceOpen("bank") or sell.IsPlaceOpen("mail")
end

-- Whether a source is switched on ("bags", "bank", "mail"): for this visit, or your setting.
local function SwitchedOn(where)
	if visit and sell.AtBankOrMailbox() then
		return visit[where] == true
	end
	local value = ns:GetOption(SWITCH_OPTIONS[where])
	if where == "bags" then
		return value ~= false
	end
	return value == true
end

function sell.ShowsBags()
	return SwitchedOn("bags")
end

-- Whether the bank or mail is listed: read live while you're there, else as Inventory Tracker
-- last saw it.
function sell.Shows(where)
	if not SwitchedOn(where) then
		return false
	end
	return sell.IsPlaceOpen(where) or ns:IsModuleEnabled("inventoryTracker")
end

-- A switch clicked: for this visit at the bank or mailbox, else the setting.
function sell.Toggle(where)
	if visit and sell.AtBankOrMailbox() then
		visit[where] = not visit[where]
		if sell.onChanged then
			sell.onChanged()
		end
	else
		ns:SetSetting(SWITCH_OPTIONS[where], not SwitchedOn(where))
	end
end

local SORTS = {
	name = function(a, b)
		return (a.name or "") < (b.name or "")
	end,
	count = function(a, b)
		return a.count < b.count
	end,
	each = function(a, b)
		return (a.groupEach or 0) < (b.groupEach or 0)
	end,
	ah = function(a, b)
		return (a.ahTotal or 0) < (b.ahTotal or 0)
	end,
	vendor = function(a, b)
		return a.vendorTotal < b.vendorTotal
	end,
	value = function(a, b)
		return a.value < b.value
	end,
}

function sell.GetSort()
	local sort = NraKitDB.sellListSort
	if not (sort and SORTS[sort.key]) then
		return "value", false
	end
	return sort.key, sort.ascending == true
end

-- Sorts by a column; the same column again flips the order (money columns start high).
function sell.SetSort(key)
	local current, ascending = sell.GetSort()
	if current == key then
		ascending = not ascending
	else
		ascending = key == "name"
	end
	NraKitDB.sellListSort = { key = key, ascending = ascending }
	if sell.onChanged then
		sell.onChanged()
	end
end

local function SortItems(items)
	local key, ascending = sell.GetSort()
	local less = SORTS[key]
	table.sort(items, function(a, b)
		if less(a, b) ~= less(b, a) then
			if ascending then
				return less(a, b)
			end
			return less(b, a)
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return (a.name or "") < (b.name or "")
	end)
end

-- Everything, grouped by where it sells best: { ah = {...}, vendor = {...} (soulbound ones
-- too: at a vendor that makes no difference), kept = {...}, ahTotal, vendorTotal (of what's
-- in your bags), elsewhereTotal (of what's in your bank and mail, when shown), loading }.
-- Bank and mail items (item.where) are in the same groups as your bags', marked. Each item
-- gets groupEach: the price of one where its group sells it.
function sell.Collect()
	local min = (ns:GetValue("sellListMinValue") or 5) * 100
	local groups = { ah = {}, vendor = {}, kept = {}, ahTotal = 0, vendorTotal = 0, elsewhereTotal = 0, loading = false }
	local function Add(item)
		if not Price(item) then
			groups.loading = true
			return
		end
		-- Whether a saved bank or mail item is soulbound isn't known; one that binds when picked
		-- up is. (Read live, the bank says; mail is never soulbound to you yet.)
		if item.where and not item.slots and item.bindType == 1 then
			item.bound = true
		end
		if item.bound then
			item.value, item.best = item.vendorTotal, "vendor"
		end
		item.groupEach = item.best == "ah" and item.each or item.vendorEach
		if sell.IsKept(item.id) then
			table.insert(groups.kept, item)
		elseif item.value <= 0 or item.value < min then
			return
		else
			table.insert(item.best == "ah" and groups.ah or groups.vendor, item)
			if item.where then
				groups.elsewhereTotal = groups.elsewhereTotal + item.value
			elseif item.best == "ah" then
				groups.ahTotal = groups.ahTotal + item.ahTotal
			else
				groups.vendorTotal = groups.vendorTotal + item.vendorTotal
			end
		end
	end
	if sell.ShowsBags() then
		for _, item in ipairs(BagItems()) do
			Add(item)
		end
	end
	for _, where in ipairs({ "bank", "mail" }) do
		if sell.Shows(where) then
			for _, item in ipairs(ElsewhereItems(where)) do
				Add(item)
			end
		end
	end
	for _, list in ipairs({ groups.ah, groups.vendor, groups.kept }) do
		SortItems(list)
	end
	return groups
end

-- Where you are: "ah", "merchant" or "away". Groups fold by it.
function sell.Context()
	if auctionHouseOpen then
		return "ah"
	elseif merchantOpen then
		return "merchant"
	end
	return "away"
end

-- Whether a group is open. Each place remembers its own: at the auction house the vendor
-- group starts folded, at a merchant the auction house group; Kept starts folded everywhere.
function sell.IsOpen(group)
	local context = sell.Context()
	local saved = NraKitDB.sellListOpen and NraKitDB.sellListOpen[context]
	if saved and saved[group] ~= nil then
		return saved[group]
	end
	if group == "kept" then
		return false
	end
	return not (context == "ah" and group == "vendor" or context == "merchant" and group == "ah")
end

function sell.SetOpen(group, open)
	local context = sell.Context()
	NraKitDB.sellListOpen = NraKitDB.sellListOpen or {}
	-- (Saved per group before places had their own.)
	if type(NraKitDB.sellListOpen[context]) ~= "table" then
		NraKitDB.sellListOpen[context] = {}
	end
	NraKitDB.sellListOpen[context][group] = open
	if sell.onChanged then
		sell.onChanged()
	end
end

---------------------------------------------------------------------------
-- Buttons on the auction house, bank and mailbox windows
---------------------------------------------------------------------------

-- Where a "NraKit Sell List" button goes, by the window's close button: { frame name, option }.
local PLACE_BUTTONS = {
	{ frame = "AuctionHouseFrame", option = "sellListAHButton" },
	{ frame = "BankFrame", option = "sellListPlaceButtons" },
	{ frame = "MailFrame", option = "sellListPlaceButtons" },
}
local placeButtons = {} -- frame name -> button

local function UpdatePlaceButtons()
	for _, place in ipairs(PLACE_BUTTONS) do
		local button = placeButtons[place.frame]
		if button then
			button:SetShown(ns:IsModuleEnabled(module.key) and ns:GetOption(place.option))
		end
	end
end

local function CreatePlaceButtons()
	for _, place in ipairs(PLACE_BUTTONS) do
		local parent = _G[place.frame]
		if not placeButtons[place.frame] and type(parent) == "table" and parent.GetFrameLevel then
			local button = ns.UI.CreateFlatButton(parent, "NraKit Sell List", 20)
			-- Above the window's border and title, which are drawn far above the window itself.
			local title = parent.TitleContainer
			button:SetFrameLevel((title and title:GetFrameLevel() or parent:GetFrameLevel() + 500) + 5)
			button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -1)
			button:SetScript("OnClick", function()
				if sell.IsWindowShown and sell.IsWindowShown() then
					sell.HideWindow()
				else
					ns:OpenSellList()
				end
			end)
			button:SetScript("OnEnter", function(self)
				ns.UI.ShowTooltip(self, "Sell List", "What in your bags is worth selling, most valuable first. Opens beside this window.")
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			placeButtons[place.frame] = button
			if place.frame == "AuctionHouseFrame" then
				-- Opening the auction house opens the list (an option). The window is shown by
				-- now, so the list can dock beside it.
				parent:HookScript("OnShow", function()
					if ns:IsModuleEnabled(module.key) and ns:GetOption("sellListAutoOpen") then
						auctionHouseOpen = true
						ns:OpenSellList()
					end
				end)
			end
		end
	end
	UpdatePlaceButtons()
end

-- Opens the list; at the auction house, a merchant, the bank or the mailbox (if that's the
-- option) NraKit's window docks beside it, whichever tab you go to next, until it closes.
-- The bank's page tabs hang off its right side: dock past the widest of them. (Forever's
-- bank: BankFrame.bankPageTabPool, tabs anchored to its top right; read only.)
local function BankTabsWidth()
	local width = 0
	local pool = type(BankFrame) == "table" and BankFrame.bankPageTabPool
	if pool and pool.EnumerateActive then
		for tab in pool:EnumerateActive() do
			if tab:IsShown() then
				width = math.max(width, tab:GetWidth() or 0)
			end
		end
	end
	return width
end

-- An open mail shows to the right of the mailbox, where the list docks: then the list moves
-- right of it, and back when it closes.
local function MailDock()
	if type(OpenMailFrame) == "table" and OpenMailFrame:IsShown() then
		return OpenMailFrame
	end
	return MailFrame
end

local DOCKS = {
	{ open = function() return auctionHouseOpen end, frame = function() return AuctionHouseFrame end },
	{ open = function() return merchantOpen end, frame = function() return MerchantFrame end },
	{ open = function() return sell.IsPlaceOpen("bank") end, frame = function() return BankFrame end,
		x = function() return BankTabsWidth() + 6 end },
	{ open = function() return sell.IsPlaceOpen("mail") end, frame = MailDock },
}

-- Where the list opens by itself (the "Automatically Open At" options): place -> option.
sell.AUTO_OPEN = {
	{ key = "ah", option = "sellListAutoOpen", label = "Auction House" },
	{ key = "merchant", option = "sellListMerchantOpen", label = "Merchants" },
	{ key = "bank", option = "sellListBankOpen", label = "Bank" },
	{ key = "mail", option = "sellListMailOpen", label = "Mailbox" },
}

-- Coming and going: the bank and mailbox windows showing or hiding (whatever events the client
-- sends), so leaving can't be missed. Arriving with the window shown can open the list.
local function Arrive(where, shown)
	if not placeOpen[where] then
		-- Focus on this place: only it is listed, for this visit.
		visit = { bags = false, bank = where == "bank", mail = where == "mail" }
	end
	placeOpen[where] = true
	CreatePlaceButtons()
	Changed()
	if shown and ns:GetOption(where == "bank" and "sellListBankOpen" or "sellListMailOpen")
		and not (sell.IsWindowShown and sell.IsWindowShown()) then
		ns:OpenSellList()
	end
end

local function Leave(where)
	if not placeOpen[where] then
		return
	end
	placeOpen[where] = false
	if not (placeOpen.bank or placeOpen.mail) then
		visit = nil
	end
	local anchor = ns.UI.DockAnchor()
	if anchor and (anchor == _G[PLACE_FRAMES[where]] or (where == "mail" and anchor == OpenMailFrame)) then
		ns.UI.Undock()
	end
	Changed()
end

local placesHooked = {}

local function HookPlaces()
	for where, name in pairs(PLACE_FRAMES) do
		local frame = _G[name]
		if not placesHooked[where] and type(frame) == "table" and frame.HookScript then
			placesHooked[where] = true
			frame:HookScript("OnShow", function()
				if ns:IsModuleEnabled(module.key) then
					Arrive(where, true)
				end
			end)
			frame:HookScript("OnHide", function()
				Leave(where)
			end)
		end
	end
end

local openMailHooked = false

local function HookOpenMail()
	if openMailHooked or type(OpenMailFrame) ~= "table" then
		return
	end
	openMailHooked = true
	local function Follow()
		local anchor = ns.UI.DockAnchor()
		if anchor and (anchor == MailFrame or anchor == OpenMailFrame) then
			ns.UI.MoveDock(MailDock())
		end
	end
	OpenMailFrame:HookScript("OnShow", Follow)
	OpenMailFrame:HookScript("OnHide", Follow)
end

function ns:OpenSellList()
	if ns:GetOption("sellListDock") and not ns.UI.IsDocked() then
		for _, dock in ipairs(DOCKS) do
			local frame = dock.open() and dock.frame()
			if type(frame) == "table" and frame:IsShown() then
				ns.UI.Dock(frame, dock.x and dock.x())
				break
			end
		end
	end
	if sell.ShowWindow then
		sell.ShowWindow()
	end
end

-- Redraws the list (if it's open): what's in a place changed, or you came or went.
function Changed()
	if sell.onChanged then
		sell.onChanged()
	end
	if sell.onPlaceChanged then
		sell.onPlaceChanged()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" then
		if addonName == "Blizzard_AuctionHouseUI" or addonName == "Blizzard_MailFrame" then
			CreatePlaceButtons()
			HookPlaces()
			HookOpenMail()
		end
	elseif event == "AUCTION_HOUSE_SHOW" then
		auctionHouseOpen = true
		CreatePlaceButtons()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		auctionHouseOpen = false
		ns.UI.Undock()
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
		ns.UI.Undock()
	elseif event == "BANKFRAME_OPENED" then
		HookPlaces()
		Arrive("bank")
	elseif event == "BANKFRAME_CLOSED" then
		Leave("bank")
	elseif event == "MAIL_SHOW" then
		HookPlaces()
		HookOpenMail()
		Arrive("mail")
	elseif event == "MAIL_CLOSED" then
		Leave("mail")
	elseif event == "MAIL_INBOX_UPDATE" then
		Changed()
	end
end)

-- A merchant opens the list (an option), once its window is shown so the list docks beside it.
local merchantHooked = false

local function HookMerchant()
	if type(MerchantFrame) ~= "table" or merchantHooked then
		return
	end
	merchantHooked = true
	MerchantFrame:HookScript("OnShow", function()
		if ns:IsModuleEnabled(module.key) then
			merchantOpen = true
			if ns:GetOption("sellListMerchantOpen") then
				ns:OpenSellList()
			end
		end
	end)
end

function module:OnInitialize()
	sell.LoadAutoOpen()
	eventFrame:RegisterEvent("ADDON_LOADED")
	CreatePlaceButtons()
	HookMerchant()
	HookPlaces()
	HookOpenMail()
	ns:RegisterSlashCommand("sell", function(rest)
		if rest:lower() == "debug" then
			ns:SetDebug("sell", not ns:IsDebugging("sell")) -- (the same as /nra debug sell)
			return
		end
		if not ns:IsModuleEnabled(module.key) then
			ns:Print("Turn on Sell List first (/nra).")
			return
		end
		ns:OpenSellList()
	end, {
		summary = "The Sell List: what in your bags is worth selling",
		usage = { "/nra sell - open the Sell List", "/nra sell debug - log taking from the bank and mail (the same as /nra debug sell)" },
	})
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED",
		"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE" }) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	UpdatePlaceButtons()
end

-- "Automatically Open At" is per character (a bank alt opens it at the bank, your main not):
-- each character's ticks are saved by name (NraKitDB.sellListAutoOpenChars), and the four
-- options show the character you're on. One that hasn't set them gets the defaults.
local AUTO_OPEN_DEFAULTS = { sellListAutoOpen = true, sellListMerchantOpen = false, sellListBankOpen = false,
	sellListMailOpen = false }

local function CharacterAutoOpen()
	NraKitDB.sellListAutoOpenChars = NraKitDB.sellListAutoOpenChars or {}
	local name = ns:PlayerName()
	NraKitDB.sellListAutoOpenChars[name] = NraKitDB.sellListAutoOpenChars[name] or {}
	return NraKitDB.sellListAutoOpenChars[name]
end

-- Puts this character's ticks into the options (at login).
function sell.LoadAutoOpen()
	local mine = CharacterAutoOpen()
	for key, default in pairs(AUTO_OPEN_DEFAULTS) do
		local value = mine[key]
		if value == nil then
			value = default
		end
		NraKitDB[key] = value
		if ns.settings[key] then
			ns.settings[key]:SetValue(value)
		end
	end
end

function module:OnOptionChanged(key, value)
	if AUTO_OPEN_DEFAULTS[key] ~= nil then
		CharacterAutoOpen()[key] = value == true
	end
	UpdatePlaceButtons()
	if sell.onChanged then
		sell.onChanged()
	end
end

ns:RegisterModule(module)
