# NraKit
WoW Forever addon with a collection of small QoL tweaks.

## Install
Clone or symlink this repo into `World of Warcraft/_<flavor>_/Interface/AddOns/NraKit`
(the folder name must be `NraKit`).

## Settings
Options live in the game's Settings panel under **AddOns → NraKit**, or open them with `/nrakit` (`/nra`).

## Features
- **Class-colored health bars**: player, target, target of target, focus and party frames
  show class-colored health bars when the unit is a player. NPCs keep the default color.
- **Nameplates only for engaged enemies** (off by default): optionally turns enemy nameplates on
  when entering combat and off when leaving it, then shows full plates only for enemies fighting you
  (optionally your group). Other enemy NPCs are hidden during combat, or optionally show just
  their name, restyled to resemble the engine's overhead names. Target, focus and enemy players
  always get full plates. Hidden plates can still be clicked where their bar would be, because
  addons can't change a plate's click area during combat.
