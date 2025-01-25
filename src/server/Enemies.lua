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

local GROUND_UNIT_FOLDER = game.Workspace.GroundUnits
local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_UNIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z
local GROUND_UNIT_LENGTH_HALF = GROUND_UNIT_LENGTH / 2
local X_MARGIN = 40
local SPAWN_SPACE_WIDTH = GROUND_UNIT_TEMPLATE.Size.X - X_MARGIN * 2
local X_INTERVAL = 5--20
local Z_INTERVAL = 20
local ENEMY_CELL_SIZE = Vector3.new(2, 6, 2)
local MAX_ROW, MAX_COLS = 16, 16
local DISTANCE_FROM_MID_TO_BOOSTER = SharedConfig.DISTANCE_FROM_MID_TO_BOOSTER
local START_ZONE_GAP = 70
local FIRST_HALF_Z_OFFSET = -DISTANCE_FROM_MID_TO_BOOSTER + START_ZONE_GAP
local SECOND_HALF_Z_OFFSET = -DISTANCE_FROM_MID_TO_BOOSTER - SharedConfig.BOOSTER_DEPTH
local NUM_OF_COLUMNS = math.floor((GROUND_UNIT_LENGTH - X_MARGIN * 2) / X_INTERVAL)


-- origin is a center-top
-- +-----O-----+ -Z   `O` is origin
-- |  1  |  2  |  ^
-- +-----+-----+  |
-- |  3  |  4  |  o---> X
-- +-----+-----+
local function create_grid(cell_w: int, cell_h: int, cols: int, rows: int, origin: Vector3)
    -- TODO: shift on X axis for each new row
    -- spawns from top left corner
    local grid = table.create(cols * rows)
    local bitmap = table.create(#grid, false)
    local x_offset = origin.X - (cols * cell_w) // 2 + cell_w // 2
    local z_offset = origin.Z + cell_h // 2
    local X_SHIFT = cell_w // 4
    for ri = 1, rows do
        local dx = ri % 2 ~= 0 and X_SHIFT or -X_SHIFT
        for ci = 1, cols do
            local x = x_offset + (ci - 1) * cell_w + dx
            local z = z_offset + (ri - 1) * cell_h
            local pos = Vector3.new(x, origin.Y, z)
            grid[(ci - 1) * rows + ri] = pos
            bitmap[(ci - 1) * cell_h + ri] = false
        end
    end
    local rc2idx = function(row: int, col: int)
        return (row - 1) * cols + col
    end
    local idx2rc = function(idx: int)
        local row = math.floor((idx - 1) / cols) + 1
        local col = idx - (row - 1) * cols
        return row, col
    end
    return grid, bitmap, rc2idx, idx2rc
end

local m = {}

-- Every odd wave spawns in the current ground unit in front of the boosters, every even - after some time, behind the boosters
m.ENEMIES_DATA_TABLE = {
    {count = 20, ids = {Id.Enemy.BASIC}},
    {count = 20, ids = {Id.Enemy.BASIC}},
}

function m.AddEnemies(worldState: state.Main, groundUnit: BasePart, isFirstHalf: bool, numberOfEnemies: int, ids:{id})
    local enemies = {}
    if numberOfEnemies <= 0 then
        return enemies
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

    -- TODO: make sure that the number of columns correspond with cell_width

    -- make sure the grid fits all the required enemies
    while numberOfEnemies > cols * rows do
        rows += 1
    end

    local grid, bitmap, _rc2idx, _idx2rc = create_grid(cell_w, cell_h, cols, rows, origin)

    for i = 1, numberOfEnemies do
        local idx: int
        repeat
            idx = math.random(#grid)
        until not bitmap[idx]
        bitmap[idx] = true
        local enemyPos = grid[idx]
        local yOffset = ENEMY_CELL_SIZE.Y / 2
        enemyPos = Vector3.new(enemyPos.X, enemyPos.Y + yOffset, enemyPos.Z)
        -- if __DEV__ then
        --     warn("enemy pos", enemyPos)
        --     local part = Instance.new("Part")
        --     part.Name = "EnemyPos"..tostring(enemyPos)
        --     part.Size = Vector3.new(1, 1, 1)
        --     part.CanCollide = false
        --     part.Anchored = true
        --     part.CFrame = CFrame.new(enemyPos)
        --     part.Parent = workspace
        --     part.BrickColor = BrickColor.new("Really red")
        -- end

        -- define enemy id
        local enemyId = Id.Enemy.BASIC
        if ids then 
            local ind = math.random(1, #ids)
            enemyId = ids[ind]
        end

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

        local enemyFolder = assert(groundUnit:FindFirstChild("Enemies"))
        enemyInstance.Parent = enemyFolder
        enemyInstance.CFrame = CFrame.new(enemyPos)
        local enemyGuid = WorldService.AddEnemyToState(enemyId, enemyPos, enemyInstance)
        assert(typeof(enemyGuid) == "string")
        enemyInstance.Name = enemyGuid
        table.insert(enemies, enemyGuid)
    end
    return enemies
end

return m
