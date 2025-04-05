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
local WARNING_SPOT_TEMPLATE = assert(ReplicatedStorage:WaitForChild("WarningSpot"))
local COLOR_1 = Color3.fromHex("246b34")
local COLOR_2 = Color3.fromHex("4fee00")

local doUpAndDown = function(tween: Tween, tween2: Tween, duration: number)
    tween:Play()
    task.wait(duration + 2)
    tween2:Play()
    task.wait(duration)
end

local function animateObstacle(
    worldState: state.Replica,
    obstacle: BasePart,
    duration: number,
    initPos: Vector3,
    targetPos: Vector3,
    warningSpot: Instance,
    localRoot: BasePart
)
    task.spawn(function()
        if not obstacle:IsA("BasePart") then
            return
        end

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween1 = TweenService:Create(obstacle, tweenInfo, {
            Position = targetPos,
        })
        local tween2 = TweenService:Create(obstacle, tweenInfo, {
            Position = initPos,
        })

        task.wait(1)
        doUpAndDown(tween1, tween2, duration)

        local period = math.random(0.5, 2)
        local timesToFlickerSlow = 3
        local timesToFlickerMed = 4
        local timesToFlickerFast = 10
        local periodFlickerSlow = period / 2 / timesToFlickerSlow
        local halfPeriodFlickerSlow = periodFlickerSlow / 2
        local periodFlickerMed = period / 4 / timesToFlickerMed
        local halfPeriodFlickerMed = periodFlickerMed / 2
        local periodFlickerFast = period / 4 / timesToFlickerFast
        local halfPeriodFlickerFast = periodFlickerFast / 2

        local tweenInfoFlickerSlow = TweenInfo.new(halfPeriodFlickerSlow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tweenInfoFlickerMed = TweenInfo.new(halfPeriodFlickerMed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tweenInfoFlickerFast = TweenInfo.new(halfPeriodFlickerFast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        local tweenFlickerSlowIOut = TweenService:Create(warningSpot, tweenInfoFlickerSlow, {
            Color = COLOR_2,
        })
        local tweenFlickerSlowIn = TweenService:Create(warningSpot, tweenInfoFlickerSlow, {
            Color = COLOR_1,
        })
        local tweenFlickerMedOut = TweenService:Create(warningSpot, tweenInfoFlickerMed, {
            Color = COLOR_2,
        })
        local tweenFlickerMedIn = TweenService:Create(warningSpot, tweenInfoFlickerMed, {
            Color = COLOR_1,
        })
        local tweenFlickerFastOut = TweenService:Create(warningSpot, tweenInfoFlickerFast, {
            Color = COLOR_2,
        })
        local tweenFlickerFastIn = TweenService:Create(warningSpot, tweenInfoFlickerFast, {
            Color = COLOR_1,
        })

        if localRoot.Position.Z > targetPos.Z then -- obstacles are still ahead of the player
            while true do
                tween1:Play()
                task.wait(duration + 2)
                tween2:Play()
                task.wait(duration)
                for i = 1, timesToFlickerSlow do
                    tweenFlickerSlowIOut:Play()
                    task.wait(halfPeriodFlickerSlow)
                    tweenFlickerSlowIn:Play()
                    task.wait(halfPeriodFlickerSlow)
                end

                for i = 1, timesToFlickerMed do
                    tweenFlickerMedOut:Play()
                    task.wait(halfPeriodFlickerMed)
                    tweenFlickerMedIn:Play()
                    task.wait(halfPeriodFlickerMed)
                end

                for i = 1, timesToFlickerFast do
                    tweenFlickerFastOut:Play()
                    task.wait(halfPeriodFlickerFast)
                    tweenFlickerFastIn:Play()
                    task.wait(halfPeriodFlickerFast)
                end
            end
        end
    end)
end

local changeMesh = function(worldState: state.Replica, instanceGuid: str, newMeshTemplate: BasePart, pos: Vector3, parent: Instance)
    local oldSize = newMeshTemplate.Size
    local newMeshInstance = newMeshTemplate:Clone()
    local newSize =
        Vector3.new(oldSize.X * SharedConfig.GRAVE_SIZE_MULT, oldSize.Y * SharedConfig.GRAVE_SIZE_MULT, oldSize.Z * SharedConfig.GRAVE_SIZE_MULT)
    newMeshInstance.Size = newSize
    local targetY = newSize.Y / 2
    pos = Vector3.new(pos.X, targetY, pos.Z)
    newMeshInstance.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)
    newMeshInstance.Parent = parent
    newMeshInstance.Name = instanceGuid
    worldState:set(instanceGuid, W.ClientInstance, newMeshInstance)
end

local cleanupObstacle = function(worldState: state.Replica, instanceGuid: str)
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

local onPlayerCollisionWithObstacle = function(worldState: state.Replica, instanceGuid: str)
    local instanceRefId = worldState:get(instanceGuid, W.RefId)
    local currentMesh = worldState:get(instanceGuid, W.ClientInstance)
    if currentMesh then
        -- change the model of the obstacle
        local currentMeshStage = worldState:get(instanceGuid, W.ValueView)
        if currentMeshStage and currentMeshStage == 3 then
            cleanupObstacle(worldState, instanceGuid)
        elseif currentMeshStage and currentMeshStage ~= 0 then
            local newMeshStage = currentMeshStage + 1
            local newMeshTemplate
            if currentMeshStage == 1 then
                newMeshTemplate = S.Obstacle[instanceRefId].meshTemplateHalf
            elseif currentMeshStage == 2 then
                newMeshTemplate = S.Obstacle[instanceRefId].meshTemplateLast
            end
            local pos = currentMesh.Position
            local parent = currentMesh.Parent
            disposer.dispose(currentMesh)
            if newMeshTemplate then
                worldState:set(instanceGuid, W.ValueView, newMeshStage)
                changeMesh(worldState, instanceGuid, newMeshTemplate, pos, parent)
            end
        end
    end
end

local function subscribeInstance(worldState: state.Replica, instanceGuid: string, refId: id, instance)
    workerMaid[instanceGuid] = instance.Touched:Connect(function(triggerer)
        if triggerer.Name ~= "HumanoidRootPart" then
            return
        end
        local character = triggerer.Parent
        assert(character:IsA("Model")) -- sanity check
        -- check if this player already collided with this instance
        if not worldState:has(instanceGuid) then
            log:error("worldState is nil for this guid %s", instanceGuid)
            return
        end
        -- if the player already collided with this instance, do nothing
        if worldState:get(instanceGuid, W.ClientFlags) then
            return
        end

        -- local player has not yet collided with this instance, do the checks
        local triggererId
        local isClone, playerId = Misc.CloneOrPlayer(worldState, character)
        if playerId and playerId == LOCAL_PLAYER.UserId then
            if isClone then
                -- player's clone collided with the instance
                Misc.DestroyClientClone(character)
                triggererId = character.Name
            else
                -- player themselves collided with the instance for the first time, set the flag for the check above
                worldState:set(instanceGuid, W.ClientFlags, true)
                triggererId = LOCAL_PLAYER.UserId
            end

            -- handle client instance
            onPlayerCollisionWithObstacle(worldState, instanceGuid)

            -- signal to server to handle server instance
            Signal.Fire(Id.C2S.PLAYER_COLLIDED_W_OBSTACLE, instanceGuid, triggererId)
        end
    end)
end

local m = {}

m.onObstacleAdded = function(worldState: state.Replica, instanceGuid: str, localRoot: BasePart)
    local obstPos = worldState:get(instanceGuid, W.Position)
    local refId = worldState:get(instanceGuid, W.RefId)
    local meshTemplate = S.Obstacle[refId].meshTemplateFull
    local oldSize = meshTemplate.Size
    local obstInstance = meshTemplate:Clone()
    local mult = SharedConfig.GRAVE_SIZE_MULT
    obstInstance.Size = Vector3.new(oldSize.X * mult, oldSize.Y * mult, oldSize.Z * mult)
    -- local correctY = - obstInstance.Size.Y / 2
    local isForward = math.random(0, 1) == 0
    local randomZ = math.random(SharedConfig.GRAVE_Z_DISTRIBUTION_RANDOMNESS.X, SharedConfig.GRAVE_Z_DISTRIBUTION_RANDOMNESS.Y)
    if not isForward then
        randomZ = -randomZ
    end

    obstInstance.Name = instanceGuid
    local parentFolder = workspace:FindFirstChild(SharedConfig.OBSTACLE_FOLDER_NAME)
    if not parentFolder then
        parentFolder = Instance.new("Folder", workspace)
        parentFolder.Name = SharedConfig.OBSTACLE_FOLDER_NAME
    end
    obstInstance.Position = obstPos
    obstInstance.CFrame = CFrame.new(obstPos) * CFrame.Angles(0, math.pi, 0)
    obstInstance.Parent = parentFolder

    worldState:set(instanceGuid, W.ClientInstance, obstInstance)

    local targetY = obstInstance.Size.Y / 2
    local targetPos = Vector3.new(obstInstance.Position.X, targetY, obstInstance.Position.Z)

    -- spawn warning spot
    local warningSpot = WARNING_SPOT_TEMPLATE:Clone()
    warningSpot.Parent = obstInstance
    warningSpot.Position = Vector3.new(obstInstance.Position.X, .01, obstInstance.Position.Z)

    animateObstacle(worldState, obstInstance, 2, obstPos, targetPos, warningSpot, localRoot)

    subscribeInstance(worldState, instanceGuid, refId, obstInstance)
end

m.CleanupClientObstacle = cleanupObstacle

-- function m.ShakeCamera(intensity: number, duration: number, frequency: number)
--     local camera = workspace.Camera
--     if not camera then return end

--     local originalCFrame = camera.CFrame

--     TaskPool.spawn(function()
--         task.wait(.5)
--         SFX.PLAY_SOUND(Id.Sound.CREAK_METAL)

--         local startTime = os.clock()

--         while os.clock() - startTime < duration do
--             local elapsed = os.clock() - startTime
--             local progress = elapsed / duration

--             -- Calculate shake amount (decreases over time)
--             local currentIntensity = intensity * (1 - progress)

--             -- Generate random Y offset and rotation
--             local yOffset = math.random(-currentIntensity, currentIntensity)
--             local rotation = math.rad(math.random(-currentIntensity * 5, currentIntensity * 5))

--             -- Apply shake (only Y position and rotation)
--             camera.CFrame = originalCFrame * CFrame.new(0, yOffset, 0) * CFrame.fromOrientation(0, rotation, 0)

--             -- Wait for next shake
--             task.wait(1/frequency)
--         end

--         -- Reset camera
--         -- camera.CFrame = originalCFrame
--     end)
-- end

-- Example usage:
-- m.ShakeCamera(20, 10, 10) -- intensity: 0.5, duration: 2 seconds, frequency: 10 shakes per second

return m
-- TODO: subscribe to collision with bullets and make them breakable?
