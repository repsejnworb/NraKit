-- Mail: the four mail features became options of one Mail feature; settings carry over.

return {
	-- Saved by an older version: Fill in mail subject on, the other two off.
	db = { mailSubject = true, openSelectedMail = false, mailRecipient = false, mailRecipientOnOpen = false },
	run = function(t, ns)
		t.test("someone who had a mail feature on gets Mail on, with just those parts", function()
			t.equal(NraKitDB.mail, true, "Mail on")
			t.equal(NraKitDB.mailSubject, true, "subject kept on")
			t.equal(NraKitDB.openSelectedMail, false, "open selected kept off")
			t.equal(NraKitDB.mailRecipient, false, "recipient kept off")
			t.equal(NraKitDB.mailRecipientOnOpen, false, "its sub-option as it was")
			t.equal(NraKitDB.mailAttachAll, true, "the new part on")
			t.ok(ns.mail.IsOn("mailSubject"), "subject works")
			t.ok(not ns.mail.IsOn("mailRecipient"), "recipient doesn't")
		end)

		t.test("someone who had none on: Mail off, every part on for when they turn it on", function()
			local db = { mailSubject = false, openSelectedMail = false, mailRecipient = false }
			ns.modules.mail:Migrate(db)
			t.equal(db.mail, nil, "Mail left to its default (off)")
			t.equal(db.mailSubject, nil, "parts left to their defaults (on)")
			t.equal(db.openSelectedMail, nil, "open selected too")
		end)

		t.test("it only happens once", function()
			local db = { mail = false, mailSubject = true }
			ns.modules.mail:Migrate(db)
			t.equal(db.mail, false, "Mail as set")
			t.equal(db.mailSubject, true, "untouched")
		end)
	end,
}
