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


local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_UNIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z
local GROUND_UNIT_LENGTH_HALF = GROUND_UNIT_LENGTH / 2
local X_MARGIN = 40
local SPAWN_SPACE_WIDTH = GROUND_UNIT_TEMPLATE.Size.X - X_MARGIN * 2
local X_INTERVAL = 5
local Z_INTERVAL = 20
local ENEMY_CELL_SIZE = Vector3.new(4, 6, 4)
local DISTANCE_FROM_MID_TO_BOOSTER = SharedConfig.DISTANCE_FROM_MID_TO_BOOSTER
local Y_OFFSET = 50
local Z_DISTRIBUTION_RANDOMNESS = Vector2.new(10, 40)

local ENEMIES_DATA_TABLE = {
    { count = 6, gacha = {[Id.EnemyFlying.ZOMBALLOON] = 1}},
}
local m = {}

function m.AddEnemiesFlying(worldState: state.Main, groundUnit: BasePart, isFirstHalf: bool, waveNumber :int)
    local enemiesGuids = {}
    if waveNumber > #ENEMIES_DATA_TABLE then
        waveNumber = #ENEMIES_DATA_TABLE
    end
    local numberOfEnemies = ENEMIES_DATA_TABLE[waveNumber].count
    if numberOfEnemies <= 0 then
        return enemiesGuids
    end
    local groundUnitPos = groundUnit.Position
    local z = groundUnitPos.Z
    if isFirstHalf then
        z = z - DISTANCE_FROM_MID_TO_BOOSTER
    else
        z = z - GROUND_UNIT_LENGTH_HALF
    end
    local cell_w = ENEMY_CELL_SIZE.X + X_INTERVAL
    local cell_h = ENEMY_CELL_SIZE.Z + Z_INTERVAL
    local origin = Vector3.new(groundUnitPos.X, Y_OFFSET, z)
    local cols = math.floor(SPAWN_SPACE_WIDTH / cell_w)
    local rows = 4

    -- make sure the grid fits all the required enemies
    while numberOfEnemies > cols * rows do
        rows += 1
    end

    local grid, bitmap, _rc2idx, _idx2rc = Misc.CreateGrid(cell_w, cell_h, cols, rows, origin)

    for i = 1, numberOfEnemies do
        local idx: int
        repeat
            idx = math.random(#grid)
        until not bitmap[idx]
        bitmap[idx] = true
        local enemyPos = grid[idx]
        
        -- adjust Y to raise to the sky and Z for randomness
        local isForward = math.random(0, 1) == 0
        local randomZ = math.random(Z_DISTRIBUTION_RANDOMNESS.X, Z_DISTRIBUTION_RANDOMNESS.Y)
        if not isForward then
            randomZ = -randomZ
        end
        local correctZ = enemyPos.Z + randomZ
        enemyPos = Vector3.new(enemyPos.X, Y_OFFSET, correctZ)

        -- define enemy id
        local gacha = ENEMIES_DATA_TABLE[waveNumber].gacha
        local enemyId = Rand.weighted_choice(gacha)

        local enemyGuid = WorldService.AddEnemyToState(enemyId, enemyPos)
        table.insert(enemiesGuids, enemyGuid)
    end
    return enemiesGuids
end

return m