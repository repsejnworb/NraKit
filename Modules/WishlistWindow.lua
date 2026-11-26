local _, ns = ...

-- The Wishlist window (/nra wishlist): your wishlist in a section per slot (click a
-- section to fold it, shift-click to fold the others), items you don't have first, then
-- by the level to wear them. Each row: icon, name, your note, and the level (grey while
-- it's above yours) or "Got it". Search (name or note) and a filter: All, Ready (you can
-- wear it), Not yet (too high level), Got.
--
-- Click a row to edit its note, shift-click links it in chat, ctrl-click previews it,
-- right-click for more (got / not got, Wowhead link, remove). Drop an item on the window
-- to add it.

local UI = ns.UI
local wishlist = ns.wishlist
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 26
local TOP_HEIGHT = 48
local FOOTER_HEIGHT = 28
local GOT_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "

-- Sections, in paper doll order. Anything else (not gear) goes in Other.
local GROUPS = {
	{ key = "head", label = "Head", locs = { "INVTYPE_HEAD" } },
	{ key = "neck", label = "Neck", locs = { "INVTYPE_NECK" } },
	{ key = "shoulder", label = "Shoulder", locs = { "INVTYPE_SHOULDER" } },
	{ key = "back", label = "Back", locs = { "INVTYPE_CLOAK" } },
	{ key = "chest", label = "Chest", locs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
	{ key = "wrist", label = "Wrist", locs = { "INVTYPE_WRIST" } },
	{ key = "hands", label = "Hands", locs = { "INVTYPE_HAND" } },
	{ key = "waist", label = "Waist", locs = { "INVTYPE_WAIST" } },
	{ key = "legs", label = "Legs", locs = { "INVTYPE_LEGS" } },
	{ key = "feet", label = "Feet", locs = { "INVTYPE_FEET" } },
	{ key = "rings", label = "Rings", locs = { "INVTYPE_FINGER" } },
	{ key = "trinkets", label = "Trinkets", locs = { "INVTYPE_TRINKET" } },
	{ key = "weapons", label = "Weapons", locs = { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
	{ key = "offhand", label = "Off hand", locs = { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
	{ key = "ranged", label = "Ranged", locs = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
	{ key = "other", label = "Other", locs = { "INVTYPE_BODY", "INVTYPE_TABARD" } },
}
local GROUP_BY_LOC = {}
for _, group in ipairs(GROUPS) do
	for _, loc in ipairs(group.locs) do
		GROUP_BY_LOC[loc] = group
	end
end
local OTHER = GROUPS[#GROUPS]

local FILTERS = {
	{ key = "all", label = "All" },
	{ key = "ready", label = "Ready", tip = "Items you don't have yet and can wear at your level." },
	{ key = "later", label = "Not yet", tip = "Items you don't have yet and can't wear at your level." },
	{ key = "got", label = "Got", tip = "Items you have." },
}

local HELP = "Add gear you want:\n"
	.. "  - shift-click an item into |cffffd100/nra wishlist|r (anything after it becomes its note; several items at once work too)\n"
	.. "  - right-click an item link in chat\n"
	.. "  - drop an item from your bags here\n"
	.. "  - right-click an item in Item Lookup (|cffffd100/nra item <name>|r)"

local frame, searchBox, scroll, footerLeft, foldAll, noteBox, filterChips, helpButton
local pool = UI.CreatePool()
local query, filter = "", "all"
local editingID -- the item whose note is being edited
local renderPending = false

local Render

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function QualityColor(quality)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(UI.TEXT)
end

local function PlayerLevel()
	return UnitLevel("player") or 1
end

-- Every item with what the list needs, in its section: { group = { item, ... } }.
local function Collect()
	local byGroup = {}
	for _, entry in pairs(wishlist.GetData().items) do
		local name, quality, minLevel, equipLoc, icon = wishlist.Info(entry)
		local item = { entry = entry, name = name or ("Item " .. entry.id), quality = quality, minLevel = minLevel, icon = icon }
		local ready = not minLevel or minLevel <= PlayerLevel()
		local shown = filter == "all" or (filter == "got" and entry.got) or (filter == "ready" and not entry.got and ready)
			or (filter == "later" and not entry.got and not ready)
		if shown and query ~= "" then
			shown = item.name:lower():find(query, 1, true) or (entry.note and entry.note:lower():find(query, 1, true))
		end
		if shown then
			local group = GROUP_BY_LOC[equipLoc] or OTHER
			byGroup[group] = byGroup[group] or {}
			table.insert(byGroup[group], item)
		end
	end
	for _, items in pairs(byGroup) do
		table.sort(items, function(a, b)
			if (a.entry.got or false) ~= (b.entry.got or false) then
				return not a.entry.got
			end
			if (a.minLevel or 0) ~= (b.minLevel or 0) then
				return (a.minLevel or 0) < (b.minLevel or 0)
			end
			if a.name ~= b.name then
				return a.name < b.name
			end
			return a.entry.id < b.entry.id
		end)
	end
	return byGroup
end

------------------------------------------------------------------------------
-- Adding, editing
------------------------------------------------------------------------------

-- An item dropped on the window goes on the list.
local function TakeCursorItem()
	local kind, id, link = GetCursorInfo()
	if kind == "item" and id then
		ClearCursor()
		local entry, isNew = wishlist.Add(link or id)
		if entry and not isNew then
			ns:Print((wishlist.Link(entry) or "That item") .. " is on your wishlist already.")
		end
	end
end

local function EditNote(id)
	editingID = id
	Render()
	noteBox:SetFocus()
end

local function SaveNote()
	if editingID then
		local id = editingID
		editingID = nil
		wishlist.SetNote(id, noteBox:GetText()) -- redraws
	end
end

local function OpenRowMenu(row)
	local entry = row.item.entry
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(row.item.name)
		root:CreateButton(entry.note and "Edit note" or "Add a note", function()
			EditNote(entry.id)
		end)
		root:CreateButton(entry.got and "Mark as not got" or "Mark as got", function()
			wishlist.SetGot(entry.id, not entry.got)
		end)
		root:CreateButton("Copy Wowhead Link", function()
			ns.wowheadLink.Show("item", entry.id)
		end)
		root:CreateDivider()
		root:CreateButton("Remove from wishlist", function()
			wishlist.Remove(entry.id)
		end)
	end)
end

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function OnRowClick(self, button)
	local entry = self.item.entry
	if button == "RightButton" then
		OpenRowMenu(self)
	elseif IsModifiedClick() then
		local link = wishlist.Link(entry)
		if link then
			HandleModifiedItemClick(link)
		end
	else
		EditNote(entry.id)
	end
end

local function OnRowEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local entry = self.item.entry
	if entry.link then
		GameTooltip:SetHyperlink(entry.link)
	else
		GameTooltip:SetItemByID(entry.id)
	end
	GameTooltip:AddLine("Click to edit the note, right-click for more", 0.5, 0.5, 0.5)
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
		row:SetScript("OnReceiveDrag", TakeCursorItem)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(30, 30)
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.level = MakeLabel(row, "", "GameFontHighlightSmall")
		row.level:SetPoint("RIGHT", -12, 0)
		row.level:SetJustifyH("RIGHT")
		row.name = MakeLabel(row, "")
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
		row.name:SetPoint("RIGHT", row.level, "LEFT", -16, 0)
		row.name:SetWordWrap(false)
		row.note = MakeLabel(row, "", "GameFontHighlightSmall")
		row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
		row.note:SetPoint("RIGHT", row.level, "LEFT", -16, 0)
		row.note:SetWordWrap(false)
		return row
	end)
end

local function FillRow(row, item, index)
	local entry = item.entry
	row.item = item
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
	row.icon:SetTexture(item.icon or 134400)
	row.icon:SetDesaturated(entry.got == true)
	row.name:SetText(item.name)
	row.name:SetTextColor(QualityColor(item.quality))
	row.name:SetAlpha(entry.got and 0.6 or 1)
	if entry.note then
		row.note:SetText(entry.note)
		row.note:SetTextColor(unpack(UI.TEXT))
	else
		row.note:SetText("Click to add a note (where it comes from)")
		row.note:SetTextColor(unpack(UI.TEXT_DIM))
	end
	row.note:SetShown(editingID ~= entry.id)
	if entry.got then
		row.level:SetText(GOT_ICON .. "Got it")
		row.level:SetTextColor(0.25, 0.75, 0.25)
	elseif item.minLevel and item.minLevel > 1 then
		row.level:SetText("Level " .. item.minLevel)
		row.level:SetTextColor(unpack(item.minLevel > PlayerLevel() and UI.TEXT_DIM or UI.TEXT))
	else
		row.level:SetText("")
	end
	if editingID == entry.id then
		noteBox:ClearAllPoints()
		noteBox:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 14, -3)
		noteBox:SetPoint("RIGHT", row.level, "LEFT", -16, 0)
		if not noteBox:HasFocus() then
			noteBox:SetText(entry.note or "")
		end
		noteBox:Show()
	end
end

local function AddHeader(content, group, count, y, width)
	local header = pool:Acquire("header", function()
		local button = CreateFrame("Button", nil, content)
		button:SetHeight(HEADER_HEIGHT)
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.05)
		UI.AddLine(button, "BOTTOM")
		button.arrow = button:CreateTexture(nil, "ARTWORK")
		button.arrow:SetSize(12, 12)
		button.arrow:SetPoint("LEFT", 4, 0)
		button.arrow:SetAtlas("common-icon-forwardarrow")
		button.text = MakeLabel(button, "", "GameFontNormal")
		button.text:SetPoint("LEFT", button.arrow, "RIGHT", 6, 0)
		button.count = MakeLabel(button, "", "GameFontDisable")
		button.count:SetPoint("LEFT", button.text, "RIGHT", 8, 0)
		button:SetScript("OnClick", function(self)
			local collapsed = wishlist.GetData().collapsed
			if IsShiftKeyDown() then
				for _, each in ipairs(GROUPS) do
					collapsed[each.key] = true
				end
				collapsed[self.groupKey] = nil
			else
				collapsed[self.groupKey] = not collapsed[self.groupKey] or nil
			end
			Render()
		end)
		button:SetScript("OnEnter", function(self)
			UI.ShowTooltip(self, self.label, "Click to fold or unfold. Shift-click to fold all the others.")
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:SetScript("OnReceiveDrag", TakeCursorItem)
		return button
	end)
	local closed = wishlist.GetData().collapsed[group.key]
	header.groupKey, header.label = group.key, group.label
	header.arrow:SetRotation(closed and 0 or -math.pi / 2)
	header.text:SetText(group.label)
	header.text:SetTextColor(unpack(UI.ACCENT))
	header.count:SetText(count)
	header:SetWidth(width)
	header:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
	return not closed
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
	return (lines + 1) * 17 + 12 -- its height, roughly
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	pool:ReleaseAll()
	noteBox:Hide()
	for _, chip in ipairs(filterChips) do
		chip:SetSelected(chip.filterKey == filter)
	end
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local total = wishlist.Count()

	helpButton:SetShown(total > 0)
	if total == 0 then
		content:SetHeight(Message(content, "Your wishlist is empty.\n\n" .. HELP, -PAD - 4) + PAD)
		footerLeft:SetText("")
		foldAll:Hide()
		return
	end

	local byGroup = Collect()
	local y, shown, groupKeys = -PAD, 0, {}
	if helpButton.open then
		y = y - Message(content, HELP, y - 4) - 4
	end
	for _, group in ipairs(GROUPS) do
		local items = byGroup[group]
		if items then
			table.insert(groupKeys, group.key)
			if AddHeader(content, group, #items, y, width) then
				y = y - HEADER_HEIGHT - 2
				for index, item in ipairs(items) do
					local row = AcquireRow(content)
					row:SetWidth(width)
					row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
					FillRow(row, item, index)
					y = y - ROW_HEIGHT
				end
				y = y - 8
			else
				y = y - HEADER_HEIGHT - 4
			end
			shown = shown + #items
		end
	end
	if shown == 0 then
		Message(content, "Nothing on your wishlist matches.", y - 4)
		y = y - 30
	end
	content:SetHeight(-y + PAD)
	scroll:SetScroll(scroll:GetVerticalScroll())

	local collapsed = wishlist.GetData().collapsed
	local allClosed = #groupKeys > 0
	for _, key in ipairs(groupKeys) do
		allClosed = allClosed and collapsed[key] == true
	end
	foldAll.keys, foldAll.allClosed = groupKeys, allClosed
	foldAll.text:SetText(allClosed and "Unfold All" or "Fold All")
	foldAll:SetShown(#groupKeys > 0)

	local got = 0
	for _, entry in pairs(wishlist.GetData().items) do
		got = got + (entry.got and 1 or 0)
	end
	local text = string.format("%d %s, %d got", total, total == 1 and "item" or "items", got)
	if shown < total then
		text = text .. string.format(" (%d shown)", shown)
	end
	footerLeft:SetText(text)
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

local function CreateWindow()
	frame = UI.CreateWindow("NraKitWishlistFrame", "Wishlist", WIDTH, HEIGHT, 0, "wishlist")
	local body = frame.body

	-- The search box never takes the keyboard by itself (you may be moving or fighting).
	searchBox = UI.CreateSearchBox(body, 220, function(text)
		query = text
		scroll:SetScroll(0)
		Render()
	end)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD - 1)
	searchBox:HookScript("OnEnterPressed", searchBox.ClearFocus)

	filterChips = {}
	local anchor = searchBox
	for _, each in ipairs(FILTERS) do
		local chip = UI.CreateFlatButton(body, each.label, 22)
		chip.filterKey = each.key
		chip:SetPoint("LEFT", anchor, "RIGHT", anchor == searchBox and 16 or 4, 0)
		chip:SetScript("OnClick", function(self)
			filter = self.filterKey
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			scroll:SetScroll(0)
			Render()
		end)
		if each.tip then
			chip:SetScript("OnEnter", function(self)
				UI.ShowTooltip(self, each.label, each.tip)
			end)
			chip:SetScript("OnLeave", GameTooltip_Hide)
		end
		table.insert(filterChips, chip)
		anchor = chip
	end

	foldAll = CreateFrame("Button", nil, body)
	foldAll:SetSize(80, 22)
	foldAll:SetPoint("TOPRIGHT", -PAD - 30, -PAD)
	helpButton = UI.CreateHelpButton(body, "How to add items", Render)
	helpButton:SetPoint("TOPRIGHT", -PAD, -PAD)
	foldAll.text = MakeLabel(foldAll, "", "GameFontDisableSmall")
	foldAll.text:SetPoint("RIGHT")
	foldAll.text:SetJustifyH("RIGHT")
	foldAll:SetScript("OnClick", function(self)
		local collapsed = wishlist.GetData().collapsed
		for _, key in ipairs(self.keys or {}) do
			collapsed[key] = not self.allClosed or nil
		end
		Render()
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
	-- Drop an item anywhere on the list to add it.
	scroll:EnableMouse(true)
	scroll:SetScript("OnReceiveDrag", TakeCursorItem)
	scroll:SetScript("OnMouseUp", TakeCursorItem)

	noteBox = CreateFrame("EditBox", nil, scroll.content, "InputBoxTemplate")
	noteBox:SetHeight(20)
	noteBox:SetAutoFocus(false)
	noteBox:SetMaxLetters(200)
	noteBox:Hide()
	noteBox:SetScript("OnEnterPressed", function(self)
		SaveNote()
		self:ClearFocus()
	end)
	noteBox:SetScript("OnEscapePressed", function(self)
		editingID = nil -- not saved
		self:ClearFocus()
		Render()
	end)
	noteBox:SetScript("OnEditFocusLost", SaveNote)

	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_HEIGHT)
	UI.AddLine(footer, "TOP")
	footerLeft = MakeLabel(footer, "", "GameFontHighlightSmall")
	footerLeft:SetPoint("LEFT", PAD, 0)
	local hint = MakeLabel(footer, "Drop an item here to add it. Shift-click links, right-click for more", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -PAD, 0)

	frame:HookScript("OnShow", Render)
	frame:HookScript("OnHide", function()
		filter = "all" -- a forgotten filter would make the list look broken next time
		editingID = nil
		helpButton:SetOpen(false)
	end)
	wishlist.onChanged = Render
	wishlist.onItemLoaded = RequestRender
end

-- Toggles the window (or just shows it, with `show`).
function ns:OpenWishlist(show)
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
	key = "wishlist", label = "Wishlist", menuLabel = "Wishlist", order = 6, frameName = "NraKitWishlistFrame",
	open = function()
		ns:OpenWishlist(true)
	end,
	module = "wishlist",
})

ns:AddOptionsButton("wishlist", "Open Wishlist", "Your wishlist, by slot (/nra wishlist).", function()
	ns:OpenWishlist(true)
end)
