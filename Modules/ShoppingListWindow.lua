local _, ns = ...

-- The NraKit Shopping List tab (/nra shop): everything you're shopping for to craft, added a
-- recipe at a time (right-click a recipe, Add to NraKit Shopping List; AuctionatorPrices.lua).
-- Each row: the item, what it's for, the amount (type it, or - and +), the price of one and
-- of them all ("vendor" when a vendor sells it), how many you have over your characters
-- (hover for who), and remove. Right-click a row for more.
--
-- The footer has the total, Clear list (asks first) and Search at AH: Auctionator keeps a copy
-- ("NraKit Shopping List") while you're away from the auction house; at it, that button
-- writes it and searches.

local UI = ns.UI
local prices = ns.auctionator
local shopping = prices.shopping
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 40
local TOP_HEIGHT = 30
local FOOTER_HEIGHT = 36
local VENDOR_TAG = "  |cff999999vendor|r"

-- Columns, from the right edge of a row: { right offset, width }.
local REMOVE_RIGHT = -8
local HAVE_RIGHT, HAVE_WIDTH = -40, 70
local TOTAL_RIGHT, TOTAL_WIDTH = -118, 110
local EACH_RIGHT, EACH_WIDTH = -236, 100
local AMOUNT_RIGHT, AMOUNT_WIDTH = -348, 92

local HELP = "Add what a recipe needs:\n"
	.. "  - right-click a recipe link in chat\n"
	.. "  - right-click a recipe in your profession window, or use its Shopping list button\n"
	.. "then pick |cffffd100Add to NraKit Shopping List|r. Each adds one craft's reagents.\n\n"
	.. "Auctionator gets a copy, \"NraKit Shopping List\", in its Shopping tab."

local frame, scroll, footerTotal, searchButton, clearButton
local pool = UI.CreatePool()
local renderPending = false
local editing -- the amount box being typed in

local Render

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function QualityColor(itemID)
	local quality = select(3, C_Item.GetItemInfo(itemID))
	local color = quality and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(UI.TEXT)
end

-- "for Green Iron Bracers x2, Copper Chain Belt"
function shopping.ForText(entry)
	local names = {}
	for name, count in pairs(entry.crafts or {}) do
		table.insert(names, count > 1 and (name .. " x" .. count) or name)
	end
	table.sort(names)
	if #names == 0 then
		return ""
	end
	return "for " .. table.concat(names, ", ")
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function OpenRowMenu(row)
	local entry = row.entry
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(C_Item.GetItemNameByID(entry.id) or ("Item " .. entry.id))
		root:CreateButton("Copy Wowhead link", function()
			ns.wowheadLink.Show("item", entry.id)
		end)
		root:CreateDivider()
		root:CreateButton("Remove from the list", function()
			shopping.Remove(entry.id)
		end)
	end)
end

local function OnRowClick(self, button)
	if button == "RightButton" then
		OpenRowMenu(self)
	elseif IsModifiedClick() then
		local _, link = C_Item.GetItemInfo(self.entry.id)
		if link then
			HandleModifiedItemClick(link)
		end
	end
end

local function OnRowEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.entry.id)
	GameTooltip:AddLine("Shift-click to link, right-click for more", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function OnHaveEnter(self)
	local holders = self.holders
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, "You have " .. (self.total or 0))
	if holders then
		for _, holder in ipairs(holders) do
			local r, g, b = ns.inventory.ClassColor(holder.class)
			GameTooltip:AddDoubleLine(holder.label, string.format("%d (%s)", holder.total, holder.where), r, g, b, 1, 1, 1)
		end
	else
		GameTooltip_AddNormalLine(GameTooltip, "In your bags and bank. Turn on Inventory Tracker to count all your characters.", true)
	end
	GameTooltip:Show()
end

local function ApplyAmount(box)
	local row = box.row
	editing = nil
	if row and row.entry then
		local amount = tonumber(box:GetText())
		if amount and amount >= 1 and amount ~= row.entry.amount then
			shopping.SetAmount(row.entry.id, amount) -- redraws
			return
		end
	end
	Render()
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
		row.icon:SetSize(30, 30)
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(16, 16)
		row.remove:SetPoint("RIGHT", REMOVE_RIGHT, 0)
		row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
		row.remove:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
		row.remove:SetScript("OnClick", function(self)
			shopping.Remove(self:GetParent().entry.id)
		end)
		row.remove:SetScript("OnEnter", function(self)
			UI.ShowTooltip(self, "Remove from the list")
		end)
		row.remove:SetScript("OnLeave", GameTooltip_Hide)

		row.have = CreateFrame("Frame", nil, row)
		row.have:SetSize(HAVE_WIDTH, ROW_HEIGHT)
		row.have:SetPoint("RIGHT", HAVE_RIGHT, 0)
		row.have:EnableMouse(true)
		row.have:SetScript("OnEnter", OnHaveEnter)
		row.have:SetScript("OnLeave", GameTooltip_Hide)
		row.have.text = MakeLabel(row.have, "", "GameFontHighlightSmall")
		row.have.text:SetPoint("RIGHT")
		row.have.text:SetJustifyH("RIGHT")

		row.total = MakeLabel(row, "", "GameFontHighlight")
		row.total:SetPoint("RIGHT", TOTAL_RIGHT, 0)
		row.total:SetWidth(TOTAL_WIDTH)
		row.total:SetJustifyH("RIGHT")
		row.each = MakeLabel(row, "", "GameFontHighlightSmall")
		row.each:SetPoint("RIGHT", EACH_RIGHT, 0)
		row.each:SetWidth(EACH_WIDTH)
		row.each:SetJustifyH("RIGHT")

		row.plus = UI.CreateFlatButton(row, "+", 20)
		row.plus:SetWidth(20)
		row.plus:SetPoint("RIGHT", AMOUNT_RIGHT, 0)
		row.plus:SetScript("OnClick", function(self)
			local entry = self:GetParent().entry
			shopping.SetAmount(entry.id, entry.amount + (IsShiftKeyDown() and 10 or 1))
		end)
		row.amount = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
		row.amount:SetSize(40, 20)
		row.amount:SetPoint("RIGHT", row.plus, "LEFT", -6, 0)
		row.amount:SetAutoFocus(false)
		row.amount:SetNumeric(true)
		row.amount:SetMaxLetters(5)
		row.amount:SetJustifyH("CENTER")
		row.amount.row = row
		row.amount:SetScript("OnEditFocusGained", function(self)
			editing = self
		end)
		row.amount:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
		end)
		row.amount:SetScript("OnEscapePressed", function(self)
			self:SetText(tostring(self.row.entry.amount))
			self:ClearFocus()
		end)
		row.amount:SetScript("OnEditFocusLost", ApplyAmount)
		row.minus = UI.CreateFlatButton(row, "-", 20)
		row.minus:SetWidth(20)
		row.minus:SetPoint("RIGHT", row.amount, "LEFT", -6, 0)
		row.minus:SetScript("OnClick", function(self)
			local entry = self:GetParent().entry
			shopping.SetAmount(entry.id, math.max(1, entry.amount - (IsShiftKeyDown() and 10 or 1)))
		end)

		row.name = MakeLabel(row, "")
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
		row.name:SetPoint("RIGHT", row.minus, "LEFT", -12, 0)
		row.name:SetWordWrap(false)
		row.note = MakeLabel(row, "", "GameFontDisableSmall")
		row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
		row.note:SetPoint("RIGHT", row.minus, "LEFT", -12, 0)
		row.note:SetWordWrap(false)
		return row
	end)
end

-- Fills a row; returns its total (nil without a price).
local function FillRow(row, entry, index)
	row.entry = entry
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id) or 134400)
	local unit, vendor = prices.Unit(entry.id)
	row.name:SetText((C_Item.GetItemNameByID(entry.id) or ("Item " .. entry.id)) .. (vendor and VENDOR_TAG or ""))
	row.name:SetTextColor(QualityColor(entry.id))
	row.note:SetText(shopping.ForText(entry))
	row.amount:SetText(tostring(entry.amount))
	if unit then
		row.each:SetText(prices.MoneyText(unit))
		row.each:SetTextColor(unpack(UI.TEXT))
		row.total:SetText(prices.MoneyText(unit * entry.amount))
		row.total:SetTextColor(1, 1, 1)
	else
		row.each:SetText("")
		row.total:SetText("no price")
		row.total:SetTextColor(unpack(UI.TEXT_DIM))
	end
	local have, holders = prices.Have(entry.id)
	row.have.total, row.have.holders = have, holders
	row.have.text:SetText("have " .. have)
	if have >= entry.amount then
		row.have.text:SetTextColor(0.3, 1, 0.3)
	else
		row.have.text:SetTextColor(unpack(UI.TEXT_DIM))
	end
	return unit and unit * entry.amount
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

local function UpdateSearchButton()
	local atAH = prices.IsAuctionHouseOpen()
	searchButton:SetEnabled(atAH and #shopping.GetData().items > 0)
	searchButton.text:SetTextColor(unpack(atAH and UI.GOLD or UI.TEXT_DIM))
end

function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local items = shopping.GetData().items
	UpdateSearchButton()
	clearButton:SetShown(#items > 0)
	if #items == 0 then
		content:SetHeight(Message(content, "Your NraKit Shopping List is empty.\n\n" .. HELP, -PAD - 4) + PAD)
		footerTotal:SetText("")
		return
	end
	local y, sum, unpriced = -6, 0, 0
	for index, entry in ipairs(items) do
		local row = AcquireRow(content)
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
		local total = FillRow(row, entry, index)
		if total then
			sum = sum + total
		else
			unpriced = unpriced + 1
		end
		y = y - ROW_HEIGHT
	end
	content:SetHeight(-y + PAD)
	scroll:SetScroll(scroll:GetVerticalScroll())
	local text = string.format("%d %s   Total  %s", #items, #items == 1 and "item" or "items", prices.MoneyText(sum))
	if unpriced > 0 then
		text = text .. string.format("  |cff999999(+%d without a price)|r", unpriced)
	end
	footerTotal:SetText(text)
end
shopping.Render = Render

-- Redraws soon, but not under the amount being typed.
local function RequestRender()
	if renderPending or editing or not (frame and frame:IsShown()) then
		return
	end
	renderPending = true
	C_Timer.After(0.2, Render)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function ConfirmClear()
	StaticPopupDialogs.NRAKIT_CLEAR_SHOPPING_LIST = StaticPopupDialogs.NRAKIT_CLEAR_SHOPPING_LIST or {
		text = "Clear your NraKit Shopping List?",
		button1 = YES,
		button2 = NO,
		OnAccept = function()
			shopping.Clear()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopup_Show("NRAKIT_CLEAR_SHOPPING_LIST")
end

local function ColumnTitle(parent, text, right, width, justify)
	local title = MakeLabel(parent, text, "GameFontDisableSmall")
	title:SetPoint("RIGHT", right - PAD, 0)
	title:SetWidth(width)
	title:SetJustifyH(justify or "RIGHT")
	return title
end

local function CreateWindow()
	frame = UI.CreateWindow("NraKitShoppingListFrame", "Shopping list", WIDTH, HEIGHT, 0, "shopping")
	local body = frame.body

	-- Column titles, over the rows' columns.
	local top = CreateFrame("Frame", nil, body)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT", -13, 0)
	top:SetHeight(TOP_HEIGHT)
	UI.AddLine(top, "BOTTOM")
	local itemTitle = MakeLabel(top, "NraKit Shopping List", "GameFontNormal")
	itemTitle:SetPoint("LEFT", PAD + 8, 0)
	ColumnTitle(top, "Amount", AMOUNT_RIGHT, AMOUNT_WIDTH, "CENTER")
	ColumnTitle(top, "Each", EACH_RIGHT, EACH_WIDTH)
	ColumnTitle(top, "Total", TOTAL_RIGHT, TOTAL_WIDTH)
	ColumnTitle(top, "Have", HAVE_RIGHT, HAVE_WIDTH)

	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - 15)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerTotal = MakeLabel(footer, "", "GameFontHighlight")
	footerTotal:SetPoint("LEFT", PAD, 0)

	searchButton = UI.CreateFlatButton(footer, "Search at AH", 24)
	searchButton:SetPoint("RIGHT", -PAD, 0)
	searchButton:SetMotionScriptsWhileDisabled(true)
	searchButton:SetScript("OnClick", function()
		shopping.Sync(true)
	end)
	searchButton:SetScript("OnEnter", function(self)
		if prices.IsAuctionHouseOpen() then
			UI.ShowTooltip(self, "Search at AH", "Search for everything on the list in Auctionator's Shopping tab.")
		else
			UI.ShowTooltip(self, "Search at AH", "Works at the auction house. Auctionator already has the list: \""
				.. prices.SHOPPING_LIST .. "\" in its Shopping tab.")
		end
	end)
	searchButton:SetScript("OnLeave", GameTooltip_Hide)

	clearButton = UI.CreateFlatButton(footer, "Clear list", 24)
	clearButton:SetPoint("RIGHT", searchButton, "LEFT", -8, 0)
	clearButton:SetScript("OnClick", ConfirmClear)

	local events = CreateFrame("Frame", nil, frame)
	events:SetScript("OnEvent", RequestRender)
	frame:HookScript("OnShow", function()
		for _, event in ipairs({ "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ITEM_DATA_LOAD_RESULT" }) do
			events:RegisterEvent(event)
		end
		Render()
	end)
	frame:HookScript("OnHide", function()
		events:UnregisterAllEvents()
		editing = nil
	end)
	shopping.onChanged = Render
end

-- Toggles the window (or just shows it, with `show`).
function ns:OpenShoppingList(show)
	if not frame then
		CreateWindow()
	end
	if show then
		frame:Show()
		Render()
	else
		frame:SetShown(not frame:IsShown())
	end
end

UI.RegisterTab({
	key = "shopping", label = "Shopping list", menuLabel = "Shopping list", order = 8, frameName = "NraKitShoppingListFrame",
	open = function()
		ns:OpenShoppingList(true)
	end,
	module = "auctionatorPrices",
})

ns:AddOptionsButton("auctionatorPrices", "Open shopping list", "The NraKit Shopping List (/nra shop).", function()
	ns:OpenShoppingList(true)
end)
