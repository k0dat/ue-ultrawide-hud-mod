# UEUltrawideHUDMod

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for Unreal Engine games. On an ultrawide screen it moves the HUD horizontally into a centred virtual aspect-ratio area (16:9 by default), so health, ammo and minimaps sit near the middle of the screen instead of at its far edges.

Tested on UE 4.27 with Echo Point Nova and System Shock (2023). UE5 is untested. The mod is meant for single-player, offline use: injecting UE4SS into a game with anti-cheat can get you banned.

## Install

1. Install the UE4SS **experimental** build into `<Game>/<Project>/Binaries/Win64/`.
2. Copy `src/UEUltrawideHUDMod` into `ue4ss/Mods/`.
3. Copy the profile for your game from `profiles/` into `Mods/UEUltrawideHUDMod/`, next to `enabled.txt`. For a game without a profile, copy `Template.ini` and fill it in as described below.

The mod loads the first `.ini` file it finds in its folder, whatever its name, so keep only one there. It only moves widgets that are listed in that profile. Restart the game after editing it.

## Configure a new game

1. Load into gameplay with the HUD visible and press **Ctrl+Del**.
2. Open the newest `widgets_*.txt` in `Mods/UEUltrawideHUDMod/`. It lists every widget in the viewport as an indented tree, with each child's anchors and offsets.
3. Find the widget that holds the HUD and add a section named after its class to your profile.

```ini
[General]
VirtualAspect=16:9
PollInterval=1
Debug=false

[WIDGET_PlayerHUD]
Method=anchors
Exclude=PANEL_DamageIndicators,WIDGET_MainMenu_InGame
Unshift=PANEL_Brackets
```

Write `Key=value` with no spaces around `=`, and put comments (`;` or `#`) on their own lines.

| Section | Key | Default | Meaning |
|---|---|---|---|
| `[General]` | `VirtualAspect` | `16:9` | Aspect ratio the HUD is moved into, as `W:H` or a number |
| | `PollInterval` | `1` | Seconds between checks for new HUD widgets and resolution changes |
| | `Debug` | `false` | `true` logs every anchor the mod writes to `UE4SS.log` |
| `[WidgetClass]` | `Method` | `viewport` | `viewport` or `anchors`, see below |
| | `Clip` | `true` | Hide elements that are parked off-screen for slide-in animations |
| | `Exclude` | | `anchors` only: comma-separated children to leave alone |
| | `Unshift` | | `anchors` only: comma-separated widgets the game positions in full-screen coordinates |

The `_C` suffix on the class name is optional. Child names are not case-sensitive.

### Choosing a method

- **viewport** shrinks the whole widget into the virtual area. Use it when the widget holds only HUD elements (Echo Point Nova).
- **anchors** moves each direct child of the widget's first Canvas Panel. Use it when the widget also holds things that must stay full-screen, such as a pause menu or damage overlay, and list those in `Exclude` (System Shock).

With `anchors`, a child that stretches across the screen becomes a container the width of the virtual area. If the game places something inside it using full-screen coordinates (System Shock's selection box), it ends up shifted sideways. Name it in `Unshift` to put it back.

## Known limitations

- Only UMG widgets added directly to the viewport are handled. HUDs drawn with `AHUD`/Canvas calls and widgets nested inside another widget are not.
- A new HUD (after a respawn or loading a save) can show in its original position for up to one poll interval.
- With `anchors`, the mod keeps writing the position it calculated from the anchors it first saw. A child that the game re-anchors itself, such as a crosshair that doubles as a mouse cursor, should go in `Exclude`.
- An `Unshift` widget is looked up once per container, so it must exist when the HUD first appears.
- At a 16:9 or narrower resolution the original anchors are written back, but clipping set by `Clip` stays on.

## Development

`tests/run.sh` runs the mod against a small fake UE4SS using the profiles in `profiles/` (needs Lua 5.4 or newer). It checks the logic only; the real check is a run in game. [SPEC.md](SPEC.md) describes the behaviour and what was learned from the reference games.
