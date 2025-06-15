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
local Enemies = require(server.Enemies)
local EnemiesFlying = require(server.EnemiesFlyingServer)
local PlayerService = game:GetService("Players")
local SharedUtil = require(shared.util)
local rand = require(shared.rand)
local BoosterServer = require(server.BoosterServer)
local Obstacles = require(server.Obstacles)
local ClonesServer = require(server.ClonesServer)
local Remote = require(shared.Remote)
local Rand = require(shared.rand)
local TweenService = game:GetService("TweenService")

local CLONES = {}

local m = {} :: {
    get_state: (int) -> PSS.PlayerState?,
    StarFstartmaintMainLoopPlayer: (PSS.PlayerState) -> (num) -> (),
    Init: (state: state.Main, (int) -> PSS.PlayerState?) -> (),
    CreatePlayerHpGui: (PSS.PlayerState) -> (),
    DestroyEnemy: (enemy_guid: str, player_id: num?) -> (),
    Cleanup: () -> (),
    HandleBoosterDeath: (PSS.PlayerState, booster_guid: str, boost_ref_id: id, value: num, boost_content_id: id) -> (),
    StartMainLoopWorld: (world_state: state.Main, (int) -> PSS.PlayerState?) -> (num) -> (),
    SetPlayerAlignment: (PSS.PlayerState) -> (),
    SpawnPlayer: (PSS.PlayerState, int) -> (),
}

local workerMaid = disposer.new()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GROUND_UNIT_FOLDER = game.Workspace.GroundUnits
local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_INIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z
local BOOSTER_TEMPLATE = assert(ReplicatedStorage.Booster)
local BOOSTER_WIDTH = BOOSTER_TEMPLATE.Size.X
local BOOSTER_GUI_TEMPLATE = assert(ReplicatedStorage.UI.BoosterGui)
local BOOSTER_OFFSET_X = 220
local BOOSTER_OFFSET_Y = 9
local BOOSTER_OFFSET_Z = -50
local BOOSTER_GAP = 40
local GAP_WIDTH = BOOSTER_GAP - BOOSTER_WIDTH
local BOOSTER_CONTENTS_BILLBOARD_TEMPLATE = assert(ReplicatedStorage.BoosterContentsBillboard)

local CLONES_DUMMY_FOLDER = assert(workspace:FindFirstChild(SharedConfig.CLONES_DUMMY_FOLDER_NAME))

local FIELD_NAMES = En.with_id("*")({
    FIRST = 1,
    SECOND = 2,
    MIDDLE = 3,
    FOURTH = 4,
    FIFTH = 5,
})

-- stylua: ignore
local GROUND_UNITS = {
    {                                             zOffset = GROUND_INIT_LENGTH * 2 },
    {                                             zOffset = GROUND_INIT_LENGTH},
    {                                             zOffset = 0},
    {                                             zOffset = -GROUND_INIT_LENGTH },
    {                                             zOffset = GROUND_INIT_LENGTH * -2 },
}::{{unit: Part?, zOffset: num}}
local startingPos = Vector3.new(0, -10, 0)

local DRIVING_BOX_TEMPLATE = assert(ReplicatedStorage.DrivingBoxModel)
local DRIVING_BOX_INSTANCE = DRIVING_BOX_TEMPLATE:Clone()
DRIVING_BOX_INSTANCE.Parent = game.Workspace
local DRIVING_BOX_BACK_PART = assert(DRIVING_BOX_INSTANCE.DrivingBoxBackPart)
local DRIVING_BOX_FRONT = assert(DRIVING_BOX_INSTANCE.PartFront)
local DRIVING_BOX_ATT = Instance.new("Attachment") :: Attachment
DRIVING_BOX_ATT.Parent = DRIVING_BOX_FRONT
local chldrn = DRIVING_BOX_INSTANCE:GetChildren()
for _, child in ipairs(chldrn) do
    if child:IsA("WeldConstraint") then
        child.Enabled = true
    end
end

local HUMANOID_Y_OFFSET

local function deleteGroundUnit(groundUnit: Part, index: int)
    local children = groundUnit:GetChildren()
    for _, v in ipairs(children) do
        if v:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            WorldService.RemoveEntity(v.Name)
        end
    end
    -- delete boosters
    local boosters = groundUnit:GetChildren()
    for i, booster in ipairs(boosters) do
        BoosterServer.DeleteBooster(WorldService.world, booster.Name, m.get_state)
    end
    -- delete obstacles
    local groundUnitPos = groundUnit.Position
    local unitHalfLength = groundUnit.Size.Z / 2
    for guid, refId, pos in WorldService.world:select(W.RefId, W.Position) do
        if Id.kind(refId) == Id.Kind.Obstacle then
            if pos.Z > groundUnitPos.Z - unitHalfLength then
                Obstacles.RemoveObstacle(WorldService.world, guid :: guid)
            end
        end
    end
    groundUnit:Destroy()
end

local function onBossArrival()
    -- local unitsFolder = GROUND_UNIT_FOLDER:GetChildren()
    -- for _, unit in ipairs(unitsFolder) do
    --     unit.AssemblyLinearVelocity = unit.CFrame.LookVector * SharedConfig.MOVEMENT_LINEAR_VELOCITY_BOSS
    -- end
    WorldService.SetBossFightOn()
end

local function setBooster(worldState: state.Main, instance: BasePart, get_state: (int) -> PSS.PlayerState?)
    local refID, boostContentId = BoosterServer.SetBoosterValue(worldState)
    local valueRange = S.Boost[refID].valueRange
    local value = math.random(valueRange[1], valueRange[#valueRange])
    local hpRange = S.Boost[refID].hpRange
    local hp_mult = BoosterServer.GetCurrentBoosterHpMult(worldState)
    local hp = math.floor(math.random(hpRange[1], hpRange[#hpRange]) * hp_mult)

    local contentsBillboardInstance = BOOSTER_CONTENTS_BILLBOARD_TEMPLATE:Clone()
    local boosterPos = instance.Position
    local billboardPos = contentsBillboardInstance.Position
    contentsBillboardInstance.CFrame = CFrame.new(boosterPos.X, billboardPos.Y, boosterPos.Z)
    contentsBillboardInstance.Parent = instance
    local contentsTextbox = contentsBillboardInstance.BoosterContentsGui.TextLabel
    local txt = ""
    local col = instance.Color
    if refID == Id.Boost.ADD_CLONE then
        txt = string.format("+%d clones", value)
        col = Color3.fromRGB(0, 255, 0)
    elseif refID == Id.Boost.CHANGE_WEAPON then
        txt = string.format("%s", S.Weapon[boostContentId :: id].name)
        col = Color3.fromRGB(169, 132, 255)
        if boostContentId == Id.Weapon.SPRAYGUN then
            col = Color3.fromRGB(177, 94, 11)
        elseif boostContentId == Id.Weapon.ROCKET then
            col = Color3.fromRGB(149, 16, 142)
        end
    elseif refID == Id.Boost.FIRST_AID_KIT then
        value = math.round(value / 10) * 10 -- round the value
        txt = "+health"
        col = Color3.fromRGB(255, 26, 79)
    end
    -- set GUI
    instance.Color = col
    contentsTextbox.Text = txt
    contentsTextbox.TextColor3 = col
    local boosterGui = BOOSTER_GUI_TEMPLATE:Clone()
    boosterGui.Parent = instance
    boosterGui.Adornee = instance
    boosterGui.TextLabel.Text = NumFormat.format_damage(hp)
    boosterGui.TextLabel.TextColor3 = col

    instance:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost], refID)
    instance.CollisionGroup = "BulletCollidable"
    -- add booster to world state
    local boosterGuid = WorldService.AddBooster(instance, refID, value, hp, boostContentId)
    -- add booster to player states
    local players = game.Players:GetPlayers()
    for _, player in ipairs(players) do
        local playerState = get_state(player.UserId)
        if playerState then
            playerState:AddBooster(boosterGuid)
        end
    end
    -- subscribe booster to collision with player
    BoosterServer.SubscribeBooster(worldState, get_state, boosterGuid, refID, instance)
end

local function spawnGroundUnit(worldState: state.Main, groundUnit: Part, index: int, refPos: Vector3)
    WorldService.UpdateBoosterWaveCount()

    GROUND_UNITS[index].unit = groundUnit
    local unitPos = CFrame.new(refPos.X, refPos.Y, refPos.Z + GROUND_UNITS[index].zOffset)
    groundUnit.Parent = GROUND_UNIT_FOLDER
    groundUnit.CFrame = unitPos

    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    trigger.CFrame = CFrame.new(9, 20.5, unitPos.Z - 245)
    groundUnit.AssemblyLinearVelocity = groundUnit.CFrame.LookVector * SharedConfig.MOVEMENT_LINEAR_VELOCITY_REG

    for i = 1, SharedConfig.BOOSTERS_IN_UNIT do --12 boosters
        local booster = BOOSTER_TEMPLATE:Clone()
        booster.CFrame = CFrame.new(BOOSTER_OFFSET_X - BOOSTER_GAP * (i - 1), BOOSTER_OFFSET_Y, unitPos.Z + BOOSTER_OFFSET_Z)
        booster.Parent = groundUnit
        setBooster(worldState, booster, m.get_state)
    end
end

local function generateEnemies(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    local newWaveNumber = WorldService.UpdateEnemyWaveCount()
    local unit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part
    local enemyWalkingGuids = Enemies.AddEnemies(worldState, get_state, unit, true, newWaveNumber) :: {}
    local enemiesFlyingGuids = EnemiesFlying.AddEnemiesFlying(worldState, unit, true, newWaveNumber) :: {}
    local enemyGuids = {}
    for _, enemyGuid in ipairs(enemyWalkingGuids) do
        table.insert(enemyGuids, enemyGuid)
    end
    for _, enemyGuid in ipairs(enemiesFlyingGuids) do
        table.insert(enemyGuids, enemyGuid)
    end

    if #enemyGuids > 0 then
        for _, enemyGuid in ipairs(enemyGuids) do
            local enemyRefId = worldState:get(enemyGuid, W.RefId)
            if enemyRefId == Id.Enemy.OCTOBOSS then
                onBossArrival()
            end
        end
    end
end

local function isPvPTime(get_state: (player_id: int) -> PSS.PlayerState?)
    -- TODO: uncomment everything
    local waveNumber = WorldService.GetEnemyWaveNumber()
    local isPvPTime = false
    if waveNumber == SharedConfig.FINAL_BOSS_WAVE_NUMBER then
        local allPlayers = game.Players:GetPlayers()
        local playersInSession = 0
        if #allPlayers > 1 then
            for _, player in ipairs(allPlayers) do
                local thisPlayerState = get_state(player.UserId)
                if thisPlayerState then
                    local playerFlags = thisPlayerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
                    if Id.flag_test(playerFlags, Id.PlayerF.READY) then
                        playersInSession += 1
                        local algnConstraint = thisPlayerState.character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
                        if algnConstraint then
                            algnConstraint:Destroy()
                        end
                    end
                end
            end
        end
        -- if there are more than 1 player in the session, it's PvP time, otherwise spawn boss
        if playersInSession > 1 then
            isPvPTime = true
            WorldService.SetPvPTimeOn()
            -- TODO:
            local unitsFolder = GROUND_UNIT_FOLDER:GetChildren()
            TaskPool.spawn(function()
                for _, unit in ipairs(unitsFolder) do
                    -- unit.AssemblyLinearVelocity = unit.CFrame.LookVector * SharedConfig.MOVEMENT_LINEAR_VELOCITY_BOSS
                    local tweenInfo = TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
                    local tween = TweenService:Create(unit, tweenInfo, { AssemblyLinearVelocity = Vector3.new(0, 0, 0) })
                    tween:Play()
                end
                task.wait(10)
            end)
        end
    end
    return isPvPTime
end

local function subscribeTrigger(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?, index, groundUnit)
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    workerMaid.trigger = trigger.Touched:Connect(function(triggerer)
        if triggerer == DRIVING_BOX_FRONT then
            local fourth = GROUND_UNITS[FIELD_NAMES.FOURTH].unit :: Part
            -- create obstacles on the next ground unit
            Obstacles.AddObstacles(worldState, fourth, true)

            subscribeTrigger(worldState, get_state, FIELD_NAMES.FOURTH, fourth)
            trigger:Destroy()
            local first = GROUND_UNITS[FIELD_NAMES.FIRST].unit :: Part
            deleteGroundUnit(first, FIELD_NAMES.FIRST)
            -- shift all other units in the data table accordingly
            GROUND_UNITS[FIELD_NAMES.FIRST].unit = GROUND_UNITS[FIELD_NAMES.SECOND].unit
            GROUND_UNITS[FIELD_NAMES.SECOND].unit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit
            GROUND_UNITS[FIELD_NAMES.MIDDLE].unit = GROUND_UNITS[FIELD_NAMES.FOURTH].unit
            GROUND_UNITS[FIELD_NAMES.FOURTH].unit = GROUND_UNITS[FIELD_NAMES.FIFTH].unit
            local middle = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part
            local refPos = middle.Position
            spawnGroundUnit(worldState, GROUND_UNIT_TEMPLATE:Clone(), FIELD_NAMES.FIFTH, refPos)

            if worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value) then
                if not isPvPTime(get_state) then
                    generateEnemies(worldState, get_state)
                end
            end

            local isToSpawn = true
            TaskPool.spawn(function()
                -- if game session is still on, generate the next wave after a delay
                local countdown = SharedConfig.ENEMY_WAVE_DELAY
                while countdown > 0 do
                    task.wait(0.1)
                    countdown -= 0.1
                    if not worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value) then
                        -- game session stopped, cancel second wave
                        isToSpawn = false
                        break
                    end
                end
                if isToSpawn and countdown < 0 then
                    if not isPvPTime(get_state) then
                        generateEnemies(worldState, get_state)
                    end
                end
            end)
        end
    end)
end

local function selectPlayer(playersInSession: { Player }, enemyPos: Vector3, enemyRefId: id): (Player?, BasePart?, num?)
    local playerPool = {}

    for _, p in ipairs(playersInSession) do
        local char = p.Character :: Model
        local playerRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
        local distToTarget = (enemyPos - playerRoot.Position).Magnitude
        if enemyRefId == Id.Enemy.OCTOBOSS then
            table.insert(playerPool, { player = p, playerRoot = playerRoot, distToTarget = distToTarget })
        elseif distToTarget < 150 then
            table.insert(playerPool, { player = p, playerRoot = playerRoot, distToTarget = distToTarget })
        end
    end

    if #playerPool <= 0 then
        return nil, nil, nil
    end

    local ind = math.random(1, #playerPool)
    local selectedPlayer = playerPool[ind].player
    local playerRoot = playerPool[ind].playerRoot
    local distToTarget = playerPool[ind].distToTarget

    local closenessByX = math.abs(enemyPos.X - playerRoot.Position.X)
    if closenessByX > SharedConfig.ENEMY_SIGHT_RADIUS then
        --
        return nil, nil, nil
    end

    return selectedPlayer, playerRoot, distToTarget
end

local function updatePlayerUpgrades(player_state: PSS.PlayerState, dt: num)
    for _, upgrade_id in Id.PlayerUpgradeNonPersistent:ids() do
        local flags = player_state.state:get(upgrade_id, C.Bitset)
        local isActive = Id.flag_test(flags, Id.PlayerF.PERK_ACTIVE)
        local isExpirable = S.PlayerUpgradeNonPersistent[upgrade_id].isExpirable
        local isLooped = S.PlayerUpgradeNonPersistent[upgrade_id].isLooped
        if isActive then
            if isExpirable then
                -- expirable perks
                local currentTTL = player_state.state:get(upgrade_id, C.TTL)
                if currentTTL then
                    player_state.state:set(upgrade_id, C.TTL, currentTTL - dt)
                    if currentTTL < roflake.time() then
                        -- when time is up, reset the upgrade
                        player_state:DeactivatePlayerUpgradeNonPers(upgrade_id)
                    end
                end
            end
            if isLooped then
                -- looped perks
                local currentTTE = player_state.state:get(upgrade_id, C.TTE)
                if currentTTE then
                    player_state.state:set(upgrade_id, C.TTE, currentTTE - dt)
                end
                if currentTTE < 0 then
                    local period = S.PlayerUpgradeNonPersistent[upgrade_id].period
                    -- when time is up, do the logic and reset the tte
                    if upgrade_id == Id.PlayerUpgradeNonPersistent.CLONE_FACTORY then
                        -- clone perk
                        local stage = player_state.state:get(upgrade_id, C.ValueNonPers)
                        for i = 1, stage do
                            local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, player_state.player_id)
                        end
                    elseif upgrade_id == Id.PlayerUpgradeNonPersistent.SHIELD_RECHARGE then
                        local shieldFlags = player_state.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)
                        if not Id.flag_test(shieldFlags, Id.PlayerF.PERK_ACQUIRED) then
                            log:error("shield perk not acquired for: '%*'", player_state.player_id, debug.traceback())
                            continue
                        end
                        -- activate shield if it is not active
                        if not Id.flag_test(shieldFlags, Id.PlayerF.PERK_ACTIVE) then
                            player_state:ActivatePlayerUpgradeNonPers(Id.PlayerUpgradeNonPersistent.SHIELD)
                        end
                        -- if SHIELD COOLDOWN MULT is active, reduce the SHIELD RECHARGE period
                        local shieldCooldownFlags = player_state.state:get(Id.PlayerUpgradeNonPersistent.SHIELD_COOLDOWN_MULT, C.Bitset)
                        if Id.flag_test(shieldCooldownFlags, Id.PlayerF.PERK_ACTIVE) then
                            local cooldownMult = S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.SHIELD_COOLDOWN_MULT].multiplier :: num
                            local cooldownStage = player_state.state:get(Id.PlayerUpgradeNonPersistent.SHIELD_COOLDOWN_MULT, C.ValueNonPers)
                            if cooldownStage and cooldownStage > 0 then
                                cooldownMult *= cooldownStage
                            end
                            period -= period * cooldownMult
                        end
                    end
                    if period then
                        player_state.state:set(upgrade_id, C.TTE, period)
                    else
                        log:error("no period for looped perk: '%*'", upgrade_id, debug.traceback())
                    end
                end
            end
        end
    end
end

local function getShieldDamage(player_state: PSS.PlayerState)
    local shieldDamage = 0
    local shieldFlags = player_state.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)
    local shieldDmgFlags = player_state.state:get(Id.PlayerUpgradeNonPersistent.SHIELD_DAMAGE, C.Bitset)
    local isShieldDmg = Id.flag_test(shieldFlags, Id.PlayerF.PERK_ACTIVE) and Id.flag_test(shieldDmgFlags, Id.PlayerF.PERK_ACTIVE)
    if isShieldDmg then
        shieldDamage = assert(S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.SHIELD_DAMAGE].damage)
    end
    return isShieldDmg, shieldDamage
end

function m.Init(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    m.get_state = get_state
    -- init first batch of ground units and fill in the data table
    local firstUnit = GROUND_UNIT_TEMPLATE:Clone()
    local secondUnit = GROUND_UNIT_TEMPLATE:Clone()
    local middleUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fourthUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fifthUnit = GROUND_UNIT_TEMPLATE:Clone()
    spawnGroundUnit(worldState, firstUnit, FIELD_NAMES.FIRST, startingPos)
    spawnGroundUnit(worldState, secondUnit, FIELD_NAMES.SECOND, startingPos)
    spawnGroundUnit(worldState, middleUnit, FIELD_NAMES.MIDDLE, startingPos)

    local middle = assert(GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part)
    subscribeTrigger(worldState, get_state, FIELD_NAMES.MIDDLE, middle)

    spawnGroundUnit(worldState, fourthUnit, FIELD_NAMES.FOURTH, startingPos)
    spawnGroundUnit(worldState, fifthUnit, FIELD_NAMES.FIFTH, startingPos)
    -- unanchor the driving box so that it can register collisions
    DRIVING_BOX_BACK_PART.Anchored = false
    DRIVING_BOX_FRONT.Anchored = false
end

function m.StartMainLoopWorld(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    local oldPos = SharedConfig.DRIVING_BOX_STARTING_POS
    return function(dt)
        if not worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value) then
            return
        end

        local isBossFightOn = worldState:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
        local isPvPTime = worldState:get(Id.WorldSpecs.PVP_TIME, W.Value)
        local studPerSec = SharedConfig.MOVEMENT_SPEED
        local studPerTick = SharedConfig.MOVEMENT_SPEED * dt
        if isBossFightOn then
            studPerSec = SharedConfig.MOVEMENT_SPEED_BOSS
            studPerTick = SharedConfig.MOVEMENT_SPEED_BOSS * dt
        elseif isPvPTime then
            studPerSec = 0
            studPerTick = 0
        end

        for _, player in game.Players:GetPlayers() do
            local player_state = get_state(player.UserId)
            if not player_state then
                continue
            end

            -- handle perks
            updatePlayerUpgrades(player_state, dt)

            local nonPersFlags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
            if Id.flag_test(nonPersFlags, Id.PlayerF.READY) then
                -- weapon cooldown
                local shot_tte = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE) :: num
                shot_tte -= dt
                player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE, math.max(shot_tte, 0))

                -- player movement
                local character = player_state.character
                local humanoid = player_state.humanoid
                local playerRootPart = player_state.root
                local playerRootPartPos = playerRootPart.Position
                
                local input = humanoid.MoveDirection -- client's current input
                -- local forward = Vector3.new(playerRootPart.CFrame.LookVector.X, 0, playerRootPart.CFrame.LookVector.Z).Unit * studPerTick
                -- combine forward force + input (e.g., input.X for strafe)
                -- local moveVector = forward + Vector3.new(input.X, HUMANOID_Y_OFFSET, -studPerTick)
                -- humanoid:Move(moveVector, false)
                player_state.humanoid.WalkSpeed = studPerSec
                character:MoveTo(Vector3.new(playerRootPartPos.X + input.X/4, HUMANOID_Y_OFFSET, oldPos.Z - studPerTick - SharedConfig.PLAYER_OFFSET_FROM_DRIVER))

                -- check obstacle collision for player and driver
                for guid, refId, obstPos in WorldService.world:select(W.RefId, W.Position) do
                    if Id.kind(refId) == Id.Kind.Obstacle then
                        -- check if the player is colliding with the obstacle
                        local rootPos = playerRootPart.Position
                        if rootPos then
                            local proximityByX = math.abs(rootPos.X - obstPos.X)
                            local proximityByZ = math.abs(rootPos.Z - obstPos.Z)
                            local obstacleTemplate = assert(S.Obstacle[refId].meshTemplateFull)
                            local obstWidth = obstacleTemplate.Size.X
                            if proximityByX < obstWidth and proximityByZ < SharedConfig.COLLISION_PROXIMITY_TO_OBSTACLE then
                                if not Obstacles.IsPlayerAlreadyCollided(guid :: guid, player_state.player_id) then
                                    -- apply shield damage, if there is still an obstacle afterwards, apply damage to the player
                                    Obstacles.UpdateObstacleFlags(WorldService.world, guid :: guid, player_state.player_id)
                                    local dmg = assert(S.Obstacle[refId].damage)
                                    local isShieldDmg, shieldDamage = getShieldDamage(player_state)
                                    if isShieldDmg then
                                        Signal.Fire(Id.S2S.SHIELD_DAMAGE_SERVER, player_state.player_id, guid :: str, shieldDamage)
                                    end
                                    if worldState:has(guid) then
                                        local obstacleHp = WorldService.world:get(guid, W.HP)
                                        if obstacleHp > 0 then
                                            player_state:DeductHp(dmg - shieldDamage)
                                        end
                                    end
                                end
                            end
                        end
                        -- check if the driver back part is colliding with the obstacle
                        local driverPos = DRIVING_BOX_BACK_PART.Position
                        if driverPos then
                            if driverPos.Z < obstPos.Z then
                                WorldService.RemoveEntity(guid)
                            end
                        end
                    end
                end
            end
        end

        -- driving box movement
        if isBossFightOn then
            DRIVING_BOX_INSTANCE:PivotTo(CFrame.new(oldPos.X, oldPos.Y, oldPos.Z - studPerTick))
        elseif isPvPTime then
            -- do nothing
        else
            DRIVING_BOX_INSTANCE:PivotTo(CFrame.new(oldPos.X, oldPos.Y, oldPos.Z - studPerTick))
        end
        -- TODO: stop it altogether after some time when boss fight is on to prevent new unit generation and lock player on the current unit
        oldPos = DRIVING_BOX_BACK_PART.Position

        -- handle enemies and bombs
        for guid, refId, currentPos in worldState:select(W.RefId, W.Position) do
            -- flying enemies
            if Id.kind(refId) == Id.Kind.EnemyFlying then
                -- remove flyers if they "collided" with the driving box's rear
                if DRIVING_BOX_BACK_PART.Position.Z <= currentPos.Z then
                    m.DestroyEnemy(guid :: string)
                else
                    local tte = worldState:get(guid, W.TTE)
                    if tte < roflake.time() then
                        -- reset tte
                        local period = assert(S.EnemyFlying[refId].period)
                        local newTTE = roflake.time() + Rand.uniform(period.X, period.Y)
                        worldState:set(guid, W.TTE, newTTE)
                        -- spawn bomb
                        local flyerHeight = assert(S.EnemyFlying[refId].flyerHeight)
                        local _bombGuid = WorldService.AddBombToState(Id.Bomb.ZOMBALLOON_BOMB, currentPos + Vector3.new(0, flyerHeight, 0), guid)
                    end
                end

            -- bombs
            elseif Id.kind(refId) == Id.Kind.Bomb then
                local bombPos = worldState:get(guid, W.Position)
                if bombPos then
                    -- update bomb's position
                    local ownerGuid = worldState:get(guid, W.OwnerGuid)
                    if not ownerGuid then
                        log:error("no ownerGuid found for bomb: '%*'", guid)
                        continue
                    end
                    local ownerRefId = worldState:get(ownerGuid, W.RefId)
                    local bombSpeed = 0.1
                    if ownerRefId then
                        bombSpeed = assert(S.Bomb[refId].bombSpeed)
                    end
                    worldState:set(guid, W.Position, bombPos - Vector3.new(0, bombSpeed, 0))

                    -- check for collisions with the ground
                    local groundUnit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part
                    local groundUnitPos = groundUnit.Position
                    local distY = math.abs(bombPos.Y - groundUnitPos.Y)
                    if distY < 2 then
                        WorldService.RemoveEntity(guid)
                    end

                    -- check for collisions with players
                    local players = game.Players:GetPlayers()
                    for _, player in ipairs(players) do
                        local weaponId = worldState:get(player.UserId, W.WeaponId)
                        if weaponId ~= Id.Weapon._NONE then
                            local playerHead = player.Character:FindFirstChild("Head")
                            if playerHead then
                                local playerHeadPos = playerHead.Position
                                local dist = (bombPos - playerHeadPos).Magnitude
                                local explosionSize = assert(S.Bomb[refId].explosionSize)
                                if dist < explosionSize.X then
                                    -- harm player, delete bomb
                                    local dmg = assert(S.Bomb[refId].damage)
                                    local playerState = get_state(player.UserId)
                                    if playerState then
                                        playerState:DeductHp(dmg)
                                    end
                                    local thisPlayerState = assert(get_state(player.UserId))
                                    thisPlayerState:NotifyClient(Id.S2C.BOMB_HIT, guid, playerHeadPos)
                                    WorldService.RemoveEntity(guid)
                                end
                            end
                        end
                    end
                end
            -- infantry enemies
            elseif Id.kind(refId) == Id.Kind.Enemy then
                assert(typeof(guid) == "string") -- sanity check
                local flags = worldState:get(guid, W.Bitset)
                local enemyTemplate = assert(S.Enemy[refId].meshTemplate)
                local speed = log:assert(S.Enemy[refId].speed, "S.Enemy has no speed for: '%*'", refId)
                local newPos = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + dt * speed)
                local distToTarget
                local playerId
                local playerState
                local playersInSession = {}

                if flags and Id.flag_test(flags, Id.EnemyF.SEEK_ACTIVATED) then
                    local players = game.Players:GetPlayers()
                    for _, player in ipairs(players) do
                        local weaponId = worldState:get(player.UserId, W.WeaponId)
                        if weaponId ~= Id.Weapon._NONE then
                            table.insert(playersInSession, player)
                        else
                            -- player is not in session, remove this enemy's lock on him if any
                            playerId = player.UserId :: int
                            if worldState:get(guid, W.PlayerId) == playerId then
                                worldState:set(guid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                            end
                        end
                    end
                    if #playersInSession > 0 then
                        local player, playerRoot
                        if (not worldState:get(guid, W.PlayerId)) or worldState:get(guid, W.PlayerId) == SharedConfig.DEFAULT_PLAYER_ID then
                            -- select a player that is close enough to the enemy
                            player, playerRoot, distToTarget = selectPlayer(playersInSession, currentPos, refId)
                            if player then
                                -- a player that is close enough is selected, set lock to target
                                playerId = player.UserId :: int
                                worldState:set(guid, W.PlayerId, playerId)
                            end
                        else
                            -- enemy is already locked on target, assign player, playerRoot and distTotarget
                            playerId = worldState:get(guid, W.PlayerId)
                            player = game.Players:GetPlayerByUserId(playerId)
                            playerState = get_state(worldState:get(guid, W.PlayerId))
                            if playerState then
                                playerRoot = playerState.root :: BasePart
                                if not playerRoot then
                                    log:error("No player root found for player: '%*'", worldState:get(guid, W.PlayerId))
                                    return
                                end
                                local toTarget = currentPos - playerRoot.Position
                                distToTarget = toTarget.Magnitude
                            else
                                log:error("No player state found for player: '%*'", worldState:get(guid, W.PlayerId))
                                return
                            end
                        end

                        if player and playerRoot and distToTarget then
                            -- local time_to_target = distToTarget / speed
                            local critDist = 10 --1.5
                            playerId = player.UserId :: int
                            playerState = get_state(playerId)
                            if currentPos.Z - 5 > playerRoot.Position.Z then -- enemy got behind the player, cancel seeking
                                if refId ~= Id.Enemy.OCTOBOSS then -- boss is an exception
                                    worldState:set(guid, W.Bitset, Id.flag_set(flags, Id.EnemyF.SEEK_ACTIVATED, false))
                                    worldState:set(guid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                end
                            -- elseif distToTarget < 20 then
                            elseif currentPos.Z > playerRoot.Position.Z - critDist then
                                -- enemy is pretty close to player, cancel seeking
                                if refId ~= Id.Enemy.OCTOBOSS then -- boss is an exception
                                    worldState:set(guid, W.Bitset, Id.flag_set(flags, Id.EnemyF.SEEK_ACTIVATED, false))
                                    worldState:set(guid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                end
                            else
                                -- predict player's position, binomial distribution add some randomness
                                local playerPos = playerRoot.Position
                                local targetPos = Vector3.new(playerPos.X, playerPos.Y, playerPos.Z - critDist)
                                -- local target = targetPos + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                local dist = (currentPos - targetPos).Magnitude
                                local t = dist / speed
                                local target = targetPos + (rand.binomial() * t) * playerRoot.AssemblyLinearVelocity
                                newPos = currentPos:Lerp(target, dt * speed / dist) -- Move towards the predicted position slightly ahead of the player
                            end
                        else
                            -- no player is close enough, remove lock to target if any
                            worldState:set(guid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                        end
                    end
                end

                -- check for "collision" with players
                if #playersInSession > 0 then
                    for _, player in ipairs(playersInSession) do
                        local thisPlayerState = get_state(player.UserId)
                        if thisPlayerState then
                            local root = thisPlayerState.root :: BasePart
                            local proximity = (currentPos - root.Position).Magnitude
                            local thickness = enemyTemplate.Size.Z / 2
                            if proximity < thickness then
                                -- enemy is critically close to player, check for shield damage
                                local isShieldDmg, shieldDamage = getShieldDamage(thisPlayerState)
                                if isShieldDmg then
                                    Signal.Fire(Id.S2S.SHIELD_DAMAGE_SERVER, thisPlayerState.player_id, guid :: str, shieldDamage)
                                end
                                -- if there is still an enemy afterwards, apply damage to the player, then die (boss is an exception)
                                if worldState:has(guid) then
                                    local enemyDamage = S.Enemy[refId].damage
                                    thisPlayerState:DeductHp(enemyDamage - shieldDamage)
                                    if refId ~= Id.Enemy.OCTOBOSS then
                                        -- TODO: effects
                                        m.DestroyEnemy(guid)
                                    end
                                end
                            end
                        end
                    end
                end

                if worldState:has(guid) then
                    -- update enemy's position
                    worldState:set(guid, W.Position, newPos)

                    if DRIVING_BOX_BACK_PART.Position.Z <= currentPos.Z then
                        -- destroy enemy if it collided with the driving box's rear
                        if refId ~= Id.Enemy.OCTOBOSS then -- boss is an exception
                            m.DestroyEnemy(guid)
                        end
                    elseif DRIVING_BOX_FRONT.Position.Z <= currentPos.Z then
                        -- activate seek mode on collision with the driver box's front
                        worldState:set(guid, W.Bitset, Id.flag_or(flags, Id.EnemyF.SEEK_ACTIVATED))
                    end
                end
            end
        end

        -- check clones collisions
        for cloneGuid, refId, playerId in worldState:select(W.RefId, W.PlayerId) do
            if Id.kind(refId) == Id.Kind.Clone then
                local playerState = get_state(playerId)
                if not playerState then
                    continue
                end
                -- with boosters
                -- checking second unit, not middle because the units' indeces has already shifted
                local currentGroundUnit = GROUND_UNITS[FIELD_NAMES.SECOND].unit :: Part
                local playerRootPart = playerState.root :: BasePart
                -- local rootPos = playerRootPart.Position
                local cloneIndex = worldState:get(cloneGuid, W.Value)
                local alreadyInCol = (cloneIndex - 1) % SharedConfig.CLONES_IN_A_ROW
                local row = math.floor((cloneIndex - 1) / SharedConfig.CLONES_IN_A_ROW) + 1
                local cloneCFrame = Misc.GetCloneCFrame(playerRootPart.CFrame, alreadyInCol, row)
                local isCollided = false
                for _, booster in currentGroundUnit:GetChildren() do
                    if not worldState:has(booster.Name) then
                        continue
                    end
                    local boosterInstance = worldState:get(booster.Name, W.ServerInstance)
                    local boosterSizeZ = boosterInstance.Size.Z
                    local boosterSizeX = boosterInstance.Size.X
                    -- local distZ = math.abs(clonePos.Z - boosterInstance.Position.Z)
                    -- local distX = math.abs(clonePos.X - boosterInstance.Position.X)
                    local distZ = math.abs(cloneCFrame.Position.Z - boosterInstance.Position.Z)
                    local distX = math.abs(cloneCFrame.Position.X - boosterInstance.Position.X)
                    if distZ < boosterSizeZ / 2 and distX < boosterSizeX / 2 then
                        -- Misc.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED_HIGH], cloneCFrame.Position, 0)
                        WorldService.RemoveEntity(cloneGuid)
                        isCollided = true
                        break
                    end
                end

                if isCollided then
                    continue
                end

                -- with obstacles and bombs
                for objectGuid, refId, objectPos in worldState:select(W.RefId, W.Position) do
                    if Id.kind(refId) == Id.Kind.Obstacle then
                        -- local proximityByX = math.abs(clonePos.X - obstaclePos.X)
                        -- local proximityByZ = math.abs(clonePos.Z - obstaclePos.Z)
                        -- local obstacleTemplate = assert(S.Obstacle[refId].meshTemplateFull)
                        -- local obstWidth = obstacleTemplate.Size.X
                        -- if proximityByX < obstWidth and proximityByZ < SharedConfig.COLLISION_PROXIMITY_TO_OBSTACLE then
                        -- if (cloneCFrame - obstaclePos).Magnitude < 10 then
                        if (cloneCFrame.Position - objectPos).Magnitude < 10 then
                            -- Misc.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED_HIGH], cloneCFrame.Position, 0)
                            -- Misc.SoundLocalizedAudio(S.Sound[Id.Sound.THUMP_LOCALIZED], cloneCFrame.Position, 0)
                            WorldService.RemoveEntity(cloneGuid)
                            isCollided = true
                            break
                        end
                    elseif Id.kind(refId) == Id.Kind.Bomb then
                        -- if (cloneCFrame - obstaclePos).Magnitude < 20 then
                        local ownerGuid = worldState:get(objectGuid, W.OwnerGuid)
                        if not ownerGuid then
                            log:error("no ownerGuid found for bomb: '%*'", objectGuid)
                            continue
                        end
                        local explosionSize = assert(S.Bomb[refId].explosionSize)
                        if (cloneCFrame.Position - objectPos).Magnitude < explosionSize.X then
                            -- Misc.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED_HIGH], cloneCFrame.Position, 0)
                            playerState:NotifyClient(Id.S2C.BOMB_HIT, objectGuid, objectPos)
                            WorldService.RemoveEntity(cloneGuid)
                            isCollided = true
                            break
                        end
                    end
                end

                if isCollided then
                    continue
                end
            end
        end

        -- delete bullet entity when ttl is up
        for bulletGuid, startPos, ownerId, weaponId, ttl in worldState:select(W.Position, W.PlayerId, W.WeaponId, W.TTL) do
            if roflake.time() > ttl then
                WorldService.RemoveEntity(bulletGuid)
            end
        end
    end
end

m.DestroyEnemy = function(guid, playerId: num?)
    if WorldService.world:has(guid) then
        WorldService.RemoveEntity(guid)
    end
    assert(typeof(guid) == "string") -- sanity check
    workerMaid[guid] = nil
end

m.Cleanup = function()
    -- anchor driving box so that it won't fall down
    DRIVING_BOX_BACK_PART.Anchored = true
    DRIVING_BOX_FRONT.Anchored = true

    -- delete ground units
    local groundUnits = GROUND_UNIT_FOLDER:GetChildren()
    for i, unit in ipairs(groundUnits) do
        deleteGroundUnit(unit, i)
    end
    for i, entry in ipairs(GROUND_UNITS) do
        entry.unit = nil
    end

    workerMaid.trigger = nil

    -- delete boosters
    for guid, refId, _value, _hp, _boostContentId in WorldService.world:select(W.RefId, W.Value, W.HP, W.BoostContentId, W.ServerInstance) do
        if Id.kind(refId) == Id.Kind.Boost then
            WorldService.RemoveEntity(guid)
        end
    end

    -- reset driving box position
    DRIVING_BOX_INSTANCE:PivotTo(CFrame.new(SharedConfig.DRIVING_BOX_STARTING_POS))

    -- delete bullets
    for guid, _pos, _playerId, _weaponId, _ttl in WorldService.world:select(W.Position, W.PlayerId, W.WeaponId, W.TTL) do
        WorldService.RemoveEntity(guid)
    end
end

function m.HandleBoosterDeath(playerState: PSS.PlayerState, booster_guid: str, boost_ref_id: id, value: num, boost_content_id: id)
    if not boost_ref_id then
        log:error("no boost_id", debug.traceback)
    end
    -- unsubscribe booster
    workerMaid[booster_guid] = nil
    if boost_ref_id == Id.Boost.ADD_CLONE then
        for i = 1, value do
            local playerId = playerState.player_id
            local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, playerId)
        end
    elseif boost_ref_id == Id.Boost.CHANGE_WEAPON then
        Signal.Fire(Id.S2S.CHANGE_WEAPON, playerState.player_id, boost_content_id)
    elseif boost_ref_id == Id.Boost.FIRST_AID_KIT then
        local old_hp, new_hp = playerState:AddHp(value)
        local hp_added = new_hp - old_hp
        playerState:NotifyClient(Id.S2C.BOOSTER_DESTROYED, boost_ref_id, hp_added, boost_content_id)
    end
end

function m.SpawnPlayer(player_state: PSS.PlayerState, players_in_session: int)
    -- TODO: refactor into being able to spawn only between sessions

    -- NOTE: players_already_in_session includes this player_state.player

    -- define spawning position
    local nonPersFlags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.flag_or(nonPersFlags, Id.PlayerF.READY))

    local playerCharacter = player_state.character :: Model
    local playerRootPart = player_state.root :: Part

    local driver_pos = DRIVING_BOX_BACK_PART.Position
    local ground_folder = workspace:FindFirstChild("GroundUnits")
    local existing_ground_units = ground_folder:GetChildren()
    local last_spawned_ground_unit = existing_ground_units[#existing_ground_units]
    local boosters = {}
    for _, child in last_spawned_ground_unit:GetChildren() do
        if child:FindFirstChild("BoosterGui") then
            table.insert(boosters, child)
        end
    end

    assert(#boosters > 0 and #boosters % 2 == 0)

    local x_pos = driver_pos.X
    local index = 1
    if players_in_session > #boosters then
        index = math.random(1, #boosters)
    elseif players_in_session % 2 == 0 then
        -- evens
        local starting_point = #boosters / 2 + 1
        index = starting_point - players_in_session / 2
    else
        -- odds
        local starting_point = #boosters / 2
        index = starting_point + (players_in_session + 1) / 2
    end
    x_pos = boosters[index].Position.X
    local y_pos = playerRootPart.Position.Y
    local z_pos = driver_pos.Z - SharedConfig.PLAYER_OFFSET_FROM_DRIVER
    if players_in_session > 1 then
        local all_players = game.Players:GetPlayers()
        local isInSession = false
        for _, otherPlayer in all_players do
            local weapon_id = WorldService.world:get(otherPlayer.UserId, W.WeaponId)
            isInSession = weapon_id ~= Id.Weapon._NONE
            if isInSession then
                z_pos = otherPlayer.Character.HumanoidRootPart.Position.Z
            end
        end
        assert(isInSession) -- sanity check
    end

    local target_c_frame = CFrame.new(x_pos, y_pos, z_pos)
    playerRootPart.CFrame = target_c_frame

    -- set player alignment
    local attAlign = Instance.new("Attachment") :: Attachment
    attAlign.CFrame = playerRootPart.CFrame
    attAlign.Parent = playerRootPart
    local playerAlignConst = Instance.new("AlignOrientation")
    playerAlignConst.Name = SharedConfig.PLAYER_ALIGN_CONSTR_NAME
    playerAlignConst.Parent = playerCharacter
    playerAlignConst.Attachment0 = attAlign
    playerAlignConst.Attachment1 = DRIVING_BOX_ATT

    -- create attachement for clones
    local attClones = Instance.new("Attachment") :: Attachment
    attClones.Name = SharedConfig.CLONE_ATTACHMENT_NAME
    attClones.CFrame = playerRootPart.CFrame
    attClones.Parent = playerRootPart

    HUMANOID_Y_OFFSET = y_pos
end

print("[Game Module -- started]")
return m
