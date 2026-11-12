# Compatibility

Games with a ready-made profile in [`profiles/`](profiles/). All were tested with UE4SS 4.0.

**Path** is where UE4SS is installed, alongside the game's Unreal Engine binary, relative to the game's install folder (for Steam, `<Steam>\steamapps\common\`). The mod then goes in `ue4ss\Mods\` inside that folder. See the [README](README.md) for the full install steps and the known limitations that apply to every game.

| Title | Profile | Path | Notes | Other fixes |
|---|---|---|---|---|
| Echo Point Nova | [`EchoPointNova.ini`](profiles/EchoPointNova.ini) | `Greylock\Greylock\Binaries\Win64` | Needs more thorough testing. | [FOV aspect ratio fix](other-fixes/EchoPointNova.md) |
| Redout: Enhanced Edition | [`Redout.ini`](profiles/Redout.ini) | `Redout\redout\Binaries\Win64` | Needs more thorough testing. | |
| System Shock (2023 remake) | [`SystemShock.ini`](profiles/SystemShock.ini) | `System Shock Remake\SystemShock\Binaries\Win64` | Needs more thorough testing. Covers the station HUD and the cyberspace HUD. Two cosmetic glitches: the selection box slides in from the left edge of the 16:9 area when it first appears, and the crosshair slides in from the right when the inventory closes. | |

## Adding a game

Add the profile to `profiles/` and a row here, keeping the table in alphabetical order. In Notes, list any known glitches and say so if the profile needs more thorough testing. Put the steps for any other fix in a file named after the game in `other-fixes/` and link to it from the table.
