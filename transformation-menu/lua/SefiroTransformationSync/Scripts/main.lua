-- SefiroTransformationSync: SyncMap entries of the Transformation Menu character packs.
--
-- Oblivion Remastered links every TES form to its Unreal asset through TESSync.AllForms (FormID -> asset path). A form
-- added by a plugin has no entry, so the game never creates it ("CreateReference failed") and a character's race
-- cannot load. A pack lists its forms in "syncMap" (format in SefiroTransformation\packs\README.md); this mod adds
-- them when the game builds the map. The technique (transient TESSync + AllForms:Add) was learned from
-- TesSyncMapInjector by BB; the code is ours.
--
-- It is a separate Lua mod on purpose: NotifyOnNewObject runs its callback on the thread that creates the object, so
-- it must not share a Lua state with the Transformation Menu, which runs on the game thread.

local TAG = "[SefiroTransformationSync] "
local function log(text) print(TAG .. text .. "\n") end

local function scriptDir()
    local src = debug.getinfo(1, "S").source
    return (src:match("^@(.*[\\/])") or "")
end
local PACKS_DIR = scriptDir() .. "..\\..\\SefiroTransformation\\packs\\"
local GAME_DATA = "..\\..\\Content\\Dev\\ObvData\\Data\\"   -- the game's working directory is Binaries\Win64
local GAME_PAKS = "..\\..\\Content\\Paks\\~mods\\"

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local t = f:read("*a"); f:close(); return t
end

-- Minimal JSON (objects, arrays, strings, numbers, true/false/null): enough for the packs.
local function jsonDecode(text)
    local pos = 1
    local function ws() pos = text:find("[^ \t\r\n]", pos) or (#text + 1) end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = text:sub(i, i)
            if c == "" then error("unterminated string") end
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == "\\" then
                local e = text:sub(i + 1, i + 1)
                local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
                if e == "u" then out[#out + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = map[e] or e; i = i + 2 end
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = text:sub(pos, pos)
        if c == "{" then
            local t = {}; pos = pos + 1; ws()
            if text:sub(pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                ws(); local k = str(); ws()
                if text:sub(pos, pos) ~= ":" then error("':' expected at " .. pos) end
                pos = pos + 1; t[k] = value(); ws()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == "}" then return t elseif d ~= "," then error("',' expected at " .. pos) end
            end
        elseif c == "[" then
            local t = {}; pos = pos + 1; ws()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == "]" then return t elseif d ~= "," then error("',' expected at " .. pos) end
            end
        elseif c == '"' then return str()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num then error("invalid value at " .. pos) end
            pos = pos + #num; return tonumber(num)
        end
    end
    return value()
end

-- Plugin load index, with the game's rule: Plugins.txt lines whose file exists in Data, in order; AltarDeluxe.esp is
-- deactivated without the Deluxe entitlement, so every plugin after it moves down by one (RVA 0x65D1740).
local PLUGIN_INDEX = {}
do
    local n = 0
    for line in (readFile(GAME_DATA .. "Plugins.txt") or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:find("^#") and readFile(GAME_DATA .. line) then
            PLUGIN_INDEX[line:lower()] = n; n = n + 1
        end
    end
end
local DELUXE_INDEX = PLUGIN_INDEX["altardeluxe.esp"]
local function hasDeluxe()
    local ok, v = pcall(function()
        local lib = StaticFindObject("/Script/Altar.Default__VAltarEntitlementBlueprintLibrary")
        if lib and lib:IsValid() then return lib:HasDeluxeEntitlement() end
        return nil
    end)
    if ok and type(v) == "boolean" then return v end
    return nil
end
-- Load index of a plugin, or nil while it depends on the Deluxe flag and the flag cannot be read yet.
local function loadIndex(plugin)
    local key = plugin:lower()
    local idx = PLUGIN_INDEX[key]
    if not idx then return nil, "not in Plugins.txt" end
    if DELUXE_INDEX == nil or idx < DELUXE_INDEX or key == "altardeluxe.esp" then return idx end
    local d = hasDeluxe()
    if d == nil then return nil, "Deluxe flag not readable yet" end
    return d and idx or idx - 1
end

-- Entries of the installed packs (same availability rule as the menu: pak in ~mods, plugin in Plugins.txt).
local ENTRIES = {}
do
    local names = {}
    local okP, p = pcall(io.popen, 'dir /b "' .. PACKS_DIR .. '*.json" 2>nul')
    if okP and p then for line in p:lines() do names[#names + 1] = line end; p:close() end
    for _, file in ipairs(names) do
        local okJ, pack = pcall(jsonDecode, readFile(PACKS_DIR .. file) or "")
        if okJ and type(pack) == "table" and type(pack.syncMap) == "table" then
            local req = pack.requires or {}
            if req.pak and not readFile(GAME_PAKS .. req.pak) then
                log("pack " .. file .. ": pak " .. req.pak .. " not installed, skipped")
            elseif req.plugin and not PLUGIN_INDEX[req.plugin:lower()] then
                log("pack " .. file .. ": plugin " .. req.plugin .. " not in Plugins.txt, skipped")
            else
                for _, e in ipairs(pack.syncMap) do
                    local id = tonumber(e.id or "", 16)
                    if type(e.plugin) == "string" and id and type(e.asset) == "string" then
                        ENTRIES[#ENTRIES + 1] = { plugin = e.plugin, id = id & 0xFFFFFF, asset = e.asset, pack = pack.id or file }
                    else
                        log("pack " .. file .. ": invalid syncMap entry skipped")
                    end
                end
            end
        elseif not okJ then
            log("pack " .. file .. ": invalid file (" .. tostring(pack) .. ")")
        end
    end
end

local added = {}   -- FormID -> asset already added to the current map
local function apply(tesSync, final)
    local allForms = tesSync.AllForms
    if not (allForms and allForms:IsValid()) then return false end
    local pending = 0
    for _, e in ipairs(ENTRIES) do
        local idx, why = loadIndex(e.plugin)
        if idx then
            local formId = (idx << 24) | e.id
            if added[formId] ~= e.asset then
                allForms:Add(formId, e.asset)
                added[formId] = e.asset
                log(string.format("%s: %08X -> %s", e.pack, formId, e.asset))
            end
        elseif final then
            log(e.pack .. ": " .. e.plugin .. " " .. tostring(why) .. ", entry " .. string.format("%06X", e.id) .. " not added")
        else
            pending = pending + 1
        end
    end
    return pending == 0
end

if #ENTRIES == 0 then
    log("no character pack with SyncMap entries installed")
else
    log(#ENTRIES .. " SyncMap entries from the character packs")
    NotifyOnNewObject("/Script/Altar.TESSync", function(obj)
        if not obj:GetFullName():find("/Engine/Transient.TESSync", 1, true) then return end
        added = {}
        -- now and again after 1 s and 3 s: the game fills the map right after creating the object, and the Deluxe
        -- flag may not be readable at the first call
        pcall(apply, obj, false)
        ExecuteWithDelay(1000, function() pcall(apply, obj, false) end)
        ExecuteWithDelay(3000, function() pcall(apply, obj, true) end)
    end)
end
