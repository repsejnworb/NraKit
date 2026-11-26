local addonName, ns = ...

-- Newer version check and /nra who, over hidden addon messages (prefix "NraKit").
--
-- At login NraKit says hello to your guild, and to your group when you join one:
-- "HELLO:<version>". A copy with a newer release that hears an older one answers on the
-- same channel ("VER:<version>") after a random second or two, unless someone else
-- already did, so a big guild doesn't all answer at once. Hearing a newer release gives
-- one chat line per session; What's New shows it too.
--
-- /nra who asks the guild and group ("WHO"); everyone answers by whisper ("VER:...")
-- and the list prints a few seconds later, with how many NraKit users you've come
-- across: this session, and ever (NraKitDB.nraKitUsersSeen: name -> last seen; only
-- kept on your computer).
--
-- A development copy (a git clone: the TOC version is still "@project-version@")
-- answers /nra who as "dev" but never compares. Pre-releases only count for people on
-- a pre-release themselves. Versions must look like 1.2.3 (or 1.2.3-beta.1), so a
-- prank "v99" can at most cause one chat line. Addon messages are blocked in some
-- situations (Midnight lockdown, e.g. instanced combat); then nothing is sent.
--
-- The option (NraKitDB.versionCheck, on unless false, switched on the What's New page)
-- also stops sending: nobody sees your version when it's off.

local versionCheck = {}
ns.versionCheck = versionCheck

local PREFIX = "NraKit"
local HELLO_DELAY = 10 -- seconds after login
local GROUP_DELAY = 3
local REPLY_DELAY_MIN, REPLY_DELAY_SPREAD = 1, 3
local WHO_WAIT = 3

local known = {} -- "Bob Stone" -> { version, time } heard this session
local pendingReply = {} -- channel -> true while waiting to answer an older hello
local groupChannel -- the group channel we last said hello on
local notified = false

function versionCheck.Enabled()
	return NraKitDB.versionCheck ~= false
end

------------------------------------------------------------------------------
-- Versions
------------------------------------------------------------------------------

-- "v0.12.0" / "0.13.0-beta.1" -> { 0, 13, 0, pre = "beta.1" }, or nil if it isn't a version.
function versionCheck.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local major, minor, patch, pre = text:match("^v?(%d+)%.(%d+)%.(%d+)%-([%w%.]+)$")
	if not major then
		major, minor, patch = text:match("^v?(%d+)%.(%d+)%.(%d+)$")
	end
	if not major or #major > 3 or #minor > 3 or #patch > 3 then
		return nil
	end
	return { tonumber(major), tonumber(minor), tonumber(patch), pre = pre }
end

-- >0 if a is newer than b. A pre-release comes before its release.
function versionCheck.Compare(a, b)
	for index = 1, 3 do
		if a[index] ~= b[index] then
			return a[index] - b[index]
		end
	end
	if (a.pre ~= nil) ~= (b.pre ~= nil) then
		return a.pre and -1 or 1
	end
	if a.pre and a.pre ~= b.pre then
		return a.pre > b.pre and 1 or -1
	end
	return 0
end

-- Our version from the TOC, or "dev" for a development copy.
function versionCheck.MyVersion()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if versionCheck.Parse(version) then
		return (version:gsub("^v", ""))
	end
	return "dev"
end

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

-- "Bob-Stone" (as addon messages may give it) -> "Bob Stone".
local function DisplayName(sender)
	return (sender:gsub("%-", " "))
end

local function IsMe(sender)
	local name, surname = UnitName("player")
	local me = surname and surname ~= "" and (name .. " " .. surname) or name
	return me ~= nil and DisplayName(sender):lower() == me:lower()
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------

local function Send(message, channel, target)
	if not versionCheck.Enabled() or not channel then
		return false
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return false
	end
	C_ChatInfo.SendAddonMessage(PREFIX, message, channel, target)
	return true
end

local function GroupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

local function Hello(channel)
	Send("HELLO:" .. versionCheck.MyVersion(), channel)
end

------------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------------

-- The newest release heard this session that is newer than ours, or nil.
function versionCheck.Newer()
	return versionCheck.newest
end

local function Heard(sender, version)
	local name = DisplayName(sender)
	known[name] = { version = version, time = GetTime() }
	NraKitDB.nraKitUsersSeen = NraKitDB.nraKitUsersSeen or {}
	NraKitDB.nraKitUsersSeen[name:lower()] = time()
	local theirs, mine = versionCheck.Parse(version), versionCheck.Parse(versionCheck.MyVersion())
	if not theirs or not mine or (theirs.pre and not mine.pre) then
		return
	end
	if versionCheck.Compare(theirs, mine) <= 0 then
		return
	end
	local newest = versionCheck.Parse(versionCheck.newest)
	if not newest or versionCheck.Compare(theirs, newest) > 0 then
		versionCheck.newest = version
	end
	if not notified then
		notified = true
		ns:Print(string.format("|cffffd100NraKit %s is out|r (you have %s). Update through CurseForge or your addon manager.",
			version, versionCheck.MyVersion()))
	end
end

-- Someone said hello with an older release than ours: answer on the same channel, unless
-- another newer copy does first.
local function MaybeReply(version, channel)
	local theirs, mine = versionCheck.Parse(version), versionCheck.Parse(versionCheck.MyVersion())
	if not theirs or not mine or mine.pre or versionCheck.Compare(mine, theirs) <= 0 then
		return
	end
	if pendingReply[channel] then
		return
	end
	pendingReply[channel] = true
	C_Timer.After(REPLY_DELAY_MIN + math.random() * REPLY_DELAY_SPREAD, function()
		if pendingReply[channel] then
			pendingReply[channel] = nil
			Send("VER:" .. versionCheck.MyVersion(), channel)
		end
	end)
end

function versionCheck.OnMessage(text, channel, sender)
	if not versionCheck.Enabled() or type(text) ~= "string" or type(sender) ~= "string" or IsMe(sender) then
		return
	end
	local command, version = text:match("^(%u+):?(.*)$")
	if command == "HELLO" then
		Heard(sender, version)
		MaybeReply(version, channel)
	elseif command == "VER" then
		Heard(sender, version)
		-- Someone with at least our version already answered there.
		local theirs, mine = versionCheck.Parse(version), versionCheck.Parse(versionCheck.MyVersion())
		if theirs and mine and versionCheck.Compare(theirs, mine) >= 0 then
			pendingReply[channel] = nil
		end
	elseif command == "WHO" then
		Send("VER:" .. versionCheck.MyVersion(), "WHISPER", sender)
	end
end

------------------------------------------------------------------------------
-- /nra who
------------------------------------------------------------------------------

local function PrintWho(since)
	local list = {}
	for sender, info in pairs(known) do
		if info.time >= since then
			table.insert(list, { name = DisplayName(sender), version = info.version })
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	local mine = versionCheck.Parse(versionCheck.MyVersion())
	local function Describe(version)
		local parsed = versionCheck.Parse(version)
		if not parsed then
			return version == "dev" and "dev" or "?"
		end
		if mine and versionCheck.Compare(parsed, mine) < 0 then
			return "|cff808080" .. version .. " (older)|r"
		elseif mine and versionCheck.Compare(parsed, mine) > 0 then
			return "|cff33ff33" .. version .. " (newer)|r"
		end
		return version
	end
	ns:Print(string.format("%d %s in your guild and group run NraKit (you: %s):", #list,
		#list == 1 and "other player" or "other players", versionCheck.MyVersion()))
	for _, entry in ipairs(list) do
		print(string.format("  %s  %s", entry.name, Describe(entry.version)))
	end
	local session, ever = versionCheck.SeenCounts()
	print(string.format("  |cff808080NraKit users you've come across: %d this session, %d in all.|r", session, ever))
end

-- How many other NraKit users you've heard from (guild, group, whispers): this session, and ever.
function versionCheck.SeenCounts()
	local session, ever = 0, 0
	for _ in pairs(known) do
		session = session + 1
	end
	for _ in pairs(NraKitDB.nraKitUsersSeen or {}) do
		ever = ever + 1
	end
	return session, ever
end

local WHO_HELP = {
	summary = "who in your guild and group runs NraKit, and which version",
	usage = { "/nra who - ask your guild and group which NraKit version they run (answers come in over a few seconds)" },
}

local function OnWho()
	if not versionCheck.Enabled() then
		ns:Print("Version sharing is off (What's New, /nra new), so NraKit doesn't ask or answer.")
		return
	end
	local since = GetTime()
	local sent = false
	if IsInGuild() then
		sent = Send("WHO", "GUILD") or sent
	end
	sent = Send("WHO", GroupChannel()) or sent
	if not sent then
		ns:Print("Not in a guild or group (or addon messages are blocked here), so there's nobody to ask.")
		return
	end
	ns:Print("Asking your guild and group...")
	C_Timer.After(WHO_WAIT, function()
		PrintWho(since)
	end)
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, channel, sender = ...
		if prefix == PREFIX then
			versionCheck.OnMessage(text, channel, sender)
		end
	elseif event == "PLAYER_LOGIN" then
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		C_Timer.After(HELLO_DELAY, function()
			if IsInGuild() then
				Hello("GUILD")
			end
			groupChannel = GroupChannel()
			Hello(groupChannel)
		end)
	elseif event == "GROUP_ROSTER_UPDATE" then
		-- Joined a group (or it became a raid or instance group): say hello there once.
		local channel = GroupChannel()
		if channel ~= groupChannel then
			groupChannel = channel
			if channel then
				C_Timer.After(GROUP_DELAY, function()
					if GroupChannel() == channel then
						Hello(channel)
					end
				end)
			end
		end
	end
end)

ns:RegisterSlashCommand("who", OnWho, WHO_HELP)
