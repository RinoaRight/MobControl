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

local m = {}

function m.CreateClone()
    TaskPool.spawn(function()
        local LOCAL_PLAYER = game.Players.LocalPlayer
        local DRIVING_BOX_ATT = workspace:WaitForChild("DrivingBox", 10):FindFirstChild("Attachment")
        local playerAtt = Instance.new("Attachment") :: Attachment
        local rootPart = (LOCAL_PLAYER.root) :: Part
        playerAtt.CFrame = (rootPart :: Part).CFrame
        playerAtt.Parent = rootPart
        local alignConst = Instance.new("AlignOrientation")
        alignConst.Parent = workspace
        alignConst.Attachment0 = playerAtt
        alignConst.Attachment1 = DRIVING_BOX_ATT
        -- clone the player's character
        local character = LOCAL_PLAYER.character
        character.Archivable = true
        local cloneChar = character:Clone()
        cloneChar.Name = "Clone"
        -- onCloneCharacterAdded(cloneChar)
        cloneChar.Parent = workspace.Clones
        -- table.insert(CLONES, cloneChar)
        local _cloneHumanoid = cloneChar:WaitForChild("Humanoid", 10) :: Humanoid
        local cloneRootPart = cloneChar:WaitForChild("HumanoidRootPart", 10) :: Part
        cloneRootPart.CFrame = CFrame.new(rootPart.Position.X + 5, rootPart.Position.Y, rootPart.Position.Z + 20) --* CFrame.Angles(0, math.rad(180), 0)
        local cloneAtt = Instance.new("Attachment") :: Attachment
        cloneAtt.CFrame = (cloneRootPart :: Part).CFrame
        cloneAtt.Parent = cloneRootPart
        local cloneAlignConst = Instance.new("AlignOrientation")
        cloneAlignConst.Name = "CloneAlignConstraint"
        cloneAlignConst.Parent = workspace
        cloneAlignConst.Attachment0 = cloneAtt
        cloneAlignConst.Attachment1 = playerAtt
    end)
end

return m
