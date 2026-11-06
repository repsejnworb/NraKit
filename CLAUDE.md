# NraKit

A World of Warcraft **Forever** addon: a collection of small, independent QoL features.

## Working conventions

- Conventional commits (`feat:`, `fix:`, ...). **Never** add a `Co-Authored-By` or any other attribution trailer.
- Work directly in this `main/` worktree, commit, and push to `origin/main`.
- **Every feature is off by default** (module `default = false`). Sub-options inside a feature may default on.
- Each feature should be toggleable on the NraKit overview page; anything tunable goes in settings, not code constants.
- No local test runner: syntax-check with `luac -p <file>`; the user tests in-game and pastes errors/screenshots.
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
- `Modules/*.lua` – one feature per file, registered with `ns:RegisterModule(module)`.

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
- Overhead names (with nameplates off) are drawn by the engine, not Lua. A unit with a nameplate never gets its engine name back.

## Forever quirks

- "Always Show Nameplates" off (`nameplateShowAll = 0`) is **broken in Forever** (known since beta): it doesn't limit
  plates to combat. EngagedNameplates toggles `nameplateShowEnemies` on `PLAYER_REGEN_DISABLED`/`ENABLED` instead.
- `nameplateMinScaleDistance` and `nameplateMaxScaleDistance` are both 10, so plates are either full size or min scale (no gradient).
- Modules that change CVars save the user's originals in `NraKitDB` and restore them when turned off.
