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
local PlayerService = game:GetService("Players")
local SharedUtil = require(shared.util)
local rand = require(shared.rand)

local CLONES = {}

local m = {} :: {
    get_state: (int) -> PSS.PlayerState?,
    StartMainLoopPlayer: (PSS.PlayerState) -> (num) -> (),
    Init: (state: state.Main, (int) -> PSS.PlayerState?) -> (),
    CreatePlayerHpGui: (PSS.PlayerState) -> (),
    DestroyEnemy: (enemy_guid: str) -> (),
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
    { unit = GROUND_UNIT_FOLDER.GroundUnit_Start, zOffset = 0},
    {                                             zOffset = -GROUND_INIT_LENGTH },
    {                                             zOffset = GROUND_INIT_LENGTH * -2 },
}
local startingPos = GROUND_UNITS[3].unit.Position

local DRIVING_BOX_TEMPLATE = assert(ReplicatedStorage.DrivingBox)
local DRIVING_BOX_INSTANCE = DRIVING_BOX_TEMPLATE:Clone()
local DRIVING_BOX_FRONT = assert(DRIVING_BOX_INSTANCE.PartFront)
DRIVING_BOX_INSTANCE.Parent = game.Workspace
local DRIVING_BOX_ATT = Instance.new("Attachment") :: Attachment
DRIVING_BOX_ATT.Parent = DRIVING_BOX_FRONT

local function deleteGroundUnit(groundUnit: Part, index: int)
    local children = groundUnit:GetChildren()
    for _, v in ipairs(children) do
        if v:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            WorldService.RemoveEntity(v.Name)
        end
    end
    groundUnit:Destroy()
end

local function setBooster(instance: BasePart, get_state: (int) -> PSS.PlayerState?)
    -- TODO: actual range of selection of every type
    local refID = math.random(Id.Boost.ADD_CLONE, Id.Boost.CHANGE_WEAPON)
    local valueRange = S.Boost[refID].valueRange
    local value = math.random(valueRange[1], valueRange[#valueRange])
    local hpRange = S.Boost[refID].hpRange
    local hp = math.random(hpRange[1], hpRange[#hpRange])

    local boostContentId = false :: id | bool
    local contentsBillboardInstance = BOOSTER_CONTENTS_BILLBOARD_TEMPLATE:Clone()
    local boosterPos = instance.Position
    local billboardPos = contentsBillboardInstance.Position
    contentsBillboardInstance.CFrame = CFrame.new(boosterPos.X, billboardPos.Y, boosterPos.Z)
    contentsBillboardInstance.Parent = instance
    local contentsTextbox = contentsBillboardInstance.BoosterContentsGui.TextLabel
    local txt = ""
    local col = instance.Color
    if refID == Id.Boost.ADD_CLONE then
        txt = string.format("+ %d clones", value)
        col = Color3.fromRGB(0, 255, 0)
    elseif refID == Id.Boost.CHANGE_WEAPON then
        local contents = assert(S.Boost[refID].contentsRange)
        boostContentId = math.random(contents[1], contents[#contents])
        txt = string.format("%s", S.Weapon[boostContentId :: id].name)
        col = Color3.fromRGB(169, 132, 255)
        if boostContentId == Id.Weapon.SHOTGUN then
            col = Color3.fromRGB(177, 94, 11)
        end
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
    WorldService.AddBooster(instance, refID, value, hp, boostContentId)
end

local function spawnGroundUnit(worldState: state.Main, groundUnit: Part, index: int, refPos: Vector3)
    GROUND_UNITS[index].unit = groundUnit
    local unitPos = CFrame.new(refPos.X, refPos.Y, refPos.Z + GROUND_UNITS[index].zOffset)
    groundUnit.CFrame = unitPos

    local enemyFolder = groundUnit:FindFirstChild("Enemies")
    if not enemyFolder then
        enemyFolder = Instance.new("Folder")
        assert(enemyFolder)
        enemyFolder.Parent = groundUnit
        enemyFolder.Name = "Enemies"
    end

    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    trigger.CFrame = CFrame.new(9, 20.5, unitPos.Z - 245)
    groundUnit.Parent = GROUND_UNIT_FOLDER
    groundUnit.AssemblyLinearVelocity = groundUnit.CFrame.LookVector * SharedConfig.MOVEMENT_LINEAR_VELOCITY
    for i = 1, 12 do --12 boosters
        local booster = BOOSTER_TEMPLATE:Clone()
        booster.CFrame = CFrame.new(BOOSTER_OFFSET_X - BOOSTER_GAP * (i - 1), BOOSTER_OFFSET_Y, unitPos.Z + BOOSTER_OFFSET_Z)
        booster.Parent = groundUnit
        setBooster(booster, m.get_state)
    end
end

local function subscribeEnemyToTouch(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?, enemyGiud: str, enemyId, enemyInstance)
    workerMaid[enemyGiud] = enemyInstance.Touched:Connect(function(triggerer)
        if triggerer == DRIVING_BOX_FRONT then
            local flags = worldState:get(enemyGiud, W.Bitset)
            if flags and not Id.flag_test(flags, Id.EnemyF.SEEK_ACTIVATED) then
                worldState:set(enemyGiud, W.Bitset, Id.flag_set(flags, Id.EnemyF.SEEK_ACTIVATED, true))
            end
        elseif triggerer == DRIVING_BOX_INSTANCE then
            m.DestroyEnemy(enemyGiud)
        end
        -- NOTE: bullet collision are handled on the client
    end)
end

local function subscribeTrigger(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?, index, groundUnit)
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    workerMaid.trigger = trigger.Touched:Connect(function(triggerer)
        if triggerer == DRIVING_BOX_FRONT then
            subscribeTrigger(worldState, get_state, FIELD_NAMES.FOURTH, GROUND_UNITS[FIELD_NAMES.FOURTH].unit)
            trigger:Destroy()
            deleteGroundUnit(GROUND_UNITS[FIELD_NAMES.FIRST].unit, FIELD_NAMES.FIRST)
            -- shift all other units in the data table accordingly
            GROUND_UNITS[FIELD_NAMES.FIRST].unit = GROUND_UNITS[FIELD_NAMES.SECOND].unit
            GROUND_UNITS[FIELD_NAMES.SECOND].unit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit
            GROUND_UNITS[FIELD_NAMES.MIDDLE].unit = GROUND_UNITS[FIELD_NAMES.FOURTH].unit
            GROUND_UNITS[FIELD_NAMES.FOURTH].unit = GROUND_UNITS[FIELD_NAMES.FIFTH].unit
            local refPos = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.Position
            spawnGroundUnit(worldState, GROUND_UNIT_TEMPLATE:Clone(), FIELD_NAMES.FIFTH, refPos)
            -- TODO: take enemy numbers from main difficulty data table
            local enemies = Enemies.AddEnemies(worldState, GROUND_UNITS[FIELD_NAMES.MIDDLE].unit, true, 20)
            for _, enemyGuid in ipairs(enemies) do
                assert(type(enemyGuid) == "string") -- sanity check
                local enemyId = worldState:get(enemyGuid, W.RefId)
                local enemyInstance = worldState:get(enemyGuid, W.ServerInstance)
                subscribeEnemyToTouch(worldState, get_state, enemyGuid, enemyId, enemyInstance)
            end

            TaskPool.spawn(function()
                task.wait(SharedConfig.ENEMY_WAVE_DELAY)
                -- TODO: take enemy numbers from main difficulty data table
                local enemies = Enemies.AddEnemies(worldState, GROUND_UNITS[FIELD_NAMES.MIDDLE].unit, false, 20)
                for _, enemyGuid in ipairs(enemies) do
                    assert(type(enemyGuid) == "string") -- sanity check
                    local enemyId = worldState:get(enemyGuid, W.RefId)
                    local enemyInstance = worldState:get(enemyGuid, W.ServerInstance)
                    subscribeEnemyToTouch(worldState, get_state, enemyGuid, enemyId, enemyInstance)
                end
            end)
        end
    end)
end

local function selectPlayer(playersInSession: { Player }, enemyInstance: BasePart): (Player?, BasePart?, num?)
    local totalPlayers = #playersInSession
    local ind = math.random(1, totalPlayers)
    local player = playersInSession[ind] :: Player
    local char = player.Character :: Model
    local playerRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
    local toTarget = enemyInstance.Position - playerRoot.Position
    local distToTarget = toTarget.Magnitude
    local closenessByX = math.abs(enemyInstance.Position.X - playerRoot.Position.X)
    if distToTarget >= 150 or closenessByX > SharedConfig.ENEMY_SIGHT_RADIUS then
        return nil, nil, nil
    end
    return player, playerRoot, distToTarget
end

function m.Init(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    m.get_state = get_state
    -- init first batch of ground units and fill in the data table
    local firstUnit = GROUND_UNIT_TEMPLATE:Clone()
    local secondUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fourthUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fifthUnit = GROUND_UNIT_TEMPLATE:Clone()

    -- init first ground unit
    subscribeTrigger(worldState, get_state, FIELD_NAMES.MIDDLE, GROUND_UNITS[FIELD_NAMES.MIDDLE].unit)
    local boosters = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit:GetChildren()
    for i, booster in ipairs(boosters) do
        if booster:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            setBooster(booster, get_state)
        end
    end

    -- spawn the rest of the first batch of ground units
    spawnGroundUnit(worldState, firstUnit, FIELD_NAMES.FIRST, startingPos)
    spawnGroundUnit(worldState, secondUnit, FIELD_NAMES.SECOND, startingPos)
    spawnGroundUnit(worldState, fourthUnit, FIELD_NAMES.FOURTH, startingPos)
    spawnGroundUnit(worldState, fifthUnit, FIELD_NAMES.FIFTH, startingPos)
end

function m.StartMainLoopWorld(worldState: state.Main, get_state: (player_id: int) -> PSS.PlayerState?)
    local oldPos = DRIVING_BOX_INSTANCE.Position
    GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.AssemblyLinearVelocity = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.CFrame.LookVector * 30
    return function(dt)
        -- driving box movement
        DRIVING_BOX_INSTANCE.CFrame = CFrame.new(oldPos.X, oldPos.Y, oldPos.Z - 0.5)
        oldPos = DRIVING_BOX_INSTANCE.Position

        -- move enemies
        local enemies = {}
        local enemyTargets = {}
        local currentGroundUnits = GROUND_UNIT_FOLDER:GetChildren()
        for _, unit in ipairs(currentGroundUnits) do
            local enemyFolder = unit:FindFirstChild("Enemies")
            if enemyFolder then
                local enemyInstances = enemyFolder:GetChildren()
                if #enemyInstances > 0 then
                    for _, enemyInstance in ipairs(enemyInstances) do
                        local currentPos: Vector3 = enemyInstance.Position
                        table.insert(enemies, enemyInstance)
                        -- local lookAt = DRIVING_BOX_INSTANCE.Position
                        local lookAt = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + 5)
                        local flags = worldState:get(enemyInstance.Name, W.Bitset)
                        -- local playerTargetedId = worldState:get(enemyInstance.Name, W.PLayerId)

                        local enemyId = worldState:get(enemyInstance.Name, W.RefId)
                        local speed = log:assert(S.Enemy[enemyId].speed, "S.Enemy has no speed for: '%*'", enemyId)
                        local newPos = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + dt * speed)

                        if flags and Id.flag_test(flags, Id.EnemyF.SEEK_ACTIVATED) then
                            local players = game.Players:GetPlayers()
                            local playersInSession = {}
                            for _, player in ipairs(players) do
                                local weaponId = worldState:get(player.UserId, W.WeaponId)
                                if weaponId ~= Id.Weapon._NONE then
                                    table.insert(playersInSession, player)
                                else
                                    -- player is not in session, remove this enemy's lock on him if any
                                    local playerId = player.UserId :: int
                                    if worldState:get(enemyInstance.Name, W.PLayerId) == playerId then
                                        worldState:set(enemyInstance.Name, W.PLayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                    end
                                end
                            end
                            if #playersInSession > 0 then
                                local player, playerRoot, distToTarget
                                if
                                    (not worldState:get(enemyInstance.Name, W.PLayerId))
                                    or worldState:get(enemyInstance.Name, W.PLayerId) == SharedConfig.DEFAULT_PLAYER_ID
                                then
                                    -- select a player that is close enough to the enemy
                                    player, playerRoot, distToTarget = selectPlayer(playersInSession, enemyInstance)
                                    if player then
                                        -- a player that is close enough is selected, set lock to target
                                        local playerId = player.UserId :: int
                                        worldState:set(enemyInstance.Name, W.PLayerId, playerId)
                                    end
                                else
                                    -- enemy is already locked on target, assign player, playerRoot and distTotarget
                                    local playerId = worldState:get(enemyInstance.Name, W.PLayerId)
                                    player = game.Players:GetPlayerByUserId(playerId)
                                    local playerState = get_state(worldState:get(enemyInstance.Name, W.PLayerId))
                                    if playerState then
                                        playerRoot = playerState.root :: BasePart
                                        if not playerRoot then
                                            log:error("No player root found for player: '%*'", worldState:get(enemyInstance.Name, W.PLayerId))
                                            return
                                        end
                                        local toTarget = enemyInstance.Position - playerRoot.Position
                                        distToTarget = toTarget.Magnitude
                                    else
                                        log:error("No player state found for player: '%*'", worldState:get(enemyInstance.Name, W.PLayerId))
                                        return
                                    end
                                end

                                if player and playerRoot and distToTarget then
                                    local time_to_target = distToTarget / speed
                                    local playerId = player.UserId :: int
                                    local playerState = get_state(playerId)

                                    if currentPos.Z - 5 > playerRoot.Position.Z then
                                        -- enemy got behind the player, cancel seeking
                                        worldState:set(enemyInstance.Name, W.Bitset, Id.flag_set(flags, Id.EnemyF.SEEK_ACTIVATED, false))
                                        -- if currentPos.Z > playerRoot.Position.Z - 40 then
                                        --     local pos = Vector3.new(playerRoot.Position.X, currentPos.Y, currentPos.Z + dt * speed)
                                        -- TODO: lerp to the new position so that the locked enemy X == players X

                                        -- local target = playerRoot.Position + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                        -- lookAt = playerRoot.Position
                                        -- newPos = currentPos:Lerp(target, dt * speed / distToTarget) -- Move towards the predicted position of the player
                                    elseif distToTarget < 10 then
                                        -- enemy is close to player, harm them, then die
                                        local enemyDamage = S.Enemy[enemyId].damage
                                        if playerState then
                                            local playerHP = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.Value)
                                            local newHP = playerHP - enemyDamage
                                            if newHP <= 0 then
                                                Signal.Fire(Id.S2S.PLAYER_DIED, playerId)
                                            else
                                                playerState:DeductHp(enemyDamage)
                                                playerState:NotifyClient(Id.S2C.PLAYER_DAMAGED, newHP)
                                            end
                                            -- TODO: effects
                                            m.DestroyEnemy(enemyInstance.Name)
                                        end
                                    else
                                        ---[[ old code
                                        -- predict player's position, binomial distribution add some randomness
                                        local playerPos = playerRoot.Position
                                        local target = Vector3.new(playerPos.X, playerPos.Y, playerPos.Z) + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                        -- local target = playerPos + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                        lookAt = playerRoot.Position
                                        newPos = currentPos:Lerp(target, dt * speed / distToTarget) -- Move towards the predicted position slightly ahead of the player
                                        --]]

                                        --[[ My crap
                                        -- TODO: tune this, this is the speed at which the enemy will rotate to face the player
                                        local K = 0.05 -- in radians/sec
                                        -- predict player's position, binomial distribution add some randomness
                                        local playerPos = playerRoot.Position
                                        local target = playerPos + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                        -- Calculate desired look direction
                                        local desiredLook = (target - currentPos).Unit
                                        local currentLook: Vector3 = enemyInstance.CFrame.LookVector
                                        local angle = currentLook:Angle(desiredLook, Vector3.UP)

                                        -- Limit rotation angle
                                        angle = math.sign(angle) * math.min(math.abs(angle), K * dt) 
                                        
                                        local rotation = CFrame.fromAxisAngle(Vector3.UP, angle)
                                        lookAt = rotation.LookVector
                                        newPos = currentPos + lookAt * dt * speed
                                        --]]

                                        --[[ Cloude version
                                        -- TODO: tune this, this is the speed at which the enemy will rotate to face the player
                                        local K = 0.05 --2.5 -- radians/sec
                                        local playerPos = playerRoot.Position
                                        local target = playerPos + (rand.binomial() * time_to_target) * playerRoot.AssemblyLinearVelocity
                                        local desiredLook = (target - currentPos).Unit
                                        local currentLook = enemyInstance.CFrame.LookVector
                                        local angle = math.acos(currentLook:Dot(desiredLook))
                                        -- Determine rotation direction using cross product
                                        local axis = currentLook:Cross(desiredLook)
                                        local rotationDirection = axis.Y > 0 and 1 or -1
                                        angle = rotationDirection * math.min(math.abs(angle), K * dt)
                                        local rotation = CFrame.fromAxisAngle(Vector3.yAxis, angle)
                                        lookAt = currentPos + rotation.LookVector
                                        newPos = currentPos:Lerp(currentPos - rotation.LookVector * speed, dt)
                                        --]]

                                    end
                                else
                                    -- no player is close enough, remove lock to target if any
                                    worldState:set(enemyInstance.Name, W.PLayerId, SharedConfig.DEFAULT_PLAYER_ID)
                                end
                            end
                        end
                        if worldState:has(enemyInstance.Name) then
                            worldState:set(enemyInstance.Name, W.Position, newPos)
                        end
                        lookAt = Vector3.new(lookAt.X, newPos.Y, lookAt.Z) -- lock Y axis
                        local newCframe = CFrame.new(newPos, lookAt) * CFrame.Angles(0, math.pi, 0)
                        table.insert(enemyTargets, newCframe)
                    end
                end
            end
        end
        if #enemies > 0 then
            workspace:BulkMoveTo(enemies, enemyTargets, Enum.BulkMoveMode.FireCFrameChanged)
        end
    end
end

function m.StartMainLoopPlayer(player_state: PSS.PlayerState): (num) -> ()
    return function(dt)
        -- weapon cooldown
        local flags = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
        if Id.flag_test(flags, Id.PlayerF.READY) then
            local shot_ttl = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.TTL) :: num
            shot_ttl -= dt
            player_state.state:set(Id.PlayerStats.GAME_SESSION, C.TTL, math.max(shot_ttl, 0))
        end
    end
end

m.DestroyEnemy = function(guid)
    -- TODO: effects
    WorldService.RemoveEntity(guid)
    assert(typeof(guid) == "string") -- sanity check
    workerMaid[guid] = nil
end

function m.HandleBoosterDeath(playerState: PSS.PlayerState, booster_guid: str, boost_ref_id: id, value: num, boost_content_id: id)
    if not boost_ref_id then
        log:error("no boost_id", debug.traceback)
    end
    -- unsubscribe booster
    workerMaid[booster_guid] = nil
    -- TODO: others
    if boost_ref_id == Id.Boost.ADD_CLONE then
        for i = 1, value do
            local playerId = playerState.player_id
            local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, playerId)
        end
    elseif boost_ref_id == Id.Boost.CHANGE_WEAPON then
        Signal.Fire(Id.S2S.CHANGE_WEAPON, playerState.player_id, boost_content_id)
        -- TODO:
    end
end

function m.SpawnPlayer(player_state: PSS.PlayerState, players_already_in_session: int)
    -- NOTE: players_already_in_session includes this player_state.player

    -- define spawning position
    local flags = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.Bitset, Id.flag_set(flags, Id.PlayerF.READY, true))

    local driver_pos = DRIVING_BOX_INSTANCE.Position
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
    if players_already_in_session > #boosters then
        index = math.random(1, #boosters)
    elseif players_already_in_session % 2 == 0 then
        -- evens
        local starting_point = #boosters / 2 + 1
        index = starting_point - players_already_in_session / 2
    else
        -- odds
        local starting_point = #boosters / 2
        index = starting_point + (players_already_in_session + 1) / 2
    end
    x_pos = boosters[index].Position.X
    local y_pos = player_state.root.Position.Y
    local z_pos = driver_pos.Z - 50
    if players_already_in_session > 1 then
        local all_players = game.Players:GetPlayers()
        local isInSession = false
        for _, player in all_players do
            local weapon_id = WorldService.world:get(player.UserId, W.WeaponId)
            isInSession = weapon_id ~= Id.Weapon._NONE
            if isInSession then
                z_pos = player.Character.HumanoidRootPart.Position.Z
            end
        end
        assert(isInSession) -- sanity check
    end

    local target_c_frame = CFrame.new(x_pos, y_pos, z_pos)
    player_state.root.CFrame = target_c_frame

    -- set player alignment
    local playerAtt = Instance.new("Attachment") :: Attachment
    local playerCharacter = player_state.character :: Model
    local playerRootPart = player_state.root :: Part
    playerAtt.CFrame = playerRootPart.CFrame
    playerAtt.Parent = playerRootPart
    local playerAlignConst = Instance.new("AlignOrientation")
    playerAlignConst.Name = SharedConfig.PLAYER_ALIGN_CONSTR_NAME
    playerAlignConst.Parent = playerCharacter
    playerAlignConst.Attachment0 = playerAtt
    playerAlignConst.Attachment1 = DRIVING_BOX_ATT
end

print("[Game Module -- started]")
return m
