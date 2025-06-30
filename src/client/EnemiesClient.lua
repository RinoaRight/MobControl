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

local shared = game.ReplicatedStorage.shared
local Id = require(shared.Id)
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "Boosters"):set_prettifier(Id.pp):set_delimiter(" ")
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local W = SharedConfig.World.CId
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local workerMaid = disposer.new()
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local Misc = require(shared.Misc)
local S = require(shared.StaticData)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TaskPool = require(shared.TaskPool)
local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local ENEMIES_FOLDER = assert(workspace:WaitForChild("Enemies"))
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)
local TARGET_SIGN_TEMPLATE = assert(ReplicatedStorage:WaitForChild("TargetSign"))

local _maid = disposer.new()

local function flickerEnemy(guid: string, part: BasePart)
    local colorDark = Color3.fromHex("246b34")
    local colorBright = Color3.fromHex("37a24e")

    -- Start flickering
    local period = 5
    _maid[guid] = TaskPool.spawn(function()
        while true do
            -- Forward transition
            for i = 0, 1, 0.01 do
                part.Color = colorDark:Lerp(colorBright, i)
                task.wait(period / 200) -- period/2 divided by 100 steps
            end

            -- Backward transition
            for i = 1, 0, -0.01 do
                part.Color = colorDark:Lerp(colorBright, i)
                task.wait(period / 200) -- period/2 divided by 100 steps
            end
        end
    end)

    part.Destroying:Connect(function()
        _maid[guid] = nil
    end)
end


local function onEnemyAdded(worldState, playerState: state.Replica, enemyGuid: string)
    local enemyRefId = worldState:get(enemyGuid, W.RefId)
    local enemyPos = worldState:get(enemyGuid, W.Position) :: Vector3

    local enemyInstance
    if S.Enemy[enemyRefId].meshTemplate then
        enemyInstance = S.Enemy[enemyRefId].meshTemplate:Clone()
    else
        enemyInstance = Instance.new("Part")
        enemyInstance.Size = Vector3.new(2, 6, 2)
    end
    enemyInstance.CanCollide = false
    enemyInstance.Anchored = true
    enemyInstance.CollisionGroup = "BulletCollidable"

    enemyInstance.Parent = ENEMIES_FOLDER
    enemyInstance.CFrame = CFrame.new(enemyPos)
    enemyInstance.Name = enemyGuid

    worldState:set(enemyGuid, W.ClientInstance, enemyInstance)

    -- if the enemy is a boss, attach the player's align constraint to the boss
    if enemyRefId == Id.Enemy.OCTOBOSS then
        local bossAtt = Instance.new("Attachment") :: Attachment
        bossAtt.Parent = enemyInstance
        local character = LOCAL_PLAYER.Character
        local playerAlignConst = character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
        if playerAlignConst then
            playerAlignConst.Attachment1 = bossAtt
        end
    end
end

local m = {}

m.OnBossDestroyed = function(worldState, enemyGuid: string)
    local character = LOCAL_PLAYER.Character
    local playerAlignConst = character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
    if playerAlignConst then
        playerAlignConst.Attachment1 = nil
        print("LLLLLLL", playerAlignConst.Attachment1)
    end
end

workerMaid.subToAdd = Signal.Connect(Id.C2C.NEW_ENEMY_ADDED, onEnemyAdded)

return m
