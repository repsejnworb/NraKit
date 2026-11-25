local _, ns = ...

-- What's new: the changelog shown in the NraKit window (/nra new), newest first. It is
-- also the release notes on CurseForge and GitHub (tools/changelog.lua writes CHANGELOG.md
-- from it when releasing).
--
-- Written for players, not developers. Every commit that changes something players can
-- see adds a line to the "Unreleased" block at the top (add the block if it's missing);
-- `just release` turns that block into the new version. Entries are only ever added,
-- never removed or reordered: the window counts them to know what's new to someone.
--
-- Entry: { kind, text, module = <module key>? }
--   kind    "new" (a new feature, or something new a feature can do), "improved" or "fixed"
--   module  the feature it's about; a "new" entry with a module gets that feature's
--           on/off switch and a Settings link in the window. Every feature needs one
--           "new" entry with its module (tests/changelog_test.lua checks).

ns.changelog = {
	{ version = "Unreleased", entries = {
		{ "new", "Reminders: notes to yourself that come back when they're due. /nra remind <text> is for your next login; put a trigger in front for later: a time (30m, 2h, 1d, or 1h30m), a zone (in Darkshore: ...), a level (at 30: ...) or another character (@Bankalt: ..., also with a trigger). Shift-clicked items work. Due reminders show on a card that stays until you close it: tick what you've done, and the rest stay in a small list on screen and come back at your next login. A sound plays (pick it in the settings). The new Reminders tab lists them all, with ones you left your other characters, and lets you edit them or be reminded again later. /nra preview reminders shows the card.", module = "reminders" },
		{ "improved", "Wishlist: the ? button at the top shows how to add items again (with examples), once your wishlist isn't empty anymore." },
	} },
	{ version = "0.25.0", date = "2026-11-25", entries = {
		{ "improved", "Wishlist: add several items at once by shift-clicking them all into /nra wishlist. Text after an item becomes that item's note." },
	} },
	{ version = "0.24.0", date = "2026-11-25", entries = {
		{ "new", "Unlearned abilities: after a respec, abilities you don't know anymore stay on your bars, only greyed out. Now they get a red cross and a tooltip line, and when your spells change a message says which ones on your bars you lost (click it to take them off, after combat if you're fighting) and which new ones aren't on your bars yet. /nra unlearned lists them, /nra unlearned remove takes them off. /nra preview unlearned shows the message.", module = "unlearnedAbilities" },
		{ "new", "Wishlist: a list of gear you want, per character, by slot. Add items with /nra wishlist <item> [note] (shift-click it in; /nra wish for short), by right-clicking an item link in chat or an item in Item lookup, or by dropping them on the new Wishlist tab. Each shows the level to wear it and your note on where it comes from; filter by Ready, Not yet or Got. Items you get are ticked off with a message. A star marks wishlist items in your bags, at vendors, in quest rewards, the loot window and loot rolls (gold while you want it, grey once you have it), and item tooltips say they're on your wishlist.", module = "wishlist" },
		{ "fixed", "Copy Wowhead link: the box with the link now shows on top of NraKit's windows (it was hidden behind them when copying an item from Item lookup)." },
	} },
	{ version = "0.23.2", date = "2026-11-24", entries = {
		{ "fixed", "Unspent talent points: the reminder no longer shows on top of the talents window. It hides while the window is open, and other windows now cover it too." },
	} },
	{ version = "0.23.1", date = "2026-11-24", entries = {
		{ "fixed", "Potential Upgrades: green \"Equip:\" bonuses now count, on both the new item and the one you wear: attack power, spell power and healing, mana per 5, and chance to hit or crit. A ring with +8 Attack Power is no longer treated as having nothing on it, and the tooltip line shows the difference (e.g. -8 AP, +1% Crit). Still a rough clue while leveling, not a sim." },
	} },
	{ version = "0.23.0", date = "2026-11-20", entries = {
		{ "new", "Player notes: tags. Give players any number of tags of your own (Ninjalooter, Good tank, Guildie) on their page (+ Tag lists your tags to tick, or makes a new one), or from chat: /nra note Bob Stone kos #ninjalooter stole my node. The notebook lists players in a section per tag (click a section to fold it, shift-click to fold the others, or Fold all), then the players without tags, and the Tags page adds, renames and deletes tags. Shared notes bring their tags along.", module = "playerNotes" },
		{ "improved", "Player notes: the label is now one of four (Kill on sight, Avoid, Neutral, Liked), and tags do the grouping. Your own labels became tags automatically, with the label they were based on; Good and Friend became Liked." },
		{ "improved", "Player notes: right-click a player for Player note, where you can label them (Kill on sight, Avoid, Neutral, Liked) in one click, or open their notes." },
		{ "new", "Player notes: rate the players you like, 1 to 5 stars in halves. Click the stars next to Liked on their page, or right-click a player: Player note, Like and rate (which then opens their notes for a note or tags; an option). The stars show in their tooltip and in your notes, and come along when you share a note." },
		{ "new", "Player notes: filter the list by label. The KoS, Avoid, Neutral and Liked chips under the search show only those players (turn on more than one to see them together); they reset when you close the window." },
	} },
	{ version = "0.22.0", date = "2026-11-20", entries = {
		{ "fixed", "Campfire timer: getting up early no longer says \"Camp Benefits ready\" when you already had Camp Benefits from an earlier rest." },
		{ "improved", "Campfire timer: the bar shows once each time you sit down at the fire, not again every minute while you stay seated." },
		{ "new", "Player notes: share a note in chat. Shift-click a player in your notes (or Link in chat on their page) to put [NraKit note: Name] in chat. Others with NraKit can click it to see the player's label and notes and add them to theirs; notes keep who wrote them, and their own label stays unless they pick yours.", module = "playerNotes" },
	} },
	{ version = "0.21.0", date = "2026-11-20", entries = {
		{ "new", "Damage meter look: a clean, flat look for the game's damage meter. A thin header with a small title and small buttons (shown only while your mouse is over the meter, if you like), flat bars in a softer class colour and outlined text. Size, style and colours are still set in Edit Mode.", module = "damageMeterLook" },
		{ "fixed", "What's new: the Settings button next to a new feature can be clicked again; the feature's on/off switch no longer covers it." },
	} },
	{ version = "0.20.0", date = "2026-11-20", entries = {
		{ "new", "Campfire timer: also works in a sleeping bag. The bar counts your Well-Rested stacks up to 3 and turns green (with the sound) when you're fully rested. After the first stack it also knows how long the rest takes, and shows the time left. It can be turned off in its settings. /nra preview sleepingbag shows it." },
	} },
	{ version = "0.19.0", date = "2026-11-20", entries = {
		{ "new", "/nra preview: see any of NraKit's on-screen messages with made-up content (goal complete, milestones, quest reminders, Unit Scanner alerts, player warnings, the talent reminder, the campfire bar), to check how they look. /nra preview lists them." },
		{ "new", "Quests to turn in: /nra done (or a key) shows a small list of your finished quests by the zone you turn them in. Click one to see it on the map, right-click to make it your waypoint. The zones are sorted by how far away they are, and entering one where you have quests to turn in shows a small message you can click to open the list.", module = "turnInQuests" },
		{ "new", "Mail: an arrow next to Open All with more ways to open: collect only auction gold (sales and outbid refunds), auction purchases or expired auctions, or take the money from every mail and leave the items. Each says how many mails and how much gold first.", module = "mail" },
		{ "new", "Mail: Alt+click an item in your bags with Send Mail open to attach every stack of it you have (all your Silk Cloth, all your Small Red Pouches), as many as fit.", module = "mail" },
		{ "improved", "Mail: Open selected mail, Fill in mail subject and Remember mail recipient are now parts of one Mail feature, each with its own switch. If you had any of them on, Mail is on with the same parts." },
	} },
	{ version = "0.18.0", date = "2026-11-19", entries = {
		{ "improved", "NraKit window: every tab is always there. Tabs of features that are off are dimmed and show what the feature does, with a button to turn it on." },
		{ "fixed", "NraKit window: tabs update right away when you turn a feature on or off, instead of after switching tabs." },
	} },
	{ version = "0.17.2", date = "2026-11-19", entries = {
		{ "improved", "Item lookup: the search box no longer grabs your keyboard when the window opens (or with /nra item <name>), so you can keep moving and fighting; click it to type, and Enter or Esc gives the keys back." },
	} },
	{ version = "0.17.1", date = "2026-11-19", entries = {
		{ "fixed", "Inspect anything: NPCs show their health and attack speed again, with the level, type and stats in small lines above the model as before. Players' level line no longer shows their race, as in the game's own inspect window." },
	} },
	{ version = "0.17.0", date = "2026-11-19", entries = {
		{ "new", "Inspect anything: one key inspects your target (or what's under the mouse when you have none), in a window like the inspect window that stays open until you close it, even when they run off. Players show their gear (loaded after combat if you inspect them in combat), NPCs a 3D model you can turn, move and zoom, with their health, attack speed and a link to their abilities on Wowhead. Set the key under Key Bindings > NraKit, or right-click an NPC or enemy player and choose View 3D model.", module = "inspectAnything" },
		{ "improved", "Key bindings: NraKit's keys have their own NraKit section in Key Bindings instead of being mixed in with other addons'." },
	} },
	{ version = "0.16.0", date = "2026-11-19", entries = {
		{ "new", "Item lookup: search every item in the game by name. /nra item nightbl lists the matching items in an Items tab, with their tooltips; Shift-click to link one in chat. The list of names fills in by itself in the background, with a progress bar in the tab to pause it or check again for newly discovered items.", module = "itemLookup" },
	} },
	{ version = "0.15.0", date = "2026-11-19", entries = {
		{ "new", "Double-click fishing: with a fishing pole in your main hand, double right-click the world to cast Fishing.", module = "doubleClickFishing" },
	} },
	{ version = "0.14.1", date = "2026-11-19", entries = {
		{ "fixed", "Inventory Tracker: characters are kept by first name and surname, so two of yours with the same first name no longer share one inventory. Tooltips and the inventory browser show the full name, and mail to \"Firstname Surname\" counts on that character. Your saved inventories move over when you log in to each character." },
		{ "fixed", "Farm goals: goals are kept by first name and surname, so two characters with the same first name no longer share their goals." },
	} },
	{ version = "0.14.0", date = "2026-11-19", entries = {
		{ "improved", "Farm goals: icons that fit the goal, like an axe for Axes, a pick for Mining, coins for gold and the level's badge for level goals." },
		{ "new", "Farm goals: pick your own icon for a goal, like a macro icon. Click the icon in the goal form, or drop an item or spell on it to use its icon." },
	} },
	{ version = "0.13.0", date = "2026-11-19", entries = {
		{ "new", "Fill in mail subject: the subject of a mail you send is written from what you attach, e.g. \"Linen Cloth (40)\", \"25g\" or \"Linen Cloth (20) + 5g\". A subject you typed is left alone.", module = "mail" },
		{ "new", "Remember mail recipient: the To box keeps the name after you send a mail, so mailing your bank alt again needs no typing. It also fills in the last player you mailed when you open Send Mail.", module = "mail" },
		{ "improved", "The mail features (Open selected mail, Fill in mail subject, Remember mail recipient) have their own Mail section in the NraKit window and settings." },
	} },
	{ version = "0.12.0", date = "2026-11-19", entries = {
		{ "new", "Player notes: give players a label (Kill on sight, Avoid, Neutral, Good, Friend, or your own) and keep dated notes on them. Shown in their tooltip; right-click a player for Player note or to set their label. Warns you when a player you've marked Avoid or Kill on sight joins your group, invites, whispers or trades you.", module = "playerNotes" },
		{ "new", "Unit Scanner alerts you when a player you've labelled Kill on sight (Player notes) shows up nearby.", module = "unitScanner" },
		{ "new", "What's new: this page. NraKit tells you in chat when it has been updated; new features can be turned on right here." },
		{ "improved", "NraKit's windows (Settings, Inventory, Goals, Notes) are tabs of one window: same size and place, with tabs at the top for the features you have on. Right-click NraKit in the addon button by the minimap for a menu of them." },
		{ "new", "NraKit tells you when a newer version is out, when someone in your guild or group already has it. /nra who lists who in your guild and group runs NraKit, which version, and how many NraKit users you've come across. Switch it off on this page." },
	} },
	{ version = "0.11.0", date = "2026-11-18", entries = {
		{ "new", "Farm goals: set goals like \"loot 4000 Silk Cloth\", \"reach level 40\", \"earn 100 gold\", \"reach Revered with Timbermaw Hold\", a skill or a currency, and track them in a small movable tracker with rate per hour and time left. /nra goal opens the goals window.", module = "farmGoals" },
		{ "new", "Farm goals tracker views: Full, Compact and Icons; shelve goals to hide them for a while; go again or set a new target when a goal is done." },
		{ "new", "Farm goals: progress bars are marked at 25/50/75%, tooltips show the percentage, and an optional small message marks each milestone." },
		{ "new", "Inventory browser (/nra inv): every character's bags, bank, mail and equipped items as a grid or a list, with search, categories, level and gold.", module = "inventoryTracker" },
		{ "new", "Choose your alert sounds (Campfire timer, Unit Scanner, Farm goals) from a short list, or search every game sound." },
		{ "new", "NraKit is in the addon button by the minimap: left-click for settings, right-click for the inventory browser." },
		{ "new", "/nra help lists the chat commands; add help after one for details (e.g. /nra goal help)." },
		{ "improved", "Farm goals' finish message is bigger, and shown again after the fight if the goal was done in combat." },
		{ "fixed", "Chosen alert sounds were ignored and the default played instead." },
	} },
	{ version = "0.10.0", date = "2026-11-18", entries = {
		{ "new", "NraKit's own window (/nra): features grouped in a sidebar, search, and every option right under its feature." },
	} },
	{ version = "0.9.0", date = "2026-11-18", entries = {
		{ "new", "Copy Wowhead link: hover an item, spell, NPC, quest, achievement or currency and press Ctrl+C to get its wowhead.com/forever link.", module = "wowheadLink" },
		{ "improved", "The Wowhead link box sits in the middle of the screen and closes when you copy (Cmd+C on a Mac)." },
	} },
	{ version = "0.8.0", date = "2026-11-17", entries = {
		{ "new", "Campfire timer: a progress bar in the middle of the screen while you rest at a Welcoming Campfire.", module = "campfireTimer" },
	} },
	{ version = "0.7.0", date = "2026-11-17", entries = {
		{ "new", "Inventory Tracker: item tooltips show how many each of your characters has, and where.", module = "inventoryTracker" },
		{ "new", "Known recipes: recipes you already know get a green check at vendors and in your bags.", module = "knownRecipes" },
		{ "new", "Open selected mail: tick mails in your inbox and Open All only opens those.", module = "mail" },
		{ "new", "Hide micro menu notifications: no more \"new\" dot on the Shop button, and the Legacy button's dot only for unspent points.", module = "microMenuNotifications" },
		{ "fixed", "One feature failing to start no longer stops the others." },
	} },
	{ version = "0.6.0", date = "2026-11-16", entries = {
		{ "new", "Unit Scanner: alerts you when a mob or player from your list shows up nearby, marks it and gives you a button to target it.", module = "unitScanner" },
		{ "new", "/leave with nothing after it leaves your group.", module = "leaveGroup" },
		{ "new", "Unspent talent points: a reminder while you have points to spend.", module = "unspentTalents" },
		{ "new", "Show quest level: the quest's level in front of its title.", module = "questLevel" },
		{ "fixed", "Engaged-only nameplates hides idle enemies out of combat too, and leaves nameplates on after combat if you turned them on yourself." },
	} },
	{ version = "0.5.0", date = "2026-11-12", entries = {
		{ "new", "Sous Chef: cooking recipes where you only miss vendor-bought spices, water or flour show what to buy.", module = "sousChef" },
	} },
	{ version = "0.4.4", date = "2026-11-10", entries = {
		{ "fixed", "Using items from your bags (e.g. learning a recipe) could be blocked by NraKit." },
	} },
	{ version = "0.4.3", date = "2026-11-10", entries = {
		{ "fixed", "Open Clams only warns in combat when it can't switch to the next kind of item." },
	} },
	{ version = "0.4.2", date = "2026-11-10", entries = {
		{ "fixed", "The Open Clams button was hidden behind the bags." },
	} },
	{ version = "0.4.1", date = "2026-11-10", entries = {
		{ "fixed", "Open Clams could stop the bags from opening." },
	} },
	{ version = "0.4.0", date = "2026-11-10", entries = {
		{ "new", "Open Clams: a button by your bag money opens clams and other containers one click at a time.", module = "openClams" },
	} },
	{ version = "0.3.0", date = "2026-11-07", entries = {
		{ "new", "Potential Upgrades: arrows on items that beat what you have equipped.", module = "potentialUpgrades" },
	} },
	{ version = "0.2.0", date = "2026-11-06", entries = {
		{ "new", "Bag Tithe: a button by the bag sort button highlights your least valuable bag slots, with sell values.", module = "bagTithe" },
	} },
	{ version = "0.1.0", date = "2026-11-06", entries = {
		{ "new", "Class-colored health bars on player, target, focus and party frames.", module = "classColorHealthBars" },
		{ "new", "Engaged-only nameplates: full nameplates only for enemies fighting you.", module = "engagedNameplates" },
		{ "new", "Mark most valuable quest reward: a gold coin on the reward that sells for the most.", module = "questRewardValue" },
	} },
}
