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

local function onBoosterAdded(worldState, playerState: state.Replica, boosterGuid)
    local instance = workspace:FindFirstChild(boosterGuid, true)
    workerMaid[boosterGuid] = instance.Touched:Connect(function(other)
        if other.Name ~= "HumanoidRootPart" then
            return
        end

        local parent = other.Parent
        assert(parent:IsA("Model")) -- sanity check
        -- check if this player already collided with this booster.
        if not playerState then
            return
        end
        if not playerState:has(boosterGuid) then
            log:error("playerState is nil for booster %s", boosterGuid)
            return
        end
        -- if the player already collided with this booster, do nothing
        if playerState:get(boosterGuid, C.ClientFlags) then
            return
        end

        -- local player has not yet collided with this booster, do the checks
        local triggererId
        if parent.Parent == SharedConfig.CLONES_FOLDER_NAME then
            -- player's clone collided with the booster, check if it the local player's clone
            local playerId = worldState:get(parent.Name, W.PLayerId)
            if playerId ~= LOCAL_PLAYER.UserId then
                return
            end
            triggererId = parent.Name
            -- TODO:
        elseif PlayerService:GetPlayerFromCharacter(parent) == LOCAL_PLAYER then
            -- player themselves collided with the booster
            triggererId = LOCAL_PLAYER.UserId
            -- TODO:
        end

        if triggererId then
            -- player has collided with the booster for the first time, set it to the state
            playerState:set(boosterGuid, C.ClientFlags, true)
            Signal.Fire(Id.C2S.PLAYER_COLLIDED_W_BOOSTER, boosterGuid, triggererId)
        end
    end)
end

local m = {}

workerMaid.sub = Signal.Connect(Id.C2C.NEW_BOOSTER_ADDED, onBoosterAdded)

return m
