-- Quests to turn in: finished quests by turn-in zone, the window's clicks, and the reminder.

-- The quest log: headings and quests ({ title, id, done, map }).
local LOG = {
	{ header = "Wetlands" },
	{ title = "The Doomed Fleet", id = 1, done = true, map = 1437 },
	{ title = "Unfinished Business", id = 2, done = false, map = 1437 },
	{ header = "Stormwind" },
	{ title = "Hemet Nesingwary", id = 3, done = true, map = 1434, level = 32 }, -- turned in in Stranglethorn
	{ header = "Loch Modan" },
	{ title = "Find Bingles", id = 4, done = true, map = 1432 },
	{ title = "No Map", id = 5, done = true },
}
local MAPS = { [1437] = "Wetlands", [1434] = "Stranglethorn Vale", [1432] = "Loch Modan" }
local opened, superTracked, linked = {}, 0, {}

-- The shared arrival message waits a moment for other features' parts: run that at once.
C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("Toast", 1, true) then
		callback()
	end
end

return {
	enable = { "turnInQuests" },
	run = function(t, ns, wow)
		C_QuestLog.GetNumQuestLogEntries = function()
			return #LOG
		end
		C_QuestLog.GetInfo = function(index)
			local entry = LOG[index]
			return entry and { title = entry.header or entry.title, isHeader = entry.header ~= nil, questID = entry.id }
		end
		C_QuestLog.IsComplete = function(id)
			for _, entry in ipairs(LOG) do
				if entry.id == id then
					return entry.done
				end
			end
		end
		C_QuestLog.GetQuestDifficultyLevel = function(id)
			for _, entry in ipairs(LOG) do
				if entry.id == id then
					return entry.level
				end
			end
		end
		GetQuestDifficultyColor = function(level)
			return { r = 1, g = level > 30 and 0.5 or 1, b = 0 }
		end
		GetQuestUiMapID = function(id)
			for _, entry in ipairs(LOG) do
				if entry.id == id then
					return entry.map or 0
				end
			end
		end
		C_Map.GetMapInfo = function(mapID)
			return MAPS[mapID] and { name = MAPS[mapID] }
		end
		QuestMapFrame_OpenToQuestDetails = function(id)
			table.insert(opened, id)
		end
		C_SuperTrack = {
			GetSuperTrackedQuestID = function()
				return superTracked
			end,
			SetSuperTrackedQuestID = function(id)
				superTracked = id
			end,
		}
		GetQuestLink = function(id)
			return "|Hquest:" .. id .. "|h[quest]|h"
		end
		ChatFrameUtil.InsertLink = function(link)
			table.insert(linked, link)
		end
		local shift = false
		IsModifiedClick = function(kind)
			return kind == "CHATLINK" and shift
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
		end
		-- World positions: maps' centres and the player, on continent 1 (Stranglethorn on 2).
		local CENTRES = { [1437] = { 1, 100, 0 }, [1432] = { 1, 300, 0 }, [1434] = { 2, 0, 0 }, [9999] = { 1, 300, 0 } }
		local playerMap = 9999 -- where the player stands: (300, 0) on continent 1
		CreateVector2D = function(x, y)
			return { x = x, y = y, GetXY = function(self)
				return self.x, self.y
			end }
		end
		C_Map.GetBestMapForUnit = function()
			return playerMap
		end
		C_Map.GetPlayerMapPosition = function()
			return CreateVector2D(0.5, 0.5)
		end
		C_Map.GetWorldPosFromMapPos = function(mapID)
			local centre = CENTRES[mapID]
			if centre then
				return centre[1], CreateVector2D(centre[2], centre[3])
			end
		end
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					return frame
				end
			end
		end
		local function Row(title)
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "questID") and wow.visible(frame) and rawget(frame, "title") == title then
					return frame
				end
			end
		end

		t.test("finished quests by turn-in zone, the zone you're in first", function()
			wow.data.zone = "Loch Modan"
			local zones = ns.turnInQuests.Zones()
			local list = {}
			for _, zone in ipairs(zones) do
				local titles = {}
				for _, quest in ipairs(zone.quests) do
					table.insert(titles, quest.title)
				end
				table.insert(list, zone.zone .. ": " .. table.concat(titles, ", "))
			end
			t.equal(table.concat(list, " | "),
				"Loch Modan: Find Bingles, No Map | Wetlands: The Doomed Fleet | Stranglethorn Vale: Hemet Nesingwary",
				"grouped by where they're turned in (the log's heading without a map)")
		end)

		t.test("/nra done opens the window; clicks show the map, set the waypoint, link", function()
			SlashCmdList.NRAKIT("done")
			t.ok(NraKitTurnInFrame:IsShown(), "window open")
			local row = Row("Hemet Nesingwary")
			t.ok(row, "a row per quest")
			t.equal(row.text:GetText(), "[32] Hemet Nesingwary", "level in front")
			row.scripts.OnClick(row, "LeftButton")
			t.equal(opened[1], 3, "map opened on the quest")
			row.scripts.OnClick(row, "RightButton")
			t.equal(superTracked, 3, "waypoint set")
			row = Row("Hemet Nesingwary")
			row.scripts.OnClick(row, "RightButton")
			t.equal(superTracked, 0, "and cleared")
			row = Row("Hemet Nesingwary")
			row.poi.scripts.OnClick(row.poi, "LeftButton")
			t.equal(superTracked, 3, "its round quest icon sets the waypoint too")
			t.equal(Row("Hemet Nesingwary").poi.selected, true, "and lights up")
			row = Row("Hemet Nesingwary")
			row.poi.scripts.OnClick(row.poi, "LeftButton")
			t.equal(superTracked, 0, "clicked again: cleared")
			row = Row("Hemet Nesingwary") -- the list redraws (and reuses rows) after a waypoint change
			shift = true
			row.scripts.OnClick(row, "LeftButton")
			shift = false
			t.ok(linked[1] and linked[1]:find("quest:3", 1, true), "linked")
			wow.data.inCombat = true
			row.scripts.OnClick(row, "LeftButton")
			wow.data.inCombat = false
			t.equal(#opened, 1, "no map in combat")
			t.ok(Printed("can't be opened by addons in combat"), "says so")
			SlashCmdList.NRAKIT("done")
			t.ok(not NraKitTurnInFrame:IsShown(), "toggled closed")
		end)

		t.test("zones by distance: here, then nearest on this continent, then other continents", function()
			wow.data.zone = "Elwynn Forest" -- nothing to turn in here
			CENTRES[1432] = { 1, 300, 0 } -- standing at Loch Modan's centre
			local order = {}
			for _, zone in ipairs(ns.turnInQuests.Zones()) do
				table.insert(order, zone.zone)
			end
			t.equal(table.concat(order, ", "), "Loch Modan, Wetlands, Stranglethorn Vale", "nearest first")
			CENTRES[1432] = { 1, 900, 0 } -- Loch Modan now further away than Wetlands
			order = {}
			for _, zone in ipairs(ns.turnInQuests.Zones()) do
				table.insert(order, zone.zone)
			end
			t.equal(table.concat(order, ", "), "Wetlands, Loch Modan, Stranglethorn Vale", "re-sorted")
			CENTRES[1432] = { 1, 300, 0 }
		end)

		t.test("entering a zone with turn-ins shows a toast (once); clicking it opens the list", function()
			wow.data.zone = "Wetlands"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(Shown("|cffffd1001 QUEST TO TURN IN|r") and Shown("Wetlands") and Shown("|cffffd100QUESTS|r")
				and Shown("|cff999999•|r  The Doomed Fleet"), "toast: how many, the zone, then a QUESTS section with the quest")
			t.ok(not Printed("to turn in here in Wetlands"), "no chat line by default")
			local holder = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "onClick") ~= nil
			end)[1]
			holder.scripts.OnMouseUp(holder)
			t.ok(NraKitTurnInFrame:IsShown(), "clicked: the list opens")
			NraKitTurnInFrame:Hide()
			ns:SetSetting("turnInQuestsChat", true)
			wow.data.zone = "Loch Modan"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(Printed("2 quests to turn in here in Loch Modan: Find Bingles, No Map"), "chat line when asked for")
			local lines = #wow.printed
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(#wow.printed, lines, "not again in the same zone")
			ns:SetSetting("turnInQuestsAutoOpen", true)
			wow.data.zone = "Stranglethorn Vale"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(NraKitTurnInFrame:IsShown(), "opened there")
			NraKitTurnInFrame:Hide()
			ns:SetSetting("turnInQuestsReminder", false)
			ns:SetSetting("turnInQuestsAutoOpen", false)
			wow.data.zone = "Loch Modan"
			lines = #wow.printed
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(#wow.printed, lines, "no reminder when switched off")
		end)

		t.test("does nothing while off", function()
			ns:SetSetting("turnInQuests", false)
			wow.data.zone = "Wetlands"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			SlashCmdList.NRAKIT("done")
			t.ok(not NraKitTurnInFrame:IsShown(), "no window")
			t.ok(Printed("Turn on Quests to turn in first"), "says how")
			t.noErrors()
		end)
	end,
}
