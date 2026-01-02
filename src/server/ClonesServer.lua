--!nolint
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
local server = game.ServerScriptService.server
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
local PSS = require(server.PlayerStateService)

local m = {}

-- m.AttachCloneDummies = function(player_state: PSS.PlayerState)
--     -- TODO: clone dummy are hindering other player's movement, need to fix
--     for i = 1, SharedConfig.CLONES_IN_A_ROW do
--         local cloneInstance = Instance.new("Part")
--         local humanoid_root_part = player_state.root
--         local player_id = player_state.player_id
--         cloneInstance.Size = humanoid_root_part.Size
--         cloneInstance.Transparency = 1
--         cloneInstance.CanCollide = false
--         cloneInstance.CanTouch = true
--         cloneInstance.Massless = true
--         cloneInstance.Anchored = false
--         cloneInstance:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Clone], player_id)
--         local folder = workspace:FindFirstChild(SharedConfig.CLONES_DUMMY_FOLDER_NAME)
--         if not folder then
--             folder = Instance.new("Folder")
--             assert(folder, "type coercion")
--             folder.Name = SharedConfig.CLONES_DUMMY_FOLDER_NAME
--             folder.Parent = workspace
--         end
--         cloneInstance.Name = tostring(i)
--         cloneInstance.Parent = folder
--         cloneInstance.CFrame = humanoid_root_part.CFrame
--         cloneInstance.Position = Misc.GetCloneDummyPos(humanoid_root_part.Position, i - 1, 0)
--         Misc.AddInstanceToRaycastFilter(cloneInstance)

--         local att2 = Instance.new("Attachment")
--         att2.Parent = cloneInstance
--         att2.CFrame = humanoid_root_part.CFrame

--         local posConstraint = Instance.new("AlignPosition")
--         posConstraint.Parent = cloneInstance
--         posConstraint.Attachment0 = att2
--         local att1 = assert(humanoid_root_part:FindFirstChild(SharedConfig.CLONE_ATTACHMENT_NAME):: Attachment)
--         posConstraint.Attachment1 = att1
--         posConstraint.ApplyAtCenterOfMass = true
--         posConstraint.Mode = Enum.PositionAlignmentMode.OneAttachment
--         posConstraint.RigidityEnabled = true
--     end
-- end

-- m.RemovePlayerCloneDummies = function(player_state: PSS.PlayerState)
--     local folder = workspace:FindFirstChild(SharedConfig.CLONES_DUMMY_FOLDER_NAME)
--     if not folder then
--         return
--     end
--     for _, child in folder:GetChildren() do
--         if child:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Clone]) == player_state.player_id then
--             child:Destroy()
--         end
--     end
-- end

return m
