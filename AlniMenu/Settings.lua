-- AlniMenu/Settings.lua
-- AlniMenu's page in the game's Settings panel.

local ADDON_NAME, ns = ...

-- Every theme, including Basic and Panel, which are built around a close
-- button corner the menu does not fill yet.
local THEME_DESCRIPTIONS = {
    basic    = "A metal window frame with a title bar.",
    gold     = "A gold dialog border with a title banner.",
    panel    = "The frame of windows like the Character window.",
    modern   = "The Game Menu's border and header.",
    standard = "A grey dialog border with a title banner.",
    tooltip  = "A tooltip's thin border.",
}

local function GetThemeOptions()
    local container = Settings.CreateControlTextContainer()
    for _, name in ipairs(ns.Lib:GetThemes()) do
        container:Add(name, name:sub(1, 1):upper() .. name:sub(2), THEME_DESCRIPTIONS[name])
    end
    return container:GetData()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterAllEvents()

    local category = Settings.RegisterVerticalLayoutCategory("AlniMenu")

    local themeSetting = Settings.RegisterAddOnSetting(
        category, "ALNIMENU_THEME", "theme", AlniMenuDB,
        Settings.VarType.String, "Theme", "modern")
    Settings.CreateDropdown(category, themeSetting, GetThemeOptions,
        "The border and title style of the menu.")
    Settings.SetOnValueChangedCallback("ALNIMENU_THEME", function()
        ns.ApplyTheme()
    end)

    -- which buttons show, and in which category, is edited on the menu
    -- itself (the gear in its corner)
    SettingsPanel:GetLayout(category):AddInitializer(CreateSettingsButtonInitializer(
        "Buttons and categories", "Edit Layout",
        function() ns.SetEditing(true) end,
        "Opens the menu in edit mode: show or hide buttons, move them between categories, "
        .. "and add, rename or reorder categories. The gear in the menu's corner does the same.",
        true))

    Settings.RegisterAddOnCategory(category)
end)
