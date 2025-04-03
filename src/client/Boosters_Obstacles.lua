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

local function subscribeInstance(playerState, worldState: state.Replica, instanceGuid: string, instance)
    workerMaid[instanceGuid] = instance.Touched:Connect(function(triggerer)
        if triggerer.Name ~= "HumanoidRootPart" then
            return
        end
        local character = triggerer.Parent
        assert(character:IsA("Model")) -- sanity check
        -- check if this player already collided with this instance
        if not playerState then
            return
        end
        if not playerState:has(instanceGuid) then
            log:error("playerState is nil for this guid %s", instanceGuid)
            return
        end
        -- if the player already collided with this instance, do nothing
        if playerState:get(instanceGuid, C.ClientFlags) then
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
                playerState:set(instanceGuid, C.ClientFlags, true)
                triggererId = LOCAL_PLAYER.UserId
            end
            Signal.Fire(Id.C2S.PLAYER_COLLIDED_W_SERVER_INSTANCE, instanceGuid, triggererId)
        end
    end)
end

local m = {}

m.onServerInstanceAdded = function(worldState: state.Replica, playerState: state.Replica, instanceGuid)
    TaskPool.spawn(function()
        -- wait for instance to be created
        local instance
        local countdown = 3
        while not instance do
            if countdown <= 0 then
                log:error("Instance not found for guid %s", instanceGuid)
                return
            end
            local t = .1
            task.wait(t)
            countdown -= t
            instance = workspace:FindFirstChild(instanceGuid, true)
        end
        subscribeInstance(playerState, worldState, instanceGuid, instance)
    end)
end

m.CancelSubscription = function(guid)
    if workerMaid[guid] then
        workerMaid[guid] = nil
    end
end

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
