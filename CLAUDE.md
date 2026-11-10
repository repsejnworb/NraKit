# NraKit

A World of Warcraft **Forever** addon: a collection of small, independent QoL features.

## Working conventions

- Conventional commits (`feat:`, `fix:`, ...). **Never** add a `Co-Authored-By` or any other attribution trailer.
- Work directly in this `main/` worktree, commit, and push to `origin/main`.
- **Every feature is off by default** (module `default = false`). Sub-options inside a feature may default on.
- Each feature should be toggleable on the NraKit overview page; anything tunable goes in settings, not code constants.
- No local test runner: syntax-check with `just check` (`luac -p`); the user tests in-game and pastes errors/screenshots.
  Ask them to run `/console scriptErrors 1` when testing. Chat `/run` lines are cut off at 255 characters, so split long diagnostics.

## Target client

- WoW Forever is built on the **Retail (mainline) UI**, not Classic. TOC `## Interface: 16001`
  (build range 16000–19999). Using the Retail number from `version.txt` (120105) shows "incompatible".
- References live outside the repo, in `../tmp/`:
  - `../tmp/wow-ui-source/` – Blizzard UI source (Retail 12.x). `Interface/AddOns/Blizzard_APIDocumentationGenerated/` documents
    APIs, including secret-value rules (`SecretPredicatesDocumentation.lua`).
  - `../tmp/Chattynator/` – a known-working Forever addon (see `Core/Constants.lua` for flavor detection).
  - `../tmp/screenshots/` – in-game screenshots the user provides.

## Layout

- `NraKit.toc` – load order; new modules must be added here.
- `Core.lua` – namespace, module registry, SavedVariables (`NraKitDB`), `/nrakit` and `/nra`. The module table format is documented at the top.
- `Settings.lua` – Blizzard Settings API. Main page = one header plus an on/off switch per module (`module.section`).
  Modules with `options` get a subpage; options support `type = "number"` sliders (`min/max/step/format`),
  `header = "..."` subsections, and `parent = <option key>` nesting (greyed out unless the parent is on).
- `Bindings.xml` – keybindings (auto-loaded by the game, not listed in the TOC); binding names are set in Lua.
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
- Overhead names (with nameplates off) are drawn by the engine, not Lua. A unit with a nameplate never gets its engine name back.

## Forever quirks

- "Always Show Nameplates" off (`nameplateShowAll = 0`) is **broken in Forever** (known since beta): it doesn't limit
  plates to combat. EngagedNameplates toggles `nameplateShowEnemies` on `PLAYER_REGEN_DISABLED`/`ENABLED` instead.
- `nameplateMinScaleDistance` and `nameplateMaxScaleDistance` are both 10, so plates are either full size or min scale (no gradient).
- Modules that change CVars save the user's originals in `NraKitDB` and restore them when turned off.

## Releasing

- CurseForge project ID `1786796` (in the TOC as `X-Curse-Project-ID`). Repo secret `CF_API_KEY` holds the upload token.
- `.github/workflows/release.yml` runs the BigWigs packager on any pushed tag. It builds the zip, creates a GitHub
  release and uploads to CurseForge (Forever flavor, detected from `## Interface: 16001`). `## Version: @project-version@`
  is replaced with the tag. Tags with `alpha`/`beta` upload as alpha/beta files.
  Release with `just release` (Cocogitto picks the next semver from conventional commits since the last tag, asks
  for confirmation, creates an annotated tag and pushes it). `just release-pre alpha.1` makes a pre-release, `just next`
  previews the next version, `just check` syntax-checks the Lua files. Only release when the user asks.
- `.pkgmeta` leaves `.github/`, `CLAUDE.md` and `README.md` out of the zip. `.github/logo.png` is the full logo; `Media/Icon.png` is the in-game icon.
- `.github/workflows/interface-version.yml` checks daily (or run it manually) for a new Forever interface number and opens a PR.
