local _, ns = ...

-- Sous Chef: marks recipes in the profession window where you have the main ingredients
-- (the meat, fish, eggs...) but are missing secondaries you can buy from a vendor (spices,
-- water, flour...), so you can grab them and cook instead of vendoring the meat. Item
-- tooltips on a main ingredient say what it cooks into and what's missing.
--
-- "Secondary" = sold by vendors: a built-in list of the common cooking ones, plus every
-- item seen for sale in unlimited supply at a merchant (remembered account-wide).
-- Recipes are read while the profession window is open and saved per character, so the
-- tooltips work with it closed.
--
-- Taint: we only add our own frames to Blizzard's recipe rows (hooksecurefunc on Init)
-- and never write Blizzard's Lua state.

local module = {
	key = "sousChef",
	section = "Professions",
	name = "Sous Chef",
	description = "Marks cooking recipes where you have the main ingredient (like the meat) but are missing vendor-bought secondaries (like spices), with an icon of what to buy. Item tooltips on the main ingredient show what it cooks into. Open your cooking window once per character so Sous Chef knows your recipes.",
	default = false,
	options = {
		{
			key = "sousChefSkillUpOnly",
			header = "General",
			name = "Only recipes that give skill",
			description = "Leave out recipes that are grey for you (no skill-ups).",
			default = true,
		},
		{
			key = "sousChefTooltip",
			name = "Show in item tooltips",
			description = "On a main ingredient's tooltip, list the recipes it's used in and the secondaries you're missing.",
			default = true,
		},
		{
			key = "sousChefAllProfessions",
			name = "Also in other professions",
			description = "Mark recipes in every profession, not just Cooking (e.g. First Aid, or crafts that use vendor thread or vials).",
			default = false,
		},
	},
}

-- Common vendor-sold cooking reagents. Anything else sold by a merchant in unlimited
-- supply is learned when you visit one.
local KNOWN_VENDOR_ITEMS = {
	[159] = true, -- Refreshing Spring Water
	[1179] = true, -- Ice Cold Milk
	[1205] = true, -- Melon Juice
	[2678] = true, -- Mild Spices
	[2692] = true, -- Hot Spices
	[3713] = true, -- Soothing Spices
	[17194] = true, -- Holiday Spices
	[30817] = true, -- Simple Flour
}

local VENDOR_KEY = "sousChefVendorItems"
local RECIPES_KEY = "sousChefRecipes"
local MARK_ICON_SIZE = 16
local MAX_TOOLTIP_RECIPES = 3

local SKILL_UP_DIFFICULTIES = {
	[Enum.TradeskillRelativeDifficulty.Optimal] = true,
	[Enum.TradeskillRelativeDifficulty.Medium] = true,
	[Enum.TradeskillRelativeDifficulty.Easy] = true,
}
local DIFFICULTY_COLORS = {
	[Enum.TradeskillRelativeDifficulty.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
	[Enum.TradeskillRelativeDifficulty.Medium] = FAIR_DIFFICULTY_COLOR,
	[Enum.TradeskillRelativeDifficulty.Easy] = EASY_DIFFICULTY_COLOR,
}

local marks = {} -- recipe row -> our mark frame
local hookedRows = {}
local hookedInit -- our wrapped ProfessionsRecipeListRecipeMixin.Init
local primaryIndex -- itemID -> { recipe entries } for tooltips, rebuilt when recipes change

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function IsVendorItem(itemID)
	return KNOWN_VENDOR_ITEMS[itemID] or (NraKitDB[VENDOR_KEY] and NraKitDB[VENDOR_KEY][itemID]) or false
end

local function CharacterRecipes()
	NraKitDB[RECIPES_KEY] = NraKitDB[RECIPES_KEY] or {}
	local key = UnitName("player") .. "-" .. GetRealmName()
	NraKitDB[RECIPES_KEY][key] = NraKitDB[RECIPES_KEY][key] or {}
	return NraKitDB[RECIPES_KEY][key]
end

-- The basic reagents of a recipe: { { itemIDs = {...}, quantity = n }, ... }. A slot can
-- accept several items (e.g. quality tiers); they all count towards it.
local function ReadReagents(recipeID)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic or not schematic.reagentSlotSchematics then
		return nil
	end
	local slots = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.reagentType == Enum.CraftingReagentType.Basic and slot.required ~= false then
			local itemIDs = {}
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then
					table.insert(itemIDs, reagent.itemID)
				end
			end
			if #itemIDs > 0 then
				table.insert(slots, { itemIDs = itemIDs, quantity = slot.quantityRequired or 1 })
			end
		end
	end
	return slots
end

local function CountItems(itemIDs)
	local count = 0
	for _, itemID in ipairs(itemIDs) do
		count = count + C_Item.GetItemCount(itemID)
	end
	return count
end

-- How many crafts your main ingredients cover, and the secondaries missing for that many
-- ({ { itemID, count }, ... }, empty if you have everything). nil if the recipe has no
-- main ingredient or you don't have enough of them for one craft.
local function Evaluate(reagents)
	local crafts, secondaries = math.huge, {}
	local hasPrimary = false
	for _, slot in ipairs(reagents) do
		local have = CountItems(slot.itemIDs)
		if IsVendorItem(slot.itemIDs[1]) then
			table.insert(secondaries, { slot = slot, have = have })
		else
			hasPrimary = true
			crafts = math.min(crafts, math.floor(have / slot.quantity))
		end
	end
	if not hasPrimary or crafts < 1 then
		return nil
	end
	local missing = {}
	for _, secondary in ipairs(secondaries) do
		local need = crafts * secondary.slot.quantity - secondary.have
		if need > 0 then
			table.insert(missing, { itemID = secondary.slot.itemIDs[1], count = need })
		end
	end
	return crafts, missing
end

local function GivesSkill(canSkillUp, difficulty)
	return canSkillUp and SKILL_UP_DIFFICULTIES[difficulty] or false
end

local function ProfessionAllowed(profession)
	return profession == Enum.Profession.Cooking or ns:GetOption("sousChefAllProfessions")
end

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

-- Saves the open profession's learned recipes for this character (used by tooltips).
local function SaveRecipes()
	if not C_TradeSkillUI.IsTradeSkillReady() or C_TradeSkillUI.IsTradeSkillLinked()
		or C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsNPCCrafting() then
		return
	end
	local profession = C_TradeSkillUI.GetBaseProfessionInfo().profession
	if not profession then
		return
	end
	local saved = {}
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned and not info.isRecraft then
			local reagents = ReadReagents(recipeID)
			if reagents and #reagents > 0 then
				saved[recipeID] = {
					name = info.name,
					canSkillUp = info.canSkillUp,
					difficulty = info.relativeDifficulty,
					reagents = reagents,
				}
			end
		end
	end
	CharacterRecipes()[profession] = saved
	primaryIndex = nil
end

local function GetPrimaryIndex()
	if primaryIndex then
		return primaryIndex
	end
	primaryIndex = {}
	for profession, recipes in pairs(CharacterRecipes()) do
		for _, entry in pairs(recipes) do
			entry.profession = profession
			for _, slot in ipairs(entry.reagents) do
				if not IsVendorItem(slot.itemIDs[1]) then
					for _, itemID in ipairs(slot.itemIDs) do
						primaryIndex[itemID] = primaryIndex[itemID] or {}
						table.insert(primaryIndex[itemID], entry)
					end
				end
			end
		end
	end
	return primaryIndex
end

-- Supply (-1 = unlimited) and whether it costs something other than gold.
local function GetMerchantSupply(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		return info and info.numAvailable, info and info.hasExtendedCost
	end
	local _, _, _, _, numAvailable, _, _, hasExtendedCost = GetMerchantItemInfo(index)
	return numAvailable, hasExtendedCost
end

-- Remember what merchants sell in unlimited supply: those are secondaries.
local function LearnMerchantItems()
	NraKitDB[VENDOR_KEY] = NraKitDB[VENDOR_KEY] or {}
	local learned = false
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		local numAvailable, hasExtendedCost = GetMerchantSupply(index)
		if itemID and numAvailable == -1 and not hasExtendedCost
			and not NraKitDB[VENDOR_KEY][itemID] then
			NraKitDB[VENDOR_KEY][itemID] = true
			learned = true
		end
	end
	if learned then
		primaryIndex = nil
	end
end

---------------------------------------------------------------------------
-- Recipe list marks
---------------------------------------------------------------------------

local function GetMark(row)
	local mark = marks[row]
	if mark then
		return mark
	end
	mark = CreateFrame("Frame", nil, row)
	mark:SetSize(MARK_ICON_SIZE, MARK_ICON_SIZE)
	mark:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	mark.icon = mark:CreateTexture(nil, "OVERLAY")
	mark.icon:SetAllPoints()
	mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	mark.more = mark:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	mark.more:SetPoint("RIGHT", mark, "LEFT", -1, 0)
	marks[row] = mark
	return mark
end

local function CurrentProfession()
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	return info and info.profession
end

local function ApplyMark(row)
	local mark = marks[row]
	if mark then
		mark:Hide()
		mark.crafts, mark.missing = nil, nil
	end
	if not ns:IsModuleEnabled(module.key) or not ProfessionAllowed(CurrentProfession()) then
		return
	end
	local elementData = row.GetElementData and row:GetElementData()
	local data = elementData and elementData.data
	local recipeInfo = data and data.recipeInfo
	if not recipeInfo or not recipeInfo.learned or recipeInfo.isRecraft then
		return
	end
	if ns:GetOption("sousChefSkillUpOnly") and not GivesSkill(recipeInfo.canSkillUp, recipeInfo.relativeDifficulty) then
		return
	end
	local reagents = ReadReagents(recipeInfo.recipeID)
	if not reagents then
		return
	end
	local crafts, missing = Evaluate(reagents)
	if not crafts or #missing == 0 then
		return
	end

	mark = GetMark(row)
	mark.crafts, mark.missing = crafts, missing
	mark.icon:SetTexture(C_Item.GetItemIconByID(missing[1].itemID))
	mark.more:SetText(#missing > 1 and ("+" .. (#missing - 1)) or "")
	mark:Show()

	-- Keep the recipe name from running under our icon.
	local reserved = MARK_ICON_SIZE + 4 + (#missing > 1 and mark.more:GetStringWidth() + 1 or 0)
	local count = row.Count and row.Count:IsShown() and row.Count:GetStringWidth() or 0
	local skillUps = row.SkillUps and row.SkillUps:GetWidth() or 0
	local maxWidth = row:GetWidth() - (reserved + count + 10 + skillUps)
	if row.Label and maxWidth > 0 and row.Label:GetWidth() > maxWidth then
		row.Label:SetWidth(maxWidth)
	end
end

local function OnRowInit(row)
	ApplyMark(row)
end

local function HookRow(row)
	if not hookedRows[row] and row.Init and row.Init ~= hookedInit then
		hookedRows[row] = true
		hooksecurefunc(row, "Init", OnRowInit)
	end
end

local function GetRecipeScrollBox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	return page and page.RecipeList and page.RecipeList.ScrollBox
end

local function RefreshRows()
	local scrollBox = GetRecipeScrollBox()
	if scrollBox and scrollBox:IsVisible() then
		scrollBox:ForEachFrame(function(row)
			if row.Label and row.SkillUps then -- recipe rows, not category headers
				HookRow(row) -- rows created before we hooked the mixin
				ApplyMark(row)
			end
		end)
	end
end

-- Our tooltip on the row: what to buy and how many crafts it gives.
local function OnRecipeEnter(_, row)
	local mark = marks[row]
	if not mark or not mark:IsShown() or not mark.missing then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, "Sous Chef")
	local parts = {}
	for _, missing in ipairs(mark.missing) do
		table.insert(parts, string.format("%d× %s", missing.count, ItemName(missing.itemID)))
	end
	GameTooltip_AddNormalLine(GameTooltip, string.format("Buy %s to make %d.", table.concat(parts, ", "), mark.crafts))
	GameTooltip:Show()
end

local function HookRecipeList()
	if hookedInit or not ProfessionsRecipeListRecipeMixin then
		return
	end
	-- Rows copy the mixin's Init when they're created, so hooking it covers all new rows.
	hooksecurefunc(ProfessionsRecipeListRecipeMixin, "Init", OnRowInit)
	hookedInit = ProfessionsRecipeListRecipeMixin.Init
	EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", OnRecipeEnter, module)
end

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------

local function OnItemTooltip(tooltip, data)
	if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not ns:IsModuleEnabled(module.key)
		or not ns:GetOption("sousChefTooltip") or not data or not data.id then
		return
	end
	local entries = GetPrimaryIndex()[data.id]
	if not entries then
		return
	end

	local lines = {}
	for _, entry in ipairs(entries) do
		local givesSkill = GivesSkill(entry.canSkillUp, entry.difficulty)
		if ProfessionAllowed(entry.profession) and (givesSkill or not ns:GetOption("sousChefSkillUpOnly")) then
			local crafts, missing = Evaluate(entry.reagents)
			if crafts then
				table.insert(lines, { entry = entry, crafts = crafts, missing = missing, givesSkill = givesSkill })
			end
		end
	end
	if #lines == 0 then
		return
	end
	-- Skill-ups first, then the recipes you can make most of.
	table.sort(lines, function(a, b)
		if a.givesSkill ~= b.givesSkill then
			return a.givesSkill
		end
		if a.crafts ~= b.crafts then
			return a.crafts > b.crafts
		end
		return a.entry.name < b.entry.name
	end)

	tooltip:AddLine(" ")
	tooltip:AddLine("Sous Chef", NORMAL_FONT_COLOR:GetRGB())
	for index = 1, math.min(#lines, MAX_TOOLTIP_RECIPES) do
		local line = lines[index]
		local color = DIFFICULTY_COLORS[line.entry.difficulty] or DISABLED_FONT_COLOR
		local status
		if #line.missing == 0 then
			status = string.format("ready (%d)", line.crafts)
		else
			local parts = {}
			for _, missing in ipairs(line.missing) do
				table.insert(parts, string.format("%d× %s", missing.count, ItemName(missing.itemID)))
			end
			status = "buy " .. table.concat(parts, ", ")
		end
		tooltip:AddDoubleLine(line.entry.name, status, color.r, color.g, color.b, 1, 1, 1)
	end
	if #lines > MAX_TOOLTIP_RECIPES then
		tooltip:AddLine(string.format("+%d more", #lines - MAX_TOOLTIP_RECIPES), DISABLED_FONT_COLOR:GetRGB())
	end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------

local saveQueued = false
local refreshQueued = false

local function QueueSave()
	if not saveQueued then
		saveQueued = true
		C_Timer.After(0.5, function()
			saveQueued = false
			SaveRecipes()
		end)
	end
end

local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, function()
			refreshQueued = false
			RefreshRows()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "Blizzard_ProfessionsTemplates" or arg1 == "Blizzard_Professions" then
			HookRecipeList()
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
		QueueSave()
		QueueRefresh()
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		LearnMerchantItems()
	elseif event == "BAG_UPDATE_DELAYED" then
		QueueRefresh()
	end
end)

function module:OnInitialize()
	HookRecipeList()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	eventFrame:UnregisterAllEvents()
	if enabled then
		HookRecipeList()
		if not hookedInit then
			eventFrame:RegisterEvent("ADDON_LOADED")
		end
		eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
		eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
		eventFrame:RegisterEvent("MERCHANT_SHOW")
		eventFrame:RegisterEvent("MERCHANT_UPDATE")
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	end
	QueueRefresh()
end

function module:OnOptionChanged()
	QueueRefresh()
end

ns:RegisterModule(module)
