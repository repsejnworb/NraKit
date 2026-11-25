local _, ns = ...

-- Unlearned abilities: after a respec, the abilities you lost stay on your bars, only greyed
-- out like anything you can't use right now. This marks them (a red cross in the corner
-- and a tooltip line), and when your spells change it says which ones on your bars you no
-- longer know (click to take them off) and which new ones aren't on your bars yet.
--
-- Bar buttons are protected: we only put a non-clickable overlay on them, and read
-- button.action. Taking actions off the bars (PickupAction) waits until out of combat.
-- "Your spells" are the spellbook's base spells (not stance or talent overrides), so they
-- only change when you learn or unlearn something.

local module = {
	key = "unlearnedAbilities",
	section = "Trackers & Reminders",
	name = "Unlearned abilities",
	description = "Mark abilities on your action bars that you don't know anymore (after a respec, say) with a red cross and a tooltip line. When your spells change, say which ones on your bars you lost (click to take them off) and which new ones aren't on your bars.",
	default = false,
	options = {
		{
			key = "unlearnedAbilitiesMark",
			header = "General",
			name = "Mark them on your bars",
			description = "A red cross in the corner of action buttons with an ability you don't know anymore, and a line in their tooltip.",
			default = true,
		},
		{
			key = "unlearnedAbilitiesNotify",
			name = "Tell me when my spells change",
			description = "After a respec (or learning new spells), show which abilities on your bars you lost, with a click to take them off, and which new ones aren't on your bars yet.",
			default = true,
		},
	},
}

-- Every action bar's buttons (the names Blizzard's tutorials use).
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
	"MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local MAX_SLOT = 180
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TOAST_SECONDS = 15
local MAX_LISTED = 4
local MAX_NEW = 8 -- more new spells at once than this isn't learning, it's the spellbook loading

local unlearned = {}
ns.unlearnedAbilities = unlearned

local marks = {} -- button -> overlay frame
local hooked = {} -- button -> true
local known -- [spellID] = true: the spellbook's spells at the last look (nil until the first)
local removeQueued = false

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Whether you know a spell, or it's in your spellbook (overrides count, e.g. a stance's version).
function unlearned.IsKnown(spellID)
	if C_SpellBook.IsSpellKnownOrInSpellBook then
		return C_SpellBook.IsSpellKnownOrInSpellBook(spellID) == true
	end
	return (C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID)) or (IsPlayerSpell and IsPlayerSpell(spellID))
end

-- The spell in an action slot if it's one you don't know, else nil.
function unlearned.UnknownSpell(slot)
	if not slot then
		return nil
	end
	local actionType, id, subType = GetActionInfo(slot)
	if IsSecret(actionType) or IsSecret(id) or actionType ~= "spell" or subType == "pet" or type(id) ~= "number" then
		return nil
	end
	if C_Spell.DoesSpellExist and not C_Spell.DoesSpellExist(id) then
		return nil
	end
	local base = C_SpellBook.FindBaseSpellByID and C_SpellBook.FindBaseSpellByID(id) or id
	if unlearned.IsKnown(id) or unlearned.IsKnown(base) then
		return nil
	end
	return id
end

-- Action slots with spells you don't know: { [slot] = spellID }.
function unlearned.Slots()
	local slots = {}
	for slot = 1, MAX_SLOT do
		local spellID = unlearned.UnknownSpell(slot)
		if spellID then
			slots[slot] = spellID
		end
	end
	return slots
end

local function SpellName(spellID)
	return C_Spell.GetSpellName(spellID) or ("spell " .. spellID)
end

-- "A, B, C and 2 more"
local function NameList(spellIDs)
	local names = {}
	for index, spellID in ipairs(spellIDs) do
		if index > MAX_LISTED then
			table.insert(names, string.format("%d more", #spellIDs - MAX_LISTED))
			break
		end
		table.insert(names, SpellName(spellID))
	end
	return table.concat(names, ", ")
end

------------------------------------------------------------------------------
-- Marks on the bars
------------------------------------------------------------------------------

local function Mark(button)
	local mark = marks[button]
	if not mark then
		mark = CreateFrame("Frame", nil, button)
		mark:SetAllPoints()
		mark:EnableMouse(false)
		mark:SetFrameLevel(button:GetFrameLevel() + 5)
		mark.shade = mark:CreateTexture(nil, "OVERLAY")
		mark.shade:SetAllPoints()
		mark.shade:SetColorTexture(0, 0, 0, 0.35)
		mark.cross = mark:CreateTexture(nil, "OVERLAY", nil, 1)
		mark.cross:SetTexture(CROSS)
		mark.cross:SetSize(16, 16)
		mark.cross:SetPoint("TOPRIGHT", 2, 2)
		marks[button] = mark
	end
	return mark
end

local function UpdateButton(button)
	local on = ns:IsModuleEnabled(module.key) and ns:GetOption("unlearnedAbilitiesMark")
		and unlearned.UnknownSpell(button.action) ~= nil
	if on then
		Mark(button):Show()
	elseif marks[button] then
		marks[button]:Hide()
	end
end

local function UpdateMarks()
	for _, bar in ipairs(BARS) do
		for index = 1, 12 do
			local button = _G[bar .. index]
			if button then
				if not hooked[button] and button.Update then
					hooked[button] = true
					hooksecurefunc(button, "Update", UpdateButton) -- a new action, or the bar's page changed
				end
				UpdateButton(button)
			end
		end
	end
end

local function OnActionTooltip(tooltip, slot)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("unlearnedAbilitiesMark") then
		return
	end
	if tooltip.IsForbidden and tooltip:IsForbidden() then
		return
	end
	if unlearned.UnknownSpell(slot) then
		tooltip:AddLine("NraKit: Not learned. You don't know this anymore (a respec, say). Drag it off the bar.", 1, 0.3, 0.3, true)
		tooltip:Show()
	end
end

------------------------------------------------------------------------------
-- Taking them off
------------------------------------------------------------------------------

-- Takes every unknown spell off your bars (out of combat; in combat it waits). Returns how many.
function unlearned.RemoveAll()
	if InCombatLockdown() then
		if not removeQueued then
			removeQueued = true
			ns:Print("Taking the unlearned abilities off your bars after combat.")
		end
		return 0
	end
	removeQueued = false
	if GetCursorInfo() then
		ClearCursor()
	end
	local count = 0
	for slot in pairs(unlearned.Slots()) do
		PickupAction(slot)
		ClearCursor()
		count = count + 1
	end
	if count > 0 then
		ns:Print(string.format("Took %d unlearned %s off your bars.", count, count == 1 and "ability" or "abilities"))
	end
	UpdateMarks()
	return count
end

-- Asks before taking them off: your bars are yours. "Take them off" does it.
function unlearned.ConfirmRemove()
	local spells = {}
	for _, spellID in pairs(unlearned.Slots()) do
		table.insert(spells, spellID)
	end
	if #spells == 0 then
		ns:Print("Nothing to take off: you know everything on your bars.")
		return
	end
	table.sort(spells)
	StaticPopupDialogs.NRAKIT_REMOVE_UNLEARNED = StaticPopupDialogs.NRAKIT_REMOVE_UNLEARNED or {
		text = "Take these abilities you don't know anymore off your action bars?\n\n%s",
		button1 = "Take them off",
		button2 = CANCEL or "Cancel",
		OnAccept = function()
			unlearned.RemoveAll()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show("NRAKIT_REMOVE_UNLEARNED", NameList(spells))
end

------------------------------------------------------------------------------
-- When your spells change
------------------------------------------------------------------------------

-- The spellbook's spells you know (base spells, not passives or other specs').
local function SpellbookSpells()
	local spells = {}
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.isGuild and not info.offSpecID then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.itemType == spellType and not item.isPassive and not item.isOffSpec then
					spells[item.actionID] = true
				end
			end
		end
	end
	return spells
end

local function OnBars(spellID)
	local slots = C_ActionBar.FindSpellActionButtons and C_ActionBar.FindSpellActionButtons(spellID)
	return type(slots) == "table" and #slots > 0
end

local function ShowLost(lost)
	ns.toast.Show({
		style = "big",
		heading = "Not learned anymore",
		text = string.format("%d on your bars: %s", #lost, NameList(lost)),
		detail = "Click to take them off your bars (you'll be asked first)",
		icon = CROSS,
		duration = TOAST_SECONDS,
		onClick = unlearned.ConfirmRemove,
	})
end

local function ShowNew(new)
	ns.toast.Show({
		style = "small",
		heading = "New, not on your bars",
		text = NameList(new),
		detail = "Find them in your spellbook",
		duration = TOAST_SECONDS,
	})
end

-- The talents window is where you respec: the messages wait until it's closed, so they never
-- sit on top of it (and take a click meant for it).
local waiting -- { lost = {}, new = {} } while the talents window is open
local function TalentsOpen()
	return PlayerSpellsFrame ~= nil and type(PlayerSpellsFrame) == "table" and PlayerSpellsFrame:IsShown()
end

local function ShowWaiting()
	if not waiting or TalentsOpen() then
		return
	end
	local lost, new = {}, waiting.new
	for _, spellID in ipairs(waiting.lost) do
		if OnBars(spellID) then -- you may have taken it off yourself meanwhile
			table.insert(lost, spellID)
		end
	end
	waiting = nil
	if #lost > 0 then
		ShowLost(lost)
	end
	if #new > 0 then
		ShowNew(new)
	end
end

local hookedTalents = false
local function HookTalentsWindow()
	if hookedTalents or not (PlayerSpellsFrame and type(PlayerSpellsFrame) == "table") then
		return
	end
	hookedTalents = true
	PlayerSpellsFrame:HookScript("OnHide", function()
		C_Timer.After(0.3, ShowWaiting)
	end)
end

-- Compares your spells with the last look: abilities lost that are still on your bars, and
-- new ones that aren't on any bar.
function unlearned.CheckChanges()
	local now = SpellbookSpells()
	if not next(now) then
		return -- the spellbook isn't loaded (logging in, zoning): not a change
	end
	local before = known
	known = now
	if not before or not ns:IsModuleEnabled(module.key) or not ns:GetOption("unlearnedAbilitiesNotify") then
		return
	end
	local lost, new = {}, {}
	for spellID in pairs(before) do
		if not now[spellID] and OnBars(spellID) then
			table.insert(lost, spellID)
		end
	end
	for spellID in pairs(now) do
		if not before[spellID] and not OnBars(spellID) then
			table.insert(new, spellID)
		end
	end
	table.sort(lost)
	table.sort(new)
	if #new > MAX_NEW then
		new = {} -- (many at once is the spellbook finishing loading, not learning)
	end
	if #lost > 0 then
		ns:Print(string.format("Not learned anymore, still on your bars: %s. Click the message, or |cffffd100/nra unlearned remove|r, to take them off.",
			NameList(lost)))
	end
	if #lost + #new == 0 then
		return
	end
	HookTalentsWindow()
	waiting = waiting or { lost = {}, new = {} }
	for _, spellID in ipairs(lost) do
		table.insert(waiting.lost, spellID)
	end
	for _, spellID in ipairs(new) do
		table.insert(waiting.new, spellID)
	end
	ShowWaiting()
end

ns:RegisterPreview("unlearned", "Unlearned abilities: the message after a respec", function()
	ns.toast.Show({
		style = "big",
		heading = "Not learned anymore",
		text = "3 on your bars: Concussion Blow, Improved Revenge, Last Stand",
		detail = "Click to take them off your bars (not in this preview)",
		icon = CROSS,
		duration = TOAST_SECONDS,
	})
	ns.toast.Show({
		style = "small",
		heading = "New, not on your bars",
		text = "Bloodthirst, Rampage",
		detail = "Find them in your spellbook",
		duration = TOAST_SECONDS,
	})
end)

------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------

local function OnSlashCommand(input)
	if not ns:IsModuleEnabled(module.key) then
		ns:Print("Unlearned abilities is turned off. Turn it on in /nra.")
		return
	end
	if strtrim(input or ""):lower() == "remove" then
		if unlearned.RemoveAll() == 0 and not removeQueued then
			ns:Print("Nothing to take off: you know everything on your bars.")
		end
		return
	end
	local spells = {}
	for _, spellID in pairs(unlearned.Slots()) do
		table.insert(spells, spellID)
	end
	if #spells == 0 then
		ns:Print("You know every ability on your bars.")
	else
		table.sort(spells)
		ns:Print(string.format("On your bars but not learned: %s. |cffffd100/nra unlearned remove|r takes them off.", NameList(spells)))
	end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local checkQueued = false
local function QueueCheck()
	if not checkQueued then
		checkQueued = true
		C_Timer.After(0.5, function()
			checkQueued = false
			unlearned.CheckChanges()
			UpdateMarks()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if removeQueued then
			unlearned.RemoveAll()
		end
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		QueueCheck()
	else
		UpdateMarks()
	end
end)

local EVENTS = { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR",
	"ACTIONBAR_PAGE_CHANGED", "PLAYER_REGEN_ENABLED" }

function module:OnInitialize()
	ns:RegisterSlashCommand("unlearned", OnSlashCommand, {
		summary = "Unlearned abilities: list the abilities on your bars you don't know anymore",
		usage = {
			"/nra unlearned - list the abilities on your bars you don't know anymore",
			"/nra unlearned remove - take them off your bars (after combat, if you're fighting)",
		},
	})
	hooksecurefunc(GameTooltip, "SetAction", OnActionTooltip)
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			pcall(eventFrame.RegisterEvent, eventFrame, event) -- skip events this client doesn't have
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		known = nil -- start from what you know now
		QueueCheck()
	else
		UpdateMarks()
	end
end

function module:OnOptionChanged()
	UpdateMarks()
end

ns:RegisterModule(module)
