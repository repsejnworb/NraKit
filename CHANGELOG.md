# NraKit 0.35.0

### Improved
- **Inventory Tracker**: Remembers which recipes each of your characters knows: a recipe (in your bags, at a vendor, a link in chat) says **Known by** which of them, so your bank alt can see your main already has it.
- **Farm Goals**: Item goals show what they're worth at the auction house (Auctionator, else a vendor) and **gold per hour**: "18/h · 38g/h". The finished message says what the goal is worth.
- **Lookup**: Item Lookup is now **Lookup**, with **[ Items ][ Spells ][ Recipes ]** at its top. Items and spells are found by name or **ID**.
  - **Spells**: every spell (`/nra` spell charge), with its **class**, yours first; filter by class. Shift-click links it.
  - **Recipes**: every profession recipe (`/nra` recipe bracers) with what it makes and needs; pick a **profession** with its button.
  - With prices: what a craft **costs**, what it **sells for** and the **profit**; sort by profit to see what's worth crafting.
  - Right-click a recipe for the shopping-list menu; hover for its tooltip with what you have.
- **Bag Tithe**: With Auctionator, a slot is worth its **auction house** price when that's more than a vendor pays, so valuable trade goods aren't ranked as junk (soulbound items stay at vendor price).
- **Sell List**: Items you're still farming for a Farm Goal stay in their own folded group until the goal is done, so you don't sell what you're collecting.
- **Mail**: **Shift-click** a mail's checkbox to tick every mail from the one you clicked before.
- **Sell List**: A **Gain** column shows how much more the auction house pays than a vendor, and the auction house items are ranked by it: 20s that a vendor pays 1c for now comes before 40s that a vendor pays 39s for.

### Fixed
- **Mail**: Ticking one of several identical mails (a batch you sent yourself) no longer ticks them all.

Type /nra new in game to see what's new in every version.
