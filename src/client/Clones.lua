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
        -- local playerIdName = tostring(playerId)
        -- cloneChar.Name = playerIdName
        -- local playerFolderName = playerIdName .. "_Clones"
        
        local playerFolderName = "Clones"
        -- local folder = workspace:FindFirstChild(playerFolderName)
        local existingFolder = playerCharacter:FindFirstChild(playerFolderName) :: Folder?
        local folder:Folder = existingFolder or Instance.new("Folder") :: Folder
        if not existingFolder then
            folder.Name = playerFolderName
            folder.Parent = playerCharacter
        end
        cloneChar.Parent = folder

        local humanoidRootPart = playerCharacter:WaitForChild("HumanoidRootPart") :: BasePart
        local cloneRootPart = cloneChar:WaitForChild("HumanoidRootPart", 10) :: Part
        -- TODO: formation
        cloneRootPart.CFrame = CFrame.new(humanoidRootPart.Position.X + 5, humanoidRootPart.Position.Y, humanoidRootPart.Position.Z + 20)
    end)
end

return m
