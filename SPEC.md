# Ultrawide HUD Mod: Specification

A UE4SS Lua mod that moves UMG HUD widgets horizontally into a centred virtual aspect-ratio area on ultrawide screens. This is the second implementation. It favours short, readable code over completeness: small visual glitches are acceptable, and the config file is assumed to be valid.

## 1. Scope

- Move HUD elements on the **x-axis only**. Anchor Y values, offsets, sizes and z-order are never changed.
- One `.ini` profile per game. No changes are made to widgets that aren't listed in it.
- A widget dump on **Ctrl+Del** for finding widget and child names.
- UE4SS experimental build, Lua 5.4, UE4SS's `UEHelpers`, and the bundled `ini_parser.lua` ([WickyPlays/Lua_INI_Parser](https://github.com/WickyPlays/Lua_INI_Parser)). No other dependencies.

Out of scope: hot reload, an on/off toggle, a debug overlay, configurable hotkeys, console commands, config validation, Canvas/`AHUD`-drawn HUDs, widgets nested inside other widgets, safe zones, multiplayer.

## 2. Virtual area

Let `S` be the viewport's width divided by its height and `V` the configured virtual aspect.

- `ratio = V / S` is the fraction of the screen width the virtual area covers. At 5120x1440 with `V` = 16:9 the ratio is 0.5 and the area spans x = 0.25 to 0.75.
- If `S <= V + 0.01`, the ratio is 1.
- Every anchor X value maps as `x' = 0.5 + (x - 0.5) * ratio`. A ratio of 1 therefore gives back the original anchors, which is how the HUD is restored when the resolution drops to 16:9.

The viewport size comes from `UWidgetLayoutLibrary::GetViewportSize`, with the player controller from `UEHelpers.GetPlayerController()` as the world context. If there is no controller or the size is 0x0, the poll does nothing.

## 3. Poll

One loop (`LoopInGameThreadWithDelay`, every `PollInterval` seconds) does all the work:

1. Read the viewport size and compute the ratio.
2. For each configured class, `FindAllOf("<Name>_C")`. Per-class lookups cost about 0.25 ms; `FindAllOf("UserWidget")` costs 3 to 7 ms and is only used by the dump.
3. For each valid instance that is in the viewport, apply the configured method.

Instances outside the viewport are skipped. Both reference games keep old HUD instances alive there after a respawn or a save load.

The first time the mod sees a slot or widget, it saves its anchors under the object's full name. Every later write is computed from those saved anchors and only happens when the current anchors differ from the result. This makes the poll safe to repeat, and it covers new HUD instances, widgets that lose their anchors when re-added to the viewport, and resolution changes, with no separate code for each.

The consequence is that the mod overrules the game: if the game re-anchors a moved slot, the next poll writes the mod's value again. Such children belong in `Exclude`.

## 4. Remap methods

### 4.1 Viewport (`Method=viewport`, default)

Maps the widget's viewport-slot anchors (`GetAnchorsInViewport` / `SetAnchorsInViewport`), so the whole widget shrinks into the virtual area. With `Clip=true` and a ratio below 1, the widget's root gets `ClipToBounds`, which hides elements parked off-screen for slide-in animations.

Use it for widgets that hold only HUD elements. Everything inside shrinks with the widget, including full-screen effects.

### 4.2 Anchors (`Method=anchors`)

Finds the first `CanvasPanel` in the widget's tree (breadth-first from `WidgetTree.RootWidget`, not entering nested UserWidgets) and maps the `CanvasPanelSlot` anchors of each direct child that isn't named in `Exclude`. Nested canvases are left alone, which avoids shifting anything twice.

- A point-anchored child keeps its offset, so an element 50 units from the left screen edge ends up 50 units inside the virtual left edge. Centred children don't move.
- A stretched child (Min.X differs from Max.X) shrinks to the virtual width. With `Clip=true` and a ratio below 1 it gets `ClipToBounds`.
- `Unshift` names widgets below a stretched child that the game positions in full-screen coordinates. Their own slot anchors get the inverse mapping, so they stay where they were on screen:

  ```
  a' = (orig.Min.X + a * (orig.Max.X - orig.Min.X) - new.Min.X) / (new.Max.X - new.Min.X)
  ```

  where orig and new are the stretched child's anchors before and after. For a (0,1) container at ratio 0.5, an anchor of 0 becomes -0.5. The search runs once per container and its result is cached.

## 5. Configuration

The profile is the first `.ini` file found in the mod folder (beside `enabled.txt`), read once at startup; the name doesn't matter, so a file from `profiles/` can be copied in as it is. Lua can't list a folder, so the mod finds it through UE4SS's `IterateGameDirectories()`, following the script's own path from `Binaries` down to the mod folder. With no profile the mod stops with an error. `[General]` holds `VirtualAspect` (`W:H` or a number, default `16:9`), `PollInterval` (seconds, default 1) and `Debug` (default `false`; logs each anchor write). Every other section is a widget, named after its class with or without `_C`, with the keys `Method`, `Clip`, `Exclude` and `Unshift`. Lists are comma-separated. Names of children match case-insensitively.

The parser needs `Key=value` with no spaces around `=` and has no inline comments.

## 6. Widget dump

Ctrl+Del writes `widgets_YYYYMMDD_HHMMSS.txt` to the mod folder and logs the path. After a header with the viewport size and virtual area, it lists each UserWidget in the viewport as an indented tree: class, name, visibility, and for children of a canvas their anchors and offsets. Nested UserWidgets are expanded in place.

## 7. Error handling

The poll and the dump each run inside one `pcall` that logs the error with the `[UEUltrawideHUDMod]` prefix. UObjects are checked with `IsValid()` where the game is known to hand back dead or null ones (widget instances, tree roots, slots, cached Unshift targets), and not elsewhere.

## 8. Findings from the reference games

Both run UE 4.27.2. These come from in-game runs of the first implementation.

**UE4SS API**

- `slot:GetAnchors()` returns a plain Lua table (`.Minimum.X` and so on), and `SetAnchors` accepts one. Writes take effect straight away. Values are 32-bit floats, so compare with a tolerance.
- `FindAllOf` needs the generated class name with `_C` and returns nil when nothing matches.
- `debug.getinfo(1, "S").source` gives the script's absolute path.
- `GetCachedGeometry` is useless from Lua because `FGeometry` isn't reflected.

**Echo Point Nova** (project name "Greylock")

- HUD widgets `WBP_HUMANHUD_C` and `WB_ShooterHUD_C` hold only HUD elements. The viewport method fits.
- The HUD is recreated on every respawn and level load, and the old instance stays alive outside the viewport.
- `WBP_LevelUpSwingOut` is parked off-screen and slides in by animating its slot's left offset. Only the viewport method with clipping shows it correctly.

**System Shock (2023)**

- One widget, `WIDGET_PlayerHUD_C`, holds the whole UI. Its root canvas `PANEL_Camera` has the HUD container `RETAINER_ScreenEffects` beside the pause menu, boot and crash screens and damage indicators, so it needs the anchors method with those excluded.
- The hardware panels inside the HUD container are parked off-screen, so the container must be clipped.
- The selection box `PANEL_Brackets` is positioned in full-screen coordinates and needs `Unshift`.
- The crosshair `WIDGET_CrosshairCursor` is re-anchored by the game on every mode switch and must be excluded.
- Loading a save creates a new HUD and leaves the old one alive outside the viewport. Viewport-slot anchors are lost when a widget is re-added to the viewport.
- Cyberspace uses a separate class, `WIDGET_CyberspaceHUD_C`.
- Cosmetic and accepted: the selection box slides in from the left virtual edge when it first appears, and the crosshair slides in from the right when the inventory closes.
