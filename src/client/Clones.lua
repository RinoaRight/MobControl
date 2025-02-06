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

local LOCAL_PLAYER = game.Players.LocalPlayer

function m.CreateClone(playerId: int, cloneGuid: num | str)
    local cloneInstance
    TaskPool.spawn(function()
        -- clone the player's character
        local playerCharacter
        local players = game.Players:GetPlayers()
        for _, player in ipairs(players) do
            if player.UserId == playerId then
                playerCharacter = player.Character or player.CharacterAdded:Wait()
                break
            end
        end
        if not playerCharacter then
            log:error("Failed to find player character for player %s", playerId)
            return
        end
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
            if #existingClones > 0 then
                cloneCharTemplate = existingClones[1] :: Model
            end
        end
        cloneInstance = cloneCharTemplate:Clone()
        local humanoid = cloneInstance:WaitForChild("Humanoid") :: Humanoid
        humanoid.DisplayName = " "
        cloneInstance.Name = cloneGuid
        for _, instance in cloneInstance:GetDescendants() do
            if instance:IsA("BasePart") then
                instance.CollisionGroup = "DriverNonCollidable"
                -- if instance.Name == SharedConfig.PLAYER_HITBOX_NAME then
                --     instance:Destroy()
                -- end
            end
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
        Misc.AddInstanceToRaycastFilter(cloneInstance)
    end)

    return cloneInstance
end

return m
