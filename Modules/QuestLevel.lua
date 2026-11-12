local _, ns = ...

-- Shows the quest's level in front of its title, e.g. "[24] The Defias Brotherhood".
-- Covers the quest dialog (offer, progress and turn-in pages), the quest log popup and
-- the map's quest details. Most of these render through QuestInfo_Display; the
-- progress page ("Do you have the items?") sets its own title on show.

local module = {
	key = "questLevel",
	section = "Quests",
	name = "Show quest level",
	description = "Show the quest's level in front of its title in the quest dialog and quest details, e.g. \"[24] The Defias Brotherhood\".",
	default = false,
	options = {
		{
			key = "questLevelColor",
			name = "Color by difficulty",
			description = "Color the level like the quest log does: red is far above you, orange and yellow are a challenge, green is easy and grey gives little experience.",
			default = true,
		},
	},
}

-- fontString -> title text Blizzard set, so we can restore it when turned off
local originals = {}
-- fontString -> text we set (original plus level prefix)
local decorated = {}

local function GetLevelPrefix(questID)
	if not questID or questID == 0 then
		return nil
	end
	local level = C_QuestLog.GetQuestDifficultyLevel(questID)
	if not level or level <= 0 then
		return nil
	end
	local text = "[" .. level .. "]"
	if ns:GetOption("questLevelColor") then
		local color = GetQuestDifficultyColor(level)
		if color then
			text = CreateColor(color.r, color.g, color.b):WrapTextInColorCode(text)
		end
	end
	return text .. " "
end

local function Decorate(fontString, questID)
	local text = fontString:GetText()
	-- Some views (map rewards) don't reset the title, so it may still carry our prefix.
	if not text or text == "" or text == decorated[fontString] then
		return
	end
	originals[fontString] = text
	decorated[fontString] = nil
	local prefix = ns:IsModuleEnabled(module.key) and GetLevelPrefix(questID)
	if prefix then
		decorated[fontString] = prefix .. text
		fontString:SetText(decorated[fontString])
	end
end

local function OnQuestInfoDisplay()
	if not QuestInfoTitleHeader:IsShown() then
		return
	end
	local questID
	if QuestInfoFrame.questLog then
		questID = C_QuestLog.GetSelectedQuest()
	else
		questID = GetQuestID()
	end
	Decorate(QuestInfoTitleHeader, questID)
end

local function OnProgressShow()
	Decorate(QuestProgressTitleText, GetQuestID())
end

function module:OnInitialize()
	-- QuestInfo_ShowTitle is captured by reference in QUEST_TEMPLATE_*.elements, so hook the caller.
	hooksecurefunc("QuestInfo_Display", OnQuestInfoDisplay)
	QuestFrameProgressPanel:HookScript("OnShow", OnProgressShow)
end

local function Restore()
	for fontString, text in pairs(originals) do
		if fontString:GetText() == decorated[fontString] then
			fontString:SetText(text)
		end
		decorated[fontString] = nil
	end
end

local function Redraw()
	Restore()
	if QuestInfoTitleHeader:IsVisible() then
		OnQuestInfoDisplay()
	end
	if QuestProgressTitleText:IsVisible() then
		OnProgressShow()
	end
end

function module:OnEnabledChanged()
	Redraw()
end

function module:OnOptionChanged()
	Redraw()
end

ns:RegisterModule(module)
