--!strict
--!native
type str = string
type bool = boolean
type num = number
type positive = num
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.shared
local SharedConfig = require(shared.SharedConfig)
local Id = require(shared.Id)
local S = require(shared.StaticData)
local Taskpool = require(shared.TaskPool)
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local NumFormat = require(shared.num_format)
local Queue = require(shared.queue)
local rand = require(shared.rand)
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local W = SharedConfig.World.CId
local C = SharedConfig.PlayerState.CId
local state = require(shared.state)

local m = {}
m.__index = m

local blacklist = {} :: { Instance }

m.AddInstanceToRaycastFilter = function(instance)
    table.insert(blacklist, instance)
end

local function playFlickerAnim(textBox, mult, value, isToDestroy)
    Taskpool.spawn(function()
        local originalSize = textBox.Size :: UDim2
        local tweenIn =
            TweenService:Create(textBox, TweenInfo.new(0.1), { Size = UDim2.fromScale(originalSize.X.Scale * mult, originalSize.Y.Scale * mult) })
        local tweenOut = TweenService:Create(textBox, TweenInfo.new(0.1), { Size = originalSize })
        local isPlus = value >= 0
        local col = Color3.fromHex("55ff00")
        if not isPlus then
            col = Color3.fromHex("ff5500")
        end
        local formattedHp = NumFormat.format_number(value, nil, nil, true)
        if isPlus then
            formattedHp = "+" .. formattedHp
        end

        textBox.Text = formattedHp
        textBox.TextColor3 = col
        tweenIn:Play()
        task.wait(0.4)
        tweenOut:Play()
        task.wait(0.4)
        textBox.Text = SharedConfig.DEFAULT_HP_GUI_TEXT
        if isToDestroy then
            local gui = assert(textBox.Parent)
            gui:Destroy()
        end
    end)
end

m.FlickerPlayerHPGui = function(originalTextBox: TextLabel, mult: num, hp: num)
    local currentTextBox = originalTextBox
    local isToDestroy = false
    if currentTextBox.Text ~= SharedConfig.DEFAULT_HP_GUI_TEXT then
        local oldGiu = assert(currentTextBox.Parent)
        local newGuiIntance = oldGiu:Clone() :: BillboardGui
        newGuiIntance.Parent = oldGiu.Parent
        local oldExtentsOffset = newGuiIntance.ExtentsOffset
        local newY = newGuiIntance.ExtentsOffset.Y + 2
        newGuiIntance.ExtentsOffset = Vector3.new(oldExtentsOffset.X, newY, oldExtentsOffset.Z)
        currentTextBox = newGuiIntance:FindFirstChild("TextLabel") :: TextLabel
        isToDestroy = true
    end
    playFlickerAnim(currentTextBox, mult, hp, isToDestroy)
end

m.PlayCharacterAnim = function(character: Model, animId: str, isLooped: bool?)
    local humanoid = assert(character:WaitForChild("Humanoid"))
    local animator = humanoid:FindFirstChild("Animator") :: Animator
    local activeAnimTrack
    for _, animTrack in ipairs(animator:GetPlayingAnimationTracks()) do
        if animTrack.Animation.AnimationId == animId then
            activeAnimTrack = animTrack
            break
        end
    end

    if not activeAnimTrack then
        local animation = Instance.new("Animation")
        animation.AnimationId = animId
        local newHoldAnimTrack = animator:LoadAnimation(animation)
        activeAnimTrack = newHoldAnimTrack
    end

    if isLooped then
        activeAnimTrack.Looped = true
    end

    activeAnimTrack.Priority = Enum.AnimationPriority.Action4
    activeAnimTrack:Play(0.100000001, 1, 2)

    return activeAnimTrack
end

m.IsBulletCollidableToHit = function(bulletCFrame: CFrame, bulletRange: num, bulletSize: Vector3)
    local blockcastParams = RaycastParams.new()
    blockcastParams.FilterDescendantsInstances = blacklist
    local rayDirection = Vector3.new(0, 0, -bulletRange)
    local blockcastResult = workspace:Blockcast(bulletCFrame, bulletSize, rayDirection, blockcastParams)
    -- if "debug" then
    --     local ray = Instance.new("Part")
    --     ray.CanCollide = false
    --     ray.Parent = workspace
    --     ray.Anchored = true
    --     ray.Size = Vector3.new(0.1, 0.1, 2 * rayDirection.Magnitude)
    --     ray.CFrame = CFrame.new(pos, pos + rayDirection)
    --     Debris:AddItem(ray, 3)
    -- end
    local target = nil
    local distance
    local blockcastInstance
    if blockcastResult then
        blockcastInstance = blockcastResult.Instance
        -- if blockcastInstance:GetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.Boost]) then
        if blockcastInstance.CollisionGroup == SharedConfig.BULLET_COLLIDABLE_COLLISION_GROUP_NAME then
            target = blockcastInstance
            distance = (blockcastResult.Position - bulletCFrame.Position).Magnitude
        end
    end
    return target, distance
end

local partsInRadiusParams = OverlapParams.new()
partsInRadiusParams.FilterDescendantsInstances = blacklist
m.GetBulletCollidablesInRadius = function(cFrame, size)
    local instances = workspace:GetPartBoundsInBox(cFrame, size, partsInRadiusParams)
    local bulletCollidables = {}
    for _, instance in ipairs(instances) do
        if instance.CollisionGroup == SharedConfig.BULLET_COLLIDABLE_COLLISION_GROUP_NAME then
            table.insert(bulletCollidables, instance)
        end
    end
    return bulletCollidables
end

m.CloneOrLocalPlayer = function(world_state, character: Model)
    local isClone, playerId
    assert(character.Parent)
    if character.Parent.Name == SharedConfig.CLONES_FOLDER_NAME then
        isClone = true
        playerId = world_state:get(character.Name, W.PlayerId)
    elseif PlayerService:GetPlayerFromCharacter(character) then
        playerId = PlayerService:GetPlayerFromCharacter(character).UserId
    end
    return isClone, playerId
end

m.GetClonePos = function(pos: Vector3, alreadyInCol: int, row: int)
    local dist = SharedConfig.INTERCLONES_DISTANCE
    local new_pos = Vector3.new(pos.X, pos.Y, pos.Z + dist)
    local x = 0
    local z = dist

    if alreadyInCol == 1 then
        x = -dist
    elseif alreadyInCol == 2 then
        x = dist
    elseif alreadyInCol == 3 then
        x = -dist * 2
    elseif alreadyInCol == 4 then
        x = dist * 2
    end
    new_pos = Vector3.new(new_pos.X + x, new_pos.Y, new_pos.Z + z * row)
    return new_pos
end

-- attach hitbox to the player == clones formation width
m.AttachHitboxToPlayer = function(player_state)
    local player_character = player_state.character
    local humanoid_root_part = player_state.root
    local hitbox = Instance.new("Part")
    hitbox.Size = Vector3.new(5, 5, 5)
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.Anchored = false
    hitbox.CollisionGroup = "BulletNonCollidable"
    hitbox.Massless = true
    hitbox.Parent = player_character
    hitbox.CFrame = humanoid_root_part.CFrame
    local weld = Instance.new("WeldConstraint")
    weld.Parent = hitbox
    local rootPart = assert(player_state.root :: BasePart)
    weld.Part0 = rootPart
    weld.Part1 = hitbox
    hitbox.Name = SharedConfig.PLAYER_HITBOX_NAME
    hitbox.CanCollide = false
    local width = SharedConfig.INTERCLONES_DISTANCE * (SharedConfig.CLONES_IN_A_ROW - 1)
    hitbox.Size = Vector3.new(width, 6, 4)
end

m.SoundLocalizedAudio = function(audioEmitterTemplate, pos: Vector3, delay: num)
    Taskpool.defer(function()
        local audioEmitter = audioEmitterTemplate:Clone()
        audioEmitter.Parent = game.Workspace
        audioEmitter.Position = pos
        local aud = audioEmitter:FindFirstChildWhichIsA("Sound") :: Sound

        task.wait(delay)

        aud:Play()
        aud.Ended:Connect(function()
            audioEmitter:Destroy()
        end)
    end)
end

m.DestroyClientClone = function(character: Model)
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
    m.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED], root.Position, 0)
    character:Destroy()
end

m.EquipWeaponModel = function(char, weapon_id: int)
    local weapon_instance = S.Weapon[weapon_id].instance:Clone()
    -- spawn instance and parent it to the player
    local weldingSpot = char:FindFirstChild("RightHand") :: MeshPart
    local w = weldingSpot:FindFirstChild("WeldConstraint") :: WeldConstraint
    if not w then
        w = Instance.new("WeldConstraint", weldingSpot)
    end
    weapon_instance.Parent = weldingSpot
    weapon_instance.Name = S.Weapon[weapon_id].name
    local newCF = weldingSpot.CFrame * CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
    weapon_instance.PrimaryPart:PivotTo(newCF)
    w.Part0 = weldingSpot
    w.Part1 = weapon_instance.PrimaryPart
    return weapon_instance
end

m.IsPlayerHitByExplosion = function(worldState, explosionInstance: Explosion)
    local victimId

    -- set up a table to track the models hit
    local modelsHit = {}
    explosionInstance.Hit:Connect(function(part, distance)
        -- check if the local player is hit (NOTE: no friendly fire allowed)
        local parentModel = part.Parent
        if parentModel then
            -- check to see if this model has already been hit
            if modelsHit[parentModel] then
                return
            end
            -- log this model as hit
            modelsHit[parentModel] = true

            -- look for a humanoid
            local humanoid = parentModel:FindFirstChild("Humanoid")
            if humanoid then
                assert(parentModel:IsA("Model"))
                local isClone, playerId = m.CloneOrLocalPlayer(worldState, parentModel)
                if playerId and playerId == LOCAL_PLAYER.UserId then
                    if isClone then
                        -- player's clone was hit
                        m.DestroyClientClone(parentModel)
                        victimId = parentModel.Name
                    else
                        -- player themselves got hit by explosion
                        S.Sound[Id.Sound.SCREAM]:Play()
                        victimId = LOCAL_PLAYER.UserId
                    end
                end
            end
        end
    end)
    -- terminate subscription on the end of explosion
    explosionInstance.AncestryChanged:Connect(function()
        if not explosionInstance.Parent then
            explosionInstance:Destroy()
        end
    end)

    return victimId
end

local function onClickEvent(input, playerGui: StarterGui, ui_element: GuiObject, func, isOnElementClickedDo: boolean?)
    if
        input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.Gamepad1
    then
        local pos = input.Position
        local uiElementsClicked = playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y)

        -- there were some GUI elements at the click position
        if #uiElementsClicked > 0 then
            -- determine if the UI element has been clicked
            for _, obj in ipairs(uiElementsClicked) do
                if obj == ui_element then
                    if isOnElementClickedDo then
                        func()
                        return
                    else
                        return
                    end
                end
            end
        end

        -- no UI elements has been clicked
        if not isOnElementClickedDo then
            func()
        end
    end
end

function m.OnUIElementNotClickedDo(input, playerGui: StarterGui, ui_element: GuiObject, func)
    onClickEvent(input, playerGui, ui_element, func, false)
end

function m.OnUIElementClickedDo(input, playerGui: StarterGui, ui_element: GuiObject, func)
    onClickEvent(input, playerGui, ui_element, func, true)
end

function m.IsEnoughFunds(playerState, itemPrice: num, currencyId: int)
    local playerFunds = playerState:get(currencyId, C.Value)
    if playerFunds >= itemPrice then
        return true
    end
    return false
end

function m.IsUpgradePreviousTier(upgradeId: int)
    -- TODO: other multi-tiered upgrades
    local previousTierId
    if
        upgradeId <= Id.PlayerUpgrade.FIREPOWER_5 and upgradeId > Id.PlayerUpgrade.FIREPOWER_1
        or upgradeId <= Id.PlayerUpgrade.HITPOINTS_5 and upgradeId > Id.PlayerUpgrade.HITPOINTS_1
        or upgradeId <= Id.PlayerUpgrade.INIT_CLONE_3 and upgradeId > Id.PlayerUpgrade.INIT_CLONE_2
    then
        previousTierId = upgradeId - 1
    end
    return previousTierId
end

function m.IsUpgradeNextTier(upgradeId: int)
    -- TODO: other multi-tiered upgrades
    local nextTierId
    if
        upgradeId < Id.PlayerUpgrade.FIREPOWER_5 and upgradeId >= Id.PlayerUpgrade.FIREPOWER_1
        or upgradeId < Id.PlayerUpgrade.HITPOINTS_5 and upgradeId >= Id.PlayerUpgrade.HITPOINTS_1
        or upgradeId < Id.PlayerUpgrade.INIT_CLONE_3 and upgradeId >= Id.PlayerUpgrade.INIT_CLONE_1
    then
        nextTierId = upgradeId + 1
    end
    return nextTierId
end

function m.IsFirepowerUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgrade.FIREPOWER_1, Id.PlayerUpgrade.FIREPOWER_5 do
        if playerState.state:get(i, C.Value) then
            id = i
        end
    end
    return id
end

function m.IsHpUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgrade.HITPOINTS_1, Id.PlayerUpgrade.HITPOINTS_5 do
        if playerState:get(i, C.Value) then
            id = i
        end
    end
    return id
end

function m.IsCloneUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgrade.INIT_CLONE_1, Id.PlayerUpgrade.INIT_CLONE_3 do
        if playerState.state:get(i, C.Value) then
            id = i
        end
    end
    return id
end

return m
