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
local supervisor = require(shared.supervisor)
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ftest = WorldService.ftest
local worldfset = WorldService.fset

local m = {} :: {
    get_state: (int) -> PSS.PlayerState?,
    StarFstartmaintMainLoopPlayer: (PSS.PlayerState) -> (num) -> (),
    Init: (state: state.Main, (int) -> PSS.PlayerState?) -> (),
    CreatePlayerHpGui: (PSS.PlayerState) -> (),
    DestroyEnemy: (enemy_guid: str, player_id: num?) -> (),
    StartDamageThrottleSupervisor: (get_state: (player_id: int) -> PSS.PlayerState?) -> supervisor.supervisor,
    Cleanup: () -> (),
    HandleBoosterDeath: (PSS.PlayerState, booster_guid: str, boost_ref_id: id, value: num, boost_content_id: id) -> (),
    StartMainLoopWorld: (world_state: state.Main, (int) -> PSS.PlayerState?) -> (num) -> (),
    SetPlayerAlignment: (PSS.PlayerState) -> (),
    SpawnPlayer: (PSS.PlayerState, int) -> (),
    UnconstrainPlayer: (PSS.PlayerState) -> (),
    UpdatePlayerIntendedPos: (PSS.PlayerState, Vector3) -> (),
    ApplyExplosionKnockback: (PSS.PlayerState, Vector3, num?, num?) -> (),
}

local workerMaid = disposer.new()

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
local STARTING_POS = Vector3.new(0, -10, 0)

local DRIVING_BOX_TEMPLATE = assert(ReplicatedStorage.DrivingBoxModel)
local DRIVING_BOX_INSTANCE = DRIVING_BOX_TEMPLATE:Clone()
DRIVING_BOX_INSTANCE.Parent = game.Workspace
local DRIVING_BOX_BACK_PART = assert(DRIVING_BOX_INSTANCE.DrivingBoxBackPart)
local DRIVING_BOX_FRONT = assert(DRIVING_BOX_INSTANCE.PartFront)
local DRIVING_BOX_LIMIT_LEFT = assert(DRIVING_BOX_INSTANCE.LimitLeft)
local DRIVING_BOX_LIMIT_RIGHT = assert(DRIVING_BOX_INSTANCE.LimitRight)
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

local function onBossArrival(get_state: (player_id: int) -> PSS.PlayerState?, enemyGuid: guid)
    WorldService.SetBossFightOn(enemyGuid)
    -- spawn poison belt
    local poisonBeltInstance = assert(ReplicatedStorage.VFX:WaitForChild("PoisonBeltServer")):Clone()
    poisonBeltInstance.Parent = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit
    poisonBeltInstance.Anchored = true
    poisonBeltInstance.Transparency = 1
    local driverPos = DRIVING_BOX_BACK_PART.Position
    poisonBeltInstance.Position = Misc.GetPoisonBeltStartingPosition(driverPos)
    poisonBeltInstance.Name = SharedConfig.POISON_BELT_NAME_SERVER
    Misc.AnimatePoisonBelt(poisonBeltInstance, poisonBeltInstance)

    for _, player in game.Players:GetPlayers() do
        local player_state = get_state(player.UserId)
        if not player_state then
            continue
        end
        player_state.humanoid.WalkSpeed = SharedConfig.PLAYER_DEFAULT_WALK_SPEED
        player_state.humanoid.AutoRotate = false
    end
end

local function setBooster(worldState: state.Main, instance: BasePart, get_state: (int) -> PSS.PlayerState?)
    local refID, boostContentId = BoosterServer.SetBoosterValue(worldState)
    local valueRange = S.Boost[refID].valueRange
    local hpRange = S.Boost[refID].hpRange
    local hp_mult = BoosterServer.GetCurrentBoosterHpMult(worldState)
    local hp_average = (hpRange.X + hpRange.Y) / 2
    local hp_no_mult = math.random(hpRange.X, hpRange.Y)
    -- double hp if there is an according handicap. NOTE: this is currently disabled
    -- local current_handicap = WorldService.world:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
    -- if current_handicap == Id.Handicap.DOUBLE_HP then
    --     hp_no_mult *= SharedConfig.HP_HANDICAP_MULT
    -- end
    local hp_w_mult = math.floor(hp_no_mult * hp_mult)
    local value_average = math.floor((valueRange.X + valueRange.Y) / 2)
    local value
    if hp_no_mult < hp_average then
        value = math.random(valueRange.X, value_average)
    else
        value = math.random(value_average, valueRange.Y)
    end

    local contentsBillboardInstance = BOOSTER_CONTENTS_BILLBOARD_TEMPLATE:Clone()
    local boosterPos = instance.Position
    local billboardPos = contentsBillboardInstance.Position
    contentsBillboardInstance.CFrame = CFrame.new(boosterPos.X, billboardPos.Y, boosterPos.Z)
    contentsBillboardInstance.Parent = instance
    local contentsTextbox = contentsBillboardInstance.BoosterContentsGui.TextLabel
    local txt = ""
    local col = instance.Color
    if refID == Id.Boost.ADD_CLONE then
        local s = ""
        col = Color3.fromRGB(0, 255, 0)
        if value > 1 then
            s = "s"
            col = Color3.fromRGB(1, 255, 166)
        end
        txt = string.format("+%d clone%s", value, s)
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
    boosterGui.TextLabel.Text = NumFormat.format_damage(hp_w_mult)
    boosterGui.TextLabel.TextColor3 = col

    instance:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost], refID)
    instance.CollisionGroup = "BulletCollidable"
    -- add booster to world state
    local boosterGuid = WorldService.AddBooster(instance, refID, value, hp_w_mult, boostContentId)
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
    local enemyGuids = {} :: { guid }
    for _, enemyGuid in ipairs(enemyWalkingGuids) do
        table.insert(enemyGuids, enemyGuid)
    end

    local enemiesFlyingGuids = EnemiesFlying.AddEnemiesFlying(worldState, unit, true, newWaveNumber) :: {}
    for _, enemyGuid in ipairs(enemiesFlyingGuids) do
        table.insert(enemyGuids, enemyGuid)
    end

    if #enemyGuids > 0 then
        for _, enemyGuid in ipairs(enemyGuids) do
            local refId = worldState:get(enemyGuid, W.RefId)
            -- NOTE: can't test the 'isBoss' flag, because it is yet to be set
            if Id.kind(refId) == Id.Kind.Enemy and refId > Id.Enemy._BOSS then
                onBossArrival(get_state, enemyGuid)
            end
        end
    end
end

local function isPvPTime(get_state: (player_id: int) -> PSS.PlayerState?)
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
            WorldService.UpdateObstacleWaveCount()
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
            -- rename all units accordingly
            assert(GROUND_UNITS[FIELD_NAMES.FIRST].unit).Name = "1"
            assert(GROUND_UNITS[FIELD_NAMES.SECOND].unit).Name = "2"
            assert(GROUND_UNITS[FIELD_NAMES.MIDDLE].unit).Name = "3"
            assert(GROUND_UNITS[FIELD_NAMES.FOURTH].unit).Name = "4"
            assert(GROUND_UNITS[FIELD_NAMES.FIFTH].unit).Name = "5"

            if worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value) then
                -- if not isPvPTime(get_state) then
                generateEnemies(worldState, get_state)
                -- end
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
                    -- if not isPvPTime(get_state) then
                    generateEnemies(worldState, get_state)
                    -- end
                end
            end)
        end
    end)
end

local function selectPlayerToLockOn(
    worldState: state.Main,
    playersInSession: { Player },
    enemyPos: Vector3,
    enemyGuid: uid,
    enemyRefId: id
): (Player?, BasePart?, num?)
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

    if #playerPool < 1 then
        return nil, nil, nil
    end

    local ind = math.random(1, #playerPool)
    local selectedPlayer = playerPool[ind].player
    local playerRoot = playerPool[ind].playerRoot
    local distToTarget = playerPool[ind].distToTarget

    local closenessByX = math.abs(enemyPos.X - playerRoot.Position.X)
    if closenessByX > SharedConfig.ENEMY_SIGHT_RADIUS and enemyRefId ~= Id.Enemy.OCTOBOSS then
        return nil, nil, nil
    end

    if selectedPlayer and S.Enemy[enemyRefId].ttl then
        local baseTTL = assert(S.Enemy[enemyRefId].ttl)
        local ttl = math.random(baseTTL - 1, baseTTL + 1)
        worldState:set(enemyGuid, W.TTL, roflake.time() + ttl)
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
                            period *= cooldownMult
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

local function getEnemyTargetPos(playerRoot: BasePart, critDist: num, currentPos: Vector3, speed: num, dt: num)
    -- predict player's position, binomial distribution add some randomness
    local playerPos = playerRoot.Position
    local targetPos = Vector3.new(playerPos.X, playerPos.Y, playerPos.Z - critDist)
    -- local target = targetPos + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
    local dist = (currentPos - targetPos).Magnitude
    local t = dist / speed
    local target = targetPos + (rand.binomial() * t) * playerRoot.AssemblyLinearVelocity
    local newPos
    newPos = currentPos:Lerp(target, dt * speed / dist) -- Move towards the predicted position slightly ahead of the player
    return newPos
end

function m.Init(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    m.get_state = get_state
    -- init first batch of ground units and fill in the data table
    local firstUnit = GROUND_UNIT_TEMPLATE:Clone()
    local secondUnit = GROUND_UNIT_TEMPLATE:Clone()
    local middleUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fourthUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fifthUnit = GROUND_UNIT_TEMPLATE:Clone()
    spawnGroundUnit(worldState, firstUnit, FIELD_NAMES.FIRST, STARTING_POS)
    spawnGroundUnit(worldState, secondUnit, FIELD_NAMES.SECOND, STARTING_POS)
    spawnGroundUnit(worldState, middleUnit, FIELD_NAMES.MIDDLE, STARTING_POS)

    local middle = assert(GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part)
    subscribeTrigger(worldState, get_state, FIELD_NAMES.MIDDLE, middle)

    spawnGroundUnit(worldState, fourthUnit, FIELD_NAMES.FOURTH, STARTING_POS)
    spawnGroundUnit(worldState, fifthUnit, FIELD_NAMES.FIFTH, STARTING_POS)
    -- unanchor the driving box so that it can register collisions
    DRIVING_BOX_BACK_PART.Anchored = false
    DRIVING_BOX_FRONT.Anchored = false
end

function m.StartMainLoopWorld(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    local driverOldPos = SharedConfig.DRIVING_BOX_STARTING_POS
    return function(dt)
        if not worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value) then
            return
        end

        local isBossFightOn = worldState:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
        local studPerSec = SharedConfig.MOVEMENT_SPEED
        local studPerTick = SharedConfig.MOVEMENT_SPEED * dt
        if isBossFightOn then
            studPerSec = SharedConfig.MOVEMENT_SPEED_BOSS
            studPerTick = SharedConfig.MOVEMENT_SPEED_BOSS * dt
        end

        for _, player in game.Players:GetPlayers() do
            local playerState = get_state(player.UserId)
            if not playerState then
                continue
            end

            -- handle handicaps
            local current_handicap = worldState:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
            if current_handicap == Id.Handicap.HP_DRAIN then
                local hp_drain = SharedConfig.HP_DRAIN_AMOUNT
                local tte = worldState:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.TTE) :: num
                if tte < 0 then
                    playerState:DeductHp(hp_drain, Id.Handicap.HP_DRAIN)
                    local hp_drain_period = SharedConfig.HP_DRAIN_PERIOD
                    worldState:set(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.TTE, hp_drain_period)
                end
            end

            -- handle perks
            updatePlayerUpgrades(playerState, dt)

            local nonPersFlags = playerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
            if Id.flag_test(nonPersFlags, Id.PlayerF.READY) then
                -- weapon cooldown
                local shot_tte = playerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE) :: num
                shot_tte -= dt
                playerState.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE, math.max(shot_tte, 0))

                local humanoid = playerState.humanoid
                local character = playerState.character
                local playerRootPart = playerState.root
                local playerRootPartPos = playerRootPart.Position

                -- just-in-case measure: kill off the players that fall beneath the ground
                if playerRootPartPos.Y < 0 then
                    playerState:DeductHp(1000)
                end

                local input = humanoid.MoveDirection -- client's current input

                -- player movement (boss fight is handled separately below)
                if not isBossFightOn then
                    playerState.humanoid.WalkSpeed = studPerSec

                    -- limit player's movement to the driving box's limits
                    local currentX = playerRootPartPos.X
                    local currentZ = playerRootPartPos.Z
                    local changeX = input.X / 4
                    local changeZ = studPerTick
                    local newX = currentX + changeX
                    local newZ = currentZ - changeZ
                    if
                        newX > DRIVING_BOX_LIMIT_RIGHT.Position.X - DRIVING_BOX_LIMIT_RIGHT.Size.Z
                        or newX < DRIVING_BOX_LIMIT_LEFT.Position.X + DRIVING_BOX_LIMIT_RIGHT.Size.Z
                    then
                        newX = currentX
                    end
                    if
                        newZ > DRIVING_BOX_BACK_PART.Position.Z - DRIVING_BOX_FRONT.Size.Z
                        or newZ < DRIVING_BOX_FRONT.Position.Z + DRIVING_BOX_FRONT.Size.Z / 2
                    then
                        newZ = currentZ
                    end

                    character:PivotTo(CFrame.new(newX, HUMANOID_Y_OFFSET, newZ))
                end

                -- check obstacle collision for player and driver
                for guid, refId, obstPos in WorldService.world:select(W.RefId, W.Position) do
                    if Id.kind(refId) == Id.Kind.Obstacle then
                        -- check if the player is colliding with the obstacle
                        if playerRootPart then
                            local proximityByX = math.abs(playerRootPart.Position.X - obstPos.X)
                            local proximityByZ = math.abs(playerRootPart.Position.Z - obstPos.Z)
                            local obstacleTemplate = assert(S.Obstacle[refId].meshTemplateFull)
                            local obstWidth = obstacleTemplate.Size.X
                            if proximityByX < obstWidth and proximityByZ < SharedConfig.COLLISION_PROXIMITY_TO_OBSTACLE then
                                if not Obstacles.IsPlayerAlreadyCollided(guid :: guid, playerState.player_id) then
                                    -- apply shield damage, if there is still an obstacle afterwards, apply damage to the player
                                    Obstacles.UpdateObstacleFlags(WorldService.world, guid :: guid, playerState.player_id)
                                    local dmg = assert(S.Obstacle[refId].damage)
                                    local isShieldDmg, shieldDamage = getShieldDamage(playerState)
                                    if isShieldDmg then
                                        Signal.Fire(Id.S2S.SHIELD_DAMAGE_SERVER, playerState.player_id, guid :: str, shieldDamage)
                                    end
                                    if worldState:has(guid) then
                                        local obstacleHp = WorldService.world:get(guid, W.HP)
                                        if obstacleHp > 0 then
                                            playerState:DeductHp(dmg - shieldDamage)
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
        if not isBossFightOn then
            DRIVING_BOX_INSTANCE:PivotTo(CFrame.new(driverOldPos.X, driverOldPos.Y, driverOldPos.Z - studPerTick))
        end
        driverOldPos = DRIVING_BOX_BACK_PART.Position

        -- handle enemies and bombs
        for enemyGuid, refId, currentPos in worldState:select(W.RefId, W.Position) do
            -- flying enemies
            if Id.kind(refId) == Id.Kind.EnemyFlying then
                -- remove flyers if they "collided" with the driving box's rear
                if DRIVING_BOX_BACK_PART.Position.Z <= currentPos.Z then
                    m.DestroyEnemy(enemyGuid :: string)
                else
                    local tte = worldState:get(enemyGuid, W.TTE)
                    if tte < roflake.time() then
                        -- reset tte
                        local period = assert(S.EnemyFlying[refId].period)
                        local newTTE = roflake.time() + Rand.uniform(period.X, period.Y)
                        worldState:set(enemyGuid, W.TTE, newTTE)
                        -- spawn bomb
                        local flyerHeight = assert(S.EnemyFlying[refId].flyerHeight)
                        local _bombGuid = WorldService.AddBombToState(Id.Bomb.ZOMBALLOON_BOMB, currentPos + Vector3.new(0, flyerHeight, 0), enemyGuid)
                    end
                end

            -- bombs
            elseif Id.kind(refId) == Id.Kind.Bomb then
                local bombPos = worldState:get(enemyGuid, W.Position)
                if bombPos then
                    -- update bomb's position
                    local ownerGuid = worldState:get(enemyGuid, W.OwnerGuid)
                    if not ownerGuid then
                        log:error("no ownerGuid found for bomb: '%*'", enemyGuid)
                        continue
                    end
                    local ownerRefId = worldState:get(ownerGuid, W.RefId)
                    local bombSpeed = 0.1
                    if ownerRefId then
                        bombSpeed = assert(S.Bomb[refId].bombSpeed)
                    end
                    worldState:set(enemyGuid, W.Position, bombPos - Vector3.new(0, bombSpeed, 0))

                    -- check for collisions with the ground
                    local groundUnit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit :: Part
                    local groundUnitPos = groundUnit.Position
                    local distY = math.abs(bombPos.Y - groundUnitPos.Y)
                    if distY < 2 then
                        Misc.SoundLocalizedAudio(S.Sound[Id.Sound.EXPLOSION_SHORT_LOCALIZED], bombPos, 0)
                        WorldService.RemoveEntity(enemyGuid)
                    end

                    -- check for collisions with players
                    local players = game.Players:GetPlayers()
                    for _, player in ipairs(players) do
                        local weaponId = worldState:get(player.UserId, W.WeaponId)
                        if weaponId ~= Id.Weapon._NONE then
                            local playerHead = player.Character:FindFirstChild("Head")
                            if playerHead then
                                local playerHeadPos = playerHead.Position
                                -- local dist = (bombPos - playerHeadPos).Magnitude
                                local distByX = math.abs(bombPos.X - playerHeadPos.X)
                                local distByZ = math.abs(bombPos.Z - playerHeadPos.Z)
                                local explosionSize = assert(S.Bomb[refId].explosionSize)
                                if distByX < explosionSize.X / 2 and distByZ < explosionSize.Z / 2 then
                                    -- harm player, delete bomb
                                    local dmg = assert(S.Bomb[refId].damage)
                                    local playerState = get_state(player.UserId)
                                    if playerState then
                                        playerState:DeductHp(dmg)
                                    end
                                    local thisPlayerState = assert(get_state(player.UserId))
                                    thisPlayerState:NotifyClient(Id.S2C.BOMB_HIT, enemyGuid, playerHeadPos)
                                    WorldService.RemoveEntity(enemyGuid)
                                end
                            end
                        end
                    end
                end

            -- infantry enemies
            elseif Id.kind(refId) == Id.Kind.Enemy then
                assert(typeof(enemyGuid) == "string") -- sanity check
                -- local enemyFlags = assert(worldState:get(guid, W.Bitset))
                local isBoss = ftest(enemyGuid, Id.EnemyF.IS_BOSS)
                local isSeekActivated = ftest(enemyGuid, Id.EnemyF.SEEK_ACTIVATED)
                local enemyTemplate = assert(S.Enemy[refId].meshTemplate)
                local speed = log:assert(S.Enemy[refId].speed, "S.Enemy has no speed for: '%*'", refId)
                local newPos = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + dt * speed)
                local distToTarget
                local playerId
                local playerState
                local playersInSession = {}

                local players = game.Players:GetPlayers()
                for _, player in ipairs(players) do
                    local weaponId = worldState:get(player.UserId, W.WeaponId)
                    if weaponId ~= Id.Weapon._NONE then
                        table.insert(playersInSession, player)
                    else
                        -- player is not in session, remove this enemy's lock on him if any
                        playerId = player.UserId :: int
                        if worldState:get(enemyGuid, W.PlayerId) == playerId then
                            worldState:set(enemyGuid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                        end
                    end
                end

                -- handle enemy movement
                if isSeekActivated then
                    if #playersInSession > 0 then
                        local player, playerRoot
                        if (not worldState:get(enemyGuid, W.PlayerId)) or worldState:get(enemyGuid, W.PlayerId) == SharedConfig.DEFAULT_PLAYER_ID then
                            -- select a player that is close enough to the enemy
                            player, playerRoot, distToTarget = selectPlayerToLockOn(worldState, playersInSession, currentPos, enemyGuid, refId)
                            if player then
                                -- a player that is close enough is selected, set lock to target
                                playerId = player.UserId :: int
                                worldState:set(enemyGuid, W.PlayerId, playerId)
                            end
                        else
                            -- enemy is already locked on target
                            playerId = worldState:get(enemyGuid, W.PlayerId)
                            player = game.Players:GetPlayerByUserId(playerId)
                            playerState = get_state(worldState:get(enemyGuid, W.PlayerId))
                            if playerState then
                                -- if player that enemy is locked on is not in session, remove lock
                                local isPlayerInSession = playerState:test_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, Id.PlayerF.READY)
                                local playerTTL = worldState:get(enemyGuid, W.TTL)
                                if playerTTL < roflake.time() or not isPlayerInSession then
                                    worldState:set(enemyGuid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                    continue
                                end
                                -- all check are done, assign player, playerRoot and distTotarget
                                playerRoot = playerState.root :: BasePart
                                if not playerRoot then
                                    log:error("No player root found for player: '%*'", worldState:get(enemyGuid, W.PlayerId))
                                    return
                                end
                                local toTarget = currentPos - playerRoot.Position
                                distToTarget = toTarget.Magnitude
                            else
                                log:error("No player state found for player: '%*'", worldState:get(enemyGuid, W.PlayerId))
                                return
                            end
                        end

                        if player and playerRoot and distToTarget then
                            local critDist = 1
                            playerId = player.UserId :: int
                            playerState = get_state(playerId)
                            if isBoss then
                                -- bosses
                                newPos = getEnemyTargetPos(playerRoot, critDist, currentPos, speed, dt)
                            else
                                -- other enemies
                                if currentPos.Z - 5 > playerRoot.Position.Z then -- enemy got behind the player, cancel seeking
                                    worldfset(enemyGuid, Id.EnemyF.SEEK_ACTIVATED, false)
                                    worldState:set(enemyGuid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                elseif currentPos.Z > playerRoot.Position.Z - critDist then
                                    -- enemy is pretty close to player, cancel seeking
                                    worldfset(enemyGuid, Id.EnemyF.SEEK_ACTIVATED, false)
                                    worldState:set(enemyGuid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                else
                                    newPos = getEnemyTargetPos(playerRoot, critDist, currentPos, speed, dt)
                                end
                            end
                        else
                            -- no player is close enough, remove lock to target if any
                            worldState:set(enemyGuid, W.PlayerId, SharedConfig.DEFAULT_PLAYER_ID)
                        end
                    end
                end

                -- check proximity to players and do the logic
                -- TODO: collisions with clones
                if #playersInSession > 0 then
                    for _, player in ipairs(playersInSession) do
                        local thisPlayerState = get_state(player.UserId)
                        if thisPlayerState then
                            local root = thisPlayerState.root :: BasePart
                            local proximity = currentPos - root.Position
                            proximity = Vector3.new(proximity.X, 0, proximity.Z).Magnitude -- ignore Y axis
                            local thickness = enemyTemplate.Size.Z / 2

                            -- TODO: change speed for some enemies when a certain proximity is reached. Including bosses.
                            if proximity < thickness then
                                -- enemy is critically close to player, check for shield damage
                                local isShieldDmg, shieldDamage = getShieldDamage(thisPlayerState)
                                if isShieldDmg then
                                    Signal.Fire(Id.S2S.SHIELD_DAMAGE_SERVER, thisPlayerState.player_id, enemyGuid :: str, shieldDamage)
                                end
                                -- if there is still an enemy afterwards, apply damage to the player, then (if not boss) die
                                if worldState:has(enemyGuid) then
                                    local enemyDamage = S.Enemy[refId].damage
                                    if not isBoss then
                                        thisPlayerState:DeductHp(enemyDamage - shieldDamage)
                                        -- TODO: effects
                                        m.DestroyEnemy(enemyGuid)
                                    else
                                        local tte = worldState:get(thisPlayerState.player_id, W.TTE)
                                        if tte < 0 then
                                            thisPlayerState:DeductHp(enemyDamage - shieldDamage)
                                            local throttleDur = 1
                                            if S.Enemy[refId].hitThrottleDuration then
                                                throttleDur = assert(S.Enemy[refId].hitThrottleDuration)
                                            end
                                            worldState:set(thisPlayerState.player_id, W.TTE, throttleDur)
                                        end
                                    end
                                end
                            elseif isBoss then
                                -- check if it's time for boss to perform special attack
                                Enemies.DoBossSpecial(worldState, thisPlayerState, refId, enemyGuid, currentPos, root, proximity, dt)
                            end
                        end
                    end
                end

                if worldState:has(enemyGuid) then
                    -- update enemy's position
                    worldState:set(enemyGuid, W.Position, newPos)

                    if DRIVING_BOX_BACK_PART.Position.Z <= currentPos.Z then
                        -- destroy enemy if it collided with the driving box's rear
                        if refId ~= Id.Enemy.OCTOBOSS then -- boss is an exception
                            m.DestroyEnemy(enemyGuid)
                        end
                    elseif DRIVING_BOX_FRONT.Position.Z <= currentPos.Z then
                        -- activate seek mode on collision with the driver box's front
                        worldfset(enemyGuid, Id.EnemyF.SEEK_ACTIVATED, true)
                    end
                end
            end
        end

        -- check clones collisions
        local explosionHitRegistered = false
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
                    local boosterHP = worldState:get(booster.Name, W.HP)
                    local boosterSizeZ = boosterInstance.Size.Z
                    local boosterSizeX = boosterInstance.Size.X
                    local distZ = math.abs(cloneCFrame.Position.Z - boosterInstance.Position.Z)
                    local distX = math.abs(cloneCFrame.Position.X - boosterInstance.Position.X)
                    if distZ < boosterSizeZ / 2 and distX < boosterSizeX / 2 then
                        WorldService.DamageClone(cloneGuid :: str, boosterHP)
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
                        if (cloneCFrame.Position - objectPos).Magnitude < 2 then
                            local damage = S.Obstacle[refId].damage
                            WorldService.DamageClone(cloneGuid :: str, damage)
                            isCollided = true
                            break
                        end
                    elseif Id.kind(refId) == Id.Kind.Bomb then
                        local ownerGuid = worldState:get(objectGuid, W.OwnerGuid)
                        if not ownerGuid then
                            log:error("no ownerGuid found for bomb: '%*'", objectGuid)
                            continue
                        end
                        local explosionSize = assert(S.Bomb[refId].explosionSize)
                        if (cloneCFrame.Position - objectPos).Magnitude < explosionSize.X then
                            local tte = worldState:get(cloneGuid, W.TTE)
                            if tte <= 0 and not explosionHitRegistered then
                                playerState:NotifyClient(Id.S2C.BOMB_HIT, objectGuid, objectPos)
                            end
                            local bombDamage = S.Bomb[refId].damage
                            WorldService.DamageClone(cloneGuid :: str, bombDamage)
                            explosionHitRegistered = true
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

        -- handle world ttl
        for uid, ttl in worldState:select(W.TTL) do
            if roflake.time() > ttl then
                if worldState:get(uid, W.WeaponId) and worldState:get(uid, W.PlayerId) then
                    -- delete bullet entity
                    WorldService.RemoveEntity(uid)
                end
            end
        end

        -- handle world tte
        for uid, tte in worldState:select(W.TTE) do
            local newTTE = tte - dt
            worldState:set(uid, W.TTE, newTTE)
        end
    end
end

m.DestroyEnemy = function(guid, playerId: num?)
    local isBoss = ftest(guid, Id.EnemyF.IS_BOSS)
    if WorldService.world:has(guid) then
        WorldService.RemoveEntity(guid)
    end
    assert(typeof(guid) == "string") -- sanity check
    -- if is boss, delete poison belt
    if isBoss then
        local poisonBeltInstance = assert(GROUND_UNITS[FIELD_NAMES.MIDDLE].unit):FindFirstChild(SharedConfig.POISON_BELT_NAME_SERVER) :: BasePart
        if poisonBeltInstance then
            poisonBeltInstance:Destroy()
        end
    end
    workerMaid[guid] = nil
end

m.StartDamageThrottleSupervisor = function(get_state: (player_id: int) -> PSS.PlayerState?): supervisor.supervisor
    local throttleSupervisor = supervisor.create()
    throttleSupervisor:start(function()
        -- if boss fight is on, check for poison belt overlap
        if not WorldService.world:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value) then
            return
        end
        for _, player in game.Players:GetPlayers() do
            local player_state = get_state(player.UserId)
            if not player_state then
                continue
            end
            local playerRootPart = player_state.root
            local parts = workspace:GetPartBoundsInBox(playerRootPart.CFrame, playerRootPart.Size)
            local isOverlapping = false
            for _, part in ipairs(parts) do
                if part.Parent.Name == SharedConfig.POISON_BELT_NAME_SERVER then
                    isOverlapping = true
                    break
                end
            end
            local poisonBelt = assert(GROUND_UNITS[FIELD_NAMES.MIDDLE].unit):FindFirstChild(SharedConfig.POISON_BELT_NAME_SERVER) :: BasePart
            local poisonBeltPos = poisonBelt.Position
            local playerPos = playerRootPart.Position
            local tolerance = 5
            if
                math.abs(playerPos.Z - poisonBeltPos.Z) > SharedConfig.POISON_BELT_SIZE_1 / 2 + tolerance
                or math.abs(playerPos.X - poisonBeltPos.X) > SharedConfig.POISON_BELT_SIZE_1 / 2 + tolerance
            then
                isOverlapping = true
            end
            if isOverlapping then
                player_state:DeductHp(SharedConfig.POISON_BELT_DAMAGE, Id.WorldSpecs.BOSS_FIGHT_ON)
            end
        end
    end, 0.5) -- 10 times per second
    return throttleSupervisor
end

m.UnconstrainPlayer = function(player_state: PSS.PlayerState)
    local algnConstraint = player_state.character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
    if algnConstraint then
        algnConstraint:Destroy()
    end
    player_state.humanoid.WalkSpeed = SharedConfig.PLAYER_DEFAULT_WALK_SPEED
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
    BoosterServer.GiveBoosterBonus(playerState, boost_ref_id, boost_content_id, value)
    -- if boost_ref_id == Id.Boost.ADD_CLONE then
    --     for i = 1, value do
    --         local playerId = playerState.player_id
    --         local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, playerId)
    --     end
    -- elseif boost_ref_id == Id.Boost.CHANGE_WEAPON then
    --     Signal.Fire(Id.S2S.CHANGE_WEAPON, playerState.player_id, boost_content_id)
    -- elseif boost_ref_id == Id.Boost.FIRST_AID_KIT then
    --     local currentHandicap = WorldService.world:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
    --     local old_hp, new_hp = playerState:AddHp(value, currentHandicap)
    --     local hp_added = new_hp - old_hp
    --     playerState:NotifyClient(Id.S2C.BOOSTER_DESTROYED, boost_ref_id, hp_added, boost_content_id)
    -- end
end

function m.SpawnPlayer(player_state: PSS.PlayerState, players_in_session: int)
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
    local halfGround = last_spawned_ground_unit.Size.X / 2
    if math.abs(x_pos - last_spawned_ground_unit.Position.X) >= halfGround then -- sanity check
        x_pos = last_spawned_ground_unit.Position.X
        log:error("player spawned outside the field")
    end
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

function m.ApplyExplosionKnockback(player_state: PSS.PlayerState, explosionPos: Vector3, maxForce: num?, maxRange: num?)
    local playerRoot = player_state.root :: BasePart
    if not playerRoot then
        log:error("No player root found for knockback: '%*'", player_state.player_id)
        return
    end

    -- Default values
    local force_limit = maxForce or 100 -- Maximum knockback force
    local range_limit = maxRange or 50 -- Maximum range for knockback effect

    local playerPos = playerRoot.Position
    local toPlayer = playerPos - explosionPos
    local distance = toPlayer.Magnitude

    -- Calculate knockback direction (only X and Z, no vertical launch)
    local direction = Vector3.new(toPlayer.X, 0, toPlayer.Z).Unit

    -- Apply distance falloff (inverse square with minimum)
    local falloff = math.max(0.1, 1 - (distance / range_limit) ^ 2)
    local force = force_limit * falloff

    -- Apply slight upward component for more realistic effect
    local knockbackVector = direction * force + Vector3.new(0, force * 0.3, 0)

    -- Apply the knockback
    playerRoot.AssemblyLinearVelocity = playerRoot.AssemblyLinearVelocity + knockbackVector
end

print("[Game Module -- started]")

return m
