-- A small fake of the UE4SS Lua API: just enough UMG for the mod to run outside a game.
-- It models what the in-game spikes found: anchors are plain tables stored as 32-bit floats,
-- FindAllOf returns nil when nothing matches, and null object properties read as nil.

local M = {}

local classes = {}

local function defineClass(name, super)
    local class = { name = name, super = classes[super] }
    function class:GetFName() return { ToString = function() return name end } end
    classes[name] = class
    return class
end

defineClass("Object")
defineClass("Widget", "Object")
defineClass("Image", "Widget")
defineClass("PanelWidget", "Widget")
defineClass("CanvasPanel", "PanelWidget")
defineClass("RetainerBox", "PanelWidget")
defineClass("Overlay", "PanelWidget")
defineClass("UserWidget", "Widget")
defineClass("CanvasPanelSlot", "Object")

local function float32(x) return (string.unpack("f", string.pack("f", x))) end

local function copyAnchors(a)
    return {
        Minimum = { X = float32(a.Minimum.X), Y = float32(a.Minimum.Y) },
        Maximum = { X = float32(a.Maximum.X), Y = float32(a.Maximum.Y) },
    }
end

function M.anchors(minX, minY, maxX, maxY)
    return { Minimum = { X = minX, Y = minY }, Maximum = { X = maxX, Y = maxY } }
end

-- Every fake UObject shares these methods, whatever its class.
local Object = {}
Object.__index = Object

function Object:IsValid() return not self.destroyed end
function Object:GetFullName() return string.format("%s /Engine/Transient.%s_%d", self.class.name, self.name, self.id) end
function Object:GetFName() return { ToString = function() return self.name end } end
function Object:GetClass() return self.class end
function Object:GetVisibility() return 0 end
function Object:SetClipping(value) self.Clipping = value end
function Object:GetChildrenCount() return #self.children end
function Object:GetChildAt(i) return self.children[i + 1] end
function Object:GetAnchors() return copyAnchors(self.anchors) end
function Object:SetAnchors(a) self.anchors = copyAnchors(a) end
function Object:GetOffsets() return self.offsets end
function Object:IsInViewport() return self.inViewport end
function Object:GetAnchorsInViewport() return copyAnchors(self.anchors) end
function Object:SetAnchorsInViewport(a) self.anchors = copyAnchors(a) end

function Object:IsA(class)
    local c = self.class
    while c do
        if c == class then return true end
        c = c.super
    end
    return false
end

local objects, nextId

local function newObject(className, name, fields)
    local obj = setmetatable(fields or {}, Object)
    obj.class, obj.name, obj.id = assert(classes[className], className), name, nextId
    nextId = nextId + 1
    objects[#objects + 1] = obj
    return obj
end

-- A widget; `parent` is a panel. Children of a canvas get a CanvasPanelSlot with `anchors`.
function M.widget(className, name, parent, anchors)
    local widget = newObject(className, name, { children = {}, Clipping = 0 })
    if not parent then return widget end
    parent.children[#parent.children + 1] = widget
    if parent:IsA(classes.CanvasPanel) then
        widget.Slot = newObject("CanvasPanelSlot", name .. "_Slot",
            { anchors = copyAnchors(anchors), offsets = { Left = 0, Top = 0, Right = 100, Bottom = 50 } })
    end
    return widget
end

-- A top-level UserWidget of a blueprint class, added to the viewport.
function M.userWidget(className, root)
    if not classes[className] then defineClass(className, "UserWidget") end
    return newObject(className, className:gsub("_C$", ""),
        { WidgetTree = { RootWidget = root, IsValid = function() return true end },
          inViewport = true, anchors = M.anchors(0, 0, 1, 1) })
end

function M.defineClass(name, super) return defineClass(name, super) end

function M.tick()
    for _, fn in ipairs(M.loops) do fn() end
end

function M.pressKey()
    for _, fn in ipairs(M.keybinds) do fn() end
end

-- A folder as IterateGameDirectories() presents it: subfolders by name, files under __files.
local function directory(path)
    return setmetatable({}, { __index = function(_, key)
        if key ~= "__files" then return directory(path .. "/" .. key) end
        local files = {}
        local listing = io.popen('ls -p "' .. path .. '" | grep -v /')
        for name in listing:lines() do files[#files + 1] = { __name = name } end
        listing:close()
        return files
    end })
end

-- Clears the fake world and installs the UE4SS globals. `gameDir` holds the "Game" project folder.
function M.reset(gameDir)
    objects, nextId = {}, 0
    M.viewport = { X = 5120, Y = 1440 }
    M.loops, M.keybinds, M.log = {}, {}, {}

    local controller = newObject("Object", "PlayerController")
    local layoutLibrary = { GetViewportSize = function() return M.viewport end }
    package.loaded.UEHelpers = { GetPlayerController = function() return controller end }

    function StaticFindObject(path)
        if path:find("Default__WidgetLayoutLibrary") then return layoutLibrary end
        return classes[path:match("%.([%w_]+)$")]
    end

    function FindAllOf(className)
        local found = {}
        for _, obj in ipairs(objects) do
            if classes[className] and obj:IsA(classes[className]) and obj:IsValid() then found[#found + 1] = obj end
        end
        return #found > 0 and found or nil
    end

    function IterateGameDirectories() return directory(gameDir) end

    Key = { DEL = "DEL" }
    ModifierKey = { CONTROL = "CONTROL" }
    function RegisterKeyBind(_, _, fn) M.keybinds[#M.keybinds + 1] = fn end
    function LoopInGameThreadWithDelay(_, fn) M.loops[#M.loops + 1] = fn end
    function ExecuteInGameThread(fn) fn() end
    function print(text) M.log[#M.log + 1] = text end
end

return M
