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
local log = Logger.create("Market"):set_prettifier(Id.pp):set_delimiter(" ")
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

type PlayerState = PSS.PlayerState

local CLONES = {}

local workerMaid = disposer.new()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GROUND_UNIT_FOLDER = game.Workspace.GroundUnits
local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_INIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z

local FIELD_NAMES = En.with_id("*")({
    FIRST = 1,
    SECOND = 2,
    MIDDLE = 3,
    FOURTH = 4,
    FIFTH = 5,
})

-- stylua: ignore
local GROUND_UNITS = {
    {                                             zOffset = GROUND_INIT_LENGTH * 2 },
    {                                             zOffset = GROUND_INIT_LENGTH},
    { unit = GROUND_UNIT_FOLDER.GroundUnit_Start, zOffset = 0},
    {                                             zOffset = -GROUND_INIT_LENGTH },
    {                                             zOffset = GROUND_INIT_LENGTH * -2 },
}
local startingPos = GROUND_UNITS[3].unit.Position

local DRIVING_BOX_TEMPLATE = assert(ReplicatedStorage.DrivingBox)
local DRIVING_BOX_INSTANCE = DRIVING_BOX_TEMPLATE:Clone()
local DRIVING_BOX_FRONT = assert(DRIVING_BOX_INSTANCE.PartFront)
DRIVING_BOX_INSTANCE.Parent = game.Workspace
local DRIVING_BOX_ATT = Instance.new("Attachment") :: Attachment
DRIVING_BOX_ATT.Parent = DRIVING_BOX_FRONT

local function deleteGroundUnit(groundUnit: Part, index: int)
    local children = groundUnit:GetChildren()
    for _, v in ipairs(children) do
        if v:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
            WorldService.RemoveBooster(v.Name)
        end
    end
    groundUnit:Destroy()
end

local function setBooster(instance: BasePart)
    -- TODO: actual range of selection
    local refID = math.random(Id.Boost.ADD_CLONE, Id.Boost.ADD_CLONE)
    local value = math.random(S.Boost[refID].valueRange[1], S.Boost[refID].valueRange[2])
    local hp = math.random(S.Boost[refID].hpRange[1], S.Boost[refID].hpRange[2])
    local boostContentId = nil
    -- TODO: Fill in the data in booster's GUI
    if refID == Id.Boost.ADD_CLONE then
        -- TODO:
    elseif refID == Id.Boost.BULLET_SPEED_MULT then
        -- TODO:
    elseif refID == Id.Boost.CHANGE_WEAPON then
        -- TODO: actual range of selection
        boostContentId = math.random(Id.Weapon.DEFAULT, Id.Weapon.DEFAULT)
    end
    instance:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost], refID)
    -- TODO: currently it is setting boosters for solo player only, Refactor to multiplayer.
    WorldService.AddBooster(instance, refID, value, hp, boostContentId)
end

local function spawnGroundUnit(worldState: state.Main, groundUnit: Part, index: int, refPos: Vector3)
    GROUND_UNITS[index].unit = groundUnit
	local unitPos = CFrame.new(refPos.X, refPos.Y, refPos.Z + GROUND_UNITS[index].zOffset)
    groundUnit.CFrame = unitPos
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    trigger.CFrame = CFrame.new(9, 20.5, unitPos.Z - 245)
    groundUnit.Parent = GROUND_UNIT_FOLDER
	groundUnit.AssemblyLinearVelocity = groundUnit.CFrame.LookVector * 30
    local boosterLeft = assert(groundUnit:FindFirstChild("BoosterLeft") :: BasePart)
	boosterLeft.CFrame = CFrame.new(unitPos.X - 20, unitPos.Y + 20, unitPos.Z -50)
    local boosterRight = assert(groundUnit:FindFirstChild("BoosterRight") :: BasePart)
	boosterRight.CFrame = CFrame.new(unitPos.X + 20, unitPos.Y + 20, unitPos.Z -50)
    -- TODO: currently it is setting boosters for solo player only, Refactor to multiplayer.
    setBooster(boosterLeft)
    setBooster(boosterRight)
end

local function subscribeTrigger(worldState: state.Main, index, groundUnit)
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    workerMaid.trigger = trigger.Touched:Connect(function(triggerer)
        if triggerer == DRIVING_BOX_FRONT then
            subscribeTrigger(worldState, FIELD_NAMES.FOURTH, GROUND_UNITS[FIELD_NAMES.FOURTH].unit)
            trigger:Destroy()
            deleteGroundUnit(GROUND_UNITS[FIELD_NAMES.FIRST].unit, FIELD_NAMES.FIRST)
            -- shift all other units in the data table accordingly
            GROUND_UNITS[FIELD_NAMES.FIRST].unit = GROUND_UNITS[FIELD_NAMES.SECOND].unit
            GROUND_UNITS[FIELD_NAMES.SECOND].unit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit
            GROUND_UNITS[FIELD_NAMES.MIDDLE].unit = GROUND_UNITS[FIELD_NAMES.FOURTH].unit
            GROUND_UNITS[FIELD_NAMES.FOURTH].unit = GROUND_UNITS[FIELD_NAMES.FIFTH].unit
            local refPos = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.Position
            spawnGroundUnit(worldState, GROUND_UNIT_TEMPLATE:Clone(), FIELD_NAMES.FIFTH, refPos)
        end
    end)
end

-- local function onDescendantAdded(descendant)
--     -- Set collision group for any part descendant
--     if descendant:IsA("BasePart") then
--         -- descendant.CollisionGroup = "Clones"
--     end
-- end

-- local function onCloneCharacterAdded(character)
--     -- Process existing and new descendants for physics setup
--     for _, descendant in character:GetDescendants() do
--         onDescendantAdded(descendant)
--     end
--     character.DescendantAdded:Connect(onDescendantAdded)
-- end

local m = {}

function m.init(worldState: state.Main, get_state: (player_id: int) -> PlayerState?)
    -- init first batch of ground units and fill in the data table
    local firstUnit = GROUND_UNIT_TEMPLATE:Clone()
    local secondUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fourthUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fifthUnit = GROUND_UNIT_TEMPLATE:Clone()
	
    subscribeTrigger(worldState, FIELD_NAMES.MIDDLE, GROUND_UNITS[FIELD_NAMES.MIDDLE].unit)
	GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.AssemblyLinearVelocity = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.CFrame.LookVector * 30
    spawnGroundUnit(worldState, firstUnit, FIELD_NAMES.FIRST, startingPos)
    spawnGroundUnit(worldState, secondUnit, FIELD_NAMES.SECOND, startingPos)
    spawnGroundUnit(worldState, fourthUnit, FIELD_NAMES.FOURTH, startingPos)
    spawnGroundUnit(worldState, fifthUnit, FIELD_NAMES.FIFTH, startingPos)
end

local oldPos = DRIVING_BOX_INSTANCE.Position
function m.StartMainLoop(world_state)
    return function(dt)
        -- driving box movement
        DRIVING_BOX_INSTANCE.CFrame = CFrame.new(oldPos.X, oldPos.Y, oldPos.Z - 0.5)
        oldPos = DRIVING_BOX_INSTANCE.Position
    end
end

print("[Game Module -- started]")
return m
-- TODO: adding boosts with an attribute == boost_id
-- boost:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost], boost_id)
