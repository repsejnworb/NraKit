-- Damage Meter Look: a stand-in of the game's damage meter (one window, one row), skinned.

local FLAT = "Interface\\Buttons\\WHITE8X8"

-- hooksecurefunc really hooks methods here, so the meter's calls reach the module.
local hook = hooksecurefunc
hooksecurefunc = function(target, name, fn)
	if type(target) == "table" then
		local original = target[name]
		rawset(target, name, function(...)
			original(...)
			fn(...)
		end)
	else
		hook(target, name, fn)
	end
end

-- A bar row: a status bar whose fill Blizzard colours.
local function NewRow()
	local row = CreateFrame("Button")
	local fill = CreateFrame("Texture")
	fill:SetTexture("blizzard-bar")
	rawset(row.StatusBar, "GetStatusBarTexture", function()
		return fill
	end)
	return row, fill
end

local row, fill = NewRow()
local window = CreateFrame("Frame")
local scrollBox = CreateFrame("Frame") -- (the stand-in would take "ScrollBox" for a method)
rawset(scrollBox, "ForEachFrame", function(_, fn)
	fn(row)
end)
rawset(window.MinimizeContainer, "ScrollBox", scrollBox)
DamageMeter = CreateFrame("Frame")
DamageMeterSessionWindow1 = window

-- What the title and the combat timer are anchored to: anchors[name][point] = relativeTo.
local anchors = { timer = {}, title = {} }
for name, frame in pairs({ timer = window.SessionTimer, title = window.DamageMeterTypeDropdown }) do
	rawset(frame, "SetPoint", function(_, point, relativeTo)
		anchors[name][point] = relativeTo
	end)
end

local popup
StaticPopupDialogs = {}
StaticPopup_Show = function(name)
	popup = name
end

return {
	enable = { "damageMeterLook" },
	run = function(t, ns, wow)
		local function Glyph(text)
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "CreateFontString" and frame.text == text then
					return frame
				end
			end
		end

		t.test("the meter gets the flat look", function()
			t.equal(window.Header:GetHeight(), 22, "a thin header")
			t.equal(fill:GetTexture(), FLAT, "a flat bar")
			t.equal(fill:GetAlpha(), 0.55, "in a softer colour")
			t.equal(row.StatusBar.BackgroundEdge.shown, false, "Blizzard's bar edge hidden")
			t.ok(Glyph("-"), "a small minimize glyph")
		end)

		-- Regression: the combat timer sat before the title and pushed it right when it appeared.
		t.test("the title keeps its place; the combat timer comes after it", function()
			t.equal(anchors.title.LEFT, window.Header, "the title starts at the header's left")
			t.ok(anchors.timer.LEFT ~= nil and anchors.timer.LEFT ~= window.Header, "the timer is anchored after the title")
		end)

		t.test("a new row is skinned once; a style change skins it again", function()
			local newRow, newFill = NewRow()
			window:InitEntry(newRow)
			t.equal(newFill:GetTexture(), FLAT, "skinned when it appears")
			newFill:SetTexture("changed")
			window:InitEntry(newRow)
			t.equal(newFill:GetTexture(), "changed", "not again on every meter update")
			newRow:UpdateStyle()
			t.equal(newFill:GetTexture(), FLAT, "again after Blizzard restyles it")
		end)

		-- Regression: they stayed visible after a reload until the first hover.
		t.test("the header buttons hide again when something shows them, without a hover first", function()
			wow.advance(0)
			window.SettingsDropdown:SetAlpha(1)
			window.MinimizeButton:SetAlpha(1)
			wow.advance(0)
			t.equal(window.SettingsDropdown:GetAlpha(), 0, "settings hidden again")
			t.equal(window.MinimizeButton:GetAlpha(), 0, "minimize hidden again")
		end)

		t.test("the header buttons show while the mouse is over the meter", function()
			wow.advance(0)
			t.equal(window.SettingsDropdown:GetAlpha(), 0, "hidden at rest")
			rawset(window, "mouseOver", true)
			wow.advance(0)
			t.equal(window.SettingsDropdown:GetAlpha(), 1, "shown on hover")
			rawset(window, "mouseOver", false)
			ns:SetSetting("damageMeterLookHover", false)
			wow.advance(0)
			t.equal(window.SettingsDropdown:GetAlpha(), 1, "always, with the option off")
		end)

		t.test("minimized, the glyph says so", function()
			window.MinimizeContainer:Hide()
			wow.advance(0)
			t.ok(Glyph("+"), "+")
			window.MinimizeContainer:Show()
			wow.advance(0)
			t.ok(Glyph("-"), "- again")
		end)

		t.test("turning it off asks for a reload", function()
			ns:SetSetting("damageMeterLook", false)
			t.equal(popup, "NRAKIT_DAMAGE_METER_RELOAD", "reload prompt")
			t.noErrors()
		end)

		t.test("/nra dps flips the game's damage meter setting (the look on or off)", function()
			local cvars = { damageMeterEnabled = "1" }
			C_CVar.GetCVarBool = function(name) return cvars[name] == "1" end
			C_CVar.SetCVar = function(name, value) cvars[name] = value end
			SlashCmdList.NRAKIT("dps")
			t.equal(cvars.damageMeterEnabled, "0", "hidden")
			t.ok(wow.printed[#wow.printed]:find("hidden", 1, true), "says so")
			SlashCmdList.NRAKIT("dps")
			t.equal(cvars.damageMeterEnabled, "1", "shown again")
			SlashCmdList.NRAKIT("dps show")
			t.equal(cvars.damageMeterEnabled, "1", "show keeps it shown")
			SlashCmdList.NRAKIT("dps hide")
			t.equal(cvars.damageMeterEnabled, "0", "hide")
			-- Edit Mode set to show it in combat only: said when showing it.
			rawset(DamageMeter, "visibility", Enum.DamageMeterVisibility.InCombat)
			SlashCmdList.NRAKIT("dps")
			t.ok(wow.printed[#wow.printed]:find("in combat only", 1, true), "visibility: " .. wow.printed[#wow.printed])
			t.ok(wow.printed[#wow.printed]:find("Always in Edit Mode", 1, true), "and how to make it always show")
			rawset(DamageMeter, "visibility", nil)
			C_DamageMeter = { IsDamageMeterAvailable = function() return false end }
			SlashCmdList.NRAKIT("dps")
			t.equal(cvars.damageMeterEnabled, "1", "not available: left alone")
			t.ok(wow.printed[#wow.printed]:find("isn't available", 1, true), "says so")
			C_DamageMeter = nil
			t.noErrors()
		end)
	end,
}
