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
local BoosterServer = require(server.BoosterServer)

local LOBBY = workspace:WaitForChild("Lobby")
local LEADERBOARDS_FOLDER = LOBBY:WaitForChild("Leaderboards")
local BOSS_KILLER_PODIUM = assert(LEADERBOARDS_FOLDER:WaitForChild("BossKillerPodium"))

local m = {}

m.SpawnWinner = function(playerState: PSS.PlayerState, achievementId)
    local podium
    if achievementId == Id.Achievement.BOSS_KILLER then
        podium = BOSS_KILLER_PODIUM
    end
    if not podium then
        return
    end

    local playerChar = playerState.character
    if not playerChar then
        return
    end

    local orientationBlock = podium:FindFirstChild("OrientationBlock")

    -- spawn winner's clone
    local clone = playerChar:Clone()
    clone.Parent = podium
    local cloneRoot = clone:FindFirstChild("HumanoidRootPart") :: Part
    local currentScale = clone:GetScale()
    local newScale = currentScale * 3
    clone:ScaleTo(newScale)
    local oldPos = cloneRoot.Position :: Vector3
    local podiumPos = podium.Position :: Vector3 
    local diff = math.abs(podium.Position.Y - cloneRoot.Position.Y)
    local yOffset = podium.Size.Y / 2 + diff
    local targetPos = Vector3.new(podiumPos.X, oldPos.Y + yOffset, podiumPos.Z)
    cloneRoot.CFrame = CFrame.lookAlong(targetPos, -orientationBlock.Position)

    -- play animation
    local animId = S.Animation[Id.Animation.DANCE]
    if animId then
        Misc.PlayCharacterAnim(clone, animId, true)
    end
end

return m
