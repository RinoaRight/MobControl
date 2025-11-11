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
local TaskPool = require(shared.TaskPool)
local TweenService = game:GetService("TweenService")
local _roflake = require(shared.roflake)
local TARGET_SIGN_NAME = "TargetSign"
local TARGET_SIGN_TEMPLATE = assert(ReplicatedStorage:WaitForChild(TARGET_SIGN_NAME))

local function animateSign(worldState: state.Replica, signPos: Vector3, bomb: BasePart, ownerInstance: BasePart)
    TaskPool.spawn(function()
        -- animate target sign
        local targetInstance = TARGET_SIGN_TEMPLATE:Clone()
        local targetGui = targetInstance:WaitForChild("TargetGui")
        local imageLabel = assert(targetGui:WaitForChild("ImageLabel"))
        local redImage = assert(targetGui:WaitForChild("Red"))
        redImage.Visible = false
        imageLabel.ImageTransparency = 1
        local origSize = UDim2.fromScale(1, 1)
        local targetSize = UDim2.fromScale(0.7, 0.7)
        local Y = 0.5
        imageLabel.Size = origSize
        targetInstance.Position = Vector3.new(signPos.X, Y, signPos.Z)
        targetInstance.Parent = bomb
        -- local targetInstance = assert(ownerInstance:WaitForChild(TARGET_SIGN_NAME)) :: Part
        -- local targetGui = targetInstance:WaitForChild("TargetGui") :: SurfaceGui
        -- local imageLabel = assert(targetGui:WaitForChild("ImageLabel")) :: ImageLabel
        -- local redImage = assert(targetGui:WaitForChild("Red")) :: ImageLabel
        -- redImage.Visible = false
        -- imageLabel.ImageTransparency = 1
        -- local origSize = UDim2.fromScale(1, 1)
        -- local targetSize = UDim2.fromScale(0.7, 0.7)
        local duration1 = 0.3
        local times1 = 2
        local tweenInfo1 = TweenInfo.new(duration1, Enum.EasingStyle.Linear)
        local tween1 = TweenService:Create(imageLabel, tweenInfo1, { ImageTransparency = 0.2, Size = targetSize })
        local tween2 = TweenService:Create(imageLabel, tweenInfo1, { ImageTransparency = 0, Size = origSize })
        for i = 1, times1 do
            if worldState:has(bomb.Name) then
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
        local tween4 = TweenService:Create(imageLabel, tweenInfo2, { ImageTransparency = 0.1, Size = origSize })
        for i = 1, times2 do
            if worldState:has(bomb.Name) then
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
        local tween6 = TweenService:Create(imageLabel, tweenInfo3, { ImageTransparency = 0.1, Size = origSize })
        redImage.Visible = true
        for i = 1, times3 do
            if worldState:has(bomb.Name) then
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

local function animateFlyer(worldState: state.Replica, flyer: BasePart, serverPos: Vector3, localRoot: BasePart)
    if not flyer:IsA("BasePart") then
        return
    end

    workerMaid[flyer.Name] = TaskPool.spawn(function()
        -- flyer's tweens
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

        local tweenUp = TweenService:Create(flyer, tweenInfo2, {
            Position = targetPos2,
        })
        local tweenDown = TweenService:Create(flyer, tweenInfo2, {
            Position = targetPos1,
        })

        -- target sign's tweens
        -- local targetInstance = assert(TARGET_SIGN_TEMPLATE:Clone())
        -- local targetGui = targetInstance:WaitForChild("TargetGui")
        -- local imageLabel = assert(targetGui:WaitForChild("ImageLabel"))
        -- local redImage = assert(targetGui:WaitForChild("Red"))
        -- redImage.Visible = false
        -- imageLabel.ImageTransparency = 1
        -- local origSize = UDim2.fromScale(1, 1)
        -- local targetSize = UDim2.fromScale(0.7, 0.7)
        -- local Y = 0.5
        -- imageLabel.Size = origSize
        -- targetInstance.Position = Vector3.new(serverPos.X, Y, serverPos.Z)
        -- targetInstance.Parent = flyer
        -- local tweenInfoSign1 = TweenInfo.new(duration1, Enum.EasingStyle.Linear)
        -- local tweenInfoSign2 = TweenInfo.new(duration2, Enum.EasingStyle.Linear)
        -- local tweenSign1 = TweenService:Create(imageLabel, tweenInfoSign1, { ImageTransparency = 0.2, Size = targetSize })
        -- local tweenSign2 = TweenService:Create(imageLabel, tweenInfoSign2, { ImageTransparency = 0, Size = origSize })

        while worldState:has(flyer.Name) do
            local children = flyer:GetChildren()
            local bomb
            for _, child in ipairs(children) do
                if child:IsA("Part") and child.Name ~= TARGET_SIGN_TEMPLATE then
                    bomb = child
                    break
                end
            end
            tweenUp:Play()
            -- if not bomb then
                -- tweenSign1:Play()
            -- end
            task.wait(duration2)
            tweenDown:Play()
            -- if not bomb then
                -- tweenSign2:Play()
            -- end
            task.wait(duration2)
        end
    end)
end

local m = {}

m.OnFlyerAdded = function(worldState: state.Replica, playerState: state.Replica, instanceGuid: str, localRoot: BasePart)
    local flyerPos = worldState:get(instanceGuid, W.Position) :: Vector3
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
    flyerInstance.CFrame = CFrame.new(flyerPos)
    flyerInstance.Parent = parentFolder

    worldState:set(instanceGuid, W.ClientInstance, flyerInstance)

    animateFlyer(worldState, flyerInstance, flyerPos, localRoot)
end

m.OnBombActivated = function(worldState: state.Replica, bombGuid: str)
    -- TODO: missile SFX
    local bomb = Instance.new("Part")
    bomb.Shape = Enum.PartType.Ball
    bomb.Name = bombGuid
    bomb.CanCollide = false
    bomb.Anchored = false
    bomb.Color = Color3.fromRGB(255, 0, 0)
    bomb.Size = Vector3.new(10, 10, 10)
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
    animateSign(worldState, pos, bomb, ownerInstance)
end

m.CleanupClientFlyer = function(worldState: state.Replica, instanceGuid: str)
    if workerMaid[instanceGuid] then
        workerMaid[instanceGuid] = nil
    end
end

return m
