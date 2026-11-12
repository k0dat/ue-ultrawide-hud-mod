# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

**UEUltrawideHUDMod** is a UE4SS Lua mod that moves Unreal Engine HUD widgets horizontally into a centred virtual aspect-ratio area (e.g. 16:9) on ultrawide displays.

[SPEC.md](SPEC.md) describes the behaviour and what was learned from the reference games. Read it before changing how the mod works, and update it in the same change when the behaviour changes. [README.md](README.md) is the user-facing guide; keep it in step too.

This is a deliberately small codebase. An earlier implementation was thrown away for being over-engineered, so the goal of any change is the least code that does the job and reads easily.

## Priorities

This is not a mission-critical application.

- Avoid excessive error checking. Assume the engine won't crash, and fail gracefully when something goes wrong.
- Minor graphical glitches are acceptable, such as a HUD element briefly popping when it first appears.
- Assume the profile (`.ini`) is valid. Don't add validation unless asked.
- Don't bring back removed features unless asked: hot reload, the debug overlay, the on/off toggle, configurable hotkeys, console commands.

## Lua style

- Target Lua 5.4. The dev machine runs 5.5, so don't use 5.5-only syntax.
- Prefer plain functions and tables. Use metatables or OOP only where there is real shared behaviour.
- Modules are `local M = {} ... return M`. No globals.
- Always use `local`. Cache lookups (`local insert = table.insert`) only in tight loops.
- Use `ipairs` for arrays, `pairs` for maps and `#t` for length.
- Return `nil, err` for expected failures. Use `error()` only for programmer errors.
- Use `or` for defaults (`opts = opts or {}`) rather than nested nil checks.
- No unnecessary wrappers, getters and setters, or utility layers.
- Keep functions short and prefer early returns. Aim for under about 30 lines; a longer function is probably doing two things, but don't split code just to hit a number.
- Comments say why, or record something learned in game. Don't narrate what the code does.

## Dependencies

- UE4SS stable release **4.0 or newer** and its Lua API. Don't use functions that only exist in newer experimental builds. Docs: https://docs.ue4ss.com/
- Use `UEHelpers` from UE4SS where it already provides something (e.g. `GetPlayerController`) instead of writing it again.
- `Scripts/ini_parser.lua` is third-party ([WickyPlays/Lua_INI_Parser](https://github.com/WickyPlays/Lua_INI_Parser)). Leave it unmodified.
- Ask before adding any new dependency.

## Layout

```
src/UEUltrawideHUDMod/     the mod folder, copied into ue4ss/Mods/
  enabled.txt
  Scripts/
    main.lua               profile loading, poll loop, Ctrl+Del hotkey
    remap.lua              viewport and anchors methods, Unshift
    dump.lua               widget tree dump
    ini_parser.lua         third-party
profiles/                  one .ini per tested game, plus Template.ini
tests/                     offline tests against a fake UE4SS
```

The mod loads the first `.ini` file in its own folder, so `src/UEUltrawideHUDMod/` must not contain one. Profiles live in `profiles/` and the user copies one in.

## How we work

The agent **can't run the games**. Development happens on Linux/WSL and the games run on Windows.

1. The agent changes the Lua scripts and runs the offline tests.
2. The user copies the mod into the game's `ue4ss/Mods` folder and runs the game.
3. The user reports back, pasting `UE4SS.log` or a widget dump where needed.

So:

- Run `tests/run.sh` before handing over a change. It runs the mod against `tests/mock_ue4ss.lua` using the profiles in `profiles/`.
- The tests only check logic against a model of the API. Don't say something works in game until the user has confirmed it.
- When an in-game run shows the UE4SS API behaves differently from the mock, fix the mock to match and note the finding in SPEC.md §8.
- Say so plainly when a change relies on a UE4SS function that hasn't been confirmed in game.
- Log lines use the `[UEUltrawideHUDMod]` prefix. Per-write detail belongs behind `Debug=true`.

## Hard constraints

- Move widgets on the **x-axis only**. Never change vertical position, offsets or scale.
- All UObject work happens on the game thread (`LoopInGameThreadWithDelay`, `ExecuteInGameThread`).
- Every anchor write is computed from the saved original anchors, never from current values, so repeated polls can't compound.

## Reference games

Both run UE 4.27.2. UE5 is untested.

| Game | UE4SS Mods folder |
|---|---|
| Echo Point Nova | `<Steam>\steamapps\common\Greylock\Greylock\Binaries\Win64\ue4ss\Mods` (internal project name "Greylock") |
| System Shock (2023 remake) | `<Steam>\steamapps\common\System Shock Remake\SystemShock\Binaries\Win64\ue4ss\Mods` |

## Git

Commit only when the user asks.
