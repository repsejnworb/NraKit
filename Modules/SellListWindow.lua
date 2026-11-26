local _, ns = ...

-- The Sell list tab (SellList.lua has the data): your bags' items worth selling, the most
-- valuable first. Columns: count, auction price of one, at the auction house (all of them)
-- and at a vendor; the better of the two is bright. Click a column title to sort by it.
-- Groups below "To sell" fold: soulbound (vendor only), your bank, and what you keep.
--
-- Click an item at the auction house to pick it up (then drop it in the sell slot),
-- shift-click to link it, right-click to keep it off the list.

local UI = ns.UI
local sell = ns.sellList
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 38
local GROUP_HEIGHT = 28
local TOP_HEIGHT = 30
local FOOTER_HEIGHT = 36

-- Columns, from the right edge of a row: { right offset, width }.
local VENDOR_RIGHT, VENDOR_WIDTH = -8, 96
local AH_RIGHT, AH_WIDTH = -112, 110
local EACH_RIGHT, EACH_WIDTH = -230, 96
local COUNT_RIGHT, COUNT_WIDTH = -334, 50

local GROUPS = {
	{ key = "sell", label = "To sell" },
	{ key = "vendor", label = "Vendor only", note = "soulbound: they can't go on the auction house" },
	{ key = "bank", label = "In your bank", note = "take them out to sell them" },
	{ key = "kept", label = "Kept", note = "you keep these off the list: right-click one to list it again" },
}

local frame, scroll, footerText, footerNote
local sortTitles = {}
local pool = UI.CreatePool()
local renderPending = false

local Render

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
		root:CreateButton("Copy Wowhead link", function()
			ns.wowheadLink.Show("item", item.id)
		end)
	end)
end

local function OnRowClick(self, button)
	local item = self.item
	if button == "RightButton" then
		OpenRowMenu(self)
	elseif IsModifiedClick() then
		local link = item.link or select(2, C_Item.GetItemInfo(item.id))
		if link then
			HandleModifiedItemClick(link)
		end
	elseif sell.IsAuctionHouseOpen() and item.bag and not InCombatLockdown() then
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
	if item.age and item.age > sell.STALE_DAYS then
		GameTooltip:AddLine(string.format("Auction price last seen %d days ago: it may have changed.", item.age), 1, 0.6, 0.2, true)
	end
	if item.bag and sell.IsAuctionHouseOpen() then
		GameTooltip:AddLine("Click to pick it up, then drop it in the auction house's sell slot.", 0.5, 0.5, 0.5, true)
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
local function NoteText(item)
	local parts = {}
	if item.best == "vendor" and item.ahTotal then
		table.insert(parts, "|cffffd100a vendor pays more|r")
	elseif item.best == "vendor" and sell.HasAuctionator() and not item.bound then
		table.insert(parts, "no auction price")
	end
	if item.age and item.age > sell.STALE_DAYS then
		table.insert(parts, string.format("|cffff9933price %d days old|r", item.age))
	end
	if item.disenchant then
		table.insert(parts, "disenchants for ~" .. Money(item.disenchant))
	end
	return table.concat(parts, "  ·  ")
end

local function FillRow(row, item, index)
	row.item = item
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.icon:SetTexture(item.icon or 134400)
	row.icon:SetDesaturated(sell.IsKept(item.id))
	row.name:SetText(item.name or ("Item " .. item.id))
	row.name:SetTextColor(QualityColor(item.quality))
	row.note:SetText(NoteText(item))
	row.count:SetText(item.count > 1 and ("x" .. item.count) or "")
	row.count:SetTextColor(unpack(UI.TEXT))
	local stale = item.age and item.age > sell.STALE_DAYS
	row.each:SetText(item.each and Money(item.each) or "")
	row.each:SetTextColor(unpack(stale and UI.TEXT_DIM or UI.TEXT))
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

function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	UpdateSortTitles()
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local groups = sell.Collect()
	local y = -6

	for _, group in ipairs(GROUPS) do
		local items = groups[group.key]
		if #items > 0 or group.key == "sell" then
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
						or "Nothing in your bags worth selling (or it's all kept or below your minimum)."
					y = y - Message(content, text, y - 2)
				end
				for index, item in ipairs(items) do
					local row = AcquireRow(content)
					row:SetWidth(width)
					row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
					FillRow(row, item, index)
					y = y - ROW_HEIGHT
				end
				y = y - 8
			end
		end
	end
	content:SetHeight(-y + PAD)
	scroll:SetScroll(scroll:GetVerticalScroll())

	footerText:SetText(string.format("|cffffffff~%s|r at the auction house (%d items)   ·   %s at vendors",
		Money(groups.sellTotal), #groups.sell, Money(groups.vendorTotal)))
	footerNote:SetText(sell.HasAuctionator() and "" or "Vendor prices only: Auctionator adds auction house prices")
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
local function SortTitle(parent, text, key, right, width, justify)
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
		UI.ShowTooltip(self, "Sort by " .. text:lower(), "Click again to turn the order around.")
	end)
	title:SetScript("OnLeave", GameTooltip_Hide)
	table.insert(sortTitles, title)
	return title
end

local function CreateWindow()
	frame = UI.CreateWindow("NraKitSellListFrame", "Sell list", WIDTH, HEIGHT, 0, "sell")
	local body = frame.body

	local top = CreateFrame("Frame", nil, body)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT", -13, 0)
	top:SetHeight(TOP_HEIGHT)
	UI.AddLine(top, "BOTTOM")
	local itemTitle = SortTitle(top, "Item", "name", 0, 60, "LEFT")
	itemTitle:ClearAllPoints()
	itemTitle:SetPoint("LEFT", PAD + 30, 0)
	SortTitle(top, "Count", "count", COUNT_RIGHT, COUNT_WIDTH)
	SortTitle(top, "Each", "each", EACH_RIGHT, EACH_WIDTH)
	SortTitle(top, "Auction house", "ah", AH_RIGHT, AH_WIDTH)
	SortTitle(top, "Vendor", "vendor", VENDOR_RIGHT, VENDOR_WIDTH)
	local valueTitle = SortTitle(top, "Value", "value", 0, 60, "LEFT")
	valueTitle:ClearAllPoints()
	valueTitle:SetPoint("LEFT", itemTitle.text, "RIGHT", 16, 0)

	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - 15)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerText = MakeLabel(footer, "", "GameFontHighlight")
	footerText:SetPoint("LEFT", PAD, 0)
	footerNote = MakeLabel(footer, "", "GameFontDisableSmall")
	footerNote:SetPoint("RIGHT", -PAD, 0)
	footerNote:SetJustifyH("RIGHT")

	local events = CreateFrame("Frame", nil, frame)
	events:SetScript("OnEvent", RequestRender)
	frame:HookScript("OnShow", function()
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
			events:RegisterEvent(event)
		end
		Render()
	end)
	frame:HookScript("OnHide", function()
		events:UnregisterAllEvents()
		frame.docked = nil
	end)
	sell.onChanged = Render
end

-- Shows the list; beside `dockTo` (the auction house) if given.
function sell.ShowWindow(dockTo)
	if not frame then
		CreateWindow()
	end
	frame:Show()
	if dockTo then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 4, 0)
		frame.docked = true
	end
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

-- The auction house closed: a list opened beside it closes with it.
function sell.Undock()
	if frame and frame.docked then
		frame:Hide()
		UI.RestorePosition(frame)
	end
end

UI.RegisterTab({
	key = "sell", label = "Sell list", menuLabel = "Sell list", order = 9, frameName = "NraKitSellListFrame",
	open = function()
		ns:OpenSellList()
	end,
	module = "sellList",
})
