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

-- forward declarations
local playRunAnimTrack
local startRunAnim
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

on[Id.S2C.PLAYER_DIED] = function(state: state.Replica)
    LOCAL_HUMANOID.JumpPower = 50
    LOCAL_HUMANOID_ROOT_PART:FindFirstChild(SharedConfig.CLONE_ATTACHMENT_NAME):Destroy()
    -- workspace:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME):Destroy()
    for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
        if v.Name == SharedConfig.RUN_ANIMATION_NAME then
            v:Stop()
        end
    end
end

-- Server Broadcasts
local on_cc = {}

on_cc[Id.S2CC.PLAYER_STARTED_SESSION] = function(player_id: id)
    if player_id == LOCAL_PLAYER.UserId then
        -- the logic is already done in subscribeStartCollider
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
    runAnimTrack.Priority = Enum.AnimationPriority.Action4
end

startRunAnim = function(character)
    local runAnimTrack = character.Humanoid:LoadAnimation(RUN_ANIM)
    runAnimTrack.Priority = Enum.AnimationPriority.Action4
    playRunAnimTrack(runAnimTrack)
    return runAnimTrack
end

local function subscribeStartCollider()
    local SESSION_STARTER_COLLIDER = assert(workspace:WaitForChild("SessionStarter"):FindFirstChild("Collider"))
    local START_BTN = START_GUI:FindFirstChild("OKButton", true)
    START_GUI.Enabled = false
    maid.StartCollider = SESSION_STARTER_COLLIDER.Touched:Connect(function(other)
        if other == LOCAL_HUMANOID_ROOT_PART then
            -- TODO: freeze player?
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
                subscribeStartCollider()
            end)
        end
    end)
end

-- initial subscription of the start button
do
    subscribeStartCollider()
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

    workspace:BulkMoveTo(activeBullets, bulletsTargets, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire bullets for the local player
    local flags = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if flags and Id.flag_test(flags, Id.PlayerF.READY) then
        local weaponId = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.RefId)
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local shot_ttl = PLAYER_STATE:get(Id.PlayerStats.GAME_SESSION, C.TTL) or 0 :: num
            if shot_ttl <= 0 then
                fireBullet(LOCAL_PLAYER)
                -- TODO: clones' fire
            end
        end
    end

    -- fake bullets' animation for other players
    -- TODO: fixme. no other players' bullets are shown
    for _, player in ipairs(players) do
        if player == LOCAL_PLAYER then
            continue
        end
        if not WORLD:env(ENV_WORLD_READY) then
            log:warn("WORLD is not ready yet")
            continue
        end
        local playerId = player.UserId
        if WORLD:has(playerId) then
            local weapon_id = WORLD:get(playerId, W.WeaponId)
            if weapon_id and weapon_id ~= Id.Weapon._NONE then
                local shot_ttl = WORLD:get(playerId, W.TTL)
                if shot_ttl and shot_ttl <= 0 then
                    fireBullet(player)
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
    if Id.kind(oldValue) == Id.Kind.Clone then
        -- delete clone instance if it was deleted from world
        local instance = workspace:FindFirstChild(guid, true)
        if instance then
            Disposer.dispose(instance)
        else
            log:error("failed to delete clone instance for player " .. oldValue)
            return
        end
    end
end)
