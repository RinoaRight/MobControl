-- type str = string
-- type bool = boolean
-- type num = number
-- type integer = num
-- type uint = integer
-- type int = integer
-- type id = int
-- type u32 = uint
-- type i32 = int
-- type u8 = uint
-- type array<a> = { a }
-- type table = { [any]: any }
-- type map<k, v> = { [k]: v }
-- type fun = (...any) -> ...any
-- type guid = str
-- type uid = str | id
-- local _fmt = string.format

-- local shared = game.ReplicatedStorage.shared
-- local Id = require(shared.Id)
-- local Logger = require(shared.logger)
-- local log = Logger.create(script and script.Name or "Boosters"):set_prettifier(Id.pp):set_delimiter(" ")
-- local Signal = require(shared.signal)
-- local En = require(shared.enum)
-- local _iota = En.iota
-- local _flag = En.flag
-- local disposer = require(shared.disposer)
-- local state = require(shared.state)
-- local SharedConfig = require(shared.SharedConfig)
-- local C = SharedConfig.PlayerState.CId
-- local W = SharedConfig.World.CId
-- local SharedConfig = require(shared.SharedConfig)
-- local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
-- local workerMaid = disposer.new()
-- local LOCAL_PLAYER = game.Players.LocalPlayer
-- local PlayerService = game:GetService("Players")
-- local Misc = require(shared.Misc)
-- local S = require(shared.StaticData)
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
-- local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
-- local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
-- local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)


-- local function onEnemyRemoved( enemyGuid)
--     workerMaid[enemyGuid] = nil
-- end

-- local function onEnemyAdded(worldState, playerState: state.Replica, enemyGuid)
--     local instance = workspace:FindFirstChild(enemyGuid, true)
--     workerMaid[enemyGuid] = instance.Touched:Connect(function(triggerer)
--         print("LLLLLLL", triggerer.Name)

--         -- sanity-check if the enemy is still alive
--         if not worldState:has(enemyGuid) then
--             onEnemyRemoved(enemyGuid)
--             return
--         end

--         -- check if the triggerer is a bullet
--         if triggerer.Name ~= SharedConfig.BULLET_NAME then
--             print("LLLLLLL not a bullet", triggerer.Name)
--             return
--         end

--         -- check if the bullet belongs to the local player
--         local bulletOwnerId = triggerer.Name:GetAttribute(SharedConfig.BULLET_ATTRIBUTE_NAME)
--         if bulletOwnerId ~= LOCAL_PLAYER.UserId then
--             print("LLLLLLL no owner id")
--             return
--         end

--         -- check if there is a weapon
--         local weaponId = playerState:get(Id.PlayerStats.GAME_SESSION, C.RefId)
--         if not weaponId then
--             print("LLLLLLL no weapon id")
--             error("weaponId is nil")
--         end
        
--         print("LLLLLLL everything is fine")
--         Signal.Broadcast(Id.C2S.ENEMY_HIT, enemyGuid)
--     end)
-- end

-- local m = {}

-- workerMaid.subToAdd = Signal.Connect(Id.C2C.NEW_ENEMY_ADDED, onEnemyAdded)
-- workerMaid.subToRemove = Signal.Connect(Id.C2C.ENEMY_REMOVED, onEnemyRemoved)

-- return m
