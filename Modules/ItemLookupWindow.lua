local _, ns = ...

-- The Lookup window (the "Lookup" tab): [ Items ][ Spells ][ Recipes ] at the top, one at a
-- time, a search box, and the matches. /nra item, /nra spell, /nra recipe open it in that mode.
--
--   Items    every item in the game (ItemLookup.lua learns their names in the background):
--            icon, name in its quality colour, type, required level, how many you have.
--            Shift-click links, Ctrl-click previews, right-click for the wishlist.
--   Spells   every spell (SpellRecipeLookup.lua): yours first, with "Known". Shift-click links.
--   Recipes  every profession recipe: its profession, what it makes and needs, and with prices
--            (Auctionator, else vendors) the cost of one craft, what it sells for and the profit;
--            sorted by name or profit. Hover shows the recipe's own tooltip (with NraKit's cost
--            and have lines); right-click for the shopping-list menu.

local UI = ns.UI
local WIDTH, HEIGHT = UI.WINDOW_WIDTH, UI.WINDOW_HEIGHT
local PAD = UI.PAD
local ROW_HEIGHT = 30
local RECIPE_ROW_HEIGHT = 38
local TOP_HEIGHT = 80
local CHIP_HEIGHT = 20 -- the Recipes mode's profession chips, under the search box
local FOOTER_HEIGHT = 28
local MAX_SHOWN = 200
local MAX_REAGENT_ICONS = 6

local ICONS = "Interface\\Icons\\"
local MODES = {
	{ key = "items", label = "Items", icon = ICONS .. "INV_Misc_Bag_08", empty = "Type part of an item's name above." },
	{ key = "spells", label = "Spells", icon = ICONS .. "INV_Misc_Book_09", empty = "Type part of a spell's name above." },
	{ key = "recipes", label = "Recipes", icon = ICONS .. "INV_Scroll_03" },
}

-- Each profession's icon (the game's own); one not listed gets a recipe scroll.
local PROFESSION_ICONS = {
	Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
	Engineering = "Trade_Engineering", Leatherworking = "Trade_LeatherWorking", Tailoring = "Trade_Tailoring",
	Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice", Mining = "Trade_Mining",
	Fishing = "Trade_Fishing", Jewelcrafting = "INV_Misc_Gem_01", Inscription = "INV_Inscription_Tradeskill01",
	Herbalism = "Trade_Herbalism", Skinning = "INV_Misc_Pelt_Wolf_01",
}
local function ProfessionIcon(name)
	return ICONS .. (PROFESSION_ICONS[name] or "INV_Scroll_03")
end
local HINTS = {
	items = "Shift-click to link in chat, Ctrl-click to preview",
	spells = "Shift-click to link in chat, right-click for more",
	recipes = "Shift-click to link in chat, right-click for shopping lists",
}

local frame, searchBox, progressBar, progressButton, scroll, footerLeft, hint, sortLabel
local modeButtons, sortButtons = {}, {}
local professionChips = {} -- reused chip buttons
local topLine
local pool = UI.CreatePool()
local query = ""
local shownIDs = {} -- [id] = true for the item rows on screen
local renderPending = false

local function Mode()
	return NraKitDB.lookupMode or "items"
end

local function RecipeSort()
	return NraKitDB.lookupRecipeSort or "name"
end

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

local function Money(copper)
	return GetMoneyString and GetMoneyString(math.floor(math.abs(copper)), true) or tostring(copper)
end

-- The progress bar: how complete the current mode's list is, and the button next to it
-- (items only: pause or check again).
local function UpdateProgress()
	local mode, text, button, fraction, color = Mode(), nil, nil, 1, { 0.3, 0.6, 0.3 }
	if mode == "items" then
		local progress = ns.itemLookup.Progress()
		if progress.done then
			text = string.format("All %s known item names learned", Number(progress.named))
			button = "Check again"
		elseif progress.total then
			text = string.format("%s %s of %s item names", progress.paused and "Paused:" or "Learning", Number(progress.named),
				Number(progress.total))
			button = progress.paused and "Resume" or "Pause"
			fraction = progress.named / math.max(progress.total, 1)
			color = progress.paused and UI.GREY or UI.ACCENT
		else
			text = progress.paused and string.format("Paused: %s item names", Number(progress.named)) or "Finding the game's items..."
			button = progress.paused and "Resume" or "Pause"
			fraction, color = 0, progress.paused and UI.GREY or UI.ACCENT
		end
	elseif mode == "spells" then
		local progress = ns.spellLookup.Progress()
		if progress then
			text = "Reading the game's spells..."
			fraction, color = progress.read / progress.total, UI.ACCENT
		else
			text = string.format("%s spells", Number(ns.spellLookup.Count()))
		end
	else
		local progress = ns.spellLookup.Progress() and { checked = 0, total = 1 } or ns.recipeLookup.Progress()
		if progress then
			text = "Finding the game's recipes (once per game version)..."
			fraction, color = progress.checked / math.max(progress.total, 1), UI.ACCENT
		else
			text = string.format("%s recipes  ·  %s", Number(ns.recipeLookup.Count()),
				ns.sellList and ns.sellList.HasAuctionator() and "prices from Auctionator" or "vendor prices (Auctionator adds auction prices)")
		end
	end
	progressBar.text:SetText(text)
	progressBar:SetMinMaxValues(0, 1)
	progressBar:SetValue(fraction)
	progressBar:SetStatusBarColor(color[1], color[2], color[3], 0.8)
	progressButton:SetShown(button ~= nil)
	if button then
		progressButton.action = button
		progressButton.text:SetText(button)
		progressButton:SetWidth(progressButton.text:GetStringWidth() + 20)
	end
end

local BUTTON_TIPS = {
	["Pause"] = "Stop learning item names for now (until you resume). Searching still works with the names learned so far.",
	["Resume"] = "Carry on learning item names in the background.",
	["Check again"] = "Ask the server again for the items that had no name yet, like items nobody had discovered. This happens by itself once a day.",
}

------------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------------

local function InsertLink(link)
	if link and ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	end
end

local function OnRowEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.kind == "spells" then
		GameTooltip:SetSpellByID(self.id)
	elseif self.kind == "recipes" then
		-- The recipe's own tooltip, with NraKit's cost and have lines (Auctionator Prices).
		GameTooltip:SetHyperlink("enchant:" .. self.id)
	else
		GameTooltip:SetItemByID(self.id)
	end
	GameTooltip:Show()
end

local function OpenMenu(row)
	MenuUtil.CreateContextMenu(row, function(_, root)
		if row.kind == "recipes" then
			root:CreateTitle(row.recipeName or "Recipe")
			if ns.auctionator and ns.auctionator.FillRecipeMenu then
				ns.auctionator.FillRecipeMenu(root, row.id)
			end
			root:CreateButton("Copy Wowhead link", function()
				ns.wowheadLink.Show("spell", row.id)
			end)
		else
			root:CreateTitle(C_Spell.GetSpellName(row.id) or "Spell")
			root:CreateButton("Copy Wowhead link", function()
				ns.wowheadLink.Show("spell", row.id)
			end)
		end
	end)
end

local function OnRowClick(self, button)
	if self.kind == "items" then
		if button == "RightButton" then
			if ns:IsModuleEnabled("wishlist") then
				ns.wishlist.OpenItemMenu(self, self.id, function()
					ns.wishlist.SetStar(self, self.id, self.icon)
				end)
			end
			return
		end
		local link = select(2, C_Item.GetItemInfo(self.id))
		if link then
			HandleModifiedItemClick(link)
		end
		return
	end
	if button == "RightButton" then
		OpenMenu(self)
	elseif IsModifiedClick("CHATLINK") then
		local link = self.kind == "recipes" and C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(self.id)
		InsertLink(link or C_Spell.GetSpellLink(self.id))
	end
end

local function NewRow(content, height)
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(height)
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	return row
end

local function Text(row, font, point, x)
	local text = row:CreateFontString(nil, "OVERLAY", font)
	text:SetPoint(point, x, 0)
	text:SetJustifyH(point == "RIGHT" and "RIGHT" or "LEFT")
	text:SetWordWrap(false)
	return text
end

local function AcquireItemRow(content)
	return pool:Acquire("item", function()
		local row = NewRow(content, ROW_HEIGHT)
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.type = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.type:SetJustifyH("LEFT")
		row.type:SetWordWrap(false)
		row.owned = Text(row, "GameFontHighlightSmall", "RIGHT", -10)
		row.level = Text(row, "GameFontDisableSmall", "RIGHT", -90)
		return row
	end)
end

local function AcquireSpellRow(content)
	return pool:Acquire("spell", function()
		local row = NewRow(content, ROW_HEIGHT)
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.subtext = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.subtext:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.known = Text(row, "GameFontHighlightSmall", "RIGHT", -90)
		row.spellID = Text(row, "GameFontDisableSmall", "RIGHT", -10)
		return row
	end)
end

-- Columns of a recipe row, from its right edge: { right offset, width }.
local PROFIT_RIGHT, PROFIT_WIDTH = -8, 96
local SELLS_RIGHT, SELLS_WIDTH = -110, 96
local COST_RIGHT, COST_WIDTH = -212, 96

local function AcquireRecipeRow(content)
	return pool:Acquire("recipe", function()
		local row = NewRow(content, RECIPE_ROW_HEIGHT)
		row.icon:SetSize(28, 28)
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
		row.name:SetPoint("RIGHT", row, "RIGHT", COST_RIGHT - COST_WIDTH - 8, 0)
		row.profession = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.profession:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
		row.reagents = {}
		for index = 1, MAX_REAGENT_ICONS do
			local icon = row:CreateTexture(nil, "ARTWORK")
			icon:SetSize(14, 14)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.reagents[index] = icon
		end
		local function Column(right, width)
			local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			text:SetPoint("RIGHT", right, 0)
			text:SetWidth(width)
			text:SetJustifyH("RIGHT")
			text:SetWordWrap(false)
			return text
		end
		row.cost = Column(COST_RIGHT, COST_WIDTH)
		row.sells = Column(SELLS_RIGHT, SELLS_WIDTH)
		row.profit = Column(PROFIT_RIGHT, PROFIT_WIDTH)
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

local function RenderItems(content, width)
	local matches, total = ns.itemLookup.Search(query, MAX_SHOWN)
	for index, match in ipairs(matches) do
		shownIDs[match.id] = true
		local row = AcquireItemRow(content)
		row.kind, row.id, row.itemID = "items", match.id, match.id
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD - (index - 1) * ROW_HEIGHT)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		local _, itemType, itemSubType, _, icon = C_Item.GetItemInfoInstant(match.id)
		row.icon:SetTexture(icon or 134400)
		row.name:SetText(match.name)
		row.name:SetTextColor(QualityColor(match.quality))
		row.name:SetWidth(width * 0.45)
		row.type:SetText(itemSubType and itemSubType ~= itemType and (itemType .. " - " .. itemSubType) or itemType or "")
		row.type:SetPoint("LEFT", row, "LEFT", 38 + width * 0.45 + 12, 0)
		row.type:SetWidth(width * 0.3)
		-- The required level needs the item loaded; it shows up when it arrives.
		local _, _, _, _, minLevel = C_Item.GetItemInfo(match.id)
		row.level:SetText(minLevel and minLevel > 1 and ("Level " .. minLevel) or "")
		local owned = Owned(match.id)
		row.owned:SetText(owned > 0 and ("|cff40c040You have " .. owned .. "|r") or "")
		ns.wishlist.SetStar(row, match.id, row.icon)
	end
	return #matches, total, ROW_HEIGHT
end

local function RenderSpells(content, width)
	local matches, total = ns.spellLookup.Search(query, MAX_SHOWN)
	for index, match in ipairs(matches) do
		local row = AcquireSpellRow(content)
		row.kind, row.id = "spells", match.id
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD - (index - 1) * ROW_HEIGHT)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		row.icon:SetTexture(C_Spell.GetSpellTexture(match.id) or 134400)
		row.name:SetText(match.name)
		row.name:SetTextColor(match.known and 1 or 0.85, match.known and 0.82 or 0.85, match.known and 0 or 0.85)
		local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(match.id)
		row.subtext:SetText(subtext or "")
		row.known:SetText(match.known and "|cff40c040Known|r" or "")
		row.spellID:SetText(tostring(match.id))
	end
	return #matches, total, ROW_HEIGHT
end

local function RenderRecipes(content, width)
	local matches, total = ns.recipeLookup.Search(query, MAX_SHOWN, RecipeSort(), NraKitDB.lookupRecipeProfession)
	for index, recipe in ipairs(matches) do
		local row = AcquireRecipeRow(content)
		row.kind, row.id, row.recipeName = "recipes", recipe.id, recipe.name
		row:SetWidth(width)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD - (index - 1) * RECIPE_ROW_HEIGHT)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		local icon = recipe.output and select(5, C_Item.GetItemInfoInstant(recipe.output)) or C_Spell.GetSpellTexture(recipe.id)
		row.icon:SetTexture(icon or 134400)
		row.name:SetText(recipe.name .. ((recipe.quantity or 1) > 1 and (" |cff999999x" .. recipe.quantity .. "|r") or ""))
		row.name:SetTextColor(QualityColor(recipe.output and select(3, C_Item.GetItemInfo(recipe.output)) or 1))
		row.profession:SetText(recipe.profession)
		-- The reagents as small icons after the profession.
		local anchor = row.profession
		for slot, reagentIcon in ipairs(row.reagents) do
			local reagent = recipe.reagents[slot]
			reagentIcon:ClearAllPoints()
			if reagent then
				reagentIcon:SetTexture(select(5, C_Item.GetItemInfoInstant(reagent.itemID)) or 134400)
				reagentIcon:SetPoint("LEFT", anchor, "RIGHT", slot == 1 and 10 or 3, 0)
				reagentIcon:Show()
				anchor = reagentIcon
			else
				reagentIcon:Hide()
			end
		end
		local cost, sells, profit, missing = ns.recipeLookup.Value(recipe)
		row.cost:SetText(#recipe.reagents == 0 and "" or (Money(cost) .. (missing > 0 and " |cffff9933+?|r" or "")))
		row.sells:SetText(sells and Money(sells) or "|cff666666-|r")
		if profit then
			row.profit:SetText((profit < 0 and "|cffff5050-" or "|cff40c040") .. Money(profit) .. "|r")
		else
			row.profit:SetText("|cff666666-|r")
		end
	end
	return #matches, total, RECIPE_ROW_HEIGHT
end

-- Recipes: [ All ][ Blacksmithing ][ ... ] chips under the search box (yours first), wrapping
-- onto a second line if needed. Returns how much room they take (0 in other modes).
local function LayoutProfessionChips(body, mode)
	for _, chip in ipairs(professionChips) do
		chip:Hide()
	end
	if mode ~= "recipes" then
		return 0
	end
	local professions, mine = ns.recipeLookup.Professions()
	if #professions == 0 then
		return 0
	end
	local selected = NraKitDB.lookupRecipeProfession
	local names = { "All" }
	for _, name in ipairs(professions) do
		table.insert(names, name)
	end
	local x, y, maxX = PAD, -PAD - 68, body:GetWidth() - PAD
	for index, name in ipairs(names) do
		local chip = professionChips[index]
		if not chip then
			chip = UI.CreateFlatButton(body, "", CHIP_HEIGHT)
			chip:SetScript("OnClick", function(self)
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				NraKitDB.lookupRecipeProfession = self.profession
				scroll:SetScroll(0)
				Render()
			end)
			professionChips[index] = chip
		end
		chip.profession = index > 1 and name or nil
		UI.SetButtonIcon(chip, index > 1 and ProfessionIcon(name) or (ICONS .. "INV_Misc_Book_11"), name, 14)
		if x + chip:GetWidth() > maxX then
			x, y = PAD, y - CHIP_HEIGHT - 4
		end
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", x, y)
		chip:SetSelected(chip.profession == selected)
		-- Your professions in gold, when not selected.
		if mine[name] and chip.profession ~= selected then
			chip.text:SetTextColor(unpack(UI.GOLD))
		end
		chip:Show()
		x = x + chip:GetWidth() + 4
	end
	return -y - (PAD + 68) + CHIP_HEIGHT + 8
end

local function Render()
	renderPending = false
	if not (frame and frame:IsShown()) then
		return
	end
	local mode = Mode()
	-- The list starts under the chips (Recipes) or right under the search box.
	local top = TOP_HEIGHT + LayoutProfessionChips(frame.body, mode)
	topLine:SetPoint("TOPLEFT", 0, -top)
	topLine:SetPoint("TOPRIGHT", 0, -top)
	scroll:SetPoint("TOPLEFT", 0, -top - 1)
	for _, button in ipairs(modeButtons) do
		button:SetSelected(button.mode == mode)
	end
	for _, button in ipairs(sortButtons) do
		button:SetShown(mode == "recipes")
		button:SetSelected(button.sort == RecipeSort())
	end
	sortLabel:SetShown(mode == "recipes")
	hint:SetText(HINTS[mode] .. (mode == "items" and ns:IsModuleEnabled("wishlist") and ", right-click for your wishlist" or ""))
	UpdateProgress()
	pool:ReleaseAll()
	wipe(shownIDs)
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD

	if query == "" and mode ~= "recipes" then
		for _, info in ipairs(MODES) do
			if info.key == mode then
				Message(content, info.empty)
			end
		end
		content:SetHeight(60)
		footerLeft:SetText("")
		return
	end
	local shown, total, rowHeight
	if mode == "spells" then
		shown, total, rowHeight = RenderSpells(content, width)
	elseif mode == "recipes" then
		shown, total, rowHeight = RenderRecipes(content, width)
	else
		shown, total, rowHeight = RenderItems(content, width)
	end
	if total == 0 then
		Message(content, query == "" and "No recipes yet." or string.format("Nothing matches \"%s\".", query))
		content:SetHeight(60)
		footerLeft:SetText("")
		return
	end
	content:SetHeight(PAD * 2 + shown * rowHeight)
	scroll:SetScroll(scroll:GetVerticalScroll())
	if total > shown then
		footerLeft:SetText(string.format("Showing %d of %d matches: type more to narrow it down.", shown, total))
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

-- Switches mode (and starts reading spells or finding recipes when they're needed).
local function SetMode(mode)
	NraKitDB.lookupMode = mode
	if mode == "spells" then
		ns.spellLookup.Start()
	elseif mode == "recipes" then
		ns.recipeLookup.Start()
	end
	scroll:SetScroll(0)
	Render()
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function CreateWindow()
	frame = UI.CreateWindow("NraKitItemLookupFrame", "Lookup", WIDTH, HEIGHT, 0, "items")
	local body = frame.body

	-- [ Items ][ Spells ][ Recipes ]: one at a time.
	local anchor
	for _, info in ipairs(MODES) do
		local button = UI.CreateFlatButton(body, info.label, 24)
		UI.SetButtonIcon(button, info.icon, nil, 16)
		button:SetWidth(button:GetWidth() + 6)
		button.mode = info.key
		if anchor then
			button:SetPoint("LEFT", anchor, "RIGHT", 1, 0)
		else
			button:SetPoint("TOPLEFT", PAD, -PAD)
		end
		button:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetMode(self.mode)
		end)
		anchor = button
		table.insert(modeButtons, button)
	end
	-- Recipes: sort by name or by profit.
	sortLabel = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	local previous
	for index, info in ipairs({ { "profit", "Profit" }, { "name", "Name" } }) do
		local button = UI.CreateFlatButton(body, info[2], 22)
		button:SetWidth(button.text:GetStringWidth() + 22)
		button.sort = info[1]
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", -1, 0)
		else
			button:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
		end
		button:SetScript("OnClick", function(self)
			NraKitDB.lookupRecipeSort = self.sort
			scroll:SetScroll(0)
			Render()
		end)
		previous = button
		table.insert(sortButtons, button)
		if index == 2 then
			sortLabel:SetPoint("RIGHT", button, "LEFT", -8, 0)
		end
	end
	sortLabel:SetText("Sort by")

	searchBox = UI.CreateSearchBox(body, 260, function(text)
		query = text
		scroll:SetScroll(0)
		Render()
	end)
	searchBox:SetPoint("TOPLEFT", PAD + 6, -PAD - 37)

	progressButton = UI.CreateFlatButton(body, "Pause", 22)
	progressButton:SetPoint("TOPRIGHT", -PAD, -PAD - 36)
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
	progressBar:SetPoint("RIGHT", body, "RIGHT", -110, 0)
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

	topLine = body:CreateTexture(nil, "BORDER")
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
	hint = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("RIGHT", -PAD, 0)

	-- The search box never takes the keyboard by itself (you may be moving or fighting):
	-- click it to type. Enter (like Esc) gives the keys back to the game.
	searchBox:HookScript("OnEnterPressed", searchBox.ClearFocus)
	frame:HookScript("OnShow", function()
		SetMode(Mode())
	end)

	-- A new name that matches, or a shown item finishing loading (its level), redraws.
	ns.itemLookup.onStored = function(itemID, name)
		if not (frame:IsShown() and query ~= "" and Mode() == "items") then
			return
		end
		if not itemID or shownIDs[itemID] or (name and name:lower():find(query, 1, true)) then
			RequestRender()
		end
	end
	-- Spells read, recipes found (once each): show them.
	ns.spellLookup.onReady = Render
	ns.recipeLookup.onReady = Render
end

-- Opens the window in `mode` ("items", "spells", "recipes"; default: the last one), searching
-- for `text` if given; without text it toggles (the same mode) or switches.
function ns:OpenLookup(mode, text)
	if not frame then
		CreateWindow()
	end
	text = text and strtrim(text) or ""
	local switching = mode and mode ~= Mode()
	if mode then
		NraKitDB.lookupMode = mode
	end
	if text ~= "" then
		searchBox:SetText(text)
		searchBox:ClearFocus()
		frame:Show()
		SetMode(Mode())
	elseif switching and frame:IsShown() then
		SetMode(Mode())
	else
		frame:SetShown(not frame:IsShown())
	end
end

-- (Items: the name it always had.)
function ns:OpenItemLookup(text)
	ns:OpenLookup("items", text)
end

UI.RegisterTab({
	key = "items", label = "Lookup", menuLabel = "Lookup", order = 5, frameName = "NraKitItemLookupFrame",
	open = function()
		ns:OpenLookup()
	end,
	module = "itemLookup",
})
