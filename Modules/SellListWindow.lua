local _, ns = ...

-- The Sell List tab (SellList.lua has the data): your bags' items worth selling, the most
-- valuable first. Columns: count, at a vendor, the auction price of one and at the auction
-- house (all of them, last: it's the one you look for); the better of vendor and auction is
-- bright. Click a column title to sort by it. Groups below "To sell" fold: soulbound (vendor
-- only), your bank, and what you keep.
--
-- At the auction house: click an item to pick it up (then drop it in the sell slot), or
-- Alt+click (Auctionator's own shortcut) to put it in Auctionator's Selling tab: the row hands
-- the click to HandleModifiedItemClick with the item's bag slot, the same as a click in your
-- bags, and Auctionator's own hook does the rest. Shift-click links, right-click keeps it off.
--
-- Prices aren't redrawn by themselves (rows would jump under the mouse): while it's open, the
-- shown items' auction prices are checked now and then, and a fresh scan says "prices have
-- changed" by the refresh button.

local UI = ns.UI
local sell = ns.sellList
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 38
local GROUP_HEIGHT = 28
local TOOLBAR_HEIGHT = 30
local TOP_HEIGHT = 30
local FOOTER_HEIGHT = 36

-- Columns, from the right edge of a row: { right offset, width }.
local AH_RIGHT, AH_WIDTH = -8, 110
local GAIN_RIGHT, GAIN_WIDTH = -126, 96
local VENDOR_RIGHT, VENDOR_WIDTH = -230, 96
local EACH_RIGHT, EACH_WIDTH = -334, 96
local COUNT_RIGHT, COUNT_WIDTH = -438, 50
local CHECK_SECONDS = 2 -- how often the shown prices are compared with Auctionator's

-- Groups, in the order they're listed (at a merchant the vendor group comes first).
local GROUPS = {
	ah = { key = "ah", label = "To Sell: Auction House" },
	vendor = { key = "vendor", label = "To Sell: Vendor" },
	goals = { key = "goals", label = "For Your Farm Goals", note = "still farming these: they move to To Sell when the goal is done" },
	kept = { key = "kept", label = "Kept", note = "you keep these off the list: right-click one to list it again" },
}
local ORDER = { "ah", "vendor", "goals", "kept" }
local MERCHANT_ORDER = { "vendor", "ah", "goals", "kept" }

-- Bank and mail items (the Bank and Mail switches): a badge on the icon and a row tint of
-- their own (the bank warm, like a vault; mail cool blue). At the bank or mailbox: click to take.
local PLACES = {
	bank = { label = "Bank", icon = "Interface\\Minimap\\Tracking\\Banker", tint = { 1, 0.7, 0.25, 0.08 }, color = "ffd9a54c",
		tag = "In Bank" },
	mail = { label = "Mail", icon = "Interface\\Minimap\\Tracking\\Mailbox", tint = { 0.35, 0.55, 1, 0.08 }, color = "ff66a6ff",
		tag = "In Mail" },
}

local frame, scroll, footerText, footerNote, refreshButton, autoOpenButton
local placeChips = {} -- the Bank and Mail switches
local sortTitles = {}
local shownItems = {} -- the items on screen, to notice when their auction prices change
local pricesChanged = false
local pool = UI.CreatePool()
local renderPending = false

local Render, UpdateFooterNote, NoteLines

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function Money(copper)
	return GetMoneyString and GetMoneyString(copper, true) or tostring(copper)
end

local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(UI.TEXT)
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function OpenRowMenu(row)
	local item = row.item
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(item.name or ("Item " .. item.id))
		if sell.IsKept(item.id) then
			root:CreateButton("List it again", function()
				sell.SetKept(item.id, false)
			end)
		else
			root:CreateButton("Keep, don't list", function()
				sell.SetKept(item.id, true)
			end)
		end
		root:CreateButton("Copy Wowhead Link", function()
			ns.wowheadLink.Show("item", item.id)
		end)
	end)
end

local function OnRowClick(self, button)
	local item = self.item
	-- A bank or mail item, while you're there: take it (Shift: all that fits, no asking).
	if item.where and sell.IsPlaceOpen(item.where) and button == "LeftButton" and not IsAltKeyDown() then
		if IsShiftKeyDown() then
			sell.TakeAllThatFits(item)
		else
			sell.AskTake(item, self)
		end
		return
	end
	if button == "RightButton" then
		OpenRowMenu(self)
	elseif IsModifiedClick() then
		local link = item.link or select(2, C_Item.GetItemInfo(item.id))
		if link then
			-- With its bag slot, like a click in your bags: Auctionator's Alt+click hook
			-- puts it in its Selling tab.
			local location = item.bag and type(ItemLocation) == "table"
				and ItemLocation:CreateFromBagAndSlot(item.bag, item.slot) or nil
			HandleModifiedItemClick(link, location)
		end
	elseif (sell.IsAuctionHouseOpen() or sell.IsMerchantOpen()) and item.bag and not InCombatLockdown() then
		C_Container.PickupContainerItem(item.bag, item.slot)
	end
end

local function OnRowEnter(self)
	local item = self.item
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if item.bag then
		GameTooltip:SetBagItem(item.bag, item.slot)
	elseif item.link then
		GameTooltip:SetHyperlink(item.link)
	else
		GameTooltip:SetItemByID(item.id)
	end
	for _, line in ipairs(NoteLines(item)) do
		GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
	end
	if item.bag and sell.IsAuctionHouseOpen() then
		GameTooltip:AddLine("Click to pick it up, then drop it in the auction house's sell slot.", 0.5, 0.5, 0.5, true)
		if sell.HasAuctionator() then
			GameTooltip:AddLine("Alt-click to put it in Auctionator's Selling tab.", 0.5, 0.5, 0.5, true)
		end
	elseif item.bag and sell.IsMerchantOpen() then
		GameTooltip:AddLine("Click to pick it up, then click the merchant's window to sell it.", 0.5, 0.5, 0.5, true)
	elseif item.where and sell.IsPlaceOpen(item.where) then
		GameTooltip:AddLine("Click to take it into your bags; Shift-click to take all that fits.", 0.5, 0.5, 0.5, true)
	elseif item.where then
		GameTooltip:AddLine(item.where == "bank" and "In your bank, as last seen. Open your bank to take it."
			or "In your mail, as last seen. Open your mailbox to take it.", 0.5, 0.5, 0.5, true)
	end
	GameTooltip:AddLine("Shift-click to link, right-click to keep it off the list", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function AcquireRow(content)
	return pool:Acquire("row", function()
		local row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", OnRowClick)
		row:SetScript("OnEnter", OnRowEnter)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.place = row:CreateTexture(nil, "OVERLAY")
		row.place:SetSize(16, 16)
		row.place:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -4)
		local function Column(right, width, font)
			local label = MakeLabel(row, "", font or "GameFontHighlight")
			label:SetPoint("RIGHT", right, 0)
			label:SetWidth(width)
			label:SetJustifyH("RIGHT")
			label:SetWordWrap(false)
			return label
		end
		row.vendor = Column(VENDOR_RIGHT, VENDOR_WIDTH)
		row.ah = Column(AH_RIGHT, AH_WIDTH)
		row.gain = Column(GAIN_RIGHT, GAIN_WIDTH)
		row.each = Column(EACH_RIGHT, EACH_WIDTH, "GameFontHighlightSmall")
		row.count = Column(COUNT_RIGHT, COUNT_WIDTH, "GameFontHighlightSmall")
		row.name = MakeLabel(row, "")
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 0)
		row.name:SetPoint("RIGHT", row, "RIGHT", COUNT_RIGHT - COUNT_WIDTH - 10, 0)
		row.name:SetWordWrap(false)
		row.note = MakeLabel(row, "", "GameFontDisableSmall")
		row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 0)
		row.note:SetPoint("RIGHT", row, "RIGHT", COUNT_RIGHT - COUNT_WIDTH - 10, 0)
		row.note:SetWordWrap(false)
		return row
	end)
end

-- The small line under an item's name: why its value is what it is.
-- The short tags under an item's name ("In Mail  ·  6 Days Old"); the row's tooltip spells
-- them out (NoteLines).
local function NoteText(item)
	local parts = {}
	if item.where then
		local place = PLACES[item.where]
		table.insert(parts, "|c" .. place.color .. place.tag .. "|r")
	end
	if item.best == "vendor" and not item.ahTotal and sell.HasAuctionator() and not item.bound then
		table.insert(parts, "No AH Price")
	end
	if item.bound then
		table.insert(parts, "Soulbound")
	end
	if item.best == "ah" and item.age and item.age > sell.STALE_DAYS then
		table.insert(parts, string.format("|cffff9933%d Days Old|r", item.age))
	end
	if item.disenchant then
		table.insert(parts, "Disenchant ~" .. Money(item.disenchant))
	end
	return table.concat(parts, "  ·  ")
end
sell.NoteText = NoteText

-- What the tags mean, in full: { text, r, g, b } lines for the row's tooltip.
function NoteLines(item)
	local lines = {}
	local function Add(text, r, g, b)
		table.insert(lines, { text, r or 0.8, g or 0.8, b or 0.8 })
	end
	if item.best == "vendor" and item.ahTotal then
		Add(string.format("A vendor pays more: %s, the auction house %s.", Money(item.vendorTotal), Money(item.ahTotal)))
	elseif item.best == "vendor" and sell.HasAuctionator() and not item.bound then
		Add("No auction price: Auctionator hasn't seen it at the auction house.")
	end
	if item.age and item.age > sell.STALE_DAYS then
		Add(string.format("Auction price last seen %d days ago: it may have changed.", item.age), 1, 0.6, 0.2)
	end
	if item.disenchant then
		Add("Disenchants for about " .. Money(item.disenchant) .. ".")
	end
	return lines
end
sell.NoteLines = NoteLines

local function FillRow(row, item, index)
	row.item = item
	local place = item.where and PLACES[item.where]
	if place then
		row.bg:SetColorTexture(unpack(place.tint))
	else
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	end
	row.place:SetShown(place ~= nil)
	row.place:SetTexture(place and place.icon or nil)
	row.icon:SetTexture(item.icon or 134400)
	row.icon:SetDesaturated(sell.IsKept(item.id))
	row.icon:SetAlpha(place and 0.75 or 1)
	row.name:SetText(item.name or ("Item " .. item.id))
	row.name:SetTextColor(QualityColor(item.quality))
	row.name:SetAlpha(place and 0.8 or 1)
	row.note:SetText(NoteText(item))
	row.count:SetText(item.count > 1 and ("x" .. item.count) or "")
	row.count:SetTextColor(unpack(UI.TEXT))
	local stale = item.age and item.age > sell.STALE_DAYS
	-- Each: the price of one where its group sells it.
	row.each:SetText(item.groupEach and item.groupEach > 0 and Money(item.groupEach) or "")
	row.each:SetTextColor(unpack(stale and item.best == "ah" and UI.TEXT_DIM or UI.TEXT))
	row.ah:SetText(item.ahTotal and Money(item.ahTotal) or "|cff666666-|r")
	row.vendor:SetText(item.vendorTotal > 0 and Money(item.vendorTotal) or "|cff666666-|r")
	-- The better of the two is bright, the other dim.
	if item.best == "ah" then
		row.ah:SetTextColor(1, 1, 1)
		row.vendor:SetTextColor(unpack(UI.TEXT_DIM))
	else
		row.vendor:SetTextColor(1, 1, 1)
		row.ah:SetTextColor(unpack(UI.TEXT_DIM))
	end
	-- Gain: what the auction house pays over a vendor.
	row.gain:SetText(item.gain and Money(item.gain) or "|cff666666-|r")
	row.gain:SetTextColor(unpack(stale and UI.TEXT_DIM or UI.GOLD))
end

-- A group's heading row: click to fold or open it.
local function AcquireGroupHeader(content)
	return pool:Acquire("group", function()
		local header = CreateFrame("Button", nil, content)
		header:SetHeight(GROUP_HEIGHT)
		local highlight = header:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.04)
		header.toggle = header:CreateTexture(nil, "ARTWORK")
		header.toggle:SetSize(14, 14)
		header.toggle:SetPoint("LEFT", 8, 0)
		header.label = MakeLabel(header, "", "GameFontNormal")
		header.label:SetPoint("LEFT", header.toggle, "RIGHT", 8, 0)
		header.note = MakeLabel(header, "", "GameFontDisableSmall")
		header.note:SetPoint("LEFT", header.label, "RIGHT", 10, 0)
		header.note:SetPoint("RIGHT", -110, 0)
		header.note:SetWordWrap(false)
		header.total = MakeLabel(header, "", "GameFontHighlightSmall")
		header.total:SetPoint("RIGHT", -8, 0)
		header.total:SetJustifyH("RIGHT")
		header:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			sell.SetOpen(self.group, not sell.IsOpen(self.group))
		end)
		UI.AddLine(header, "BOTTOM")
		return header
	end)
end

local function Message(content, text, y)
	local message = pool:Acquire("message", function()
		local fontString = MakeLabel(content, "", "GameFontDisable")
		fontString:SetSpacing(3)
		return fontString
	end)
	message:SetText(text)
	message:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y)
	message:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
	local _, lines = text:gsub("\n", "")
	return (lines + 1) * 17 + 12
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

local function UpdateSortTitles()
	local key, ascending = sell.GetSort()
	for _, title in ipairs(sortTitles) do
		local on = title.key == key
		title.text:SetTextColor(unpack(on and UI.GOLD or UI.TEXT_DIM))
		title.arrow:SetShown(on)
		title.arrow:SetTexture(ascending and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
	end
end

-- The note by the refresh button: prices have changed, or there are no auction prices.
function UpdateFooterNote()
	local taking = sell.TakeStatus and sell.TakeStatus()
	if taking then
		footerNote:SetText(taking)
		footerNote:SetTextColor(unpack(UI.GOLD))
	elseif pricesChanged then
		footerNote:SetText("Prices have changed: refresh")
		footerNote:SetTextColor(unpack(UI.ACCENT))
	else
		footerNote:SetText(sell.HasAuctionator() and "" or "Vendor prices only: Auctionator adds auction house prices")
		footerNote:SetTextColor(unpack(UI.TEXT_DIM))
	end
	refreshButton.icon:SetVertexColor(unpack(pricesChanged and UI.ACCENT or { 1, 1, 1 }))
end

-- Whether any shown item's auction price differs from Auctionator's now.
function sell.PricesChanged()
	for _, item in ipairs(shownItems) do
		local each = sell.AuctionPrice(item.id, item.link)
		if each ~= item.each then
			return true
		end
	end
	return false
end

function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	UpdateSortTitles()
	-- "Automatically Open At: Auction House, Bank"
	local places = {}
	for _, place in ipairs(sell.AUTO_OPEN) do
		if ns:GetOption(place.option) then
			table.insert(places, place.label)
		end
	end
	autoOpenButton.text:SetText("Automatically Open At:  |cffffffff" .. (#places > 0 and table.concat(places, ", ") or "Nowhere") .. "|r")
	autoOpenButton:SetWidth(autoOpenButton.text:GetStringWidth() + 32)
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local groups = sell.Collect()
	local y = -6
	wipe(shownItems)
	pricesChanged = false

	for _, key in ipairs(sell.IsMerchantOpen() and MERCHANT_ORDER or ORDER) do
		local group = GROUPS[key]
		local items = groups[key]
		if #items > 0 or key == "ah" or key == "vendor" then
			local open = sell.IsOpen(group.key)
			local header = AcquireGroupHeader(content)
			header.group = group.key
			header:SetWidth(width)
			header:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
			header.toggle:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
			header.label:SetText(group.label)
			local count = #items == 1 and "1 item" or (#items .. " items")
			header.note:SetText(group.note and (count .. "  ·  " .. group.note) or count)
			local sum = 0
			for _, item in ipairs(items) do
				sum = sum + item.value
			end
			header.total:SetText(sum > 0 and Money(sum) or "")
			y = y - GROUP_HEIGHT - 2
			if open then
				if #items == 0 then
					local text = groups.loading and "Loading item info..."
						or (key == "ah" and "Nothing that sells better at the auction house." or "Nothing that sells better at a vendor.")
					y = y - Message(content, text, y - 2)
				end
				for index, item in ipairs(items) do
					local row = AcquireRow(content)
					row:SetWidth(width)
					row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
					FillRow(row, item, index)
					table.insert(shownItems, item)
					y = y - ROW_HEIGHT
				end
				y = y - 8
			end
		end
	end
	content:SetHeight(-y + PAD)
	scroll:SetScroll(scroll:GetVerticalScroll())

	-- What you can sell now, from your bags; your bank and mail apart.
	local bagsAH, bagsVendor = 0, 0
	for _, item in ipairs(groups.ah) do
		bagsAH = bagsAH + (item.where and 0 or 1)
	end
	for _, item in ipairs(groups.vendor) do
		bagsVendor = bagsVendor + (item.where and 0 or 1)
	end
	local text = string.format("|cffffffff~%s|r at the auction house (%d)   ·   %s at vendors (%d)",
		Money(groups.ahTotal), bagsAH, Money(groups.vendorTotal), bagsVendor)
	if groups.elsewhereTotal > 0 then
		text = text .. "   ·   |cff999999+" .. Money(groups.elsewhereTotal) .. " in bank & mail|r"
	end
	footerText:SetText(text)
	for _, chip in ipairs(placeChips) do
		chip:SetSelected(chip.where == "bags" and sell.ShowsBags() or chip.where ~= "bags" and sell.Shows(chip.where))
		local available = chip.where == "bags" or ns:IsModuleEnabled("inventoryTracker") or sell.IsPlaceOpen(chip.where)
			or sell.AtBankOrMailbox()
		chip:SetEnabled(available)
		chip:SetAlpha(available and 1 or 0.5)
	end
	UpdateFooterNote()
end

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

-- A column title you click to sort by it.
local function SortTitle(parent, text, key, right, width, justify, note)
	local title = CreateFrame("Button", nil, parent)
	title:SetSize(width, TOP_HEIGHT)
	title:SetPoint("RIGHT", right - PAD, 0)
	title.key = key
	title.text = MakeLabel(title, text, "GameFontHighlightSmall")
	title.text:SetPoint(justify == "LEFT" and "LEFT" or "RIGHT", justify == "LEFT" and 14 or 0, 0)
	title.arrow = title:CreateTexture(nil, "OVERLAY")
	title.arrow:SetSize(10, 10)
	title.arrow:SetPoint("RIGHT", title.text, "LEFT", -3, -1)
	title:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		sell.SetSort(self.key)
	end)
	title:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Sort by " .. text:lower(), (note and note .. " " or "") .. "Click again to turn the order around.")
	end)
	title:SetScript("OnLeave", GameTooltip_Hide)
	table.insert(sortTitles, title)
	return title
end

local function CreateWindow()
	frame = UI.CreateWindow("NraKitSellListFrame", "Sell List", WIDTH, HEIGHT, 0, "sell")
	local body = frame.body

	-- Toolbar: open the list by itself at the auction house (the same as the option).
	local toolbar = CreateFrame("Frame", nil, body)
	toolbar:SetPoint("TOPLEFT")
	toolbar:SetPoint("TOPRIGHT")
	toolbar:SetHeight(TOOLBAR_HEIGHT)
	UI.AddLine(toolbar, "BOTTOM")
	-- "Automatically Open At: Auction House": a menu of places to tick.
	autoOpenButton = UI.CreateFlatButton(toolbar, "", 22)
	autoOpenButton:SetPoint("LEFT", PAD, 0)
	autoOpenButton.arrow = autoOpenButton:CreateTexture(nil, "ARTWORK")
	autoOpenButton.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	autoOpenButton.arrow:SetSize(10, 10)
	autoOpenButton.text:ClearAllPoints()
	autoOpenButton.text:SetPoint("LEFT", 10, 0)
	autoOpenButton.arrow:SetPoint("LEFT", autoOpenButton.text, "RIGHT", 4, -2)
	autoOpenButton:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			root:CreateTitle("Automatically Open At (This Character)")
			for _, place in ipairs(sell.AUTO_OPEN) do
				root:CreateCheckbox(place.label, function()
					return ns:GetOption(place.option) == true
				end, function()
					ns:SetSetting(place.option, not ns:GetOption(place.option))
				end)
			end
		end)
	end)
	autoOpenButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Automatically Open At", "Where the Sell List opens by itself, beside the window there. Each character has its own: your bank alt can open it at the bank, your main not.")
	end)
	autoOpenButton:SetScript("OnLeave", GameTooltip_Hide)

	-- Bank and Mail: list those too (Inventory Tracker's data), right of the switches.
	local anchor
	local CHIPS = {
		mail = PLACES.mail,
		bank = PLACES.bank,
		bags = { label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
	}
	for _, where in ipairs({ "mail", "bank", "bags" }) do
		local place = CHIPS[where]
		local chip = UI.CreateFlatButton(toolbar, "", 22)
		chip.where = where
		chip.icon = chip:CreateTexture(nil, "ARTWORK")
		chip.icon:SetSize(16, 16)
		chip.icon:SetPoint("LEFT", 6, 0)
		chip.icon:SetTexture(place.icon)
		chip.text:ClearAllPoints()
		chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
		chip.text:SetText(place.label)
		chip:SetWidth(chip.text:GetStringWidth() + 34)
		if anchor then
			chip:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
		else
			chip:SetPoint("RIGHT", -PAD, 0)
		end
		anchor = chip
		chip:SetMotionScriptsWhileDisabled(true)
		chip:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			sell.Toggle(self.where)
		end)
		chip:SetScript("OnEnter", function(self)
			local title = "Show your " .. self.where
			if sell.AtBankOrMailbox() then
				local here = sell.IsPlaceOpen("bank") and "bank" or "mailbox"
				UI.ShowTooltip(self, title, "At the " .. here .. " the list shows just what's there. Click to "
					.. (sell.ShowsBags() and self.where == "bags" or self.where ~= "bags" and sell.Shows(self.where) and "hide" or "show")
					.. " your " .. self.where .. " for this visit; your settings come back when you leave.")
				return
			end
			if self.where == "bags" then
				UI.ShowTooltip(self, title, "List what's in your bags.")
				return
			end
			if not ns:IsModuleEnabled("inventoryTracker") then
				UI.ShowTooltip(self, title, "Turn on Inventory Tracker to include your bank and mail.")
				return
			end
			local seen = sell.LastSeen(self.where)
			local age = seen and math.floor((time() - seen) / 86400)
			local when = not seen and "Not seen yet: open it once on this character."
				or age == 0 and "As last seen today." or string.format("As last seen %d day%s ago.", age, age == 1 and "" or "s")
			UI.ShowTooltip(self, title, "List what's in your " .. self.where .. " too, marked: you can't sell it from there. " .. when)
		end)
		chip:SetScript("OnLeave", GameTooltip_Hide)
		table.insert(placeChips, chip)
	end

	local top = CreateFrame("Frame", nil, body)
	top:SetPoint("TOPLEFT", 0, -TOOLBAR_HEIGHT - 1)
	top:SetPoint("TOPRIGHT", -13, -TOOLBAR_HEIGHT - 1)
	top:SetHeight(TOP_HEIGHT)
	UI.AddLine(top, "BOTTOM")
	local itemTitle = SortTitle(top, "Item", "name", 0, 60, "LEFT")
	itemTitle:ClearAllPoints()
	itemTitle:SetPoint("LEFT", PAD + 30, 0)
	SortTitle(top, "Count", "count", COUNT_RIGHT, COUNT_WIDTH)
	SortTitle(top, "Each", "each", EACH_RIGHT, EACH_WIDTH)
	SortTitle(top, "Auction House", "ah", AH_RIGHT, AH_WIDTH)
	SortTitle(top, "Vendor", "vendor", VENDOR_RIGHT, VENDOR_WIDTH)
	SortTitle(top, "Gain", "gain", GAIN_RIGHT, GAIN_WIDTH, nil,
		"What the auction house pays over a vendor: the most worth the bother of listing first.")
	local valueTitle = SortTitle(top, "Value", "value", 0, 60, "LEFT")
	valueTitle:ClearAllPoints()
	valueTitle:SetPoint("LEFT", itemTitle.text, "RIGHT", 16, 0)

	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOOLBAR_HEIGHT - TOP_HEIGHT - 2)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - 15)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerText = MakeLabel(footer, "", "GameFontHighlight")
	footerText:SetPoint("LEFT", PAD, 0)
	refreshButton = UI.CreateFlatButton(footer, "", 24)
	refreshButton:SetWidth(24)
	refreshButton:SetPoint("RIGHT", -PAD, 0)
	refreshButton.icon = refreshButton:CreateTexture(nil, "ARTWORK")
	refreshButton.icon:SetAtlas("UI-RefreshButton")
	refreshButton.icon:SetSize(16, 16)
	refreshButton.icon:SetPoint("CENTER")
	refreshButton:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		sell.ClearTakeStatus()
		Render()
	end)
	refreshButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Refresh", "Price and sort the list again, with Auctionator's latest prices.")
	end)
	refreshButton:SetScript("OnLeave", GameTooltip_Hide)
	footerNote = MakeLabel(footer, "", "GameFontNormalSmall")
	footerNote:SetPoint("RIGHT", refreshButton, "LEFT", -8, 0)
	footerNote:SetJustifyH("RIGHT")

	local events = CreateFrame("Frame", nil, frame)
	events:SetScript("OnEvent", RequestRender)
	frame:HookScript("OnShow", function()
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
			events:RegisterEvent(event)
		end
		sell.ClearTakeStatus() -- the last result was about the last time
		Render()
	end)
	frame:HookScript("OnHide", function()
		events:UnregisterAllEvents()
		sell.HidePrompt()
	end)
	-- Now and then: have the auction prices of what's shown changed (a fresh scan)?
	local sinceCheck = 0
	events:SetScript("OnUpdate", function(_, elapsed)
		sinceCheck = sinceCheck + elapsed
		if sinceCheck < CHECK_SECONDS or pricesChanged or not sell.HasAuctionator() then
			return
		end
		sinceCheck = 0
		if sell.PricesChanged() then
			pricesChanged = true
			UpdateFooterNote()
		end
	end)
	sell.onChanged = Render
	sell.onTakeStatus = function()
		if frame:IsShown() then
			UpdateFooterNote()
		end
	end
	sell.onPlaceChanged = function()
		sell.HidePrompt()
		-- Left the bank or mailbox: what was taken there is old news.
		if not sell.AtBankOrMailbox() then
			sell.ClearTakeStatus()
		end
	end
end

function sell.ShowWindow()
	if not frame then
		CreateWindow()
	end
	frame:Show()
	Render()
end

function sell.HideWindow()
	if frame then
		frame:Hide()
	end
end

function sell.IsWindowShown()
	return frame ~= nil and frame:IsShown()
end

UI.RegisterTab({
	key = "sell", label = "Sell List", menuLabel = "Sell List", order = 9, frameName = "NraKitSellListFrame",
	open = function()
		ns:OpenSellList()
	end,
	module = "sellList",
})
