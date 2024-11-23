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

function m.CreateClone(playerId, playerCharacter: Model)
    TaskPool.spawn(function()
        -- clone the player's character
        playerCharacter.Archivable = true
        local cloneChar = playerCharacter:Clone()
        local playerIdName = tostring(playerId)
        cloneChar.Name = playerIdName
        local playerFolderName = playerIdName .. "_Clones"
        local folder = workspace:FindFirstChild(playerFolderName)
        if not folder then
            folder = Instance.new("Folder") :: Folder
            folder.Name = playerFolderName
            folder.Parent = workspace.Clones
        end
        cloneChar.Parent = folder

        local humanoidRootPart = playerCharacter:WaitForChild("HumanoidRootPart") :: BasePart
        local cloneRootPart = cloneChar:WaitForChild("HumanoidRootPart", 10) :: Part
        -- TODO: formation
        cloneRootPart.CFrame = CFrame.new(humanoidRootPart.Position.X + 5, humanoidRootPart.Position.Y, humanoidRootPart.Position.Z + 20)
        -- local cloneAtt = Instance.new("Attachment") :: Attachment
        -- cloneAtt.CFrame = (cloneRootPart :: Part).CFrame
        -- cloneAtt.Parent = cloneRootPart
        -- local cloneAlignConst = Instance.new("AlignOrientation")
        -- cloneAlignConst.Name = "CloneAlignConstraint"
        -- cloneAlignConst.Parent = workspace
        -- cloneAlignConst.Attachment0 = cloneAtt
        -- cloneAlignConst.Attachment1 = playerAtt
    end)
end

return m
