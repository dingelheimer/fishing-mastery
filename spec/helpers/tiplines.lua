-- Records what a row's tip(builder) writes, as plain lines without color escapes: a title or line
-- as its text, a pair as "label = value", a gap as " ", details as the Shift lines (shift) or the
-- prompt (the "Hold Shift" line).
local M = {}

local function plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function M.lines(draw, shift)
    local out = {}
    local builder = {}
    local function add(_, text)
        out[#out + 1] = plain(text)
    end
    builder.Title, builder.Line, builder.Hint = add, add, add
    function builder.Pair(_, label, value)
        out[#out + 1] = plain(label) .. " = " .. plain(value)
    end
    -- A Tip header is a line; a detail pane header or row (cells) is joined by " | ".
    function builder.Header(_, cells)
        out[#out + 1] = type(cells) == "table" and plain(table.concat(cells, " | ")) or plain(cells)
    end
    builder.Row = builder.Header
    function builder.Gap()
        out[#out + 1] = " "
    end
    function builder.Details(_, lines, prompt)
        out[#out + 1] = " "
        if not shift then
            out[#out + 1] = prompt or "Hold Shift for how this is counted"
            return
        end
        for _, line in ipairs(lines) do
            out[#out + 1] = plain(line)
        end
    end
    draw(builder)
    return out
end

-- The lines as one string (for find checks).
function M.text(draw, shift)
    return table.concat(M.lines(draw, shift), "\n")
end

return M
