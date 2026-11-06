local _, ns = ...

-- Colors the health bars of the standard unit frames by class, but only when
-- the unit is a player. NPC bars are left with Blizzard's default coloring.

local module = {
	key = "classColorHealthBars",
	name = "Class-colored health bars",
	description = "Color the health bars on the player, target, target of target, focus and party frames by class when the unit is a player. NPCs keep their default color.",
	default = true,
}

local UNITS = {
	player = true,
	target = true,
	targettarget = true,
	focus = true,
	focustarget = true,
	party1 = true,
	party2 = true,
	party3 = true,
	party4 = true,
}

local DISCONNECTED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

local hookedBars = {}
-- Bars we have recolored, mapped to Blizzard's color/desaturation from before
-- we touched them, so we can put it back when the unit becomes an NPC.
local originalStates = {}

local function GetUnitClassColor(unit)
	local _, classFile = UnitClass(unit)
	if not classFile then
		return nil
	end
	if C_ClassColor and C_ClassColor.GetClassColor then
		return C_ClassColor.GetClassColor(classFile)
	end
	return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function SetBarColor(bar, color)
	if not originalStates[bar] then
		local r, g, b, a = bar:GetStatusBarColor()
		originalStates[bar] = {
			r = r, g = g, b = b, a = a,
			desaturated = bar.GetStatusBarDesaturated and bar:GetStatusBarDesaturated(),
		}
	end
	-- Modern health bar textures are pre-tinted green; desaturate so the class color shows true.
	if bar.SetStatusBarDesaturated then
		bar:SetStatusBarDesaturated(true)
	end
	bar:SetStatusBarColor(color.r, color.g, color.b)
end

local function RestoreBar(bar)
	local state = originalStates[bar]
	if not state then
		return
	end
	originalStates[bar] = nil
	if bar.SetStatusBarDesaturated then
		bar:SetStatusBarDesaturated(state.desaturated and true or false)
	end
	bar:SetStatusBarColor(state.r, state.g, state.b, state.a)
end

local function UpdateBar(bar)
	local unit = bar.unit
	if ns:IsModuleEnabled(module.key) and unit and UNITS[unit] and UnitIsPlayer(unit) then
		local color = UnitIsConnected(unit) and GetUnitClassColor(unit) or DISCONNECTED_COLOR
		SetBarColor(bar, color)
	else
		RestoreBar(bar)
	end
end

local function OnHealthBarUpdate(bar)
	if not bar or not bar.unit or not UNITS[bar.unit] then
		-- Bar may have been switched to e.g. "vehicle"; undo any coloring we did.
		if bar and hookedBars[bar] then
			RestoreBar(bar)
		end
		return
	end
	if not hookedBars[bar] then
		hookedBars[bar] = true
		-- Some Blizzard code recolors the bar on value change (classic health gradient);
		-- reapply after it so our color sticks.
		bar:HookScript("OnValueChanged", UpdateBar)
	end
	UpdateBar(bar)
end

function module:OnInitialize()
	hooksecurefunc("UnitFrameHealthBar_Update", OnHealthBarUpdate)
	if HealthBar_OnValueChanged then
		hooksecurefunc("HealthBar_OnValueChanged", function(bar)
			if hookedBars[bar] then
				UpdateBar(bar)
			end
		end)
	end
	self:Refresh()
end

function module:OnEnabledChanged()
	self:Refresh()
end

function module:Refresh()
	for bar in pairs(hookedBars) do
		UpdateBar(bar)
	end
end

ns:RegisterModule(module)
