-- Minimal SVG writer for the widget dump: elements are built as strings and written in one go.

local M = {}

local ENTITIES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }

local function escape(value)
    if type(value) == "number" then return string.format("%g", value) end
    return (tostring(value):gsub('[&<>"]', ENTITIES))
end

-- One element. `content` is text, which gets escaped, or an array of elements; without it the tag
-- closes itself. Attributes are sorted so the output doesn't change from run to run.
function M.element(name, attrs, content)
    local keys = {}
    for key in pairs(attrs or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local tag = "<" .. name
    for _, key in ipairs(keys) do
        tag = tag .. string.format(' %s="%s"', key, escape(attrs[key]))
    end
    if content == nil then return tag .. "/>" end
    local body = type(content) == "table" and table.concat(content, "\n") or escape(content)
    return string.format("%s>%s</%s>", tag, body, name)
end

-- Writes a document whose user units span `width` x `height`. Returns `path`.
function M.write(path, width, height, attrs, content)
    local file, err = io.open(path, "w")
    if not file then return nil, err end
    attrs.xmlns = "http://www.w3.org/2000/svg"
    attrs.viewBox = string.format("0 0 %g %g", width, height)
    file:write(M.element("svg", attrs, content), "\n")
    file:close()
    return path
end

return M
