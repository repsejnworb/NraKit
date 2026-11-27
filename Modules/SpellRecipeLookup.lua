local _, ns = ...

-- Lookup's spells and recipes (the window is ItemLookupWindow.lua; items are ItemLookup.lua).
--
-- Spells: their names are in the client (no server asked), so every spell ID is read once,
-- in chunks across frames, the first time it's needed (Forever's spells go up to ~1.4 million,
-- custom ones included: a few tenths of a second in all). Not saved: it's quick to read again.
-- The game doesn't say which class a spell is (its skill line answers nothing for class spells),
-- so each character's spellbook is remembered as you log in (its class tabs, not General:
-- learned and future spells), account-wide in NraKitDB.spellClassData = { [CLASS] = { [id] = true } }.
-- A lower rank you know (Cleave Rank 2) is your class's too: it shares a name with a spell in your
-- class's spellbook. "Knowing" a spell isn't enough by itself: you also know your recipes,
-- languages, armour skills... Classes you haven't logged in on aren't known; their spells show
-- as "other" (a known recipe shows its profession).
--
-- Recipes: a profession's recipe is a spell the game gives a profession
-- (C_TradeSkillUI.GetProfessionInfoByRecipeID), readable without the profession window,
-- along with what it makes and needs (GetRecipeSchematic). The spells are checked once per
-- game version, in the background, and the recipe IDs saved (NraKitDB.recipeLookupData =
-- { build, filter, ids = { recipeID, ... } }). Enchants make no item: they have no output.

local MAX_SPELL_ID = 1500000
local SPELL_CHUNK = 50000 -- spell IDs read per frame
local RECIPE_CHUNK = 1500 -- spells checked for a profession per frame

local spells = {}
ns.spellLookup = spells
local recipes = {}
ns.recipeLookup = recipes

local function BuildKey()
	local version, build = GetBuildInfo()
	return tostring(version) .. "." .. tostring(build)
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

local spellList -- { { id, name, lower }, ... } once read
local classNames -- [CLASS] = { [lower-case name] = true }, from the spellbooks
local recipeIndex = 1 -- next spell (in spellList) to check, while finding recipes
local found -- recipe IDs found this time (while finding them)
local readyCallbacks = {} -- run once the recipes are found (recipes.WhenReady)
local byName -- [lower-case name] = { recipe ID, ... }, worked out when needed
local spellCursor = 1
local spellReader = CreateFrame("Frame")
spellReader:Hide()

local function ReadSpells()
	spellList = spellList or {}
	local last = math.min(spellCursor + SPELL_CHUNK - 1, MAX_SPELL_ID)
	for id = spellCursor, last do
		local name = C_Spell.GetSpellName(id)
		if name and name ~= "" then
			table.insert(spellList, { id = id, name = name, lower = name:lower() })
		end
	end
	spellCursor = last + 1
	if spellCursor > MAX_SPELL_ID then
		spellReader:Hide()
		if spells.onReady then
			spells.onReady()
		end
		if recipes.Start then
			recipes.Start()
		end
	end
end
spellReader:SetScript("OnUpdate", ReadSpells)

-- Remember the spellbook at login, and when it changes (learning, a new level).
local spellbookWatcher = CreateFrame("Frame")
spellbookWatcher:RegisterEvent("PLAYER_LOGIN")
spellbookWatcher:RegisterEvent("SPELLS_CHANGED")
spellbookWatcher:SetScript("OnEvent", function()
	if ns:IsModuleEnabled("itemLookup") then
		spells.CollectSpellbook()
	end
end)

-- Starts reading the spells (once).
function spells.Start()
	if spellCursor <= MAX_SPELL_ID then
		spellReader:Show()
	end
end

-- Reads the spells again from the start (for tests).
function spells.Reset()
	spellList, spellCursor = nil, 1
	spells.Start()
end

-- Lets go of the spell list and the recipes' details (Lookup closed: they're read again, quickly,
-- next time). Not while recipes are being found: that walks the spell list.
function spells.Release()
	if found then
		return
	end
	spellReader:Hide()
	spellList, spellCursor = nil, 1
	if recipes.Release then
		recipes.Release()
	end
end

-- { read, total } while reading, nil once done.
function spells.Progress()
	if spellCursor > MAX_SPELL_ID then
		return nil
	end
	return { read = spellCursor - 1, total = MAX_SPELL_ID }
end

function spells.Count()
	return spellList and #spellList or 0
end

local function ClassData()
	NraKitDB.spellClassData = NraKitDB.spellClassData or {}
	return NraKitDB.spellClassData
end

-- Remembers this character's spellbook as its class's spells (class tabs, not General).
function spells.CollectSpellbook()
	local _, class = UnitClass("player")
	if not class or type(C_SpellBook) ~= "table" or not C_SpellBook.GetNumSpellBookSkillLines then
		return
	end
	local data = ClassData()
	data[class] = data[class] or {}
	local known = data[class]
	classNames = nil -- the names are worked out again
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 2, C_SpellBook.GetNumSpellBookSkillLines() or 0 do -- 1 is General: racials, auto attack
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.isGuild and not info.shouldHide then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
				-- Spells you have and ones you'll learn (1 Spell, 2 FutureSpell).
				if item and (item.itemType == 1 or item.itemType == 2) then
					known[item.actionID] = true
					if item.spellID then
						known[item.spellID] = true
					end
				end
			end
		end
	end
end

-- The classes whose spells are known (from your characters' spellbooks): { "WARRIOR", ... }.
function spells.KnownClasses()
	local list = {}
	for class in pairs(ClassData()) do
		table.insert(list, class)
	end
	table.sort(list)
	return list
end

-- Each class's spell names (lower-case), from the spellbooks: for telling a lower rank you
-- know (Cleave Rank 2) is your class's. Worked out when needed.
local function ClassNames()
	if not classNames then
		classNames = {}
		for class, ids in pairs(ClassData()) do
			local names = {}
			for id in pairs(ids) do
				local name = C_Spell.GetSpellName(id)
				if name then
					names[name:lower()] = true
				end
			end
			classNames[class] = names
		end
	end
	return classNames
end

-- A spell's class (from the spellbooks), or nil. `known` (you know it) with `lower` (its name):
-- a lower rank of one of your class's spells counts too.
function spells.ClassOf(id, known, lower)
	for class, ids in pairs(ClassData()) do
		if ids[id] then
			return class
		end
	end
	if known and lower then
		local _, myClass = UnitClass("player")
		local names = ClassNames()[myClass]
		if names and names[lower] then
			return myClass
		end
	end
end

-- A spell that's a profession's recipe: its profession's name, or nil (for showing a known
-- recipe as "Cooking" rather than as a class's).
function spells.ProfessionOf(id)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(id)
	if info and info.profession ~= nil and info.professionName and info.professionName ~= "" then
		return info.professionName
	end
end

-- Spells whose name contains query (lower-case), passing `filter` (nil: all; "mine": yours;
-- a class like "WARRIOR"; "other": no class known): { { id, name, known, class }, ... }, best
-- first (yours, your class's, other classes', the rest; then names starting with it, then by
-- name), at most `limit`; and how many matched.
function spells.Search(query, limit, filter)
	local _, myClass = UnitClass("player")
	-- A number finds spells by ID too: that one first, then IDs starting with it.
	local number = query:match("^%s*(%d+)%s*$")
	local matches = {}
	for _, spell in ipairs(spellList or {}) do
		local at = spell.lower:find(query, 1, true)
		local byID = number and tostring(spell.id):sub(1, #number) == number
		if at or byID then
			local known = IsPlayerSpell(spell.id) == true
			local class = spells.ClassOf(spell.id, known, spell.lower)
			local mine = known and class ~= nil and class == myClass -- your class's, and you know it
			if not filter or (filter == "mine" and mine) or (filter == "other" and not class) or filter == class then
				table.insert(matches, { id = spell.id, name = spell.name, starts = at == 1, known = known, class = class,
					group = mine and 1 or class == myClass and 2 or class and 3 or 4,
					exact = byID and #tostring(spell.id) == #number, byID = byID })
			end
		end
	end
	table.sort(matches, function(a, b)
		if a.exact ~= b.exact then
			return a.exact
		end
		if a.group ~= b.group then
			return a.group < b.group
		end
		if a.byID and b.byID then
			return a.id < b.id
		end
		if a.starts ~= b.starts then
			return a.starts
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	local total = #matches
	for index = total, limit + 1, -1 do
		matches[index] = nil
	end
	return matches, total
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local details = {} -- recipeID -> its details, read once (let go when Lookup closes)

function recipes.Release()
	details = {}
end
local recipeFinder = CreateFrame("Frame")
recipeFinder:Hide()

local function Data()
	NraKitDB.recipeLookupData = NraKitDB.recipeLookupData or {}
	return NraKitDB.recipeLookupData
end

-- A real profession recipe: its skill line is one of the professions (info.profession is set
-- only for those: racial skills, Lockpicking, Riding, Poisons, test lines have none), and it
-- makes something or needs reagents (an enchant: reagents, no item), unlike "Find Herbs".
local function IsRecipe(id)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(id)
	if not (info and info.profession ~= nil and info.professionName and info.professionName ~= "") then
		return false
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(id, false)
	return schematic ~= nil and (schematic.outputItemID ~= nil or #(schematic.reagentSlotSchematics or {}) > 0)
end
recipes.IsRecipe = IsRecipe

-- Saved recipe lists made with another filter are found again (bump when IsRecipe changes).
local FILTER_VERSION = 2

local function Saved(data)
	return data.build == BuildKey() and data.filter == FILTER_VERSION and data.ids ~= nil
end

recipeFinder:SetScript("OnUpdate", function(self)
	if InCombatLockdown() then
		return
	end
	local last = math.min(recipeIndex + RECIPE_CHUNK - 1, #spellList)
	for index = recipeIndex, last do
		local id = spellList[index].id
		if IsRecipe(id) then
			table.insert(found, id)
		end
	end
	recipeIndex = last + 1
	if recipeIndex > #spellList then
		self:Hide()
		local data = Data()
		data.build, data.filter, data.ids = BuildKey(), FILTER_VERSION, found
		found, byName = nil, nil
		if recipes.onReady then
			recipes.onReady()
		end
		local callbacks = readyCallbacks
		readyCallbacks = {}
		for _, callback in ipairs(callbacks) do
			callback()
		end
		-- Found for something else (known recipes): let go of the spell list (tens of MB)
		-- unless Lookup is showing it.
		local window = _G.NraKitItemLookupFrame
		if not (window and window:IsShown()) then
			spells.Release()
		end
	end
end)

-- Finds the recipes (once per game version; needs the spells read first).
function recipes.Start()
	local data = Data()
	if Saved(data) then
		return
	end
	if not spellList or spells.Progress() then
		spells.Start() -- finding recipes follows
		return
	end
	if not found then
		found, recipeIndex = {}, 1
		recipeFinder:Show()
	end
end

-- { checked, total } while finding them, nil once known.
function recipes.Progress()
	local data = Data()
	if Saved(data) then
		return nil
	end
	if found then
		return { checked = recipeIndex - 1, total = #spellList }
	end
	return { checked = 0, total = 0 }
end

-- A recipe's details: { id, name, lower, profession, output (item ID or nil), quantity,
-- reagents = { { count, itemID }, ... } }.
function recipes.Get(id)
	local recipe = details[id]
	if recipe then
		return recipe
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(id, false)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(id)
	local name = schematic and schematic.name or C_Spell.GetSpellName(id) or ("Recipe " .. id)
	recipe = { id = id, name = name, lower = name:lower(), profession = info and info.professionName or "",
		output = schematic and schematic.outputItemID, reagents = {} }
	recipe.quantity = schematic and (schematic.quantityMin or schematic.quantityMax) or 1
	for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if reagent and reagent.itemID and slot.required ~= false then
			table.insert(recipe.reagents, { count = slot.quantityRequired or 1, itemID = reagent.itemID })
		end
	end
	details[id] = recipe
	return recipe
end

-- Functions to call once the recipes are known (now, if they already are).

function recipes.WhenReady(callback)
	if recipes.IDs() then
		callback()
	else
		table.insert(readyCallbacks, callback)
	end
end

-- Every recipe's ID, or nil until they're found.
function recipes.IDs()
	local data = Data()
	return Saved(data) and data.ids or nil
end

-- The recipes with this name (lower-case), from the spell names: { id, ... } or nil.
function recipes.ByName(lower)
	local ids = recipes.IDs()
	if not ids then
		return nil
	end
	if not byName then
		byName = {}
		for _, id in ipairs(ids) do
			local name = C_Spell.GetSpellName(id)
			if name then
				local key = name:lower()
				byName[key] = byName[key] or {}
				table.insert(byName[key], id)
			end
		end
	end
	return byName[lower]
end

-- The recipes a recipe item teaches, from its name ("Recipe: Clam Chowder", "Plans: ...",
-- "Formula: ..."): the game gives such items a generic "Learning" spell, not the recipe.
function recipes.FromItemName(name)
	local recipe = name and name:match("^[^:]+:%s*(.+)$")
	return recipe and recipes.ByName(recipe:lower()) or nil
end

function recipes.Count()
	local ids = Data().ids
	return ids and #ids or 0
end

-- What a recipe is worth: cost of one craft (reagents: vendor price if a vendor sells it, else
-- the auction house's), what it makes sells for (auction house, else vendor; times how many
-- it makes), profit; nil where unknown. `missing` = reagents without a price.
function recipes.Value(recipe)
	local prices, sell = ns.auctionator, ns.sellList
	local cost, missing = 0, 0
	for _, reagent in ipairs(recipe.reagents) do
		local unit = prices and prices.Unit and prices.Unit(reagent.itemID)
		if unit then
			cost = cost + unit * reagent.count
		else
			missing = missing + 1
		end
	end
	local sells
	if recipe.output then
		local each = sell and sell.AuctionPrice and sell.AuctionPrice(recipe.output)
		if not each or each <= 0 then
			each = select(11, C_Item.GetItemInfo(recipe.output))
		end
		if each and each > 0 then
			sells = each * (recipe.quantity or 1)
		end
	end
	local profit = sells and missing == 0 and (sells - cost) or nil
	return cost, sells, profit, missing
end

-- The professions that have recipes: your own first (as GetProfessions tells), then the rest
-- by name.
function recipes.Professions()
	local seen, list = {}, {}
	for _, id in ipairs(Data().ids or {}) do
		local profession = recipes.Get(id).profession
		if profession ~= "" and not seen[profession] then
			seen[profession] = true
			table.insert(list, profession)
		end
	end
	local mine = {}
	if GetProfessions and GetProfessionInfo then
		for _, index in pairs({ GetProfessions() }) do
			local name = index and GetProfessionInfo(index)
			if name then
				mine[name] = true
			end
		end
	end
	table.sort(list, function(a, b)
		if (mine[a] == true) ~= (mine[b] == true) then
			return mine[a] == true
		end
		return a < b
	end)
	return list, mine
end

-- Recipes whose name or profession contains query (lower-case; "" for all), of `profession`
-- (nil for all): their details, sorted by `sort` ("name", or "profit": most first), at most
-- `limit`; and how many matched.
function recipes.Search(query, limit, sort, profession)
	local matches = {}
	for _, id in ipairs(Data().ids or {}) do
		local recipe = recipes.Get(id)
		if (not profession or recipe.profession == profession)
			and (query == "" or recipe.lower:find(query, 1, true) or recipe.profession:lower():find(query, 1, true)) then
			table.insert(matches, recipe)
		end
	end
	if sort == "profit" then
		for _, recipe in ipairs(matches) do
			local _, _, profit = recipes.Value(recipe)
			recipe.sortProfit = profit or -math.huge
		end
		table.sort(matches, function(a, b)
			if a.sortProfit ~= b.sortProfit then
				return a.sortProfit > b.sortProfit
			end
			return a.name < b.name
		end)
	else
		table.sort(matches, function(a, b)
			local aStarts, bStarts = query ~= "" and a.lower:find(query, 1, true) == 1, query ~= "" and b.lower:find(query, 1, true) == 1
			if aStarts ~= bStarts then
				return aStarts
			end
			if a.name ~= b.name then
				return a.name < b.name
			end
			return a.id < b.id
		end)
	end
	local total = #matches
	for index = total, limit + 1, -1 do
		matches[index] = nil
	end
	return matches, total
end
