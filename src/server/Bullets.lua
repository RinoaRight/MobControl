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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ACTIVE_BULLETS_REPOSITORY = workspace:WaitForChild("Bullets")
Misc.AddPlayerCharToRaycastFilter(ACTIVE_BULLETS_REPOSITORY)
local INACTIVE_BULLETS_REPOSITORY = ReplicatedStorage:WaitForChild("Bullets")
local activeBulletsDataTable = {} :: { table }
local NIL_TABLE = table.freeze { "NIL" }

local function spawnBullet(player, rootPart: BasePart, weapon_id: id)
    -- TODO: spawn bullet farther from the player root to compensate server lag
    local bullet

    if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
        bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
    else
        bullet = Instance.new("Part")
        bullet.Name = SharedConfig.BULLET_NAME
    end

    -- set bullet properties
    bullet.CollisionGroup = "Bullet"
    bullet.CanCollide = false
    bullet.Anchored = true
    bullet:SetAttribute(SharedConfig.BULLET_ATTRIBUTE_NAME, player.UserId)
    local s = 1
    if S.Weapon[weapon_id].bulletSize then
        s = S.Weapon[weapon_id].bulletSize
    end
    bullet.Size = Vector3.new(s, s, s)

    -- set bullet's position
    local pos = rootPart.Position + rootPart.CFrame.LookVector * SharedConfig.BULLET_START_OFFSET_MULT
    bullet.Parent = ACTIVE_BULLETS_REPOSITORY
    local speed = S.Weapon[weapon_id].baseSpeed + rootPart.AssemblyLinearVelocity.Magnitude
    local range = SharedConfig.BULLET_BASE_DISTANCE
    if S.Weapon[weapon_id].range then
        range = S.Weapon[weapon_id].range
    end
    local bulletTTL = roflake.time() + range / speed

    bullet.Position = pos

    table.insert(activeBulletsDataTable, {
        bullet = bullet,
        speed = speed,
        ttl = bulletTTL,
        ownerId = player.UserId,
        weapon_id = weapon_id,
        rotation = CFrame.Angles(0, 0, 0),
    })

    local indexInTable = #activeBulletsDataTable

    return pos, indexInTable
end

local function setShotgunBulletsToDataTable(player, playerRootPart, weapon_id)
    -- generate multiple bullets and set different rotation for each of them to the data table of active bullets
    local pos
    for i = 1, 5 do
        local bulletPos, indexInTable = spawnBullet(player, playerRootPart, weapon_id)
        local yRot = 0
        if i == 2 then
            yRot = 2
        elseif i == 3 then
            yRot = 4
        elseif i == 4 then
            yRot = -2
        elseif i == 5 then
            yRot = -4
        end
        pos = bulletPos -- they are overwriting each other, but it doesnt' matter cuz they are the same
        local rot = CFrame.Angles(0, math.rad(yRot), 0)
        activeBulletsDataTable[indexInTable].rotation = rot
    end
    return pos
end

local function onBoosterHit(playerState, current_weapon_id, booster)
    local dmg = S.Weapon[current_weapon_id].damage
    local booster_hp = WorldService.world:get(booster.Name, W.HP)
    local new_hp = booster_hp - dmg
    local boosterGui = booster:FindFirstChildWhichIsA("SurfaceGui")
    boosterGui.TextLabel.Text = NumFormat.format_damage(new_hp)

    local isBoosterDead = false
    if new_hp <= 0 then
        -- give boost to the player who killed the booster
        local boostRefId = WorldService.world:get(booster.Name, W.RefId)
        local boostContentId = WorldService.world:get(booster.Name, W.BoostContentId)
        local value = WorldService.world:get(booster.Name, W.Value)
        WorldService.world:delete(booster.Name)
        if playerState.state:has(booster.Name) then
            playerState.state:delete(booster.Name)
        end

        if not boostRefId then
            log:error("no boost_id", debug.traceback)
        end

        isBoosterDead = true

        -- TODO: others
        if boostRefId == Id.Boost.ADD_CLONE then
            for i = 1, value do
                local playerId = playerState.player_id
                local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, playerId)
            end
        elseif boostRefId == Id.Boost.CHANGE_WEAPON then
            Signal.Fire(Id.S2S.CHANGE_WEAPON, playerState.player_id, boostContentId)
            -- TODO:
        end
    else
        WorldService.world:set(booster.Name, W.HP, booster_hp - dmg)
    end

    return isBoosterDead
end

local function onEnemyHit(playerState, enemy, weaponId)
    local isEnemyDead = false

    local enemyGuid = enemy.Name
    local targetRefId = WorldService.world:get(enemyGuid, W.RefId)
    if Id.kind(targetRefId) ~= Id.Kind.Enemy then
        log:error("The target id is not of ENEMY kind")
        return isEnemyDead
    end
    if WorldService.world:has(enemyGuid) then
        local dmg = 0
        if S.Weapon[weaponId] and S.Weapon[weaponId].damage then
            dmg = S.Weapon[weaponId].damage
        end
        local enemyHP = WorldService.world:get(enemyGuid, W.HP)
        
        local newHP = enemyHP - dmg

        if enemyHP - dmg <= 0 then
            WorldService.RemoveEntity(enemyGuid)
            isEnemyDead = true
        else
            WorldService.world:set(enemyGuid, W.HP, newHP)
        end
    end
    return isEnemyDead
end

local function fireBullet(player, playerState)
    local player_char = player.Character
    local playerRootPart = assert(player_char.HumanoidRootPart) :: BasePart
    local weaponId = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.RefId)
    if not weaponId or weaponId == Id.Weapon._NONE then
        return
    end

    -- player's fire
    local pos
    if weaponId == Id.Weapon.SHOTGUN then
        pos = setShotgunBulletsToDataTable(player, playerRootPart, weaponId)
    else
        pos = spawnBullet(player, playerRootPart, weaponId)
    end

    -- TODO: clones are not firing, FIXIT
    -- clones' fire (is handled as an additional local player's fire)
    local clones_folder = player_char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clones_folder then
        for _, clone in ipairs(clones_folder:GetChildren()) do
            local rootPart = clone.HumanoidRootPart
            pos = spawnBullet(player, rootPart, Id.Weapon.BASIC)
            if weaponId == Id.Weapon.SHOTGUN then
                pos = setShotgunBulletsToDataTable(player, rootPart, weaponId)
            else
                pos = spawnBullet(player, rootPart, weaponId)
            end
        end
    end

    -- TODO: change sound for each type of weapon
    Misc.SoundLocalizedAudio(S.Sound[Id.Sound.FIRE_PISTOL_LOCALIZED], pos, 0)

    -- reset ttl
    local ttl
    if weaponId and weaponId ~= Id.Weapon._NONE then
        ttl = S.Weapon[weaponId].cooldown
    end
    playerState.state:set(Id.PlayerStats.GAME_SESSION, C.TTL, ttl)
end

local m = {}

m.HandleExistingBullets = function(get_state: (player_id: int) -> PSS.PlayerState?, dt)
    local targetDead

    local activeBullets = {}
    local bulletsTargets = {}
    local now = roflake.time()
    for i, bulletData in ipairs(activeBulletsDataTable) do
        -- check for collisions
        local bullet = bulletData.bullet :: Part
        local ownerId = bulletData.ownerId
        local ttl = bulletData.ttl
        local rot = bulletData.rotation
        local speed = bulletData.speed

        local player = game.Players:GetPlayerByUserId(ownerId)
        if not player then
            -- player logged off
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
            continue
        end

        local playerState = get_state(ownerId)
        if not playerState then
            continue
        end

        local isPlayerInSession = false
        if playerState.state:has(Id.PlayerStats.GAME_SESSION) then
            local flags = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
            if flags and Id.flag_test(flags, Id.PlayerF.READY) then
                isPlayerInSession = true
            end
        end

        local currentWeaponId = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.RefId)
        local target, _dist = Misc.IsBulletCollidableToHit(bullet.Position)

        local targetCframe = CFrame.new(bullet.Position + (bullet.CFrame.LookVector * speed * dt)) * rot
        local targetThickness
        local targetRefId
        local isTargetKillable
        if target and WorldService.world:has(target.Name) then
            targetRefId = WorldService.world:get(target.Name, W.RefId)
            if not targetRefId then
                log:error("no refId for the bullet target", targetRefId, target.ClassName)
                return targetDead
            end
            if Id.kind(targetRefId) == Id.Kind.Boost then
                targetThickness = SharedConfig.BOOSTER_DEPTH
                isTargetKillable = true
            elseif Id.kind(targetRefId) == Id.Kind.Enemy then
                targetThickness = SharedConfig.REGULAR_ENEMY_HITBOX_RADIUS
                isTargetKillable = true
            end
        end
        if target and isTargetKillable and (target.Position.Z + targetThickness + 1 >= bullet.Position.Z) then
            -- bullet collided with the target, delete it and signal to server
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
            local isTargetDead = false
            if Id.kind(targetRefId) == Id.Kind.Boost then
                isTargetDead = onBoosterHit(playerState, currentWeaponId, target)
            elseif Id.kind(targetRefId) == Id.Kind.Enemy then
                isTargetDead = onEnemyHit(playerState, target, currentWeaponId)
            end
            if isTargetDead and isPlayerInSession then
                -- player is still in session, register the collision
                targetDead = target
            end
        elseif now >= ttl then
            -- bullet timed-out, delete it
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        else
            table.insert(activeBullets, bullet)
            table.insert(bulletsTargets, targetCframe)
        end
    end

    -- remove all NIL_TABLEs from the table
    local activeBulletsDataTableTemp = table.clone(activeBulletsDataTable)
    table.clear(activeBulletsDataTable)
    for i, bulletData in ipairs(activeBulletsDataTableTemp) do
        if bulletData ~= NIL_TABLE then
            table.insert(activeBulletsDataTable, bulletData)
        end
    end

    workspace:BulkMoveTo(activeBullets, bulletsTargets, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire new bullets
    local players = game:GetService("Players"):GetPlayers()
    for _, player in ipairs(players) do
        local playerId = player.UserId
        local playerState = get_state(playerId) :: PSS.PlayerState
        if not playerState then
            log:error("No player state for player " .. playerId)
            continue
        end

        if playerState.state:has(Id.PlayerStats.GAME_SESSION) then
            local flags = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
            if flags and Id.flag_test(flags, Id.PlayerF.READY) then
                local weaponId = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.RefId)
                if not weaponId or weaponId == Id.Weapon._NONE then
                    log:error("No bullet can be fired for this weapon_id", weaponId)
                end
                local weapon_id = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.RefId)
                if weapon_id and weapon_id ~= Id.Weapon._NONE then
                    -- player is inside the game session, fire bullets
                    local shot_ttl = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.TTL)
                    if shot_ttl then
                        shot_ttl -= dt
                        if shot_ttl <= 0 then
                            fireBullet(player, playerState)
                        end
                    end
                end
            end
        end
    end

    return targetDead
end

return m
