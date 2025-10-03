--!strict
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

type int = number
type GetState = (int) -> PSS.PlayerState?

local m = {}
function m.PlacePlayersOnRectanglePerimeter(activePlayers: {}, center: Vector3)
    -- Place n players evenly along the perimeter of a rectangle, all facing the center

    local size = Vector2.new(450, 450) -- width, length
    local y = 5 -- height at which to place players

    local n = #activePlayers
    if n == 0 then
        return
    end

    local width, length = size.X, size.Y
    local halfW, halfL = width / 2, length / 2
    local rectPoints = {
        Vector3.new(center.X - halfW, y, center.Z - halfL), -- bottom-left
        Vector3.new(center.X + halfW, y, center.Z - halfL), -- bottom-right
        Vector3.new(center.X + halfW, y, center.Z + halfL), -- top-right
        Vector3.new(center.X - halfW, y, center.Z + halfL), -- top-left
    }

    -- Perimeter = total distance around rectangle
    local perim = 2 * (width + length)
    local spacing = perim / n

    -- Precompute edges (for looping)
    local edges = {
        { rectPoints[1], rectPoints[2], width }, -- bottom edge
        { rectPoints[2], rectPoints[3], length }, -- right edge
        { rectPoints[3], rectPoints[4], width }, -- top edge
        { rectPoints[4], rectPoints[1], length }, -- left edge
    }

    -- Place each player
    local currentDist = 0
    for i, player in ipairs(activePlayers) do
        local dist = currentDist % perim
        -- Figure out which edge this distance falls on
        local edgeStart = 0
        for edgeIdx, edge in ipairs(edges) do
            local edgeLen = edge[3]
            if dist <= edgeStart + edgeLen then
                -- Position along this edge
                local alpha = (dist - edgeStart) / edgeLen
                local from, to = edge[1], edge[2]
                local pos = from:Lerp(to, alpha)
                -- Face the center (lookVector = (center - pos).Unit)
                if player:IsA("Player") then
                    local char = assert(player.Character)
                    local root = assert(char:FindFirstChild("HumanoidRootPart")) :: BasePart
                    root.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
                elseif player:IsA("Model") and player:FindFirstChild("HumanoidRootPart") then
                    player.HumanoidRootPart.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
                else
                    -- testing purposes, baseParts instead of players
                    player.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
                end
                break
            end
            edgeStart += edgeLen
        end
        currentDist += spacing
    end
end

function m.OnPvpOff(get_state: GetState)
    for _, player in game.Players:GetPlayers() do
        local player_state = get_state(player.UserId)
        if not player_state then
            continue
        end

        -- for all player parts, reset the collision group to nil
        for _, part in Misc.GetAllPlayerParts(player_state) do
            (part :: BasePart).CollisionGroup = "Default"
        end
    end
end

return m
