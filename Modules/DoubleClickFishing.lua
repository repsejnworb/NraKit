local _, ns = ...

-- Double-click fishing: with a fishing pole in your main hand, double right-click the world
-- to cast Fishing (like Fishing Ace! and Fishing Buddy's Easy Cast did).
--
-- Casting is protected, so a secure button casts it. On the second right press within the
-- double-click time, right-click is bound to that button for a moment (an override binding);
-- releasing the mouse then clicks it, a real click of yours, and the binding is removed
-- right after. Bindings can't change in combat, so it does nothing then. Right-clicks on a
-- unit (an NPC, a player) are left alone, and so is holding right-click to turn the camera
-- (one long press is never a double-click).
--
-- Forever has the old ranked Fishing spells; the button casts your highest one.

local module = {
	key = "doubleClickFishing",
	section = "Professions",
	name = "Double-click fishing",
	description = "With a fishing pole in your main hand, double right-click the world to cast Fishing. Right-clicking NPCs and players, and holding right-click to turn the camera, work as normal.",
	default = false,
	options = {
		{
			key = "doubleClickFishingSpeed",
			type = "number",
			name = "Double-click time",
			description = "How quickly the second right-click has to follow the first.",
			default = 400, min = 200, max = 800, step = 50, format = "%d ms",
		},
	},
}

local BUTTON_NAME = "NraKitFishingButton"
-- Fishing, highest rank first (Grand Master, Master... in the old ranked style).
local FISHING_SPELLS = { 18248, 7732, 7731, 7620 }
local KEEP_BINDING = 1 -- seconds; removed by then even if the release never came

local fishing = {}
ns.doubleClickFishing = fishing

local button
local lastPress = 0

function fishing.Spell()
	for _, spellID in ipairs(FISHING_SPELLS) do
		if IsPlayerSpell(spellID) then
			return spellID
		end
	end
end

function fishing.HasPole()
	local itemID = GetInventoryItemID("player", INVSLOT_MAINHAND or 16)
	if not itemID then
		return false
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID == Enum.ItemClass.Weapon and subclassID == Enum.ItemWeaponSubclass.Fishingpole
end

local function ClearBinding()
	if button and not InCombatLockdown() then
		ClearOverrideBindings(button)
	end
end

local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetAttribute("type", "spell")
	button:SetAttribute("useOnKeyDown", false) -- cast on the release
	button:RegisterForClicks("AnyUp")
	button:SetScript("PostClick", ClearBinding)
end

function fishing.OnMouseDown(_, mouseButton)
	if mouseButton ~= "RightButton" or not ns:IsModuleEnabled(module.key) then
		return
	end
	local now = GetTime()
	local isDouble = now - lastPress < (ns:GetValue("doubleClickFishingSpeed") or 400) / 1000
	lastPress = isDouble and 0 or now -- a third press starts over
	if not isDouble or InCombatLockdown() or UnitExists("mouseover") or not fishing.HasPole() then
		return
	end
	local spellID = fishing.Spell()
	if not spellID then
		return
	end
	button:SetAttribute("spell", spellID)
	SetOverrideBindingClick(button, true, "BUTTON2", BUTTON_NAME)
	C_Timer.After(KEEP_BINDING, ClearBinding)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", ClearBinding) -- PLAYER_REGEN_DISABLED: still allowed here

function module:OnInitialize()
	CreateButton()
	WorldFrame:HookScript("OnMouseDown", fishing.OnMouseDown)
	eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function module:OnEnabledChanged()
	ClearBinding()
end

ns:RegisterModule(module)
