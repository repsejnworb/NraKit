local _, ns = ...

-- What's new: which changelog entries (Changelog.lua) you haven't seen, and the chat line
-- after an update. The page itself is in the NraKit window (Options.lua), opened with
-- /nra new.
--
-- Entries are only ever added, so counting them is enough: NraKitDB.changelogSeen is how
-- many there were when you last opened the page, NraKitDB.changelogAnnounced how many
-- when the chat line last went out (once per update). A fresh install starts with
-- everything seen: a changelog is for people updating.

local whatsNew = {}
ns.whatsNew = whatsNew

local ANNOUNCE_DELAY = 8 -- seconds after login, so it isn't lost in the login chat

local entries

-- Every entry, newest first, with its version: { kind, text, title, points, tip, module,
-- version, date } (see Changelog.lua for what each is).
function whatsNew.Entries()
	if not entries then
		entries = {}
		for _, release in ipairs(ns.changelog) do
			for _, entry in ipairs(release.entries) do
				table.insert(entries, {
					kind = entry[1], text = entry[2], module = entry.module,
					title = entry.title, points = entry.points, tip = entry.tip,
					version = release.version, date = release.date,
				})
			end
		end
	end
	return entries
end

-- Changelog text for the game: **words** brighter (lines can't switch font, but can switch
-- colour), /commands gold ("/nra shop" as a whole). Colours don't nest in WoW, so commands
-- inside **...** stay bright with the rest of it.
local BRIGHT, COMMAND = "|cffffffff", "|cffffd100"

local function Commands(text)
	text = (" " .. text):gsub("([%s%(])/nra (%a+)", function(before, name)
		if ns:IsSlashCommand(name) then
			return before .. COMMAND .. "/nra " .. name .. "|r"
		end
	end)
	text = text:gsub("([%s%(])(/%a[%w]*)", "%1" .. COMMAND .. "%2|r")
	return (text:sub(2))
end

function whatsNew.Markup(text)
	local parts, rest = {}, text or ""
	while true do
		local first, last, inner = rest:find("%*%*(.-)%*%*")
		if not first then
			break
		end
		table.insert(parts, Commands(rest:sub(1, first - 1)))
		table.insert(parts, BRIGHT .. inner .. "|r")
		rest = rest:sub(last + 1)
	end
	table.insert(parts, Commands(rest))
	return table.concat(parts)
end

function whatsNew.UnseenCount()
	local total = #whatsNew.Entries()
	return math.max(0, total - (NraKitDB.changelogSeen or total))
end

function whatsNew.MarkSeen()
	NraKitDB.changelogSeen = #whatsNew.Entries()
	ns:BadgeChanged()
end

function whatsNew.ChatEnabled()
	return NraKitDB.whatsNewChat ~= false
end

local KIND_WORDS = {
	new = { "new feature", "new features" },
	improved = { "improvement", "improvements" },
	fixed = { "fix", "fixes" },
}

-- "NraKit has been updated to 0.12.0: 2 new features, 1 fix. ..." once per update.
function whatsNew.Announce()
	local total = #whatsNew.Entries()
	local unseen = whatsNew.UnseenCount()
	if not whatsNew.ChatEnabled() or unseen == 0 or (NraKitDB.changelogAnnounced or 0) >= total then
		return
	end
	NraKitDB.changelogAnnounced = total

	local counts = {}
	for index = 1, unseen do
		local kind = whatsNew.Entries()[index].kind
		counts[kind] = (counts[kind] or 0) + 1
	end
	local parts = {}
	for _, kind in ipairs({ "new", "improved", "fixed" }) do
		if counts[kind] then
			table.insert(parts, counts[kind] .. " " .. KIND_WORDS[kind][counts[kind] == 1 and 1 or 2])
		end
	end
	local version = whatsNew.Entries()[1].version
	ns:Print(string.format("has been updated%s: %s. Type |cffffd100/nra new|r to see what's new.",
		version ~= "Unreleased" and (" to " .. version) or "", table.concat(parts, ", ")))
end

local HELP = {
	summary = "What's new in NraKit (the changelog)",
	usage = { "/nra new - what's new in each version; turn new features on right there (also /nra changelog)" },
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
	if NraKitDB.changelogSeen == nil then
		whatsNew.MarkSeen()
		NraKitDB.changelogAnnounced = #whatsNew.Entries()
	end
	C_Timer.After(ANNOUNCE_DELAY, whatsNew.Announce)
end)

local function Open()
	ns:OpenWhatsNew()
end

ns:RegisterBadge({
	key = "whatsNew",
	option = "nraButtonBadgeWhatsNew",
	count = whatsNew.UnseenCount,
	text = function(count)
		return string.format("%d %s in NraKit (/nra new)", count, count == 1 and "change" or "changes")
	end,
	open = Open,
})
ns:RegisterSlashCommand("new", Open, HELP)
ns:RegisterSlashCommand("whatsnew", Open, HELP)
ns:RegisterSlashCommand("changelog", Open, HELP)
