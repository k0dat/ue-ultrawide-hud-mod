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

-- Whether `svg` has a <rect> with these attribute values, in any order.
local function hasRect(svg, attrs)
    for tag in svg:gmatch("<rect[^>]*>") do
        local all = true
        for key, value in pairs(attrs) do
            all = all and tag:find(string.format(' %s="%s"', key, value), 1, true) ~= nil
        end
        if all then return true end
    end
    return false
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("a")
    file:close()
    return text
end

-- Called before each restart of the mod, which clears the log, and at the end.
local function checkNoErrors()
    for _, line in ipairs(mock.log or {}) do
        check("no errors logged: " .. line, not line:find("error", 1, true))
    end
end

-- Starts the mod in an empty fake world with `profileText` as the only .ini file in the mod folder.
local profilePath
local function startMod(fileName, profileText)
    if profilePath then os.remove(profilePath) end
    profilePath = modDir .. "/" .. fileName
    local file = assert(io.open(profilePath, "w"))
    file:write(profileText)
    file:close()
    for _, name in ipairs({ "remap", "dump", "svg", "ini_parser" }) do package.loaded[name] = nil end
    checkNoErrors()
    mock.reset(gameDir)
    dofile(modDir .. "/Scripts/main.lua")
end

local function echoPointNovaHud()
    local root = mock.widget("Overlay", "Root")
    local canvas = mock.widget("CanvasPanel", "MainCanvas", root)
    local health = mock.widget("Image", "Health", canvas, mock.anchors(0, 1, 0, 1))
    health.Slot.offsets = { Left = 0, Top = -50, Right = 100, Bottom = 50 }
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

local mainCanvas = hud.WidgetTree.RootWidget.children[1]
local hidden = mock.widget("CanvasPanel", "Hidden", mainCanvas, mock.anchors(0, 0, 1, 1))
hidden.visibility = 2
mock.widget("Image", "HiddenIcon", hidden, mock.anchors(0, 0, 0, 0))
mock.widget("Image", "Collapsed", mainCanvas, mock.anchors(0, 0, 0, 0)).visibility = 1
mock.widget("Image", "Marker", mainCanvas, mock.anchors(0.5, 0, 0.5, 0)).Slot.alignment = { X = 0.5, Y = 0 }
mock.defineClass("WBP_Slot_C", "UserWidget")
local nested = mock.widget("WBP_Slot_C", "Slot", mainCanvas, mock.anchors(0, 0, 0, 0))
local nestedCanvas = mock.widget("CanvasPanel", "SlotCanvas")
nested.WidgetTree = { RootWidget = nestedCanvas, IsValid = function() return true end }
mock.widget("Image", "SlotIcon", nestedCanvas, mock.anchors(0, 0, 0, 0))
mock.scale = 2 -- 5120x1440 pixels is 2560x720 Slate units
local shotDir = gameDir .. "/Game/Saved/Screenshots/WindowsNoEditor/"
os.execute('mkdir -p "' .. shotDir .. '" && touch "' .. shotDir .. 'ScreenShot00000.png"')

-- Base names of the dumps logged so far.
local function dumpBases()
    local bases = {}
    for base in table.concat(mock.log):gmatch("dump written to ([^\n]+)%.txt") do bases[#bases + 1] = base end
    return bases
end

mock.pressKey()
local dumpBase = dumpBases()[1]
check("dump: file written", dumpBase ~= nil)
local dumpText = dumpBase and readFile(dumpBase .. ".txt") or ""
local svgText = dumpBase and readFile(dumpBase .. ".svg") or ""
check("dump: header has the viewport", dumpText:find("Viewport 5120x1440", 1, true) ~= nil)
check("dump: top-level widget listed by class", dumpText:find('\nWBP_HUMANHUD_C "WBP_HUMANHUD" Visible', 1, true) ~= nil)
check("dump: child listed with its anchors",
    dumpText:find('    Image "Health" Visible  anchors (0,1)-(0,1)  offsets (0,-50,100,50)', 1, true) ~= nil)
check("dump: stale instance not listed", select(2, dumpText:gsub("WBP_HUMANHUD_C", "")) == 1)
check("dump: hidden and collapsed children listed", dumpText:find('CanvasPanel "Hidden" Hidden', 1, true) ~= nil
    and dumpText:find('Image "HiddenIcon" Visible', 1, true) ~= nil and dumpText:find('Image "Collapsed" Collapsed', 1, true) ~= nil)
check("svg: virtual area drawn in Slate units", hasRect(svgText, { x = 640, width = 1280, height = 720 }))
check("svg: child boxed inside the moved widget",
    hasRect(svgText, { x = 640, y = 670, width = 100, height = 50 }))
check("svg: point-anchored child placed by its alignment", hasRect(svgText, { x = 1230, y = 0, width = 100, height = 50 }))
check("svg: whole box takes the hover", hasRect(svgText, { x = 640, y = 670, ["pointer-events"] = "all" }))
check("svg: child labelled", svgText:find('>Health</text>', 1, true) ~= nil)
check("svg: tooltip escaped", svgText:find('<title>Image &quot;Health&quot; Visible', 1, true) ~= nil)
check("svg: hidden subtree and collapsed child not drawn", svgText:find(">Hidden<", 1, true) == nil
    and svgText:find(">HiddenIcon<", 1, true) == nil and svgText:find(">Collapsed<", 1, true) == nil)
check("svg: nested UserWidget drawn as one box",
    svgText:find(">Slot</text>", 1, true) ~= nil and svgText:find(">SlotIcon<", 1, true) == nil)
check("dump: nested UserWidget expanded in the text", dumpText:find('Image "SlotIcon"', 1, true) ~= nil)
check("screenshot: taken with the HUD", mock.commands[1] == "shot showui")
check("screenshot: first free number drawn under the boxes",
    svgText:find('href="file:///' .. shotDir .. 'ScreenShot00001.png"', 1, true) ~= nil)

mock.pressKey() -- the first screenshot isn't on disk yet, as when Ctrl+Del is pressed twice quickly
local second = dumpBases()[2]
check("dump: a second dump gets its own files", second ~= nil and second ~= dumpBase)
check("screenshot: a second dump predicts the next number",
    readFile(second .. ".svg"):find("ScreenShot00002.png", 1, true) ~= nil)

checkNoErrors()
mock.scale = nil -- any failure in the SVG part
mock.pressKey()
check("dump: text written when the SVG part fails", #dumpBases() == 3 and readFile(dumpBases()[3] .. ".txt"):find("Health", 1, true) ~= nil)
check("dump: SVG failure logged", table.concat(mock.log):find("error:", 1, true) ~= nil)
mock.log = {} -- that error was expected

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

ss.crosshair.Slot.alignment, ss.crosshair.Slot.autoSize, ss.crosshair.desiredSize = { X = 0.5, Y = 0.5 }, true, { X = 40, Y = 30 }
mock.pressKey()
svgText = readFile(dumpBases()[1] .. ".svg")
check("svg: stretched child uses its offsets as margins",
    hasRect(svgText, { x = 1280, y = 0, width = 2460, height = 1390 }))
check("svg: auto-sized child centred on its anchor",
    hasRect(svgText, { x = 2540, y = 705, width = 40, height = 30 }))
check("svg: smaller box drawn over a later, larger sibling",
    (svgText:find(">PANEL_Brackets<", 1, true) or 0) > (svgText:find(">WIDGET_MainMenu_InGame<", 1, true) or math.huge))

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

-- The game destroys the selection box and creates a new one a few polls later.
local gameHud = ss.retainer.children[1]
ss.brackets.destroyed = true
mock.tick()
mock.tick()
ss.brackets = mock.widget("Image", "PANEL_Brackets", gameHud, mock.anchors(0, 0, 0, 0))
mock.tick()
check("anchors: Unshift target found when it appears late", hasX(ss.brackets.Slot, -0.5, -0.5))

-- Removed from its parent: no slot, but still valid until garbage collection.
table.remove(gameHud.children, #gameHud.children)
ss.brackets.Slot = nil
ss.brackets = mock.widget("Image", "PANEL_Brackets", gameHud, mock.anchors(0, 0, 0, 0))
mock.tick()
mock.tick()
check("anchors: Unshift target found again after it is detached", hasX(ss.brackets.Slot, -0.5, -0.5))

checkNoErrors()
ss.retainer.Slot.GetAnchors = function() error("not a canvas slot") end
timer.Slot.anchors = mock.anchors(1, 0, 1, 0)
mock.tick()
check("errors: a failing widget is logged", table.concat(mock.log):find("not a canvas slot", 1, true) ~= nil)
check("errors: later widgets still moved", hasX(timer.Slot, 0.75, 0.75))
ss.retainer.Slot.GetAnchors = nil
mock.log = {}

------------------------------------------------------------------------
-- Config options
------------------------------------------------------------------------

startMod("Custom.INI", "[General]\nVirtualAspect=21:9\nDebug=true\n\n[WBP_HUMANHUD_C]\nClip=false\n")
hud, root = echoPointNovaHud()
mock.tick()
check("config: 21:9 area on a 32:9 screen, method defaults to viewport", hasX(hud, 0.5 - 0.328125, 0.5 + 0.328125))
check("config: Clip=false leaves clipping alone", root.Clipping == 0)
check("config: Debug=true logs writes", table.concat(mock.log):find("anchors x 0..1 -> 0.171875..0.828125", 1, true) ~= nil)

------------------------------------------------------------------------
-- SVG writer
------------------------------------------------------------------------

local Svg = require("svg")
check("svg writer: sorted, escaped attributes and text",
    Svg.element("text", { y = 1.5, x = 'a"b' }, "<T&>") == '<text x="a&quot;b" y="1.5">&lt;T&amp;&gt;</text>')
check("svg writer: no content closes the tag", Svg.element("rect", { width = 10 }) == '<rect width="10"/>')
check("svg writer: child elements not escaped",
    Svg.element("g", nil, { Svg.element("title", nil, "a"), "<b/>" }) == "<g><title>a</title>\n<b/></g>")

local urlTest = modDir .. "/url_test.svg"
require("dump").writeSvg(urlTest, { width = 10, height = 10, ratio = 1, screenshot = "C:/Games #2/100%/s.png" }, {})
check("svg: screenshot path made URL-safe",
    readFile(urlTest):find('href="file:///C:/Games %232/100%25/s.png"', 1, true) ~= nil)
os.remove(urlTest)

checkNoErrors()

realPrint(failures == 0 and "all tests passed" or (failures .. " test(s) failed"))
os.exit(failures == 0)
