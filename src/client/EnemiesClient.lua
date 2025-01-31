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
local ENEMIES_FOLDER = assert(workspace:WaitForChild("Enemies"))
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)

local function onEnemyRemoved(enemyGuid: string)
    workerMaid[enemyGuid] = nil
    local instance = ENEMIES_FOLDER:FindFirstChild(enemyGuid)
    if instance then
        instance:Destroy()
    else
        log:error("No instance found for this enemy uid")
    end
end

local function onEnemyAdded(worldState, playerState: state.Replica, enemyGuid: string)
    local enemyId = worldState:get(enemyGuid, W.RefId)
    local enemyPos = worldState:get(enemyGuid, W.Position) :: Vector3

    local enemyInstance
    if S.Enemy[enemyId].meshTemplate then
        enemyInstance = S.Enemy[enemyId].meshTemplate:Clone()
    else
        enemyInstance = Instance.new("Part")
        enemyInstance.Size = Vector3.new(2, 6, 2)
    end
    enemyInstance.CanCollide = false
    enemyInstance.Anchored = true
    enemyInstance.CollisionGroup = "BulletCollidable"

    enemyInstance.Parent = ENEMIES_FOLDER
    enemyInstance.CFrame = CFrame.new(enemyPos)
    enemyInstance.Name = enemyGuid

    workerMaid[enemyGuid] = enemyInstance
end

local m = {}

-- m.MoveEnemyInstances = function(worldState, newPos: Vector3)
--     local enemies = {}
--     local enemyTargets = {}
--     local enemyFolder = ENEMIES_FOLDER
--     if enemyFolder then
--         local enemyInstances = enemyFolder:GetChildren()
--         if #enemyInstances > 0 then
--             for _, enemyInstance in ipairs(enemyInstances) do
--                 local currentPos: Vector3 = enemyInstance.Position
--                 table.insert(enemies, enemyInstance)
--                 local lookAt = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + 5)

--                 -- enemy is already locked on target, define lookAt
--                 local playerId = worldState:get(enemyInstance.Name, W.PLayerId)
--                 local player = game.Players:GetPlayerByUserId(playerId)
--                 if player then
--                     local playerRoot = player.Character:FindFirstChild("HumanoidRootPart")
--                     lookAt = playerRoot.Position
--                 end
--                 lookAt = Vector3.new(lookAt.X, newPos.Y, lookAt.Z) -- lock Y axis
--                 local newCframe = CFrame.new(newPos, lookAt) * CFrame.Angles(0, math.pi, 0)
--                 table.insert(enemyTargets, newCframe)
--             end
--         end
--     end
--     if #enemies > 0 then
--         workspace:BulkMoveTo(enemies, enemyTargets, Enum.BulkMoveMode.FireCFrameChanged)
--     end
-- end

workerMaid.subToAdd = Signal.Connect(Id.C2C.NEW_ENEMY_ADDED, onEnemyAdded)
workerMaid.subToRemove = Signal.Connect(Id.C2C.ENEMY_REMOVED, onEnemyRemoved)

return m
