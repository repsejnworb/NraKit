# NraKit

**Small quality-of-life tweaks for WoW Forever. Every feature is off by default, so turn on only what you want.**

Type **/nrakit** (or **/nra**), or open **Options → AddOns → NraKit**. The main page has an on/off switch for each feature, and features with options get their own page.

## Features

### Class-colored health bars
Your player, target, target-of-target, focus and party frames show **class-colored health bars** for players. NPCs keep their normal colors.

### Engaged-only nameplates
See plates only for the enemies that are actually fighting you.
- Full nameplates **only for enemies attacking you** (optionally also your party/raid).
- Every other enemy is hidden, so no more wall of health bars from mobs you aren't fighting.
- Optionally keep idle enemies' **names**, styled like the game's own overhead names, with adjustable size, height, outline and shadow.
- Optionally turns enemy nameplates **on when you enter combat and off when you leave it**, so you get clean overhead names while questing. (Forever's own "Always Show Nameplates" setting doesn't limit plates to combat at the moment.) If you turn enemy nameplates on yourself (V), they stay on.
- Your target, focus and enemy players always get full nameplates.

### Most valuable quest reward
When a quest lets you choose a reward, a **gold coin** marks the one that sells to a vendor for the most gold (sell price × stack size).

### Quest level
Shows the **quest's level in front of its title** in the quest dialog and quest details, like **[24] The Defias Brotherhood**, colored by difficulty just like the quest log.

### Bag Tithe
Find out what to throw away when your bags are full.
- A button next to the bag sort button **highlights your least valuable slots** (sell price × stack size), ranked from red to yellow, with rank numbers and sell values.
- Everything else is dimmed; your bags work as normal underneath.
- **Alt+click** an item to leave it out of the ranking. The ignore list can be edited in the options.

### Potential Upgrades
**Arrows on bag items and quest rewards**, plus a tooltip line, for items that beat what you're wearing.
- **Green**: clear upgrade. Usable now and at least as good on every stat that matters for your class (plus armor or weapon DPS).
- **Yellow**: likely upgrade, using a simple per-class stat priority.
- **Grey**: an upgrade once you reach the required level.

### Known recipes
No more mousing over every recipe at a vendor. Recipes you **already know get a green check** and a greyed-out icon at vendors, and a check in your bags.
- Optionally marks recipes for your professions that you **can learn now (green +)** or **once your skill is high enough (yellow +)**.
- Works for anything the game calls "Already known".
- Optionally makes **Bag Tithe** rank known recipes as junk.

### Inventory Tracker
Where did I put that? **Item tooltips show how many each of your characters has**, and where: bags, bank, mail or equipped, plus a total.
- Visit the bank and mailbox once on each character so they're known; after that they stay up to date.
- Items you **mail to your own characters** show up on them right away.
- **/nra inv** lists tracked characters, **/nra inv forget &lt;name&gt;** removes one.

### Open Clams
A small button at the bottom of your bags, next to your money, **opens the next clam** (or any other "Right Click to Open" container, except locked boxes) **one click at a time**, and shows how many are left.
- Can be **bound to a key** (Keybindings → AddOns → NraKit).
- Openable items get a **green border** in your bags.

### Sous Chef
Have the meat but not the spices? In the cooking window, recipes where you have the **main ingredient** but are missing **vendor-bought extras** (spices, water, flour...) show an icon of **what to buy and how much**.
- Tooltips on main ingredients list what they cook into and what's missing.
- Optionally only for recipes that still give skill, and optionally for all professions.

### Unspent talent points
A **reminder in the middle of the screen** while you have talent points to spend. Size and position are adjustable, and it can hide in combat.

### /leave leaves your group
Type **/leave** (with nothing after it) or **/leavegroup** to leave your party, raid or instance group. **/leave &lt;channel&gt;** still leaves a chat channel.

### Open selected mail
A **checkbox on each mail** in your inbox. Tick the ones you want and the **Open All** button becomes **Open Selected**, opening only those.

### Hide micro menu notifications
Hides the blue notification dot on the **Shop** button that never goes away.

### Unit Scanner
Get alerted when a **mob or player from your own list** shows up.
- **Sound, on-screen text, chat line** and a flashing taskbar icon, each optional.
- Found units get a **raid marker** (Moon by default), and a **button to target them** with one click or a keybind.
- Target a unit and type **/nra scan** to add it (again to remove it), or use **/nra scan &lt;name or NPC ID&gt;**, **/nra scan list**, **/nra scan remove &lt;# or name&gt;** and **/nra scan clear**.
- Units are found through nameplates, mouseover, your and your group's targets, **minimap markers** (rares) and **NPC yells and emotes**. The nameplate range can optionally be raised while scanning.
- Addons can only see units the game already shows you, so keep enemy nameplates on (with Engaged-only nameplates, the scanner keeps them on for you).

## Feedback and bugs
NraKit is a growing collection of small fixes. Found a bug or have an idea? **[Open an issue on GitHub](https://github.com/repsejnworb/NraKit/issues).**

Source code: [github.com/repsejnworb/NraKit](https://github.com/repsejnworb/NraKit) (MIT license)
