-- AlniMenu/Menu.lua
local ADDON_NAME, ns = ...

--------------------------------------------------
-- Layout
--------------------------------------------------

-- the Game Menu's own sizes (MainMenuFrameTemplate)
local BUTTON_W, BUTTON_H = 200, 36
local COLUMN_GAP         = 8    -- between columns
local SECTION_GAP        = 20   -- between sections
local HEADING_H          = 20   -- the category names over the columns
local TOP, BOTTOM        = 48, 34
local SIDE               = 28
local EDIT_W             = 260  -- columns in edit mode, room for the controls
local MIN_UNUSED_ROWS    = 8    -- Unused wraps into more columns past this or the tallest category
local SEPARATOR_H        = 12   -- a separator row, outside edit mode

-- Blizzard's big red Game Menu button
local BUTTON_TEMPLATE = "MainMenuFrameButtonTemplate"

--- Blizzard's translated label `key`, or `fallback` where it has none
---@param key string
---@param fallback string
---@return string
local function L(key, fallback)
    local text = _G[key]
    return type(text) == "string" and text or fallback
end

--------------------------------------------------
-- Buttons
--
-- ENTRIES[key]:
--   text     label
--   default  on until the player switches it in the settings
--   always   cannot be switched off (none at the moment)
--   action   function returning how the button works on this client,
--            or nil where it cannot:
--              { click = frame }   a secure click on that Blizzard button
--              { macro = "/cmd" }  a secure slash command
--              { func = fn }       fn() after the menu closes
--   shown    optional: function returning whether it applies right now
--   badge    optional: function returning what to mark it with now, as
--            the Game Menu does: "new" (the NEW label) or "alert" (the
--            notification dot), or nil; and, for an alert, the reason,
--            shown when the button is hovered (as the micro menu's
--            callouts say it)
--------------------------------------------------

--- A Blizzard button to click, if this client has it
---@param name string
---@return function
local function Click(name)
    return function()
        local frame = _G[name]
        if frame then
            return { click = frame }
        end
    end
end

--- A function to call, if this client has the global `name` (checked when the menu is built, once every Blizzard file
--- has loaded); with no name, always
---@param name string?
---@param fn function
---@return function
local function Func(name, fn)
    return function()
        if name == nil or _G[name] ~= nil then
            return { func = fn }
        end
    end
end

local function Macro(command)
    return function() return { macro = command } end
end

local function OpenSettings()
    SettingsPanel:Open()
end

--- Blizzard's own menu, for anything AlniMenu does not offer. Opened from addon code, so its buttons run as AlniMenu's
--- code; if Blizzard blocks any of them (Log Out, Exit Game...), the chat line from Core.lua names it, and Shift+Esc
--- opens the menu untouched instead.
local function ShowBlizzardMenu()
    ns.allowBlizzardMenu = true   -- AlniMenu steps aside this once
    if GameMenuFrame_Show then
        GameMenuFrame_Show()
    else
        ShowUIPanel(GameMenuFrame)
    end
end

--- The profession in slot `slot` of GetProfessions() (1 and 2: the main professions, 5: Cooking), as its name and the
--- spell that opens its window: the first spell of the profession in the spellbook, the one the Professions book casts.
--- Nil when the character has none there.
---@param slot integer
---@return function
local function Profession(slot)
    return function()
        if not (GetProfessions and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then
            return nil
        end
        local index = select(slot, GetProfessions())
        if not index then
            return nil
        end
        local name, _, _, _, _, offset = GetProfessionInfo(index)
        local info = C_SpellBook.GetSpellBookItemInfo(offset + 1, Enum.SpellBookSpellBank.Player)
        if not (info and info.spellID) then
            return nil
        end
        return name, info.spellID
    end
end

--------------------------------------------------
-- Alerts: the reasons the micro menu calls attention to a window (MainMenuBarMicroButtons.lua and
-- Blizzard_Tutorials_Professions.lua), worked out the same way here. Each returns the message, or nil. Worked out, not
-- read off the micro buttons: Blizzard disables those, and hides their dots, while the Game Menu is open, which is just
-- when AlniMenu opens.
--------------------------------------------------

local Alerts = {}

--- Talents, in the micro menu's order of importance
---@return string?
function Alerts.Talents()
    if IsPlayerInitialSpec and IsPlayerInitialSpec() and (GetNumSpecializations() or 0) > 0 then
        return L("NPEV2_SPEC_TUTORIAL_GOSSIP_CLOSED", "Choose a specialization.")
    end
    local talents = C_ClassTalents
    if talents and (talents.HasUnspentTalentPoints()
        or (talents.HasUnspentHeroTalentPoints and talents.HasUnspentHeroTalentPoints())) then
        return L("TALENT_MICRO_BUTTON_UNSPENT_TALENTS", "You have unspent talent points.")
    end
    -- PvP talents only matter with War Mode on or in a battleground
    local pvp = C_PvP and (C_PvP.IsWarModeDesired() or (PVPUtil and PVPUtil.IsInActiveBattlefield()))
    if pvp and C_SpecializationInfo and C_SpecializationInfo.GetPvpTalentAlertStatus then
        local emptySlot, newTalent = C_SpecializationInfo.GetPvpTalentAlertStatus()
        if emptySlot then
            return L("TALENT_MICRO_BUTTON_UNSPENT_PVP_TALENT_SLOT", "You have an empty PvP talent slot.")
        elseif newTalent then
            return L("TALENT_MICRO_BUTTON_NEW_PVP_TALENT", "You have a new PvP talent.")
        end
    end
end

--- A profession specialization to choose; `name` limits it to one profession
---@param name string?
---@return string?
function Alerts.NewSpecialization(name)
    local profName = C_ProfSpecs and C_ProfSpecs.GetNewSpecReminderProfName and C_ProfSpecs.GetNewSpecReminderProfName()
    if profName and (not name or name == profName) then
        local text = PROFESSIONS_NEW_CHOICE_AVAILABLE_SPECIALIZATION
        return text and text:format(profName) or ("A new " .. profName .. " specialization is available.")
    end
end

function Alerts.Professions()
    local newSpec = Alerts.NewSpecialization()
    if newSpec then
        return newSpec
    end
    if C_ProfSpecs and C_ProfSpecs.ShouldShowPointsReminder and C_ProfSpecs.ShouldShowPointsReminder() then
        return L("PROFESSIONS_UNSPENT_SPEC_POINTS_REMINDER", "You have unspent profession specialization points.")
    end
end

function Alerts.Mounts()
    local journal = C_MountJournal
    local count = journal and journal.GetNumMountsNeedingFanfare and journal.GetNumMountsNeedingFanfare() or 0
    if count > 0 then
        return count > 1 and L("COLLECTION_UNOPENED_PLURAL", "You have new mounts to open.")
            or L("COLLECTION_UNOPENED_SINGULAR", "You have a new mount to open.")
    end
end

--- As the Guild & Communities micro button's dot
---@return string?
function Alerts.Guild()
    if not (C_Club and C_Club.IsEnabled() and C_SocialRestrictions and C_SocialRestrictions.CanReceiveChat()) then
        return nil
    end
    local unseen = false
    for _, invitation in ipairs(C_Club.GetInvitationsForSelf() or {}) do
        if not (DISPLAYED_COMMUNITIES_INVITATIONS and DISPLAYED_COMMUNITIES_INVITATIONS[invitation.club.clubId]) then
            unseen = true
        end
    end
    if unseen then
        return "You have new community invitations."
    end
    if CommunitiesUtil and CommunitiesUtil.DoesAnyCommunityHaveUnreadMessages() then
        return "You have unread community messages."
    end
end

--- As the Adventure Guide micro button's dot: tabs not looked at yet
---@return string?
function Alerts.AdventureGuide()
    local tabsSeen = Enum.FrameTutorialAccount and Enum.FrameTutorialAccount.EnconterJournalTutorialsTabSeen
    local unseen = tabsSeen and not GetCVarBitfield("closedInfoFramesAccountWide", tabsSeen)
    local journeys = LE_FRAME_TUTORIAL_JOURNEYS_TAB and not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_JOURNEYS_TAB)
    if unseen or journeys then
        return "There is something new to see in the Adventure Guide."
    end
end

--- An open support ticket that needs something from the player: the box Blizzard shows by the buffs
--- (TicketStatusFrame), in its own words
---@return string?
function Alerts.Ticket()
    if TicketStatusFrame and TicketStatusFrame:IsShown() then
        local text = TicketStatusTitleText and TicketStatusTitleText:GetText()
        return (text and text ~= "") and text or "Your support ticket needs your attention."
    end
end

--- As the Shop micro button's dot
---@return string?
function Alerts.Shop()
    if C_CatalogShop and C_CatalogShop.HasNewProducts and C_CatalogShop.HasNewProducts() then
        return "There are new products in the Shop."
    end
end

--- A badge function showing the alert `check` finds
---@param check function
---@param ... any
---@return function
local function AlertBadge(check, ...)
    local args = { ... }
    return function()
        local ok, text = pcall(check, unpack(args))
        if ok and text then
            return "alert", text
        end
    end
end

--- A button that casts the spell of a profession (a secure spell button, as in the Professions book)
---@param slot integer
---@param fallback string
---@return table
local function ProfessionEntry(slot, fallback)
    local profession = Profession(slot)
    return {
        text       = fallback,
        profession = profession,
        default    = true,
        action     = function() return { spell = true } end,
        shown      = function() return profession() ~= nil end,
        -- a new specialization to choose in this profession
        badge      = function()
            local name = profession()
            local text = name and Alerts.NewSpecialization(name)
            if text then
                return "alert", text
            end
        end,
    }
end

local function CollectionsTab(index)
    return Func("ToggleCollectionsJournal", function() ToggleCollectionsJournal(index) end)
end

local ENTRIES = {
    -- windows (the micro menu, and the tabs inside it)
    character    = { text = L("CHARACTER_BUTTON", "Character Info"), action = Click("CharacterMicroButton") },
    reputation   = { text = L("REPUTATION", "Reputation"),
                     action = Func("ToggleCharacter", function() ToggleCharacter("ReputationFrame") end) },
    currency     = { text = L("CURRENCY", "Currency"),
                     action = Func("ToggleCharacter", function() ToggleCharacter("TokenFrame") end) },
    professions  = { text = L("PROFESSIONS_BUTTON", "Professions"), action = Click("ProfessionMicroButton"),
                     badge  = AlertBadge(Alerts.Professions) },
    -- each named after the profession learned there, hidden when none
    profession1  = ProfessionEntry(1, "First Profession"),
    profession2  = ProfessionEntry(2, "Second Profession"),
    cooking      = ProfessionEntry(5, "Cooking"),
    -- Forever has a micro button for each, to click securely; Retail has one for both, so there it takes Blizzard's
    -- function
    spellbook    = { text = L("SPELLBOOK", "Spellbook"),
                     action = function()
                         return Click("SpellbookMicroButton")()
                             or { func = function() PlayerSpellsUtil.ToggleSpellBookFrame() end }
                     end },
    talents      = { text = L("TALENTS", "Talents"),
                     action = function()
                         return Click("TalentMicroButton")()
                             or { func = function() PlayerSpellsUtil.ToggleClassTalentOrSpecFrame() end }
                     end,
                     badge  = AlertBadge(Alerts.Talents) },
    achievements = { text = L("ACHIEVEMENT_BUTTON", "Achievements"), action = Click("AchievementMicroButton") },
    questlog     = { text = "Quest Log & Map", action = Click("QuestLogMicroButton") },
    calendar     = { text = "Calendar", action = Click("GameTimeFrame") },
    housing      = { text = "Housing Dashboard", action = Click("HousingMicroButton") },
    guild        = { text = L("GUILD_AND_COMMUNITIES", "Guild & Communities"), action = Click("GuildMicroButton"),
                     badge  = AlertBadge(Alerts.Guild) },
    groupfinder  = { text = L("GROUP_FINDER", "Group Finder"), action = Click("LFDMicroButton") },
    pvp          = { text = L("PLAYER_V_PLAYER", "Player vs. Player"),
                     action = Func("TogglePVPUI", function() TogglePVPUI() end) },
    mounts       = { text = L("MOUNTS", "Mounts"), action = CollectionsTab(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS or 1),
                     badge  = AlertBadge(Alerts.Mounts) },
    appearances  = { text = "Appearances", action = CollectionsTab(COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES or 5) },
    adventure    = { text = L("ADVENTURE_JOURNAL", "Adventure Guide"), action = Click("EJMicroButton"),
                     badge  = AlertBadge(Alerts.AdventureGuide) },

    -- the Game Menu's own
    options  = { text = L("GAMEMENU_OPTIONS", "Options"), default = true, action = Func(nil, OpenSettings),
                 badgeKind = "new",
                 badge  = function()
                     return CurrentVersionHasNewUnseenSettings() and "new"
                 end },
    shop     = { text = L("BLIZZARD_STORE", "Shop"), default = true,
                 action = Func("ToggleStoreUI", function() ToggleStoreUI() end),
                 shown  = function() return C_StorePublic and C_StorePublic.IsEnabled and C_StorePublic.IsEnabled() end,
                 badge  = AlertBadge(Alerts.Shop) },
    addons   = { text = L("ADDONS", "AddOns"), default = true,
                 action = Func("AddonList", function() ShowUIPanel(AddonList) end) },
    editmode = { text = L("HUD_EDIT_MODE_MENU", "Edit Mode"), default = true, action = Macro("/editmode"),
                 shown  = function() return EditModeManagerFrame and EditModeManagerFrame:CanEnterEditMode() end,
                 badge  = function()
                     local tutorial = EditModeManagerFrame and EditModeManagerFrame.Tutorial
                     return tutorial and tutorial:HasHelptipsToShow() and "alert"
                 end },
    support  = { text = L("GAMEMENU_SUPPORT", "Support"), default = true,
                 action = Func("ToggleHelpFrame", function() ToggleHelpFrame() end),
                 badge  = AlertBadge(Alerts.Ticket) },
    macros   = { text = L("MACROS", "Macros"), default = true, action = Macro("/macro") },
    reload   = { text = "Reload UI", default = true, action = Macro("/reload") },
    logout   = { text = L("LOG_OUT", "Log Out"), default = true, action = Macro("/logout") },
    exit     = { text = L("EXIT_GAME", "Exit Game"), default = true, action = Macro("/quit") },
    volume   = { text = "Volume", widget = true, action = function() return { volume = true } end },
    latency  = { text = "Latency", widget = true, action = function() return { latency = true } end },
    blizzard = { text = "Blizzard Menu", default = true, action = Func(nil, ShowBlizzardMenu) },
    -- optional: without it the menu shows a close X by the gear
    close    = { text = L("RETURN_TO_GAME", "Return to Game"), default = true, action = Func(nil, function() end) },
}

-- Widgets: added from edit mode (Add Widget), never in Unused. In the order Add Widget lists them
local WIDGETS = { "volume", "latency" }

--------------------------------------------------
-- Layout: which buttons go in which category
--
-- AlniMenuDB.layout is a list of categories, left to right; each is a column in the menu:
--   name   heading over the column (and over its settings checkboxes)
--   items  button keys, top to bottom
--   gaps   { [key] = true } for a gap above that button, as between
--          the Game Menu's groups
-- Buttons in no category are unused. The editor (Editor.lua) changes it; DEFAULT_LAYOUT is where it starts and what
-- Reset goes back to.
--------------------------------------------------

local DEFAULT_LAYOUT = {
    { name = "Character",
      items = { "character", "spellbook", "talents",
                "professions", "profession1", "profession2", "achievements" },
      gaps  = { professions = true } },
    { name = "Game Menu", fixed = true,
      items = { "options", "shop", "addons", "editmode", "support", "macros", "reload",
                "logout", "exit", "blizzard", "close" },
      gaps  = { addons = true, logout = true, blizzard = true },
      off   = { shop = true, reload = true, close = true } },
    { name = "Social",    items = { "guild", "groupfinder", "pvp" } },
    { name = "Adventure",
      items = { "questlog", "adventure", "calendar", "housing", "mounts", "appearances" },
      gaps  = { housing = true } },
}

-- Just the game's own Game Menu. What a new install starts with
local ORIGINAL_LAYOUT = {
    { name = "Game Menu", fixed = true,
      items = { "options", "shop", "addons", "editmode", "support", "macros",
                "logout", "exit", "close" },
      gaps  = { addons = true, logout = true, close = true } },
}

-- The layouts the settings page can load
local LAYOUTS = { default = DEFAULT_LAYOUT, original = ORIGINAL_LAYOUT }

-- The Game Menu category: always shown, never renamed or deleted
local GAME_MENU_NAME = L("MAINMENU_BUTTON", "Game Menu")

--- A fresh copy of `template` (default: DEFAULT_LAYOUT)
---@param template table?
---@return table
function ns.DefaultLayout(template)
    local layout = {}
    for i, category in ipairs(template or DEFAULT_LAYOUT) do
        local gaps = {}
        for key in pairs(category.gaps or {}) do
            gaps[key] = true
        end
        layout[i] = { name = category.fixed and GAME_MENU_NAME or category.name, fixed = category.fixed,
                      items = { unpack(category.items) }, gaps = gaps }
    end
    return layout
end

--- Switches on the buttons `template` places, except its `off` ones, and switches the rest off. Custom buttons keep
--- theirs.
---@param template table
local function SetButtonsFrom(template)
    local on = {}
    for _, category in ipairs(template) do
        for _, key in ipairs(category.items) do
            on[key] = not (category.off and category.off[key])
        end
    end
    for key, entry in pairs(ENTRIES) do
        if not entry.always and not entry.custom then
            AlniMenuDB.buttons[key] = on[key] or false
        end
    end
end

--- The Game Menu category of the saved layout
---@return table
local function GameMenuCategory()
    for _, category in ipairs(AlniMenuDB.layout) do
        if category.fixed then
            return category
        end
    end
    return AlniMenuDB.layout[1]
end

--- Whether `layout` has `key` in any category
---@param layout table
---@param key string
---@return boolean
local function InLayout(layout, key)
    for _, category in ipairs(layout) do
        for _, k in ipairs(category.items) do
            if k == key then
                return true
            end
        end
    end
    return false
end

--- Puts `key`, a button this layout has never had, where DEFAULT_LAYOUT has it: into the saved category of the same
--- name, after the button it follows by default; otherwise it stays unused
---@param layout table
---@param key string
local function PlaceNewButton(layout, key)
    for _, default in ipairs(DEFAULT_LAYOUT) do
        for j, k in ipairs(default.items) do
            if k == key then
                for _, category in ipairs(layout) do
                    if category.name == default.name then
                        local at = #category.items + 1
                        local before = default.items[j - 1]
                        for n, existing in ipairs(category.items) do
                            if existing == before then
                                at = n + 1
                            end
                        end
                        table.insert(category.items, at, key)
                        return
                    end
                end
                return
            end
        end
    end
end

--- Repairs AlniMenuDB.layout so the menu can trust it: makes one if missing, drops buttons this version does not know
--- or that appear twice, places buttons added since the layout was saved (AlniMenuDB.known lists the ones it has seen),
--- and puts the buttons that must always be there back into the first category if they went missing.
function ns.CheckLayout()
    local layout = AlniMenuDB.layout
    if type(layout) ~= "table" or #layout == 0 then
        AlniMenuDB.layout = ns.DefaultLayout(ORIGINAL_LAYOUT)
        SetButtonsFrom(ORIGINAL_LAYOUT)
        AlniMenuDB.known = {}
        for key in pairs(ENTRIES) do
            AlniMenuDB.known[key] = true
        end
        return
    end

    local placed = {}
    for _, category in ipairs(layout) do
        category.name   = tostring(category.name or "")
        category.gaps   = type(category.gaps) == "table" and category.gaps or {}
        category.hidden = category.hidden == true or nil
        local items = {}
        for _, key in ipairs(type(category.items) == "table" and category.items or {}) do
            if ENTRIES[key] and not placed[key] then
                placed[key] = true
                table.insert(items, key)
            end
        end
        category.items = items
    end

    -- layouts saved before AlniMenuDB.known existed: what they have is known
    if type(AlniMenuDB.known) ~= "table" then
        AlniMenuDB.known = {}
        for key in pairs(placed) do
            AlniMenuDB.known[key] = true
        end
    end
    -- in DEFAULT_LAYOUT's order, so each new button finds the one it follows already placed
    local order, seen = {}, {}
    for _, default in ipairs(DEFAULT_LAYOUT) do
        for _, key in ipairs(default.items) do
            table.insert(order, key)
            seen[key] = true
        end
    end
    for key in pairs(ENTRIES) do
        if not seen[key] then
            table.insert(order, key)
        end
    end
    for _, key in ipairs(order) do
        if ENTRIES[key] and not placed[key] and not AlniMenuDB.known[key] then
            PlaceNewButton(layout, key)
        end
        AlniMenuDB.known[key] = true
    end

    -- exactly one Game Menu category: the one marked, else the one named so, else the one with Blizzard Menu, else the
    -- first
    local fixed
    for _, category in ipairs(layout) do
        if not fixed and category.fixed then
            fixed = category
        end
    end
    for _, category in ipairs(layout) do
        if not fixed and (category.name == GAME_MENU_NAME or category.name == "Game Menu") then
            fixed = category
        end
    end
    for _, category in ipairs(layout) do
        for _, key in ipairs(category.items) do
            if not fixed and key == "blizzard" then
                fixed = category
            end
        end
    end
    fixed = fixed or layout[1]
    for _, category in ipairs(layout) do
        category.fixed = nil
    end
    fixed.fixed, fixed.name, fixed.hidden = true, GAME_MENU_NAME, nil

    for key, entry in pairs(ENTRIES) do
        if entry.always and not placed[key] and not InLayout(layout, key) then
            table.insert(fixed.items, key)
        end
    end

    -- separators only exist in a category
    for key, entry in pairs(ENTRIES) do
        if entry.separator and not InLayout(layout, key) then
            AlniMenuDB.separators[entry.separator] = nil
            ns.RemoveEntry(key)
        end
    end

    -- unused buttons are off
    if type(AlniMenuDB.buttons) == "table" then
        for key, entry in pairs(ENTRIES) do
            if not entry.always and not InLayout(layout, key) then
                AlniMenuDB.buttons[key] = false
            end
        end
    end
end

--- The buttons in no category, sorted by label
---@return string[]
function ns.UnusedKeys()
    local placed = {}
    for _, category in ipairs(AlniMenuDB.layout) do
        for _, key in ipairs(category.items) do
            placed[key] = true
        end
    end
    local unused = {}
    for key, entry in pairs(ENTRIES) do
        if not placed[key] and not entry.widget then
            table.insert(unused, key)
        end
    end
    table.sort(unused, function(a, b) return ns.Label(a) < ns.Label(b) end)
    return unused
end

ns.ENTRIES = ENTRIES
for key, entry in pairs(ENTRIES) do
    entry.key = key
end

--- What `key`'s button says: the player's own name for it if they renamed it (AlniMenuDB.labels; not custom buttons,
--- whose label is part of them), otherwise its own label
---@param key string
---@return string
function ns.Label(key)
    local entry = ENTRIES[key]
    if not entry then
        return ""
    end
    local renamed = not entry.custom and AlniMenuDB.labels and AlniMenuDB.labels[key]
    if renamed then
        return renamed
    end
    -- a profession button is named after the profession learned there
    local name = entry.profession and entry.profession()
    return name or entry.text
end

--------------------------------------------------
-- Custom buttons
--
-- AlniMenuDB.custom[id] = { text = label, macro = macro text }, made in edit mode (Custom.lua). Each is the catalog
-- entry "custom<id>": a secure button running the macro, like Log Out runs /logout.
--------------------------------------------------

function ns.CustomKey(id)
    return "custom" .. id
end

--- Adds (or refreshes) custom button `id` in the catalog
---@param id integer
---@return string
---@return table
function ns.AddCustomEntry(id)
    local data = AlniMenuDB.custom[id]
    local key = ns.CustomKey(id)
    local entry = ENTRIES[key] or { custom = id, key = key }
    entry.text = data.text
    entry.action = function() return { macro = AlniMenuDB.custom[id].macro } end
    ENTRIES[key] = entry
    return key, entry
end

--- Catalog entries for every saved custom button; before the layout is checked, so it keeps them
function ns.LoadCustomEntries()
    for id in pairs(AlniMenuDB.custom) do
        ns.AddCustomEntry(id)
    end
end

--------------------------------------------------
-- Separators
--
-- AlniMenuDB.separators[id] = true, added from Add Widget. Each is the widget "separator<id>", so there can be any
-- number of them.
--------------------------------------------------

function ns.AddSeparatorEntry(id)
    local key = "separator" .. id
    ENTRIES[key] = ENTRIES[key] or {
        key = key, separator = id, widget = true, text = "Separator", rowHeight = SEPARATOR_H,
        action = function() return { separator = true } end,
    }
    return key
end

function ns.LoadSeparatorEntries()
    for id in pairs(AlniMenuDB.separators) do
        ns.AddSeparatorEntry(id)
    end
end

--- Whether the player has `key` switched on
---@param key string
---@return boolean
function ns.IsEnabled(key)
    local entry = ENTRIES[key]
    if entry.always then
        return true
    end
    local saved = AlniMenuDB.buttons and AlniMenuDB.buttons[key]
    if saved == nil then
        return entry.default and true or false
    end
    return saved
end

--------------------------------------------------
-- Window
--------------------------------------------------

local menu

-- The debug view (the bug icon, only with DEBUG on in Core.lua): every button, every marker a button can show, and what
-- each button is
local debugView = false

--- The master volume slider: a row the size of a button
---@param entry table
---@param action table
---@return Frame
local function CreateVolumeSlider(entry, action)
    local b = CreateFrame("Frame", nil, menu)
    b:SetSize(BUTTON_W, BUTTON_H)
    b.action = action

    local function Volume()
        return math.floor((tonumber(GetCVar("Sound_MasterVolume")) or 0) * 100 + 0.5)
    end
    local slider = ns.Lib:CreateSlider(b, {
        width = BUTTON_W - 40,
        value = Volume(),
        onChange = function(value)
            value = math.floor(value + 0.5)
            -- also called while the slider is made and on every show
            if value ~= Volume() then
                SetCVar("Sound_MasterVolume", value / 100)
            end
            if b.name then
                b.label:SetText(b.name .. " " .. value .. "%")
            end
        end,
    })
    slider:SetPoint("TOP", 0, -2)
    b.label = slider.label
    b.name = ns.Label(entry.key)

    -- what the layout and edit mode use on buttons
    function b:SetText(text)
        self.name = text
        self.label:SetText(text .. " " .. Volume() .. "%")
    end
    function b:GetFontString()
        return self.label
    end
    b:SetText(b.name)

    -- the volume may have changed since the menu last showed
    b:SetScript("OnShow", function() slider:SetValue(Volume()) end)
    return b
end

--- Home and world latency, as the micro menu's tooltip shows them
---@param entry table
---@param action table
---@return Frame
local function CreateLatency(entry, action)
    local b = CreateFrame("Frame", nil, menu)
    b:SetSize(BUTTON_W, BUTTON_H)
    b.action = action
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.label:SetPoint("CENTER")

    local function Color(ms)
        if ms < (PERFORMANCEBAR_LOW_LATENCY or 300) then
            return "|cff00ff00"
        end
        if ms < (PERFORMANCEBAR_MEDIUM_LATENCY or 600) then
            return "|cffffff00"
        end
        return "|cffff0000"
    end
    local function Update()
        local _, _, home, world = GetNetStats()
        b.label:SetText(b.name .. " " .. Color(home) .. home .. "|r / " .. Color(world) .. world .. "|r ms")
    end

    function b:SetText(text)
        self.name = text
        Update()
    end
    function b:GetFontString()
        return self.label
    end
    b:SetText(ns.Label(entry.key))

    -- every second while the menu is open
    b:SetScript("OnShow", function()
        Update()
        b.ticker = C_Timer.NewTicker(1, Update)
    end)
    b:SetScript("OnHide", function()
        if b.ticker then
            b.ticker:Cancel()
        end
        b.ticker = nil
    end)
    ns.Lib:AddTooltip(b, function()
        return ns.Label(entry.key), "Home: chat, friends and addons.\nWorld: combat and everything around you."
    end)
    return b
end

--- A line across the column
---@param entry table
---@param action table
---@return Frame
local function CreateSeparatorRow(entry, action)
    local b = CreateFrame("Frame", nil, menu)
    b:SetSize(BUTTON_W, SEPARATOR_H)
    b.action = action
    local line = ns.Lib:CreateSeparator(b, { color = { 0.8, 0.7, 0.4, 0.6 } })
    line:ClearAllPoints()
    line:SetPoint("LEFT", 12, 0)
    line:SetPoint("RIGHT", -12, 0)

    -- what the layout and edit mode use on buttons
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    function b:SetText()
    end
    function b:GetFontString()
        return self.label
    end
    return b
end

--- Makes the button for `entry`, the way its action needs; nil when this client cannot do it
---@param entry table
---@return Button?
local function CreateMenuButton(entry)
    local action = entry.action()
    if not action then
        return nil
    end
    if action.separator then
        return CreateSeparatorRow(entry, action)
    end
    if action.volume then
        return CreateVolumeSlider(entry, action)
    end
    if action.latency then
        return CreateLatency(entry, action)
    end

    local b
    if action.click or action.macro or action.spell then
        b = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate, " .. BUTTON_TEMPLATE)
        if action.click then
            b:SetAttribute("type", "click")
            b:SetAttribute("clickbutton", action.click)
        elseif action.spell then
            -- the spell itself is set each time the menu is laid out
            b:SetAttribute("type", "spell")
        else
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", action.macro)
        end
        -- once, on release, on every client
        b:SetAttribute("useOnKeyDown", false)
        b:RegisterForClicks("AnyUp")
        b:HookScript("PostClick", function() ns.HideMenu() end)
    else
        b = CreateFrame("Button", nil, menu, BUTTON_TEMPLATE)
        b:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            ns.HideMenu()
            action.func()
        end)
    end
    b:SetSize(BUTTON_W, BUTTON_H)
    b:SetText(ns.Label(entry.key))
    b.action = action
    -- the reason for an alert badge, when it has one
    ns.Lib:AddTooltip(b, function()
        if debugView then
            return ns.Label(entry.key), b.debugText
        end
        return b.alertText
    end)
    return b
end

--- Makes the button for catalog entry `key` if the menu is built and it has none yet, or brings a custom button's label
--- and macro up to date. Out of combat only: the buttons are secure.
---@param key string
function ns.RefreshEntryButton(key)
    local entry = ENTRIES[key]
    if not menu or not entry then
        return
    end
    if not entry.button then
        entry.button = CreateMenuButton(entry)
    elseif entry.custom then
        entry.button:SetAttribute("macrotext", AlniMenuDB.custom[entry.custom].macro)
        entry.button.action.macro = AlniMenuDB.custom[entry.custom].macro
    end
    if entry.button then
        entry.button:SetText(ns.Label(key))
    end
    if entry.editBar then
        entry.editBar.label:SetText(ns.Label(key))
    end
end

--- Takes a deleted custom button out of the catalog and the menu
---@param key string
function ns.RemoveEntry(key)
    local entry = ENTRIES[key]
    if not entry then
        return
    end
    if entry.button then
        entry.button:Hide()
    end
    if entry.editBar then
        entry.editBar:Hide()
    end
    for _, category in ipairs(AlniMenuDB.layout) do
        for j = #category.items, 1, -1 do
            if category.items[j] == key then
                table.remove(category.items, j)
            end
        end
        category.gaps[key] = nil
    end
    ENTRIES[key] = nil
end

--- Shows the mark entry.badge asks for on its button, made the way the Game Menu makes them (GameMenuFrame.xml), or
--- hides it
---@param entry table
local function UpdateBadge(entry)
    local b = entry.button
    local badge, reason
    if entry.badge then
        badge, reason = entry.badge()
    end
    -- and whatever else a micro button it clicks shows its dot for
    local micro = b.action.click
    if not badge and micro and micro.NotificationOverlay and micro.NotificationOverlay:IsShown() then
        badge = "alert"
    end
    b.alertText = badge == "alert" and reason or nil

    if debugView then
        -- what the button is and does, and what it would mark itself with
        local action = b.action
        local how = action.click and ("clicks " .. (action.click:GetName() or "a Blizzard button"))
            or action.macro and ("runs " .. action.macro:gsub("\n", " / "))
            or action.spell and ("casts spell " .. tostring(b:GetAttribute("spell")))
            or "calls a Blizzard function"
        local lines = {
            "key: " .. entry.key,
            how,
            "switched on: " .. tostring(ns.IsEnabled(entry.key)),
            "applies now: " .. tostring(not entry.shown or entry.shown() and true or false),
            "marker now: " .. (badge or "none") .. (reason and (" (" .. reason .. ")") or ""),
        }
        b.debugText = table.concat(lines, "\n")
        -- show the marker it can have: its own kind, or the alert dot for a micro button's dot
        local canMark = entry.badge or (micro and micro.NotificationOverlay)
        if canMark and not badge then
            badge = entry.badgeKind or "alert"
        end
    end

    if badge == "new" and not b.newLabel then
        b.newLabel = CreateFrame("Frame", nil, b, "NewFeatureLabelTemplate")
        b.newLabel:SetScale(0.8)
        b.newLabel:SetPoint("BOTTOMRIGHT", b:GetFontString(), "LEFT", 16, -10)
    elseif badge == "alert" and not b.alert then
        b.alert = CreateFrame("Frame", nil, b)
        b.alert:SetSize(21, 21)
        b.alert:SetPoint("TOPLEFT", b, "TOPLEFT", -5, 5)
        b.alert:SetFrameLevel(b:GetFrameLevel() + 10)
        local icon = b.alert:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        icon:SetAtlas("UI-HUD-MicroMenu-Communities-Icon-Notification")
    end
    if b.newLabel then
        b.newLabel:SetShown(badge == "new")
    end
    if b.alert then
        b.alert:SetShown(badge == "alert")
    end
end

--- Whether the button for `key` shows right now: made, switched on, and its `shown` check (if any) passing. Not whether
--- a micro button it clicks is enabled: Blizzard disables them all while the Game Menu or the Settings panel is open,
--- and AlniMenu opens at the moment the Game Menu shows. They are enabled again by the time a button is clicked.
---@param key string
---@return boolean
local function IsShown(key)
    local entry = ENTRIES[key]
    if not (entry.button and ns.IsEnabled(key)) then
        return false
    end
    if entry.shown and not entry.shown() then
        return false
    end
    return true
end

--------------------------------------------------
-- Edit mode
--
-- The gear in the corner switches the menu into edit mode: every button this client has shows, switched on or not, each
-- covered by a bar of controls (the bar also keeps clicks from reaching the button, so nothing runs while editing).
-- Column headings become name boxes, an Unused column lists the buttons in no category, and a row along the bottom adds
-- a category, resets the layout or finishes. Every change is saved to AlniMenuDB at once.
--------------------------------------------------

local editing = false
local Layout, HasShownIn   -- below; the edit controls lay the menu out again

-- Edit mode changes AlniMenuDB as it goes. This is how it was when edit mode started (or when a layout was loaded from
-- the settings), put back unless edit mode ends with Done.
local saved
local refreshButtons = false   -- buttons to bring up to date out of combat

local function Copy(t)
    if type(t) ~= "table" then
        return t
    end
    local c = {}
    for k, v in pairs(t) do
        c[k] = Copy(v)
    end
    return c
end

local function Snapshot()
    saved = {
        layout     = Copy(AlniMenuDB.layout),
        buttons    = Copy(AlniMenuDB.buttons),
        labels     = Copy(AlniMenuDB.labels),
        custom     = Copy(AlniMenuDB.custom),
        nextCustom = AlniMenuDB.nextCustom,
        separators    = Copy(AlniMenuDB.separators),
        nextSeparator = AlniMenuDB.nextSeparator,
    }
end

local function RefreshButtons()
    refreshButtons = false
    for key in pairs(ENTRIES) do
        ns.RefreshEntryButton(key)
    end
end

local function Discard()
    if not saved then
        return
    end
    if ns.HideCustomWindow then
        ns.HideCustomWindow()
    end
    -- custom buttons made while editing go; deleted ones come back
    for key, entry in pairs(ENTRIES) do
        if entry.custom and not saved.custom[entry.custom] then
            ns.RemoveEntry(key)
        end
        if entry.separator and not saved.separators[entry.separator] then
            ns.RemoveEntry(key)
        end
    end
    AlniMenuDB.layout     = saved.layout
    AlniMenuDB.buttons    = saved.buttons
    AlniMenuDB.labels     = saved.labels
    AlniMenuDB.custom     = saved.custom
    AlniMenuDB.nextCustom = saved.nextCustom
    AlniMenuDB.separators    = saved.separators
    AlniMenuDB.nextSeparator = saved.nextSeparator
    saved = nil
    ns.LoadCustomEntries()
    ns.LoadSeparatorEntries()
    -- secure buttons: only out of combat
    if InCombatLockdown() then
        refreshButtons = true
    else
        RefreshButtons()
    end
end
local DoLayout

local ICON = {
    up     = "Interface\\Buttons\\Arrow-Up-Up",
    down   = "Interface\\Buttons\\Arrow-Down-Up",
    left   = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    right  = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    gap    = "Interface\\Buttons\\UI-PlusButton-Up",
    nogap  = "Interface\\Buttons\\UI-MinusButton-Up",
    delete = "Interface\\Buttons\\UI-StopButton",
    gear   = "Interface\\Buttons\\UI-OptionsButton",
    edit   = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
}

--- A small icon button with a tooltip
---@param parent Frame
---@param icon string
---@param size number
---@param tooltip string
---@param onClick function
---@return Button
local function IconButton(parent, icon, size, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    ns.Lib:AddTooltip(b, tooltip)
    return b
end

--- Enables `b`, or greys it out
---@param b Button
---@param usable boolean
local function SetUsable(b, usable)
    b:SetEnabled(usable)
    b:SetAlpha(usable and 1 or 0.3)
end

--- Where `key` is: its category's index and its place in it (nil, nil when unused)
---@param key string
---@return integer?
---@return integer?
local function Find(key)
    for i, category in ipairs(AlniMenuDB.layout) do
        for j, k in ipairs(category.items) do
            if k == key then
                return i, j
            end
        end
    end
end

local function Changed()
    Layout()
end

--- Moves `key` up (-1) or down (+1) in its column
---@param key string
---@param delta integer
local function MoveVertical(key, delta)
    local i, j = Find(key)
    if not i then
        return
    end
    local items = AlniMenuDB.layout[i].items
    local to = j + delta
    if to < 1 or to > #items then
        return
    end
    items[j], items[to] = items[to], items[j]
    Changed()
end

--- Moves `key` to the next column left (-1) or right (+1); right of the last category is Unused
---@param key string
---@param delta integer
local function MoveColumn(key, delta)
    local layout = AlniMenuDB.layout
    local i, j = Find(key)
    local from = i or (#layout + 1)
    local to = from + delta
    if to < 1 or to > #layout + 1 then
        return
    end
    if to > #layout and (ENTRIES[key].always or ENTRIES[key].widget) then  -- must stay in the menu
        return
    end

    if i then
        table.remove(layout[i].items, j)
        layout[i].gaps[key] = nil
    end
    if to <= #layout then
        table.insert(layout[to].items, key)
    end
    -- unused buttons are off; out of Unused, on
    if not i or to > #layout then
        AlniMenuDB.buttons[key] = to <= #layout
    end
    Changed()
end

local function ToggleGap(key)
    local i = Find(key)
    if not i then
        return
    end
    local gaps = AlniMenuDB.layout[i].gaps
    gaps[key] = not gaps[key] or nil
    Changed()
end

local function MoveCategory(i, delta)
    local layout = AlniMenuDB.layout
    local to = i + delta
    if to < 1 or to > #layout then
        return
    end
    layout[i], layout[to] = layout[to], layout[i]
    Changed()
end

--- Deletes category `i`; its buttons become unused, except the ones that must stay, which go to the first category left
---@param i integer
local function DeleteCategory(i)
    local layout = AlniMenuDB.layout
    if #layout <= 1 or layout[i].fixed then
        return
    end
    local removed = table.remove(layout, i)
    for _, key in ipairs(removed.items) do
        if ENTRIES[key].always then
            table.insert(GameMenuCategory().items, key)
        else
            AlniMenuDB.buttons[key] = false   -- now unused
        end
    end
    Changed()
end

--- Shows or hides category `i` in the menu (not the Game Menu one)
---@param i integer
---@param shown boolean
local function SetCategoryShown(i, shown)
    local category = AlniMenuDB.layout[i]
    if not category or category.fixed then
        return
    end
    category.hidden = not shown or nil
    Changed()
end

local function AddCategory()
    table.insert(AlniMenuDB.layout, { name = "New Category", items = {}, gaps = {} })
    Changed()
end

--- Puts widget `key` at the end of the Game Menu category, switched on
---@param key string
local function AddWidget(key)
    table.insert(GameMenuCategory().items, key)
    AlniMenuDB.buttons[key] = true
    Changed()
end

--- Adds a new separator at the end of the Game Menu category
local function AddSeparator()
    local id = AlniMenuDB.nextSeparator
    AlniMenuDB.nextSeparator = id + 1
    AlniMenuDB.separators[id] = true
    local key = ns.AddSeparatorEntry(id)
    ns.RefreshEntryButton(key)
    AddWidget(key)
end

--- Takes widget `key` out of the menu; Add Widget offers it again. A separator is deleted.
---@param key string
local function RemoveWidget(key)
    local entry = ENTRIES[key]
    if entry and entry.separator then
        AlniMenuDB.separators[entry.separator] = nil
        AlniMenuDB.buttons[key] = nil
        ns.RemoveEntry(key)
        Changed()
        return
    end
    local i, j = Find(key)
    if not i then
        return
    end
    table.remove(AlniMenuDB.layout[i].items, j)
    AlniMenuDB.layout[i].gaps[key] = nil
    AlniMenuDB.buttons[key] = false
    Changed()
end

--- The Add Widget list: widgets this client has that are not in the menu
---@param owner Frame
local function ShowWidgetMenu(owner)
    local available = {}
    for _, key in ipairs(WIDGETS) do
        if ENTRIES[key].button and not Find(key) then
            table.insert(available, key)
        end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        if available[1] then
            AddWidget(available[1])
        else
            AddSeparator()
        end
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, key in ipairs(available) do
            root:CreateButton(ns.Label(key), function() AddWidget(key) end)
        end
        -- any number of these
        root:CreateButton("Separator", AddSeparator)
    end)
end

--- Load Layout: the layouts the settings page offers too, after asking
---@param owner Frame
local function ShowLayoutMenu(owner)
    local function Ask(label, data)
        StaticPopup_Show("ALNIMENU_LOAD_LAYOUT", label, nil, data)
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return Ask("Default", { name = "default" })
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateButton("Default", function() Ask("Default", { name = "default" }) end)
        root:CreateButton("Original", function() Ask("Original", { name = "original" }) end)
        if #AlniMenuDB.layouts > 0 then
            root:CreateDivider()
        end
        for _, saved in ipairs(AlniMenuDB.layouts) do
            local name = saved.name
            local sub = root:CreateButton(name)
            sub:CreateButton("Load", function() Ask(name, { saved = name }) end)
            sub:CreateButton(DELETE or "Delete", function()
                StaticPopup_Show("ALNIMENU_DELETE_LAYOUT", name, nil, name)
            end)
        end
    end)
end

--- The bar of controls over `entry`'s button, made on first use
---@param key string
---@return Frame
local function EditBar(key)
    local entry = ENTRIES[key]
    if entry.editBar then
        return entry.editBar
    end

    local bar = CreateFrame("Frame", nil, menu)
    bar:SetAllPoints(entry.button)
    bar:SetFrameLevel(entry.button:GetFrameLevel() + 5)
    bar:EnableMouse(true)   -- keeps clicks off the button underneath

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(0, 0, 0, 0.75)

    if not entry.always then
        bar.check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
        bar.check:SetSize(24, 24)
        bar.check:SetPoint("LEFT", 6, 0)
        bar.check:SetScript("OnClick", function(self)
            AlniMenuDB.buttons[key] = self:GetChecked() and true or false
            Changed()
        end)
        ns.Lib:AddTooltip(bar.check, "Show in the menu")
    end

    -- right to left
    bar.right = IconButton(bar, ICON.right, 18, "Move to the next column", function() MoveColumn(key, 1) end)
    bar.right:SetPoint("RIGHT", -8, 0)
    bar.left  = IconButton(bar, ICON.left, 18, "Move to the previous column", function() MoveColumn(key, -1) end)
    bar.left:SetPoint("RIGHT", bar.right, "LEFT", 0, 0)
    bar.down  = IconButton(bar, ICON.down, 14, "Move down", function() MoveVertical(key, 1) end)
    bar.down:SetPoint("RIGHT", bar.left, "LEFT", -2, 0)
    bar.up    = IconButton(bar, ICON.up, 14, "Move up", function() MoveVertical(key, -1) end)
    bar.up:SetPoint("RIGHT", bar.down, "LEFT", -2, 0)
    bar.gap   = IconButton(bar, ICON.gap, 14, "Gap above: a space between this button and the one above",
        function() ToggleGap(key) end)
    bar.gap:SetPoint("RIGHT", bar.up, "LEFT", -4, 0)

    -- custom buttons: edit or delete; widgets: remove; the others: rename
    if entry.widget then
        bar.edit = IconButton(bar, ICON.delete, 16, "Remove this widget", function() RemoveWidget(key) end)
    else
        bar.edit = IconButton(bar, ICON.edit, 16,
            entry.custom and "Edit or delete this button" or "Rename this button",
            function()
                if entry.custom then
                    ns.EditCustomButton(key)
                else
                    ns.RenameButton(key)
                end
            end)
    end
    bar.edit:SetPoint("RIGHT", bar.gap, "LEFT", -4, 0)
    local leftmost = bar.edit
    if entry.custom then
        bar.delete = IconButton(bar, ICON.delete, 16, "Delete this button", function() ns.DeleteCustomButton(key) end)
        bar.delete:SetPoint("RIGHT", bar.edit, "LEFT", -4, 0)
        leftmost = bar.delete
    end

    -- small, to fit beside the controls; the full name in a tooltip when it is cut off with "..."
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 32, 0)
    bar.label:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWordWrap(false)
    bar.label:SetText(ns.Label(key))
    ns.Lib:AddTooltip(bar, function()
        if bar.label:IsTruncated() then
            return ns.Label(key)
        end
    end)

    entry.editBar = bar
    return bar
end

--- Brings `key`'s bar up to date with where it is now
---@param key string
---@param column integer
---@param index integer
---@param count integer
---@param unused boolean
local function UpdateEditBar(key, column, index, count, unused)
    local entry = ENTRIES[key]
    local bar = EditBar(key)
    local layout = AlniMenuDB.layout
    local enabled = ns.IsEnabled(key)

    if bar.check then
        bar.check:SetChecked(enabled and not unused)
        SetUsable(bar.check, not unused)
    end
    bar.label:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
    bar.label:SetText(ns.Label(key))
    SetUsable(bar.up, not unused and index > 1)
    SetUsable(bar.down, not unused and index < count)
    SetUsable(bar.left, column > 1)
    SetUsable(bar.right, not unused and not (column == #layout and (entry.always or entry.widget)))
    bar.gap:SetShown(not unused)
    local gap = not unused and layout[column].gaps[key]
    bar.gap:SetNormalTexture(gap and ICON.nogap or ICON.gap)
    bar:Show()
end

--- The heading over edit column `i`: a name box and column controls for a category, a plain label for Unused. Made on
--- first use.
---@param i integer
---@return Frame
local function EditHeading(i)
    menu.editHeadings = menu.editHeadings or {}
    local head = menu.editHeadings[i]
    if head then
        return head
    end

    head = CreateFrame("Frame", nil, menu)
    head:SetSize(EDIT_W, 26)

    head.show = CreateFrame("CheckButton", nil, head, "UICheckButtonTemplate")
    head.show:SetSize(24, 24)
    head.show:SetPoint("LEFT", 0, 0)
    head.show:SetScript("OnClick", function(self) SetCategoryShown(head.index, self:GetChecked()) end)
    ns.Lib:AddTooltip(head.show, "Show in the menu")

    head.name = ns.Lib:CreateEditBox(head, {
        width          = EDIT_W - 100,
        maxLetters     = 32,
        onEnterPressed = function(text)
            local category = AlniMenuDB.layout[head.index]
            if category and not category.fixed and text ~= "" then
                category.name = text
            end
            Changed()
        end,
    })
    head.name:SetPoint("LEFT", 30, 0)
    -- leaving the box keeps what was typed, like pressing Enter
    head.name:HookScript("OnEditFocusLost", function(self)
        local category = AlniMenuDB.layout[head.index]
        if category and not category.fixed and self:GetText() ~= "" and self:GetText() ~= category.name then
            category.name = self:GetText()
            Changed()
        end
    end)

    head.delete = IconButton(head, ICON.delete, 16, "Delete this category (its buttons become unused)",
        function() DeleteCategory(head.index) end)
    head.delete:SetPoint("RIGHT", -4, 0)
    head.right = IconButton(head, ICON.right, 18, "Move this column right",
        function() MoveCategory(head.index, 1) end)
    head.right:SetPoint("RIGHT", head.delete, "LEFT", -2, 0)
    head.left = IconButton(head, ICON.left, 18, "Move this column left",
        function() MoveCategory(head.index, -1) end)
    head.left:SetPoint("RIGHT", head.right, "LEFT", 0, 0)

    head.label = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head.label:SetPoint("CENTER")

    -- the Game Menu category's name, which can't be changed
    head.fixedName = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head.fixedName:SetPoint("LEFT", 8, 0)

    menu.editHeadings[i] = head
    return head
end

-- The row along the bottom in edit mode, made on first use Along the bottom in edit mode: adding things on the left,
-- then loading a layout and leaving edit mode on the right
local FOOTER_W = 120
local FOOTER_MIN = 7 * FOOTER_W + 4 * 8 + 2 * 24   -- the narrowest it fits in

local function EditFooter()
    if menu.editFooter then
        return menu.editFooter
    end
    local footer = CreateFrame("Frame", nil, menu)
    footer:SetSize(FOOTER_MIN, 24)

    local addButton = ns.Lib:CreateButton(footer, {
        text        = "Add Button",
        width       = FOOTER_W,
        onClick     = function() ns.EditCustomButton(nil) end,
        tooltip     = "Add Button",
        tooltipText = "A button of your own that runs a macro.",
    })
    addButton:SetPoint("LEFT")
    local addWidget
    addWidget = ns.Lib:CreateButton(footer, {
        text        = "Add Widget",
        width       = FOOTER_W,
        onClick     = function() ShowWidgetMenu(addWidget) end,
        tooltip     = "Add Widget",
        tooltipText = "Something other than a button, like a volume slider.",
    })
    addWidget:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    local add = ns.Lib:CreateButton(footer, { text = "Add Category", width = FOOTER_W, onClick = AddCategory })
    add:SetPoint("LEFT", addWidget, "RIGHT", 8, 0)

    local done = ns.Lib:CreateButton(footer, {
        text    = "Done",
        width   = FOOTER_W,
        onClick = function() ns.SetEditing(false, true) end,
    })
    done:SetPoint("RIGHT")
    local cancel = ns.Lib:CreateButton(footer, {
        text        = CANCEL or "Cancel",
        width       = FOOTER_W,
        onClick     = function() ns.SetEditing(false) end,
        tooltip     = CANCEL or "Cancel",
        tooltipText = "Leaves edit mode without saving the changes.",
    })
    cancel:SetPoint("RIGHT", done, "LEFT", -8, 0)
    local load
    load = ns.Lib:CreateButton(footer, {
        text        = "Load Layout",
        width       = FOOTER_W,
        onClick     = function() ShowLayoutMenu(load) end,
        tooltip     = "Load Layout",
        tooltipText = "Default, Original or one you saved. Replaces your layout.",
    })
    load:SetPoint("RIGHT", cancel, "LEFT", -24, 0)
    local save = ns.Lib:CreateButton(footer, {
        text        = "Save Layout",
        width       = FOOTER_W,
        onClick     = function() StaticPopup_Show("ALNIMENU_SAVE_LAYOUT") end,
        tooltip     = "Save Layout",
        tooltipText = "Saves the layout as it is now, to load from Load Layout.",
    })
    save:SetPoint("RIGHT", load, "LEFT", -8, 0)

    menu.editFooter = footer
    return footer
end

--------------------------------------------------
-- Laying it out
--------------------------------------------------

--- Places `keys` from `top` down at `x`, with a gap above those in `gaps` (unless nothing shows above them yet).
--- `visible(key)` decides which show. Returns the keys placed and how far down they reach.
---@param keys string[]
---@param gaps table
---@param visible function
---@param x number
---@param top number
---@return string[]
---@return number
local function LayoutColumn(keys, gaps, visible, x, top)
    local y = top
    local placed = {}
    for _, key in ipairs(keys) do
        local entry = ENTRIES[key]
        if visible(key) then
            if #placed > 0 and gaps[key] then
                y = y - SECTION_GAP
            end
            table.insert(placed, key)
            if entry.profession then
                -- the profession learned there may have changed
                local _, spellID = entry.profession()
                entry.button:SetAttribute("spell", spellID)
                entry.button:SetText(ns.Label(key))
            end
            -- widgets can be shorter, but not in edit mode, where the controls go
            local h = (not editing and entry.rowHeight) or BUTTON_H
            if entry.rowHeight then
                entry.button:SetHeight(h)
            end
            entry.button:ClearAllPoints()
            entry.button:SetPoint("TOPLEFT", menu, "TOPLEFT", x, y)
            entry.button:Show()
            y = y - h
        end
    end
    return placed, y
end

--- In edit mode every button this client has shows
---@param key string
---@return boolean
local function Exists(key)
    return ENTRIES[key].button ~= nil
end

--- Normal mode: one column per category with something to show, each under its name when there is more than one. Edit
--- mode: every category, then Unused, all with their controls. Fits the window to them. Out of combat only: some
--- buttons are secure.
function DoLayout()
    if not menu then
        return
    end

    -- start from nothing
    for _, entry in pairs(ENTRIES) do
        local b = entry.button
        if b then
            b:Hide()
            b:SetWidth(editing and EDIT_W or BUTTON_W)
            b:GetFontString():SetAlpha(editing and 0 or 1)
            -- badges are only updated outside edit mode
            if editing and b.newLabel then
                b.newLabel:Hide()
            end
            if editing and b.alert then
                b.alert:Hide()
            end
            if entry.widget then
                b:SetAlpha(editing and 0 or 1)
            end
        end
        if entry.editBar then
            entry.editBar:Hide()
        end
    end
    for _, heading in ipairs(menu.headings or {}) do
        heading:Hide()
    end
    for _, head in ipairs(menu.editHeadings or {}) do
        head:Hide()
    end
    if menu.editFooter then
        menu.editFooter:Hide()
    end
    menu.headings = menu.headings or {}

    local layout = AlniMenuDB.layout
    local columns = {}
    local hasReturn = false   -- Return to Game showing in the menu
    local hasBlizzard = false -- Blizzard Menu showing in the menu
    local showAll = editing or debugView   -- every category, and Unused
    for i, category in ipairs(layout) do
        if showAll or (not category.hidden and HasShownIn(category)) then
            table.insert(columns, { category = category, index = i })
        end
    end
    if showAll then
        -- Unused in as many columns as it takes to be no taller than the tallest category
        local rows = MIN_UNUSED_ROWS
        for _, column in ipairs(columns) do
            local n = 0
            for _, key in ipairs(column.category.items) do
                if Exists(key) then
                    n = n + 1
                end
            end
            rows = math.max(rows, n)
        end
        local unused = {}
        for _, key in ipairs(ns.UnusedKeys()) do
            if Exists(key) then
                table.insert(unused, key)
            end
        end
        local first = true
        repeat
            local chunk = {}
            for i = 1, rows do
                if #unused == 0 then
                    break
                end
                table.insert(chunk, table.remove(unused, 1))
            end
            table.insert(columns, { unused = true, first = first, items = chunk, index = #layout + 1 })
            first = false
        until #unused == 0
    end

    local headed = showAll or #columns > 1
    local headingH = editing and 32 or HEADING_H
    local top    = -TOP - (headed and headingH or 0)
    local bottom = top - (editing and BUTTON_H or 0)   -- empty columns still get a row

    local columnW = editing and EDIT_W or BUTTON_W
    for c, column in ipairs(columns) do
        local x = SIDE + (c - 1) * (columnW + COLUMN_GAP)
        local keys = column.unused and column.items or column.category.items
        local gaps = column.unused and {} or column.category.gaps

        if editing then
            local head = EditHeading(c)
            head.index = column.index
            head:ClearAllPoints()
            head:SetPoint("BOTTOMLEFT", menu, "TOPLEFT", x, top + 4)
            local fixed = not column.unused and column.category.fixed
            head.name:SetShown(not column.unused and not fixed)
            head.show:SetShown(not column.unused and not fixed)
            head.fixedName:SetShown(fixed and true or false)
            head.left:SetShown(not column.unused)
            head.right:SetShown(not column.unused)
            head.delete:SetShown(not column.unused and not fixed)
            head.label:SetShown(column.unused and true or false)
            if column.unused then
                head.label:SetText(column.first and "Unused" or "")
            elseif fixed then
                head.fixedName:SetText(column.category.name)
                SetUsable(head.left, column.index > 1)
                SetUsable(head.right, column.index < #layout)
            else
                if not head.name:HasFocus() then
                    head.name:SetText(column.category.name)
                end
                local shown = not column.category.hidden
                head.show:SetChecked(shown)
                head.name:SetTextColor(shown and 1 or 0.5, shown and 1 or 0.5, shown and 1 or 0.5)
                SetUsable(head.left, column.index > 1)
                SetUsable(head.right, column.index < #layout)
                SetUsable(head.delete, #layout > 1)
            end
            head:Show()
        elseif headed then
            local heading = menu.headings[c]
            if not heading then
                heading = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                menu.headings[c] = heading
            end
            heading:SetText(column.unused and (column.first and "Unused" or "") or column.category.name)
            heading:ClearAllPoints()
            heading:SetPoint("BOTTOM", menu, "TOPLEFT", x + BUTTON_W / 2, top + 4)
            heading:Show()
        end

        local placed, y = LayoutColumn(keys, gaps, showAll and Exists or IsShown, x, top)
        for i, key in ipairs(placed) do
            if editing then
                UpdateEditBar(key, column.index, i, #placed, column.unused)
            else
                UpdateBadge(ENTRIES[key])
                if key == "close" then
                    hasReturn = true
                end
                if key == "blizzard" then
                    hasBlizzard = true
                end
            end
        end
        bottom = math.min(bottom, y)
    end

    -- a close X by the gear when there is no Return to Game to click, and always while editing. Basic has a slot for it
    -- in its corner, so there it always shows. In Basic and Panel it goes where AlnUI puts its own
    local theme = menu:GetTheme()
    local cornerX = theme == "basic" or theme == "panel"
    local showX = theme == "basic" or editing or not hasReturn
    menu.closeX:SetShown(showX)
    menu.closeX:ClearAllPoints()
    if cornerX then
        menu.closeX:SetPoint("TOPRIGHT", 1, 0)
    else
        menu.closeX:SetPoint("TOPRIGHT", -6, -6)
    end
    -- the Blizzard Menu button by the gear, the same way: when the menu has no Blizzard Menu to click, and always while
    -- editing
    menu.blizz:SetShown(editing or not hasBlizzard)
    menu.gear:ClearAllPoints()
    if showX then
        menu.gear:SetPoint("RIGHT", menu.closeX, "LEFT", -2, 0)
    elseif cornerX then
        -- in the title bar
        menu.gear:SetPoint("TOPRIGHT", -6, -1)
    else
        menu.gear:SetPoint("TOPRIGHT", -12, -12)
    end

    local width = 2 * SIDE + #columns * columnW + (#columns - 1) * COLUMN_GAP
    if editing then
        local footer = EditFooter()
        width = math.max(width, FOOTER_MIN + 2 * SIDE)
        footer:SetWidth(width - 2 * SIDE)
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", menu, "TOPLEFT", SIDE, bottom - 16)
        footer:Show()
        bottom = bottom - 16 - 24
    end
    menu:SetSize(width, -bottom + BOTTOM)
end

--- DoLayout, saying in chat if it fails: WoW hides Lua errors unless scriptErrors is on, and a half-done layout leaves
--- buttons where they were before
function Layout()
    local ok, err = xpcall(DoLayout, function(e)
        return tostring(e) .. (debugstack and ("\n" .. debugstack(2, 4, 0)) or "")
    end)
    if not ok then
        print("|cff33ff99" .. ADDON_NAME .. ":|r layout error: " .. tostring(err))
    end
end

--- Whether any of `category`'s buttons shows right now
---@param category table
---@return boolean
HasShownIn = function(category)
    for _, key in ipairs(category.items) do
        if IsShown(key) then
            return true
        end
    end
    return false
end

--------------------------------------------------
-- Window
--------------------------------------------------

local function BuildMenu()
    menu = ns.Lib:CreateDialog({
        name          = "AlniMenuFrame",
        title         = L("MAINMENU_BUTTON", "Game Menu"),
        width         = BUTTON_W + 2 * SIDE,   -- fitted by Layout
        height        = 300,
        theme         = AlniMenuDB.theme,
        strata        = "DIALOG",
        noCloseButton = true,  -- as the Game Menu; its own close X is below
    })

    for _, entry in pairs(ENTRIES) do
        entry.button = CreateMenuButton(entry)
    end

    -- the gear: edit mode on and off
    local gear = IconButton(menu, ICON.gear, 20, "Edit layout", function() ns.SetEditing(not editing) end)
    gear:SetPoint("TOPRIGHT", -12, -12)
    gear:SetFrameLevel(menu:GetFrameLevel() + 20)
    menu.gear = gear

    -- the way out to the Game Menu, left of the gear (shown by Layout)
    local blizz = CreateFrame("Button", nil, menu)
    blizz:SetSize(16, 20)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-HUD-MicroMenu-GameMenu-Up") then
        blizz:SetNormalAtlas("UI-HUD-MicroMenu-GameMenu-Up")
        blizz:SetPushedAtlas("UI-HUD-MicroMenu-GameMenu-Down")
    else
        blizz:SetNormalTexture("Interface\\Buttons\\UI-MicroButton-MainMenu-Up")
        blizz:SetPushedTexture("Interface\\Buttons\\UI-MicroButton-MainMenu-Down")
    end
    blizz:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    blizz:SetPoint("RIGHT", gear, "LEFT", -4, 0)
    blizz:SetFrameLevel(menu:GetFrameLevel() + 20)
    blizz:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        ns.HideMenu()
        ShowBlizzardMenu()
    end)
    ns.Lib:AddTooltip(blizz, "Blizzard Menu")
    menu.blizz = blizz

    -- the close X, for when Return to Game is not in the menu
    local closeX = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    closeX:SetFrameLevel(menu:GetFrameLevel() + 20)
    closeX:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        ns.HideMenu()
    end)
    menu.closeX = closeX

    -- the debug view's switch, only while debugging (DEBUG in Core.lua)
    if ns.DEBUG then
        local bug = IconButton(menu, "Interface\\HelpFrAame\\HelpIcon-Bug", 22,
            "Debug view: every button and every marker", function()
                debugView = not debugView
                Layout()
            end)
        -- top-left corner, mirroring the gear (same center distance from the edges)
        bug:SetPoint("TOPLEFT", 11, -11)
        bug:SetFrameLevel(menu:GetFrameLevel() + 20)
        menu.bug = bug
    end

    -- closing the menu ends edit mode, without saving
    menu:HookScript("OnHide", function()
        if editing then
            editing = false
            Discard()
        end
    end)

    -- Esc closes it, like any addon window
    table.insert(UISpecialFrames, "AlniMenuFrame")
end

--------------------------------------------------
-- Showing and hiding
--------------------------------------------------

function ns.ShowMenu()
    if InCombatLockdown() then
        return false
    end
    if not menu then
        BuildMenu()
    end
    if refreshButtons then
        RefreshButtons()
    end
    Layout()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    menu:Show()
    return true
end

--- Hides the menu; true if it was showing
---@return boolean
function ns.HideMenu()
    if not (menu and menu:IsShown()) then
        return false
    end
    if InCombatLockdown() then
        return false
    end
    menu:Hide()
    return true
end

--- Turns edit mode on or off, opening the menu if needed Turning it off saves the changes only with `save` (Done)
---@param on boolean
---@param save boolean?
function ns.SetEditing(on, save)
    if InCombatLockdown() then
        return
    end
    if on and not editing then
        Snapshot()
    end
    if not on and editing then
        if save then
            saved = nil
        else
            Discard()
        end
    end
    editing = on and true or false
    if not (menu and menu:IsShown()) then
        ns.ShowMenu()
    else
        Layout()
    end
end

--- Switches the menu to the theme in AlniMenuDB
function ns.ApplyTheme()
    if not menu then
        return
    end
    menu:SetTheme(AlniMenuDB.theme)
    if menu:IsShown() then
        Layout()
    end
end

--- Lays the open menu out again, after a setting changes
function ns.ApplyLayout()
    if menu and menu:IsShown() and not InCombatLockdown() then
        Layout()
    end
end

-- Saved layouts: AlniMenuDB.layouts = { { name, layout, buttons } }, from Save Layout in edit mode. `buttons` is which
-- of the buttons in the layout were switched on.

local function FindSaved(name)
    for i, saved in ipairs(AlniMenuDB.layouts) do
        if saved.name == name then
            return i, saved
        end
    end
end

function ns.SaveLayout(name)
    local buttons = {}
    for _, category in ipairs(AlniMenuDB.layout) do
        for _, key in ipairs(category.items) do
            buttons[key] = ns.IsEnabled(key)
        end
    end
    local data = { name = name, layout = Copy(AlniMenuDB.layout), buttons = buttons }
    local i = FindSaved(name)
    if i then
        AlniMenuDB.layouts[i] = data
    else
        table.insert(AlniMenuDB.layouts, data)
    end
end

function ns.DeleteLayout(name)
    local i = FindSaved(name)
    if i then
        table.remove(AlniMenuDB.layouts, i)
    end
end

--- Puts a saved layout in place. Its separators come back as new ones
---@param saved table
local function UseSaved(saved)
    local layout = Copy(saved.layout)
    local on = {}
    for _, category in ipairs(layout) do
        for j, key in ipairs(category.items) do
            if key:match("^separator%d+$") then
                local id = AlniMenuDB.nextSeparator
                AlniMenuDB.nextSeparator = id + 1
                AlniMenuDB.separators[id] = true
                local new = ns.AddSeparatorEntry(id)
                if category.gaps[key] then
                    category.gaps[key], category.gaps[new] = nil, true
                end
                on[new] = saved.buttons[key]
                category.items[j] = new
            else
                on[key] = saved.buttons[key]
            end
        end
    end
    AlniMenuDB.layout = layout
    for key, entry in pairs(ENTRIES) do
        if not entry.always then
            if on[key] ~= nil then
                AlniMenuDB.buttons[key] = on[key]
            elseif not entry.custom then
                AlniMenuDB.buttons[key] = false
            end
        end
    end
end

--- Replaces the layout with one of LAYOUTS (`data.name`: "default", "original") or a saved one (`data.saved`: its
--- name). In edit mode it is kept only with Done.
---@param data table
function ns.LoadLayout(data)
    if InCombatLockdown() then
        print("|cff33ff99" .. ADDON_NAME .. ":|r not in combat.")
        return
    end
    if data.saved then
        local _, saved = FindSaved(data.saved)
        if not saved then
            return
        end
        UseSaved(saved)
    elseif LAYOUTS[data.name] then
        AlniMenuDB.layout = ns.DefaultLayout(LAYOUTS[data.name])
        SetButtonsFrom(LAYOUTS[data.name])
    else
        return
    end
    ns.CheckLayout()
    -- separators made for it now have a button
    if menu then
        for key in pairs(ENTRIES) do
            ns.RefreshEntryButton(key)
        end
    end
    ns.ApplyLayout()
end

StaticPopupDialogs.ALNIMENU_LOAD_LAYOUT = {
    text         = "Replace your menu layout with the %s layout?",
    button1      = ACCEPT or "Accept",
    button2      = CANCEL or "Cancel",
    OnAccept     = function(_, data) ns.LoadLayout(data) end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

StaticPopupDialogs.ALNIMENU_DELETE_LAYOUT = {
    text         = "Delete the saved layout %s?",
    button1      = DELETE or "Delete",
    button2      = CANCEL or "Cancel",
    OnAccept     = function(_, name) ns.DeleteLayout(name) end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

local function SaveFromPopup(popup)
    local box = popup.GetEditBox and popup:GetEditBox() or popup.editBox
    local name = strtrim(box:GetText())
    if name ~= "" then
        ns.SaveLayout(name)
    end
end

StaticPopupDialogs.ALNIMENU_SAVE_LAYOUT = {
    text                   = "Save the current layout as:",
    button1                = SAVE or "Save",
    button2                = CANCEL or "Cancel",
    hasEditBox             = true,
    maxLetters             = 32,
    OnAccept               = SaveFromPopup,
    EditBoxOnEnterPressed  = function(self)
        local popup = self:GetParent()
        SaveFromPopup(popup)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout                = 0,
    whileDead              = true,
    hideOnEscape           = true,
}
