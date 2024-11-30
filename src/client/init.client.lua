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

local ENV_READY = "READY"
local ENV_FIRE_SERVER = "FIRE_SERVER"
local ENV_WORLD_READY = "WORLD_READY"

local ACTIVE_BULLETS_REPOSITORY = workspace:WaitForChild("Bullets")
local INACTIVE_BULLETS_REPOSITORY = ReplicatedStorage:WaitForChild("Bullets")
local activeBulletsDataTable = {}

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
-- Net handlers
-----------------------------
local on = {} :: Remote.OnRemoteEvent<state.Replica>

on[Id.S2C.UPDATE_STATE] = function(state: state.Replica, update_log)
    state:update(update_log)
end

on[Id.S2C.INIT_WORLD] = function(state: state.Replica, world_snapshot)
    WORLD:init(world_snapshot)
    WORLD:env(ENV_WORLD_READY, true)
    log:debug("~~~", WORLD:format_state("*"))
end

on[Id.S2C.UPDATE_WORLD] = function(state: state.Replica, update_log)
    WORLD:update(update_log)
end

-----------------------------
-- Handshake
-----------------------------

local load = function(fire: FireServer, snapshot)
    local state = PLAYER_STATE
    PLAYER_STATE:init(snapshot)
    PLAYER_STATE:env(ENV_FIRE_SERVER, fire)
    PLAYER_STATE:env(ENV_READY, true)
    log:debug("~~~", PLAYER_STATE:format_state("*"))
    -- RemoteClient.ConnectToBroadcast(on_cc)
    return state
end

local fire_server, disposable, state, us2cc = RemoteClient.Handshake(load, on)

local Players = game:GetService("Players")
local LOCAL_PLAYER = Players.LocalPlayer
repeat
    wait()
until LOCAL_PLAYER.Character
local LOCAL_CHARACTER = LOCAL_PLAYER.Character
local LOCAL_HUMANOID = LOCAL_PLAYER.Character:WaitForChild("Humanoid")
local LOCAL_HUMANOID_ROOT_PART = assert(LOCAL_PLAYER.Character:WaitForChild("HumanoidRootPart"))
-- local PLAYER_SPAWN_POS = LOCAL_CHARACTER.Position
local DRIVING_BOX_INSTANCE = workspace:FindFirstChild("DrivingBox")
repeat
    wait()
until DRIVING_BOX_INSTANCE
local DRIVING_BOX_FRONT = DRIVING_BOX_INSTANCE.PartFront

-- load run animation
local animateScript = LOCAL_CHARACTER:WaitForChild("Animate")
local RUN_ANIM_NAME = "RunAnim"
local RUN_ANIM = animateScript:WaitForChild("run"):WaitForChild(RUN_ANIM_NAME)

local function startRunAnim(character)
    local runAnim = character.Humanoid:LoadAnimation(RUN_ANIM)
    runAnim.Priority = Enum.AnimationPriority.Action4
    runAnim:Play(0.100000001, 1, 2)
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
    -- TODO: refactor = move it from here to a loop where all clones of all players are assigned their pos
    local players = game:GetService("Players"):GetPlayers()
    for _, player in ipairs(players) do
        Clones.CreateClone(player.UserId, player.Character)
    end
end

local function fireBulletPlayer(player)
    local bullet
    if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
        bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
    else
        bullet = Instance.new("Part")
        bullet.Name = "Bullet"
        bullet.CollisionGroup = "Bullet"
        bullet.Size = Vector3.new(0.2, 0.2, 0.2)
        bullet.Anchored = true
    end
    local player_char = player.Character
    local rootPart = assert(player_char.HumanoidRootPart) :: BasePart
    local pos = rootPart.Position + rootPart.CFrame.LookVector * 2
    bullet.Parent = ACTIVE_BULLETS_REPOSITORY
    bullet.Position = pos
    local rayOrigin = pos
    local rayDirection = Vector3.new(pos.X, pos.Y, pos.Z + SharedConfig.BULLET_BASE_DISTANCE)
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection)
    -- TODO: refactor, get the weapon from the player Ecs
    local weapon_id = Id.Weapon.BASIC
    -- TODO: refactor speed. is to be taken from C.Weapon
    local speed = S.Weapon[weapon_id].baseSpeed + rootPart.AssemblyLinearVelocity.Magnitude
    local ttl = roflake.time() + math.abs(SharedConfig.BULLET_BASE_DISTANCE / speed)
    local boosterToHit, dist = Misc.IsBoosterToHit(pos, rootPart, ttl)
    if boosterToHit then
        ttl = roflake.time() + (dist / speed)
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

    local clonesRootParts = {}
    local clonesTargets = {}
    local playerRootPart
    for _, player in ipairs(players) do
        local char = player.Character
        playerRootPart = assert(char.HumanoidRootPart) :: Part
        local clonesFolder = char:FindFirstChild("Clones")
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

            local clonePos = Vector3.new(pos.X - 5 * i, pos.Y, pos.Z + 5)
            local cloneTarget = CFrame.lookAlong(clonePos, playerRootPart.CFrame.LookVector, Vector3.yAxis)
            -- cloneRootPart.CFrame = CFrame.lookAlong(clonePos, playerRootPart.CFrame.LookVector, Vector3.yAxis)
            table.insert(clonesRootParts, cloneRootPart)
            table.insert(clonesTargets, cloneTarget)
            workspace:BulkMoveTo(clonesRootParts, clonesTargets, Enum.BulkMoveMode.FireCFrameChanged)
        end
    end

    local activeBullets = {}
    local bulletsTargets = {}
    local now = roflake.time()
    for i, bulletData in ipairs(activeBulletsDataTable) do
        local bullet = bulletData.bullet :: Part
        local speedPerFrame = (bulletData.speed :: num) / 24
        local target = CFrame.new((bullet.CFrame.Position :: Vector3) + (bullet.CFrame.LookVector :: Vector3) * speedPerFrame)
        local booster = bulletData.booster
        local ttl = bulletData.ttl
        if booster then
        end
        if (booster and booster.Position.Z >= bullet.Position.Z) or now >= ttl then
            -- bullet collided with the booster or timed-out, delete it
            Array.swap_remove(activeBulletsDataTable, i)
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        else
            table.insert(activeBullets, bullet)
            table.insert(bulletsTargets, target)
        end
    end

    -- TODO: fake other players' bullets? (knowing their position and weapon from world state).
    -- TODO: Can we create entities of other players in a player state, refenrencing them by their player_id
    -- and updating their weapon_id by a S2CC event?
    workspace:BulkMoveTo(activeBullets, bulletsTargets, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire bullets for the local player
    local weaponId = PLAYER_STATE:get(Id.PlayerStats.WEAPON, C.ValueId) or Id.Weapon.BASIC
    local cooldown = S.Weapon[weaponId].cooldown
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        local shot_ttl = PLAYER_STATE:get(Id.TimedEvent.WEAPON_COOLDOWN, C.TTL) :: num
        if shot_ttl <= 0 then
            fireBulletPlayer(LOCAL_PLAYER)
        end
    end

    -- fake bullets for other players
    for _, player in ipairs(players) do
        if player == LOCAL_PLAYER then
            continue
        end
        local playerId = player.UserId
        local shot_ttl = WORLD:get(playerId, W.TTL)
        if shot_ttl and shot_ttl <= 0 then
            log:trace("player %d fired a bullet", playerId)
            fireBulletPlayer(player)
        else
            log:trace("player %* has a shot_ttl of %*", playerId, shot_ttl)
        end
    end
    log:trace(WORLD.format_state, WORLD, "*")
end)

-- diable jumping
LOCAL_HUMANOID.JumpPower = 0

local isRunAnimActive
local infrequentLoop = supervisor.create(1, "client-infrequent")
infrequentLoop:start(function(dt)
    for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
        if v.Name == RUN_ANIM_NAME then
            isRunAnimActive = true
            break
        end
    end
    if not isRunAnimActive then
        startRunAnim(LOCAL_CHARACTER)
    end

    if LOCAL_HUMANOID_ROOT_PART then
    end
end, 1, "test")
