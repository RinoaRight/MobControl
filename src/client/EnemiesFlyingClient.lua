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
local Rand = require(shared.rand)
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

local function animateBomb(worldState: state.Replica, signPos: Vector3, flyer: BasePart)
    TaskPool.spawn(function()
        -- animate target sign
        local targetInstance = TARGET_SIGN_TEMPLATE:Clone()
        local imageLabel = targetInstance:WaitForChild("TargetGui"):WaitForChild("ImageLabel")
        imageLabel.ImageTransparency = 1
        local origSize = UDim2.fromScale(1, 1)
        local targetSize = UDim2.fromScale(0.7, 0.7)
        local Y = 0.5
        imageLabel.Size = origSize
        targetInstance.Position = Vector3.new(signPos.X, Y, signPos.Z)
        targetInstance.Parent = flyer
        local duration1 = 0.3
        local times1 = 2
        local tweenInfo1 = TweenInfo.new(duration1, Enum.EasingStyle.Linear)
        local tween1 = TweenService:Create(imageLabel, tweenInfo1, { ImageTransparency = 0.2, Size = targetSize })
        local tween2 = TweenService:Create(imageLabel, tweenInfo1, { ImageTransparency = 0, Size = origSize })
        for i = 1, times1 do
            if worldState:has(flyer.Name) then
                tween1:Play()
                task.wait(duration1)
                tween2:Play()
                task.wait(duration1)
            end
        end
        local duration2 = 0.2
        local times2 = 2
        local tweenInfo2 = TweenInfo.new(duration2, Enum.EasingStyle.Linear)
        local tween3 = TweenService:Create(imageLabel, tweenInfo2, { ImageTransparency = 0.2, Size = targetSize })
        local tween4 = TweenService:Create(imageLabel, tweenInfo2, { ImageTransparency = 0, Size = origSize })
        for i = 1, times2 do
            if worldState:has(flyer.Name) then
                tween3:Play()
                task.wait(duration2)
                tween4:Play()
                task.wait(duration2)
            end
        end
        local duration3 = 0.1
        local times3 = 8
        local tweenInfo3 = TweenInfo.new(duration3, Enum.EasingStyle.Linear)
        local tween5 = TweenService:Create(imageLabel, tweenInfo3, { ImageTransparency = 0.2, Size = targetSize })
        local tween6 = TweenService:Create(imageLabel, tweenInfo3, { ImageTransparency = 0, Size = origSize })
        for i = 1, times3 do
            if worldState:has(flyer.Name) then
                tween5:Play()
                task.wait(duration3)
                tween6:Play()
                task.wait(duration3)
            end
        end
        -- local duration4 = 0.05
        -- local tweenInfo4 = TweenInfo.new(duration4, Enum.EasingStyle.Linear)
        -- local tween7 = TweenService:Create(imageLabel, tweenInfo4, { ImageTransparency = 0.2, Size = targetSize })
        -- local tween8 = TweenService:Create(imageLabel, tweenInfo4, { ImageTransparency = 0, Size = origSize })
        -- for i = 1, 12 do
        --     tween7:Play()
        --     task.wait(duration4)
        --     tween8:Play()
        --     task.wait(duration4)
        -- end
        targetInstance:Destroy()
    end)
end

-- TESTING
-- flickerTargetSign(Vector3.new(-280, 5.1, 91))
-- local part = game.workspace:WaitForChild("Part")
-- flickerEnemy("Part", part)

-- local function animateTargetSign(worldState: state.Replica, flyer: BasePart)
--     -- TODO: spawn bombs and subscribe them to collision with player, animate target sign
--     task.spawn(function()
--         -- spawn target sign
--         local targetSign = TARGET_SIGN_TEMPLATE:Clone()
--         targetSign.Parent = flyer
--         targetSign.Position = Vector3.new(flyer.Position.X, 0.01, flyer.Position.Z)
--         -- animate target sign
--         local currentSignSize = targetSign.Size
--         local targetSignSize = Vector3.new(currentSignSize.X * 1.5, currentSignSize.Y, currentSignSize.Z * 1.5)
--         local period = 0.5
--         local tweenSizeOut = TweenService:Create(targetSign, TweenInfo.new(period, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
--             Size = targetSignSize,
--         })
--         local tweenSizeIn = TweenService:Create(targetSign, TweenInfo.new(period, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
--             Size = currentSignSize,
--         })
--         for i = 0, 5 do
--             tweenSizeOut:Play()
--             task.wait(period)
--             tweenSizeIn:Play()
--             task.wait(period)
--         end
--     end)
-- end

local function animateFlyer(worldState: state.Replica, flyer: BasePart, serverPos: Vector3, localRoot: BasePart)
    workerMaid[flyer.Name] = TaskPool.spawn(function()
        if not flyer:IsA("BasePart") then
            return
        end

        local flyerRefId = worldState:get(flyer.Name, W.RefId)
        local flyerHeight = S.EnemyFlying[flyerRefId].flyerHeight
        local targetYOffset = 5
        local targetPos1 = Vector3.new(serverPos.X, serverPos.Y + flyerHeight, serverPos.Z)
        local targetPos2 = Vector3.new(targetPos1.X, targetPos1.Y - targetYOffset, targetPos1.Z)

        local duration1 = Rand.uniform(SharedConfig.FIRST_BOMB_DELAY - 2, SharedConfig.FIRST_BOMB_DELAY)
        local tweenInfo1 = TweenInfo.new(duration1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween0 = TweenService:Create(flyer, tweenInfo1, { Position = targetPos1 })

        tween0:Play()
        task.wait(duration1)

        local duration2 = Rand.uniform(1.1, 2.0)
        local tweenInfo2 = TweenInfo.new(duration2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        local tween1 = TweenService:Create(flyer, tweenInfo2, {
            Position = targetPos2,
        })
        local tween2 = TweenService:Create(flyer, tweenInfo2, {
            Position = targetPos1,
        })
        while worldState:has(flyer.Name) do
            tween1:Play()
            task.wait(duration2)
            tween2:Play()
            task.wait(duration2)
        end
    end)
end

local m = {}

m.OnFlyerAdded = function(worldState: state.Replica, playerState: state.Replica, instanceGuid: str, localRoot: BasePart)
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
    flyerInstance.CFrame = CFrame.new(flyerPos) -- * CFrame.Angles(0, math.pi, 0)
    flyerInstance.Parent = parentFolder

    worldState:set(instanceGuid, W.ClientInstance, flyerInstance)

    animateFlyer(worldState, flyerInstance, flyerPos, localRoot)
end

m.OnBombActivated = function(worldState: state.Replica, bombGuid: str)
    -- TODO: misslie SFX
    local bomb = Instance.new("Part")
    bomb.Shape = Enum.PartType.Ball
    bomb.Name = bombGuid
    bomb.CanCollide = false
    bomb.Anchored = false
    bomb.Color = Color3.fromRGB(255, 0, 0)
    bomb.Size = Vector3.new(5, 5, 5)
    local ownerGuid = worldState:get(bombGuid, W.OwnerGuid)
    local ownerInstance = worldState:get(ownerGuid, W.ClientInstance)
    if not ownerInstance then
        return
    end
    bomb.Parent = ownerInstance
    local pos = worldState:get(bombGuid, W.Position)
    bomb.Position = pos
    worldState:set(bombGuid, W.ClientFlags, false) -- set "bomb exploded" flag to false
    worldState:set(bombGuid, W.ClientInstance, bomb)
end

m.CleanupClientFlyer = function(worldState: state.Replica, instanceGuid: str)
    if workerMaid[instanceGuid] then
        workerMaid[instanceGuid] = nil
    end
end

return m
