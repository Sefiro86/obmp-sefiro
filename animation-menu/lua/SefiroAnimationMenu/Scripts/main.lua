-- SefiroAnimationMenu (Sefiro Animation Menu, 0.8): animation bench on the player's OWN character, with the bench camera.
-- Up to 0.7 the targets were the nearby custom NPCs.
--
-- Commands from cmd.txt (written by the OblivionMP mod Sefiro.AnimationMenu, Alt+Y menu), "<seq> <command>" per line:
--   play <anim> <loop 0|1>   speed <x> (0 = pause)   stop   step <1|-1>   mark <a|b>   abclear   seek <s>
--   refpose   mode <pure|slot>   root <on|off>   fav <anim>   scan   open / close (menu opened or closed)
--   home (go back to where the player was when the menu opened)
--   cam <next|prev|preset n|orbit ±1|height ±1|zoom ±1|move <axis>P|N|0|drag dx_dy|spin|reset>
--   "r <command>" = menu command from another player: ignored (synchronization is phase 2)
--
-- Rules (learned from earlier mods, and from the crash of 2026-11-16 19:09):
--  * No UE4SS LoadAsset (it crashes). The list is: animations already in memory (FindAllOf on every "scan") plus the
--    catalog catalog.txt (all animations in the pak, from tools\make_catalog.ps1). Animations not in memory are
--    loaded on play with the engine loader, KismetSystemLibrary:LoadAsset_Blocking;
--  * No NotifyOnNewObject (it crashes on the loading thread);
--  * All work runs in the local player's ReceiveTick (game thread). No LoopAsync.
-- How it plays: "pure" mode uses PlayAnimation on the mesh (single node, no AnimBlueprint); "game" mode uses
-- PlaySlotAnimationAsDynamicMontage on the "FullBody" slot (montages use Montage_Play). Speed and pause use the
-- animation play rate: CustomTimeDilation would also slow down the player's movement, camera and networking.

local TAG = "[SefiroAnimationMenu] "
local DIR = (os.getenv("APPDATA") or "") .. "\\ReadyM.Launcher\\Oblivion\\Mods\\SefiroAnimationMenu\\"
local CMD_FILE, LIST_FILE = DIR .. "cmd.txt", DIR .. "list.txt"
local POS_FILE = DIR .. "pos.txt"   -- animation position for the menu timeline (posTick)

local SLOT = "FullBody"

local logFile = io.open(DIR .. "animtest.log", "a")
if logFile then logFile:setvbuf("line"); logFile:write(("\n==== start %s ====\n"):format(os.date("%Y-%m-%d %H:%M:%S"))) end
local function log(text)
    print(TAG .. text .. "\n")
    if logFile then logFile:write(os.date("%H:%M:%S "), text, "\n"); logFile:flush() end
end
local function valid(o) return o ~= nil and o.IsValid ~= nil and o:IsValid() end
local function fullName(o) local ok, n = pcall(function() return o:GetFullName() end); return ok and n or "" end
local function shortName(o) local ok, n = pcall(function() return o:GetFName():ToString() end); return ok and n or "?" end

-- ---------------------------------------------------------------- animations in memory

local anims = {}          -- name -> { obj, montage = bool, group, len }
-- Favorites: animations marked with * in the menu, saved in favorites.txt (one per line), "Favorites" tab.
local FAV_FILE = DIR .. "favorites.txt"
local favs, favOrder = {}, {}
do
    local f = io.open(FAV_FILE, "r")
    if f then
        for line in f:lines() do
            local n = line:match("^%s*(%S+)")
            if n and not favs[n] then favs[n] = true; favOrder[#favOrder + 1] = n end
        end
        f:close()
    end
end
local listBody = ""

local function groupOf(name, path)
    local n, p = name:lower(), path:lower()
    if n:find("death") or n:find("_die") or n:find("dead") or n:find("knock") or n:find("getup")
        or n:find("ragdoll") or n:find("bleedout") or n:find("paralyz") then
        return "death"
    end
    if p:find("/idleanims/", 1, true) or p:find("/characters/", 1, true) or n:find("sneak") or n:find("swim")
        or n:find("chair") or n:find("bed") or n:find("_sit") or n:find("lean") or n:find("jump") or n:find("fall")
        or n:find("ladder") or n:find("horse") or n:find("talk") or n:find("kneel") or n:find("pray")
        or n:find("cheer") or n:find("dance") or n:find("drink") or n:find("eat") then
        return "special"
    end
    if p:find("/combat/", 1, true) or n:find("attack") or n:find("block") or n:find("recoil") or n:find("stagger")
        or n:find("equip") or n:find("cast") or n:find("spell") or n:find("dodge") or n:find("bow") then
        return "combat"
    end
    return "loco"
end

local ORDER = { loco = 1, combat = 2, special = 3, death = 4 }

-- Catalog: name -> object path ("/Game/.../Name.Name") of every animation in the pak, humanoids and creatures.
-- The "family" is the word after A_/AM_ in the name (Humanoid, Bear, Troll...): catalogFam lists them.
local catalog, catalogCount, catalogFam = {}, 0, { Humanoid = true }
local function familyOf(name) return name:match("^AM?_([^_]+)_") end
do
    local f = io.open(DIR .. "catalog.txt", "r")
    if f then
        for line in f:lines() do
            local n, p = line:match("^([%w_]+)|(/%S+)")
            local fam = n and familyOf(n)
            if fam and not catalog[n] then catalog[n] = p; catalogCount = catalogCount + 1; catalogFam[fam] = true end
        end
        f:close()
    end
    log(catalogCount > 0 and ("catalog: " .. catalogCount .. " animations")
        or "catalog missing: only animations already in memory")
end

-- Engine loader (TSoftObjectPtr::LoadSynchronous), through reflection; only from the player's ReceiveTick.
local ksl = nil
local function loadAnim(path)
    local o = StaticFindObject(path)
    if valid(o) then return o end
    if not valid(ksl) then ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
    if not valid(ksl) then log("loading: KismetSystemLibrary not found"); return nil end
    local ok, res = pcall(function()
        return ksl:LoadAsset_Blocking(ksl:Conv_SoftObjPathToSoftObjRef(ksl:MakeSoftObjectPath(path)))
    end)
    o = StaticFindObject(path)
    if valid(o) then return o end
    if ok and valid(res) then return res end
    log("loading failed: " .. path .. (ok and "" or (" (" .. tostring(res):sub(1, 120) .. ")")))
    return nil
end

-- Which families fit the body the player has right now (human, or a creature after a transformation).
-- It is decided from the skeleton: for each family, read the skeleton of one of its animations already in memory (the
-- game loads them together with the body) and keep the families with the same skeleton as the player's mesh.
local famSkel = {}                 -- family -> full skeleton name
local bodyFamilies = "Humanoid"    -- for the menu: active families, comma-separated
local playerSkeleton               -- defined further down, after localPawn

local function skeletonOf(o)
    local s = nil
    pcall(function() s = o.Skeleton end)
    return valid(s) and fullName(s) or nil
end

local function scan()
    local found, rows, cands = {}, {}, {}
    for _, cls in ipairs({ "AnimSequence", "AnimMontage" }) do
        for _, o in ipairs(FindAllOf(cls) or {}) do
            local path = fullName(o):match("^%S+%s+(.+)$")
            local name = path and path:match("%.([^%.:]+)$")
            local fam = name and familyOf(name)
            -- third person: no first person, no dynamic montages (Transient), no facial animations
            if fam and catalogFam[fam] and not path:find("FirstPerson", 1, true) and not name:find("_FP$") then
                if famSkel[fam] == nil then famSkel[fam] = skeletonOf(o) end
                cands[#cands + 1] = { name = name, path = path, fam = fam, obj = o, montage = (cls == "AnimMontage") }
            end
        end
    end
    local mine = playerSkeleton()
    local active, names = {}, {}
    for fam, s in pairs(famSkel) do
        if mine and s == mine then active[fam] = true; names[#names + 1] = fam end
    end
    if #names == 0 then
        active, names = { Humanoid = true }, { "Humanoid" }
        log("scan: player skeleton not recognized (" .. tostring(mine) .. "), using the humanoid list")
    end
    table.sort(names)
    bodyFamilies = table.concat(names, ",")
    for _, c in ipairs(cands) do
        if active[c.fam] and not found[c.name] then
            local len = 0
            pcall(function() len = c.obj:GetPlayLength() end)
            found[c.name] = { obj = c.obj, montage = c.montage, group = groupOf(c.name, c.path), len = len }
            rows[#rows + 1] = c.name
        end
    end
    local inMemory = #rows
    -- catalog animations not in memory yet: still listed, loaded on play
    for name, path in pairs(catalog) do
        if not found[name] and active[familyOf(name)] then
            found[name] = { path = path, montage = name:find("^AM_") ~= nil, group = groupOf(name, path), len = 0 }
            rows[#rows + 1] = name
        end
    end
    table.sort(rows, function(a, b)
        local ga, gb = ORDER[found[a].group], ORDER[found[b].group]
        if ga ~= gb then return ga < gb end
        return a < b
    end)
    local out = {}
    for _, name in ipairs(rows) do
        local a = found[name]
        out[#out + 1] = string.format("%s|%s|%.1f%s", a.group, name, tonumber(a.len) or 0, a.obj and "" or "|u")
    end
    anims = found
    listBody = table.concat(out, "\n")
    log(string.format("scan: body %s, %d animations, %d in memory and %d to load", bodyFamilies, #rows, inMemory,
        #rows - inMemory))
end

-- The object is looked up again at play time: the engine may have freed an animation nobody uses any more.
-- If it is not in memory (or no longer is) and the catalog knows it, load it.
local function animByName(name)
    local a = anims[name]
    if a and valid(a.obj) then return a end
    scan()
    a = anims[name]
    if not a then return nil end
    if valid(a.obj) then return a end
    if not a.path then return nil end
    local o = loadAnim(a.path)
    if not o then return nil end
    scan()   -- now it is in memory: the list gets the real length and type
    a = anims[name]
    if a and valid(a.obj) then log("loaded from the pak: " .. name); return a end
    -- object name differs from the catalog name (letter case): use the loaded object anyway
    local len = 0
    pcall(function() len = o:GetPlayLength() end)
    log("loaded from the pak: " .. name .. " (not in the list)")
    return { obj = o, montage = fullName(o):find("^AnimMontage ") ~= nil, group = "loco", len = len }
end

-- ---------------------------------------------------------------- state and targets

local state = { speed = 1, loop = false, target = "me", playing = nil, current = nil, mode = "pure", root = true }
local targets = {}        -- { actor, inst, montage, self }
local cam, PRESETS        -- bench camera (section further down); declared here because writeList reads them

local function localPawn()
    local pc = FindFirstOf("PlayerController")
    local p = nil
    if valid(pc) then pcall(function() p = pc.Pawn end) end
    if valid(p) then return p end
    p = FindFirstOf("BP_OblivionPlayerCharacter_C")
    return valid(p) and p or nil
end

-- Skeleton of the mesh the player has right now (changes with a transformation into a creature).
playerSkeleton = function()
    local p = localPawn()
    if not p then return nil end
    local sk = nil
    pcall(function() sk = p.Mesh:GetSkeletalMeshAsset() end)
    if not valid(sk) then pcall(function() sk = p.Mesh.SkeletalMesh end) end
    return valid(sk) and skeletonOf(sk) or nil
end

-- The only target is the local player.
local function findTargets()
    local self = localPawn()
    return self and { { actor = self, self = true } } or {}
end

local function writeList()
    local f = io.open(LIST_FILE .. ".tmp", "w")
    if not f then return end
    f:write("v1\n")
    f:write(string.format("#status targets=%d speed=%s loop=%d mode=%s root=%d body=%s playing=%s\n",
        #findTargets(), tostring(state.speed), state.loop and 1 or 0, state.mode, state.root and 1 or 0,
        bodyFamilies, state.playing or "-"))
    f:write(string.format("#cam on=%d preset=%s spin=%d fp=%d\n", cam.on and 1 or 0, PRESETS[cam.preset].name,
        cam.spin and 1 or 0, cam.fp and 1 or 0))
    f:write(string.format("#ab a=%s b=%s\n", state.abA and string.format("%.2f", state.abA) or "-",
        state.abB and string.format("%.2f", state.abB) or "-"))
    f:write(listBody, "\n")
    for _, n in ipairs(favOrder) do
        local a = anims[n]
        if a then f:write(string.format("fav|%s|%.1f\n", n, tonumber(a.len) or 0)) end
    end
    f:close()
    os.remove(LIST_FILE)
    os.rename(LIST_FILE .. ".tmp", LIST_FILE)
end

-- ---------------------------------------------------------------- actions

local function animInstance(actor)
    local inst = nil
    pcall(function() inst = actor.Mesh:GetAnimInstance() end)
    return valid(inst) and inst or nil
end

local function setSpeed(t, speed)
    if t.self then
        -- On the player only the animation slows down: CustomTimeDilation would also slow down movement, camera and
        -- network sync. Single node sequence: mesh play rate; montage: montage play rate.
        pcall(function()
            if t.single then
                t.actor.Mesh:SetPlayRate(speed)
            else
                local inst = animInstance(t.actor)
                if inst and valid(t.montage) then inst:Montage_SetPlayRate(t.montage, speed) end
            end
        end)
        return
    end
    pcall(function() t.actor.CustomTimeDilation = speed end)
end

-- "Pure" mode: the mesh plays the sequence by itself (EAnimationMode AnimationSingleNode), without the AnimBlueprint,
-- like the offline bench. It is needed for the rig: in "game" mode the NPC AnimBlueprint applies the FullBody slot
-- only to the neck and head (test 2026-11-16, sprint: body in idle and neck bent like a sprint, a pose the game
-- never produces). Stop goes back to the AnimBlueprint (SetAnimationMode(AnimationBlueprint, init)).
local MODE_BP, MODE_SINGLE = 0, 1

local function restoreBlueprint(t)
    if not t.single then return end
    t.single = false
    local ok, err = pcall(function()
        local mesh = t.actor.Mesh
        mesh:Stop()
        mesh:SetAnimationMode(MODE_BP, true)
    end)
    if not ok then log("back to the AnimBlueprint on " .. shortName(t.actor) .. ": " .. tostring(err):sub(1, 160)) end
end

-- Root motion on/off (command "root on|off"). Off: the playing AnimInstance switches to IgnoreRootMotion
-- (ERootMotionMode 1): the root movement is extracted and discarded, the character stays in place.
-- On, and every stop, restore the mode the instance had: outside the bench the game must find its own mode again,
-- otherwise dodges and attacks would no longer move the player. There are two instances (AnimBlueprint and the
-- single node of pure mode), each with its own original mode.
local ROOT_IGNORE = 1
local rootSaved = {}

local function setRoot(t, ignore)
    local inst = animInstance(t.actor)
    if not inst then return end
    local key = t.single and "single" or "bp"
    local ok, err = pcall(function()
        if ignore then
            if rootSaved[key] == nil then rootSaved[key] = tonumber(inst.RootMotionMode) or 3 end
            inst:SetRootMotionMode(ROOT_IGNORE)
        elseif rootSaved[key] ~= nil then
            inst:SetRootMotionMode(rootSaved[key])
        end
    end)
    if not ok then log("root motion on " .. shortName(t.actor) .. ": " .. tostring(err):sub(1, 160)) end
end

local function stopOn(t, blend, keepSingle)
    if not keepSingle then restoreBlueprint(t) end
    local inst = animInstance(t.actor)
    if inst and valid(t.montage) then pcall(function() inst:Montage_Stop(blend or 0.2, t.montage) end) end
    t.montage = nil
end

local function playOn(t, a)
    if state.mode == "pure" and not a.montage then
        stopOn(t, 0.1, true)
        local ok, err = pcall(function() t.actor.Mesh:PlayAnimation(a.obj, state.loop) end)
        if ok then t.single = true else log("PlayAnimation on " .. shortName(t.actor) .. ": " .. tostring(err):sub(1, 160)) end
        setSpeed(t, state.speed)
        setRoot(t, not state.root)
        return
    end
    stopOn(t, 0.1)
    setRoot(t, not state.root)
    local inst = animInstance(t.actor)
    if not inst then log(shortName(t.actor) .. ": no AnimInstance"); return end
    local ok, res = pcall(function()
        if a.montage then
            inst:Montage_Play(a.obj, 1.0, 0, 0.0, true)
            return a.obj
        end
        return inst:PlaySlotAnimationAsDynamicMontage(a.obj, FName(SLOT), 0.15, 0.15, 1.0,
            state.loop and 100000 or 1, -1.0, 0.0)
    end)
    if ok then t.montage = res else log("play on " .. shortName(t.actor) .. ": " .. tostring(res):sub(1, 160)) end
    setSpeed(t, state.speed)
end

local function cmdPlay(name, loop)
    local a = animByName(name)
    if not a then log("play: " .. name .. " is not in memory on this PC"); return end
    state.loop = (loop == "1")
    local keep = (state.mode == "pure" and not a.montage)   -- stay in single node: no AnimBlueprint reinit
    local again = findTargets()
    local still = {}
    for _, t in ipairs(again) do still[fullName(t.actor)] = true end
    for _, t in ipairs(targets) do
        -- anything that is no longer a target still goes back to the AnimBlueprint
        if valid(t.actor) then stopOn(t, 0.1, keep and still[fullName(t.actor)]) end
    end
    for _, t in ipairs(again) do
        for _, old in ipairs(targets) do
            if valid(old.actor) and fullName(old.actor) == fullName(t.actor) then t.single = old.single end
        end
    end
    state.playing, state.current = name, a
    state.abA, state.abB = nil, nil
    targets = again
    if #targets == 0 then log("play: player not found") end
    for _, t in ipairs(targets) do playOn(t, a) end
    log(string.format("play %s (%s, %.1f s, loop %s) on %d targets", name, a.montage and "montage" or "sequence",
        tonumber(a.len) or 0, tostring(state.loop), #targets))
end

local function cmdStop()
    for _, t in ipairs(targets) do
        if valid(t.actor) then
            if t.single then setRoot(t, false) end   -- the single node instance stays in memory: restore its mode
            stopOn(t, 0.2); setSpeed(t, 1); setRoot(t, false)
        end
    end
    state.playing, state.current, state.speed = nil, nil, 1
    log("stop")
end

local function cmdRoot(on)
    state.root = (on ~= "off")
    if state.playing then
        for _, t in ipairs(targets) do if valid(t.actor) then setRoot(t, not state.root) end end
    end
    log("root motion " .. (state.root and "yes" or "no (in place)"))
end

local function cmdSpeed(x)
    local v = tonumber(x)
    if not v or v < 0 or v > 2 then return end
    state.speed = v
    if #targets == 0 then targets = findTargets() end
    for _, t in ipairs(targets) do if valid(t.actor) then setSpeed(t, v) end end
    log("speed " .. v)
end

-- ---------------------------------------------------------------- animation position, A-B, rest pose, favorites
local FRAME = 1 / 30

local function posOf(t)
    if t.single then
        local ok, v = pcall(function() return t.actor.Mesh:GetPosition() end)
        return ok and tonumber(v) or nil
    end
    local inst = animInstance(t.actor)
    if inst and valid(t.montage) then
        local ok, v = pcall(function() return inst:Montage_GetPosition(t.montage) end)
        return ok and tonumber(v) or nil
    end
    return nil
end

local function setPos(t, p)
    if t.single then
        pcall(function()
            local mesh = t.actor.Mesh
            mesh:SetPosition(p, false)
            if not mesh:IsPlaying() then mesh:Play(state.loop) end   -- a finished animation restarts from there
        end)
        return
    end
    local inst = animInstance(t.actor)
    if inst and valid(t.montage) then
        local playing = true
        pcall(function() playing = inst:Montage_IsPlaying(t.montage) end)
        if not playing and state.current then playOn(t, state.current) end
        pcall(function() inst:Montage_SetPosition(t.montage, p) end)
    elseif state.current then
        playOn(t, state.current)
        inst = animInstance(t.actor)
        if inst and valid(t.montage) then pcall(function() inst:Montage_SetPosition(t.montage, p) end) end
    end
end

local function curLen()
    return state.current and tonumber(state.current.len) or 0
end

-- one-frame step (30 per second) forward/backward; pauses
local function cmdStep(dir)
    local d = tonumber(dir) or 1
    state.speed = 0
    for _, t in ipairs(targets) do
        if valid(t.actor) then
            setSpeed(t, 0)
            local p = posOf(t) or 0
            local L = curLen()
            local np = p + d * FRAME
            if L > 0 then np = math.max(0, math.min(L, np)) end
            setPos(t, np)
        end
    end
    local p = targets[1] and posOf(targets[1])
    log(string.format("frame %s: %s s", d > 0 and "forward" or "backward", p and string.format("%.3f", p) or "?"))
end

-- markers A and B from the current animation position; with both set, the A-B section repeats
local function cmdMark(which)
    local t = targets[1]
    local p = t and valid(t.actor) and posOf(t)
    if not p then log("A-B: no animation playing"); return end
    if which == "a" then state.abA = p else state.abB = p end
    if state.abA and state.abB and state.abB < state.abA then state.abA, state.abB = state.abB, state.abA end
    log(string.format("A-B: A=%s B=%s", tostring(state.abA), tostring(state.abB)))
end

-- Menu timeline: every 0.2 s, if it changed, the animation's "position length" goes to pos.txt (read by the C# mod).
local posCount, posLast = 0, nil
local function posTick()
    posCount = posCount + 1
    if posCount % 2 ~= 0 then return end
    local text = "- -"
    local t = targets[1]
    if state.playing and state.current and t and valid(t.actor) then
        local pp = posOf(t)
        if pp then text = string.format("%.3f %.3f", pp, curLen()) end
    end
    if text == posLast then return end
    posLast = text
    local f = io.open(POS_FILE, "w")
    if f then f:write(text, "\n"); f:close() end
end

local function abTick()
    if not (state.abA and state.abB and state.playing) or state.speed == 0 then return end
    for _, t in ipairs(targets) do
        if valid(t.actor) then
            local p = posOf(t)
            if p == nil or p >= state.abB or p < state.abA - 0.05 then setPos(t, state.abA) end
        end
    end
end

-- mesh rest pose: single node mode with no animation
local function cmdRefPose()
    cmdStop()
    for _, t in ipairs(targets) do
        if valid(t.actor) then
            local ok, err = pcall(function()
                local mesh = t.actor.Mesh
                mesh:SetAnimationMode(MODE_SINGLE, false)
                mesh:SetAnimation(nil)
            end)
            t.single = ok
            log("rest pose on " .. shortName(t.actor) .. ": " .. (ok and "OK" or tostring(err):sub(1, 160)))
        end
    end
    if #targets == 0 then
        targets = findTargets()
        if #targets > 0 then return cmdRefPose() end
    end
    state.playing = "rest_pose"   -- no spaces: the status line is "key=value" pairs separated by spaces
end

local function saveFavs()
    local f = io.open(FAV_FILE .. ".tmp", "w")
    if not f then return end
    for _, n in ipairs(favOrder) do f:write(n, "\n") end
    f:close()
    os.remove(FAV_FILE)
    os.rename(FAV_FILE .. ".tmp", FAV_FILE)
end

local function cmdFav(name)
    if not name or name == "" then return end
    if favs[name] then
        favs[name] = nil
        for i, n in ipairs(favOrder) do if n == name then table.remove(favOrder, i); break end end
        log("favorite removed: " .. name)
    else
        favs[name] = true
        favOrder[#favOrder + 1] = name
        log("favorite: " .. name)
    end
    saveFavs()
end

-- ---------------------------------------------------------------- bench camera (target "me")
-- Our own CameraActor becomes the PlayerController's view (SetViewTargetWithBlend) while the menu is open with
-- target "me". It is fixed in the world: the player's position and direction when it is turned on, so animations that
-- rotate or move the body can be read against a fixed reference. It orbits that point (framings and numeric
-- keypad); the distance comes from the capsule height, so it also works when scaled up or transformed.
-- The game recomputes its third-person camera every frame: that is why its spring arm is not touched.

local FOV = 50                                        -- horizontal (UE), less distorting than the game's
local ASPECT = 16 / 9
local VTAN = math.tan(math.rad(FOV / 2)) / ASPECT     -- tangent of half the vertical field
-- character at 35% of the width: the menu (560 px + margin) takes the right side of the screen
local LATERAL = math.deg(math.atan(0.30 * math.tan(math.rad(FOV / 2))))
PRESETS = {
    { name = "three_quarter", yaw = 35,  pitch = -8,  frame = "body" },
    { name = "front",         yaw = 0,   pitch = -5,  frame = "body" },
    { name = "profile",       yaw = 90,  pitch = -5,  frame = "body" },
    { name = "back",          yaw = 180, pitch = -8,  frame = "body" },
    { name = "close_up",      yaw = 25,  pitch = -4,  frame = "head" },
    { name = "feet",          yaw = 40,  pitch = -18, frame = "feet" },
}
cam = { on = false, preset = 1, yaw = 35, pitch = -8, zoom = 1, lift = 0, spin = false,
              anchor = nil, facing = 0, H = 180, base = 0, cur = nil, checkAt = nil, fp = false,
              vel = { orbit = 0, height = 0, zoom = 0 } }
local menuOpen = false

local function controllerOf(pawn)
    local pc = nil
    if pawn then pcall(function() pc = pawn.Controller end) end
    return valid(pc) and pc or nil
end

-- Menu open (0.7): game cursor on and player frozen.
-- ReadyM 1.1.0 does not give the mouse to pages during gameplay, but pages receive clicks when the game shows the
-- cursor (web-ui docs, CefInputMode). So: bShowMouseCursor + SetInputMode_GameAndUIEx, and the player is blocked
-- (DisableInput on the pawn: no attacks or blocks with clicks; movement and look input ignored: the mouse does not
-- turn the view). On close everything goes back as before; the unblock uses Reset*, which clears the game's counter.
local inputBlocked, cursorLogged = false, false
local wbl = nil

local function setCursor(pc, on)
    if not valid(wbl) then wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end
    pc.bShowMouseCursor = on
    if valid(wbl) then
        if on then wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false, false)
        else wbl:SetInputMode_GameOnly(pc, false) end
    end
end

local function updateInput()
    local want = menuOpen
    local pawn = localPawn()
    local pc = controllerOf(pawn)
    if not pc then return end
    if want == inputBlocked then
        -- the game may hide the cursor again (mode change, HUD): turn it back on every pass
        if want then
            local shown = true
            pcall(function() shown = pc.bShowMouseCursor end)
            if not shown then
                pcall(setCursor, pc, true)
                if not cursorLogged then cursorLogged = true; log("cursor: the game had hidden it, turned on again") end
            end
        end
        return
    end
    local ok, err = pcall(function()
        if want then
            setCursor(pc, true)
            pawn:DisableInput(pc)
            pc:SetIgnoreMoveInput(true); pc:SetIgnoreLookInput(true)
        else
            setCursor(pc, false)
            pawn:EnableInput(pc)
            pc:ResetIgnoreMoveInput(); pc:ResetIgnoreLookInput()
        end
    end)
    inputBlocked = want
    log((want and "menu open: cursor on, player frozen" or "menu closed: cursor off, player free")
        .. (ok and "" or (" (error: " .. tostring(err):sub(1, 160) .. ")")))
end

local function measure(pawn)
    local loc, rot = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
    local half = 90
    pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    cam.anchor = { X = loc.X, Y = loc.Y, Z = loc.Z }
    cam.facing = rot.Yaw
    cam.H = 2 * half
    cam.base = loc.Z - half
end

-- Camera target parameters (yaw around the character, pitch, vertical center, distance).
local function camTarget()
    local p = PRESETS[cam.preset]
    local H, base = cam.H, cam.base
    local cz, span
    if p.frame == "head" then cz, span = base + H * 0.88, H * 0.34
    elseif p.frame == "feet" then cz, span = base + H * 0.12, H * 0.40
    else cz, span = base + H * 0.50, H * 1.12 end
    cz = cz + cam.lift * H * 0.05
    return cam.yaw, cam.pitch, cz, (span / 2) / VTAN * cam.zoom
end

local function camPlace(dt)
    local ty, tp, tz, td = camTarget()
    local c = cam.cur
    if not c or dt == nil then
        c = { yaw = ty, pitch = tp, cz = tz, d = td }
        cam.cur = c
    else
        local k = 1 - math.exp(-10 * dt)          -- smooth follow (~0.1 s)
        local dy = (ty - c.yaw + 180) % 360 - 180   -- shortest turn
        c.yaw = c.yaw + dy * k
        c.pitch = c.pitch + (tp - c.pitch) * k
        c.cz = c.cz + (tz - c.cz) * k
        c.d = c.d + (td - c.d) * k
    end
    local a, pr = math.rad(cam.facing + c.yaw), math.rad(-c.pitch)
    local horiz = c.d * math.cos(pr)
    local px = cam.anchor.X + math.cos(a) * horiz
    local py = cam.anchor.Y + math.sin(a) * horiz
    local pz = c.cz + c.d * math.sin(pr)
    local yaw = math.deg(math.atan(cam.anchor.Y - py, cam.anchor.X - px)) + LATERAL
    local pitch = math.deg(math.atan(c.cz - pz, horiz))
    cam.actor:K2_SetActorLocationAndRotation({ X = px, Y = py, Z = pz }, { Pitch = pitch, Yaw = yaw, Roll = 0 }, false, {}, true)
end

local function spawnCamera(pawn)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local cls = StaticFindObject("/Script/Engine.CameraActor")
    if not (valid(gs) and valid(cls)) then return nil end
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                 Translation = { X = cam.anchor.X, Y = cam.anchor.Y, Z = cam.anchor.Z + 100 },
                 Scale3D = { X = 1, Y = 1, Z = 1 } }
    -- AlwaysSpawn = 1 (no collision check), MultiplyWithRoot = 1
    local a = gs:BeginDeferredActorSpawnFromClass(pawn, cls, xf, 1, pawn, 1)
    if not valid(a) then return nil end
    a = gs:FinishSpawningActor(a, xf, 1)
    if not valid(a) then return nil end
    pcall(function()
        local cc = a.CameraComponent
        cc.bConstrainAspectRatio = false
        cc:SetFieldOfView(FOV)
    end)
    return a
end

local function camApplyPreset(i)
    cam.preset = ((i - 1) % #PRESETS) + 1
    local p = PRESETS[cam.preset]
    cam.yaw, cam.pitch, cam.zoom, cam.lift = p.yaw, p.pitch, 1, 0
end

-- Game camera state, saved on open and restored on close. Bed, chair, horse etc. animations have notifies that change
-- the camera manager's state (CameraTags of VAltarPlayerCameraManager); played outside their context and
-- interrupted, they can leave it in a wrong state (test 2026-11-17 14:32: after closing, the view was stuck in first
-- person).
local gameView = nil

local function tagName(t)
    local ok, s = pcall(function() return t.TagName:ToString() end)
    return ok and s or "?"
end

local function viewSnapshot(pawn, pc)
    local s = {}
    pcall(function() s.target = pc:GetViewTarget() end)
    pcall(function() s.pcm = pc.PlayerCameraManager end)
    if valid(s.pcm) then
        pcall(function() s.tag = s.pcm:GetCurrentCameraTag() end)
        if s.tag == nil then pcall(function() s.tag = s.pcm.CameraTags end) end
        s.tagName = s.tag ~= nil and tagName(s.tag) or "?"
    end
    pcall(function() s.fp = pawn.bIsUsingFirstPersonMesh == true end)
    return s
end

local function describeView(s)
    return string.format("view %s, tag %s, first person %s", valid(s.target) and shortName(s.target) or "?",
        s.tagName or "?", tostring(s.fp))
end

local function restoreGameView(pawn, pc)
    if not gameView then return end
    local now = viewSnapshot(pawn, pc)
    log("game camera on close: " .. describeView(now) .. " (on open: " .. describeView(gameView) .. ")")
    if gameView.tag ~= nil and valid(now.pcm) and now.tagName ~= gameView.tagName then
        local ok, err = pcall(function() now.pcm:ChangeCameraTags(gameView.tag) end)
        log(ok and ("camera tag restored: " .. gameView.tagName)
            or ("camera tag: " .. tostring(err):sub(1, 160)))
    end
    -- end-of-animation notifies may arrive later: second check one second later (camTick)
    cam.recheck = { at = os.clock() + 1.0, view = gameView }
    gameView = nil
end

local function recheckGameView()
    local r = cam.recheck
    cam.recheck = nil
    local pawn = localPawn()
    local pc = controllerOf(pawn)
    if not (pawn and pc) then return end
    local now = viewSnapshot(pawn, pc)
    if r.view.tag ~= nil and valid(now.pcm) and now.tagName ~= r.view.tagName then
        local ok = pcall(function() now.pcm:ChangeCameraTags(r.view.tag) end)
        log("game camera after 1 s: tag " .. now.tagName .. ", restored " .. r.view.tagName ..
            (ok and "" or " (failed)"))
    else
        log("game camera after 1 s: " .. describeView(now))
    end
end

local function camOn()
    if cam.on then return end
    local pawn = localPawn()
    local pc = controllerOf(pawn)
    if not (pawn and pc) then log("camera: player or controller not found"); return end
    gameView = viewSnapshot(pawn, pc)
    log("game camera on open: " .. describeView(gameView))
    cam.fp = false
    pcall(function() cam.fp = pawn.bIsUsingFirstPersonMesh == true end)
    if cam.fp then log("camera: you are in first person, the body is not visible: switch to third person") end
    measure(pawn)
    if not valid(cam.actor) then
        local ok, res = pcall(spawnCamera, pawn)
        cam.actor = ok and res or nil
        if not ok then log("camera: creation failed: " .. tostring(res):sub(1, 200)) end
    end
    if not valid(cam.actor) then log("camera: CameraActor not created"); return end
    cam.cur = nil
    pcall(camPlace, nil)
    local ok, err = pcall(function() pc:SetViewTargetWithBlend(cam.actor, 0.5, 4, 2.0, false) end)
    if not ok then log("camera: SetViewTargetWithBlend: " .. tostring(err):sub(1, 160)); return end
    cam.on = true
    cam.checkAt = os.clock() + 1.0   -- technical check 1: does the game's camera manager leave the view to us?
    log(string.format("camera on: %s, height %.0f cm, FOV %d", PRESETS[cam.preset].name, cam.H, FOV))
end

local function camOff(reason)
    if not cam.on and not valid(cam.actor) then return end
    local pawn = localPawn()
    local pc = controllerOf(pawn)
    if cam.on and pc and pawn then
        -- go back to the view the game had on open (usually the pawn), then to its camera state
        local back = (gameView and valid(gameView.target)) and gameView.target or pawn
        pcall(function() pc:SetViewTargetWithBlend(back, 0.4, 4, 2.0, false) end)
        restoreGameView(pawn, pc)
    end
    cam.on, cam.spin = false, false
    cam.vel = { orbit = 0, height = 0, zoom = 0 }
    if valid(cam.actor) then
        local a = cam.actor
        cam.actor = nil
        -- destroyed after the transition: doing it now would leave the camera manager without a view for half a second
        cam.destroyAt = { actor = a, at = os.clock() + 0.6 }
    end
    log("camera off (" .. (reason or "-") .. ")")
end

-- Every frame (not every 100 ms): automatic rotation and follow must be smooth.
local function camTick(dt)
    if cam.destroyAt and os.clock() >= cam.destroyAt.at then
        local a = cam.destroyAt.actor
        cam.destroyAt = nil
        if valid(a) then pcall(function() a:K2_DestroyActor() end) end
    end
    if cam.recheck and os.clock() >= cam.recheck.at then pcall(recheckGameView) end
    if not cam.on then return end
    if not valid(cam.actor) then cam.on = false; log("camera lost (level change?)"); return end
    if cam.spin then cam.yaw = cam.yaw + 20 * dt end
    -- held keys (W A S D Q E): speed, not steps
    local v = cam.vel
    if v.orbit ~= 0 then cam.yaw = cam.yaw + v.orbit * 70 * dt end
    if v.height ~= 0 then cam.lift = math.max(-12, math.min(12, cam.lift + v.height * 5 * dt)) end
    if v.zoom ~= 0 then cam.zoom = math.max(0.3, math.min(3, cam.zoom * math.exp(v.zoom * 0.9 * dt))) end
    local ok, err = pcall(camPlace, dt)
    if not ok and not cam.placeErr then cam.placeErr = true; log("camera: " .. tostring(err):sub(1, 160)) end
    if cam.checkAt and os.clock() >= cam.checkAt then
        cam.checkAt = nil
        local pc = controllerOf(localPawn())
        local vt = nil
        if pc then pcall(function() vt = pc:GetViewTarget() end) end
        local ours = valid(vt) and valid(cam.actor) and fullName(vt) == fullName(cam.actor)
        log("camera check: view " .. (ours and "ours (OK)" or ("the game's: " .. (valid(vt) and shortName(vt) or "?"))))
    end
end

-- Technical check 2: does the player's visible body (MergedMeshComponent) follow the main mesh?
local function followReport(pawn)
    local merged, leader = nil, nil
    pcall(function() merged = pawn.MergedMeshComponent end)
    if not valid(merged) then log("body check: no MergedMeshComponent"); return end
    pcall(function() leader = merged.LeaderPoseComponent end)
    local mesh = nil
    pcall(function() mesh = pawn.Mesh end)
    local follows = valid(leader) and valid(mesh) and fullName(leader) == fullName(mesh)
    log("body check: merged mesh " .. (follows and "follows the main mesh (OK)"
        or ("driven by " .. (valid(leader) and shortName(leader) or "nothing") .. " instead of the main mesh")))
end

local function cmdCam(a1, a2)
    if a1 == "next" or a1 == "prev" then camApplyPreset(cam.preset + (a1 == "next" and 1 or -1))
    elseif a1 == "orbit" then cam.yaw = cam.yaw + 15 * (tonumber(a2) or 1)
    elseif a1 == "height" then cam.lift = math.max(-12, math.min(12, cam.lift + (tonumber(a2) or 1)))
    elseif a1 == "zoom" then cam.zoom = math.max(0.3, math.min(3, cam.zoom * ((tonumber(a2) or 1) > 0 and 1.12 or 1 / 1.12)))
    elseif a1 == "spin" then cam.spin = not cam.spin
    elseif a1 == "preset" then camApplyPreset(tonumber(a2) or 1)
    elseif a1 == "move" then
        -- "cam move <axis><P|N|0>": key held (orbitP, zoomN...) or released (orbit0)
        local axis, sign = (a2 or ""):match("^(%l+)([PN0])$")
        if axis and cam.vel[axis] ~= nil then cam.vel[axis] = (sign == "P" and 1) or (sign == "N" and -1) or 0 end
    elseif a1 == "drag" then
        -- drag in the menu's camera area: "dx_dy" in pixels
        local dx, dy = (a2 or ""):match("^(%-?%d+)_(%-?%d+)$")
        dx, dy = tonumber(dx), tonumber(dy)
        if dx and dy then
            cam.yaw = cam.yaw + dx * 0.4
            cam.lift = math.max(-12, math.min(12, cam.lift - dy * 0.05))
        end
    elseif a1 == "reset" then
        local pawn = localPawn()
        if pawn then pcall(measure, pawn) end
        camApplyPreset(cam.preset)
        cam.spin = false
    end
end

-- Starting point: where the player was when the menu opened. Animations with root motion (game mode,
-- montages) can move the player far away; F7 brings the player back there, standing still and facing the same way as
-- on open.
local home = nil

local function rememberHome()
    local p = localPawn()
    if not p then return end
    local ok, loc, rot = pcall(function() return p:K2_GetActorLocation(), p:K2_GetActorRotation() end)
    if ok then home = { loc = { X = loc.X, Y = loc.Y, Z = loc.Z }, rot = { Pitch = 0, Yaw = rot.Yaw, Roll = 0 } } end
end

local function cmdHome()
    if not home then log("starting point: not saved yet"); return end
    cmdStop()
    local p = localPawn()
    if not p then return end
    pcall(function() p.CharacterMovement:StopMovementImmediately() end)
    local ok, err = pcall(function() p:K2_SetActorLocationAndRotation(home.loc, home.rot, false, {}, true) end)
    log(ok and "back at the starting point" or ("return to the starting point: " .. tostring(err):sub(1, 160)))
end

-- Menu open: bench camera on. Menu closed: game camera.
local function menuChanged()
    if menuOpen then
        camOn()
        local pawn = localPawn()
        if pawn then followReport(pawn) end
    else
        camOff("menu closed")
    end
end

local function run(line)
    local verb, a1, a2 = line:match("^(%S+)%s*(%S*)%s*(%S*)")
    -- "r ...": menu command from another player (old versions or phase 2): never on the local player
    if verb == "r" then return end
    if verb == "open" then menuOpen = true; rememberHome(); updateInput(); menuChanged()
    elseif verb == "home" then cmdHome()
    elseif verb == "seek" then
        -- click on the menu timeline: position in seconds
        local p = tonumber(a1)
        if p then
            local L = curLen()
            if L > 0 then p = math.max(0, math.min(L, p)) end
            for _, t in ipairs(targets) do if valid(t.actor) then setPos(t, p) end end
        end
    elseif verb == "close" then
        menuOpen = false
        updateInput()
        cam.vel = { orbit = 0, height = 0, zoom = 0 }
        cmdStop()   -- with the menu closed the player goes back to their AnimBlueprint and moves normally
        menuChanged()
    elseif verb == "cam" then cmdCam(a1, a2)
    elseif verb == "scan" then scan()
    elseif verb == "play" then cmdPlay(a1, a2)
    elseif verb == "stop" then cmdStop()
    elseif verb == "speed" then cmdSpeed(a1)
    elseif verb == "mode" then state.mode = (a1 == "slot") and "slot" or "pure"; log("mode " .. state.mode)
    elseif verb == "root" then cmdRoot(a1)
    elseif verb == "step" then cmdStep(a1)
    elseif verb == "mark" then cmdMark(a1 == "b" and "b" or "a")
    elseif verb == "abclear" then state.abA, state.abB = nil, nil; log("A-B cleared")
    elseif verb == "refpose" then cmdRefPose()
    elseif verb == "fav" then cmdFav(a1)
    else return end
    writeList()
end

-- ---------------------------------------------------------------- reading cmd.txt

local lastSeq = nil       -- nil: first read, commands already in the file are not run
local lastText = nil

local function poll()
    if menuOpen then updateInput() end   -- keeps the cursor on if the game hides it
    abTick()
    posTick()
    local f = io.open(CMD_FILE, "r")
    if not f then if lastSeq == nil then lastSeq = 0 end; return end
    local text = f:read("*a") or ""
    f:close()
    if text == lastText then
        -- loop of real montages (looping sequences are already repeated by the dynamic montage)
        if state.loop and state.current and state.current.montage then
            for _, t in ipairs(targets) do
                local inst = valid(t.actor) and animInstance(t.actor)
                local playing = true
                if inst then pcall(function() playing = inst:Montage_IsPlaying(state.current.obj) end) end
                if inst and not playing then playOn(t, state.current) end
            end
        end
        return
    end
    lastText = text
    local pending, maxSeq = {}, 0
    for line in text:gmatch("[^\r\n]+") do
        local seq, cmd = line:match("^(%d+)%s+(.+)$")
        seq = tonumber(seq)
        if seq then
            if seq > maxSeq then maxSeq = seq end
            if lastSeq and seq > lastSeq then pending[#pending + 1] = { seq = seq, cmd = cmd } end
        end
    end
    if lastSeq == nil then lastSeq = maxSeq; return end
    table.sort(pending, function(x, y) return x.seq < y.seq end)
    for _, p in ipairs(pending) do
        local ok, err = pcall(run, p.cmd)
        if not ok then log("command '" .. p.cmd .. "': ERROR " .. tostring(err)) end
    end
    if maxSeq > lastSeq then lastSeq = maxSeq end
end

-- The work runs in the local player's ReceiveTick (game thread), every 100 ms.
-- NO LoopAsync + ExecuteInGameThread: with one pass every 100 ms while the world was loading, UE4SS crashed
-- (2026-11-16 19:09/19:10, AV in UE4SS.dll+0xF6DB63 ~10 s after the mods started).
local PLAYER_TICK = "/Game/Dev/PlayerBlueprints/BP_OblivionPlayerCharacter.BP_OblivionPlayerCharacter_C:ReceiveTick"
local accum, localAddr, pcClass = 0, nil, nil

local function onPlayerTick(ctx, deltaParam)
    local pawn = ctx:get()
    if not valid(pawn) then return end
    local okA, addr = pcall(function() return pawn:GetAddress() end)
    if not okA then return end
    if addr ~= localAddr then
        -- the other players have this Blueprint too: work only in the local one's tick
        local isLocal = false
        pcall(function()
            if not valid(pcClass) then pcClass = StaticFindObject("/Script/Engine.PlayerController") end
            local c = pawn.Controller
            isLocal = valid(c) and c:IsA(pcClass)
        end)
        if not isLocal then return end
        localAddr = addr
    end
    local dt = 0
    pcall(function() dt = deltaParam:get() end)
    if cam.on or cam.destroyAt or cam.recheck then
        local okC, errC = pcall(camTick, dt)
        if not okC then log("camera: ERROR " .. tostring(errC)) end
    end
    accum = accum + dt
    if accum < 0.1 then return end
    accum = 0
    local ok, err = pcall(poll)
    if not ok then log("poll: ERROR " .. tostring(err)) end
end

local hooked = false
local function tryHook(where)
    if hooked then return end
    if pcall(RegisterHook, PLAYER_TICK, onPlayerTick) then
        hooked = true
        log("hooked to the player's ReceiveTick (" .. where .. ")")
    end
end
tryHook("startup")
if not hooked then
    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function() tryHook("ClientRestart") end)
    pcall(RegisterInitGameStatePostHook, function() tryHook("InitGameState") end)
end

log("loaded: Alt+Y menu (OblivionMP mod Sefiro.AnimationMenu)")
