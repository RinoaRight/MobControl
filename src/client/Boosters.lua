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
local log = Logger.create("Market"):set_prettifier(Id.pp):set_delimiter(" ")
local TaskPool = require(shared.TaskPool)
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local workerMaid = disposer.new()

local m = {}

-- local function onBoosterHitByBullet(booster)
--     Signal.Broadcast(Id.C2S.BOOSTER_HIT, booster)
-- end

-- local function subscribeBoosters(groundUnit)
--     local children = groundUnit:GetChildren()
--     for _, booster in ipairs(children) do
--         if booster:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
--             local name = booster.Name
--             workerMaid[name] = (
--                 booster.Touch:Connect(function(other)
--                     if other.Name == "Bullet" then
--                         onBoosterHitByBullet(booster)
--                     end
--                 end)
--             )
--         end
--     end
-- end

-- function m.InitBoosters()
--     local existingGroundUnits = GROUND_UNITS_FOLDER:GetChildren()
--     for _, groundUnit in ipairs(existingGroundUnits) do
--         subscribeBoosters(groundUnit)
--     end
--     workerMaid.subToGroundUnits = GROUND_UNITS_FOLDER.ChildAdded:Connect(function(groundUnit)
--         subscribeBoosters(groundUnit)
--     end)
--     -- unsubscribe booster on its removal
--     workerMaid.subToBoosterRemoved = GROUND_UNITS_FOLDER.DescendantRemoving:Connect(function(descendant)
--         if descendant:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
--             local name = descendant.Name
--             workerMaid[name] = nil
--         end
--     end)
-- end

return m
