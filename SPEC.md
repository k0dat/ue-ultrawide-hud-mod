# Ultrawide HUD Mod: Specification

A UE4SS Lua mod that moves UMG HUD widgets horizontally into a centred virtual aspect-ratio area on ultrawide screens. This is the second implementation. It favours short, readable code over completeness: small visual glitches are acceptable, and the config file is assumed to be valid.

## 1. Scope

- Move HUD elements on the **x-axis only**. Anchor Y values, offsets, sizes and z-order are never changed.
- One `.ini` profile per game. No changes are made to widgets that aren't listed in it.
- A widget dump on **Ctrl+Del** for finding widget and child names, as text and as an SVG of where each element sits.
- UE4SS stable release 4.0 or newer, Lua 5.4, UE4SS's `UEHelpers`, and the bundled `ini_parser.lua` ([WickyPlays/Lua_INI_Parser](https://github.com/WickyPlays/Lua_INI_Parser)). No other dependencies.

Out of scope: the mod's own hot reload (UE4SS's can be used while developing a profile, see §5), an on/off toggle, a debug overlay, configurable hotkeys, console commands, config validation, Canvas/`AHUD`-drawn HUDs, widgets nested inside other widgets, safe zones, multiplayer.

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

  where orig and new are the stretched child's anchors before and after. For a (0,1) container at ratio 0.5, an anchor of 0 becomes -0.5. The targets are searched for breadth-first below the container, not entering nested UserWidgets. The result is cached per container once every name has been found. Until then the search runs again on each poll, since a game can create a target after the HUD appears. A cached target that is no longer valid, or has no slot because it was removed from its parent, clears the cache.

## 5. Configuration

The profile is the first `.ini` file found in the mod folder (beside `enabled.txt`), read once at startup; the name doesn't matter, so a file from `profiles/` can be copied in as it is. Lua can't list a folder, so the mod finds it through UE4SS's `IterateGameDirectories()`, following the script's own path from `Binaries` down to the mod folder. With no profile the mod stops with an error. `[General]` holds `VirtualAspect` (`W:H` or a number, default `16:9`), `PollInterval` (seconds, default 1) and `Debug` (default `false`; logs each anchor write). Every other section is a widget, named after its class with or without `_C`, with the keys `Method`, `Clip`, `Exclude` and `Unshift`. Lists are comma-separated. Names of children match case-insensitively.

The parser needs `Key=value` with no spaces around `=` and has no inline comments.

UE4SS's own hot reload (`EnableHotReloadSystem = 1` in `UE4SS-settings.ini`, then Ctrl+R) can be used while developing a new profile, so `.ini` edits take effect without restarting the game. Use it for development only. A reload resets the saved original anchors, so a HUD that is already on screen is treated as unmoved and moved again, and it can end up in the wrong place. Reloading in the main menu and then loading a save avoids this, since the game builds a new HUD instance (confirmed in System Shock). A profile only counts as working once it has been checked after quitting and restarting the game.

## 6. Widget dump

Ctrl+Del writes `widgets_YYYYMMDD_HHMMSS.txt` to the mod folder and logs the path. A second dump in the same second gets `_2` added, and so on. After a header with the viewport size and virtual area, it lists each UserWidget in the viewport as an indented tree: class, name, visibility, and for children of a canvas their anchors and offsets. Nested UserWidgets are expanded in place.

Beside it goes `widgets_YYYYMMDD_HHMMSS.svg`, drawn in Slate units (viewport pixels divided by `UWidgetLayoutLibrary::GetViewportScale`) with the virtual area shaded. Each visible canvas child is a box labelled with its name at the top left, coloured by tree depth, and hovering anywhere in a box shows its line from the text dump. Boxes are drawn largest first, so the smallest box under the pointer gets the hover. Hidden and collapsed widgets and everything below them are left out. A nested UserWidget is drawn as one box without its contents, since a profile can't name anything inside it. Positions show the HUD as it is, after the mod has moved it. The dump also runs `shot showui` through `KismetSystemLibrary::ExecuteConsoleCommand` and draws that screenshot under the boxes. The engine saves it a frame later in `<Saved>/Screenshots/WindowsNoEditor/` as `ScreenShot00000.png` upwards. It numbers from a counter that starts at 0 each session and skips files already on disk, so the mod keeps the same counter and checks the folder from `GetProjectSavedDirectory`, made absolute with `ConvertToAbsolutePath`. Keeping its own counter matters when two dumps come a few frames apart, before the first PNG is on disk. The SVG shows the wrong screenshot or none if the engine's count drifts from the mod's: screenshots taken without the mod and deleted before the next dump, a Saved path with non-ASCII characters (Lua's `io.open` on Windows probably can't open it, so every number looks free), or a UE5 game, which saves to `Screenshots/Windows/` instead. The image is linked by `file:///` URL, with `%` and `#` in the path escaped.

The text dump is written and closed before any call that only the SVG needs (the box layout, `GetViewportScale` and the screenshot), so a failure there still leaves the text dump.

The boxes are computed, not read from the engine, because `FGeometry` isn't reflected (§8). Each canvas child is placed by the canvas layout rule: a point-anchored axis uses the offset as position, the alignment as pivot and `Offsets.Right`/`Bottom` as size, or `GetDesiredSize()` with auto-size; a stretched axis uses the offsets as margins. Every other widget is assumed to fill its parent, and a top-level widget to fill its viewport anchors. This is right for canvases inside overlays, borders and retainer boxes. Canvases inside boxes, scroll boxes or scale boxes, viewport offsets and render transforms are not modelled, and land in the wrong place.

## 7. Error handling

The dump runs inside one `pcall`, and the poll inside one for each widget instance, so a widget that fails doesn't stop the others. The error is logged with the `[UEUltrawideHUDMod]` prefix, on every poll while it keeps failing. UObjects are checked with `IsValid()` where the game is known to hand back dead or null ones (widget instances, tree roots, slots, cached Unshift targets), and not elsewhere.

## 8. Findings from the reference games

Both run UE 4.27.2. These come from in-game runs of the first implementation.

**UE4SS API**

- `slot:GetAnchors()` returns a plain Lua table (`.Minimum.X` and so on), and `SetAnchors` accepts one. Writes take effect straight away. Values are 32-bit floats, so compare with a tolerance.
- `FindAllOf` needs the generated class name with `_C` and returns nil when nothing matches.
- `debug.getinfo(1, "S").source` gives the script's absolute path.
- `GetCachedGeometry` is useless from Lua because `FGeometry` isn't reflected.
- Confirmed by the SVG dump in System Shock: `GetViewportScale`, `CanvasPanelSlot` `GetAlignment` and `GetAutoSize`, and `GetDesiredSize` work as called from Lua. `KismetSystemLibrary` `GetProjectSavedDirectory` returns an FString (`:ToString()`) that follows a game's moved Saved folder, `ConvertToAbsolutePath` takes a Lua string and returns an FString, `ExecuteConsoleCommand` runs `shot showui`, and the screenshot includes the HUD. `UEHelpers.GetKismetSystemLibrary()` returns the library. The mod's screenshot counter matched the engine's across a UE4SS hot reload, because the files already on disk are skipped.

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
