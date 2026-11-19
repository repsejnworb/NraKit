local _, ns = ...

-- The Item lookup window (/nra item <name>): a search box, a bar showing how complete the
-- list of names is (with Pause / Resume, or Check again once it's done), and the matching items (icon, name in its quality colour, type, required
-- level, and how many your characters have if Inventory Tracker is on). Hover for the
-- tooltip; Shift-click links an item in chat, Ctrl-click previews it. The list of names
-- is ItemLookup.lua's.

local UI = ns.UI
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 30
local TOP_HEIGHT = 48
local FOOTER_HEIGHT = 28
local MAX_SHOWN = 200

local frame, searchBox, progressBar, progressButton, scroll, footerLeft
local pool = UI.CreatePool()
local query = ""
local shownIDs = {} -- [id] = true for the rows on screen
local renderPending = false

local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- How many of the item your characters have (Inventory Tracker), or 0.
local function Owned(itemID)
	if not ns:IsModuleEnabled("inventoryTracker") then
		return 0
	end
	local total = 0
	for _, characters in pairs(NraKitDB.inventory or {}) do
		for _, character in pairs(characters) do
			for _, where in ipairs(ns.inventory.LOCATIONS) do
				total = total + (character[where] and character[where][itemID] or 0)
			end
		end
	end
	return total
end

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- The progress bar's text and fill, and the button next to it.
local function UpdateProgress()
	local progress = ns.itemLookup.Progress()
	local text, button
	if progress.done then
		text = string.format("All %s known item names learned", Number(progress.named))
		button = "Check again"
	elseif progress.total then
		text = string.format("%s %s of %s item names", progress.paused and "Paused:" or "Learning", Number(progress.named),
			Number(progress.total))
		button = progress.paused and "Resume" or "Pause"
	else
		text = progress.paused and string.format("Paused: %s item names", Number(progress.named)) or "Finding the game's items..."
		button = progress.paused and "Resume" or "Pause"
	end
	progressBar.text:SetText(text)
	progressBar:SetMinMaxValues(0, math.max(progress.total or 1, 1))
	progressBar:SetValue(progress.done and math.max(progress.total or 1, 1) or progress.named)
	local color = progress.done and { 0.3, 0.6, 0.3 } or progress.paused and UI.GREY or UI.ACCENT
	progressBar:SetStatusBarColor(color[1], color[2], color[3], 0.8)
	progressButton.action = button
	progressButton.text:SetText(button)
	progressButton:SetWidth(progressButton.text:GetStringWidth() + 20)
end

local BUTTON_TIPS = {
	["Pause"] = "Stop learning item names for now (until you resume). Searching still works with the names learned so far.",
	["Resume"] = "Carry on learning item names in the background.",
	["Check again"] = "Ask the server again for the items that had no name yet, like items nobody had discovered. This happens by itself once a day.",
}

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function OnRowEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.itemID)
	GameTooltip:Show()
end

-- Shift-click links it in chat, Ctrl-click previews it, like bag items.
local function OnRowClick(self)
	local link = select(2, C_Item.GetItemInfo(self.itemID))
	if link then
		HandleModifiedItemClick(link)
	end
end

local function AcquireRow(content)
	return pool:Acquire("row", function()
		local row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW_HEIGHT)
		row:SetScript("OnEnter", OnRowEnter)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetScript("OnClick", OnRowClick)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetColorTexture(1, 1, 1, 0.08)
		highlight:SetAllPoints()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.kind:SetJustifyH("LEFT")
		row.kind:SetWordWrap(false)
		row.owned = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.owned:SetPoint("RIGHT", -10, 0)
		row.owned:SetJustifyH("RIGHT")
		row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.level:SetPoint("RIGHT", -90, 0)
		row.level:SetJustifyH("RIGHT")
		return row
	end)
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

local function Message(content, text)
	local message = pool:Acquire("message", function()
		local fontString = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		fontString:SetJustifyH("LEFT")
		return fontString
	end)
	message:SetText(text)
	message:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, -PAD - 4)
	message:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
end

local function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	UpdateProgress()
	pool:ReleaseAll()
	wipe(shownIDs)
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD

	if query == "" then
		Message(content, "Type part of an item's name above.")
		content:SetHeight(60)
		footerLeft:SetText("")
		return
	end
	local matches, total = ns.itemLookup.Search(query, MAX_SHOWN)
	if total == 0 then
		Message(content, string.format("No items match \"%s\".", query))
		content:SetHeight(60)
		footerLeft:SetText("")
		return
	end

	for index, match in ipairs(matches) do
		shownIDs[match.id] = true
		local row = AcquireRow(content)
		row.itemID = match.id
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD - (index - 1) * ROW_HEIGHT)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		local _, itemType, itemSubType, _, icon = C_Item.GetItemInfoInstant(match.id)
		row.icon:SetTexture(icon or 134400)
		row.name:SetText(match.name)
		row.name:SetTextColor(QualityColor(match.quality))
		row.name:SetWidth(width * 0.45)
		row.kind:SetText(itemSubType and itemSubType ~= itemType and (itemType .. " - " .. itemSubType) or itemType or "")
		row.kind:SetPoint("LEFT", row, "LEFT", 38 + width * 0.45 + 12, 0)
		row.kind:SetWidth(width * 0.3)
		-- The required level needs the item loaded; it shows up when it arrives.
		local _, _, _, _, minLevel = C_Item.GetItemInfo(match.id)
		row.level:SetText(minLevel and minLevel > 1 and ("Level " .. minLevel) or "")
		local owned = Owned(match.id)
		row.owned:SetText(owned > 0 and ("|cff40c040You have " .. owned .. "|r") or "")
	end
	content:SetHeight(PAD * 2 + #matches * ROW_HEIGHT)
	scroll:SetScroll(scroll:GetVerticalScroll())

	if total > #matches then
		footerLeft:SetText(string.format("Showing %d of %d matches: type more to narrow it down.", #matches, total))
	else
		footerLeft:SetText(total == 1 and "1 match" or (total .. " matches"))
	end
end

-- Re-render once, soon: names arrive in bursts.
local function RequestRender()
	if renderPending or not (frame and frame:IsShown()) then
		return
	end
	renderPending = true
	C_Timer.After(0.5, Render)
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateWindow()
	frame = UI.CreateWindow("NraKitItemLookupFrame", "Items", WIDTH, HEIGHT, 0, "items")
	local body = frame.body

	searchBox = UI.CreateSearchBox(body, 260, function(text)
		query = text
		scroll:SetScroll(0)
		Render()
	end)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD - 1)

	progressButton = UI.CreateFlatButton(body, "Pause", 22)
	progressButton:SetPoint("TOPRIGHT", -PAD, -PAD)
	progressButton:SetScript("OnClick", function(self)
		if self.action == "Check again" then
			ns.itemLookup.CheckAgain()
		else
			ns.itemLookup.SetPaused(self.action == "Pause")
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		UpdateProgress()
		UI.ShowTooltip(self, self.action, BUTTON_TIPS[self.action])
	end)
	progressButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, self.action, BUTTON_TIPS[self.action])
	end)
	progressButton:SetScript("OnLeave", GameTooltip_Hide)

	progressBar = CreateFrame("StatusBar", nil, body)
	progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	-- A thin line under the text, so the text sits on the dark window, not on the fill.
	progressBar:SetHeight(3)
	progressBar:SetPoint("LEFT", searchBox, "RIGHT", 16, -9)
	progressBar:SetPoint("RIGHT", progressButton, "LEFT", -12, -9)
	local barBg = progressBar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(1, 1, 1, 0.08)
	progressBar.text = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	progressBar.text:SetPoint("BOTTOMLEFT", progressBar, "TOPLEFT", 0, 4)
	progressBar.text:SetPoint("RIGHT", progressBar, "RIGHT")
	progressBar.text:SetJustifyH("LEFT")
	progressBar.text:SetWordWrap(false)
	progressBar.text:SetTextColor(unpack(UI.TEXT))
	-- Kept up to date while the window is open.
	local sinceUpdate = 0
	progressBar:SetScript("OnUpdate", function(_, elapsed)
		sinceUpdate = sinceUpdate + elapsed
		if sinceUpdate >= 1 then
			sinceUpdate = 0
			UpdateProgress()
		end
	end)

	local topLine = body:CreateTexture(nil, "BORDER")
	topLine:SetColorTexture(unpack(UI.EDGE))
	topLine:SetPoint("TOPLEFT", 0, -TOP_HEIGHT)
	topLine:SetPoint("TOPRIGHT", 0, -TOP_HEIGHT)
	topLine:SetHeight(1)

	scroll = UI.CreateScrollArea(body)
	scroll:SetPoint("TOPLEFT", 0, -TOP_HEIGHT - 1)
	scroll:SetPoint("BOTTOMRIGHT", -13, FOOTER_HEIGHT + 1)
	scroll.content:SetWidth(WIDTH - 15)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerLeft = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footerLeft:SetPoint("LEFT", PAD, 0)
	local hint = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -PAD, 0)
	hint:SetText("Shift-click to link in chat, Ctrl-click to preview")

	frame:HookScript("OnShow", function()
		Render()
		searchBox:SetFocus()
	end)

	-- A new name that matches, or a shown item finishing loading (its level), redraws.
	ns.itemLookup.onStored = function(itemID, name)
		if not (frame:IsShown() and query ~= "") then
			return
		end
		if not itemID or shownIDs[itemID] or (name and name:lower():find(query, 1, true)) then
			RequestRender()
		end
	end
end

-- Opens the window, searching for `text` if given (toggles it when there's none).
function ns:OpenItemLookup(text)
	if not frame then
		CreateWindow()
	end
	text = text and strtrim(text) or ""
	if text ~= "" then
		searchBox:SetText(text)
		frame:Show()
		Render()
	else
		frame:SetShown(not frame:IsShown())
	end
end

UI.RegisterTab({
	key = "items", label = "Items", menuLabel = "Item lookup", order = 5, frameName = "NraKitItemLookupFrame",
	open = function()
		ns:OpenItemLookup()
	end,
	available = function()
		return ns:IsModuleEnabled("itemLookup")
	end,
})
