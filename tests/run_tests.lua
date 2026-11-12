-- Offline tests: run the mod against the fake UE4SS with the example configs.
-- Usage: lua tests/run_tests.lua <repo> <scratch game folder with the mod installed>   (see tests/run.sh)

local repo, gameDir = arg[1], arg[2]
local modDir = gameDir .. "/Game/Binaries/Win64/ue4ss/Mods/UEUltrawideHUDMod"
package.path = modDir .. "/Scripts/?.lua;" .. repo .. "/tests/?.lua;" .. package.path

local mock = require("mock_ue4ss")
local realPrint = print
local failures = 0

local function check(what, ok)
    if not ok then
        failures = failures + 1
        realPrint("FAIL: " .. what)
    end
end

local function hasX(obj, minX, maxX)
    local a = obj.anchors
    return math.abs(a.Minimum.X - minX) < 1e-4 and math.abs(a.Maximum.X - maxX) < 1e-4
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("a")
    file:close()
    return text
end

-- Starts the mod in an empty fake world with `profileText` as the only .ini file in the mod folder.
local profilePath
local function startMod(fileName, profileText)
    if profilePath then os.remove(profilePath) end
    profilePath = modDir .. "/" .. fileName
    local file = assert(io.open(profilePath, "w"))
    file:write(profileText)
    file:close()
    for _, name in ipairs({ "remap", "dump", "ini_parser" }) do package.loaded[name] = nil end
    mock.reset(gameDir)
    dofile(modDir .. "/Scripts/main.lua")
end

local function echoPointNovaHud()
    local root = mock.widget("Overlay", "Root")
    local canvas = mock.widget("CanvasPanel", "MainCanvas", root)
    local health = mock.widget("Image", "Health", canvas, mock.anchors(0, 1, 0, 1))
    return mock.userWidget("WBP_HUMANHUD_C", root), root, health
end

local function systemShockHud()
    mock.defineClass("CameraPanelWidget", "CanvasPanel")
    local root = mock.widget("CameraPanelWidget", "PANEL_Camera")
    local full, centre = mock.anchors(0, 0, 1, 1), mock.anchors(0.5, 0.5, 0.5, 0.5)
    local hud = {
        damage = mock.widget("Image", "PANEL_DamageIndicators", root, full),
        retainer = mock.widget("RetainerBox", "RETAINER_ScreenEffects", root, full),
        menu = mock.widget("Image", "WIDGET_MainMenu_InGame", root, full),
        crosshair = mock.widget("Image", "WIDGET_CrosshairCursor", root, centre),
    }
    local gameHud = mock.widget("CanvasPanel", "PANEL_GameHUD", hud.retainer)
    hud.brackets = mock.widget("Image", "PANEL_Brackets", gameHud, mock.anchors(0, 0, 0, 0))
    hud.hardware = mock.widget("Image", "PANEL_LeftHardware", gameHud, mock.anchors(0, 1, 0, 1))
    hud.widget = mock.userWidget("WIDGET_PlayerHUD_C", root)
    return hud
end

------------------------------------------------------------------------
-- Viewport method (Echo Point Nova)
------------------------------------------------------------------------

startMod("EchoPointNova.ini", readFile(repo .. "/profiles/EchoPointNova.ini"))
check("profile: found without being named config.ini", table.concat(mock.log):find("loaded .*EchoPointNova%.ini") ~= nil)
local hud, root, health = echoPointNovaHud()

mock.tick()
check("viewport: 32:9 shrinks the widget to the middle half", hasX(hud, 0.25, 0.75))
check("viewport: root is clipped", root.Clipping == 1)
check("viewport: children are not moved", hasX(health.Slot, 0, 0))

mock.tick()
check("viewport: a second poll does not compound", hasX(hud, 0.25, 0.75))

hud.anchors = mock.anchors(0, 0, 1, 1) -- the game re-added the widget to the viewport
mock.tick()
check("viewport: re-applied after the game resets it", hasX(hud, 0.25, 0.75))

mock.viewport = { X = 3440, Y = 1440 }
mock.tick()
check("viewport: follows a resolution change", hasX(hud, 0.5 - 0.372093, 0.5 + 0.372093))

mock.viewport = { X = 2560, Y = 1440 }
mock.tick()
check("viewport: restored at 16:9", hasX(hud, 0, 1))

local stale = echoPointNovaHud()
stale.inViewport = false
mock.viewport = { X = 0, Y = 0 }
mock.tick()
mock.viewport = { X = 5120, Y = 1440 }
mock.tick()
check("viewport: instances outside the viewport are left alone", hasX(stale, 0, 1))
check("viewport: applied again after a 0x0 viewport", hasX(hud, 0.25, 0.75))

------------------------------------------------------------------------
-- Dump
------------------------------------------------------------------------

mock.pressKey()
local dumpPath = table.concat(mock.log):match("dump written to ([^\n]+)")
check("dump: file written", dumpPath ~= nil)
local dumpText = dumpPath and readFile(dumpPath) or ""
check("dump: header has the viewport", dumpText:find("Viewport 5120x1440", 1, true) ~= nil)
check("dump: top-level widget listed by class", dumpText:find('\nWBP_HUMANHUD_C "WBP_HUMANHUD" Visible', 1, true) ~= nil)
check("dump: child listed with its anchors",
    dumpText:find('    Image "Health" Visible  anchors (0,1)-(0,1)  offsets (0,0,100,50)', 1, true) ~= nil)
check("dump: stale instance not listed", select(2, dumpText:gsub("WBP_HUMANHUD_C", "")) == 1)

------------------------------------------------------------------------
-- Anchors method (System Shock)
------------------------------------------------------------------------

startMod("SystemShock.ini", readFile(repo .. "/profiles/SystemShock.ini"))
local ss = systemShockHud()

mock.tick()
mock.tick()
check("anchors: HUD container moved into the virtual area", hasX(ss.retainer.Slot, 0.25, 0.75))
check("anchors: HUD container clipped", ss.retainer.Clipping == 1)
check("anchors: excluded children untouched", hasX(ss.damage.Slot, 0, 1) and hasX(ss.menu.Slot, 0, 1))
check("anchors: widget's viewport slot untouched", hasX(ss.widget, 0, 1))
check("anchors: nested canvas children untouched", hasX(ss.hardware.Slot, 0, 0))
check("anchors: selection box unshifted", hasX(ss.brackets.Slot, -0.5, -0.5))
check("anchors: Y untouched", ss.retainer.Slot.anchors.Maximum.Y == 1)

mock.viewport = { X = 1920, Y = 1080 }
mock.tick()
check("anchors: restored at 16:9", hasX(ss.retainer.Slot, 0, 1) and hasX(ss.brackets.Slot, 0, 0))

-- Cyberspace HUD: a second configured class with edge-anchored children on the root canvas.
mock.viewport = { X = 5120, Y = 1440 }
local cyberRoot = mock.widget("CanvasPanel", "Root")
local timer = mock.widget("Image", "TEXT_SecurityTimer", cyberRoot, mock.anchors(1, 0, 1, 0))
local ring = mock.widget("Image", "WIDGET_CyberspaceOccularRing", cyberRoot, mock.anchors(0, 0, 1, 1))
mock.userWidget("WIDGET_CyberspaceHUD_C", cyberRoot)
mock.tick()
check("anchors: right-anchored child moves to the virtual edge", hasX(timer.Slot, 0.75, 0.75))
check("anchors: point-anchored child is not clipped", timer.Clipping == 0)
check("anchors: exclude is per widget", hasX(ring.Slot, 0, 1))

------------------------------------------------------------------------
-- Config options
------------------------------------------------------------------------

startMod("Custom.INI", "[General]\nVirtualAspect=21:9\nDebug=true\n\n[WBP_HUMANHUD_C]\nClip=false\n")
hud, root = echoPointNovaHud()
mock.tick()
check("config: 21:9 area on a 32:9 screen, method defaults to viewport", hasX(hud, 0.5 - 0.328125, 0.5 + 0.328125))
check("config: Clip=false leaves clipping alone", root.Clipping == 0)
check("config: Debug=true logs writes", table.concat(mock.log):find("anchors x 0..1 -> 0.171875..0.828125", 1, true) ~= nil)

for _, line in ipairs(mock.log) do
    check("no errors logged: " .. line, not line:find("error", 1, true))
end

realPrint(failures == 0 and "all tests passed" or (failures .. " test(s) failed"))
os.exit(failures == 0)
