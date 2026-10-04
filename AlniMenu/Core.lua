-- AlniMenu/Core.lua
-- Saved settings, and making Esc open AlniMenu instead of the Game Menu.
--
-- Whenever the Game Menu opens, AlniMenu closes it and opens in its
-- place. Esc closes AlniMenu like any addon window (UISpecialFrames).
--
-- Not RegisterGameMenuEscHandler: adding to that list from addon code
-- taints it, and then Blizzard's own Esc handlers are blocked
-- (SpellStopCasting, SpellStopTargeting).
--
-- The Game Menu opens as usual:
--   in combat       AlniMenu's secure buttons (Log Out, Exit Game...)
--                   cannot be shown then
--   with Shift+Esc  always, as a way out
--   once allowed    from AlniMenu's Blizzard Menu button

local ADDON_NAME, ns = ...

-- AlnUI as it is right now, just after this folder's copy loaded. An
-- addon loading later with an older, unversioned copy would overwrite
-- the global AlnUI's functions; this keeps the ones AlniMenu came with.
local Lib = {}
for k, v in pairs(AlnUI) do Lib[k] = v end
ns.Lib = Lib

--------------------------------------------------
-- Configuration
--------------------------------------------------

local DEBUG = AlniDev and AlniDev.debug[ADDON_NAME] or false   -- also shows the debug view's bug icon on the menu

local function DebugPrint(...)
    if DEBUG then print("|cff33ff99" .. ADDON_NAME .. ":|r", ...) end
end
ns.DebugPrint = DebugPrint
ns.DEBUG = DEBUG

local DEFAULTS = {
    theme = "modern",   -- the Game Menu's own border
}

--------------------------------------------------
-- Saved settings
--------------------------------------------------

local function InitDB()
    AlniMenuDB = AlniMenuDB or {}
    for key, value in pairs(DEFAULTS) do
        if AlniMenuDB[key] == nil then AlniMenuDB[key] = value end
    end
    -- the player's own names for the built-in buttons, by key
    AlniMenuDB.labels = AlniMenuDB.labels or {}
    -- the player's own macro buttons (Custom.lua)
    AlniMenuDB.custom = AlniMenuDB.custom or {}
    AlniMenuDB.nextCustom = AlniMenuDB.nextCustom or 1
    ns.LoadCustomEntries()
    -- which buttons are switched on, by key; missing ones use their default
    AlniMenuDB.buttons = AlniMenuDB.buttons or {}
    for key, entry in pairs(ns.ENTRIES) do
        if not entry.always and AlniMenuDB.buttons[key] == nil then
            AlniMenuDB.buttons[key] = entry.default and true or false
        end
    end
    -- which button goes in which category
    ns.CheckLayout()
end

--------------------------------------------------
-- Esc
--------------------------------------------------

local function HookEscape()
    -- a post-hook: Blizzard's code opening the menu stays untainted
    GameMenuFrame:HookScript("OnShow", function()
        if ns.allowBlizzardMenu then
            ns.allowBlizzardMenu = false
            DebugPrint("Game Menu allowed once")
            return
        end
        if InCombatLockdown() or IsShiftKeyDown() then return end
        HideUIPanel(GameMenuFrame)
        ns.ShowMenu()
    end)
end

--------------------------------------------------
-- Events
--------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- while AlniMenu is a proof of concept: say which Blizzard-only action
-- it was stopped from doing, so it can be moved to a secure button
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:SetScript("OnEvent", function(self, event, name, func)
    if (event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED") then
        if name == ADDON_NAME then
            print("|cff33ff99" .. ADDON_NAME .. ":|r " .. event .. ": " .. tostring(func))
        end
        return
    end
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        HookEscape()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- the last moment its secure buttons may still be hidden
        ns.HideMenu()
    end
end)

--------------------------------------------------
-- Slash command
--------------------------------------------------

SLASH_ALNIMENU1 = "/alnimenu"
SlashCmdList.ALNIMENU = function(msg)
    if InCombatLockdown() then
        print("|cff33ff99" .. ADDON_NAME .. ":|r not in combat.")
    elseif strtrim(msg or ""):lower() == "edit" then
        ns.SetEditing(true)
    elseif not ns.HideMenu() then
        ns.ShowMenu()
    end
end
