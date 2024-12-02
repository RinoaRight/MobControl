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

local m = {}
m.__index = m

m.IsBoosterToHit = function(pos: Vector3, humanoidRootPart: BasePart, ttl: num)
    local raycastParams = RaycastParams.new()
    raycastParams.CollisionGroup = "BulletCollidable"
    local rayDirection = Vector3.new(pos.X, pos.Y, pos.Z - SharedConfig.BULLET_BASE_DISTANCE)
    local raycastResult = workspace:Raycast(pos, rayDirection, raycastParams)
    local booster = nil
    local distance
    local raycastInstance
    if raycastResult then
        raycastInstance = raycastResult.Instance
        if raycastInstance:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            booster = raycastInstance
            distance = (raycastResult.Position - pos).Magnitude
        end
    end
    return booster, distance
end

return m
