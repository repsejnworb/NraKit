local _, ns = ...

-- Debug logging for features (ns:Debug): what a feature does where it depends on the game
-- (moving items, docking, events Forever may not send...), to find out why something odd
-- happened in game. Off by default; /nra debug <feature> turns a feature's on.
--
--   ns:RegisterDebug("sell", "Sell List: taking from the bank and mail")   -- once, at load
--   ns:Debug("sell", "move %d from %d:%d", amount, bag, slot)              -- cheap when off
--
-- Lines go to chat ("NraKit debug (sell): ...") and to the last DEBUG_KEEP, which
-- /nra debug copy shows in a box to select and copy (chat copies badly: some lines come out
-- as "???"). Which features log is saved (NraKitDB.debugOn), so it survives /reload; a line in
-- chat after logging in says it's on, so it isn't forgotten.

local UI = ns.UI
local DEBUG_KEEP = 200

local features = {} -- name -> description, in the order registered
local order = {}
local lines = {} -- the last DEBUG_KEEP lines

local function On()
	NraKitDB.debugOn = NraKitDB.debugOn or {}
	return NraKitDB.debugOn
end

function ns:RegisterDebug(name, description)
	if not features[name] then
		table.insert(order, name)
	end
	features[name] = description
end

function ns:IsDebugging(name)
	return NraKitDB ~= nil and NraKitDB.debugOn ~= nil and NraKitDB.debugOn[name] == true
end

-- Logs a line for a feature, if its debug is on. With more arguments, `text` is a format.
function ns:Debug(name, text, ...)
	if not self:IsDebugging(name) then
		return
	end
	if select("#", ...) > 0 then
		text = string.format(text, ...)
	end
	local line = string.format("%s %s: %s", date("%H:%M:%S"), name, tostring(text))
	table.insert(lines, line)
	if #lines > DEBUG_KEEP then
		table.remove(lines, 1)
	end
	print("|cffff9933NraKit debug (" .. name .. "):|r " .. tostring(text))
end

-- The lines kept (for the copy box, and tests).
function ns:DebugLines()
	return lines
end

---------------------------------------------------------------------------
-- The copy box
---------------------------------------------------------------------------

local box

local function ShowCopyBox()
	if not box then
		box = UI.CreateWindow("NraKitDebugCopyFrame", "NraKit debug log", 640, 420, 0)
		box:SetFrameStrata("DIALOG")
		local hint = box.titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("RIGHT", -36, 0)
		hint:SetText("Ctrl+A, then Ctrl+C to copy")
		local scroll = CreateFrame("ScrollFrame", nil, box.body, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", UI.PAD, -UI.PAD)
		scroll:SetPoint("BOTTOMRIGHT", -30, UI.PAD)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(580)
		edit:SetScript("OnEscapePressed", function()
			box:Hide()
		end)
		-- Read-only: put the log back if anything is typed.
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(box.text)
			end
		end)
		scroll:SetScrollChild(edit)
		box.edit = edit
	end
	box.text = #lines > 0 and table.concat(lines, "\n") or "(nothing logged yet: turn a feature's debug on with /nra debug <feature>)"
	box.edit:SetText(box.text)
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
end
ns.ShowDebugCopyBox = ShowCopyBox

---------------------------------------------------------------------------
-- /nra debug
---------------------------------------------------------------------------

local function OnNames()
	local names = {}
	for _, name in ipairs(order) do
		if ns:IsDebugging(name) then
			table.insert(names, name)
		end
	end
	return names
end

local function List()
	ns:Print("debug logging (/nra debug <name> to turn one on or off):")
	for _, name in ipairs(order) do
		print(string.format("  |cffffd100%s|r %s  %s", name, ns:IsDebugging(name) and "|cff4cff4con|r" or "|cff808080off|r",
			features[name]))
	end
	print("  |cffffd100/nra debug copy|r - the last lines, to copy;  |cffffd100/nra debug off|r - all off")
end

function ns:SetDebug(name, on)
	On()[name] = on or nil
	ns:Print(string.format("debug for %s %s.", name, on and "on: its lines show in chat (/nra debug copy to copy them)" or "off"))
end

local function OnDebugCommand(rest)
	local name = (rest or ""):lower():match("^(%S*)")
	if name == "" then
		List()
	elseif name == "off" then
		wipe(On())
		ns:Print("debug off for everything.")
	elseif name == "copy" then
		ShowCopyBox()
	elseif features[name] then
		ns:SetDebug(name, not ns:IsDebugging(name))
	else
		ns:Print("No debug called \"" .. name .. "\". /nra debug lists them.")
	end
end

ns:RegisterSlashCommand("debug", OnDebugCommand, {
	summary = "Debug logging for features, to report a problem",
	usage = {
		"/nra debug - list what can log, and what's on",
		"/nra debug <name> - turn one on or off (e.g. /nra debug sell)",
		"/nra debug copy - the last lines in a box, to copy",
		"/nra debug off - turn all of it off",
	},
})

-- After logging in: a reminder when something is logging, so it isn't left on unnoticed.
local reminder = CreateFrame("Frame")
reminder:RegisterEvent("PLAYER_LOGIN")
reminder:SetScript("OnEvent", function()
	C_Timer.After(6, function()
		local on = OnNames()
		if #on > 0 then
			ns:Print("debug logging is on for " .. table.concat(on, ", ") .. " (/nra debug off to stop).")
		end
	end)
end)
