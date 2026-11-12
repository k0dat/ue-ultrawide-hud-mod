-- Widget dump: writes the tree of every UserWidget in the viewport to a text file, so the HUD
-- widget's class name and its children's names can be found for a profile.

local Remap = require("remap")

local M = {}

local VISIBILITY = { [0] = "Visible", "Collapsed", "Hidden", "HitTestInvisible", "SelfHitTestInvisible" }

local function describe(widget)
    local text = string.format('%s "%s" %s', widget:GetClass():GetFName():ToString(),
        widget:GetFName():ToString(), VISIBILITY[widget:GetVisibility()] or "?")
    local slot = widget.Slot
    if not (Remap.isValid(slot) and Remap.isA(slot, "CanvasPanelSlot")) then return text end
    local a, o = slot:GetAnchors(), slot:GetOffsets()
    return text .. string.format("  anchors (%g,%g)-(%g,%g)  offsets (%g,%g,%g,%g)",
        a.Minimum.X, a.Minimum.Y, a.Maximum.X, a.Maximum.Y, o.Left, o.Top, o.Right, o.Bottom)
end

local function writeTree(file, widget, indent)
    file:write(indent, describe(widget), "\n")
    local children = Remap.childrenOf(widget)
    if Remap.isA(widget, "UserWidget") then children = { Remap.rootOf(widget) } end
    for _, child in ipairs(children) do
        writeTree(file, child, indent .. "  ")
    end
end

function M.write(path, header)
    local file, err = io.open(path, "w")
    if not file then return nil, err end
    file:write(header, "\n")
    for _, widget in ipairs(FindAllOf("UserWidget") or {}) do
        if widget:IsValid() and widget:IsInViewport() then
            file:write("\n")
            writeTree(file, widget, "")
        end
    end
    file:close()
    return path
end

return M
