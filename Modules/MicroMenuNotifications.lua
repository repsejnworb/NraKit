local _, ns = ...

-- Micro menu notifications: hides the blue notification dot on micro menu buttons
-- that keep nagging. The dot is the button's NotificationOverlay frame; Blizzard
-- shows and hides it, and we only set its alpha, so we never fight Blizzard's logic
-- and putting it back is just alpha 1.

local module = {
	key = "microMenuNotifications",
	section = "Interface",
	name = "Hide micro menu notifications",
	description = "Hides the blue notification dot on micro menu buttons that keep showing it.",
	default = false,
	options = {
		{
			key = "microMenuHideShop",
			name = "Shop",
			description = "Hide the Shop button's \"new products\" dot.",
			default = true,
		},
	},
}

local function SetHidden(button, hidden)
	local overlay = button and button.NotificationOverlay
	if overlay then
		overlay:SetAlpha(hidden and 0 or 1)
	end
end

local function Update()
	local enabled = ns:IsModuleEnabled(module.key)
	SetHidden(StoreMicroButton, enabled and ns:GetOption("microMenuHideShop"))
end

function module:OnInitialize()
	Update()
end

function module:OnEnabledChanged()
	Update()
end

function module:OnOptionChanged()
	Update()
end

ns:RegisterModule(module)
