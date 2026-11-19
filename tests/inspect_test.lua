-- Inspect anything: NraKit's inspect window. Players get their gear (copied when it arrives,
-- kept when they leave, loaded after combat), NPCs the model and what can be read of them.

local inspected, notified, dressedUp, clicked = {}, {}, {}, {}
local cleared = 0
local cursorX, cursorY = 500, 500
local SECRET = setmetatable({}, { __tostring = function()
	return "secret"
end })

-- The window's title (Blizzard's frame template sets it with SetTitle).
local createFrame = CreateFrame
CreateFrame = function(kind, name, ...)
	local frame = createFrame(kind, name, ...)
	if name == "NraKitModelViewer" then
		rawset(frame, "SetTitle", function(self, title)
			rawset(self, "titleValue", title)
		end)
	end
	return frame
end

local LINKS = {
	[1] = "|cff1eff00|Hitem:10001::::::::40:::::|h[Green Helm]|h|r",
	[16] = "|cffa335ee|Hitem:10016::::::::40:::::|h[Purple Axe]|h|r",
	[18] = "|cff1eff00|Hitem:10018::::::::40:::::|h[Green Bow]|h|r",
}

return {
	enable = { "inspectAnything" },
	run = function(t, ns, wow)
		local units = wow.data.units
		CanInspect = function(unit)
			return units[unit] and units[unit].isPlayer == true and not units[unit].far
		end
		InspectUnit = function(unit)
			table.insert(inspected, unit)
		end
		NotifyInspect = function(unit)
			table.insert(notified, unit)
		end
		ClearInspectPlayer = function()
			cleared = cleared + 1
		end
		local notLoaded = {} -- [slot] = true: the item is there, its link hasn't come yet
		GetInventoryItemLink = function(unit, slot)
			return units[unit] and units[unit].isPlayer and not notLoaded[slot] and LINKS[slot] or nil
		end
		GetInventoryItemID = function(unit, slot)
			return units[unit] and units[unit].isPlayer and LINKS[slot] and (10000 + slot) or nil
		end
		GetInventorySlotInfo = function(name)
			return 0, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name
		end
		C_PaperDollInfo = { GetInspectItemLevel = function()
			return 31.5
		end }
		GetInspectSpecialization = function()
			return 71
		end
		local specName = "Arms"
		GetSpecializationInfoByID = function()
			return 71, specName
		end
		C_TransmogCollection = { GetInspectItemTransmogInfoList = function()
			return { "outfit" }
		end }
		DressUpItemTransmogInfoList = function(list)
			table.insert(dressedUp, list)
		end
		HandleModifiedItemClick = function(link)
			table.insert(clicked, link)
		end
		UnitLevel = function(unit)
			return units[unit] and units[unit].level
		end
		UnitClassification = function(unit)
			return units[unit] and units[unit].classification or "normal"
		end
		UnitCreatureType = function(unit)
			return units[unit] and units[unit].creatureType
		end
		UnitCreatureFamily = function(unit)
			return units[unit] and units[unit].family
		end
		UnitIsPlayer = function(unit)
			return units[unit] and units[unit].isPlayer == true
		end
		UnitRace = function(unit)
			local race = units[unit] and units[unit].race
			return race, race and race:gsub(" ", "")
		end
		UnitHealthMax = function(unit)
			return units[unit] and units[unit].health
		end
		UnitAttackSpeed = function(unit)
			return units[unit] and units[unit].attackSpeed
		end
		GetCursorPosition = function()
			return cursorX, cursorY
		end
		issecretvalue = function(value)
			return value == SECRET
		end
		-- Blizzard's panel layout (a "Panel" name would otherwise be a stand-in frame).
		GetUIPanelLayoutAttribute = function(name)
			return ({ LEFT_OFFSET = 16, TOP_OFFSET = -116 })[name]
		end

		local GRUNT = { name = "Grunt", surname = "Axe", isPlayer = true, level = 40, race = "Orc", guid = "Player-1-00000001" }
		local HOGGER = { name = "Hogger", level = 11, classification = "elite", creatureType = "Humanoid",
			guid = "Creature-0-1-2-3-448-0000ABCD" }

		local model, applied = nil, {}
		local function FindModel()
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "PlayerModel" then
					model = frame
				end
			end
			rawset(model, "GetEffectiveScale", function()
				return 1
			end)
			for _, method in ipairs({ "SetFacing", "SetCamDistanceScale" }) do
				rawset(model, method, function(_, value)
					applied[method] = value
				end)
			end
		end
		local function Title()
			return rawget(NraKitModelViewer, "titleValue")
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
		end
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					return true
				end
			end
			return false
		end
		-- The visible gear slot showing this link.
		local function Slot(link)
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "slotID") and wow.visible(frame) and rawget(frame, "link") == link then
					return frame
				end
			end
		end
		local function Inspect(unit, data)
			units.mouseover, units.target = nil, nil
			units[unit] = data
			NraKit_InspectAnything()
		end

		t.test("nothing to inspect says so", function()
			NraKit_InspectAnything()
			t.ok(Printed("Point at or target someone"), "message")
		end)

		t.test("an NPC: model, level and type, no gear slots", function()
			Inspect("target", HOGGER)
			t.ok(NraKitModelViewer:IsShown(), "window open")
			t.equal(Title(), "Hogger", "name")
			t.ok(Shown("Level 11 Elite Humanoid"), "level line")
			t.equal(Slot(nil), nil, "no slots for NPCs")
			t.equal(#notified, 0, "no inspect asked for")
			t.ok(wow.click("Abilities on Wowhead"), "Wowhead button")
			t.ok(not wow.click("Blizzard's inspect"), "no Blizzard's inspect button")
			FindModel()
		end)

		t.test("a player: gear asked for, then shown with spec and item level", function()
			Inspect("mouseover", GRUNT)
			t.equal(notified[1], "mouseover", "inspect asked for")
			t.equal(Title(), "Grunt Axe", "full name")
			t.ok(Shown("Loading their gear..."), "loading")
			t.equal(#inspected, 0, "Blizzard's window not opened")
			wow.fire("INSPECT_READY", GRUNT.guid)
			t.ok(Slot(LINKS[1]), "helm in its slot")
			t.ok(Slot(LINKS[16]), "axe in its slot")
			t.ok(Slot(LINKS[18]), "bow in the ranged slot")
			t.ok(Shown("·  Arms  ·  Item level 31.5"), "spec and item level, by the level line")
			t.equal(cleared, 1, "inspect data cleared after copying")
			local helm = Slot(LINKS[1])
			helm.scripts.OnClick(helm)
			t.equal(clicked[1], LINKS[1], "Shift-click links it")
		end)

		t.test("players get their race's background, greyed and darkened per race; NPCs plain black", function()
			local function Tiles()
				local files, shade = {}, nil
				for _, frame in ipairs(wow.frames) do
					local file = rawget(frame, "file")
					if wow.visible(frame) and type(file) == "string" and file:find("DressUpBackground", 1, true) then
						table.insert(files, file)
					end
				end
				table.sort(files)
				return table.concat(files, " ")
			end
			Inspect("target", { name = "Baine", surname = "Hoof", isPlayer = true, race = "Tauren", level = 30,
				guid = "Player-1-00000010" })
			local path = "Interface\\DressUpFrame\\DressUpBackground-Tauren"
			t.equal(Tiles(), path .. "1 " .. path .. "2 " .. path .. "3 " .. path .. "4", "four Tauren tiles")
			Inspect("target", HOGGER)
			t.equal(Tiles(), "", "none for an NPC")
			Inspect("mouseover", GRUNT)
		end)

		t.test("no spec on Forever: the class name the game gives instead isn't repeated", function()
			specName = "Warrior" -- the stand-in's class
			local orgrim = { name = "Orgrim", surname = "Hammer", isPlayer = true, level = 40, guid = "Player-1-00000009" }
			Inspect("target", orgrim)
			wow.fire("INSPECT_READY", orgrim.guid)
			t.ok(Shown("·  Item level 31.5"), "just the item level")
			specName = "Arms"
			Inspect("mouseover", GRUNT)
		end)

		t.test("it stays when they leave: target change, mouse off, out of sight", function()
			units.mouseover = nil
			wow.fire("PLAYER_TARGET_CHANGED")
			wow.fire("GROUP_ROSTER_UPDATE")
			t.ok(NraKitModelViewer:IsShown(), "still open")
			t.equal(Title(), "Grunt Axe", "same player")
			t.ok(Slot(LINKS[16]), "gear kept")
			t.ok(wow.click("Dressing room"), "dressing room")
			t.equal(dressedUp[1][1], "outfit", "their outfit")
		end)

		t.test("Blizzard's inspect: only nearby and out of combat", function()
			t.ok(wow.click("Blizzard's inspect"), "button")
			t.ok(Printed("need to be near you"), "they're gone")
			units.target = GRUNT
			wow.data.inCombat = true
			wow.click("Blizzard's inspect")
			t.ok(Printed("can't be opened by addons in combat"), "not in combat")
			wow.data.inCombat = false
			wow.click("Blizzard's inspect")
			t.equal(inspected[1], "target", "opened for them")
			t.ok(not NraKitModelViewer:IsShown(), "ours closes, theirs opens in its place")
		end)

		t.test("in combat, gear arrives after combat (asked again when it ends)", function()
			local thrall = { name = "Thrall", surname = "Doom", isPlayer = true, level = 60, guid = "Player-1-00000002" }
			wow.data.inCombat = true
			Inspect("target", thrall)
			t.ok(Printed("gear shows up after combat"), "says so")
			t.ok(Shown("Their gear loads after combat..."), "status")
			local asked = #notified
			wow.data.inCombat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			t.equal(#notified, asked + 1, "asked again")
			t.ok(Shown("Loading their gear..."), "loading")
			wow.fire("INSPECT_READY", thrall.guid)
			t.ok(Slot(LINKS[1]), "gear in")
		end)

		t.test("gear that arrives when they're out of sight can't be read; the window stays", function()
			local rexxar = { name = "Rexxar", surname = "Wild", isPlayer = true, level = 60, guid = "Player-1-00000003" }
			Inspect("target", rexxar)
			units.target = nil
			wow.fire("INSPECT_READY", rexxar.guid)
			t.equal(Slot(LINKS[1]), nil, "no gear")
			t.ok(NraKitModelViewer:IsShown(), "window stays")
			t.equal(Title(), "Rexxar Wild", "still them")
		end)

		-- Regression: often only 1-2 items showed; the rest load after the first answer.
		t.test("items that load after the answer fill in, then the inspect data is let go", function()
			local varian = { name = "Varian", surname = "Wrynn", isPlayer = true, level = 60, guid = "Player-1-00000006" }
			notLoaded[16], notLoaded[18] = true, true
			local clearedBefore = cleared
			Inspect("target", varian)
			wow.fire("INSPECT_READY", varian.guid)
			t.ok(Slot(LINKS[1]), "the loaded helm")
			t.equal(Slot(LINKS[16]), nil, "the axe hasn't come yet")
			local waiting = false
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "slotID") == 16 and rawget(frame, "itemID") == 10016 and wow.visible(frame) then
					waiting = true
				end
			end
			t.ok(waiting, "its slot shows the item already (by ID)")
			t.equal(cleared, clearedBefore, "inspect data kept while reading")
			notLoaded[16] = nil
			wow.advance(0.5)
			t.ok(Slot(LINKS[16]), "the axe came in")
			notLoaded[18] = nil
			wow.advance(0.5)
			t.ok(Slot(LINKS[18]), "the bow too")
			t.equal(cleared, clearedBefore + 1, "then let go")
		end)

		-- Regression: gear sometimes needed a second key press; it's asked for again by itself.
		t.test("no answer: asked again every 2 seconds while they're near, then it gives up", function()
			local jaina = { name = "Jaina", surname = "Sea", isPlayer = true, level = 60, guid = "Player-1-00000005" }
			Inspect("target", jaina)
			local asked = #notified
			wow.advance(1)
			t.equal(#notified, asked, "not yet")
			wow.advance(1)
			t.equal(#notified, asked + 1, "asked again")
			units.target = nil -- out of sight: nothing to ask with
			wow.advance(2)
			t.equal(#notified, asked + 1, "not while they're gone")
			units.target = jaina
			for _ = 1, 10 do
				wow.advance(2)
			end
			t.ok(#notified <= asked + 8, "gives up after a while: " .. (#notified - asked))
			t.ok(Shown("Their gear can't be read now: too far away?"), "says so")
			wow.fire("INSPECT_READY", jaina.guid)
			t.equal(Slot(LINKS[1]), nil, "a late answer after giving up isn't used")
			NraKit_InspectAnything()
			wow.fire("INSPECT_READY", jaina.guid)
			t.ok(Slot(LINKS[1]), "the key starts over")
		end)

		t.test("a player you can't inspect: model, and a word in chat", function()
			local far = { name = "Ann", surname = "Hill", isPlayer = true, far = true, level = 30, guid = "Player-1-00000004" }
			Inspect("target", far)
			t.equal(Title(), "Ann Hill", "shown")
			t.ok(Printed("can't inspect them right now"), "says why")
			t.ok(Shown("Their gear can't be read now: too far away?"), "status")
		end)

		t.test("a player inspected before shows their gear again at once", function()
			Inspect("target", GRUNT)
			t.ok(Slot(LINKS[16]), "gear from before")
		end)

		t.test("turn, zoom and reset", function()
			model.scripts.OnMouseDown(model, "LeftButton")
			cursorX = cursorX + 50
			model.scripts.OnUpdate(model, 0.1)
			model.scripts.OnMouseUp(model, "LeftButton")
			t.ok(math.abs(applied.SetFacing - 1) < 0.001, "turned by the drag")
			model.scripts.OnMouseWheel(model, 1)
			t.ok(math.abs(applied.SetCamDistanceScale - 0.9) < 0.001, "zoomed in")
			t.ok(wow.click("Reset view"), "reset button")
			t.equal(applied.SetFacing, 0, "facing reset")
			t.equal(applied.SetCamDistanceScale, 1, "zoom reset")
		end)

		t.test("NPC stats: secret health shows as it is, attack speed when readable, a beast's family", function()
			Inspect("target", { name = "Mangy Wolf", level = 6, creatureType = "Beast", family = "Wolf",
				health = SECRET, attackSpeed = 2, guid = "Creature-0-1-2-3-525-0000ABCD" })
			t.ok(Shown("Level 6 Beast (Wolf)"), "family after the type")
			t.ok(Shown(SECRET), "secret health handed to the text as it is")
			t.ok(Shown("2.0 s"), "attack speed")
			units.target.attackSpeed = SECRET -- in combat
			NraKit_InspectAnything()
			t.ok(not Shown("Attack speed"), "secret attack speed left out")
			wow.click("Abilities on Wowhead")
			local found
			for _, frame in ipairs(wow.frames) do
				if type(frame.text) == "string" and frame.text:find("wowhead.com/forever/npc=525", 1, true) then
					found = true
				end
			end
			t.ok(found, "npc link in the copy box")
		end)

		t.test("secret names and GUIDs still show a model", function()
			Inspect("target", { name = SECRET, surname = SECRET, level = SECRET, guid = SECRET })
			t.equal(Title(), SECRET, "the secret name is passed straight to the title")
			t.ok(not wow.click("Abilities on Wowhead"), "no Wowhead link without an NPC ID")
			t.noErrors()
		end)

		t.test("a UI panel out of combat (others push it aside); in combat, where the inspect window is", function()
			t.equal(wow.panels[NraKitModelViewer].area, "left", "a left panel, like the inspect window")
			NraKitModelViewer:Hide()
			wow.panelShown = nil
			Inspect("target", HOGGER)
			t.equal(wow.panelShown, NraKitModelViewer, "opened with ShowUIPanel")
			NraKitModelViewer:Hide()
			wow.panelShown = nil
			local placed
			rawset(NraKitModelViewer, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
				placed = { point, relativeTo, relativePoint, x, y }
			end)
			wow.data.inCombat = true
			Inspect("target", HOGGER)
			wow.data.inCombat = false
			t.equal(wow.panelShown, nil, "not as a panel in combat (Blizzard blocks it)")
			t.ok(NraKitModelViewer:IsShown(), "shown anyway")
			t.equal(placed and placed[1], "TOPLEFT", "point")
			t.equal(placed[4], 16, "left offset")
			t.equal(placed[5], -116, "top offset")
			placed = nil
			NraKit_InspectAnything()
			t.equal(placed, nil, "not moved while open (it may have been dragged)")
		end)

		t.test("View 3D model in the right-click menu of NPCs and enemy players", function()
			NraKitModelViewer:Hide()
			units.focus = { name = "Gnoll Brute", level = 12 }
			local entry = wow.menuEntry(wow.openMenu("MENU_UNIT_FOCUS", { unit = "focus" }), "View 3D model")
			t.ok(entry, "in the focus menu")
			entry.onClick()
			t.ok(NraKitModelViewer:IsShown(), "window open")
			t.equal(Title(), "Gnoll Brute", "the focus")
			t.ok(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), "target menu")
			t.ok(wow.menuEntry(wow.openMenu("MENU_UNIT_ENEMY_PLAYER", { unit = "target" }), "View 3D model"), "enemy players")
			ns:SetSetting("inspectAnythingMenu", false)
			t.equal(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), nil, "option off")
			ns:SetSetting("inspectAnythingMenu", true)
		end)

		t.test("does nothing while off", function()
			ns:SetSetting("inspectAnything", false)
			t.ok(not NraKitModelViewer:IsShown(), "closed when turned off")
			Inspect("target", HOGGER)
			t.ok(not NraKitModelViewer:IsShown(), "stays closed")
			t.equal(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), nil, "no menu entry")
			t.noErrors()
		end)
	end,
}
