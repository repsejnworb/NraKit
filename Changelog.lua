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
