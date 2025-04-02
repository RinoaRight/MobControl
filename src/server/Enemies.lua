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


local GROUND_UNIT_FOLDER = game.Workspace.GroundUnits
local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_UNIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z
local GROUND_UNIT_LENGTH_HALF = GROUND_UNIT_LENGTH / 2
local X_MARGIN = 40
local SPAWN_SPACE_WIDTH = GROUND_UNIT_TEMPLATE.Size.X - X_MARGIN * 2
local X_INTERVAL = 5
local Z_INTERVAL = 20
local ENEMY_CELL_SIZE = Vector3.new(4, 6, 4)
local MAX_ROW, MAX_COLS = 16, 16
local DISTANCE_FROM_MID_TO_BOOSTER = SharedConfig.DISTANCE_FROM_MID_TO_BOOSTER
local START_ZONE_GAP = 70
local FIRST_HALF_Z_OFFSET = -DISTANCE_FROM_MID_TO_BOOSTER + START_ZONE_GAP
local SECOND_HALF_Z_OFFSET = -DISTANCE_FROM_MID_TO_BOOSTER - SharedConfig.BOOSTER_DEPTH
local NUM_OF_COLUMNS = math.floor((GROUND_UNIT_LENGTH - X_MARGIN * 2) / X_INTERVAL)

local function spawnBoss(enemyId, unitPos)
    local bossTemplate = S.Enemy[enemyId].meshTemplate
    local y = bossTemplate.Size.Y - bossTemplate.Size.Y / 2 + 1
    local bossPos = Vector3.new(unitPos.X, y, unitPos.Z)
    local bossGuid = WorldService.AddEnemyToState(enemyId, bossPos)
    return bossGuid
end

local ENEMIES_DATA_TABLE = {
    { count = 20, gacha = {[Id.Enemy.BASIC] = 1}},
    { count = 20, gacha = {[Id.Enemy.BASIC] = 1}},
    { count = 20, gacha = {[Id.Enemy.BASIC] = 1, [Id.Enemy.CRAZOMBIE] = .3}},
    { count = 20, gacha = {[Id.Enemy.BASIC] = 1, [Id.Enemy.CRAZOMBIE] = .3}},
}
local m = {}

-- NOTE: Every odd wave spawns in the current ground unit in front of the boosters, 
-- every even - after some time, behind the boosters

function m.AddEnemies(worldState: state.Main, groundUnit: BasePart, isFirstHalf: bool, waveNumber :int)
    local enemiesGuids = {}
    if waveNumber == SharedConfig.BOSS_WAVE_NUMBER then
        local bossGuid = spawnBoss(Id.Enemy.OCTOBOSS, groundUnit.Position)
        table.insert(enemiesGuids, bossGuid)
        return enemiesGuids 
    elseif waveNumber > #ENEMIES_DATA_TABLE then
        waveNumber = #ENEMIES_DATA_TABLE
    end
    local numberOfEnemies = ENEMIES_DATA_TABLE[waveNumber].count
    if numberOfEnemies <= 0 then
        return enemiesGuids
    end
    local groundUnitPos = groundUnit.Position
    local y = ENEMY_CELL_SIZE.Z - ENEMY_CELL_SIZE.Z / 2 + 1
    local z = groundUnitPos.Z
    if isFirstHalf then
        z = z - DISTANCE_FROM_MID_TO_BOOSTER
    else
        z = z - GROUND_UNIT_LENGTH_HALF
    end
    local cell_w = ENEMY_CELL_SIZE.X + X_INTERVAL
    local cell_h = ENEMY_CELL_SIZE.Z + Z_INTERVAL
    local origin = Vector3.new(groundUnitPos.X, y, z)
    local cols = math.floor(SPAWN_SPACE_WIDTH / cell_w)
    local rows = 3

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
        local yOffset = ENEMY_CELL_SIZE.Y / 2
        enemyPos = Vector3.new(enemyPos.X, enemyPos.Y + yOffset, enemyPos.Z)

        -- define enemy id
        local gacha = ENEMIES_DATA_TABLE[waveNumber].gacha
        local enemyId = Rand.weighted_choice(gacha)

        local enemyGuid = WorldService.AddEnemyToState(enemyId, enemyPos)
        table.insert(enemiesGuids, enemyGuid)
    end
    return enemiesGuids
end

return m
