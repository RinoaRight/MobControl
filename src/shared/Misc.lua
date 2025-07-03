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

local m = {}
m.__index = m

local blacklist = {} :: { Instance }

m.AddInstanceToRaycastFilter = function(instance)
    table.insert(blacklist, instance)
    -- if math.random() < 0.01 then
    --     local count = 0
    --     for _, instance in blacklist do
    --         count += 1
    --     end
    --     warn("~coolisions~ blacklist ", #blacklist, count)
    -- end
end

m.DefineEnemyY = function(enemyInstance: BasePart)
    local y = enemyInstance.Size.Y - enemyInstance.Size.Y / 2
    return y
end

m.ShowAnnouncement = function(text, announcementGui, fontFace: Enum.Font?)
    local textBox = assert(announcementGui:WaitForChild("ContainerFrame").Message) :: TextLabel
    if fontFace then
        textBox.FontFace = Font.fromEnum(fontFace)
    end
    textBox.Text = text
    announcementGui.Enabled = true
    Taskpool.defer(function()
        local t = .5
        local tweenInfo = TweenInfo.new(t)
        local origSize = UDim2.fromScale(1, 1)
        local targetSize = UDim2.fromScale(1, 1.3)
        local tween1 = TweenService:Create(textBox, tweenInfo, { Size = targetSize })
        local tween2 = TweenService:Create(textBox, tweenInfo, { Size = origSize })
        for i = 1, 2 do
            tween1:Play()
            task.wait(t)
            tween2:Play()
            task.wait(t)
        end
        announcementGui.Enabled = false
    end)
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

m.ShowCollidableHP = function(worldState, targetGuids, killables, weapon_id, guiName, guiTemplate)
    -- TODO: show HP for the targets that have been hit by the bullet
    for i, targetGuid in ipairs(targetGuids) do
        if not worldState:has(targetGuid) then
            continue
        end
        local targetRefId = worldState:get(targetGuid, W.RefId)
        if not targetRefId then
            continue
        end

        -- show gui only for enemies and obstacles
        if Id.kind(targetRefId) ~= Id.Kind.Enemy and Id.kind(targetRefId) ~= Id.Kind.Obstacle then
            continue
        end

        -- calculate new HP, it's not yet updated in the state
        local weaponDamage = S.Weapon[weapon_id].damage
        local targetcurrentHP = worldState:get(targetGuid, W.HP)
        if not targetcurrentHP then
            continue
        end
        local targetNewHP = targetcurrentHP - weaponDamage
        if targetNewHP <= 0 then
            targetNewHP = 0
        end

        local target = assert(killables[i]) :: BasePart

        local hpGui = (target:FindFirstChild(guiName) :: BillboardGui) or guiTemplate:Clone() :: BillboardGui
        hpGui.Parent = target
        hpGui.Adornee = target
        local textLabel = assert(hpGui:FindFirstChild("TextLabel") :: TextLabel)
        textLabel.Text = tostring(math.round(targetNewHP))
        textLabel.Visible = true

        -- set TTE for how much the gui should be shown
        worldState:set(targetGuid, W.ClientTTE, 2)
    end
end

m.SpawnExplosion = function(pos: Vector3, explosionSize: Vector3)
    local explosionInstance = Instance.new("Explosion")
    explosionInstance.Position = pos
    explosionInstance.BlastRadius = explosionSize.X * 3 --explosionSize.X / 2
    explosionInstance.BlastPressure = 0
    explosionInstance.ExplosionType = Enum.ExplosionType.NoCraters
    explosionInstance.DestroyJointRadiusPercent = 0
    explosionInstance.Parent = workspace
end

-- DEBUG:
-- local counters = table.create(5, 0)
-- local RC_COUNT = 1
-- local RC_TPC_PRE = 2
-- local RC_TPC_DO = 3
-- local RC_TPC_CALC = 4
-- local RC_TPC_WALL = 5
-- counters[RC_TPC_WALL] = os.clock()

-- local dump_counters = function()
--     local micro = 1e6
--     local total = counters[RC_COUNT]/micro -- for microseconds
--     print(fmt("~coolisions~ %d calls, %.3f pre, %.3f do, %.3f calc,",
--         total, counters[RC_TPC_PRE] / total, counters[RC_TPC_DO] / total, counters[RC_TPC_CALC] / total))
--     print("~coolisions~ II ", counters[RC_COUNT],
--         counters[RC_TPC_PRE]*micro, counters[RC_TPC_DO]*micro, counters[RC_TPC_CALC]*micro,
--         os.clock() - counters[RC_TPC_WALL])
--     counters[RC_COUNT] = 0
--     counters[RC_TPC_PRE] = 0
--     counters[RC_TPC_DO] = 0
--     counters[RC_TPC_CALC] = 0
--     counters[RC_TPC_WALL] = os.clock()
-- end

local blockcastParams = RaycastParams.new()
blockcastParams.FilterDescendantsInstances = blacklist
m.IsBulletCollidableToHit = function(bulletCFrame: CFrame, bulletRange: num, bulletSize: Vector3)
    -- counters[RC_COUNT] += 1
    -- local t = os.clock()
    -- local t0 = t
    -- local rayDirection = Vector3.new(0, 0, -bulletRange)
    local rayDirection = bulletCFrame.LookVector * bulletRange
    -- counters[RC_TPC_PRE] += os.clock() - t; t = os.clock()
    local blockcastResult = workspace:Blockcast(bulletCFrame, bulletSize, rayDirection, blockcastParams)
    -- counters[RC_TPC_DO] += os.clock() - t; t = os.clock()
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
        -- counters[RC_TPC_CALC] += os.clock() - t; t = os.clock()
    end
    -- if t0 - counters[RC_TPC_WALL] >= 1.0 then
    --     dump_counters()
    -- end
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

m.CloneOrPlayer = function(world_state, character: Model)
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

-- m.GetClonePos = function(pos: Vector3, alreadyInCol: int, row: int)
--     local dist = SharedConfig.INTERCLONES_DISTANCE
--     local new_pos = Vector3.new(pos.X, pos.Y, pos.Z + dist)
--     local x = 0
--     local z = dist

--     if alreadyInCol == 1 then
--         x = -dist
--     elseif alreadyInCol == 2 then
--         x = dist
--     elseif alreadyInCol == 3 then
--         x = -dist * 2
--     elseif alreadyInCol == 4 then
--         x = dist * 2
--     end
--     new_pos = Vector3.new(new_pos.X + x, new_pos.Y, new_pos.Z + z * row)
--     return new_pos
-- end

m.GetCloneCFrame = function(cFrame: CFrame, alreadyInCol: int, row: int)
    local dist = SharedConfig.INTERCLONES_DISTANCE + 1

    local sideOffset = 0
    local behindOffset = dist * row

    if alreadyInCol == 1 then
        sideOffset = -dist
    elseif alreadyInCol == 2 then
        sideOffset = dist
    elseif alreadyInCol == 3 then
        sideOffset = -dist * 2
    elseif alreadyInCol == 4 then
        sideOffset = dist * 2
    end

    local offset = -cFrame.LookVector * behindOffset + cFrame.RightVector * sideOffset

    return CFrame.new(cFrame.Position + offset, cFrame.Position + cFrame.LookVector)
end

m.GetCloneDummyPos = function(pos: Vector3, alreadyInCol: int, row: int)
    local dist = SharedConfig.INTERCLONES_DISTANCE
    local new_pos = Vector3.new(pos.X, pos.Y, pos.Z)
    local x = 0

    if alreadyInCol == 1 then
        x = -dist
    elseif alreadyInCol == 2 then
        x = dist
    elseif alreadyInCol == 3 then
        x = -dist * 2
    elseif alreadyInCol == 4 then
        x = dist * 2
    end
    new_pos = Vector3.new(new_pos.X + x, new_pos.Y, new_pos.Z)
    return new_pos
end

-- attach hitbox to the player == clones formation width
m.AttachHitboxToPlayer = function(player_state)
    local player_character = player_state.character
    local humanoid_root_part = player_state.root
    local hitbox = Instance.new("Part")
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
    m.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED_HIGH], root.Position, 0)
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
    local newCF
    if weapon_id == Id.Weapon.BASIC or weapon_id == Id.Weapon.SPRAYGUN then
        newCF = weldingSpot.CFrame * CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
    -- elseif weapon_id == Id.Weapon.ROCKET then
        -- newCF = weldingSpot.CFrame * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, math.rad(180), 0)
    else
        newCF = weldingSpot.CFrame * CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
    end
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
                local isClone, playerId = m.CloneOrPlayer(worldState, parentModel)
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
    local playerFunds = playerState:get(currencyId, C.ValuePers)
    if playerFunds >= itemPrice then
        return true
    end
    return false
end

function m.IsUpgradePreviousTier(upgradeId: int)
    -- TODO: other multi-tiered upgrades
    local previousTierId
    if
        (upgradeId <= Id.PlayerUpgradePersistent.FIREPOWER_5 and upgradeId > Id.PlayerUpgradePersistent.FIREPOWER_1)
        or (upgradeId <= Id.PlayerUpgradePersistent.HITPOINTS_5 and upgradeId > Id.PlayerUpgradePersistent.HITPOINTS_1)
        or (upgradeId <= Id.PlayerUpgradePersistent.INIT_CLONE_3 and upgradeId > Id.PlayerUpgradePersistent.INIT_CLONE_2)
    then
        previousTierId = upgradeId - 1
    end
    return previousTierId
end

function m.IsUpgradeNextTier(upgradeId: int)
    -- TODO: other multi-tiered upgrades
    local nextTierId
    if
        (upgradeId < Id.PlayerUpgradePersistent.FIREPOWER_5 and upgradeId >= Id.PlayerUpgradePersistent.FIREPOWER_1)
        or (upgradeId < Id.PlayerUpgradePersistent.HITPOINTS_5 and upgradeId >= Id.PlayerUpgradePersistent.HITPOINTS_1)
        or (upgradeId < Id.PlayerUpgradePersistent.INIT_CLONE_3 and upgradeId >= Id.PlayerUpgradePersistent.INIT_CLONE_1)
    then
        nextTierId = upgradeId + 1
    end
    return nextTierId
end

function m.IsFirepowerUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgradePersistent.FIREPOWER_1, Id.PlayerUpgradePersistent.FIREPOWER_5 do
        local flags = playerState.state:get(i, C.Bitset)
        local isActive = Id.flag_test(flags, Id.PlayerF.PERK_ACQUIRED)
        if isActive then
            id = i
        end
    end
    return id
end

function m.IsHpUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgradePersistent.HITPOINTS_1, Id.PlayerUpgradePersistent.HITPOINTS_5 do
        local flags = playerState.state:get(i, C.Bitset)
        local isActive = Id.flag_test(flags, Id.PlayerF.PERK_ACQUIRED)
        if isActive then
            id = i
        end
    end
    return id
end

function m.IsCloneUpgrade(playerState): int | nil
    local id
    for i = Id.PlayerUpgradePersistent.INIT_CLONE_1, Id.PlayerUpgradePersistent.INIT_CLONE_3 do
        local flags = playerState.state:get(i, C.Bitset)
        local isActive = Id.flag_test(flags, Id.PlayerF.PERK_ACQUIRED)
        if isActive then
            id = i
        end
    end
    return id
end

-- origin is a center-top
-- +-----O-----+ -Z   `O` is origin
-- |  1  |  2  |  ^
-- +-----+-----+  |
-- |  3  |  4  |  o---> X
-- +-----+-----+
function m.CreateGrid(cell_w: int, cell_h: int, cols: int, rows: int, origin: Vector3)
    -- spawns from top left corner
    local grid = table.create(cols * rows)
    local bitmap = table.create(#grid, false)
    local x_offset = origin.X - (cols * cell_w) // 2 + cell_w // 2
    local z_offset = origin.Z + cell_h // 2
    local X_SHIFT = cell_w // 4
    for ri = 1, rows do
        local dx = ri % 2 ~= 0 and X_SHIFT or -X_SHIFT
        for ci = 1, cols do
            local x = x_offset + (ci - 1) * cell_w + dx
            local z = z_offset + (ri - 1) * cell_h
            local pos = Vector3.new(x, origin.Y, z)
            grid[(ci - 1) * rows + ri] = pos
            bitmap[(ci - 1) * cell_h + ri] = false
        end
    end
    local rc2idx = function(row: int, col: int)
        return (row - 1) * cols + col
    end
    local idx2rc = function(idx: int)
        local row = math.floor((idx - 1) / cols) + 1
        local col = idx - (row - 1) * cols
        return row, col
    end
    return grid, bitmap, rc2idx, idx2rc
end

return m
