local _, ns = ...

-- Item Lookup: search every item in the game by name (/nra item nightbl). The window is
-- ItemLookupWindow.lua; this file keeps the list of names it searches.
--
-- The game can't search items by name, and the client only knows the names of items it
-- has loaded. So the list fills in the background: every item ID the client has
-- (C_Item.GetItemInfoInstant answers those without the server) is asked for once, a few
-- dozen a second, lowest IDs first, paused in combat. The names are kept in saved data,
-- since the client forgets them again. Any item the game loads anyway (tooltips, loot,
-- chat links) is added too.
--
-- Items the server doesn't answer for (not in Forever, or not discovered by anyone yet)
-- are asked again after a day, or right away with "Check again" in the window. When the
-- game version changes, the walk starts over for the items without a name. The window can
-- pause it (remembered until resumed).
--
-- Data (account-wide): NraKitDB.itemLookupData = { build, cursor, paused, names = { [id] = name },
--   quality = { [id] = quality }, failed = { [id] = time() } }.

local module = {
	key = "itemLookup",
	section = "Tools",
	name = "Item Lookup",
	description = "Search every item in the game by name: /nra item nightbl lists the matching items in a window, with their tooltips. The list of names fills in by itself in the background (a few minutes, once per game version).",
	default = false,
}

local MAX_ID = 400000 -- highest item ID checked (Forever's went up to about 292000)
local SCAN_CHUNK = 25000 -- item IDs checked per frame while finding them
local SEND_INTERVAL = 0.25 -- seconds between batches of requests
local BATCH = 10 -- requests per batch
local MAX_PENDING = 40 -- unanswered requests at once
local TIMEOUT = 15 -- seconds before an unanswered request counts as failed
local RETRY_AFTER = 24 * 3600 -- seconds before a failed item is asked again

local lookup = {}
ns.itemLookup = lookup

local ids -- every item ID the client has, ascending; nil until found
local scanFrom = 1
local named, failedCount = 0, 0
local pending, pendingCount = {}, 0
local retryQueue -- failed IDs to ask again, once the first walk is done
local lowerNames = {} -- [id] = lower-case name, for searching
local sinceSend = 0
local crawler = CreateFrame("Frame")
crawler:Hide()

local function Data()
	NraKitDB.itemLookupData = NraKitDB.itemLookupData or { names = {}, quality = {}, failed = {} }
	return NraKitDB.itemLookupData
end

local function BuildKey()
	local version, build = GetBuildInfo()
	return tostring(version) .. "." .. tostring(build)
end

local function Store(itemID)
	local name, _, quality = C_Item.GetItemInfo(itemID)
	if not name then
		return false
	end
	local data = Data()
	if not data.names[itemID] then
		named = named + 1
	end
	if data.failed[itemID] then
		data.failed[itemID] = nil
		failedCount = failedCount - 1
	end
	data.names[itemID] = name
	data.quality[itemID] = quality ~= 1 and quality or nil -- most items are common
	lowerNames[itemID] = nil
	if lookup.onStored then
		lookup.onStored(itemID, name)
	end
	return true
end

local function Fail(itemID)
	local data = Data()
	if not data.failed[itemID] then
		failedCount = failedCount + 1
	end
	data.failed[itemID] = time()
end

local function Request(itemID)
	if Store(itemID) then
		return -- already loaded
	end
	pending[itemID] = GetTime()
	pendingCount = pendingCount + 1
end

-- The next item to ask for: the first walk in ID order, then failed ones that are due.
local function NextItem()
	local data = Data()
	local now = time()
	while data.cursor and data.cursor <= #ids do
		local itemID = ids[data.cursor]
		data.cursor = data.cursor + 1
		local failedAt = data.failed[itemID]
		if not data.names[itemID] and not pending[itemID] and not (failedAt and now - failedAt < RETRY_AFTER) then
			return itemID
		end
	end
	data.cursor = nil -- the first walk is done
	if not retryQueue then
		retryQueue = {}
		for itemID, failedAt in pairs(data.failed) do
			if now - failedAt >= RETRY_AFTER then
				table.insert(retryQueue, itemID)
			end
		end
		table.sort(retryQueue)
	end
	return table.remove(retryQueue, 1)
end

local function FinishScan()
	local data = Data()
	named, failedCount = 0, 0
	for _, itemID in ipairs(ids) do
		if data.names[itemID] then
			named = named + 1
		elseif data.failed[itemID] then
			failedCount = failedCount + 1
		end
	end
	if lookup.onStored then
		lookup.onStored()
	end
end

crawler:SetScript("OnUpdate", function(self, elapsed)
	if not ids then
		-- Find the item IDs the client has, a chunk per frame.
		local found = self.found or {}
		self.found = found
		local last = math.min(scanFrom + SCAN_CHUNK - 1, MAX_ID)
		for itemID = scanFrom, last do
			if C_Item.GetItemInfoInstant(itemID) then
				table.insert(found, itemID)
			end
		end
		scanFrom = last + 1
		if scanFrom > MAX_ID then
			ids, self.found = found, nil
			FinishScan()
		end
		return
	end

	local now = GetTime()
	for itemID, sentAt in pairs(pending) do
		if now - sentAt > TIMEOUT then
			pending[itemID] = nil
			pendingCount = pendingCount - 1
			Fail(itemID)
		end
	end

	sinceSend = sinceSend + elapsed
	if sinceSend < SEND_INTERVAL or InCombatLockdown() then
		return
	end
	sinceSend = 0
	for _ = 1, BATCH do
		if pendingCount >= MAX_PENDING then
			return
		end
		local itemID = NextItem()
		if not itemID then
			if pendingCount == 0 then
				self:Hide() -- all done until the next session
			end
			return
		end
		Request(itemID)
	end
end)

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, itemID, success)
	if not itemID then
		return
	end
	local wasPending = pending[itemID]
	if wasPending then
		pending[itemID] = nil
		pendingCount = pendingCount - 1
	end
	if success then
		Store(itemID)
	elseif wasPending then
		Fail(itemID)
	end
end)

------------------------------------------------------------------------------
-- API for the window
------------------------------------------------------------------------------

-- How far the list is: { named, total (nil while the item IDs are still being found),
-- paused, done }.
function lookup.Progress()
	local paused = Data().paused == true
	return {
		named = named,
		total = ids and #ids,
		paused = paused,
		done = ids ~= nil and not paused and not crawler:IsShown(),
	}
end

local function Run()
	if ns:IsModuleEnabled(module.key) and not Data().paused then
		crawler:Show()
	end
end

function lookup.SetPaused(paused)
	Data().paused = paused or nil
	if paused then
		crawler:Hide()
		-- Answers still arrive and are kept; nothing waits on them.
		wipe(pending)
		pendingCount = 0
	else
		Run()
	end
end

-- Asks again now for every item that had no name (newly discovered ones, say).
function lookup.CheckAgain()
	local data = Data()
	for itemID in pairs(data.failed) do
		data.failed[itemID] = 0
	end
	retryQueue = nil
	lookup.SetPaused(false)
end

-- Items whose name contains query (lower-case): { { id, name, quality }, ... }, best
-- first (names starting with it, then by quality and name), at most `limit`; and how
-- many matched in all.
function lookup.Search(query, limit)
	local data = Data()
	local matches = {}
	for itemID, name in pairs(data.names) do
		local lower = lowerNames[itemID]
		if not lower then
			lower = name:lower()
			lowerNames[itemID] = lower
		end
		local at = lower:find(query, 1, true)
		if at then
			table.insert(matches, { id = itemID, name = name, quality = data.quality[itemID] or 1, starts = at == 1 })
		end
	end
	table.sort(matches, function(a, b)
		if a.starts ~= b.starts then
			return a.starts
		end
		if a.quality ~= b.quality then
			return a.quality > b.quality
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

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function Start()
	local data = Data()
	local build = BuildKey()
	if data.build ~= build then
		-- New game version: new items, and the ones that failed may exist now.
		data.build, data.cursor, data.failed = build, 1, {}
	end
	retryQueue = nil -- failed items that are due by now
	eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	Run()
end

local function Stop()
	eventFrame:UnregisterAllEvents()
	crawler:Hide()
	wipe(pending)
	pendingCount = 0
end

function module:OnInitialize()
	local help = {
		summary = "Item Lookup: search every item in the game by name",
		usage = {
			"/nra item <name> - list the items whose name contains it (also /nra items)",
			"/nra item - open the item lookup window",
		},
	}
	local function OnSlashCommand(input)
		if not ns:IsModuleEnabled(module.key) then
			ns:Print("Turn on Item Lookup first (/nra).")
			return
		end
		ns:OpenItemLookup(input)
	end
	ns:RegisterSlashCommand("item", OnSlashCommand, help)
	ns:RegisterSlashCommand("items", OnSlashCommand, help)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	if enabled then
		Start()
	else
		Stop()
	end
end

ns:RegisterModule(module)
