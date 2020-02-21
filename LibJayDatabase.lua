local MAJOR = "LibJayDatabase"
local MINOR = 1

assert(LibStub, format("%s requires LibStub.", MAJOR))

local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

lib.dbs = lib.dbs or {}

local CHAR_KEY = UnitName("player") .. " - " .. GetRealmName()

--------------------------------------------------------------------------------
-- Database Mixin
--------------------------------------------------------------------------------
local DatabaseMixin = {}

local next = next
local pairs = pairs
local type = type
---@param profile table
---@param defaults table
local function removeDefaults(profile, defaults)
    if type(profile) ~= "table" or type(defaults) ~= "table" then return end

    for k, v in pairs(profile) do
        if type(v) == "table" and type(defaults[k]) == "table" then
            removeDefaults(v, defaults[k])
            if not next(v) then profile[k] = nil end
        elseif v == defaults[k] then
            profile[k] = nil
        end
    end
end

---@param self table
local function Save(self)
    for profileKey, profile in pairs(self.profiles) do
        removeDefaults(profile, self.defaults)
        if not next(profile) then self.profiles[profileKey] = nil end
    end
    removeDefaults(self.globals, self.defaults_globals)

    _G[self.variableName] = {
        profileKeys = self.profileKeys,
        profiles = self.profiles,
        globals = self.globals,
        lastChangeTime = self.lastChangeTime,
        lastChangeChar = self.lastChangeChar
    }
end

---@param self table
local function PLAYER_LOGOUT(self) if self.restored then Save(self) end end

local GetServerTime = GetServerTime
---@param self table
local function setLastChange(self)
    self.lastChangeTime = GetServerTime()
    self.lastChangeChar = CHAR_KEY
end

local wipe = wipe
local CopyTable = CopyTable
---@param self table
local function Restore(self)
    local profileKeys, profiles, globals
    if type(_G[self.variableName]) == "table" then
        profileKeys = _G[self.variableName].profileKeys
        profiles = _G[self.variableName].profiles
        globals = _G[self.variableName].globals

        self.lastChangeTime = _G[self.variableName].lastChangeTime or
                                  GetServerTime()
        self.lastChangeChar = _G[self.variableName].lastChangeChar or CHAR_KEY

        wipe(_G[self.variableName])
    end
    self.lastChangeTime = self.lastChangeTime or GetServerTime()
    self.lastChangeChar = self.lastChangeChar or CHAR_KEY

    if type(profileKeys) ~= "table" then profileKeys = {} end
    if type(profiles) ~= "table" then profiles = {} end
    if type(globals) ~= "table" then globals = {} end

    for char, key in pairs(profileKeys) do
        if type(char) == "string" and type(key) == "string" then
            self.profileKeys[char] = key
        end
    end
    for key, data in pairs(profiles) do
        if type(key) == "string" and type(data) == "table" then
            self.profiles[key] = CopyTable(data)
        end
    end
    for k, v in pairs(globals) do
        if type(k) == "string" then
            if type(v) == "table" then
                self.globals[k] = CopyTable(v)
            else
                self.globals[k] = v
            end
        end
    end

    self.restored = true

    self:SetProfile(self.profileKeys[CHAR_KEY] or self.defaultProfile)
    self.callbacks:TriggerEvent("Loaded", self)
end

local LJEvent = LibStub("LibJayEvent")
---@param self table
---@param addOnName string
local function ADDON_LOADED(self, addOnName)
    if addOnName == self.addOnName then
        LJEvent:Unregister("ADDON_LOADED", ADDON_LOADED, self)

        Restore(self)
    end
end

local LJCallback = LibStub("LibJayCallback")
local IsAddOnLoaded = IsAddOnLoaded
function DatabaseMixin:OnLoad()
    self.OnLoad = nil
    self.callbacks = self.callbacks or LJCallback:New(self)

    self.defaults = self.defaults or {}
    self.db = {}
    self.profileKeys = {}
    self.profiles = {}
    self.defaults_globals = self.defaults_globals or {}
    self.globals = {}

    LJEvent:Register("PLAYER_LOGOUT", PLAYER_LOGOUT, self)

    local loaded, finished = IsAddOnLoaded(self.addOnName)
    if not loaded or not finished then
        LJEvent:Register("ADDON_LOADED", ADDON_LOADED, self)
    else
        self:Restore()
    end

    lib.dbs[self] = true
end

---@param profile table
---@param defaults table
local function copyDefaults(profile, defaults)
    for k, v in pairs(defaults) do
        if type(profile[k]) == "nil" then
            if type(v) == "table" then
                profile[k] = CopyTable(v)
            else
                profile[k] = v
            end
        elseif type(v) == "table" and type(profile[k]) == "table" then
            copyDefaults(profile[k], v)
        end
    end
end

---@param self table
---@param event string
local function TriggerEvent(self, event, ...)
    local callbacks = self.callbacks
    callbacks:TriggerEvent(event, self, ...)
    callbacks:TriggerEvent("OnChanged", self)
end

local error = error
local format = format
---@param profileKey string
function DatabaseMixin:SetProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format(
                  "Usage: Database:SetProfile(profileKey): 'profileKey' - string expected got %s",
                  type(profileKey), 2))
    end

    if self.profile and self.profile == profileKey then return end

    if type(self.profiles[profileKey]) ~= "table" then
        self.profiles[profileKey] = CopyTable(self.defaults)
    else
        copyDefaults(self.profiles[profileKey], self.defaults)
    end
    self.db = self.profiles[profileKey]
    self.profileKeys[CHAR_KEY] = profileKey
    if self.profile then setLastChange(self) end
    self.profile = profileKey
    TriggerEvent(self, "OnProfileChanged", profileKey)
end

---@param profileKey string
function DatabaseMixin:ResetProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format(
                  "Usage: Database:SetProfile(profileKey): 'profileKey' - string expected got %s",
                  type(profileKey), 2))
    end

    if self.profiles[profileKey] then
        wipe(self.profiles[profileKey])
        self.profiles[profileKey] = CopyTable(self.defaults)
        if self.profile == profileKey then
            self.db = self.profiles[profileKey]
        end
    end

    setLastChange(self)

    TriggerEvent(self, "OnProfileReset", profileKey)
end

---@return string profile
function DatabaseMixin:GetProfile() return self.profile or self.defaultProfile end

---@return string[] profiles
function DatabaseMixin:GetProfiles()
    local profiles = {}
    for key in pairs(self.profiles) do profiles[#profiles + 1] = key end
    return profiles
end

local tContains = tContains
---@return string[] usedProfiles
function DatabaseMixin:GetUsedProfiles()
    local usedProfiles = {}
    for _, key in pairs(self.profileKeys) do
        if not tContains(usedProfiles, key) then
            usedProfiles[#usedProfiles + 1] = key
        end
    end
    return usedProfiles
end

---@return string[] unusedProfiles
function DatabaseMixin:GetUnusedProfiles()
    local usedProfiles = self:GetUsedProfiles()
    local unusedProfiles = {}
    for key in pairs(self.profiles) do
        if not tContains(usedProfiles, key) then
            unusedProfiles[#unusedProfiles + 1] = key
        end
    end
    return unusedProfiles
end

---@param profileKey string
function DatabaseMixin:DeleteProfile(profileKey)
    if type(profileKey) ~= "string" then
        error(format(
                  "Usage: Database:DeleteProfile(profileKey): 'profileKey' - string expected got %s",
                  type(profileKey), 2))
    end

    if self.profile == profileKey then
        error(format(
                  "Usage: Database:DeleteProfile(profileKey): 'profileKey' - cannot delete current profile (%s)",
                  profileKey), 2)
    end

    self.profiles[profileKey] = nil
    for char, key in pairs(self.profileKeys) do
        if key == profileKey then self.profileKeys[char] = nil end
    end

    setLastChange(self)

    TriggerEvent(self, "OnProfileDeleted", profileKey)
end

---@param from string
function DatabaseMixin:CopyProfile(from)
    if type(from) ~= "string" then
        error(format(
                  "Usage: Database:CopyProfile(from): 'from' - string expected got %s",
                  type(from), 2))
    end

    if not self.profiles[from] then
        error(format(
                  "Usage: Database:CopyProfile(from): 'from' - cannot find profile (%s)",
                  from), 2)
    end

    local current = self:GetProfile()
    wipe(self.profiles[current])
    --[[ for k, v in pairs(self.profiles[current]) do
        self.profiles[current][k] = nil
    end ]]
    --[[ for k, v in pairs(self.profiles[from]) do
        self.profiles[current][k] = type(v) == "table" and CopyTable(v) or v
    end ]]
    self.profiles[current] = CopyTable(self.profiles[from])
    copyDefaults(self.profiles[current], self.defaults)
    self.db = self.profiles[current]

    setLastChange(self)

    TriggerEvent(self, "OnProfileCopied", from)
end

local tostringall = tostringall
local function coercePath(...) return tostringall(...) end

local validValueTypes = {"boolean", "number", "string", "nil"}
for i = 1, #validValueTypes do validValueTypes[validValueTypes[i]] = true end
local validValueTypesString = table.concat(validValueTypes, ", ", 1,
                                           #validValueTypes - 1)
validValueTypesString = format("%s or %s", validValueTypesString,
                               validValueTypes[#validValueTypes])

---@param value any
---@param usage string
local function checkValue(value, usage)
    if not validValueTypes[type(value)] then
        error(format("Usage: Database:%s: 'value' - %s expected got %s", usage,
                     validValueTypesString, type(value)), 3)
    end
end

local select = select
---@param tbl table
---@param value any
---@param path any
local function set(tbl, value, path, ...)
    if select("#", ...) > 0 then
        if type(tbl[path]) ~= "table" then tbl[path] = {} end
        return set(tbl[path], value, ...)
    else
        if tbl[path] ~= value then
            tbl[path] = value
            return true
        end
    end
end

---@param value boolean | number | string | nil
---@param path any
function DatabaseMixin:SetDefault(value, path, ...)
    checkValue(value, "SetDefault(value, path[, ...])")

    set(self.defaults, value, coercePath(path, ...))

    if self.restored then
        copyDefaults(self.profiles[self:GetProfile()], self.defaults)
    end
end

---@param value any
---@param path string
function DatabaseMixin:SetWithoutResponse(value, path, ...)
    checkValue(value, "SetWithoutResponse(value, path[, ...]")
    if set(self.db, value, coercePath(path, ...)) then setLastChange(self) end
end

---@param value boolean | number | string | nil
---@param path string
function DatabaseMixin:Set(value, path, ...)
    checkValue(value, "Set(value, path[, ...]")
    if set(self.db, value, coercePath(path, ...)) then
        setLastChange(self)
        TriggerEvent(self, "OnValueChanged", value, coercePath(path, ...))
    end
end

local function get(tbl, ...)
    if select("#", ...) > 1 then
        tbl = tbl[(...)]
        if type(tbl) == "table" then return get(tbl, select(2, ...)) end
    else
        return tbl[(...)]
    end
end

---@return boolean | number | string | nil value
function DatabaseMixin:Get(...)
    if self.restored then
        local value = get(self.db, coercePath(...))
        if type(value) ~= "nil" then return value end
    end
    return get(self.defaults, coercePath(...))
end

function DatabaseMixin:Reset(...)
    self:Set(get(self.defaults, coercePath(...)), coercePath(...))
end

---@return any defult
function DatabaseMixin:GetDefault(...) return
    get(self.defaults, coercePath(...)) end

local LAST_CHANGE_FORMAT = "|cffcfcfcf%s (%s)|r"
local date = date
function DatabaseMixin:GetLastChange()
    return format(LAST_CHANGE_FORMAT, date("%Y-%m-%d %X", self.lastChangeTime),
                  self.lastChangeChar), self.lastChangeTime, self.lastChangeChar
end

function DatabaseMixin:Clear()
    local restored = self.restored
    Save(self)
    self.restored = nil
    _G[self.variableName] = nil
    if restored then Restore(self) end
end

---@param value boolean | number | string | nil
---@param path string
function DatabaseMixin:SetGlobalDefault(value, path, ...)
    checkValue(value, "SetGlobalDefault(value, path[, ...]")

    set(self.defaults_globals, value, coercePath(path, ...))
end

function DatabaseMixin:GetGlobalDefault(...)
    get(self.defaults_globals, coercePath(...))
end

---@param value boolean | number | string | nil
---@param path string
function DatabaseMixin:SetGlobal(value, path, ...)
    checkValue(value, "SetGlobal(value, path[, ...]")

    if set(self.globals, value, coercePath(path, ...)) then
        setLastChange(self)
        TriggerEvent(self, "OnGlobalValueChanged", value, coercePath(path, ...))
    end
end

---@return boolean | number | string | nil value
function DatabaseMixin:GetGlobal(...)
    if self.restored then
        local value = get(self.globals, coercePath(...))
        if type(value) ~= "nil" then return value end
    end
    return get(self.defaults_globals, coercePath(...))
end

local DEFAULT_PROFILES = {
    REALM = GetRealmName(),
    FACTION = select(2, UnitFactionGroup("player")),
    RACE = UnitRace("player"),
    CLASS = UnitClass("player")
}

local LJMixin = LibStub("LibJayMixin")
---@param addOnName string
---@param variableName string
---@param defaultProfile string | "\"REALM\"" | "\"FACTION\"" | "\"RACE\"" | "\"CLASS\""
function lib:New(addOnName, variableName, defaultProfile)
    if type(addOnName) ~= "string" then
        error(format(
                  "Usage: %s:New(addOnName, variableName[, defaultProfile]): 'addOnName' - string expected got %s",
                  MAJOR, type(addOnName), 2))
    end
    if type(variableName) ~= "string" then
        error(format(
                  "Usage: %s:New(addOnName, variableName[, defaultProfile]): 'variableName' - string expected got %s",
                  MAJOR, type(variableName), 2))
    end
    defaultProfile = defaultProfile or CHAR_KEY
    if type(defaultProfile) ~= "string" then
        error(format(
                  "Usage: %s:New(addOnName, variableName[, defaultProfile]): 'defaultProfile' - string expected got %s",
                  MAJOR, type(defaultProfile), 2))
    end

    local database = LJMixin:Mixin({
        addOnName = addOnName,
        variableName = variableName,
        defaultProfile = DEFAULT_PROFILES[defaultProfile] or defaultProfile
    }, DatabaseMixin)
    return database
end

for db in pairs(lib.dbs) do -- upgrade
    if db.restored then
        Save(db)
        db.restored = nil
    end
    LJMixin:Mixin(db, DatabaseMixin)
end
