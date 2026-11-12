-- Moves HUD widgets into the centred virtual area by scaling their anchor X values towards 0.5.
-- Anchor Y values, offsets and sizes are never touched.

local M = {}

M.verbose = false

local CLIP_TO_BOUNDS = 1 -- EWidgetClipping::ClipToBounds
local EPSILON = 1e-4     -- anchors are 32-bit floats, so they don't read back exactly

-- Anchors the game gave each slot or widget, keyed by full object name and saved the first time we
-- see it. Every write is computed from these, so repeated polls never compound.
local originals = {}
local unshiftTargets = {} -- [container full name] = widgets named in cfg.unshift, searched once
local classes = {}

local function trace(fmt, ...)
    if M.verbose then print(string.format("[UEUltrawideHUDMod] " .. fmt .. "\n", ...)) end
end

function M.isValid(obj)
    return obj ~= nil and obj:IsValid()
end

function M.isA(obj, className)
    classes[className] = classes[className] or StaticFindObject("/Script/UMG." .. className)
    return obj:IsA(classes[className])
end

function M.rootOf(userWidget)
    local tree = userWidget.WidgetTree
    if not M.isValid(tree) then return nil end
    return M.isValid(tree.RootWidget) and tree.RootWidget or nil
end

function M.childrenOf(widget)
    local children = {}
    if not M.isA(widget, "PanelWidget") then return children end
    for i = 0, widget:GetChildrenCount() - 1 do
        local child = widget:GetChildAt(i)
        if M.isValid(child) then children[#children + 1] = child end
    end
    return children
end

-- Breadth-first search from `start` (inclusive). Nested UserWidgets are not entered.
local function find(start, matches)
    local queue = { start }
    for _, widget in ipairs(queue) do
        if matches(widget) then return widget end
        for _, child in ipairs(M.childrenOf(widget)) do queue[#queue + 1] = child end
    end
end

-- Returns the anchors `obj` had originally, the anchors it should have now, and whether they
-- differ from `current`.
local function mapAnchors(obj, current, mapX)
    local key = obj:GetFullName()
    local orig = originals[key] or current
    originals[key] = orig
    local new = {
        Minimum = { X = mapX(orig.Minimum.X), Y = current.Minimum.Y },
        Maximum = { X = mapX(orig.Maximum.X), Y = current.Maximum.Y },
    }
    local changed = math.abs(new.Minimum.X - current.Minimum.X) > EPSILON
        or math.abs(new.Maximum.X - current.Maximum.X) > EPSILON
    if changed then
        trace("%s: anchors x %g..%g -> %g..%g", key, current.Minimum.X, current.Maximum.X, new.Minimum.X, new.Maximum.X)
    end
    return orig, new, changed
end

local function clipToBounds(widget)
    if widget.Clipping ~= CLIP_TO_BOUNDS then widget:SetClipping(CLIP_TO_BOUNDS) end
end

-- Viewport method: shrink the whole UserWidget through its viewport slot.
local function remapViewport(widget, scaleX, clip)
    local _, anchors, changed = mapAnchors(widget, widget:GetAnchorsInViewport(), scaleX)
    if changed then widget:SetAnchorsInViewport(anchors) end
    local root = M.rootOf(widget)
    if clip and root then clipToBounds(root) end
end

local function unshiftWidgets(container, names)
    local key = container:GetFullName()
    if not unshiftTargets[key] then
        local found = {}
        for _, wanted in ipairs(names) do
            found[#found + 1] = find(container, function(w) return w:GetFName():ToString():lower() == wanted end)
        end
        unshiftTargets[key] = found
    end
    return unshiftTargets[key]
end

-- `widget` is positioned by the game in full-screen coordinates, but sits inside a container that
-- went from `orig` to `new` anchors. Map its anchors the other way so it stays put on screen.
local function unshift(widget, orig, new)
    local slot = widget.Slot
    local function mapX(x)
        local screenX = orig.Minimum.X + x * (orig.Maximum.X - orig.Minimum.X)
        return (screenX - new.Minimum.X) / (new.Maximum.X - new.Minimum.X)
    end
    local _, anchors, changed = mapAnchors(slot, slot:GetAnchors(), mapX)
    if changed then slot:SetAnchors(anchors) end
end

-- Anchors method, one direct child of the target canvas.
local function remapChild(child, cfg, scaleX, clip)
    local slot = child.Slot
    local orig, new, changed = mapAnchors(slot, slot:GetAnchors(), scaleX)
    if changed then slot:SetAnchors(new) end
    if orig.Minimum.X == orig.Maximum.X then return end

    -- A stretched child is a container that now spans the virtual area only.
    if clip then clipToBounds(child) end
    local key = child:GetFullName()
    for _, widget in ipairs(unshiftWidgets(child, cfg.unshift)) do
        if widget:IsValid() then
            unshift(widget, orig, new)
        else
            unshiftTargets[key] = nil -- the game rebuilt it; search again on the next poll
        end
    end
end

-- Brings one live UserWidget to `ratio`: the fraction of the screen width the virtual area covers.
-- A ratio of 1 writes the original anchors back.
function M.apply(widget, cfg, ratio)
    local function scaleX(x) return 0.5 + (x - 0.5) * ratio end
    local clip = cfg.clip and ratio < 1
    if cfg.method == "viewport" then
        return remapViewport(widget, scaleX, clip)
    end

    local root = M.rootOf(widget)
    local canvas = root and find(root, function(w) return M.isA(w, "CanvasPanel") end)
    if not canvas then
        trace("%s: no CanvasPanel found, skipped", cfg.class)
        return
    end
    for _, child in ipairs(M.childrenOf(canvas)) do
        if not cfg.exclude[child:GetFName():ToString():lower()] then
            remapChild(child, cfg, scaleX, clip)
        end
    end
end

return M
