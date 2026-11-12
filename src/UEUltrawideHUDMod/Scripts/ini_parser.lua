--- ini_parser Module
-- @module ini_parser
-- @description This module provides functions to read and write INI configuration files in Lua.

local ini_parser = {}

--- Reads an INI file and parses its content into a table.
-- @param filePath string: The path to the INI file to be read.
-- @return table: A table containing the parsed INI data. The table includes an `__order` field that maintains the order of sections, keys, and comments.
function ini_parser.read(filePath)
    --Params assertions
    assert(type(filePath) == 'string', 'Parameter "filePath" must be a string.')

    local file, err = io.open(filePath, 'r')
    assert(file, 'Cannot open file: ' .. (err or filePath))

    local data = { __order = {} }
    local currentSection = nil

    for line in file:lines() do
        -- Handle empty lines
        if line:match('^%s*$') then
            table.insert(data.__order, { type = "empty" })

            -- Handle comments
        elseif line:match('^%s*[;#].*$') then
            local comment = line:match('^(%s*[;#].*)$')
            table.insert(data.__order, { type = "comment", comment = comment, section = currentSection })

            -- Handle sections
        else
            local sectionName = line:match('^%[([^%[%]]+)%]$')
            if sectionName then
                currentSection = tonumber(sectionName) or sectionName
                if not data[currentSection] then
                    data[currentSection] = { __order = {} }
                    table.insert(data.__order, { type = "section", section = currentSection })
                end
            end

            -- Handle key-value pairs
            local key, value = line:match('^([%w_]+)%s-=%s-(.+)$')
            if key and value ~= nil then
                if tonumber(value) then
                    value = tonumber(value)
                elseif value == 'true' then
                    value = true
                elseif value == 'false' then
                    value = false
                end
                data[currentSection][key] = value
                table.insert(data[currentSection].__order, key)
                table.insert(data.__order, { type = "pair", section = currentSection, key = key, value = value })
            end
        end
    end

    file:close()
    return data
end

--- Writes a table to an INI file.
-- @param filePath string: The path to the INI file to be written.
-- @param data table: A table containing the data to be written to the INI file.
function ini_parser.write(filePath, data)
    --Params assertions
    assert(type(filePath) == 'string', 'Parameter "filePath" must be a string.')
    assert(type(data) == 'table', 'Parameter "data" must be a table.')

    local file, err = io.open(filePath, 'w+b')
    assert(file, 'Cannot open file: ' .. (err or filePath))

    local contents = ''
    local order = data.__order or {}

    for _, item in ipairs(order) do
        if item.type == "empty" then
            contents = contents .. '\n'
        elseif item.type == "comment" then
            contents = contents .. item.comment .. '\n'
        elseif item.type == "section" then
            contents = contents .. ('[%s]\n'):format(item.section)
        elseif item.type == "pair" then
            contents = contents .. ('%s=%s\n'):format(item.key, tostring(data[item.section][item.key]))
        end
    end
    file:write(contents)
    file:close()
end

return ini_parser
