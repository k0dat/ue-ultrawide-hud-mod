-- UEUltrawideHUDMod: moves UMG HUD widgets into a centred virtual aspect-ratio area (e.g. 16:9) on
-- ultrawide screens. Configured by the .ini profile in the mod folder; Ctrl+Del writes a widget dump
-- there too.

local UEHelpers = require("UEHelpers")
local Ini = require("ini_parser")
local Remap = require("remap")
local Dump = require("dump")

local MOD_DIR = debug.getinfo(1, "S").source:match("@?(.*[/\\])") .. "../"

local function log(fmt, ...)
    print(string.format("[UEUltrawideHUDMod] " .. fmt .. "\n", ...))
end

-- "A, B" -> { "a", "b" }
local function splitNames(value)
    local names = {}
    for name in (value or ""):gmatch("[^,%s]+") do names[#names + 1] = name:lower() end
    return names
end

-- "16:9" or a plain number
local function parseAspect(value)
    if type(value) == "number" then return value end
    local w, h = value:match("([%d.]+)%s*:%s*([%d.]+)")
    return tonumber(w) / tonumber(h)
end

local function widgetConfig(name, section)
    local cfg = {
        class = name:gsub("_C$", "") .. "_C", -- FindAllOf needs the generated class name
        method = section.Method or "viewport",
        clip = section.Clip ~= false,
        unshift = splitNames(section.Unshift),
        exclude = {},
    }
    for _, child in ipairs(splitNames(section.Exclude)) do cfg.exclude[child] = true end
    return cfg
end

local function loadConfig(path)
    local ini = Ini.read(path)
    local general = ini.General or {}
    local config = {
        aspect = parseAspect(general.VirtualAspect or "16:9"),
        pollMs = math.floor((general.PollInterval or 1) * 1000),
        widgets = {},
    }
    Remap.verbose = general.Debug == true
    for _, item in ipairs(ini.__order) do
        if item.type == "section" and item.section ~= "General" then
            config.widgets[#config.widgets + 1] = widgetConfig(item.section, ini[item.section])
        end
    end
    return config
end

-- Path of the first .ini file in the mod folder. Lua can't list a folder, so this walks UE4SS's
-- directory tree, which starts at the game folder, along this script's path from "Binaries" down.
local function findProfile()
    local dir = IterateGameDirectories().Game
    for name in MOD_DIR:match("([Bb]inaries[/\\].*)[Ss]cripts[/\\]"):gmatch("[^/\\]+") do
        dir = dir[name]
    end
    for _, file in pairs(dir.__files) do
        if file.__name:lower():match("%.ini$") then return MOD_DIR .. file.__name end
    end
end

local profile = assert(findProfile(), "[UEUltrawideHUDMod] no .ini profile in the mod folder")
local config = loadConfig(profile)

-- Viewport size in pixels, or nil while there is no world or the size is 0x0 (startup, loading).
local function viewportSize()
    local controller = UEHelpers.GetPlayerController()
    if not controller:IsValid() then return nil end
    local size = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(controller)
    if size.X <= 0 or size.Y <= 0 then return nil end
    return size
end

-- Fraction of the screen width the virtual area covers. 1 means the screen is no wider than the
-- virtual aspect, so nothing moves.
local function widthRatio(size)
    local screenAspect = size.X / size.Y
    if screenAspect <= config.aspect + 0.01 then return 1 end
    return config.aspect / screenAspect
end

local function poll()
    local size = viewportSize()
    if not size then return end
    local ratio = widthRatio(size)
    for _, cfg in ipairs(config.widgets) do
        for _, widget in ipairs(FindAllOf(cfg.class) or {}) do
            -- Games keep old HUD instances alive outside the viewport; leave those alone.
            if widget:IsValid() and widget:IsInViewport() then
                Remap.apply(widget, cfg, ratio)
            end
        end
    end
end

local function dump()
    local size = viewportSize()
    if not size then return log("dump: no viewport yet") end
    local header = string.format(
        "UEUltrawideHUDMod widget dump, %s\nViewport %.0fx%.0f, virtual aspect %.4f, virtual area is %.1f%% of the width\n"
            .. "Top-level widgets in the viewport. A profile section is named after the widget's class (first word).",
        os.date("%Y-%m-%d %H:%M:%S"), size.X, size.Y, config.aspect, widthRatio(size) * 100)
    local path, err = Dump.write(MOD_DIR .. os.date("widgets_%Y%m%d_%H%M%S.txt"), header)
    log(path and ("dump written to " .. path) or ("dump failed: " .. err))
end

-- Reports an error from a callback instead of letting it escape into UE4SS.
local function guarded(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then log("error: %s", err) end
    end
end

LoopInGameThreadWithDelay(config.pollMs, guarded(poll))

RegisterKeyBind(Key.DEL, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(guarded(dump))
end)

log("loaded %s: virtual aspect %.4f, %d widget(s) configured, Ctrl+Del dumps widgets", profile, config.aspect, #config.widgets)
