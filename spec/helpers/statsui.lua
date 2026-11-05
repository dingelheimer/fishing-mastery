-- Stats window stubs for boot specs: tab templates, a ScrollBox that draws every row of its data
-- provider at once, realm time, date, zone names, and item quality colors.
local M = {}

-- Globals the stubs set; removed after each test.
M.STUBS = {
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "CreateScrollBoxListLinearView",
    "ScrollUtil",
    "CreateDataProvider",
    "GetGameTime",
    "date",
}

-- Tab and ScrollBox stubs: a list draws every row of its data provider at once.
function M.stub(w)
    local tabs = {}
    _G.PanelTemplates_SetNumTabs = function(frame, n)
        frame.numTabs = n
    end
    _G.PanelTemplates_SetTab = function(frame, id)
        tabs.selected = id
        frame.selectedTab = id
    end
    _G.CreateScrollBoxListLinearView = function()
        return {
            SetElementExtent = function() end,
            SetElementInitializer = function(view, _, init)
                view.init = init
            end,
        }
    end
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, _, view)
            box.SetDataProvider = function(_, provider)
                box.drawn = {}
                for i, data in ipairs(provider.rows) do
                    box.pool = box.pool or {}
                    local row = box.pool[i] or w.env.CreateFrame("Frame", nil, box)
                    box.pool[i] = row
                    view.init(row, data)
                    box.drawn[i] = row
                end
            end
        end,
    }
    _G.CreateDataProvider = function(rows)
        return { rows = rows }
    end
    _G.GetGameTime = function()
        return (math.floor((w.serverTime % 86400) / 3600) + 2) % 24, 0
    end
    _G.date = os.date
    _G.C_Map.GetMapInfo = function(map)
        return ({ [1411] = { name = "Durotar" }, [1412] = { name = "Mulgore" } })[map]
    end
    _G.C_Item.GetItemQualityColor = function()
        return 1, 1, 1, "ffffffff"
    end
    return tabs
end

-- Texts of the cells of every drawn row of a list.
function M.texts(list)
    local rows = {}
    for i, row in ipairs(list.box.drawn) do
        rows[i] = {}
        for j, cell in ipairs(row.cells) do
            rows[i][j] = cell:GetText()
        end
    end
    return rows
end

-- Removes the stubs.
function M.cleanup()
    for _, name in ipairs(M.STUBS) do
        _G[name] = nil
    end
end

return M
