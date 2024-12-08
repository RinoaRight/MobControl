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
local log = Logger.create(script and script.Name or "Clones"):set_prettifier(Id.pp):set_delimiter(" ")
local TaskPool = require(shared.TaskPool)
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local Misc = require(shared.Misc)
local SharedConfig = require(shared.SharedConfig)
local m = {}

function m.CreateClone(playerId, playerCharacter: Model)
    TaskPool.spawn(function()
        -- clone the player's character
        playerCharacter.Archivable = true
        local cloneCharTemplate = playerCharacter

        local playerFolderName = SharedConfig.CLONES_FOLDER_NAME
        local existingFolder = playerCharacter:FindFirstChild(playerFolderName) :: Folder?
        local existingClones
        local folder: Folder = existingFolder or Instance.new("Folder") :: Folder
        if not existingFolder then
            folder.Name = playerFolderName
            folder.Parent = playerCharacter
        else
            existingClones = folder:GetChildren()
            cloneCharTemplate = existingClones[1] :: Model
        end
        local cloneInstance = cloneCharTemplate:Clone()
        for _, instance in cloneInstance:GetDescendants() do
            if instance:IsA("BasePart") then
                instance.CollisionGroup = "DriverNonCollidable"
            end
        end

        -- delete player hitbox when copying the character
        -- TODO: fix
        local playerHitbox = cloneInstance:FindFirstChild(SharedConfig.PLAYER_HITBOX_NAME) :: Humanoid
        if playerHitbox then
            playerHitbox:Destroy()
        end
        cloneInstance.Parent = folder

        local humanoidRootPart = playerCharacter:WaitForChild("HumanoidRootPart") :: BasePart
        local cloneRootPart = cloneInstance:WaitForChild("HumanoidRootPart", 10) :: Part
        local existingClonesNum = 0
        if existingClones then
            existingClonesNum = #existingClones
        end

        local vacantRow = math.floor((existingClonesNum - 1) / SharedConfig.CLONES_IN_A_ROW) + 1
        local alreadyInCol = existingClonesNum % SharedConfig.CLONES_IN_A_ROW
        cloneRootPart.CFrame = CFrame.new(Misc.GetClonePos(humanoidRootPart.Position, alreadyInCol, vacantRow))
        Misc.AddPlayerCharToRaycastFilter(cloneInstance)
        -- TODO: signal to server to refelct it somehow (state.playerstats.Clones) - and fire power
    end)
end

return m
