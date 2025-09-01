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
local W = SharedConfig.World.CId
local S = require(shared.StaticData)

local createAura = function(character: Model, perk_id: int, player_id)
    -- create a new aura
    local aura = S.VFX[Id.VFX.INVINCIBILITY_AURA]:Clone()
    local color = assert(S.PlayerUpgradeNonPersistent[perk_id].color)
    local name
    if perk_id == Id.PlayerUpgradeNonPersistent.INVINCIBILITY then
        name = SharedConfig.INVINCIBILITY_AURA_NAME
    elseif perk_id == Id.PlayerUpgradeNonPersistent.SHIELD then
        name = SharedConfig.SHIELD_AURA_NAME
        Misc.PlaySound(Id.Sound.ENERGY_SWEEP)
    elseif perk_id == Id.PlayerUpgradeNonPersistent.ARMOR then
        name = SharedConfig.ARMOR_AURA_NAME
        aura.Transparency = 0.85
    end
    aura.Color = color
    aura.Name = name

    aura.Parent = character
    local upperTorso = assert(character:FindFirstChild("UpperTorso")) :: BasePart
    local constraint = Instance.new("WeldConstraint")
    constraint.Parent = aura
    constraint.Part0 = upperTorso
    constraint.Part1 = aura
    aura.Position = upperTorso.Position
    aura:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.VFX], player_id)
end

local m = {}

function m.CreateCloneInstance(worldState, playerId: int, cloneGuid: num | str)
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

        worldState:set(cloneGuid, W.ClientInstance, cloneInstance)

        for _, instance in cloneInstance:GetDescendants() do
            if instance:IsA("BasePart") then
                instance.CollisionGroup = "DriverNonCollidable"
                -- remove aura from the clone (if any)
                if instance:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.VFX]) then
                    instance:Destroy()
                end
            end
        end

        if worldState:get(Id.WorldSpecs.HANDICAP, W.Value) == Id.Handicap.BOMBS then
            createAura(cloneInstance, Id.PlayerUpgradeNonPersistent.ARMOR, playerId)
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
        cloneRootPart.CFrame = Misc.GetCloneCFrame(humanoidRootPart.CFrame, alreadyInCol, vacantRow)
    end)

    return cloneInstance
end

return m
