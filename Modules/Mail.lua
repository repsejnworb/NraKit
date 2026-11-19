local _, ns = ...

-- Mail: one feature for the mailbox helpers, each an option of it (on by default):
--   openSelectedMail   checkboxes on inbox mails; Open All opens the ticked ones (OpenSelectedMail.lua)
--   mailSubject        the subject written from what you attach (MailSubject.lua)
--   mailRecipient      the To name kept after sending, mailRecipientOnOpen fills it in (MailRecipient.lua)
--   mailAttachAll      Alt+click a bag item to attach every stack of it (MailAttachAll.lua)
-- Each file registers its part with ns.mail.Register({ key = <option key>, OnInitialize,
-- OnEnabledChanged(on) }) and asks ns.mail.IsOn(key): the Mail feature and that option on.
--
-- Three of these were features of their own before 0.19 (same keys, then module switches). Migrate
-- carries that over once: anyone who had one on gets Mail on with just those parts on (and the
-- new Alt+click); anyone who had none gets every part on, for when they turn Mail on.

local OLD_FEATURES = { "openSelectedMail", "mailSubject", "mailRecipient" }

local module = {
	key = "mail",
	section = "Mail",
	name = "Mail",
	description = "Helpers for the mailbox: open only the mails you tick, a subject written from what you attach, the last recipient remembered, and Alt+click to attach every stack of an item.",
	default = false,
	options = {
		{
			key = "openSelectedMail",
			name = "Open selected mail",
			description = "Adds a checkbox to each mail in your inbox. Tick some and the Open All button only opens those.",
			default = true,
		},
		{
			key = "mailSubject",
			name = "Fill in mail subject",
			description = "Writes the subject of a mail you're sending from what you attach: \"Linen Cloth (40)\", \"25g\" or \"Linen Cloth (20) + 5g\". A subject you typed yourself is left alone.",
			default = true,
		},
		{
			key = "mailRecipient",
			name = "Remember mail recipient",
			description = "Keeps the name in the To box after you send a mail, so you can send several to the same player (like your bank alt) without typing it again.",
			default = true,
		},
		{
			key = "mailRecipientOnOpen",
			parent = "mailRecipient",
			name = "Fill it in when opening Send Mail",
			description = "Also fill in the last player you mailed (from this character) when you open the Send Mail tab.",
			default = true,
		},
		{
			key = "mailAttachAll",
			name = "Alt+click to attach all",
			description = "With Send Mail open, Alt+click an item in your bags to attach every stack of it you have (all your Silk Cloth, all 4 Small Red Pouches), as many as fit in the mail.",
			default = true,
		},
	},
}

local features = {}

ns.mail = {}

function ns.mail.Register(feature)
	features[feature.key] = feature
end

function ns.mail.IsOn(key)
	return ns:IsModuleEnabled(module.key) and ns:GetOption(key)
end

-- Before the defaults are filled in (Core.lua).
function module:Migrate(db)
	if db.mail ~= nil then
		return
	end
	local anyOn = false
	for _, key in ipairs(OLD_FEATURES) do
		anyOn = anyOn or db[key] == true
	end
	if anyOn then
		db.mail = true -- the parts that were off stay off
	else
		for _, key in ipairs(OLD_FEATURES) do
			db[key] = nil -- off only because features started off: take the option's default (on)
		end
	end
end

function module:OnInitialize()
	for _, feature in pairs(features) do
		if feature.OnInitialize then
			feature.OnInitialize()
		end
	end
end

function module:OnEnabledChanged()
	for key, feature in pairs(features) do
		if feature.OnEnabledChanged then
			feature.OnEnabledChanged(ns.mail.IsOn(key))
		end
	end
end

function module:OnOptionChanged(key)
	local feature = features[key]
	if feature and feature.OnEnabledChanged then
		feature.OnEnabledChanged(ns.mail.IsOn(key))
	end
end

ns:RegisterModule(module)
