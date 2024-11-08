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

type PlayerState = PSS.PlayerState

local CLONES = {}

local workerMaid = disposer.new()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GROUND_UNIT_FOLDER = game.Workspace.GroundUnits
local GROUND_UNIT_TEMPLATE = assert(ReplicatedStorage.GroundUnit)
local GROUND_INIT_LENGTH = GROUND_UNIT_TEMPLATE.Size.Z

local FIELD_NAMES = En.with_id "*" {
    FIRST = 1,
    SECOND = 2,
    MIDDLE = 3,
    FOURTH = 4,
    FIFTH = 5,
}

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
    groundUnit:Destroy()
end

local function spawnGroundUnit(groundUnit: Part, index: int, refPos: Vector3)
    GROUND_UNITS[index].unit = groundUnit
    groundUnit.CFrame = CFrame.new(refPos.X, refPos.Y, refPos.Z + GROUND_UNITS[index].zOffset)
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    trigger.CFrame = CFrame.new(9, 20.5, groundUnit.Position.Z - 245)
    groundUnit.Parent = GROUND_UNIT_FOLDER
end

local function subscribeTrigger(index, groundUnit)
    local trigger = assert(groundUnit:FindFirstChild("EndZoneTrigger") :: BasePart)
    workerMaid.trigger = trigger.Touched:Connect(function(triggerer)
        if triggerer == DRIVING_BOX_FRONT then
            subscribeTrigger(FIELD_NAMES.FOURTH, GROUND_UNITS[FIELD_NAMES.FOURTH].unit)
            trigger:Destroy()
            deleteGroundUnit(GROUND_UNITS[FIELD_NAMES.FIRST].unit, FIELD_NAMES.FIRST)
            -- shift all other units in the data table accordingly
            GROUND_UNITS[FIELD_NAMES.FIRST].unit = GROUND_UNITS[FIELD_NAMES.SECOND].unit
            GROUND_UNITS[FIELD_NAMES.SECOND].unit = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit
            GROUND_UNITS[FIELD_NAMES.MIDDLE].unit = GROUND_UNITS[FIELD_NAMES.FOURTH].unit
            GROUND_UNITS[FIELD_NAMES.FOURTH].unit = GROUND_UNITS[FIELD_NAMES.FIFTH].unit
            local refPos = GROUND_UNITS[FIELD_NAMES.MIDDLE].unit.Position
            spawnGroundUnit(GROUND_UNIT_TEMPLATE:Clone(), FIELD_NAMES.FIFTH, refPos)
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

function m.init()
    -- init first batch of ground units and fill in the data table
    local firstUnit = GROUND_UNIT_TEMPLATE:Clone()
    local secondUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fourthUnit = GROUND_UNIT_TEMPLATE:Clone()
    local fifthUnit = GROUND_UNIT_TEMPLATE:Clone()
    subscribeTrigger(FIELD_NAMES.MIDDLE, GROUND_UNITS[FIELD_NAMES.MIDDLE].unit)
    spawnGroundUnit(firstUnit, FIELD_NAMES.FIRST, startingPos)
    spawnGroundUnit(secondUnit, FIELD_NAMES.SECOND, startingPos)
    spawnGroundUnit(fourthUnit, FIELD_NAMES.FOURTH, startingPos)
    spawnGroundUnit(fifthUnit, FIELD_NAMES.FIFTH, startingPos)
end

local oldPos = DRIVING_BOX_INSTANCE.Position
function m.MoveDrivingBox(world_state)
    return function(dt)
        DRIVING_BOX_INSTANCE.CFrame = CFrame.new(oldPos.X, oldPos.Y, oldPos.Z - 0.5)
        oldPos = DRIVING_BOX_INSTANCE.Position
    end
end

print("[Game Module -- started]")
return m
