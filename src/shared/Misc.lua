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
    -- if "debug" then
    --     local ray = Instance.new("Part")
    --     ray.CanCollide = false
    --     ray.Parent = workspace
    --     ray.Anchored = true
    --     ray.Size = Vector3.new(0.1, 0.1, 2 * rayDirection.Magnitude)
    --     ray.CFrame = CFrame.new(pos, pos + rayDirection)
    --     Debris:AddItem(ray, 3)
    -- end
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

m.GetClonePos = function(pos: Vector3, alreadyInCol: int, row: int)
    local dist = SharedConfig.INTERCLONES_DISTANCE
    local new_pos = Vector3.new(pos.X, pos.Y, pos.Z + dist)
    local x = 0
    local z = dist
    if alreadyInCol == 1 then
        x = -dist
    elseif alreadyInCol == 2 then
        x = dist
    elseif alreadyInCol == 3 then
        x = -dist * 2
    elseif alreadyInCol == 4 then
        x = dist
    end
    new_pos = Vector3.new(new_pos.X + x, new_pos.Y, new_pos.Z + z * row)
    return new_pos
end

-- attach hitbox to the player == clones formation width
m.AttachHitboxToPlayer = function(player_state)
    local player_character = player_state.character
    local humanoid_root_part = player_state.root
    local hitbox = Instance.new("Part")
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.Anchored = false
    hitbox.CollisionGroup = "BulletNonCollidable"
    hitbox.Massless = true
    hitbox.Parent = player_character
    hitbox.CFrame = humanoid_root_part.CFrame
    local weld = Instance.new("WeldConstraint")
    weld.Parent = hitbox
    local rootPart = assert(player_state.root :: BasePart)
    weld.Part0 = rootPart
    weld.Part1 = hitbox
    hitbox.Name = SharedConfig.PLAYER_HITBOX_NAME
    hitbox.CanCollide = false
    local width = SharedConfig.INTERCLONES_DISTANCE * (SharedConfig.CLONES_IN_A_ROW - 1)
    hitbox.Size = Vector3.new(width, 6, 4)
end

return m
