--!nolint
--!strict

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()
print("dev mode: ", __DEV__)
local __TUTORIAL__ = not __DEV__ or false

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type id = int
type ulid = str
type guid = id | ulid
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format

type base64 = str

local DEBUG = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local shared = ReplicatedStorage.shared
local Array = require(shared.array)
local Id = require(shared.Id)
local S = require(shared.StaticData)

local logger = require(shared.logger)

local log = logger.create("init.client"):set_delimiter(" "):set_prettifier(Id.pp)
local trace = log:make_level_logger("trace")

local perfn = require(shared.perfn)
local roflake = require(shared.roflake)
local state = require(shared.state)
local Remote = require(shared.Remote)
local RemoteClient = Remote.Client :: Remote.Client<state.Replica>
type FireServer = Remote.FireServer
local SharedConfig = require(shared.SharedConfig)
local Disposer = require(shared.disposer)
local lpack = require(shared.lpack)
local base64 = lpack.base64
local En = require(shared.enum)
local iota = En.iota
local Stm = require(shared.STM)
local Signal = require(shared.signal)
local supervisor = require(shared.supervisor)
local Misc = require(shared.Misc)
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Clones = require(script.Clones)
local Booster = require(script.Boosters)
local NumFormat = require(shared.num_format)
local TaskPool = require(shared.TaskPool)

local ENV_READY = "READY"
local ENV_FIRE_SERVER = "FIRE_SERVER"
local ENV_WORLD_READY = "WORLD_READY"

local ACTIVE_BULLETS_REPOSITORY = workspace:WaitForChild("Bullets")
Misc.AddPlayerCharToRaycastFilter(ACTIVE_BULLETS_REPOSITORY)
local INACTIVE_BULLETS_REPOSITORY = ReplicatedStorage:WaitForChild("Bullets")
local activeBulletsDataTable = {} :: { table }
local NIL_TABLE = table.freeze { "NIL" }

-----------------------------
-- States
-----------------------------
local PLAYER_STATE = state.replica(SharedConfig.PlayerState.replica_config)
local C = SharedConfig.PlayerState.CId
PLAYER_STATE:env(ENV_READY, false)
local WORLD = state.replica(SharedConfig.World.replica_config)
local W = SharedConfig.World.CId
WORLD:env(ENV_WORLD_READY, false)
-----------------------------

local Players = game:GetService("Players")
local LOCAL_PLAYER = Players.LocalPlayer
repeat
    wait()
until LOCAL_PLAYER.Character
local LOCAL_CHARACTER = LOCAL_PLAYER.Character
local LOCAL_HUMANOID = LOCAL_PLAYER.Character:WaitForChild("Humanoid")
local LOCAL_HUMANOID_ROOT_PART = assert(LOCAL_PLAYER.Character:WaitForChild("HumanoidRootPart"))
local LOCAL_HUMANOID_HEAD = assert(LOCAL_PLAYER.Character:WaitForChild("Head"))

local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)

-- forward declarations
local playRunAnimTrack
local startRunAnim

local _other_player = PLAYER_STATE:constructor(C.ClientRefId, C.ClientTTL)
local function setOtherPlayerToState(player_id, weapon_id)
    if PLAYER_STATE:has(player_id) or player_id == LOCAL_PLAYER.UserId then
        return
    end

    local ttl
    if weapon_id ~= Id.Weapon._NONE then
        ttl = S.Weapon[weapon_id].cooldown
    end
    _other_player(player_id, weapon_id, ttl)
end

local function handleGunHoldingAnimation(character, weapon_id: int)
    local humanoid = assert(character:WaitForChild("Humanoid"))
    local animId = S.Animation[Id.Animation.HOLD]
    local activeHoldAnimTrack
    for _, animTrack in ipairs(humanoid:GetPlayingAnimationTracks()) do
        if animTrack.Animation.AnimationId == animId then
            activeHoldAnimTrack = animTrack
            break
        end
    end

    if weapon_id == Id.Weapon._NONE and activeHoldAnimTrack then
        activeHoldAnimTrack:Stop()
    else
        if not activeHoldAnimTrack then
            local holdAnimation = Instance.new("Animation")
            holdAnimation.AnimationId = animId
            local newHoldAnimTrack = character.Humanoid:LoadAnimation(holdAnimation)
            activeHoldAnimTrack = newHoldAnimTrack
        end
        activeHoldAnimTrack.Priority = Enum.AnimationPriority.Action4
        activeHoldAnimTrack:Play(0.100000001, 1, 2)
    end
end

-----------------------------
-- Net handlers
-----------------------------
-- Server Events
local on = {} :: Remote.OnRemoteEvent<state.Replica>

on[Id.S2C.UPDATE_STATE] = function(state: state.Replica, update_log)
    state:update(update_log)
end

on[Id.S2C.INIT_WORLD] = function(state: state.Replica, world_snapshot)
    WORLD:init(world_snapshot)
    WORLD:env(ENV_WORLD_READY, true)
    log:info("world ready")
end

on[Id.S2C.UPDATE_WORLD] = function(state: state.Replica, update_log)
    WORLD:update(update_log)
end

on[Id.S2C.PLAYER_DAMAGED] = function(state: state.Replica, new_hp: int)
    Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, new_hp)
    S.Sound[Id.Sound.SCREAM]:Play()
end

on[Id.S2C.PLAYER_DIED] = function(state: state.Replica)
    LOCAL_HUMANOID.JumpPower = 50
    LOCAL_HUMANOID_ROOT_PART:FindFirstChild(SharedConfig.CLONE_ATTACHMENT_NAME):Destroy()
    for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
        if v.Name == SharedConfig.RUN_ANIMATION_NAME then
            v:Stop()
        end
    end
    -- kill his clones
    local clonesFolder = LOCAL_CHARACTER:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clonesFolder then
        clonesFolder:Destroy()
    end
end

-- Server Broadcasts
local on_cc = {} :: { [id]: (...any) -> () }

on_cc[Id.S2CC.PLAYER_STARTED_SESSION] = function(player_id: id)
    if player_id == LOCAL_PLAYER.UserId then
        local hp = SharedConfig.PLAYER_BASE_HP
        Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, hp)
        -- the rest of the logic is already done in subscribeStartCollider
        return
    else
        local player = Players:GetPlayerByUserId(player_id)
        local character = player.Character or player:WaitForChild("Character", 10)
        if not character then
            return
        end
        local humanoid = character:WaitForChild("Humanoid")
        local _ = startRunAnim(character)
    end
end

on_cc[Id.S2CC.PLAYER_STOPPED_SESSION] = function(player_id: id)
    if player_id == LOCAL_PLAYER.UserId then
        -- the logic is already done in on[Id.S2C.PLAYER_DIED]
        return
    else
        local player = Players:GetPlayerByUserId(player_id)
        local character = player.Character or player:WaitForChild("Character", 10)
        if not character then
            return
        end
        local humanoid = character:WaitForChild("Humanoid")
        for _, v in ipairs(humanoid:GetPlayingAnimationTracks()) do
            if v.Name == SharedConfig.RUN_ANIMATION_NAME then
                v:Stop()
            end
        end
        -- kill his clones
        local clonesFolder = character:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
        if clonesFolder then
            clonesFolder:Destroy()
        end
    end
end

on_cc[Id.S2CC.PLAYER_CHANGED_WEAPON] = function(player_id: id, weapon_id: id)
    -- handle hold_anim for player
    local playerChar
    if player_id == LOCAL_PLAYER.UserId then
        playerChar = LOCAL_CHARACTER
    else
        local player = Players:GetPlayerByUserId(player_id)
        if not player then
            PLAYER_STATE:delete(player_id)
            return
        end
        playerChar = player.Character
    end

    handleGunHoldingAnimation(playerChar, weapon_id)

    -- handle hold_anim and weapon_instance for clones
    local playerRootPart = assert(playerChar.HumanoidRootPart) :: Part
    local clonesFolder = playerChar:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clonesFolder then
        local clones = clonesFolder:GetChildren()
        if clones and #clones > 1 then
            for i, clone in ipairs(clones) do
                handleGunHoldingAnimation(clone, weapon_id)
                -- handle weapon instance for clones
                local gunHand = clone:FindFirstChild("RightHand")
                local weaponInstance = gunHand:FindFirstChildWhichIsA("Model")
                if weapon_id == Id.Weapon._NONE then
                    -- player has removed weapon, remove it for clones as well
                    if weaponInstance then
                        weaponInstance:Destroy()
                    end
                else
                    -- player has equipped weapon, equip it for clones as well
                    if not weaponInstance then
                        -- clone doesn't yet have weapon, equip it
                        Misc.EquipWeaponModel(clone, weapon_id)
                    elseif weaponInstance and weaponInstance.Name ~= S.Weapon[weapon_id].name then
                        -- clone is carrying different weapon than the player, change it
                        weaponInstance:Destroy()
                        Misc.EquipWeaponModel(clone, weapon_id)
                    end
                end
            end
        end
    end

    -- SFX and initial bullet TTL
    if player_id == LOCAL_PLAYER.UserId then
        if weapon_id ~= Id.Weapon._NONE then
            S.Sound[Id.Sound.RELOAD]:Play()
        end
    else
        local ttl = S.Weapon[Id.Weapon.BASIC].cooldown
        if weapon_id ~= Id.Weapon._NONE then
            ttl = S.Weapon[weapon_id].cooldown
        end
        if not PLAYER_STATE:has(player_id) then
            log:error("No entity for this player_id in player's state", player_id)
            return
        end
        PLAYER_STATE:set(player_id, C.ClientRefId, weapon_id)
        PLAYER_STATE:set(player_id, C.ClientTTL, ttl)
    end
end

-----------------------------
-- Handshake
-----------------------------
local maid = Disposer.new()
local load = function(fire: FireServer, snapshot)
    local state = PLAYER_STATE
    PLAYER_STATE:init(snapshot)
    PLAYER_STATE:env(ENV_FIRE_SERVER, fire)
    PLAYER_STATE:env(ENV_READY, true)
    log:debug("~~~", PLAYER_STATE:format_state("*"))
    RemoteClient.ConnectToBroadcast(on_cc)
    for _, id in Id.C2S:ids() do
        maid:Add(Signal.Connect(id, function(...)
            fire(id, ...)
        end))
    end
    return state
end

local fire_server, disposable, state, us2cc = RemoteClient.Handshake(load, on)

local DRIVING_BOX_INSTANCE = workspace:FindFirstChild("DrivingBox")
repeat
    wait()
until DRIVING_BOX_INSTANCE
Misc.AddPlayerCharToRaycastFilter(DRIVING_BOX_INSTANCE)
local DRIVING_BOX_FRONT = DRIVING_BOX_INSTANCE.PartFront
local LOCAL_PLAYER = game.Players.LocalPlayer
local DRIVING_BOX_ATT = workspace:WaitForChild("DrivingBox", 10):FindFirstChild("Attachment")

-- load run animation
local animateScript = LOCAL_CHARACTER:WaitForChild("Animate")
local RUN_ANIM = animateScript:WaitForChild("run"):WaitForChild(SharedConfig.RUN_ANIMATION_NAME)

playRunAnimTrack = function(runAnimTrack)
    runAnimTrack:Play(0.100000001, 1, 2)
    runAnimTrack.Priority = Enum.AnimationPriority.Action3
end

startRunAnim = function(character)
    local runAnimTrack = character.Humanoid:LoadAnimation(RUN_ANIM)
    runAnimTrack.Priority = Enum.AnimationPriority.Action3
    playRunAnimTrack(runAnimTrack)
    return runAnimTrack
end

local function subscribeStartCollider()
    local SESSION_STARTER_COLLIDER = assert(workspace:WaitForChild("SessionStarter"):FindFirstChild("Collider"))
    local START_BTN = START_GUI:FindFirstChild("OKButton", true)
    maid.StartCollider = SESSION_STARTER_COLLIDER.Touched:Connect(function(other)
        if other == LOCAL_HUMANOID_ROOT_PART then
            START_GUI.Enabled = true
            maid.StartBtn = START_BTN.MouseButton1Click:Connect(function()
                -- diable jumping
                LOCAL_HUMANOID.JumpPower = 0
                local playerAtt = Instance.new("Attachment") :: Attachment
                playerAtt.Name = SharedConfig.CLONE_ATTACHMENT_NAME
                playerAtt.CFrame = (LOCAL_HUMANOID_ROOT_PART :: Part).CFrame
                playerAtt.Parent = LOCAL_HUMANOID_ROOT_PART
                START_GUI.Enabled = false
                fire_server(Id.C2S.PLAYER_READY_TO_START)
                startRunAnim(LOCAL_CHARACTER)
                maid.StartBtn = nil
            end)
            maid.StartCollider = SESSION_STARTER_COLLIDER.TouchEnded:Connect(function(other)
                if other == LOCAL_HUMANOID_ROOT_PART then
                    START_GUI.Enabled = false
                    subscribeStartCollider()
                end
            end)
        end
    end)
end

-- Initialization
do
    TaskPool.spawn(function()
        -- initial subscription of the start button
        subscribeStartCollider()

        -- initialization of other players to the player_state
        local allPlayers = Players:GetPlayers()
        for _, player in ipairs(allPlayers) do
            if player == LOCAL_PLAYER then
                continue
            end
            local player_id = player.UserId
            repeat
                task.wait()
            until WORLD:has(player_id)
            local weapon_id = WORLD:get(player_id, W.WeaponId)
            setOtherPlayerToState(player.UserId, weapon_id)
        end
        -- initialize player's hp GUI
        PLAYER_HP_GUI.Adornee = LOCAL_HUMANOID_HEAD
        PLAYER_HP_TEXT_BOX.Text = ""
    end)
end

local function spawnBullet(player, rootPart: BasePart, weapon_id: id)
    local bullet
    local pos
    if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
        bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
    else
        bullet = Instance.new("Part")
        bullet.Name = SharedConfig.BULLET_NAME
    end

    -- set bullet properties
    bullet.CollisionGroup = "Bullet"
    bullet.CanCollide = false
    bullet.Anchored = true
    bullet:SetAttribute(SharedConfig.BULLET_ATTRIBUTE_NAME, player.UserId)
    local s = 1
    if S.Weapon[weapon_id].bulletSize then
        s = S.Weapon[weapon_id].bulletSize
    end
    bullet.Size = Vector3.new(s, s, s)

    -- set bullet's position
    local pos = rootPart.Position + rootPart.CFrame.LookVector * SharedConfig.BULLET_RAYCAST_START_MULT
    bullet.Parent = ACTIVE_BULLETS_REPOSITORY
    local speed = S.Weapon[weapon_id].baseSpeed + rootPart.AssemblyLinearVelocity.Magnitude
    -- local targetThickness = SharedConfig.BOOSTER_DEPTH
    -- local boosterThickness = SharedConfig.BOOSTER_DEPTH
    local range = SharedConfig.BULLET_BASE_DISTANCE
    if S.Weapon[weapon_id].range then
        range = S.Weapon[weapon_id].range
    end
    local bulletTTL = roflake.time() + range / speed
    -- local targetToHit, dist = Misc.IsBulletCollidableToHit(pos)

    -- if targetToHit then
    --     if WORLD:has(targetToHit.Name) then
    --         local refId = WORLD:get(targetToHit.Name, W.RefId)
    --         local instance = WORLD:get(targetToHit.Name, W.ServerInstance)
    --         targetThickness = instance.Size.Z
    --     end
    --     timeToArrive = roflake.time() + ((math.max(dist - targetThickness/2, 0)) / speed)
    -- end

    bullet.Position = pos

    table.insert(activeBulletsDataTable, {
        bullet = bullet,
        speed = speed,
        ttl = bulletTTL,
        -- booster = targetToHit,
        owner = player,
        weapon_id = weapon_id,
        rotation = CFrame.Angles(0, 0, 0),
    })

    local indexInTable = #activeBulletsDataTable

    return pos, indexInTable
end

local function setShotgunBulletsToDataTable(player, playerRootPart, weapon_id)
    -- generate multiple bullets and set different rotation for each of them to the data table of active bullets
    local pos
    for i = 1, 5 do
        local bulletPos, indexInTable = spawnBullet(player, playerRootPart, weapon_id)
        local yRot = 0
        if i == 2 then
            yRot = 2
        elseif i == 3 then
            yRot = 4
        elseif i == 4 then
            yRot = -2
        elseif i == 5 then
            yRot = -4
        end
        pos = bulletPos -- they are overwriting each other, but it doesnt' matter cuz they are the same
        local rot = CFrame.Angles(0, math.rad(yRot), 0)
        activeBulletsDataTable[indexInTable].rotation = rot
    end
    return pos
end

local function fireBullet(player)
    local player_char = player.Character
    local playerRootPart = assert(player_char.HumanoidRootPart) :: BasePart
    local weapon_id

    if player == LOCAL_PLAYER then
        weapon_id = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.RefId)
    else
        weapon_id = PLAYER_STATE:get(player.UserId, C.ClientRefId)
    end
    if not weapon_id or weapon_id == Id.Weapon._NONE then
        return
    end

    -- player's fire
    local pos
    if weapon_id == Id.Weapon.SHOTGUN then
        pos = setShotgunBulletsToDataTable(player, playerRootPart, weapon_id)
    else
        pos = spawnBullet(player, playerRootPart, weapon_id)
    end

    -- clones' fire (is handled as an additional local player's fire)
    local clones_folder = player_char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clones_folder then
        for _, clone in ipairs(clones_folder:GetChildren()) do
            local rootPart = clone.HumanoidRootPart
            pos = spawnBullet(player, rootPart, Id.Weapon.BASIC)
            if weapon_id == Id.Weapon.SHOTGUN then
                pos = setShotgunBulletsToDataTable(player, rootPart, weapon_id)
            else
                pos = spawnBullet(player, rootPart, weapon_id)
            end
        end
    end

    if player == LOCAL_PLAYER then
        -- reset ttl server-side
        fire_server(Id.C2S.BULLET_SHOT)
        -- TODO: change sound for each type of weapon
        S.Sound[Id.Sound.FIRE_PISTOL]:Play()
    else
        -- TODO: change sound for each type of weapon
        Misc.SoundLocalizedAudio(S.Sound[Id.Sound.FIRE_PISTOL_LOCALIZED], pos, 0)
        -- reset ttl for fake fire on the client
        local weapon_id = PLAYER_STATE:get(player.UserId, C.ClientRefId)
        local ttl
        if weapon_id and weapon_id ~= Id.Weapon._NONE then
            ttl = S.Weapon[weapon_id].cooldown
        end
        PLAYER_STATE:set(player.UserId, C.ClientTTL, ttl)
    end
end


-- TODO: move the whole bullets logic to server and make the shooting automatic
RunService.Heartbeat:Connect(function(dt)
    local players = game:GetService("Players"):GetPlayers()
    if #players < 1 then
        return
    end

    -- move clones
    local clonesRootParts = {}
    local clonesTargets = {}
    local playerRootPart
    for _, player in ipairs(players) do
        local char = player.Character
        playerRootPart = assert(char.HumanoidRootPart) :: Part
        local clonesFolder = char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
        if not clonesFolder then
            continue
        end
        local clones = clonesFolder:GetChildren()
        if clones and #clones < 1 then
            continue
        end
        for i, clone in ipairs(clones) do
            local pos = playerRootPart.Position
            local cloneRootPart = clone:FindFirstChild("HumanoidRootPart")
            if not cloneRootPart then
                continue
            end
            local isRunAnimActive = false
            local cloneAnimTracks = clone.Humanoid:GetPlayingAnimationTracks()
            for _, v in ipairs(cloneAnimTracks) do
                if v.Name == SharedConfig.RUN_ANIMATION_NAME then
                    isRunAnimActive = true
                    break
                end
            end
            if not isRunAnimActive then
                startRunAnim(clone)
            end

            local alreadyInCol = (i - 1) % SharedConfig.CLONES_IN_A_ROW
            local row = math.floor((i - 1) / SharedConfig.CLONES_IN_A_ROW) + 1
            local clonePos = Misc.GetClonePos(pos, alreadyInCol, row)
            local cloneTarget = CFrame.lookAlong(clonePos, playerRootPart.CFrame.LookVector, Vector3.yAxis)
            table.insert(clonesRootParts, cloneRootPart)
            table.insert(clonesTargets, cloneTarget)
            workspace:BulkMoveTo(clonesRootParts, clonesTargets, Enum.BulkMoveMode.FireCFrameChanged)
        end
    end

    -- move existing bullets
    local activeBullets = {}
    local bulletsTargets = {}
    local now = roflake.time()
    for i, bulletData in ipairs(activeBulletsDataTable) do
        -- check for collisions
        local bullet = bulletData.bullet :: Part
        -- local booster = bulletData.booster
        local owner = bulletData.owner
        local ttl = bulletData.ttl
        local rot = bulletData.rotation
        local weapon_id = bulletData.weapon_id
        local speed = bulletData.speed
        local target, _dist = Misc.IsBulletCollidableToHit(bullet.Position)

        local targetCframe = CFrame.new(bullet.Position + (bullet.CFrame.LookVector * speed * dt)) * rot
        local targetThickness
        local targetRefId
        local isTargetKillable
        if target and WORLD:has(target.Name) then
            targetRefId = WORLD:get(target.Name, W.RefId)
            -- local instance = WORLD:get(target.Name, W.ServerInstance)
            if not targetRefId then
                log:error("no refId or instance for the bullet target", targetRefId, target.ClassName)
                return
            end
            if Id.kind(targetRefId) == Id.Kind.Boost then
                targetThickness = SharedConfig.BOOSTER_DEPTH
                isTargetKillable = true
            elseif Id.kind(targetRefId) == Id.Kind.Enemy then
                targetThickness = SharedConfig.REGULAR_ENEMY_HITBOX_RADIUS
                isTargetKillable = true
            end
        end
        if target and isTargetKillable and (target.Position.Z + targetThickness + 1 >= bullet.Position.Z) then
            -- bullet collided with the target, delete it and signal to server
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
            if owner == LOCAL_PLAYER then
                if Id.kind(targetRefId) == Id.Kind.Boost then
                    Signal.Broadcast(Id.C2S.BOOSTER_HIT)
                elseif Id.kind(targetRefId) == Id.Kind.Enemy then
                    fire_server(Id.C2S.ENEMY_HIT)
                end
            end
        elseif now >= ttl then
            -- bullet timed-out, delete it
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        else
            table.insert(activeBullets, bullet)
            table.insert(bulletsTargets, targetCframe)
        end
    end
    -- remove all NIL_TABLEs from the table
    local activeBulletsDataTableTemp = table.clone(activeBulletsDataTable)
    table.clear(activeBulletsDataTable)
    for i, bulletData in ipairs(activeBulletsDataTableTemp) do
        if bulletData ~= NIL_TABLE then
            table.insert(activeBulletsDataTable, bulletData)
        end
    end

    workspace:BulkMoveTo(activeBullets, bulletsTargets, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire bullets for the local player
    if PLAYER_STATE:has(Id.PlayerStats.GAME_SESSION) then
        local flags = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
        if flags and Id.flag_test(flags, Id.PlayerF.READY) then
            local weaponId = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.RefId)
            if not weaponId or weaponId == Id.Weapon._NONE then
                log:error("No bullet can be fired for this weapon_id", weaponId)
            end
            if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                local shot_ttl = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.TTL) :: num
                if shot_ttl and shot_ttl <= 0 then
                    fireBullet(LOCAL_PLAYER)
                end
            end
        end
    end

    -- fake bullets' animation for other players
    for _, player in ipairs(players) do
        if player == LOCAL_PLAYER then
            continue
        end
        if not WORLD:env(ENV_WORLD_READY) then
            log:warn("WORLD is not ready yet")
            continue
        end
        local playerId = player.UserId
        if PLAYER_STATE:has(playerId) then
            local weapon_id = PLAYER_STATE:get(playerId, C.ClientRefId)
            if weapon_id and weapon_id ~= Id.Weapon._NONE then
                -- player is inside the game session, fire bullets
                local shot_ttl = PLAYER_STATE:get(playerId, C.ClientTTL)
                if shot_ttl then
                    shot_ttl -= dt
                    if shot_ttl <= 0 then
                        fireBullet(player)
                    else
                        PLAYER_STATE:set(playerId, C.ClientTTL, shot_ttl)
                    end
                end
            end
        end
    end
end)

local ACTIVE_RUN_ANIM_TRACK
local infrequentLoop = supervisor.create(1, "client-infrequent")
infrequentLoop:start(function(dt)
    -- player character animation check
    local isRunAnimActive
    local flags = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if flags and Id.flag_test(flags, Id.PlayerF.READY) then
        for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
            if v.Name == SharedConfig.RUN_ANIMATION_NAME then
                isRunAnimActive = true
                break
            end
        end
        if not isRunAnimActive then
            if not ACTIVE_RUN_ANIM_TRACK then
                -- animation track not loaded yet
                ACTIVE_RUN_ANIM_TRACK = startRunAnim(LOCAL_CHARACTER)
            else
                playRunAnimTrack(ACTIVE_RUN_ANIM_TRACK)
            end
        end
    end
end, 1, "test")

-- create clones if any new clones appeared
WORLD:set_on_attach(W.PLayerId, function(guid: guid, newplayerId: num)
    local id = WORLD:get(guid, W.RefId)
    if id and Id.kind(id) == Id.Kind.Clone then
        local clientInstance = workspace:FindFirstChild(guid, true)
        if not clientInstance then
            local newInstance = Clones.CreateClone(newplayerId, guid)
            local weaponId = PLAYER_STATE:get(newplayerId, C.ClientRefId)
            handleGunHoldingAnimation(newInstance, weaponId)
            if not newInstance then
                log:error("failed to create clone for player " .. newplayerId)
                return
            end
        end
    end
end)

-- subscribe boosters to collisions
local _booster = PLAYER_STATE:constructor(C.ClientFlags)
WORLD:set_on_attach(W.RefId, function(guid: guid, newValue: num)
    log:debug("~~~>", guid)
    -- check if it was a booster that has been added
    if Id.kind(newValue) == Id.Kind.Boost then
        _booster(guid, false)
        Signal.Broadcast(Id.C2C.NEW_BOOSTER_ADDED, WORLD, PLAYER_STATE, guid)
    end

    -- -- check if it was an enemy that has been added
    -- if Id.kind(newValue) == Id.Kind.Enemy then
    --     Signal.Broadcast(Id.C2C.NEW_ENEMY_ADDED, WORLD, PLAYER_STATE, guid)
    -- end
end)

-- -- cancel collision subscription
-- WORLD:set_on_detach(W.RefId, function(guid: guid, oldValue: num)
--     if Id.kind(oldValue) == Id.Kind.Enemy then
--         Signal.Broadcast(Id.C2C.ENEMY_REMOVED, guid)
--     end
-- end)

-- set newly connected players to the player state
WORLD:set_on_attach(W.WeaponId, function(guid: guid, newValue: num)
    log:debug("~~~>", guid)
    if type(guid) == "number" and Id.kind(newValue) == Id.Kind.Weapon then
        -- new player connected to the server
        setOtherPlayerToState(guid, newValue)
    end
end)

WORLD:set_on_detach(W.WeaponId, function(guid: guid, oldValue: num)
    if Id.kind(oldValue) == Id.Kind.Weapon then
        -- player has left the server, delete them from playerState
        if PLAYER_STATE:has(guid) then
            PLAYER_STATE:delete(guid)
        else
            log:error("failed to delete player entity from player state")
            return
        end
    end
end)

PLAYER_STATE:set_on_modify(C.TTL, function(guid: guid, newValue: num, oldValue: num) end)
