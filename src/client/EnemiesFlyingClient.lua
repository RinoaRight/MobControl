type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type id = int
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type guid = str
type uid = str | id
local _fmt = string.format

local shared = game.ReplicatedStorage.shared
local Id = require(shared.Id)
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "Boosters"):set_prettifier(Id.pp):set_delimiter(" ")
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local W = SharedConfig.World.CId
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local workerMaid = disposer.new()
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local Misc = require(shared.Misc)
local S = require(shared.StaticData)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)
local SFX = require(script.Parent.SFX)
local TaskPool = require(shared.TaskPool)
local TweenService = game:GetService("TweenService")
local _roflake = require(shared.roflake)
local TARGET_SIGN_TEMPLATE = assert(ReplicatedStorage:WaitForChild("TargetSign"))

local function onPlayerCollisionWithBomb(worldState: state.Replica)
    -- TODO:
end

local function subscribeBomb(worldState: state.Replica, bombInstance)
    local sub = bombInstance.Touched:Connect(function(triggerer)
        if triggerer.Name ~= "Head" then
            return
        end
        local character = triggerer.Parent
        assert(character:IsA("Model")) -- sanity check
        
        bombInstance:Destroy()

        local triggererId
        local isClone, playerId = Misc.CloneOrPlayer(worldState, character)
        if playerId and playerId == LOCAL_PLAYER.UserId then
            if isClone then
                -- player's clone collided with the instance
                Misc.DestroyClientClone(character)
                triggererId = character.Name
            else
                -- player themselves collided with the instance for the first time
                triggererId = LOCAL_PLAYER.UserId
            end

            -- handle client instance
            onPlayerCollisionWithBomb(worldState)

            -- signal to server
            Signal.Fire(Id.C2S.PLAYER_HIT_BY_BOMB, triggererId)
        end
    end)

    bombInstance.Destroying:Once(function() 
        sub:Disconnect()
    end)
end

local function animateFlyer(worldState: state.Replica, flyer: BasePart, duration: number, initPos: Vector3, targetPos: Vector3, localRoot: BasePart)
    workerMaid[flyer.Name] = task.spawn(function()
        if not flyer:IsA("BasePart") then
            return
        end

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween1 = TweenService:Create(flyer, tweenInfo, {
            Position = targetPos,
        })
        local tween2 = TweenService:Create(flyer, tweenInfo, {
            Position = initPos,
        })

        while worldState:has(flyer.Name) do
            tween1:Play()
            task.wait(duration)
            tween2:Play()
            task.wait(duration)
        end
        -- TODO: spawn bombs and subscribe them to collision with player, animate target sign

        -- spawn target sign
        local targetSign = TARGET_SIGN_TEMPLATE:Clone()
        targetSign.Parent = flyer
        targetSign.Position = Vector3.new(flyer.Position.X, 0.01, flyer.Position.Z)
        -- subscribeBomb(worldState, instanceGuid, refId, flyerInstance)
    end)
end

local m = {}

m.onFlyerAdded = function(worldState: state.Replica, instanceGuid: str, localRoot: BasePart)
    local flyerPos = worldState:get(instanceGuid, W.Position)
    local refId = worldState:get(instanceGuid, W.RefId)
    local meshTemplate = S.EnemyFlying[refId].meshTemplate
    local flyerInstance = meshTemplate:Clone()

    flyerInstance.Name = instanceGuid
    local parentFolder = workspace:FindFirstChild(SharedConfig.FLYERS_FOLDER_NAME)
    if not parentFolder then
        parentFolder = Instance.new("Folder", workspace)
        parentFolder.Name = SharedConfig.FLYERS_FOLDER_NAME
    end
    flyerInstance.Position = flyerPos
    flyerInstance.CFrame = CFrame.new(flyerPos) * CFrame.Angles(0, math.pi, 0)
    flyerInstance.Parent = parentFolder

    worldState:set(instanceGuid, W.ClientInstance, flyerInstance)

    local targetYOffset = 5
    local targetPos = Vector3.new(flyerInstance.Position.X, flyerInstance.Position.Y - targetYOffset, flyerInstance.Position.Z)

    animateFlyer(worldState, flyerInstance, 0.5, flyerPos, targetPos, localRoot)
end

m.CleanupClientObstacle = function(worldState: state.Replica, instanceGuid: str)
    if worldState:has(instanceGuid) then
        local instance = worldState:get(instanceGuid, W.ClientInstance)
        if instance then
            instance:Destroy()
        end
    end
    if workerMaid[instanceGuid] then
        workerMaid[instanceGuid] = nil
    end
end

return m
