-- AlniMenu/Plugins.lua
-- AlniMenu's own widgets, added the same way any addon can add one: with "## OptionalDeps: AlniMenu" in the TOC, call
-- AlniMenu.RegisterWidget(key, def) from the addon's main code. See AlniMenuWidget in Menu.lua for `def`.

if not (AlniMenu and AlniMenu.RegisterWidget) then
    return
end

-- Volume ------------------------------

--- The master volume, 0 to 100
---@return integer
local function Volume()
    return math.floor((tonumber(GetCVar("Sound_MasterVolume")) or 0) * 100 + 0.5)
end

AlniMenu.RegisterWidget("volume", {
    text = "Volume",
    create = function(row)
        local slider = row.lib:CreateSlider(row, {
            width = row:GetWidth() - 40,
            value = Volume(),
            onChange = function(value)
                value = math.floor(value + 0.5)
                -- also called while the slider is made and on every show
                if value ~= Volume() then
                    SetCVar("Sound_MasterVolume", value / 100)
                end
                if row.name then
                    row:SetText(row.name)
                end
            end,
        })
        slider:SetPoint("TOP", 0, -2)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOP", slider, "BOTTOM", 0, -4)
        -- the volume may have changed since the menu last showed
        row:SetScript("OnShow", function() slider:SetValue(Volume()) end)
    end,
    update = function(row)
        row.label:SetText(row.name .. " " .. Volume() .. "%")
    end,
})

-- Latency ------------------------------

--- `ms` in green, yellow or red, as the micro menu colors latency
---@param ms number
---@return string
local function Colored(ms)
    local color = "|cffff0000"
    if ms < (PERFORMANCEBAR_LOW_LATENCY or 300) then
        color = "|cff00ff00"
    elseif ms < (PERFORMANCEBAR_MEDIUM_LATENCY or 600) then
        color = "|cffffff00"
    end
    return color .. ms .. "|r"
end

AlniMenu.RegisterWidget("latency", {
    text = "Latency",
    create = function(row)
        -- every second while the menu is open
        row:SetScript("OnShow", function()
            row:SetText(row.name)
            row.ticker = C_Timer.NewTicker(1, function() row:SetText(row.name) end)
        end)
        row:SetScript("OnHide", function()
            if row.ticker then
                row.ticker:Cancel()
            end
            row.ticker = nil
        end)
        row.lib:AddTooltip(row, function()
            return row.name, "Home: chat, friends and addons.\nWorld: combat and everything around you."
        end)
    end,
    update = function(row)
        local _, _, home, world = GetNetStats()
        row.label:SetText(row.name .. " " .. Colored(home) .. " / " .. Colored(world) .. " ms")
    end,
})

-- Separator ------------------------------

AlniMenu.RegisterWidget("separator", {
    text = "Separator",
    height = 12,
    multiple = true,
    create = function(row)
        local line = row.lib:CreateSeparator(row, { color = { 0.8, 0.7, 0.4, 0.6 } })
        line:ClearAllPoints()
        line:SetPoint("LEFT", 12, 0)
        line:SetPoint("RIGHT", -12, 0)
    end,
    -- no label
    update = function() end,
})
