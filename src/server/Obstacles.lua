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

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()

--[[ stylua: ignore]] if not game then(function() game = require("game") end)() end
local shared = game.ReplicatedStorage.shared
local server = game.ServerScriptService.server
local Id = require(shared.Id)
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "GameModule"):set_prettifier(Id.pp):set_delimiter(" ")
local TaskPool = require(shared.TaskPool)
local PSS = require(server.PlayerStateService)
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local SharedConfig = require(shared.SharedConfig)
local W = SharedConfig.World.CId
local state = require(shared.state)
local roflake = require(shared.roflake)
local WorldService = require(server.WorldService)
local S = require(shared.StaticData)
local C = SharedConfig.PlayerState.CId
local Misc = require(shared.Misc)
local NumFormat = require(shared.num_format)
local SharedUtils = require(shared.util)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rand = require(shared.rand)
local _roflake = require(shared.roflake)

local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_UNIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z
local GROUND_UNIT_LENGTH_HALF = GROUND_UNIT_LENGTH / 2

local OBSTACLE_CELL_SIZE = Vector3.new(7, 14, 5)
local DISTANCE_FROM_MID_TO_BOOSTER = SharedConfig.DISTANCE_FROM_MID_TO_BOOSTER
local X_MARGIN = 40
local SPAWN_SPACE_WIDTH = GROUND_UNIT_TEMPLATE.Size.X - X_MARGIN * 2
local X_INTERVAL = 40
local Z_INTERVAL = 100

local maid = disposer.new()

-- TODO: real values
local OBSTACLES_DATA_TABLE = {
    { count = 20, gacha = { [Id.Obstacle.GRAVE] = 1 } },
}

local m = {}

function m.AddObstacles(worldState: state.Main, groundUnit: BasePart, isFirstHalf: bool, waveNumber: int)
    if waveNumber < 1 then
        waveNumber = 1
    end
    if waveNumber > #OBSTACLES_DATA_TABLE then
        waveNumber = #OBSTACLES_DATA_TABLE
    end

    local numberOfObstacles = OBSTACLES_DATA_TABLE[waveNumber].count
    if numberOfObstacles <= 0 then
        return
    end

    local groundUnitPos = groundUnit.Position
    local y = OBSTACLE_CELL_SIZE.Z - OBSTACLE_CELL_SIZE.Z / 2 + 1
    local z = groundUnitPos.Z
    if isFirstHalf then
        z = z - DISTANCE_FROM_MID_TO_BOOSTER
    else
        z = z - GROUND_UNIT_LENGTH_HALF
    end
    local cell_w = OBSTACLE_CELL_SIZE.X + X_INTERVAL
    local cell_h = OBSTACLE_CELL_SIZE.Z + Z_INTERVAL
    local origin = Vector3.new(groundUnitPos.X, y, z)
    local cols = math.floor(SPAWN_SPACE_WIDTH / cell_w)
    local rows = 3

    -- TODO: more diverse distribution, more rows. More Models?

    -- make sure the grid fits all the required enemies
    while numberOfObstacles > cols * rows do
        rows += 1
    end

    local grid, bitmap, _rc2idx, _idx2rc = Misc.CreateGrid(cell_w, cell_h, cols, rows, origin)

    for i = 1, numberOfObstacles do
        -- define enemy id
        local gacha = OBSTACLES_DATA_TABLE[waveNumber].gacha
        local obstId = Rand.weighted_choice(gacha)
        local mestTemplate = S.Obstacle[obstId].meshTemplateFull

        local idx: int
        repeat
            idx = math.random(#grid)
        until not bitmap[idx]
        bitmap[idx] = true
        local obstPos = grid[idx]
        local correctY = mestTemplate.Size.Y / 2
        obstPos = Vector3.new(obstPos.X, correctY, obstPos.Z)

        local enemyGuid = _roflake.uida()
        local obst = mestTemplate:Clone()
        obst.Name = enemyGuid
        obst.Position = obstPos
        obst.Parent = groundUnit
        WorldService.AddObstacleToState(enemyGuid, obstId, obst)
        -- TODO: correct rotation
    end
end

m.ChangeMesh = function(worldState: state.Main, instanceGuid: guid, newMeshTemplate: BasePart, pos: Vector3, parent: Instance)
    local new_nesh_instance = newMeshTemplate:Clone()
    local correctY = new_nesh_instance.Size.Y / 2
    new_nesh_instance.Position = Vector3.new(pos.X, correctY, pos.Z)
    new_nesh_instance.Parent = parent
    new_nesh_instance.Name = instanceGuid
    worldState:set(instanceGuid, W.ServerInstance, new_nesh_instance)
    -- TODO: correct rotation
end

return m
