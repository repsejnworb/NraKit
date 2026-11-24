-- Wishlist: adding items (command, drop, Item lookup's right-click), the window by slot
-- and filter, notes, ticking off items you get (with a message), and the tooltip line.

-- hooksecurefunc really hooks global functions here (loot rolls), and this feature's
-- timers run at once; other modules' don't run, as usual here.
local hook = hooksecurefunc
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then
		local original = _G[target]
		rawset(_G, target, function(...)
			original(...)
			name(...)
		end)
	else
		hook(target, name, fn)
	end
end
C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("Wishlist", 1, true) then
		callback()
	end
end

local SHOULDER, RING, CINCH, BOOTS = 7718, 2933, 9800, 4000
-- Items: name, quality, required level, slot.
local ITEMS = {
	[SHOULDER] = { "Herod's Shoulder", 3, 34, "INVTYPE_SHOULDER" },
	[RING] = { "Seal of Wrynn", 2, 20, "INVTYPE_FINGER" },
	[CINCH] = { "Bandit Cinch", 2, 25, "INVTYPE_WAIST" },
	[BOOTS] = { "Ironheel Boots", 2, 28, "INVTYPE_FEET" },
}
local function Link(id, name)
	return "|cff1eff00|Hitem:" .. id .. "::::::::30:::::|h[" .. (name or ITEMS[id][1]) .. "]|h|r"
end

return {
	enable = { "wishlist", "itemLookup" },
	run = function(t, ns, wow)
		local wishlist = ns.wishlist
		wow.data.level = 30
		wow.data.units.player = { name = "Nra", surname = "Brown" }
		local have = {} -- [itemID] = count in your bags
		local bagLinks = {} -- links in bag 0
		C_Item.GetItemInfo = function(item)
			local id = tonumber(tostring(item):match("item:(%d+)") or item)
			local info = ITEMS[id]
			if info then
				local name = tostring(item):match("|h%[(.-)%]|h") or info[1]
				return name, Link(id, name), info[2], 30, info[3], "Armor", "Mail", 1, info[4]
			end
		end
		C_Item.GetItemInfoInstant = function(id)
			local info = ITEMS[id]
			return id, "Armor", "Mail", info and info[4] or "", 1000 + id
		end
		C_Item.GetItemNameByID = function(id)
			return ITEMS[id] and ITEMS[id][1]
		end
		C_Item.GetItemCount = function(id)
			return have[id] or 0
		end
		C_Container.GetContainerNumSlots = function(bag)
			return bag == 0 and #bagLinks or 0
		end
		C_Container.GetContainerItemLink = function(bag, slot)
			return bag == 0 and bagLinks[slot] or nil
		end
		ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0, hex = "|cff1eff00" }, [3] = { r = 0, g = 0.4, b = 0.9, hex = "|cff0070dd" } }
		local toasts = {}
		ns.toast.Show = function(spec)
			table.insert(toasts, spec)
		end
		local menu
		MenuUtil.CreateContextMenu = function(owner, build)
			menu = wow.newMenu()
			build(owner, menu)
		end
		local function Slash(text)
			SlashCmdList.NRAKIT(text)
		end
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				local shown = rawget(frame, "text")
				if type(shown) == "string" and shown:find(text, 1, true) and wow.visible(frame) then
					return frame
				end
			end
		end
		-- The visible wishlist row of an item.
		local function Row(id)
			for _, frame in ipairs(wow.frames) do
				local item = rawget(frame, "item")
				if type(item) == "table" and item.entry and item.entry.id == id and wow.visible(frame) then
					return frame
				end
			end
		end
		local function Bags()
			wow.fire("BAG_UPDATE_DELAYED")
		end
		wow.advance(60) -- well past login: items you get now show a message

		t.test("/nra wishlist adds a shift-clicked item, with what follows as its note", function()
			Slash("wishlist " .. Link(SHOULDER) .. " Herod, Scarlet Monastery")
			local entry = wishlist.Get(SHOULDER)
			t.ok(entry, "added")
			t.equal(entry.note, "Herod, Scarlet Monastery", "note")
			t.ok(not entry.got, "not got")
			Slash("wish " .. Link(SHOULDER))
			t.equal(wishlist.Get(SHOULDER).note, "Herod, Scarlet Monastery", "adding it again keeps the note")
			t.equal(wishlist.Count(), 1, "once")
			t.ok(NraKitDB.wishlistData["Nra Brown"].items[SHOULDER], "saved for this character")
		end)

		t.test("an item you have already is ticked off without a message", function()
			have[RING] = 1
			Slash("wishlist " .. RING)
			t.ok(wishlist.Get(RING).got, "ticked off")
			t.equal(#toasts, 0, "no message")
		end)

		t.test("the window: a section per slot, the level to wear, filters", function()
			Slash("wishlist " .. Link(BOOTS))
			Slash("wishlist")
			t.ok(Shown("Shoulder") and Shown("Rings") and Shown("Feet"), "sections")
			t.ok(Shown("Level 34") and Shown("Got it"), "level and got")
			t.ok(Shown("Herod, Scarlet Monastery"), "note")
			wow.click("Got")
			t.ok(Row(RING) and not Row(SHOULDER), "Got: only the ring")
			wow.click("Ready")
			t.ok(Row(BOOTS) and not Row(SHOULDER) and not Row(RING), "Ready: what you can wear at 30")
			wow.click("Not yet")
			t.ok(Row(SHOULDER) and not Row(BOOTS), "Not yet: level 34")
			wow.click("All")
			t.ok(Row(SHOULDER) and Row(BOOTS) and Row(RING), "All")
		end)

		t.test("a section folds", function()
			wow.click("Shoulder")
			t.ok(not Row(SHOULDER) and Row(BOOTS), "folded")
			wow.click("Shoulder")
			t.ok(Row(SHOULDER), "unfolded")
		end)

		t.test("click a row to edit its note", function()
			local row = Row(BOOTS)
			row.scripts.OnClick(row, "LeftButton")
			local box
			for _, frame in ipairs(wow.frames) do
				if frame.template == "InputBoxTemplate" and wow.visible(frame) then
					box = frame
				end
			end
			t.ok(box, "a note box")
			box:SetText("Vendor, Ironforge")
			box.scripts.OnEnterPressed(box)
			t.equal(wishlist.Get(BOOTS).note, "Vendor, Ironforge", "saved")
			t.ok(Shown("Vendor, Ironforge"), "shown")
		end)

		t.test("getting an item ticks it off with a message", function()
			have[SHOULDER] = 1
			Bags()
			t.ok(wishlist.Get(SHOULDER).got, "ticked off")
			t.equal(#toasts, 1, "a message")
			t.ok(toasts[1].text:find("Herod's Shoulder", 1, true), toasts[1].text)
			Bags()
			t.equal(#toasts, 1, "only once")
		end)

		t.test("the right-click menu: not got, remove", function()
			local row = Row(SHOULDER)
			row.scripts.OnClick(row, "RightButton")
			wow.menuEntry(menu.entries, "Mark as not got").onClick()
			t.ok(not wishlist.Get(SHOULDER).got, "not got")
			row = Row(SHOULDER)
			row.scripts.OnClick(row, "RightButton")
			t.ok(wow.menuEntry(menu.entries, "Copy Wowhead link"), "Wowhead link")
			wow.menuEntry(menu.entries, "Remove from wishlist").onClick()
			t.ok(not wishlist.Get(SHOULDER), "removed")
			t.ok(not Row(SHOULDER), "gone from the window")
		end)

		t.test("an item with a random suffix only counts in that suffix", function()
			Slash("wishlist " .. Link(CINCH, "Bandit Cinch of the Monkey"))
			t.equal(wishlist.Get(CINCH).name, "Bandit Cinch of the Monkey", "the suffix is kept")
			have[CINCH] = 1
			bagLinks = { Link(CINCH, "Bandit Cinch of the Bear") }
			Bags()
			t.ok(not wishlist.Get(CINCH).got, "another suffix isn't it")
			bagLinks = { Link(CINCH, "Bandit Cinch of the Monkey") }
			Bags()
			t.ok(wishlist.Get(CINCH).got, "that suffix is")
		end)

		t.test("tooltip line with the note", function()
			local lines = {}
			rawset(GameTooltip, "AddLine", function(_, text)
				table.insert(lines, text)
			end)
			TooltipUtil.GetDisplayedItem = function()
				return nil, Link(BOOTS)
			end
			for _, call in ipairs(wow.tooltipCalls) do
				call.callback(GameTooltip, {})
			end
			t.ok(table.concat(lines, "\n"):find("NraKit: On your wishlist\nVendor, Ironforge", 1, true), table.concat(lines, " | "))
		end)

		t.test("dropping an item on the window adds it", function()
			wishlist.Remove(BOOTS)
			wow.dropItem(BOOTS)
			t.ok(wishlist.Get(BOOTS), "added")
		end)

		t.test("right-click in Item lookup adds to the wishlist", function()
			wishlist.Remove(SHOULDER)
			ns.itemLookup.Search = function()
				return { { id = SHOULDER, name = "Herod's Shoulder", quality = 3 } }, 1
			end
			ns:OpenItemLookup("herod")
			local row
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "itemID") == SHOULDER and wow.visible(frame) then
					row = frame
				end
			end
			t.ok(row, "the item in Item lookup")
			row.scripts.OnClick(row, "RightButton")
			wow.menuEntry(menu.entries, "Add to wishlist").onClick()
			t.ok(wishlist.Get(SHOULDER), "added")
		end)

		-- The star on a button: shown or not.
		local function Starred(button)
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "holder") and rawget(rawget(frame, "holder"), "parent") == button then
					return frame.shown
				end
			end
			return false
		end

		t.test("a star on wishlist items in Item lookup and loot rolls", function()
			local row
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "itemID") == SHOULDER and wow.visible(frame) then
					row = frame
				end
			end
			t.ok(Starred(row), "the Item lookup row of a wishlist item")
			row.scripts.OnClick(row, "RightButton")
			wow.menuEntry(menu.entries, "Remove from wishlist").onClick()
			t.ok(not Starred(row), "gone when it's removed")
			row.scripts.OnClick(row, "RightButton")
			wow.menuEntry(menu.entries, "Add to wishlist").onClick()
			t.ok(Starred(row), "back when it's added")

			local roll = CreateFrame("Frame")
			rawset(roll, "IconFrame", CreateFrame("Frame"))
			rawset(roll, "rollID", 1)
			GetLootRollItemLink = function()
				return Link(RING)
			end
			GroupLootFrame_SetupItemDisplay(roll)
			t.ok(Starred(roll.IconFrame), "a loot roll for a wishlist item")
			GetLootRollItemLink = function()
				return Link(4306, "Silk Cloth")
			end
			GroupLootFrame_SetupItemDisplay(roll)
			t.ok(not Starred(roll.IconFrame), "not for other items")
		end)

		t.test("right-click an item link in chat to add it, or take it off", function()
			wishlist.Remove(BOOTS)
			local link = Link(BOOTS)
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", ChatFrame1, link:match("|H(.-)|h"), link, "LeftButton")
			t.ok(not wishlist.Get(BOOTS), "a left-click just shows the item")
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", ChatFrame1, link:match("|H(.-)|h"), link, "RightButton")
			wow.menuEntry(menu.entries, "Add to wishlist").onClick()
			t.ok(wishlist.Get(BOOTS), "added")
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", ChatFrame1, link:match("|H(.-)|h"), link, "RightButton")
			wow.menuEntry(menu.entries, "Remove from wishlist").onClick()
			t.ok(not wishlist.Get(BOOTS), "taken off")
			local player = "|Hplayer:Bob|h[Bob]|h"
			menu = nil
			EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkClick", ChatFrame1, "player:Bob", player, "RightButton")
			t.ok(menu == nil, "no menu for other links")
		end)

		t.test("option: take items off once you have them", function()
			ns:SetSetting("wishlistRemoveGot", true)
			have[SHOULDER] = 0
			wishlist.SetGot(SHOULDER, false)
			have[SHOULDER] = 1
			Bags()
			t.ok(not wishlist.Get(SHOULDER), "taken off")
			t.noErrors()
		end)
	end,
}
