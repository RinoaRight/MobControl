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
local ReplicatedStorage = game.ReplicatedStorage

local maid = disposer.new()

local LOBBY = workspace:WaitForChild("Lobby")
local LEADERBOARDS_FOLDER = LOBBY:WaitForChild("Leaderboards")
local PODIUMS_STAND = LEADERBOARDS_FOLDER:WaitForChild("WinnerPodiums")
local BOSS_KILLER_PODIUM = assert(PODIUMS_STAND:WaitForChild("BossKillerPodium"))
local MOST_DAMAGE_PODIUM = assert(PODIUMS_STAND:WaitForChild("MostDamagePodium"))
local MOST_ENEMIES_PODIUM = assert(PODIUMS_STAND:WaitForChild("MostEnemiesPodium"))

local WINNER_GUI_PART_TEMPLATE = assert(ReplicatedStorage:WaitForChild("UI"):WaitForChild("WinnerGuiPart"))

local m = {}

m.ResetLeaderboards = function()
    for _, podium in ipairs(PODIUMS_STAND:GetChildren()) do
        for _, child in ipairs(podium:GetChildren()) do
            if child:IsA("Model") then
                child:Destroy()
            end
        end
    end
end

m.SpawnWinner = function(playerState: PSS.PlayerState, achievementId)
    TaskPool.defer(function()
        local podium
        if achievementId == Id.Achievement.BOSS_KILLER then
            podium = BOSS_KILLER_PODIUM
        elseif achievementId == Id.Achievement.MOST_DAMAGE then
            podium = MOST_DAMAGE_PODIUM
        elseif achievementId == Id.Achievement.MOST_ENEMIES then
            podium = MOST_ENEMIES_PODIUM
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
        cloneRoot.Anchored = true
        -- TODO: create a custom name plate
        local cloneHumanoid = clone:FindFirstChild("Humanoid") :: Humanoid
        if cloneHumanoid then   
            cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end

        -- spawn gui
        local winnerGuiPart = assert(WINNER_GUI_PART_TEMPLATE:Clone())
        winnerGuiPart.Parent = clone
        winnerGuiPart.Anchored = true
        winnerGuiPart.CanCollide = false
        local cloneHead = assert(clone:FindFirstChild("Head") :: Part)
        local headPos = cloneHead.Position :: Vector3
        winnerGuiPart.Position = Vector3.new(headPos.X, headPos.Y + 15, headPos.Z)
        local winnerGui = assert(winnerGuiPart:FindFirstChild("WinnerGUI") :: BillboardGui)
        winnerGui.Enabled = true
        local nameBox = assert(winnerGui:FindFirstChild("Name")) :: TextLabel
        local descrBox = assert(winnerGui:FindFirstChild("Description")) :: TextLabel
        local entry = S.Achievement[achievementId]
        if entry then
            nameBox.Text = entry.name
            nameBox.TextColor3 = entry.color
            descrBox.Text = entry.description
            descrBox.TextColor3 = entry.color
        end

        -- play animation
        -- TODO: different animations for each achievement
        task.wait(.2)
        local animId = S.Animation[Id.Animation.DANCE]
        if animId then
            Misc.PlayCharacterAnim(clone, animId, true)
        end
    end)
end

return m
