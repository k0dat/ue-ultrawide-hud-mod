-- Widget dump: writes the tree of every UserWidget in the viewport to a text file, so the HUD
-- widget's class name and its children's names can be found for a profile. An SVG beside it draws
-- each visible canvas child as a labelled box where it sits on screen.

local Remap = require("remap")
local Svg = require("svg")

local M = {}

local VISIBILITY = { [0] = "Visible", "Collapsed", "Hidden", "HitTestInvisible", "SelfHitTestInvisible" }
local HIDDEN = { [1] = true, [2] = true }
local COLOURS = { "#ff6b6b", "#ffb347", "#f0e442", "#6bd66b", "#56b4e9", "#c792ea" } -- by tree depth

local function canvasSlot(widget)
    local slot = widget.Slot
    return Remap.isValid(slot) and Remap.isA(slot, "CanvasPanelSlot") and slot or nil
end

local function describe(widget, slot)
    local text = string.format('%s "%s" %s', widget:GetClass():GetFName():ToString(),
        widget:GetFName():ToString(), VISIBILITY[widget:GetVisibility()] or "?")
    if not slot then return text end
    local a, o = slot:GetAnchors(), slot:GetOffsets()
    return text .. string.format("  anchors (%g,%g)-(%g,%g)  offsets (%g,%g,%g,%g)",
        a.Minimum.X, a.Minimum.Y, a.Maximum.X, a.Maximum.Y, o.Left, o.Top, o.Right, o.Bottom)
end

-- Adds the subtree's lines to `lines`, and to `boxes` a box for each visible canvas child. A box's
-- rect is worked out later from its `parent` box, so the text is safe on disk before any of the
-- layout calls the SVG needs.
local function walk(lines, boxes, widget, indent, parent)
    local slot = canvasSlot(widget)
    local text = describe(widget, slot)
    lines[#lines + 1] = indent .. text
    if HIDDEN[widget:GetVisibility()] then boxes = nil end
    if slot and boxes then
        parent = { widget = widget, slot = slot, parent = parent, text = text,
            name = widget:GetFName():ToString(), depth = #indent // 2 }
        boxes[#boxes + 1] = parent
    end
    local children = Remap.childrenOf(widget)
    if Remap.isA(widget, "UserWidget") then
        children = { Remap.rootOf(widget) }
        -- A profile can't name anything inside a nested UserWidget, so it is drawn as one box.
        if indent ~= "" then boxes = nil end
    end
    for _, child in ipairs(children) do
        walk(lines, boxes, child, indent .. "  ", parent)
    end
end

-- Writes the text dump to `path` and returns the boxes for `M.writeSvg`.
function M.writeText(path, header)
    local lines, boxes = { header }, {}
    for _, widget in ipairs(FindAllOf("UserWidget") or {}) do
        if widget:IsValid() and widget:IsInViewport() then
            lines[#lines + 1] = ""
            walk(lines, boxes, widget, "", { widget = widget })
        end
    end
    local file, err = io.open(path, "w")
    if not file then return nil, err end
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    return boxes
end

-- One axis of the canvas layout rule (SConstraintCanvas): returns start and length. A stretched
-- axis treats the offsets as margins and ignores alignment.
local function axis(start, length, min, max, lead, trail, align, autoSize)
    local from = start + min * length + lead
    if min ~= max then return from, start + max * length - trail - from end
    local size = autoSize or trail
    return from - align * size, size
end

-- Where a canvas child sits inside its parent's rect, in Slate units. Render transforms are ignored.
local function placeInCanvas(widget, slot, parent)
    local a, o, align = slot:GetAnchors(), slot:GetOffsets(), slot:GetAlignment()
    local desired = slot:GetAutoSize() and widget:GetDesiredSize() or {}
    local x, w = axis(parent.x, parent.w, a.Minimum.X, a.Maximum.X, o.Left, o.Right, align.X, desired.X)
    local y, h = axis(parent.y, parent.h, a.Minimum.Y, a.Maximum.Y, o.Top, o.Bottom, align.Y, desired.Y)
    return { x = x, y = y, w = w, h = h }
end

-- Any widget between two canvas children is assumed to fill its parent, which holds for overlays,
-- borders and retainer boxes. A top-level widget is assumed to fill its viewport anchors, as
-- AddToViewport leaves it.
local function rectOf(box, view)
    if box.rect then return box.rect end
    if box.slot then
        box.rect = placeInCanvas(box.widget, box.slot, rectOf(box.parent, view))
    else
        local a = box.widget:GetAnchorsInViewport()
        box.rect = { x = a.Minimum.X * view.width, y = a.Minimum.Y * view.height,
            w = (a.Maximum.X - a.Minimum.X) * view.width, h = (a.Maximum.Y - a.Minimum.Y) * view.height }
    end
    return box.rect
end

-- A file URL breaks at '#' and decodes '%'.
local function fileUrl(path)
    return "file:///" .. path:gsub("%%", "%%25"):gsub("#", "%%23")
end

-- `view` is { width, height } in Slate units, `ratio`, the virtual area's share of the width, and
-- `screenshot`, an absolute path drawn underneath the boxes.
function M.writeSvg(path, view, boxes)
    local w, h, font = view.width, view.height, view.height / 100
    local content = { Svg.element("rect", { width = w, height = h, fill = "#1e1e1e" }) }
    if view.screenshot then
        content[#content + 1] = Svg.element("image", { href = fileUrl(view.screenshot),
            width = "100%", height = "100%", preserveAspectRatio = "none" })
    end
    content[#content + 1] = Svg.element("rect", { x = (1 - view.ratio) / 2 * w, width = view.ratio * w, height = h,
        fill = "#fff", ["fill-opacity"] = 0.08 })
    -- Labels overlap where elements share a corner. Hovering anywhere in a box shows its full dump
    -- line, so the largest are drawn first and the smallest box under the pointer gets the hover.
    for _, box in ipairs(boxes) do rectOf(box, view) end
    table.sort(boxes, function(a, b) return a.rect.w * a.rect.h > b.rect.w * b.rect.h end)
    for _, box in ipairs(boxes) do
        local r, colour = box.rect, COLOURS[box.depth % #COLOURS + 1]
        content[#content + 1] = Svg.element("g", nil, {
            Svg.element("title", nil, box.text),
            Svg.element("rect", { x = r.x, y = r.y, width = r.w, height = r.h, fill = "none", stroke = colour,
                ["vector-effect"] = "non-scaling-stroke", ["pointer-events"] = "all" }),
            Svg.element("text", { x = r.x + font / 4, y = r.y + font / 4, dy = "1em", fill = colour,
                stroke = "#000", ["stroke-width"] = font / 6, ["paint-order"] = "stroke" }, box.name),
        })
    end
    return Svg.write(path, w, h, { ["font-family"] = "sans-serif", ["font-size"] = font }, content)
end

return M
