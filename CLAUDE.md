# NraKit

A World of Warcraft **Forever** addon: a collection of small, independent QoL features.

## Working conventions

- Conventional commits (`feat:`, `fix:`, ...). **Never** add a `Co-Authored-By` or any other attribution trailer.
- Work directly in this `main/` worktree, commit, and push to `origin/main`.
- **Every feature is off by default** (module `default = false`). Sub-options inside a feature may default on.
- **Changelog:** every `feat:`/`fix:` commit that changes something players can see adds a line to the `Unreleased`
  block at the top of `Changelog.lua`, in the same commit (add the block if it's missing). Write it for players
  ("Player notes: ..."), not as the commit message; kinds are `new`, `improved`, `fixed`. A new feature's entry is
  `{ "new", "...", module = "<module key>" }` (the window shows its on/off switch there; a test fails if a module
  has none). Only ever add entries, never remove or reorder them (the game counts them to know what's new to someone).
  Tests, refactors and docs need no entry. `just release` turns `Unreleased` into the version and writes `CHANGELOG.md`
  (the CurseForge/GitHub release notes); `just changelog-check` (run by release) fails on feat/fix commits with an
  empty `Unreleased`.
- Each feature should be toggleable on the NraKit overview page; anything tunable goes in settings, not code constants.
- Run `just test` before committing (it also syntax-checks). It uses LuaJIT (Lua 5.1, like the game). `tests/run.lua` loads the whole addon in TOC order into a
  stand-in client (`tests/wow.lua`), logs in and runs a `tests/*_test.lua` file; each file is a fresh process. Tests
  click through windows (`wow.click("Create goal")`, `wow.type`, `wow.tick`, `wow.fire(event, ...)`) and assert on
  saved data. Add tests for new logic and windows, and a regression test for each bug found. The stand-in only
  catches Lua errors and logic; looks and real API behaviour still need the user in game (they paste
  errors/screenshots). Unknown WoW functions do nothing there: give the stand-in real data where a test depends on it.
  Ask them to run `/console scriptErrors 1` when testing. Chat `/run` lines are cut off at 255 characters, so split long diagnostics.

## Target client

- WoW Forever is built on the **Retail (mainline) UI**, not Classic. TOC `## Interface: 16001`
  (build range 16000–19999). Using the Retail number from `version.txt` (120105) shows "incompatible".
- References live outside the repo, in `../tmp/`:
  - `../tmp/wow-ui-source/` – Blizzard UI source, on the **`forever` branch** (Forever's own UI, incl. Forever-only
    systems like `Blizzard_LegacySystem`). Read it before guessing at Forever APIs. `Interface/AddOns/Blizzard_APIDocumentationGenerated/` documents
    APIs, including secret-value rules (`SecretPredicatesDocumentation.lua`).
  - `../tmp/Chattynator/` – a known-working Forever addon (see `Core/Constants.lua` for flavor detection).
  - `../tmp/screenshots/` – in-game screenshots the user provides.

## Layout

- `NraKit.toc` – load order; new modules must be added here.
- `Core.lua` – namespace, module registry, SavedVariables (`NraKitDB`), `/nrakit` and `/nra`. The module table format is documented at the top.
- `Settings.lua` – Blizzard Settings API page (Options > AddOns > NraKit): section headers with an on/off switch per
  module. Modules with `options` get a subpage named after the module; options support `type = "number"` sliders
  (`min/max/step/format`), `header = "..."` subsections, `parent = <option key>` nesting (greyed out unless the
  parent is on) and `requires = <module key>` (greyed out while that other module is off). `ns.sectionOrder` lists the sidebar groups; put new modules in one of them. Change values with
  `ns:SetSetting(key, value)` (both UIs and the module callbacks stay in step).
- `Sounds.lua` – sound choices (`ns.sounds`): values are `"kit:NAME"`, `"lsm:Name"`, `"none"` (or `"default"` per goal).
  Options with `type = "sound"` get a dropdown + Play in both UIs; play them with `ns.sounds.PlayOption(key, default)`.
  `UI.CreateSoundSelect` is the widget; "More sounds..." searches all of SOUNDKIT and LibSharedMedia.
- `UI.lua` – shared look for NraKit's windows (`ns.UI`: window with title bar and sidebar, nav buttons, flat
  tabs/chips, search box, scroll area, widget pools, colours). New windows should use it. NraKit's main windows are
  tabs of one app: `UI.CreateWindow(..., tabKey)` at `UI.WINDOW_WIDTH`x`UI.WINDOW_HEIGHT` plus `UI.RegisterTab{ key, label,
  menuLabel, order, frameName, open, module }` gives the tab strip, one-open-at-a-time, a shared position and an
  entry in the addon button's right-click menu. Tabs always show; while `module` is off the tab is dimmed and opens a
  shared "feature is off" page (name, description, turn-on button) instead of the window. Add window OnShow/OnHide handlers with `HookScript`, not `SetScript`.
- `Toast.lua` – NraKit's messages in the middle of the screen (`ns.toast.Show{ style = "big"|"small", heading, text,
  icon/atlas, detail, duration, onClick, skipIfBusy }`); small ones wait their turn, big ones go in front. Use it for
  any feature's on-screen message.
- `Preview.lua` – `/nra preview <name>` (also `/nra test`): shows a feature's on-screen message or bar with made-up
  content. Anything a feature pops up on screen gets one: `ns:RegisterPreview(name, description, show)`.
- `Changelog.lua` – what's new per version, for players (see the changelog rule above). `WhatsNew.lua` tracks what
  each player has seen, prints one chat line after an update and registers `/nra new`; the page is in `Options.lua`.
  `tools/changelog.lua` is the release tooling (`count`, `release <version> <date>`, `markdown <version>`).
- `VersionCheck.lua` – "a newer NraKit is out" and `/nra who`, over addon messages (prefix `NraKit`) to the guild and
  group. Uses the TOC `## Version`; a git clone (`@project-version@`) counts as `dev` and never compares.
- `Options.lua` – NraKit's own window (`/nra`): sidebar with search, What's new and sections, a card per module with inline
  options. Built entirely from the module definitions, so new modules need no work here. Custom per-module buttons
  go through `ns:AddOptionsButton(moduleKey, label, description, onClick)` and show in both UIs.
- `Bindings.xml` – keybindings (auto-loaded by the game, not listed in the TOC); binding names are set in Lua.
  Use `category="NraKit"`: in Key Bindings each category is a section (a `header` only adds a spacer line).
- `Modules/*.lua` – one feature per file, registered with `ns:RegisterModule(module)`.
  `module:OnSettingsRegistered(root, subcategory, sublayout)` can add custom controls (e.g. buttons) or extra
  pages (canvas subcategories, like the Bag Tithe ignore list).

## Restrictions learned the hard way (Midnight-era client)

- Many unit API results can be **secret values**. Never compare or branch on them; check `issecretvalue()` first.
  FontStrings and textures accept secrets directly (`SetText(UnitName(u))`, `SetTextColor(UnitSelectionColor(u))`).
- `UnitThreatSituation("player"/party/pet, "nameplateN")` is **not** secret, so it's safe for "is this mob fighting me".
- Nameplate regions are **restricted**: `GetPoint()` on them errors ("Can't measure restricted regions"). Don't move or
  restore Blizzard's nameplate elements. Hide the Blizzard `UnitFrame` with `SetAlpha` and draw our own overlay frame parented to the plate.
  `plate:GetScale()` **is** readable (it includes UI scale and the distance/selected scale).
- Addons can't change a nameplate's click area in combat, and can't get distances to non-group enemies.
- Hook Blizzard functions with `hooksecurefunc`. Some are captured by reference (e.g. `QuestInfo_ShowRewards` in
  `QUEST_TEMPLATE_*.elements`), so hook the caller instead (`QuestInfo_Display`).
- Bag item buttons are protected (they use and equip items). Only add non-mouse overlay frames on top, and use
  `HookScript` to observe clicks. Alt+left-click has no default action on bag items. Separate and combined
  ("compact") bags share `BagItemSearchBox`/`BagItemAutoSortButton`, which Blizzard moves between frames.
- **Taint:** never call Blizzard code that lazily caches Lua state from our code. Calling
  `ContainerFrameUtil_EnumerateContainerFrames()`, `frame:EnumerateValidItems()` (via `GetBagSize`) or
  `UpdateSearchBox()` let our code fill Blizzard's caches, and using bag items (e.g. learning a recipe) then
  got blocked as "NraKit". Use `ns:ForEachBagItemButton(fn)` (reads `frame.Items` directly). Reading
  Blizzard state is safe; writing it (or making Blizzard write it on our call stack) is not.
- Using items is protected: it needs a `SecureActionButtonTemplate` button (`type = "item"`), one hardware click
  or key press per use, and its attributes/position/Show/Hide can only change out of combat (defer to
  `PLAYER_REGEN_ENABLED`). Use items by `"item:<id>"`, not bag slot, so a stale button can't use whatever moved in.
  `ContainerItemInfo.hasLoot` marks openable items (lockboxes too; their tooltip shows `LOCKED` until picked).
  Never parent or anchor a secure button to Blizzard's bag frames: doing so (likely) made `ToggleAllBags` fail its
  `assert(IsAnyBagOpen() == false)`. Put it on UIParent and position it absolutely (see OpenClams.lua).
- Profession recipe rows (`ProfessionsRecipeListRecipeMixin`, in the load-on-demand Blizzard_ProfessionsTemplates)
  copy the mixin's `Init` when created: hook the mixin on `ADDON_LOADED`, and hook rows created earlier one by one.
  Blizzard re-runs `SetScript("OnEnter")` on every init, so use the `Professions.RecipeListOnEnter` EventRegistry
  event for row tooltips. Recipe data (`C_TradeSkillUI.*`) is only readable while the profession window is open.
- Units can't be probed by name any more (`TargetUnit` is protected), so a unit scanner only sees nameplates,
  mouseover, targets and vignettes (see UnitScanner.lua). `UnitName`/`UnitGUID` can be secret.
- `/nra <subcommand>` is dispatched through `ns:RegisterSlashCommand(name, handler, help)` in Core.lua; plain `/nra` toggles
  the NraKit window. Always pass `help = { summary, usage = { "/nra x <arg> - what it does", ... } }`: `/nra help` lists
  summaries, `/nra x help` / `/nra x ?` print the usage (Core handles both).
- The **damage meter** (`Blizzard_DamageMeter`) shows secret values in combat, which its code only handles while
  untainted. Restyle it with post-hooks and widget calls on its regions only (`SetTexture`, `SetFont`, `SetAlpha`,
  `SetPoint`); never call its Lua methods that change state (reading, e.g. `ScrollBox:ForEachFrame`, is fine) or write its fields, and keep clicks on its own buttons (see DamageMeterLook.lua).
- Overhead names (with nameplates off) are drawn by the engine, not Lua. A unit with a nameplate never gets its engine name back.

## Forever quirks

- **No realms.** Player names are "Firstname Surname": `UnitName(unit)` returns the two parts (the realm slot holds
  the surname; Blizzard joins them with `CHARACTERNAME_SURNAME_SEPARATOR`, a space). Unit popup menus give
  `contextData.name`/`surname`. Match names case-insensitively and treat "First-Surname" as the same player
  (`ns.playerNotes.Key`).
  Per-character saved data is keyed by `ns:PlayerName()` ("Firstname Surname"), never the first name alone: two
  of a player's characters can share a first name.
- "Always Show Nameplates" off (`nameplateShowAll = 0`) is **broken in Forever** (known since beta): it doesn't limit
  plates to combat. EngagedNameplates toggles `nameplateShowEnemies` on `PLAYER_REGEN_DISABLED`/`ENABLED` instead.
- `nameplateMinScaleDistance` and `nameplateMaxScaleDistance` are both 10, so plates are either full size or min scale (no gradient).
- Modules that change CVars save the user's originals in `NraKitDB` and restore them when turned off.
- Module and option keys are `NraKitDB` keys too (their on/off values). Data a module stores in `NraKitDB` must use a
  different key (e.g. `farmGoalsData`, not `farmGoals`), or it overwrites the setting and breaks.

## Releasing

- CurseForge project ID `1786796` (in the TOC as `X-Curse-Project-ID`). Repo secret `CF_API_KEY` holds the upload token.
- `.github/workflows/release.yml` runs the BigWigs packager on any pushed tag. It builds the zip, creates a GitHub
  release and uploads to CurseForge (Forever flavor, detected from `## Interface: 16001`). `## Version: @project-version@`
  is replaced with the tag. Tags with `alpha`/`beta` upload as alpha/beta files.
  Release with `just release` (Cocogitto picks the next semver from conventional commits since the last tag, asks
  for confirmation, creates an annotated tag and pushes it). `just release-pre alpha.1` makes a pre-release, `just next`
  previews the next version, `just check` syntax-checks the Lua files, `just test` runs the tests (release runs it first). Only release when the user asks.
- `.github/CURSEFORGE.md` is the CurseForge project description (Markdown). CurseForge has no API for it, so the
  user pastes it in by hand. Keep it in sync with README.md when features change.
- Screenshots for README.md live in `.github/screenshots/` (left out of the zip with `.github/`); README.md links them
  by relative path, CURSEFORGE.md by `https://raw.githubusercontent.com/repsejnworb/NraKit/main/.github/screenshots/<name>.png`.
- `.pkgmeta` leaves `.github/`, `CLAUDE.md`, `README.md` and `tests/` out of the zip. `.github/logo.png` is the full logo; `Media/Icon.png` is the in-game icon.
- `.github/workflows/interface-version.yml` checks daily (or run it manually) for a new Forever interface number and opens a PR.
