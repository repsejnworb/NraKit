local _, ns = ...

-- Open All menu: a small arrow next to the inbox's Open All button with more ways to open:
--   Collect auction gold         sold auctions and outbid refunds (their gold)
--   Collect auction purchases    items you won
--   Collect expired auctions     unsold and cancelled items coming back
--   Take money only              the gold from every mail, items left attached
-- Each entry says how many mails and how much gold it would take; C.O.D. and GM mails are
-- never touched (as Open All).
--
-- The item entries run Blizzard's own Open All with a filter: its ShouldSkipCurrentMail is
-- wrapped (as Open selected mail does), so its pacing and server handling stay Blizzard's.
-- The gold entries can't (Open All stops when your bags are full, and takes items too), so
-- they run a small paced loop of their own: take the first matching mail's money, wait for
-- the server, look again (mails vanish once emptied, so indexes shift).
--
-- Auction mails are told apart by their invoice (GetInboxInvoiceInfo: "seller", "buyer")
-- and, for expired, cancelled and outbid mails (which have none), by Blizzard's subject lines.

local feature = { key = "mailOpenMenu" } -- an option of the Mail feature (Mail.lua)

local STEP_DELAY = 0.3 -- seconds between taking money from one mail and the next

local menu = {}
ns.mail.openMenu = menu

local arrow
local activeFilter -- the entry Blizzard's Open All is running with
local collecting -- the gold entry our loop is running: { entry, steps, gold, mails }
local sinceStep = 0
local stepFrame = CreateFrame("Frame")
stepFrame:Hide()

-- "Auction expired: %s" -> a pattern matching any such subject.
local function SubjectPattern(format, fallback)
	format = type(format) == "string" and format or fallback
	local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. escaped:gsub("%%s", ".+") .. "$"
end
local EXPIRED = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")
local CANCELLED = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s")
local OUTBID = SubjectPattern(AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s")

-- What a mail is: { money, items, invoice, subject }, or nil for mail Open All never touches.
local function Mail(index)
	local _, _, _, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
	if isGM or (cod and cod > 0) then
		return nil
	end
	return { money = money or 0, items = itemCount or 0, invoice = GetInboxInvoiceInfo(index), subject = subject or "" }
end

menu.ENTRIES = {
	{
		label = "Collect auction gold",
		tooltip = "Take the gold from auctions you sold and from bids you were outbid on.",
		gold = true,
		Match = function(mail)
			return mail.money > 0 and (mail.invoice == "seller" or mail.subject:find(OUTBID) ~= nil)
		end,
	},
	{
		label = "Collect auction purchases",
		tooltip = "Take the items you won at the auction house. Other mail is left alone.",
		Match = function(mail)
			return mail.items > 0 and mail.invoice == "buyer"
		end,
	},
	{
		label = "Collect expired auctions",
		tooltip = "Take back the items from auctions that didn't sell or that you cancelled.",
		Match = function(mail)
			return mail.items > 0 and (mail.subject:find(EXPIRED) ~= nil or mail.subject:find(CANCELLED) ~= nil)
		end,
	},
	{
		label = "Take money only",
		tooltip = "Take the gold from every mail and leave the items in them.",
		gold = true,
		Match = function(mail)
			return mail.money > 0
		end,
	},
}

-- How many mails an entry would take from, and how much gold.
function menu.Summary(entry)
	local mails, gold = 0, 0
	for index = 1, GetInboxNumItems() do
		local mail = Mail(index)
		if mail and entry.Match(mail) then
			mails = mails + 1
			gold = gold + mail.money
		end
	end
	return mails, gold
end

local function Money(copper)
	return GetCoinTextureString and GetCoinTextureString(copper) or (ns.mailSubject and ns.mailSubject.MoneyText(copper)) or tostring(copper)
end

------------------------------------------------------------------------------
-- Running an entry
------------------------------------------------------------------------------

local function StopCollecting()
	if collecting then
		if collecting.mails > 0 then
			ns:Print(string.format("Collected %s from %d %s.", Money(collecting.gold), collecting.mails,
				collecting.mails == 1 and "mail" or "mails"))
		end
		collecting = nil
	end
	stepFrame:Hide()
end

-- Takes the money from the first mail that matches; stops when there's none left.
local function CollectStep()
	collecting.steps = collecting.steps - 1
	if collecting.steps < 0 then
		StopCollecting() -- something keeps failing: don't loop forever
		return
	end
	for index = 1, GetInboxNumItems() do
		local mail = Mail(index)
		if mail and collecting.entry.Match(mail) then
			collecting.gold = collecting.gold + mail.money
			collecting.mails = collecting.mails + 1
			TakeInboxMoney(index)
			sinceStep = 0
			return
		end
	end
	StopCollecting()
end

stepFrame:SetScript("OnUpdate", function(_, elapsed)
	sinceStep = sinceStep + elapsed
	if sinceStep >= STEP_DELAY and not (C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending()) then
		CollectStep()
	end
end)

function menu.Run(entry)
	if collecting or not OpenAllMail:IsEnabled() then
		return -- already opening
	end
	if entry.gold then
		local mails = menu.Summary(entry)
		collecting = { entry = entry, steps = mails * 2 + 5, gold = 0, mails = 0 }
		stepFrame:Show()
		CollectStep()
	else
		activeFilter = entry
		OpenAllMail:Click()
	end
end

------------------------------------------------------------------------------
-- The arrow and its menu
------------------------------------------------------------------------------

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Open All")
		local busy = collecting ~= nil or not OpenAllMail:IsEnabled()
		for _, entry in ipairs(menu.ENTRIES) do
			local mails, gold = menu.Summary(entry)
			local label = entry.label
			if mails > 0 then
				label = string.format("%s  |cff999999(%d %s%s)|r", label, mails, mails == 1 and "mail" or "mails",
					gold > 0 and (", " .. Money(gold)) or "")
			end
			local button = root:CreateButton(label, function()
				menu.Run(entry)
			end)
			if button.SetEnabled then
				button:SetEnabled(mails > 0 and not busy)
			end
			if button.SetTooltip then
				button:SetTooltip(function(tooltip)
					GameTooltip_SetTitle(tooltip, entry.label)
					GameTooltip_AddNormalLine(tooltip, entry.tooltip)
				end)
			end
		end
	end)
end

local function CreateArrow()
	arrow = CreateFrame("Button", nil, OpenAllMail:GetParent())
	arrow:SetSize(24, 24)
	arrow:SetPoint("LEFT", OpenAllMail, "RIGHT", 2, 0)
	arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	arrow:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
	arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	arrow:SetScript("OnClick", OpenMenu)
	arrow:SetScript("OnEnter", function(self)
		ns.UI.ShowTooltip(self, "More ways to open", "Collect auction gold, purchases or expired auctions, or take only the money.")
	end)
	arrow:SetScript("OnLeave", GameTooltip_Hide)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", StopCollecting) -- MAIL_CLOSED

function feature.OnInitialize()
	if not (OpenAllMail and OpenAllMail.ShouldSkipCurrentMail and OpenAllMail.StopOpening) then
		return
	end
	CreateArrow()
	-- Blizzard's Open All, running one of the item entries: only its mails.
	local original = OpenAllMail.ShouldSkipCurrentMail
	OpenAllMail.ShouldSkipCurrentMail = function(self, ...)
		if activeFilter then
			local mail = Mail(self.mailIndex)
			if not (mail and activeFilter.Match(mail)) then
				return true
			end
		end
		return original(self, ...)
	end
	hooksecurefunc(OpenAllMail, "StopOpening", function()
		activeFilter = nil
	end)
	eventFrame:RegisterEvent("MAIL_CLOSED")
	feature.OnEnabledChanged(ns.mail.IsOn(feature.key))
end

function feature.OnEnabledChanged(on)
	if arrow then
		arrow:SetShown(on)
	end
	if not on then
		activeFilter = nil
		StopCollecting()
	end
end

ns.mail.Register(feature)
