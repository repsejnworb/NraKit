local _, ns = ...

-- Inventory browser (/nra inv): a window over Inventory tracker's data.
--
-- Sidebar: "All characters", then each character (class colour, level, gold); right-
-- click one to forget it. Top: location tabs (All, Bags, Bank, Mail, Equipped), a
-- grid/list toggle, search, and category chips. A line under them says how fresh the
-- data is (the bank and mail are only read while open).
--
-- One character opens as a bag-like grid; "All characters" opens as a list that says
-- who has what. The toggle is remembered separately for the two.
--
-- Item names, quality and prices come from C_Item.GetItemInfo, which may need the
-- client to load the item first; the window re-renders as they arrive.

local UI = ns.UI
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local SIDEBAR_WIDTH = 210
local PAD = UI.PAD
local SLOT, SLOT_GAP = 36, 4
local ROW_HEIGHT = 30
local TOP_HEIGHT = 92
local FOOTER_HEIGHT = 28

local CATEGORIES = {
	{ key = "all", label = "All" },
	{ key = "gear", label = "Gear" },
	{ key = "consumable", label = "Consumables" },
	{ key = "tradegoods", label = "Trade goods" },
	{ key = "recipe", label = "Recipes" },
	{ key = "quest", label = "Quest" },
	{ key = "other", label = "Other" },
}
local CATEGORY_ORDER, CATEGORY_LABELS = {}, {}
for index, category in ipairs(CATEGORIES) do
	CATEGORY_ORDER[category.key] = index
	CATEGORY_LABELS[category.key] = category.label
end

-- Enum.ItemClass -> category key; anything else is "other".
local CLASS_CATEGORY = {
	[Enum.ItemClass.Weapon] = "gear",
	[Enum.ItemClass.Armor] = "gear",
	[Enum.ItemClass.Container] = "gear",
	[Enum.ItemClass.Quiver] = "gear",
	[Enum.ItemClass.Projectile] = "gear",
	[Enum.ItemClass.Consumable] = "consumable",
	[Enum.ItemClass.ItemEnhancement] = "consumable",
	[Enum.ItemClass.Tradegoods] = "tradegoods",
	[Enum.ItemClass.Reagent] = "tradegoods",
	[Enum.ItemClass.Gem] = "tradegoods",
	[Enum.ItemClass.Recipe] = "recipe",
	[Enum.ItemClass.Questitem] = "quest",
	[Enum.ItemClass.Key] = "quest",
}

local frame, sidebarScroll, scroll, searchBox, infoText, footerLeft, footerRight, sellButton
local locationTabs, categoryChips, viewButtons = {}, {}, {}
local sidebarPool, pool = UI.CreatePool(), UI.CreatePool()

local selected -- { realm, name } of the shown character, or nil for all characters
local location = "all"
local category = "all"
local query = ""
local renderPending = false

------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------

local function IsMe(realmName, name)
	return realmName == ns.inventory.GetRealm() and name == ns.inventory.GetPlayer()
end

-- All stored characters: this realm first, you first, then by level and name.
local function GetCharacters()
	local list = {}
	for realmName, characters in pairs(NraKitDB.inventory or {}) do
		for name, data in pairs(characters) do
			table.insert(list, { realm = realmName, name = name, data = data, isMe = IsMe(realmName, name) })
		end
	end
	local myRealm = ns.inventory.GetRealm()
	table.sort(list, function(a, b)
		if (a.realm == myRealm) ~= (b.realm == myRealm) then
			return a.realm == myRealm
		end
		if a.realm ~= b.realm then
			return a.realm < b.realm
		end
		if a.isMe ~= b.isMe then
			return a.isMe
		end
		if (a.data.level or 0) ~= (b.data.level or 0) then
			return (a.data.level or 0) > (b.data.level or 0)
		end
		return a.name < b.name
	end)
	return list
end

local function GetView()
	NraKitDB.inventoryBrowserView = NraKitDB.inventoryBrowserView or { single = "grid", all = "list" }
	return NraKitDB.inventoryBrowserView[selected and "single" or "all"]
end

local function SetView(view)
	GetView()
	NraKitDB.inventoryBrowserView[selected and "single" or "all"] = view
end

local function ColorName(character)
	local r, g, b = ns.inventory.ClassColor(character.data.class)
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, character.name)
end

-- Empty when unknown (characters not logged in since gold was first recorded).
local Money

-- "~2,345g": a rough value, whole gold.
local function RoughGold(copper)
	local gold = math.floor(copper / 10000 + 0.5)
	return "~" .. (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)) .. "|cffffd100g|r"
end

-- Gold, and on a line of its own what the items are worth (Auctionator prices), if known.
local function WorthText(money, itemsValue)
	local text = money and Money(money) or ""
	if itemsValue and itemsValue > 0 then
		text = text .. (text ~= "" and "\n" or "") .. "|cffaaaaaa" .. RoughGold(itemsValue) .. " in items|r"
	end
	return text
end

local NAV_HEIGHT, NAV_HEIGHT_VALUED = 38, 50

function Money(copper)
	if not copper then
		return ""
	end
	return GetMoneyString and GetMoneyString(copper, true) or tostring(copper)
end

local function Age(timestamp)
	if not timestamp then
		return nil
	end
	local seconds = time() - timestamp
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h ago"
	end
	return math.floor(seconds / 86400) .. "d ago"
end

-- Builds the shown items: { id, count, icon, category, name, link, quality, price, owners }.
-- owners: list of { character, total, parts = { "Bags 5", ... } }.
local function CollectItems(characters)
	local byID, items = {}, {}
	for _, character in ipairs(characters) do
		for _, where in ipairs(ns.inventory.LOCATIONS) do
			if location == "all" or location == where then
				for itemID, count in pairs(character.data[where] or {}) do
					local item = byID[itemID]
					if not item then
						item = { id = itemID, count = 0, owners = {}, ownerByName = {} }
						byID[itemID] = item
						table.insert(items, item)
					end
					item.count = item.count + count
					local key = character.realm .. "-" .. character.name
					local owner = item.ownerByName[key]
					if not owner then
						owner = { character = character, total = 0, parts = {} }
						item.ownerByName[key] = owner
						table.insert(item.owners, owner)
					end
					owner.total = owner.total + count
					table.insert(owner.parts, ns.inventory.LOCATION_LABELS[where] .. " " .. count)
				end
			end
		end
	end

	local missing = false
	for _, item in ipairs(items) do
		local _, itemType, itemSubType, _, icon, classID = C_Item.GetItemInfoInstant(item.id)
		item.icon = icon or 134400
		item.category = CLASS_CATEGORY[classID] or "other"
		item.typeText = ((itemType or "") .. " " .. (itemSubType or "")):lower()
		local name, link, quality, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(item.id)
		if name then
			item.name, item.link, item.quality, item.price = name, link, quality, price
		else
			missing = true
			C_Item.RequestLoadItemDataByID(item.id)
		end
		table.sort(item.owners, function(a, b)
			return a.total > b.total
		end)
	end
	return items, missing
end

local function Filter(items)
	local shown = {}
	for _, item in ipairs(items) do
		if (category == "all" or item.category == category)
			and (query == "" or (item.name and item.name:lower():find(query, 1, true)) or item.typeText:find(query, 1, true)) then
			table.insert(shown, item)
		end
	end
	table.sort(shown, function(a, b)
		if a.category ~= b.category then
			return CATEGORY_ORDER[a.category] < CATEGORY_ORDER[b.category]
		end
		if (a.quality or 0) ~= (b.quality or 0) then
			return (a.quality or 0) > (b.quality or 0)
		end
		if a.name and b.name and a.name ~= b.name then
			return a.name < b.name
		end
		if (a.name ~= nil) ~= (b.name ~= nil) then
			return a.name ~= nil
		end
		return a.id < b.id
	end)
	return shown
end

------------------------------------------------------------------------------
-- Item widgets
------------------------------------------------------------------------------

local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function OnItemEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.itemID)
	GameTooltip:Show()
end

-- Shift-click links it in chat, Ctrl-click previews it, like bag items.
local function OnItemClick(self)
	local link = select(2, C_Item.GetItemInfo(self.itemID))
	if link then
		HandleModifiedItemClick(link)
	end
end

local function SetupItemButton(button)
	button:SetScript("OnEnter", OnItemEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", OnItemClick)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetColorTexture(1, 1, 1, 0.08)
	highlight:SetAllPoints()
end

local function SetBorder(button, quality)
	if quality and quality >= Enum.ItemQuality.Uncommon then
		button.border:SetVertexColor(QualityColor(quality))
		button.border:Show()
	else
		button.border:Hide()
	end
end

local function AcquireSlot(content)
	return pool:Acquire("slot", function()
		local slot = CreateFrame("Button", nil, content)
		slot:SetSize(SLOT, SLOT)
		SetupItemButton(slot)
		slot.bg = slot:CreateTexture(nil, "BACKGROUND")
		slot.bg:SetAllPoints()
		slot.bg:SetColorTexture(1, 1, 1, 0.05)
		slot.icon:SetPoint("TOPLEFT", 1, -1)
		slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		slot.border:SetAllPoints()
		slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
		return slot
	end)
end

local function AcquireRow(content)
	return pool:Acquire("row", function()
		local row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW_HEIGHT)
		SetupItemButton(row)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.border:SetAllPoints(row.icon)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.count:SetPoint("RIGHT", -10, 0)
		row.count:SetJustifyH("RIGHT")
		row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.where:SetPoint("RIGHT", -60, 0)
		row.where:SetJustifyH("RIGHT")
		row.where:SetWordWrap(false)
		return row
	end)
end

local function FormatCount(count)
	if count >= 10000 then
		return math.floor(count / 1000) .. "k"
	end
	return tostring(count)
end

-- "Bags 5 · Bank 7" for one character, or "Nra 12 · Alt 4" for several.
local function DescribeOwners(item)
	local parts = {}
	if selected then
		for _, owner in ipairs(item.owners) do
			for _, part in ipairs(owner.parts) do
				table.insert(parts, part)
			end
		end
	else
		for _, owner in ipairs(item.owners) do
			table.insert(parts, ColorName(owner.character) .. " " .. owner.total)
		end
	end
	return table.concat(parts, "  ·  ")
end

-- Centred in the width; on the "All" category, with a heading above each category.
local function RenderGrid(content, items, width)
	local step = SLOT + SLOT_GAP
	local columns = math.max(1, math.floor((width + SLOT_GAP) / step))
	local left = PAD + math.floor((width - (columns * step - SLOT_GAP)) / 2)
	local grouped = category == "all"
	local y = -PAD
	local current, index = nil, 0

	local function EndGroup()
		if index > 0 then
			y = y - math.ceil(index / columns) * step
		end
		index = 0
	end

	for _, item in ipairs(items) do
		if grouped and item.category ~= current then
			EndGroup()
			if current then
				y = y - 8
			end
			current = item.category
			local heading = pool:Acquire("heading", function()
				local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				text:SetJustifyH("LEFT")
				return text
			end)
			heading:SetText(CATEGORY_LABELS[current]:upper())
			heading:SetTextColor(unpack(UI.ACCENT))
			heading:SetPoint("TOPLEFT", content, "TOPLEFT", left, y)
			y = y - 18
		end
		local slot = AcquireSlot(content)
		slot.itemID = item.id
		slot.icon:SetTexture(item.icon)
		slot.count:SetText(item.count > 1 and FormatCount(item.count) or "")
		SetBorder(slot, item.quality)
		slot:SetPoint("TOPLEFT", content, "TOPLEFT", left + (index % columns) * step, y - math.floor(index / columns) * step)
		index = index + 1
	end
	EndGroup()
	return -y + PAD
end

local function RenderList(content, items, width)
	for index, item in ipairs(items) do
		local row = AcquireRow(content)
		row.itemID = item.id
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD - (index - 1) * ROW_HEIGHT)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		row.icon:SetTexture(item.icon)
		SetBorder(row, item.quality)
		row.name:SetText(item.name or "Loading...")
		row.name:SetTextColor(QualityColor(item.quality))
		row.name:SetWidth(width * 0.42)
		row.where:SetText(DescribeOwners(item))
		row.where:SetWidth(width * 0.58 - 100)
		row.count:SetText(FormatCount(item.count))
	end
	return PAD * 2 + #items * ROW_HEIGHT
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

local Render

local function OpenCharacterMenu(button)
	local character = button.character
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(character.name .. " - " .. character.realm)
		local forget = root:CreateButton("Forget this character", function()
			ns.inventory.Forget(character.realm, character.name)
			if selected and selected.realm == character.realm and selected.name == character.name then
				selected = nil
			end
			Render()
		end)
		if character.isMe then
			forget:SetEnabled(false)
		end
	end)
end

local function RenderSidebar(characters)
	sidebarPool:ReleaseAll()
	local content = sidebarScroll.content
	local width = SIDEBAR_WIDTH - 2 * PAD
	local y = 0

	local valued = false -- item values shown: taller entries, for their own line
	local function AddButton(label, character)
		local button = sidebarPool:Acquire("nav", function()
			local nav = UI.CreateNavButton(content, width, 38, "")
			nav:SetScript("OnClick", function(self, mouseButton)
				if mouseButton == "RightButton" then
					if self.character then
						OpenCharacterMenu(self)
					end
					return
				end
				selected = self.character and { realm = self.character.realm, name = self.character.name } or nil
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				scroll:SetScroll(0)
				Render()
			end)
			nav.subtext:SetWordWrap(true)
			nav.subtext:SetSpacing(2)
			return nav
		end)
		button.character = character
		button.text:SetText(label)
		button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		local height = valued and NAV_HEIGHT_VALUED or NAV_HEIGHT
		button:SetHeight(height)
		y = y - height - 2
		return button
	end

	local totalMoney -- nil until some character's gold is known
	local totalItems -- the auction value of everyone's items (Auctionator prices), nil without
	local valueOf = {}
	for _, character in ipairs(characters) do
		if character.data.money then
			totalMoney = (totalMoney or 0) + character.data.money
		end
		local value = ns.auctionator and ns.auctionator.InventoryValue and ns.auctionator.InventoryValue(character.data)
		if value then
			valueOf[character] = value
			totalItems = (totalItems or 0) + value
		end
	end
	valued = totalItems ~= nil
	local all = AddButton("All characters", nil)
	all:SetSubtext(WorthText(totalMoney, totalItems))
	all.count:SetText(#characters)
	all:SetSelected(selected == nil)

	local multipleRealms = false
	for _, character in ipairs(characters) do
		if character.realm ~= characters[1].realm then
			multipleRealms = true
		end
	end
	local lastRealm
	for _, character in ipairs(characters) do
		if multipleRealms and character.realm ~= lastRealm then
			lastRealm = character.realm
			local header = sidebarPool:Acquire("realm", function()
				local text = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
				text:SetJustifyH("LEFT")
				return text
			end)
			header:SetText(character.realm:upper())
			header:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y - 8)
			y = y - 24
		end
		local button = AddButton(character.name, character)
		button:SetSubtext(WorthText(character.data.money, valueOf[character]))
		button.count:SetText(character.data.level and tostring(character.data.level) or "")
		local isSelected = selected and selected.realm == character.realm and selected.name == character.name
		button:SetSelected(isSelected, { ns.inventory.ClassColor(character.data.class) })
	end
	content:SetSize(width, -y)
	sidebarScroll:UpdateThumb()
end

-- How fresh the data is: per location for one character, or who's missing a visit.
local function DescribeFreshness(characters)
	if selected then
		local character = characters[1]
		local parts = {}
		for _, where in ipairs(ns.inventory.LOCATIONS) do
			local label = ns.inventory.LOCATION_LABELS[where]
			local seen = character.data.seen and character.data.seen[where]
			if character.isMe and (where == "bags" or where == "equipped") then
				table.insert(parts, label .. ": live")
			elseif seen then
				table.insert(parts, label .. ": " .. Age(seen))
			elseif character.data[where] then
				table.insert(parts, label .. ": seen")
			else
				table.insert(parts, label .. ": |cffff8040not seen yet|r")
			end
		end
		return table.concat(parts, "   ·   ")
	end
	local missing = {}
	for _, where in ipairs({ "bank", "mail" }) do
		local names = {}
		for _, character in ipairs(characters) do
			if not character.data[where] then
				table.insert(names, ColorName(character))
			end
		end
		if #names > 0 then
			table.insert(missing, ns.inventory.LOCATION_LABELS[where] .. " not seen yet on " .. table.concat(names, ", "))
		end
	end
	if #missing == 0 then
		return #characters .. " characters, all bags, banks and mailboxes known."
	end
	return table.concat(missing, "   ·   ")
end

function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end

	local characters = GetCharacters()
	if selected then
		local found
		for _, character in ipairs(characters) do
			if character.realm == selected.realm and character.name == selected.name then
				found = character
			end
		end
		if not found then
			selected = nil
		end
		characters = found and { found } or characters
	end
	RenderSidebar(GetCharacters())

	for _, tab in ipairs(locationTabs) do
		tab:SetSelected(tab.key == location)
	end
	for _, chip in ipairs(categoryChips) do
		chip:SetSelected(chip.key == category)
	end
	local view = GetView()
	for _, button in ipairs(viewButtons) do
		button:SetSelected(button.key == view)
	end
	infoText:SetText(DescribeFreshness(characters))
	-- Only for your own bags: the Sell list is what you can sell now, here.
	local viewingMe = not selected
		or (selected.realm == ns.inventory.GetRealm() and selected.name == ns.inventory.GetPlayer())
	sellButton:SetShown(ns:IsModuleEnabled("sellList") and viewingMe)

	local items = CollectItems(characters)
	local shown = Filter(items)

	pool:ReleaseAll()
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local height
	if #shown == 0 then
		local empty = pool:Acquire("empty", function()
			local text = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
			text:SetJustifyH("LEFT")
			return text
		end)
		if query ~= "" then
			empty:SetText(string.format("No items match \"%s\".", query))
		elseif selected and location ~= "all" and not characters[1].data[location] then
			empty:SetText(string.format("%s not seen yet on %s: open it once on that character.",
				ns.inventory.LOCATION_LABELS[location], characters[1].name))
		else
			empty:SetText("Nothing here.")
		end
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, -PAD - 4)
		height = 60
	elseif view == "grid" then
		height = RenderGrid(content, shown, width)
	else
		height = RenderList(content, shown, width)
	end
	content:SetHeight(height)
	scroll:SetScroll(scroll:GetVerticalScroll())

	local prices = ns.auctionator
	local valued = prices and prices.ValuesInventories and prices.ValuesInventories()
	local total, value, auction = 0, 0, valued and 0 or nil
	for _, item in ipairs(shown) do
		total = total + item.count
		value = value + (item.price or 0) * item.count
		if valued then
			auction = auction + (prices.AuctionValue(item.id) or 0) * item.count
		end
	end
	footerLeft:SetText(string.format("%d items  ·  %s in total", #shown, BreakUpLargeNumbers and BreakUpLargeNumbers(total) or total))
	if auction then
		footerRight:SetText("Auction house  |cffffffff" .. RoughGold(auction) .. "|r   ·   Vendor  " .. Money(value))
	else
		footerRight:SetText("Vendor value  " .. Money(value))
	end
end

-- Re-render once, soon: data and item info arrive in bursts.
local function RequestRender()
	if renderPending or not (frame and frame:IsShown()) then
		return
	end
	renderPending = true
	C_Timer.After(0.2, Render)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateBrowser()
	frame = UI.CreateWindow("NraKitInventoryFrame", "Inventory", WIDTH, HEIGHT, SIDEBAR_WIDTH, "inventory")
	local body = frame.body

	sidebarScroll = UI.CreateScrollArea(frame.sidebar)
	sidebarScroll:SetPoint("TOPLEFT", PAD, -PAD)
	sidebarScroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	-- Location tabs, view toggle and search
	local anchor
	for _, where in ipairs({ "all", "bags", "bank", "mail", "equipped" }) do
		local tab = UI.CreateFlatButton(body, where == "all" and "All" or ns.inventory.LOCATION_LABELS[where], 24)
		tab.key = where
		tab:SetScript("OnClick", function(self)
			location = self.key
			scroll:SetScroll(0)
			Render()
		end)
		if anchor then
			tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			tab:SetPoint("TOPLEFT", PAD, -PAD)
		end
		anchor = tab
		table.insert(locationTabs, tab)
	end

	searchBox = UI.CreateSearchBox(body, 170, function(text)
		query = text
		scroll:SetScroll(0)
		Render()
	end)
	searchBox:SetPoint("TOPRIGHT", -PAD, -PAD - 1)

	local listButton = UI.CreateFlatButton(body, "List", 24)
	listButton:SetPoint("RIGHT", searchBox, "LEFT", -14, 0)
	local gridButton = UI.CreateFlatButton(body, "Grid", 24)
	gridButton:SetPoint("RIGHT", listButton, "LEFT", -2, 0)
	for key, button in pairs({ grid = gridButton, list = listButton }) do
		button.key = key
		button:SetScript("OnClick", function(self)
			SetView(self.key)
			scroll:SetScroll(0)
			Render()
		end)
		table.insert(viewButtons, button)
	end

	-- Category chips
	anchor = nil
	for _, info in ipairs(CATEGORIES) do
		local chip = UI.CreateFlatButton(body, info.label, 20)
		chip.key = info.key
		chip:SetScript("OnClick", function(self)
			category = self.key
			scroll:SetScroll(0)
			Render()
		end)
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", PAD, -PAD - 32)
		end
		anchor = chip
		table.insert(categoryChips, chip)
	end

	-- The Sell list (its own tab), while that feature is on.
	sellButton = UI.CreateFlatButton(body, "What can I sell?", 20)
	sellButton:SetPoint("TOPRIGHT", -PAD, -PAD - 32)
	sellButton:SetScript("OnClick", function()
		UI.ShowTab("sell")
	end)
	sellButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Sell list", "What in your bags is worth selling, most valuable first.")
	end)
	sellButton:SetScript("OnLeave", GameTooltip_Hide)

	infoText = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	infoText:SetPoint("TOPLEFT", PAD + 2, -PAD - 62)
	infoText:SetPoint("RIGHT", -PAD, 0)
	infoText:SetJustifyH("LEFT")
	infoText:SetWordWrap(false)

	local topLine = body:CreateTexture(nil, "BORDER")
	topLine:SetColorTexture(unpack(UI.EDGE))
	topLine:SetPoint("TOPLEFT", 0, -TOP_HEIGHT)
	topLine:SetPoint("TOPRIGHT", 0, -TOP_HEIGHT)
	topLine:SetHeight(1)

	-- Items
	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - SIDEBAR_WIDTH - 15)

	-- Footer
	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerLeft = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footerLeft:SetPoint("LEFT", PAD, 0)
	footerRight = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footerRight:SetPoint("RIGHT", -PAD, 0)

	frame:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		Render()
	end)
	frame:HookScript("OnHide", function(self)
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end)
	frame:SetScript("OnEvent", RequestRender)
	ns.inventory.onChanged = RequestRender

	-- Start on the character you're playing.
	selected = { realm = ns.inventory.GetRealm(), name = ns.inventory.GetPlayer() }
end

function ns:OpenInventoryBrowser()
	if not ns:IsModuleEnabled("inventoryTracker") then
		ns:Print("Turn on Inventory tracker first (/nra).")
		return
	end
	if not frame then
		CreateBrowser()
	end
	frame:SetShown(not frame:IsShown())
end

-- Key binding (Bindings.xml).
_G["BINDING_NAME_NRAKIT_INVENTORY_BROWSER"] = "Open the inventory browser"
function NraKit_ToggleInventoryBrowser()
	ns:OpenInventoryBrowser()
end

UI.RegisterTab({
	key = "inventory", label = "Inventory", menuLabel = "Inventory", order = 2, frameName = "NraKitInventoryFrame",
	open = function()
		ns:OpenInventoryBrowser()
	end,
	module = "inventoryTracker",
})
