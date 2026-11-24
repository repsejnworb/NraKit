local _, ns = ...

-- Wishlist: gear you want, per character. Add items with /nra wishlist <item> [note]
-- (shift-click it in), with a right-click on an item link in chat or in Item lookup, or by
-- dropping one on the window. The window (WishlistWindow.lua) lists them by slot, with the level to wear
-- them and your note on where they come from (NraKit has no database of sources).
--
-- Items you have (bags, bank or worn) are ticked off; getting one after you added it
-- shows a message. Item tooltips say they're on your wishlist, and a star marks them in
-- your bags, at vendors, in quest rewards, the loot window and loot rolls (and Item
-- lookup): gold while you want it, grey once you have it.
--
-- Saved per character in NraKitDB.wishlistData[<character>] = { items = { [itemID] =
-- { id, link?, name?, note?, added, got? } }, collapsed = { [group] = true } }. `name` is
-- only set for an item with a random suffix ("of the Monkey"): then only that one counts.

local module = {
	key = "wishlist",
	section = "Bags & Items",
	name = "Wishlist",
	description = "A list of gear you want, by slot, with the level to wear it and a note on where it comes from. Add items with /nra wishlist <item> (shift-click it in), by right-clicking an item link in chat or an item in Item lookup, or by dropping them on the window. Items you get are ticked off with a message, a star marks them in your bags, at vendors and in loot, and item tooltips say they're on your wishlist.",
	default = false,
	options = {
		{
			key = "wishlistTooltip",
			header = "General",
			name = "Say so in item tooltips",
			description = "A line in the tooltip of items on your wishlist, with your note.",
			default = true,
		},
		{
			key = "wishlistStars",
			name = "Star them",
			description = "A star on wishlist items in your bags, at vendors, in quest rewards, the loot window and loot rolls: gold while you want it, grey once you have it.",
			default = true,
		},
		{
			key = "wishlistToast",
			name = "Message when you get one",
			description = "A message in the middle of the screen when an item on your wishlist lands in your bags.",
			default = true,
		},
		{
			key = "wishlistRemoveGot",
			name = "Take items off once you have them",
			description = "Remove items from the wishlist when you get them, instead of ticking them off.",
			default = false,
		},
	},
}

local STAR_ATLAS = "auctionhouse-icon-favorite"
local STAR_SIZE = 16
local LOGIN_QUIET_SECONDS = 10 -- items you already had at login are ticked off without a message

local wishlist = {}
ns.wishlist = wishlist

local eventFrame = CreateFrame("Frame")
local loginAt
local checkQueued = false
local QueueStars

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

function wishlist.GetData()
	NraKitDB.wishlistData = NraKitDB.wishlistData or {}
	local name = ns:PlayerName() or "?"
	local data = NraKitDB.wishlistData[name]
	if not data then
		data = { items = {}, collapsed = {} }
		NraKitDB.wishlistData[name] = data
	end
	return data
end

local function Changed()
	QueueStars()
	if wishlist.onChanged then
		wishlist.onChanged()
	end
end

-- An item link, "item:123" or an item ID -> item ID and the link (if there was one).
function wishlist.ParseItem(item)
	if type(item) == "number" then
		return item
	end
	if type(item) ~= "string" then
		return nil
	end
	local id = item:match("item:(%d+)") or item:match("^%s*(%d+)%s*$")
	if not id then
		return nil
	end
	local link = item:match("|c.-|Hitem:.-|h.-|h|r") or item:match("|Hitem:.-|h.-|h")
	return tonumber(id), link
end

-- The name of a link, if it differs from the item's own name (a random suffix).
local function SuffixName(id, link)
	if not link then
		return nil
	end
	local shown = link:match("|h%[(.-)%]|h")
	local base = C_Item.GetItemNameByID(id)
	if shown and base and shown ~= base then
		return shown
	end
	return nil
end

function wishlist.Get(id)
	return id and wishlist.GetData().items[id]
end

-- The entry for an item link (or ID): an item with a random suffix only in that suffix.
function wishlist.Find(item)
	local id, link = wishlist.ParseItem(item)
	local entry = wishlist.Get(id)
	if entry and entry.name and link then
		local shown = link:match("|h%[(.-)%]|h")
		if shown and shown ~= entry.name then
			return nil
		end
	end
	return entry
end

-- The item's name, quality, required level, slot (equipLoc) and icon. Name, quality
-- and level are nil until the game has loaded the item (it's asked to).
function wishlist.Info(entry)
	local _, _, _, equipLoc, icon = C_Item.GetItemInfoInstant(entry.id)
	local name, _, quality, _, minLevel = C_Item.GetItemInfo(entry.link or entry.id)
	if not name then
		C_Item.RequestLoadItemDataByID(entry.id)
	end
	return entry.name or name or C_Item.GetItemNameByID(entry.id), quality, minLevel, equipLoc, icon
end

function wishlist.Link(entry)
	return entry.link or select(2, C_Item.GetItemInfo(entry.id))
end

-- Whether you have the item: in your bags, bank or worn. An item with a random suffix
-- only counts in that suffix (looked for in your bags and gear; the bank can't be read).
function wishlist.Have(entry)
	local count = C_Item.GetItemCount(entry.id, true) or 0
	if count == 0 and not C_Item.IsEquippedItem(entry.id) then
		return false
	end
	if not entry.name then
		return true
	end
	local function Same(link)
		return link and link:match("item:(%d+)") == tostring(entry.id) and link:match("|h%[(.-)%]|h") == entry.name
	end
	for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
		if Same(GetInventoryItemLink("player", slot)) then
			return true
		end
	end
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			if Same(C_Container.GetContainerItemLink(bag, slot)) then
				return true
			end
		end
	end
	return false
end

-- Adds an item (link, "item:123" or ID) with an optional note. Returns the entry and
-- whether it was new; adding one that's there already updates its note (if given).
function wishlist.Add(item, note)
	local id, link = wishlist.ParseItem(item)
	if not id or id <= 0 then
		return nil
	end
	local items = wishlist.GetData().items
	local entry = items[id]
	local isNew = entry == nil
	if isNew then
		entry = { id = id, added = time() }
		items[id] = entry
	end
	if link then
		entry.link, entry.name = link, SuffixName(id, link)
	end
	note = note and strtrim(note)
	if note and note ~= "" then
		entry.note = note
	end
	if isNew and wishlist.Have(entry) then
		entry.got = true -- you have it already: no message
	end
	Changed()
	return entry, isNew
end

function wishlist.Remove(id)
	local items = wishlist.GetData().items
	if not items[id] then
		return false
	end
	items[id] = nil
	Changed()
	return true
end

function wishlist.SetNote(id, note)
	local entry = wishlist.Get(id)
	if entry then
		note = strtrim(note or "")
		entry.note = note ~= "" and note or nil
		Changed()
	end
end

function wishlist.SetGot(id, got)
	local entry = wishlist.Get(id)
	if entry then
		entry.got = got or nil
		Changed()
	end
end

function wishlist.Count()
	local count = 0
	for _ in pairs(wishlist.GetData().items) do
		count = count + 1
	end
	return count
end

------------------------------------------------------------------------------
-- Getting items
------------------------------------------------------------------------------

local function ShowGot(entry)
	local name, quality, _, _, icon = wishlist.Info(entry)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	ns.toast.Show({
		style = "big",
		heading = "Wishlist",
		text = (color and color.hex or "") .. (name or "An item") .. (color and "|r" or "") .. " is yours!",
		detail = ns:GetOption("wishlistRemoveGot") and "Taken off your wishlist" or "Ticked off your wishlist. Click to open it",
		icon = icon,
		onClick = function()
			if ns.OpenWishlist and ns.wishlist.Get(entry.id) then
				ns:OpenWishlist(true)
			end
		end,
	})
end

-- Ticks off the items you have now. With a message, unless it's just after login (you
-- had them already).
function wishlist.CheckGot()
	checkQueued = false
	local quiet = not loginAt or GetTime() - loginAt < LOGIN_QUIET_SECONDS
	local got = {}
	for _, entry in pairs(wishlist.GetData().items) do
		if not entry.got and wishlist.Have(entry) then
			table.insert(got, entry)
		end
	end
	if #got == 0 then
		return
	end
	for _, entry in ipairs(got) do
		if not quiet and ns:GetOption("wishlistToast") then
			ShowGot(entry)
		end
		if ns:GetOption("wishlistRemoveGot") then
			wishlist.GetData().items[entry.id] = nil
		else
			entry.got = true
		end
	end
	Changed()
end

local function QueueCheck()
	if not checkQueued then
		checkQueued = true
		C_Timer.After(0.5, wishlist.CheckGot)
	end
end

------------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------------

local function OnItemTooltip(tooltip)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("wishlistTooltip") then
		return
	end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	local entry = wishlist.Get(wishlist.ParseItem(link))
	if not entry then
		return
	end
	tooltip:AddLine(entry.got and "NraKit: On your wishlist, got it" or "NraKit: On your wishlist", 1, 0.6, 0.2)
	if entry.note then
		tooltip:AddLine(entry.note, 1, 1, 1, true)
	end
end

------------------------------------------------------------------------------
-- Stars on item icons
------------------------------------------------------------------------------

local stars = {}

-- A star on the corner of an item button's icon (anchor) if the item (link or ID) is on
-- the wishlist: gold while you want it, grey once you have it. Hidden otherwise.
function wishlist.SetStar(button, item, anchor)
	local entry = item and ns:IsModuleEnabled(module.key) and ns:GetOption("wishlistStars") and wishlist.Find(item)
	local star = stars[button]
	if not entry then
		if star then
			star:Hide()
		end
		return
	end
	if not star then
		-- Own frame above the button's children; never takes the mouse.
		local holder = CreateFrame("Frame", nil, button)
		holder:SetAllPoints(anchor or button)
		holder:SetFrameLevel(button:GetFrameLevel() + 6)
		star = holder:CreateTexture(nil, "OVERLAY")
		star:SetAtlas(STAR_ATLAS)
		star:SetSize(STAR_SIZE, STAR_SIZE)
		star:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 3, 3)
		star.holder = holder
		stars[button] = star
	end
	star:SetDesaturated(entry.got == true)
	star:SetAlpha(entry.got and 0.7 or 1)
	star:Show()
end

local function UpdateBags()
	ns:ForEachBagItemButton(function(itemButton)
		local link = C_Container.GetContainerItemLink(itemButton:GetBagID(), itemButton:GetID())
		wishlist.SetStar(itemButton, link, itemButton.icon or itemButton.Icon)
	end)
end

local function UpdateMerchant()
	if not (MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	local onItemsTab = MerchantFrame.selectedTab == 1
	for i = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		if itemButton then
			local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + i
			local link = onItemsTab and itemButton:IsShown() and GetMerchantItemLink(index)
				or not onItemsTab and itemButton:IsShown() and GetBuybackItemLink(i)
			wishlist.SetStar(itemButton, link or nil, itemButton.icon or itemButton.Icon)
		end
	end
end

local function UpdateQuestRewards()
	local rewardsFrame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	if not rewardsFrame or not rewardsFrame.RewardButtons then
		return
	end
	for _, button in ipairs(rewardsFrame.RewardButtons) do
		local link
		if button:IsShown() and button.objectType == "item" then
			if QuestInfoFrame.questLog then
				link = GetQuestLogItemLink(button.type, button:GetID())
			else
				link = GetQuestItemLink(button.type, button:GetID())
			end
		end
		wishlist.SetStar(button, link, button.Icon)
	end
end

local function UpdateLoot()
	local scrollBox = LootFrame and LootFrame:IsShown() and LootFrame.ScrollBox
	if not (scrollBox and scrollBox.ForEachFrame) then
		return
	end
	scrollBox:ForEachFrame(function(element)
		if element.Item and element.GetSlotIndex then
			wishlist.SetStar(element.Item, GetLootSlotLink(element:GetSlotIndex()), element.Item.icon)
		end
	end)
end

local function UpdateRoll(rollFrame)
	if rollFrame and rollFrame.IconFrame then
		wishlist.SetStar(rollFrame.IconFrame, rollFrame.rollID and GetLootRollItemLink(rollFrame.rollID), rollFrame.IconFrame.Icon)
	end
end

local starsQueued = false
local function UpdateStars()
	starsQueued = false
	if not ns:IsModuleEnabled(module.key) and not next(stars) then
		return -- off, and nothing to take off
	end
	UpdateBags()
	UpdateMerchant()
	UpdateQuestRewards()
	UpdateLoot()
	for i = 1, 4 do
		local rollFrame = _G["GroupLootFrame" .. i]
		if rollFrame and rollFrame:IsShown() then
			UpdateRoll(rollFrame)
		end
	end
end

function QueueStars()
	if not starsQueued then
		starsQueued = true
		C_Timer.After(0, UpdateStars)
	end
end

------------------------------------------------------------------------------
-- Right-click menus: Item lookup rows and item links in chat
------------------------------------------------------------------------------

-- A menu to add the item (link or ID) to the wishlist, or take it off; then onDone().
function wishlist.OpenItemMenu(owner, item, onDone)
	local id, link = wishlist.ParseItem(item)
	if not id then
		return
	end
	local name = link and link:match("|h%[(.-)%]|h") or C_Item.GetItemNameByID(id) or ("Item " .. id)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(name)
		if wishlist.Find(link or id) then
			root:CreateButton("Remove from wishlist", function()
				wishlist.Remove(id)
				ns:Print("Removed " .. (link or name) .. " from your wishlist.")
				if onDone then
					onDone()
				end
			end)
		else
			root:CreateButton("Add to wishlist", function()
				local entry = wishlist.Add(link or id)
				ns:Print("Added " .. (entry and wishlist.Link(entry) or name) .. " to your wishlist.")
				if onDone then
					onDone()
				end
			end)
		end
	end)
end

-- Right-click an item link in chat (left-click still shows the item, as always).
local function OnChatLinkClick(_, _, link, text, button)
	if button ~= "RightButton" or IsModifiedClick() or not ns:IsModuleEnabled(module.key) then
		return
	end
	if type(link) == "string" and link:match("^item:") then
		wishlist.OpenItemMenu(UIParent, type(text) == "string" and text:find("|Hitem:", 1, true) and text or link)
	end
end

------------------------------------------------------------------------------
-- /nra wishlist
------------------------------------------------------------------------------

local function OnSlashCommand(rest)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Turn on Wishlist first (/nra).")
		return
	end
	if rest == "" then
		ns:OpenWishlist()
		return
	end
	local id, link = wishlist.ParseItem(rest)
	if not id then
		ns:Print("Shift-click an item after /nra wishlist to add it (or type its item ID).")
		return
	end
	-- The note is whatever follows the link (or the ID).
	local note
	if link then
		local _, finish = rest:find(link, 1, true)
		note = finish and rest:sub(finish + 1)
	else
		note = rest:match("^%s*%d+%s*(.*)$")
	end
	local entry, isNew = wishlist.Add(link or id, note)
	if not entry then
		return
	end
	local shown = wishlist.Link(entry) or wishlist.Info(entry) or ("item " .. id)
	if not isNew then
		ns:Print(shown .. " is on your wishlist already" .. ((note and strtrim(note) ~= "") and " (note updated)." or "."))
	elseif entry.got then
		ns:Print("Added " .. shown .. " to your wishlist. You have it already, so it's ticked off.")
	else
		ns:Print("Added " .. shown .. " to your wishlist.")
	end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local EVENTS = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED",
	"LOOT_SLOT_CLEARED" }

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = ...
		if isLogin or isReload or not loginAt then
			loginAt = GetTime()
		end
		QueueCheck()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		local id = ...
		if wishlist.Get(id) and wishlist.onItemLoaded then
			wishlist.onItemLoaded(id)
		end
	elseif event == "LOOT_SLOT_CLEARED" then
		QueueStars()
	else
		QueueCheck()
		QueueStars()
	end
end)

ns:RegisterPreview("wishlist", "Wishlist: the message when you get an item on it", function()
	ns.toast.Show({
		style = "big",
		heading = "Wishlist",
		text = "|cff0070ddHerod's Shoulder|r is yours!",
		detail = "Ticked off your wishlist. Click to open it",
		icon = 135058,
	})
end)

function module:OnInitialize()
	local help = {
		summary = "Wishlist: gear you want, by slot, ticked off when you get it",
		usage = {
			"/nra wishlist - open your wishlist",
			"/nra wishlist <item> [note] - add an item (shift-click it in), with an optional note on where it comes from",
			"/nra wish - short for /nra wishlist",
		},
	}
	ns:RegisterSlashCommand("wishlist", OnSlashCommand, help)
	ns:RegisterSlashCommand("wish", OnSlashCommand, help)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", OnChatLinkClick, module)

	-- Stars, after Blizzard fills the buttons.
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		if frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", QueueStars)
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
		hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", QueueStars)
	end
	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchant)
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateMerchant)
	hooksecurefunc("QuestInfo_Display", UpdateQuestRewards)
	hooksecurefunc("GroupLootFrame_SetupItemDisplay", UpdateRoll)
	if LootFrame and LootFrame.Open then
		hooksecurefunc(LootFrame, "Open", UpdateLoot)
	end
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		loginAt = loginAt or GetTime()
		QueueCheck()
	end
	QueueStars()
end

function module:OnOptionChanged()
	QueueStars()
end

ns:RegisterModule(module)
