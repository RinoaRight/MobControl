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

local ENV_READY = "READY"
local ENV_FIRE_SERVER = "FIRE_SERVER"
local ENV_WORLD_READY = "WORLD_READY"

local ACTIVE_BULLETS_REPOSITORY = workspace:WaitForChild("Bullets")
Misc.AddPlayerCharToRaycastFilter(ACTIVE_BULLETS_REPOSITORY)
local INACTIVE_BULLETS_REPOSITORY = ReplicatedStorage:WaitForChild("Bullets")
local activeBulletsDataTable = {} :: { table }
local NIL_TABLE = { "NIL" }

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

local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")

-----------------------------
-- Net handlers
-----------------------------
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
    -- RemoteClient.ConnectToBroadcast(on_cc)
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

local ACTIVE_RUN_ANIM_TRACK

-- load run animation
local animateScript = LOCAL_CHARACTER:WaitForChild("Animate")
local RUN_ANIM_NAME = "RunAnim"
local RUN_ANIM = animateScript:WaitForChild("run"):WaitForChild(RUN_ANIM_NAME)

local function playRunAnimTrack(runAnimTrack)
    runAnimTrack:Play(0.100000001, 1, 2)
end

local function startRunAnim(character)
    local runAnimTrack = character.Humanoid:LoadAnimation(RUN_ANIM)
    runAnimTrack.Priority = Enum.AnimationPriority.Action4
    ACTIVE_RUN_ANIM_TRACK = runAnimTrack
    playRunAnimTrack(runAnimTrack)
end

-- TODO: wrap it into onPlayerConnect
do
    local LOCAL_PLAYER = game.Players.LocalPlayer
    local DRIVING_BOX_ATT = workspace:WaitForChild("DrivingBox", 10):FindFirstChild("Attachment")
    local playerAtt = Instance.new("Attachment") :: Attachment
    playerAtt.Name = "CloneGuideAtt"
    playerAtt.CFrame = (LOCAL_HUMANOID_ROOT_PART :: Part).CFrame
    playerAtt.Parent = LOCAL_HUMANOID_ROOT_PART
    local alignConst = Instance.new("AlignOrientation")
    alignConst.Parent = workspace
    alignConst.Attachment0 = playerAtt
    alignConst.Attachment1 = DRIVING_BOX_ATT
    startRunAnim(LOCAL_CHARACTER)
    -- diable jumping
    LOCAL_HUMANOID.JumpPower = 0
    -- TODO: only  enable if session is not started yet
    START_GUI.Enabled = true
    local btn = START_GUI:FindFirstChild("OKButton", true)
    print("LLLLLLLL", START_GUI, btn)
    maid.StartBtn = btn.MouseButton1Click:Connect(function()
        START_GUI.Enabled = false
        fire_server(Id.C2S.PLAYER_READY_TO_START)
        maid.StartBtn = nil
    end)
end

local function fireBullet(player)
    local bullet
    if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
        bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
    else
        bullet = Instance.new("Part")
        bullet.Name = "Bullet"
        bullet.CollisionGroup = "Bullet"
        -- bullet.Shape = Enum.PartType.Ball
        bullet.CanCollide = false
        bullet.Size = Vector3.new(2, 2, 2)
        bullet.Anchored = true
    end
    local player_char = player.Character
    local rootPart = assert(player_char.HumanoidRootPart) :: BasePart
    local pos = rootPart.Position + rootPart.CFrame.LookVector * SharedConfig.BULLET_RAYCAST_START_MULT
    bullet.Parent = ACTIVE_BULLETS_REPOSITORY
    bullet.Position = pos
    -- TODO: refactor, get the weapon from the player Ecs
    local weapon_id = Id.Weapon.BASIC
    -- TODO: refactor speed. is to be taken from C.Weapon
    local speed = S.Weapon[weapon_id].baseSpeed + rootPart.AssemblyLinearVelocity.Magnitude
    local boosterThickness = SharedConfig.BOOSTER_DEPTH
    local ttl = roflake.time() + SharedConfig.BULLET_BASE_DISTANCE / speed
    local boosterToHit, dist = Misc.IsBoosterToHit(pos)
    if boosterToHit then
        ttl = roflake.time() + ((dist + boosterThickness) / speed)
    end
    table.insert(activeBulletsDataTable, { bullet = bullet, speed = speed, ttl = ttl, booster = boosterToHit })
    if player == LOCAL_PLAYER then
        fire_server(Id.C2S.BULLET_SHOT, pos)
    end
end

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
        if #clones < 1 then
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
                if v.Name == RUN_ANIM_NAME then
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
        local bullet = bulletData.bullet :: Part
        local speed = S.Weapon[Id.Weapon.BASIC].baseSpeed + SharedConfig.MOVEMENT_LINEAR_VELOCITY
        local targetPos = CFrame.new(bullet.CFrame.Position + (bullet.CFrame.LookVector * speed * dt))
        local booster = bulletData.booster
        local ttl = bulletData.ttl
        if booster and booster.Position.Z >= bullet.Position.Z then
            -- bullet collided with the booster, delete it and signal to server
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
            Signal.Broadcast(Id.C2S.BOOSTER_HIT, booster.Name)
        elseif now >= ttl then
            -- bullet timed-out, delete it
            Array.swap_remove(activeBulletsDataTable, i)
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        else
            table.insert(activeBullets, bullet)
            table.insert(bulletsTargets, targetPos)
        end
    end
    local activeBulletsDataTableTemp = table.clone(activeBulletsDataTable)
    table.clear(activeBulletsDataTable)
    for i, bulletData in ipairs(activeBulletsDataTableTemp) do
        if bulletData ~= NIL_TABLE then
            table.insert(activeBulletsDataTable, bulletData)
        end
    end

    -- TODO: fake other players' bullets? (knowing their position and weapon from world state).
    workspace:BulkMoveTo(activeBullets, bulletsTargets, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire bullets for the local player
    local flags = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if flags and Id.flag_test(flags, Id.PlayerF.READY) then
        local weaponId = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.RefId) or Id.Weapon.BASIC
        local cooldown = S.Weapon[weaponId].cooldown
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local shot_ttl = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.TTL) or 0 :: num
            if shot_ttl <= 0 then
                fireBullet(LOCAL_PLAYER)
                -- TODO: clone fire
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
        local weapon_id = WORLD:get(playerId, W.WeaponId)
        if weapon_id ~= Id.Weapon._NONE then
            local shot_ttl = WORLD:get(playerId, W.TTL)
            if shot_ttl and shot_ttl <= 0 then
                fireBullet(player)
            end
        end
    end
end)

local isRunAnimActive
local infrequentLoop = supervisor.create(1, "client-infrequent")
local isRunStopped = false
infrequentLoop:start(function(dt)
    -- player character animation check
    local flags = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if Id.flag_test(flags, Id.PlayerF.READY) then
        for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
            if v.Name == RUN_ANIM_NAME then
                isRunAnimActive = true
                break
            end
        end
        if not isRunAnimActive then
            if not ACTIVE_RUN_ANIM_TRACK then
                startRunAnim(LOCAL_CHARACTER)
            else
                playRunAnimTrack(ACTIVE_RUN_ANIM_TRACK)
            end
        end
    else
        for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
            if v.Name == RUN_ANIM_NAME and not isRunStopped then
                isRunStopped = true
                v:Stop()
            end
        end
    end
end, 1, "test")

-- create clones if any new clones appeared
WORLD:set_on_attach(W.PLayerId, function(guid: guid, newplayerId: num)
    local id = WORLD:get(guid, W.RefId)
    if id and Id.kind(id) == Id.Kind.Clone then
        -- local clientInstance = WORLD:get(guid, W.ClientInstance)
        local clientInstance = workspace:FindFirstChild(guid, true)
        if not clientInstance then
            local newInstance = Clones.CreateClone(newplayerId, guid)
            if not newInstance then
                log:error("failed to create clone for player " .. newplayerId)
                return
            end
            -- WORLD:set(guid, W.ClientInstance, newInstance)
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
end)

WORLD:set_on_detach(W.RefId, function(guid: guid, oldValue: num)
    if Id.kind(oldValue) == Id.Kind.Boost then
        -- delete booster in PlayerState when it is deleted from world
        PLAYER_STATE:delete(guid)
    end

    if Id.kind(oldValue) == Id.Kind.Clone then
        -- delete clone if it was deleted from world
        local instance = workspace:FindFirstChild(guid, true)
        if instance then
            Disposer.dispose(instance)
            -- WORLD:delete(guid)
        else
            log:error("failed to delete clone instance for player " .. oldValue)
            return
        end
    end
end)
