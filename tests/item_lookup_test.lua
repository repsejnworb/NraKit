-- Item lookup: learning item names in the background from a stand-in server, items the
-- server won't name yet (not in Forever, or not discovered), searching, and the window.

-- The client's items (GetItemInfoInstant knows them) and what the server says about them.
local ITEMS = {
	[2589] = { name = "Linen Cloth" },
	[4306] = { name = "Silk Cloth" },
	[10000] = { name = "Bolt of Linen Cloth", minLevel = 10 },
	[20000] = { name = "Hidden Blade", undiscovered = true }, -- nobody has found it yet
	[20001] = { name = "Lost Item", silent = true }, -- the server never answers
	[300000] = { name = "Nightblade", quality = 4, minLevel = 60 },
}
local loaded, requested = {}, {}
local build = "100"
local now = 1000000

GetBuildInfo = function()
	return "1.0.0", build
end
time = function()
	return now
end
C_Item.GetItemInfoInstant = function(itemID)
	if ITEMS[itemID] then
		return itemID, "Weapon", "Swords", "", 135274, 2, 7
	end
end
C_Item.GetItemInfo = function(itemID)
	local item = ITEMS[itemID]
	if item and loaded[itemID] then
		return item.name, "|Hitem:" .. itemID .. "|h[" .. item.name .. "]|h", item.quality or 1, 10, item.minLevel or 1
	end
	requested[itemID] = true
end

return {
	enable = { "itemLookup" },
	run = function(t, ns, wow)
		local lookup = ns.itemLookup

		-- The server answers everything asked so far, as it would.
		local function Answer()
			local asked = requested
			requested = {}
			for itemID in pairs(asked) do
				local item = ITEMS[itemID]
				if item and not item.silent then
					if not item.undiscovered then
						loaded[itemID] = true
					end
					wow.fire("GET_ITEM_INFO_RECEIVED", itemID, not item.undiscovered)
				end
			end
		end
		local function Run(seconds)
			for _ = 1, seconds * 4 do
				wow.advance(0.25)
				Answer()
			end
		end
		local function Names(matches)
			local names = {}
			for _, match in ipairs(matches) do
				table.insert(names, match.name)
			end
			return table.concat(names, ", ")
		end

		t.test("finds the client's items, then learns their names", function()
			local _, total = lookup.Progress()
			t.equal(total, nil, "still finding item IDs")
			Run(5)
			local named, total2, done = lookup.Progress()
			t.equal(total2, 6, "six items")
			t.equal(named, 4, "four named")
			t.ok(not done, "still waiting on the silent one")
			t.equal(NraKitDB.itemLookupData.names[300000], "Nightblade", "saved")
			t.equal(NraKitDB.itemLookupData.quality[300000], 4, "quality saved")
			t.ok(NraKitDB.itemLookupData.failed[20000], "undiscovered item noted")
		end)

		t.test("an unanswered request counts as failed, and then it's done", function()
			Run(20)
			t.ok(NraKitDB.itemLookupData.failed[20001], "silent item noted")
			local _, _, done = lookup.Progress()
			t.ok(done, "done")
		end)

		t.test("search: names starting with it first, then by quality and name", function()
			local matches, total = lookup.Search("linen", 10)
			t.equal(total, 2, "two")
			t.equal(Names(matches), "Linen Cloth, Bolt of Linen Cloth", "order")
			matches = lookup.Search("cloth", 2)
			t.equal(#matches, 2, "capped")
			t.equal(select(2, lookup.Search("cloth", 1)), 3, "total still counts all")
			t.equal(select(2, lookup.Search("hidden", 10)), 0, "undiscovered items aren't listed")
		end)

		t.test("items the game loads anyway are added", function()
			ITEMS[6948] = { name = "Hearthstone" }
			loaded[6948] = true
			wow.fire("GET_ITEM_INFO_RECEIVED", 6948, true)
			t.equal(Names(lookup.Search("hearth", 5)), "Hearthstone", "found")
		end)

		t.test("/nra item opens the window with the search", function()
			SlashCmdList.NRAKIT("item nightbl")
			t.ok(NraKitItemLookupFrame:IsShown(), "window open")
			local rows = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "itemID") ~= nil
			end)
			t.equal(#rows, 1, "one row")
			t.equal(rows[1].itemID, 300000, "Nightblade")
			t.equal(rows[1].level:GetText(), "Level 60", "required level")
			t.noErrors()
		end)

		t.test("a new game version asks again for the items that had no name", function()
			NraKitItemLookupFrame:Hide()
			ITEMS[20000].undiscovered = nil -- someone found it
			build = "101"
			ns:SetSetting("itemLookup", false)
			ns:SetSetting("itemLookup", true)
			Run(5)
			t.equal(NraKitDB.itemLookupData.names[20000], "Hidden Blade", "found now")
			t.equal(NraKitDB.itemLookupData.failed[20000], nil, "no longer failed")
		end)

		t.test("a failed item is asked again after a day, but not in combat", function()
			Run(20) -- the silent one fails again
			t.ok(NraKitDB.itemLookupData.failed[20001], "failed")
			requested = {}
			ns:SetSetting("itemLookup", false)
			ns:SetSetting("itemLookup", true)
			Run(2)
			t.equal(requested[20001], nil, "not again the same day")
			now = now + 2 * 24 * 3600
			ns:SetSetting("itemLookup", false)
			ns:SetSetting("itemLookup", true)
			wow.data.inCombat = true
			for _ = 1, 8 do
				wow.advance(0.25)
			end
			t.equal(requested[20001], nil, "not in combat")
			wow.data.inCombat = false
			wow.advance(0.25)
			t.ok(requested[20001], "asked again after a day")
		end)

		t.test("nothing is asked while off", function()
			requested = {}
			ns:SetSetting("itemLookup", false)
			Run(2)
			t.equal(next(requested), nil, "nothing while off")
			t.noErrors()
		end)
	end,
}
