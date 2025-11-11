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
local TweenService = game:GetService("TweenService")

local maid = disposer.new()

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
    local y = bossTemplate.Size.Y - bossTemplate.Size.Y / 2
    local bossPos = Vector3.new(unitPos.X, y, unitPos.Z)
    local bossGuid = WorldService.AddEnemyToState(enemyId, bossPos)
    return bossGuid
end

-- TODO: add more waves
local ENEMIES_DATA_TABLE = {
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1 } },
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1 } },
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.CRAZOMBIE] = 0.3 } },
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.CRAZOMBIE] = 0.3 } },
    { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.CONEHEAD] = 0.3 } },
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.CONEHEAD] = 0.3 } },
    { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.ZOMBUCKET] = 0.3 } },
    -- { count = 20, gacha = { [Id.Enemy.BASIC] = 1, [Id.Enemy.ZOMBUCKET] = 0.3 } },
}

local function getTweenForKnockback(root: BasePart, enemyPos: Vector3)
    local n = 20 -- knockback distance in studs
    local direction = (root.Position - enemyPos).Unit
    local rootPos = root.Position
    -- local offsetPosition = root.Position + direction * n -- Move further in that direction
    local offsetPosition = Vector3.new(rootPos.X, 20, rootPos.Z) + direction * n -- Move further in that direction
    local targetCFrame = CFrame.lookAt(offsetPosition, enemyPos)

    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

    local tween = TweenService:Create(root, tweenInfo, { CFrame = targetCFrame })
    return tween
end

local function overwriteRotation(thisPlayerState: PSS.PlayerState, root: BasePart, currentPos: Vector3)
    -- no boss's special attack, lock player's orientation to the boss
    local posToLookAt = currentPos
    local playerIntendedPos = thisPlayerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.V3)

    -- Direction from character to target (flattened to Y axis)
    local flatDir = Vector3.new(posToLookAt.X - playerIntendedPos.X, 0, posToLookAt.Z - playerIntendedPos.Z).Unit

    -- Apply only the orientation (not the full CFrame)
    root.CFrame = CFrame.new(playerIntendedPos) * CFrame.Angles(0, math.atan2(flatDir.X, flatDir.Z), 0) * CFrame.Angles(0, math.pi, 0)
end

local m = {}

-- NOTE: Every odd wave spawns in the current ground unit in front of the boosters,
-- every even - after some time, behind the boosters

function m.AddEnemies(
    worldState: state.Main,
    get_state: (player_id: int) -> PSS.PlayerState?,
    groundUnit: BasePart,
    isFirstHalf: bool,
    waveNumber: int
)
    local enemiesGuids = {}
    if waveNumber == SharedConfig.FINAL_BOSS_WAVE_NUMBER then
        local bossGuid = spawnBoss(Id.Enemy.OCTOBOSS, groundUnit.Position)
        table.insert(enemiesGuids, bossGuid)
        return enemiesGuids
    end

    if waveNumber > #ENEMIES_DATA_TABLE then
        waveNumber = #ENEMIES_DATA_TABLE
    end

    local numberOfEnemies = ENEMIES_DATA_TABLE[waveNumber].count
    if numberOfEnemies <= 0 then
        return enemiesGuids
    end
    local groundUnitPos = groundUnit.Position
    local y = ENEMY_CELL_SIZE.Z - ENEMY_CELL_SIZE.Z / 2 --+ 1
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

function m.DoBossSpecial(
    worldState,
    thisPlayerState: PSS.PlayerState,
    enemyRefId: int,
    enemyGuid: guid,
    currentPos: Vector3,
    playerRoot: BasePart,
    proximityToEnemy: num,
    dt: num
)
    -- check if it's time for boss to perform special attack
    local specialAttackRange = assert(S.Enemy[enemyRefId].specialAttackRange)
    if proximityToEnemy < specialAttackRange then
        -- if at least this player is in range, check if it's time to perform special attack. If yes, do the special attack
        local baseTTE = assert(S.Enemy[enemyRefId].tte) :: number
        if worldState:get(enemyGuid, W.TTE) < 0 then
            -- set flag to perform special attack
            WorldService.fset(enemyGuid, Id.EnemyF.PERFORM_SPECIAL_ATTACK, true)
            -- reset tte
            worldState:set(enemyGuid, W.TTE, baseTTE)
        end

        if WorldService.ftest(enemyGuid, Id.EnemyF.PERFORM_SPECIAL_ATTACK) then
            ---------------------- OCTOBOSS ----------------------
            if enemyRefId == Id.Enemy.OCTOBOSS then
                -- react to boss's special attack, if it's not done already
                if not thisPlayerState:test_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.PlayerF.BOSS_ULT_APPLIED) then
                    thisPlayerState:set_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.PlayerF.BOSS_ULT_APPLIED, true)
                    -- after the time it takes to perform the animation, do player knockback and reset the flag
                    maid.octoboss = TaskPool.spawn(function()
                        local tween = getTweenForKnockback(playerRoot, currentPos)
                        local animDur = assert(S.Enemy[enemyRefId].animationDur)
                        local leftTime = animDur
                        while leftTime > 0 do
                            leftTime = leftTime - dt
                            task.wait()
                        end
                        -- if player is still alive, apply knockback to his root
                        if thisPlayerState:test_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.PlayerF.READY) then
                            tween:Play()
                            tween.Completed:Connect(function()
                                -- damage player, reset flags
                                local dmg = assert(S.Enemy[enemyRefId].ultDamage)
                                thisPlayerState:DeductHp(dmg)
                                if WorldService.world:has(enemyGuid) then
                                    WorldService.fset(enemyGuid, Id.EnemyF.PERFORM_SPECIAL_ATTACK, false)
                                end
                                thisPlayerState:set_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.PlayerF.BOSS_ULT_APPLIED, false)
                            end)
                        end
                    end)
                else
                    -- animation is not yet over, lock player's orientation to the boss as usual
                    overwriteRotation(thisPlayerState, playerRoot, currentPos)
                end
            end
        else
            -- no boss's special attack, lock player's orientation to the boss
            overwriteRotation(thisPlayerState, playerRoot, currentPos)
        end
    else
        -- boss is not in special attack range, lock player's orientation to the boss
        overwriteRotation(thisPlayerState, playerRoot, currentPos)
    end
end

return m
