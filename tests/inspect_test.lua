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
			NraKit_InspectAnything()
			t.equal(Title(), "Ann Hill", "full name")
			units.target = { name = SECRET, surname = SECRET, level = SECRET }
			NraKit_InspectAnything()
			t.equal(Title(), SECRET, "the secret name is passed straight to the title")
			t.noErrors()
		end)

		t.test("does nothing while off", function()
			ns:SetSetting("inspectAnything", false)
			t.ok(not NraKitModelViewer:IsShown(), "closed when turned off")
			units.target = { name = "Hogger", level = 11 }
			NraKit_InspectAnything()
			t.ok(not NraKitModelViewer:IsShown(), "stays closed")
			t.noErrors()
		end)
	end,
}
