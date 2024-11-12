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
local active_bullets_table = {}

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
local UserInputService = game:GetService("UserInputService")
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
    runAnim:Play(0.100000001, 1, 2)
end

startRunAnim(LOCAL_CHARACTER)
-- TODO: refactor creating clones into normal logic: pick up boost = create clone depending on a boost's value
Clones.CreateClone(LOCAL_HUMANOID_ROOT_PART)

RunService.Heartbeat:Connect(function(dt)
    local players = game:GetService("Players"):GetPlayers()
    if #players < 1 then
        return
    end

    local clones = workspace.Clones:GetChildren()
    if #clones > 0 then
        local playerRootPart
        for _, player in ipairs(players) do
            local char = player.Character
            playerRootPart = assert(char.HumanoidRootPart) :: Part
        end
        -- TODO: refactor this logic to Ecs to make clones follow its corresponding player
        for i, clone in ipairs(clones) do
            local pos = playerRootPart.Position
            local cloneRootPart = clone:FindFirstChild("HumanoidRootPart")
            if not cloneRootPart then
                continue
            end
            -- TODO: refactor formation
            cloneRootPart.CFrame = CFrame.new(pos.X - 5 * i, pos.Y, pos.Z + 5) --* CFrame.Angles(0, math.rad(180), 0)
        end
    end

    -- TODO: move all bullets (from world state) forward with BulkMoveTo + check for collisions and TTL + move to Replicated Storage
end)

-- move driver box
local isRunAnimActive
local infrequentLoop = supervisor.create(1, "client-infrequent")
infrequentLoop:start(function(dt)
    for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
        if v.Name == RUN_ANIM_NAME then
            isRunAnimActive = true
            break
        end
    end
    -- TODO: animations of other players
    if not isRunAnimActive then
        startRunAnim(LOCAL_CHARACTER)
    end

    local clones = workspace.Clones:GetChildren()
    if #clones > 0 then
        for i, clone in ipairs(clones) do
            local cloneAnimTracks = clone.Humanoid:GetPlayingAnimationTracks()
            if #cloneAnimTracks < 1 then
                startRunAnim(clone)
            end
        end
    end
end, 1, "test")

-- TODO: sub to an event that others player's gun had changed ( to change the gun's animation )

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        local bullet
        if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
            bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
        else
            bullet = Instance.new("Part")
            bullet.Name = "Bullet"
            bullet.Size = Vector3.new(0.1, 0.1, 0.1)
        end
        local pos = LOCAL_HUMANOID_ROOT_PART.Position + LOCAL_HUMANOID_ROOT_PART.CFrame.LookVector * 2
        bullet.Parent = ACTIVE_BULLETS_REPOSITORY
        bullet.Position = pos
        local rayOrigin = pos
        local rayDirection = Vector3.new(pos.X, pos.Y, pos.Z + SharedConfig.BULLET_BASE_TTL)
        local raycastResult = workspace:Raycast(rayOrigin, rayDirection)
        local ttl = roflake.time() + SharedConfig.BULLET_BASE_TTL
        if raycastResult and raycastResult:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            -- boost is going to be hit
            -- TODO: refactor, get the weapon from the player Ecs
            local weapon_id = Id.Weapon.BASIC
            local dist = (raycastResult.Position - pos).Magnitude
            local speed = S.Weapon[weapon_id].speed
            ttl = roflake.time() + (dist / speed)
        end
        table.insert(active_bullets_table, {bullet = bullet, ttl = ttl})
        fire_server(Id.C2S.BULLET_SHOT, LOCAL_PLAYER.Position)
    end
end)
