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
local X_INTERVAL = 20
local Z_INTERVAL = 20
local ENEMY_WIDTH = 10
local MAX_ROW, MAX_COLS = 16, 16
local DISTANCE_FROM_MID_TO_BOOSTER = 50
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
    -- spawns form top left corner
    local grid = table.create(cols * rows)
    local bitmap = table.create(#grid, false)
    local x_offset = origin.X - (cols * cell_w) // 2 + cell_w // 2
    local z_offset = origin.Z + cell_h // 2
    for i = 1, cols do
        for j = 1, rows do
            local x = x_offset + (i - 1) * cell_w
            local z = z_offset + (j - 1) * cell_h
            local pos = Vector3.new(x, origin.Y, z)
            grid[(i - 1) * rows + j] = pos
            bitmap[(i - 1) * cell_h + j] = false
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

function m.AddEnemies(worldState: state.Main, groundUnit: BasePart, isFirstHalf: bool, numOfEnemies: int)
    if numOfEnemies <= 0 then
        return
    end
    local groundUnitPos = groundUnit.Position
    local z = groundUnitPos.Z
    if isFirstHalf then
        z = z - DISTANCE_FROM_MID_TO_BOOSTER
    else
        z = z - GROUND_UNIT_LENGTH_HALF
    end
    local cell_w = ENEMY_WIDTH + X_INTERVAL
    local cell_h = ENEMY_WIDTH + Z_INTERVAL
    local origin = Vector3.new(groundUnitPos.X, 20, z)
    local cols = 20
    local rows = 3

    -- TODO: make sure that the number of columns correspond with cell_width

    -- make sure the grid fits all the required enemies
    while numOfEnemies > cols * rows do
        rows += 1
    end

    local grid, bitmap, _rc2idx, _idx2rc = create_grid(cell_w, cell_h, cols, rows, origin)

    for i = 1, numOfEnemies do
        local idx: int
        repeat
            idx = math.random(#grid)
        until not bitmap[idx]
        bitmap[idx] = true
        local enemyPos = grid[idx]
        if __DEV__ then
            warn("enemy pos", enemyPos)
            local part = Instance.new("Part")
            part.Name = "EnemyPos"..tostring(enemyPos)
            part.Size = Vector3.new(1, 1, 1)
            part.CanCollide = false
            part.Anchored = true
            part.CFrame = CFrame.new(enemyPos)
            part.Parent = workspace
            part.BrickColor = BrickColor.new("Really red")
        end


        -- TODO: real enemy generator
        local enemyId = Id.Enemy.BASIC
        local enemyInstance = Instance.new("Part")
        enemyInstance.Size = Vector3.new(2, 6, 2)
        enemyInstance.CanCollide = true
        enemyInstance.Anchored = true
        enemyInstance.CollisionGroup = "BulletCollidable"

        local enemyFolder = assert(groundUnit:FindFirstChild("Enemies"))
        enemyInstance.Parent = enemyFolder
        enemyInstance.CFrame = CFrame.new(enemyPos)
        WorldService.AddEnemyToState(enemyId, enemyInstance)
    end
end

return m
