-- AlniMenu/Custom.lua
-- The window for adding, changing and deleting the player's own buttons: a label, a macro and the category it goes in.
-- Opened from edit mode (Add Button, or the pencil on a custom button's bar). For a built-in button the pencil opens it
-- smaller, to rename it only.

local ADDON_NAME, ns = ...

local MAX_MACRO = 255   -- as long as a macro may be

-- premade buttons for the Template dropdown
local TEMPLATES = {
    { text = "Dismount",              macro = "/dismount" },
    { text = "Favorite Mount",        macro = "/run C_MountJournal.SummonByID(0)" },
    { text = "Ready Check",           macro = "/readycheck" },
    { text = "Roll",                  macro = "/roll" },
    { text = "Leave Group",           macro = "/run C_PartyInfo.LeaveParty()" },
    { text = "Toggle Sound",          macro = '/run SetCVar("Sound_EnableAllSound", GetCVar("Sound_EnableAllSound") == "1" and "0" or "1")' },
    { text = "Stopwatch",             macro = "/stopwatch" },
}

local window
local editingKey   -- the button being changed; nil for a new custom one
local renaming     -- true: renaming a built-in button

local function Say(text)
    print("|cff33ff99" .. ADDON_NAME .. ":|r " .. text)
end

--- The categories as dropdown options, by index, then Unused
---@return table
local function CategoryOptions()
    local options = {}
    for i, category in ipairs(AlniMenuDB.layout) do
        options[i] = { value = i, label = category.name }
    end
    table.insert(options, { value = 0, label = "Unused" })
    return options
end

--- The index of the category holding `key`, or 0 when unused
---@param key string
---@return integer
local function CategoryOf(key)
    for i, category in ipairs(AlniMenuDB.layout) do
        for _, k in ipairs(category.items) do
            if k == key then
                return i
            end
        end
    end
    return 0
end

--- Moves `key` to the end of category `index` (0: unused)
---@param key string
---@param index integer
local function PutIn(key, index)
    if CategoryOf(key) == index then
        return
    end
    for _, category in ipairs(AlniMenuDB.layout) do
        for j = #category.items, 1, -1 do
            if category.items[j] == key then
                table.remove(category.items, j)
            end
        end
        category.gaps[key] = nil
    end
    local category = AlniMenuDB.layout[index]
    if category then
        table.insert(category.items, key)
    end
end

--- Renaming a built-in button: its own label (or an empty box) undoes it
local function SaveRename()
    local key = editingKey
    local text = strtrim(window.label:GetText())
    if text == "" or text == ns.ENTRIES[key].text then
        AlniMenuDB.labels[key] = nil
    else
        AlniMenuDB.labels[key] = text
    end
    ns.RefreshEntryButton(key)
    window:Hide()
    ns.ApplyLayout()
end

local function Save()
    if renaming then
        return SaveRename()
    end
    if InCombatLockdown() then
        Say("custom buttons can only be saved out of combat.")
        return
    end
    local text  = strtrim(window.label:GetText())
    local macro = window.macro:GetText()
    if text == "" then
        Say("give the button a label.")
        return
    end

    local key = editingKey
    if key then
        local id = ns.ENTRIES[key].custom
        AlniMenuDB.custom[id] = { text = text, macro = macro }
        ns.AddCustomEntry(id)
    else
        local id = AlniMenuDB.nextCustom
        AlniMenuDB.nextCustom = id + 1
        AlniMenuDB.custom[id] = { text = text, macro = macro }
        key = ns.AddCustomEntry(id)
        AlniMenuDB.buttons[key] = true
        AlniMenuDB.known[key] = true
    end
    -- without a category picker, new buttons go in the first category
    local index = window.category and window.category:GetValue()
    if index == nil then
        index = editingKey and CategoryOf(key) or 1
    end
    -- unused buttons are off; out of Unused (or new), on
    local from = editingKey and CategoryOf(key) or 0
    PutIn(key, index)
    if index == 0 then
        AlniMenuDB.buttons[key] = false
    elseif from == 0 then
        AlniMenuDB.buttons[key] = true
    end

    ns.RefreshEntryButton(key)
    window:Hide()
    ns.ApplyLayout()
end

--- Deletes custom button `key` (from its window, or its X in edit mode)
---@param key string
function ns.DeleteCustomButton(key)
    local entry = ns.ENTRIES[key]
    if InCombatLockdown() or not (entry and entry.custom) then
        return
    end
    ns.RemoveEntry(key)
    AlniMenuDB.custom[entry.custom] = nil
    AlniMenuDB.buttons[key] = nil
    if window and editingKey == key then
        window:Hide()
    end
    ns.ApplyLayout()
end

local function Delete()
    if editingKey then
        ns.DeleteCustomButton(editingKey)
    end
end

local function BuildWindow()
    local Lib = ns.Lib
    window = Lib:CreateDialog({
        name   = "AlniMenuCustomFrame",
        title  = "Custom Button",
        width  = 400,
        height = 330,
        theme  = AlniMenuDB.theme,
        strata = "FULLSCREEN_DIALOG",   -- over the menu
    })

    window.label = Lib:CreateEditBox(window, { label = "Label", width = 220, maxLetters = 40 })
    window.label:SetPoint("TOPLEFT", 30, -58)

    if Lib:HasDropdown() then
        window.category = Lib:CreateDropdown(window, { label = "Category", width = 120 })
        window.category:SetPoint("TOPLEFT", 266, -54)
    end

    local macroLabel = window:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    macroLabel:SetPoint("TOPLEFT", 26, -92)
    macroLabel:SetText("Macro (up to " .. MAX_MACRO .. " characters)")

    -- a dark box behind the macro text
    local box = CreateFrame("Frame", nil, window, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 24, -108)
    box:SetPoint("BOTTOMRIGHT", -24, 58)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5)

    local _, macro = Lib:CreateScrollFrame(box, {
        x1 = 8, y1 = -6, x2 = -26, y2 = 6,
        childType     = "EditBox",
        contentWidth  = 310,
        contentHeight = 1,
    })
    macro:SetMultiLine(true)
    macro:SetAutoFocus(false)
    macro:SetFontObject(ChatFontNormal)
    macro:SetMaxLetters(MAX_MACRO)
    macro:SetWidth(310)
    macro:SetScript("OnEscapePressed", macro.ClearFocus)
    window.macro = macro
    -- a click anywhere in the box starts typing
    box:SetScript("OnMouseDown", function() macro:SetFocus() end)

    window.save = Lib:CreateButton(window, { text = SAVE or "Save", width = 100, onClick = Save })
    window.save:SetPoint("BOTTOMRIGHT", -24, 22)
    window.cancel = Lib:CreateButton(window, {
        text = CANCEL or "Cancel", width = 100, onClick = function() window:Hide() end,
    })
    window.cancel:SetPoint("RIGHT", window.save, "LEFT", -8, 0)
    window.delete = Lib:CreateButton(window, { text = DELETE or "Delete", width = 100, onClick = Delete })
    window.delete:SetPoint("BOTTOMLEFT", 24, 22)
    window.reset = Lib:CreateButton(window, {
        text        = RESET or "Reset",
        width       = 100,
        onClick     = function() window.label:SetText(ns.ENTRIES[editingKey].text) end,
        tooltip     = "Reset",
        tooltipText = "Back to the button's own label. Save to keep it.",
    })
    window.reset:SetPoint("BOTTOMLEFT", 24, 22)

    -- new buttons only, where Delete goes for existing ones
    if Lib:HasDropdown() then
        local options = {}
        for i, t in ipairs(TEMPLATES) do
            options[i] = { value = i, label = t.text }
        end
        window.template = Lib:CreateDropdown(window, {
            width       = 136,   -- 8 short of Cancel, like Cancel and Save
            options     = options,
            placeholder = "Template...",
            onChange    = function(i)
                window.label:SetText(TEMPLATES[i].text)
                window.macro:SetText(TEMPLATES[i].macro)
            end,
        })
        window.template:SetPoint("BOTTOMLEFT", 24, 24)
    end

    -- everything only a custom button has, hidden while renaming
    window.customOnly = { macroLabel, box, window.category }

    table.insert(UISpecialFrames, "AlniMenuCustomFrame")
end

--- Lays the window out for a custom button, or smaller for a rename
---@param rename boolean
local function SetMode(rename)
    renaming = rename
    for _, region in pairs(window.customOnly) do
        region:SetShown(not rename)
    end
    window.reset:SetShown(rename)
    window:SetHeight(rename and 160 or 330)
    -- the title refits when the theme is applied
    window.titleText:SetText(rename and "Rename Button" or "Custom Button")
    window:SetTheme(AlniMenuDB.theme)
end

function ns.HideCustomWindow()
    if window then
        window:Hide()
    end
end

--- Opens the window to rename built-in button `key`
---@param key string
function ns.RenameButton(key)
    if InCombatLockdown() then
        return
    end
    if not window then
        BuildWindow()
    end
    editingKey = key
    SetMode(true)
    window.label:SetText(ns.Label(key))
    window.delete:Hide()
    if window.template then
        window.template:Hide()
    end
    window:Show()
    window.label:SetFocus()
    window.label:HighlightText()
end

--- Opens the window for custom button `key`, or for a new one (nil)
---@param key string?
function ns.EditCustomButton(key)
    if InCombatLockdown() then
        return
    end
    if not window then
        BuildWindow()
    end
    editingKey = key
    SetMode(false)

    local data = key and AlniMenuDB.custom[ns.ENTRIES[key].custom]
    window.label:SetText(data and data.text or "")
    window.macro:SetText(data and data.macro or "")
    if window.category then
        window.category:SetOptions(CategoryOptions())
        window.category:SetValue(key and CategoryOf(key) or 1)
    end
    window.delete:SetShown(key ~= nil)
    if window.template then
        window.template:SetValue(nil)
        window.template:SetShown(key == nil)
    end

    window:Show()
    window.label:SetFocus()
end
