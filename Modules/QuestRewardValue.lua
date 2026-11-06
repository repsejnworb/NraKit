local _, ns = ...

-- Marks the quest reward choice that sells to a vendor for the most gold with a
-- small gold coin in the corner of its icon. Works in the quest dialog, the
-- quest log popup and the map's quest details, which all render rewards through
-- QuestInfo_Display.

local module = {
	key = "questRewardValue",
	section = "Quests",
	name = "Mark most valuable quest reward",
	description = "When a quest lets you choose a reward, show a gold coin on the choice that sells to a vendor for the most gold (vendor price times stack size).",
	default = true,
}

local COIN_TEXTURE = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SIZE = 14

-- reward button -> coin texture
local coins = {}

local function GetCoin(button)
	local coin = coins[button]
	if not coin then
		coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
		coin:SetTexture(COIN_TEXTURE)
		coin:SetSize(COIN_SIZE, COIN_SIZE)
		coin:SetPoint("TOPRIGHT", button.Icon or button, "TOPRIGHT", 2, 2)
		coins[button] = coin
	end
	return coin
end

local function HideAllCoins()
	for _, coin in pairs(coins) do
		coin:Hide()
	end
end

-- Returns the item link and stack size of a choice reward button.
local function GetChoiceItem(button, questLog)
	local index = button:GetID()
	if questLog then
		local _, _, count = GetQuestLogChoiceInfo(index)
		return GetQuestLogItemLink("choice", index), count
	end
	local _, _, count = GetQuestItemInfo("choice", index)
	return GetQuestItemLink("choice", index), count
end

local UpdateRewards

local function UpdateWhenLoaded(link, rewardsFrame, questLog)
	local item = Item:CreateFromItemLink(link)
	if item:IsItemEmpty() then
		return
	end
	item:ContinueOnItemLoad(function()
		-- Only redraw if the same view is still showing.
		if rewardsFrame:IsShown() and QuestInfoFrame.rewardsFrame == rewardsFrame
			and QuestInfoFrame.questLog == questLog then
			UpdateRewards(rewardsFrame)
		end
	end)
end

UpdateRewards = function(rewardsFrame)
	if not rewardsFrame or not rewardsFrame.RewardButtons then
		return
	end
	for _, button in ipairs(rewardsFrame.RewardButtons) do
		if coins[button] then
			coins[button]:Hide()
		end
	end
	if not ns:IsModuleEnabled(module.key) then
		return
	end

	local questLog = QuestInfoFrame.questLog
	local values = {}
	local best = 0
	local choices = 0
	local pending = false
	for _, button in ipairs(rewardsFrame.RewardButtons) do
		if button:IsShown() and button.type == "choice" and button.objectType == "item" then
			choices = choices + 1
			local link, count = GetChoiceItem(button, questLog)
			if link then
				local sellPrice = select(11, C_Item.GetItemInfo(link))
				if sellPrice == nil then
					-- Not cached yet; redraw once the client has the item.
					UpdateWhenLoaded(link, rewardsFrame, questLog)
					pending = true
				else
					local value = sellPrice * math.max(count or 1, 1)
					values[button] = value
					best = math.max(best, value)
				end
			end
		end
	end

	-- Nothing to compare, nothing sells for anything, or we can't compare everything yet.
	if choices < 2 or best <= 0 or pending then
		return
	end
	for button, value in pairs(values) do
		if value == best then
			GetCoin(button):Show()
		end
	end
end

function module:OnInitialize()
	hooksecurefunc("QuestInfo_Display", function()
		UpdateRewards(QuestInfoFrame.rewardsFrame)
	end)
end

function module:OnEnabledChanged(enabled)
	if enabled then
		UpdateRewards(QuestInfoFrame.rewardsFrame)
	else
		HideAllCoins()
	end
end

ns:RegisterModule(module)
