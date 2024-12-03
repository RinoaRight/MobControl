--!strict
--!native
type str = string
type bool = boolean
type num = number
type positive = num
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.shared
local SharedConfig = require(shared.SharedConfig)
local Id = require(shared.Id)
local S = require(shared.StaticData)

local Debris = game:GetService("Debris")

local m = {}
m.__index = m

local raycastParams = RaycastParams.new()
-- raycastParams.CollisionGroup = "BulletCollidable"
-- raycastParams.FilterType = Enum.RaycastFilterType.Include
local blacklist = {} :: { Instance }

m.AddPlayerCharToRaycastFilter = function(instance)
    table.insert(blacklist, instance)
end

m.IsBoosterToHit = function(pos: Vector3)
    raycastParams.FilterDescendantsInstances = blacklist
    local rayDirection = Vector3.new(0, 0, -SharedConfig.BULLET_BASE_DISTANCE)
    local raycastResult = workspace:Raycast(pos, rayDirection, raycastParams)
    if "debug" then
        local ray = Instance.new("Part")
        ray.CanCollide = false
        ray.Parent = workspace
        ray.Anchored = true
        ray.Size = Vector3.new(.1, .1, 2 * rayDirection.Magnitude)
        ray.CFrame = CFrame.new(pos, pos + rayDirection)
        Debris:AddItem(ray, 3)
    end
    local booster = nil
    local distance
    local raycastInstance
    if raycastResult then
        print("KKKKKKKKKKKKKKKK", raycastResult.Instance.Name)
        raycastInstance = raycastResult.Instance
        if raycastInstance:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            booster = raycastInstance
            distance = (raycastResult.Position - pos).Magnitude
        end
    end
    return booster, distance
end

return m
