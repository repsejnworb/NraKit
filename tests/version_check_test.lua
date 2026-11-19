-- Newer version check and /nra who (VersionCheck.lua): versions, replies, the notice,
-- and staying quiet when switched off, blocked or on a development copy.

return {
	run = function(t, ns, wow)
		local check = ns.versionCheck
		local sent, timers = {}, {}
		local version = "0.12.0"
		C_AddOns.GetAddOnMetadata = function()
			return version
		end
		C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
			table.insert(sent, { prefix = prefix, message = message, channel = channel, target = target })
		end
		C_Timer.After = function(_, callback)
			table.insert(timers, callback)
		end
		IsInGuild = function()
			return true
		end
		local function RunTimers()
			local pending = timers
			timers = {}
			for _, callback in ipairs(pending) do
				callback()
			end
		end
		local function Message(text, channel, sender)
			wow.fire("CHAT_MSG_ADDON", "NraKit", text, channel or "GUILD", sender or "Bob Stone")
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end

		t.test("versions: parse and compare", function()
			local P, C = check.Parse, check.Compare
			t.ok(C(P("0.13.0"), P("0.12.9")) > 0, "minor beats patch")
			t.ok(C(P("v1.0.0"), P("0.99.0")) > 0, "major, with a v")
			t.ok(C(P("0.13.0-alpha.1"), P("0.13.0")) < 0, "a pre-release comes before its release")
			t.ok(C(P("0.13.0-beta.1"), P("0.13.0-alpha.2")) > 0, "beta after alpha")
			t.equal(C(P("0.12.0"), P("v0.12.0")), 0, "same")
			t.ok(P("v99") == nil and P("@project-version@") == nil and P("1.2.3.4") == nil and P("9999.0.0") == nil, "rejects junk")
		end)

		t.test("says hello to the guild after login", function()
			sent = {}
			wow.fire("PLAYER_LOGIN")
			RunTimers()
			t.equal(sent[1] and sent[1].message, "HELLO:0.12.0", "hello")
			t.equal(sent[1].channel, "GUILD", "to the guild")
			t.equal(sent[1].prefix, "NraKit", "prefix")
		end)

		t.test("says hello to a group once when joining it", function()
			sent = {}
			wow.data.party = { "party1" }
			wow.fire("GROUP_ROSTER_UPDATE")
			wow.fire("GROUP_ROSTER_UPDATE")
			RunTimers()
			t.equal(#sent, 1, "once")
			t.equal(sent[1].channel, "PARTY", "to the party")
			wow.data.party = {}
			wow.fire("GROUP_ROSTER_UPDATE")
		end)

		t.test("answers an older hello, unless someone newer already did", function()
			sent = {}
			Message("HELLO:0.11.0", "GUILD", "Old Timer")
			RunTimers()
			t.equal(sent[1] and sent[1].message, "VER:0.12.0", "answered")
			t.equal(sent[1].channel, "GUILD", "on the same channel")
			sent = {}
			Message("HELLO:0.11.0", "GUILD", "Old Timer")
			Message("VER:0.12.0", "GUILD", "Quick Responder")
			RunTimers()
			t.equal(#sent, 0, "someone else answered first")
			sent = {}
			Message("HELLO:0.12.0", "GUILD", "Same Version")
			RunTimers()
			t.equal(#sent, 0, "no answer to the same version")
		end)

		t.test("a newer pre-release doesn't count for a release", function()
			wow.printed = {}
			Message("VER:0.13.0-beta.1", "GUILD", "Beta Tester")
			t.ok(not Printed("is out"), "quiet")
			t.ok(check.Newer() == nil, "nothing newer")
		end)

		t.test("a newer release: one chat line per session", function()
			wow.printed = {}
			Message("VER:0.13.0", "GUILD", "Ann Lee")
			t.ok(Printed("0.13.0 is out") and Printed("you have 0.12.0"), "told")
			t.equal(check.Newer(), "0.13.0", "remembered")
			wow.printed = {}
			Message("HELLO:0.14.0", "PARTY", "Cid Vale")
			t.equal(#wow.printed, 0, "not again")
			t.equal(check.Newer(), "0.14.0", "but the newest is kept")
		end)

		t.test("What's new shows that a newer version is out", function()
			ns:OpenWhatsNew()
			local notices = wow.findAll(function(frame)
				local text = rawget(frame, "text")
				return frame.shown and type(text) == "string" and text:find("0.14.0 is out", 1, true)
			end)
			t.ok(#notices >= 1, "notice on the page")
		end)

		t.test("answers /nra who by whisper, ignores its own messages", function()
			sent = {}
			Message("WHO", "GUILD", "Dee Rook")
			t.equal(sent[1] and sent[1].channel, "WHISPER", "whisper")
			t.equal(sent[1].target, "Dee Rook", "to the asker")
			sent = {}
			Message("WHO", "GUILD", "Nra")
			t.equal(#sent, 0, "not to yourself")
		end)

		t.test("/nra who asks and lists who answered", function()
			sent, wow.printed = {}, {}
			wow.now = 5000
			SlashCmdList.NRAKIT("who")
			t.equal(sent[1] and sent[1].message, "WHO", "asked")
			Message("VER:0.12.0", "WHISPER", "Eli-Moss")
			Message("VER:dev", "WHISPER", "Fay Dorn")
			RunTimers()
			t.ok(Printed("2 other players"), "count")
			t.ok(Printed("Eli Moss") and Printed("Fay Dorn  dev"), "listed, dash names readable")
			t.ok(not Printed("Ann Lee"), "only who answered now")
		end)

		t.test("blocked addon messages: nothing is sent", function()
			C_ChatInfo.InChatMessagingLockdown = function()
				return true
			end
			sent = {}
			Message("WHO", "GUILD", "Dee Rook")
			t.equal(#sent, 0, "nothing sent")
			C_ChatInfo.InChatMessagingLockdown = nil
		end)

		t.test("switched off: sends nothing, hears nothing", function()
			NraKitDB.versionCheck = false
			sent, wow.printed = {}, {}
			Message("WHO", "GUILD", "Dee Rook")
			wow.fire("PLAYER_LOGIN")
			RunTimers()
			t.equal(#sent, 0, "nothing sent")
			SlashCmdList.NRAKIT("who")
			t.ok(Printed("Version sharing is off"), "/nra who explains")
			NraKitDB.versionCheck = nil
		end)

		t.test("a development copy answers who as dev and never compares", function()
			version = "@project-version@"
			t.equal(check.MyVersion(), "dev", "dev")
			sent = {}
			Message("HELLO:0.1.0", "GUILD", "Old Timer")
			RunTimers()
			t.equal(#sent, 0, "doesn't answer old hellos")
			Message("WHO", "GUILD", "Dee Rook")
			t.equal(sent[1] and sent[1].message, "VER:dev", "who answer")
		end)
	end,
}
