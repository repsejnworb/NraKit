local _, ns = ...

-- Settings page listing the items Bag Tithe ignores, with a remove button per
-- item and a "Clear all" button. Registered as a canvas page by BagTithe.lua.

local tithe = ns.BagTithe

local ROW_HEIGHT = 30
local ICON_SIZE = 24

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", 4, 0)

	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(90, 22)
	row.remove:SetPoint("RIGHT", -4, 0)
	row.remove:SetText(REMOVE)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
	row.name:SetJustifyH("LEFT")

	-- Show the item tooltip when hovering the row.
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

function tithe:CreateIgnoreListPage()
	local page = CreateFrame("Frame")
	page.rows = {}

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Bag Tithe ignore list")

	local description = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	description:SetPoint("RIGHT", -16, 0)
	description:SetJustifyH("LEFT")
	description:SetText("Bag Tithe leaves these items out of its ranking. Alt+click an item in your bags while Bag Tithe is active to add or remove it. The list is shared by all your characters.")

	local clearButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	clearButton:SetSize(120, 22)
	clearButton:SetPoint("TOPRIGHT", -16, -16)
	clearButton:SetText("Clear all")
	clearButton:SetScript("OnClick", function()
		tithe:ClearIgnoreList()
	end)

	local scrollFrame = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
	scrollFrame:SetPoint("BOTTOMRIGHT", -36, 16)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(1, 1)
	scrollFrame:SetScrollChild(content)

	local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", 4, -8)
	empty:SetText("No ignored items.")

	-- Items not cached yet get their name filled in once loaded.
	local function Rebuild()
		if not page:IsVisible() then
			return
		end
		content:SetWidth(scrollFrame:GetWidth())

		local itemIDs = {}
		for itemID in pairs(tithe:GetIgnoreList()) do
			table.insert(itemIDs, itemID)
		end
		table.sort(itemIDs, function(a, b)
			local nameA = C_Item.GetItemNameByID(a) or ""
			local nameB = C_Item.GetItemNameByID(b) or ""
			if nameA ~= nameB then
				return nameA < nameB
			end
			return a < b
		end)

		for i, itemID in ipairs(itemIDs) do
			local row = page.rows[i] or CreateRow(content)
			page.rows[i] = row
			row.itemID = itemID
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", content, "RIGHT")
			row.icon:SetTexture(C_Item.GetItemIconByID(itemID))

			local name, _, quality = C_Item.GetItemInfo(itemID)
			if name then
				local color = ITEM_QUALITY_COLORS[quality] or HIGHLIGHT_FONT_COLOR
				row.name:SetText(color.hex and (color.hex .. name .. "|r") or name)
			else
				row.name:SetText(string.format("Item %d", itemID))
				Item:CreateFromItemID(itemID):ContinueOnItemLoad(Rebuild)
			end
			row.remove:SetScript("OnClick", function()
				tithe:SetIgnored(itemID, false)
			end)
			row:Show()
		end
		for i = #itemIDs + 1, #page.rows do
			page.rows[i]:Hide()
		end

		empty:SetShown(#itemIDs == 0)
		clearButton:SetEnabled(#itemIDs > 0)
		content:SetHeight(math.max(#itemIDs * ROW_HEIGHT, 1))
	end

	page:SetScript("OnShow", Rebuild)
	page.OnRefresh = Rebuild
	table.insert(tithe.listeners, Rebuild)
	return page
end
