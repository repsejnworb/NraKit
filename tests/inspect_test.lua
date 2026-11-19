-- Inspect anything: the key inspects players and shows NPCs in the model viewer, which
-- turns, moves and zooms, follows your target, and copes with secret names.

local inspected = {}
local cursorX, cursorY = 500, 500
local SECRET = setmetatable({}, { __tostring = function()
	return "secret"
end })

return {
	enable = { "inspectAnything" },
	run = function(t, ns, wow)
		local units = wow.data.units
		CanInspect = function(unit)
			return units[unit] and units[unit].isPlayer == true
		end
		InspectUnit = function(unit)
			table.insert(inspected, unit)
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
		UnitIsPlayer = function(unit)
			return units[unit] and units[unit].isPlayer == true
		end
		UnitRace = function(unit)
			return units[unit] and units[unit].race
		end
		GetCursorPosition = function()
			return cursorX, cursorY
		end
		issecretvalue = function(value)
			return value == SECRET
		end
		UnitHealthMax = function(unit)
			return units[unit] and units[unit].health
		end
		UnitAttackSpeed = function(unit)
			return units[unit] and units[unit].attackSpeed
		end
		UnitCreatureFamily = function(unit)
			return units[unit] and units[unit].family
		end
		UnitGUID = function(unit)
			return units[unit] and units[unit].guid
		end
		-- Blizzard's panel layout (a "Panel" name would otherwise be a stand-in frame).
		GetUIPanelLayoutAttribute = function(name)
			return ({ LEFT_OFFSET = 16, TOP_OFFSET = -116 })[name]
		end

		local model, shownUnit, applied = nil, nil, {}
		local function FindModel()
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "PlayerModel" then
					model = frame
				end
			end
			rawset(model, "SetUnit", function(_, unit)
				shownUnit = unit
			end)
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
			return NraKitModelViewer.title:GetText()
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
		end

		t.test("nothing to inspect says so", function()
			NraKit_InspectAnything()
			t.ok(Printed("Point at or target someone"), "message")
		end)

		t.test("an NPC opens the model viewer", function()
			units.target = { name = "Hogger", level = 11, classification = "elite", creatureType = "Humanoid" }
			NraKit_InspectAnything()
			t.ok(NraKitModelViewer:IsShown(), "viewer open")
			t.equal(Title(), "Hogger", "name")
			FindModel()
			ns.inspectAnything.ShowModel("target")
			t.equal(shownUnit, "target", "model of the target")
			local found = false
			for _, frame in ipairs(wow.frames) do
				if frame.text == "Level 11 Elite Humanoid" then
					found = true
				end
			end
			t.ok(found, "level, elite and type")
			t.equal(#inspected, 0, "not inspected")
		end)

		t.test("a player you can inspect gets the inspect window, the mouse comes first", function()
			units.mouseover = { name = "Bob", surname = "Stone", isPlayer = true }
			NraKit_InspectAnything()
			t.equal(inspected[1], "mouseover", "inspected what's under the mouse")
			t.equal(Title(), "Hogger", "viewer untouched")
			units.mouseover = nil
		end)

		-- Regression: opening the inspect window in combat was blocked ("Interface action failed").
		t.test("in combat a player gets the model viewer, not the blocked inspect window", function()
			units.mouseover = { name = "Grunt", surname = "Axe", isPlayer = true }
			wow.data.inCombat = true
			NraKit_InspectAnything()
			t.equal(#inspected, 1, "inspect window not opened")
			t.equal(Title(), "Grunt Axe", "model shown")
			t.ok(Printed("can't open in combat"), "says why")
			wow.data.inCombat = false
			units.mouseover = nil
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

		t.test("follows your target while open, unless switched off", function()
			units.target = { name = "Mother Fang", level = 10, classification = "rare", creatureType = "Beast" }
			wow.fire("PLAYER_TARGET_CHANGED")
			t.equal(Title(), "Mother Fang", "followed")
			ns:SetSetting("inspectAnythingFollowTarget", false)
			units.target = { name = "Kobold Vermin", level = 2 }
			wow.fire("PLAYER_TARGET_CHANGED")
			t.equal(Title(), "Mother Fang", "not followed")
			ns:SetSetting("inspectAnythingFollowTarget", true)
		end)

		t.test("a player you can't inspect shows their full name; secret names still show", function()
			units.target = { name = "Ann", surname = "Hill", level = 30, race = "Human" }
			units.target.isPlayer = false -- can't inspect (say, too far)
			local isPlayer = UnitIsPlayer
			UnitIsPlayer = function()
				return true
			end
			NraKit_InspectAnything()
			UnitIsPlayer = isPlayer
			t.equal(Title(), "Ann Hill", "full name")
			t.ok(Printed("can't inspect them right now"), "says why")
			units.target = { name = SECRET, surname = SECRET, level = SECRET }
			NraKit_InspectAnything()
			t.equal(Title(), SECRET, "the secret name is passed straight to the title")
			t.noErrors()
		end)

		t.test("opens where the inspect window does", function()
			local placed
			rawset(NraKitModelViewer, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
				placed = { point, relativeTo, relativePoint, x, y }
			end)
			NraKitModelViewer:Hide()
			NraKit_InspectAnything()
			t.ok(placed, "placed when opened")
			t.equal(placed[1], "TOPLEFT", "point")
			t.equal(placed[4], 16, "left offset")
			t.equal(placed[5], -116, "top offset")
			placed = nil
			wow.fire("PLAYER_TARGET_CHANGED")
			t.equal(placed, nil, "not moved while open (it may have been dragged)")
		end)

		t.test("View 3D model in the right-click menu of NPCs and enemy players", function()
			NraKitModelViewer:Hide()
			units.focus = { name = "Gnoll Brute", level = 12 }
			local entry = wow.menuEntry(wow.openMenu("MENU_UNIT_FOCUS", { unit = "focus" }), "View 3D model")
			t.ok(entry, "in the focus menu")
			entry.onClick()
			t.ok(NraKitModelViewer:IsShown(), "viewer open")
			t.equal(Title(), "Gnoll Brute", "the focus")
			t.ok(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), "target menu")
			t.ok(wow.menuEntry(wow.openMenu("MENU_UNIT_ENEMY_PLAYER", { unit = "target" }), "View 3D model"), "enemy players")
			ns:SetSetting("inspectAnythingMenu", false)
			t.equal(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), nil, "option off")
			ns:SetSetting("inspectAnythingMenu", true)
		end)

		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					return true
				end
			end
			return false
		end

		t.test("stats: secret health shows as it is, attack speed when readable, a beast's family", function()
			units.target = { name = "Mangy Wolf", level = 6, creatureType = "Beast", family = "Wolf",
				health = SECRET, attackSpeed = 2, guid = "Creature-0-1-2-3-525-0000ABCD" }
			ns.inspectAnything.ShowModel("target")
			t.ok(Shown("Level 6 Beast (Wolf)"), "family after the type")
			t.ok(Shown(SECRET), "secret health handed to the text as it is")
			t.ok(Shown("2.0 s"), "attack speed")
			units.target.attackSpeed = SECRET -- in combat
			units.target.health = 1500 -- a player's is readable
			ns.inspectAnything.ShowModel("target")
			t.ok(Shown("1,500") or Shown("1500"), "readable health formatted")
			t.ok(not Shown("Attack speed"), "secret attack speed left out")
			t.noErrors()
		end)

		t.test("Abilities on Wowhead opens the NPC's Wowhead link", function()
			units.target = { name = "Mangy Wolf", level = 6, guid = "Creature-0-1-2-3-525-0000ABCD" }
			ns.inspectAnything.ShowModel("target")
			t.ok(wow.click("Abilities on Wowhead"), "button")
			local found
			for _, frame in ipairs(wow.frames) do
				if type(frame.text) == "string" and frame.text:find("wowhead.com/forever/npc=525", 1, true) then
					found = true
				end
			end
			t.ok(found, "npc link in the copy box")
			units.target = { name = "Bob", surname = "Stone", isPlayer = true, guid = "Player-1-0000ABCD" }
			ns.inspectAnything.ShowModel("target")
			t.ok(not wow.click("Abilities on Wowhead"), "not for players")
			units.target = { name = "Mangy Wolf", level = 6, guid = SECRET }
			ns.inspectAnything.ShowModel("target")
			t.ok(not wow.click("Abilities on Wowhead"), "not when the GUID is secret")
			t.noErrors()
		end)

		t.test("does nothing while off", function()
			ns:SetSetting("inspectAnything", false)
			t.ok(not NraKitModelViewer:IsShown(), "closed when turned off")
			units.target = { name = "Hogger", level = 11 }
			NraKit_InspectAnything()
			t.ok(not NraKitModelViewer:IsShown(), "stays closed")
			t.equal(wow.menuEntry(wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), "View 3D model"), nil, "no menu entry")
			t.noErrors()
		end)
	end,
}
