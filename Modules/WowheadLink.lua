local _, ns = ...

-- Wowhead link: hover an item, spell, NPC, quest, achievement or currency and press
-- Ctrl+C (a key binding) for a wowhead.com/forever link to it.
--
-- Addons can't write to the system clipboard, so the key opens a box in the middle of
-- the screen with the URL selected, for the OS's own copy (Ctrl+C, or Cmd+C on a Mac).
-- That key press also closes the box.
--
-- What's hovered comes from the tooltip data of GameTooltip/ItemRefTooltip (type + ID,
-- or a GUID for units). Quest log entries, the achievement frame and the objective
-- tracker show plain text tooltips, so for those we read the ID off the hovered frame.

local module = {
	key = "wowheadLink",
	section = "Interface",
	name = "Copy Wowhead link",
	description = "Hover an item, spell, NPC, quest, achievement or currency and press Ctrl+C to copy a Wowhead (Forever) link to it. Change the key under Key Bindings > AddOns.",
	default = false,
}

local BINDING = "NRAKIT_WOWHEAD_LINK"
local DEFAULT_KEY = "CTRL-C"
local URL = "https://www.wowhead.com/forever/%s=%d"
local IS_MAC = IsMacClient and IsMacClient()
local COPY_KEY = IS_MAC and "Cmd+C" or "Ctrl+C"

_G["BINDING_NAME_" .. BINDING] = "Copy Wowhead link of what's under the mouse"

local TYPE = Enum.TooltipDataType
local PAGES = {
	[TYPE.Item] = "item",
	[TYPE.Toy] = "item",
	[TYPE.Spell] = "spell",
	[TYPE.UnitAura] = "spell",
	[TYPE.Quest] = "quest",
	[TYPE.Achievement] = "achievement",
	[TYPE.Currency] = "currency",
}
local LABELS = { item = "Item", spell = "Spell", npc = "NPC", quest = "Quest", achievement = "Achievement", currency = "Currency" }

local shown = {} -- tooltip -> { page, id } for what it shows now

local function Plain(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- "Creature-0-1-2-3-<npcID>-<spawn>" (also Vehicle-); players and pets have no page.
local function NpcIDFromGUID(guid)
	if not guid then
		return nil
	end
	local kind, _, _, _, _, npcID = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(npcID)
	end
end

local function OnTooltipData(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	local page, id
	if data.type == TYPE.Unit then
		page, id = "npc", NpcIDFromGUID(Plain(data.guid))
	elseif data.type == TYPE.Mount then
		local mountID = Plain(data.id)
		page, id = "spell", mountID and select(2, C_MountJournal.GetMountInfoByID(mountID))
	else
		page, id = PAGES[data.type], Plain(data.id)
	end
	local line = data.lines and data.lines[1]
	local name = line and Plain(line.leftText)
	shown[tooltip] = page and type(id) == "number" and id > 0 and { page = page, id = id, name = name } or nil
end

local function ClearTooltip(tooltip)
	shown[tooltip] = nil
end

-- Frames that carry an ID without a data tooltip: quest log entries (questID),
-- achievement frame rows (AchievementTemplateMixin, id) and objective tracker blocks.
local function FromFrame(frame)
	for _ = 1, 4 do
		if not frame then
			return nil
		end
		if type(frame.questID) == "number" and frame.questID > 0 then
			return "quest", frame.questID
		end
		local tracker = frame.parentModule
		if tracker and type(frame.id) == "number" and frame.id > 0 then
			if tracker == AchievementObjectiveTracker then
				return "achievement", frame.id
			elseif tracker == QuestObjectiveTracker or tracker == CampaignQuestObjectiveTracker then
				return "quest", frame.id
			end
		end
		if AchievementTemplateMixin and frame.Init == AchievementTemplateMixin.Init and type(frame.id) == "number" then
			return "achievement", frame.id
		end
		frame = frame:GetParent()
	end
end

local function GetHovered()
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		local entry = shown[tooltip]
		-- A chat link's tooltip stays open, so it only counts while the mouse is on it.
		if entry and tooltip:IsShown() and (tooltip == GameTooltip or tooltip:IsMouseOver()) then
			return entry.page, entry.id, entry.name
		end
	end
	local focus = GetMouseFoci and GetMouseFoci()[1]
	if focus and not focus:IsForbidden() then
		return FromFrame(focus)
	end
end

local box

local function CreateBox()
	box = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
	box:SetSize(440, 66)
	box:SetFrameStrata("DIALOG")
	box:SetClampedToScreen(true)
	box:EnableMouse(true)
	box:Hide()

	box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	box.title:SetPoint("TOPLEFT", 12, -10)
	box.title:SetPoint("RIGHT", box, "TOPRIGHT", -170, 0)
	box.title:SetJustifyH("LEFT")
	box.title:SetWordWrap(false)

	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.hint:SetPoint("TOPRIGHT", -12, -13)
	box.hint:SetText(COPY_KEY .. " to copy, Esc to close")

	local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
	edit:SetPoint("BOTTOMLEFT", 17, 10)
	edit:SetPoint("BOTTOMRIGHT", -12, 10)
	edit:SetHeight(20)
	edit:SetAutoFocus(false)
	edit:SetScript("OnEscapePressed", function()
		box:Hide()
	end)
	edit:SetScript("OnEnterPressed", function()
		box:Hide()
	end)
	edit:SetScript("OnEditFocusLost", function()
		box:Hide()
	end)
	-- Read-only: put the URL back if anything is typed.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(box.url)
			self:HighlightText()
		end
	end)
	-- The OS copies (or cuts; OnTextChanged puts the text back) on this key press, so
	-- we can't see the clipboard but know it happened. Close right after it.
	edit:SetScript("OnKeyDown", function(_, key)
		local modifier = IS_MAC and IsMetaKeyDown() or not IS_MAC and IsControlKeyDown()
		if (key == "C" or key == "X") and modifier then
			C_Timer.After(0, function()
				box:Hide()
				ns:Print("Copied " .. box.url)
			end)
		end
	end)
	box.edit = edit
end

local function ShowBox(page, id, tooltipName)
	if not box then
		CreateBox()
	end
	box.url = string.format(URL, page, id)
	local title = LABELS[page]
	if page == "item" then
		title = title .. ": " .. (C_Item.GetItemNameByID(id) or id)
	elseif page == "spell" then
		title = title .. ": " .. (C_Spell.GetSpellName(id) or id)
	elseif page == "quest" then
		title = title .. ": " .. (C_QuestLog.GetTitleForQuestID(id) or id)
	elseif page == "achievement" then
		title = title .. ": " .. (select(2, GetAchievementInfo(id)) or id)
	else
		title = title .. ": " .. (tooltipName or id)
	end
	box.title:SetText(title)

	box:ClearAllPoints()
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
	box:Show()
	box.edit:SetText(box.url)
	box.edit:SetFocus()
	box.edit:SetCursorPosition(0)
	box.edit:HighlightText()
end

-- Called by the key binding (Bindings.xml).
function NraKit_CopyWowheadLink()
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	local page, id, name = GetHovered()
	if page and id then
		ShowBox(page, id, name)
	end
end

-- Give the binding Ctrl+C once, if that key is free. If the player later unbinds or
-- moves it, we leave it alone.
local function BindDefaultKey()
	if NraKitDB.wowheadLinkKeySet or InCombatLockdown() then
		return
	end
	NraKitDB.wowheadLinkKeySet = true
	if GetBindingKey(BINDING) or (GetBindingAction(DEFAULT_KEY) or "") ~= "" then
		return
	end
	SetBinding(DEFAULT_KEY, BINDING)
	SaveBindings(GetCurrentBindingSet())
end

function module:OnInitialize()
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, OnTooltipData)
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		tooltip:HookScript("OnTooltipCleared", ClearTooltip)
		tooltip:HookScript("OnHide", ClearTooltip)
	end
	if ns:IsModuleEnabled(self.key) then
		BindDefaultKey()
	end
end

function module:OnEnabledChanged(enabled)
	if enabled then
		BindDefaultKey()
	elseif box then
		box:Hide()
	end
end

ns:RegisterModule(module)
