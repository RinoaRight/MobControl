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
local log = Logger.create(script and script.Name or "Boosters"):set_prettifier(Id.pp):set_delimiter(" ")
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local W = SharedConfig.World.CId
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local workerMaid = disposer.new()
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local Misc = require(shared.Misc)
local S = require(shared.StaticData)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TaskPool = require(shared.TaskPool)
local SFX = require(script.Parent.SFX)
local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local ENEMIES_FOLDER = assert(workspace:WaitForChild("Enemies"))
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)
local TARGET_SIGN_TEMPLATE = assert(ReplicatedStorage:WaitForChild("TargetSign"))

local _maid = disposer.new()

local function flickerEnemy(guid: string, part: BasePart)
    local colorDark = Color3.fromHex("246b34")
    local colorBright = Color3.fromHex("37a24e")

    -- Start flickering
    local period = 5
    _maid[guid] = TaskPool.spawn(function()
        while true do
            -- Forward transition
            for i = 0, 1, 0.01 do
                part.Color = colorDark:Lerp(colorBright, i)
                task.wait(period / 200) -- period/2 divided by 100 steps
            end

            -- Backward transition
            for i = 1, 0, -0.01 do
                part.Color = colorDark:Lerp(colorBright, i)
                task.wait(period / 200) -- period/2 divided by 100 steps
            end
        end
    end)

    part.Destroying:Connect(function()
        _maid[guid] = nil
    end)
end

local function spawnEnemy(worldState: state.Replica, enemyGuid: string, enemyRefId: id, enemyInstance: BasePart)
    local enemyPos = worldState:get(enemyGuid, W.Position) :: Vector3
    enemyInstance.CanCollide = false
    enemyInstance.Anchored = true
    enemyInstance.CollisionGroup = "BulletCollidable"

    enemyInstance.Parent = ENEMIES_FOLDER
    enemyInstance.CFrame = CFrame.new(enemyPos)
    enemyInstance.Name = enemyGuid

    worldState:set(enemyGuid, W.ClientInstance, enemyInstance)
end

local function playTween(worldState, enemyGuid: string, tween: Tween)
    if worldState:has(enemyGuid) then -- check if the enemy is still in the world
        tween:Play()
    end
end

local function animateJump(worldState, enemyGuid: string, part: BasePart, humanoidRootPart: BasePart)
    assert(part and part:IsA("BasePart"), "Invalid part")
    local height = 18
    local animationDur = assert(S.Enemy[Id.Enemy.OCTOBOSS].animationDur)
    local durationDown = 0.3
    local durationUp = animationDur - durationDown
    local spinNum = 3
    local spinDuration = durationUp / spinNum
    local turnDuration = spinDuration / 3

    local originalPosition = part.Position
    local originalCFrame = part.CFrame
    local heightPerTurn = height / spinNum / 3
    local y = Misc.DefineObjectY(part)

    local baseRotation = originalCFrame - originalCFrame.Position -- Extract just the rotation part

    local spin1 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn, 0)) * baseRotation * CFrame.Angles(0, math.rad(120), 0),
    })
    local spin2 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 2, 0)) * baseRotation * CFrame.Angles(0, math.rad(240), 0),
    })
    local spin3 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 3, 0)) * baseRotation * CFrame.Angles(0, math.rad(360), 0),
    })
    local spin4 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 4, 0)) * baseRotation * CFrame.Angles(0, math.rad(120), 0),
    })
    local spin5 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 5, 0)) * baseRotation * CFrame.Angles(0, math.rad(240), 0),
    })
    local spin6 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 6, 0)) * baseRotation * CFrame.Angles(0, math.rad(360), 0),
    })
    local spin7 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 7, 0)) * baseRotation * CFrame.Angles(0, math.rad(120), 0),
    })
    local spin8 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 8, 0)) * baseRotation * CFrame.Angles(0, math.rad(240), 0),
    })
    local spin9 = TweenService:Create(part, TweenInfo.new(turnDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
        CFrame = CFrame.new(originalPosition + Vector3.new(0, heightPerTurn * 9, 0)) * baseRotation * CFrame.Angles(0, math.rad(360), 0),
    })

    worldState:set(enemyGuid, W.ClientFlags, true)

    -- spin the part
    spin1:Play()
    spin1.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin2)
    end)
    spin2.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin3)
    end)
    spin3.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin4)
    end)
    spin4.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin5)
    end)
    spin5.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin6)
    end)
    spin6.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin7)
    end)
    spin7.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin8)
    end)
    spin8.Completed:Connect(function()
        playTween(worldState, enemyGuid, spin9)
    end)
    spin9.Completed:Connect(function()
        -- TODO: VFX and SFX
        if worldState:has(enemyGuid) then -- check if the enemy is still in the world
            local newPos = worldState:get(enemyGuid, W.Position) :: Vector3
            local finalPos = Vector3.new(newPos.X, y, newPos.Z)

            -- Use a proxy to tween CFrame
            local proxy = Instance.new("CFrameValue")
            proxy.Value = part.CFrame

            proxy:GetPropertyChangedSignal("Value"):Connect(function()
                -- edit look vector to face the player
                local humPos = humanoidRootPart.Position
                local lookAt = Vector3.new(humPos.X, part.Position.Y, humPos.Z)
                local newCframe = CFrame.new(proxy.Value.Position, lookAt) * CFrame.Angles(0, math.pi, 0)
                part.CFrame = newCframe
            end)

            local tweenCFRame = TweenService:Create(proxy, TweenInfo.new(durationDown, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), {
                Value = CFrame.new(finalPos),
            })
            tweenCFRame:Play()

            tweenCFRame.Completed:Connect(function()
                -- play impact sound
                local localizedThump = S.Sound[Id.Sound.STOMP_LOCALIZED]
                Misc.SoundLocalizedAudio(localizedThump, part.Position, 0)

                proxy:Destroy()
                if worldState:has(enemyGuid) then -- check if the enemy is still in the world
                    worldState:set(enemyGuid, W.ClientFlags, false)
                end
            end)
        end
    end)
    -- end)
end

-- local unsubscribePart
local function subscribePart(part: BasePart, playerRootPart: BasePart)
    local partName = part.Name
    _maid[partName] = part.Touched:Connect(function(triggerer)
        if triggerer ~= playerRootPart then
            return
        end
        local sound = S.Sound[Id.Sound.HISS]
        if sound.Playing then
            return
        end
        SFX.PLAY_SOUND(sound, true)
        TaskPool.spawn(function()
            task.wait(1)
            sound:Stop()
        end)
        -- unsubscribePart(part, playerRootPart)
    end)
end

-- unsubscribePart = function(part: BasePart, playerRootPart: BasePart)
--     local partName = part.Name
--     _maid[partName] = part.TouchEnded:Connect(function(triggerer)
--         if triggerer ~= playerRootPart then
--             return
--         end
--         local sound = S.Sound[Id.Sound.HISS]
--         sound:Stop()
--         subscribePart(part, playerRootPart)
--     end)
-- end

local function animatePoisonBelt(worldState, poisonBelt: BasePart, playerRootPart: BasePart)
    local beltOrigin = poisonBelt.Position
    local normalizedOrigin = Vector3.new(beltOrigin.X, 0, beltOrigin.Z)
    local partFront = assert(poisonBelt:FindFirstChild("PartFront")) :: BasePart
    local partBack = assert(poisonBelt:FindFirstChild("PartBack")) :: BasePart
    local partLeft = assert(poisonBelt:FindFirstChild("PartLeft")) :: BasePart
    local partRight = assert(poisonBelt:FindFirstChild("PartRight")) :: BasePart
    -- -- subscribe parts to Touch to play a looped SFX, stop sound on TouchEnded and Destroying
    -- -- NOTE: since the poison belt is moving, we can't check for Touch and TouchEnded
    -- for _, part in { partFront, partBack, partLeft, partRight } do
    --     subscribePart(part, playerRootPart)
    --     part.Destroying:Connect(function()
    --         local sound = S.Sound[Id.Sound.HISS]
    --         sound:Stop()
    --         local partName = part.Name
    --         _maid[partName] = nil
    --     end)
    -- end
    local offset = 230
    local y = 9
    partFront.Position = Vector3.new(normalizedOrigin.X, y, normalizedOrigin.Z - offset)
    partBack.Position = Vector3.new(normalizedOrigin.X, y, normalizedOrigin.Z + offset)
    partLeft.Position = Vector3.new(normalizedOrigin.X - offset, y, normalizedOrigin.Z)
    partRight.Position = Vector3.new(normalizedOrigin.X + offset, y, normalizedOrigin.Z)
    local partHalfWidth = partFront.Size.Z / 2
    local originalSizeFront = partFront.Size
    local targetSize1 = 250
    local time1 = 90
    local size1 = Vector3.new(targetSize1, poisonBelt.Size.Y, targetSize1)
    local tweenInfoShrink1 = TweenInfo.new(time1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenShrink1 = TweenService:Create(poisonBelt, tweenInfoShrink1, { Size = size1 })
    local targetSize2 = 30
    local size2 = Vector3.new(targetSize2, poisonBelt.Size.Y, targetSize2)
    local time2 = 60
    local tweenInfoShrink2 = TweenInfo.new(time2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenShrink2 = TweenService:Create(poisonBelt, tweenInfoShrink2, { Size = size2 })
    local destinationFront1 = normalizedOrigin + Vector3.new(0, 0, -targetSize1 / 2 + partHalfWidth)
    local destinationBack1 = normalizedOrigin + Vector3.new(0, 0, targetSize1 / 2 - partHalfWidth)
    local destinationLeft1 = normalizedOrigin + Vector3.new(-targetSize1 / 2 + partHalfWidth, 0, 0)
    local destinationRight1 = normalizedOrigin + Vector3.new(targetSize1 / 2 - partHalfWidth, 0, 0)
    local destinationFront2 = normalizedOrigin + Vector3.new(0, 0, -targetSize2 / 2 + partHalfWidth)
    local destinationBack2 = normalizedOrigin + Vector3.new(0, 0, targetSize2 / 2 - partHalfWidth)
    local destinationLeft2 = normalizedOrigin + Vector3.new(-targetSize2 / 2 + partHalfWidth, 0, 0)
    local destinationRight2 = normalizedOrigin + Vector3.new(targetSize2 / 2 - partHalfWidth, 0, 0)
    local sizePart1 = Vector3.new(targetSize1, originalSizeFront.Y, originalSizeFront.Z)
    local sizePart2 = Vector3.new(targetSize2, originalSizeFront.Y, originalSizeFront.Z)
    local tweenInfoMoveFront1 = TweenInfo.new(time1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveFront1 = TweenService:Create(partFront, tweenInfoMoveFront1, { Position = destinationFront1, Size = sizePart1 })
    local tweenInfoMoveBack1 = TweenInfo.new(time1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveBack1 = TweenService:Create(partBack, tweenInfoMoveBack1, { Position = destinationBack1, Size = sizePart1 })
    local tweenInfoMoveLeft1 = TweenInfo.new(time1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveLeft1 = TweenService:Create(partLeft, tweenInfoMoveLeft1, { Position = destinationLeft1, Size = sizePart1 })
    local tweenInfoMoveRight1 = TweenInfo.new(time1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveRight1 = TweenService:Create(partRight, tweenInfoMoveRight1, { Position = destinationRight1, Size = sizePart1 })
    local tweenInfoMoveFront2 = TweenInfo.new(time2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveFront2 = TweenService:Create(partFront, tweenInfoMoveFront2, { Position = destinationFront2, Size = sizePart2 })
    local tweenInfoMoveBack2 = TweenInfo.new(time2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveBack2 = TweenService:Create(partBack, tweenInfoMoveBack2, { Position = destinationBack2, Size = sizePart2 })
    local tweenInfoMoveLeft2 = TweenInfo.new(time2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveLeft2 = TweenService:Create(partLeft, tweenInfoMoveLeft2, { Position = destinationLeft2, Size = sizePart2 })
    local tweenInfoMoveRight2 = TweenInfo.new(time2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
    local tweenMoveRight2 = TweenService:Create(partRight, tweenInfoMoveRight2, { Position = destinationRight2, Size = sizePart2 })
    TaskPool.spawn(function()
        tweenShrink1:Play()
        tweenMoveFront1:Play()
        tweenMoveBack1:Play()
        tweenMoveLeft1:Play()
        tweenMoveRight1:Play()
        tweenShrink1.Completed:Connect(function()
            tweenShrink2:Play()
            tweenMoveFront2:Play()
            tweenMoveBack2:Play()
            tweenMoveLeft2:Play()
            tweenMoveRight2:Play()
        end)
    end)
end

local m = {}

m.OnEnemyAdded = function(worldState: state.Replica, playerState: state.Replica, enemyGuid: string, isBoss: bool, drivingBoxBackPart: BasePart, playerRootPart: BasePart)
    local enemyRefId = worldState:get(enemyGuid, W.RefId)
    local enemyInstance
    if S.Enemy[enemyRefId].meshTemplate then
        enemyInstance = S.Enemy[enemyRefId].meshTemplate:Clone()
    else
        enemyInstance = Instance.new("Part")
        enemyInstance.Size = Vector3.new(2, 6, 2)
    end

    spawnEnemy(worldState, enemyGuid, enemyRefId, enemyInstance)

    if isBoss then
        -- if the enemy is a boss, attach the player's align constraint to the boss
        local bossAtt = Instance.new("Attachment") :: Attachment
        bossAtt.Parent = enemyInstance

        -- set player's align orientation constraint to the boss controller
        local character = LOCAL_PLAYER.Character
        local playerAlignOrient = character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
        if playerAlignOrient then
            playerAlignOrient.Attachment1 = bossAtt
        end

        -- spawn poison belt
        local poisonBelt = assert(ReplicatedStorage.VFX.PoisonBelt:Clone())
        local beltHeight = poisonBelt.Size.Y
        local currentGroundUnit = workspace.GroundUnits:FindFirstChild("3")
        local driverPos = drivingBoxBackPart.Position
        poisonBelt.Position = Vector3.new(driverPos.X, -beltHeight / 2 + 0.1, driverPos.Z - 50)
        poisonBelt.Parent = currentGroundUnit
        poisonBelt.Name = SharedConfig.POISON_BELT_NAME

        animatePoisonBelt(worldState, poisonBelt, playerRootPart)
    end
end

m.OnBossDestroyed = function(worldState, enemyGuid: string)
    local character = LOCAL_PLAYER.Character
    local playerAlignConst = character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
    if playerAlignConst then
        playerAlignConst.Attachment1 = nil
    end
    local poisonBelt = workspace.GroundUnits:FindFirstChild(SharedConfig.POISON_BELT_NAME, true)
    if poisonBelt then
        poisonBelt:Destroy()
    end
end

m.OnTTEReset = function(worldState: state.Replica, enemyGuid: string, refId: id, humanoidRootPart: BasePart)
    if refId == Id.Enemy.OCTOBOSS then
        local enemyInstance = worldState:get(enemyGuid, W.ClientInstance)
        if enemyInstance then
            animateJump(worldState, enemyGuid, enemyInstance, humanoidRootPart)
        end
    end
end

function m.OnEnemyHpDecreased(worldState: state.Replica, enemyGuid: string, enemyRefId: id, newHp: num, oldHp: num)
    local totalHp = S.Enemy[enemyRefId].health
    local hpNoArmor
    if S.Enemy[enemyRefId].armor then
        hpNoArmor = totalHp - assert(S.Enemy[enemyRefId].armor)
    end

    -- if the enemy is not supposed to have armor, do nothing
    if not hpNoArmor then
        return
    end

    -- if the armor has been depleted already, do nothing
    if oldHp < hpNoArmor then
        return
    end

    -- the armor has not yet been depleted, do nothing
    if newHp > hpNoArmor then
        return
    end

    local enemyInstance = worldState:get(enemyGuid, W.ClientInstance) :: MeshPart
    local newMeshInstance
    if S.Enemy[enemyRefId].meshTemplateNoArmor then
        newMeshInstance = S.Enemy[enemyRefId].meshTemplateNoArmor:Clone()
    end
    -- no new mesh template id was found in the database
    if not newMeshInstance then
        return
    end

    -- replace the mesh
    local sound
    if enemyRefId == Id.Enemy.CONEHEAD then
        sound = S.Sound[Id.Sound.POP_LOW]
    elseif enemyRefId == Id.Enemy.ZOMBUCKET then
        sound = S.Sound[Id.Sound.METAL_BUCKET]
    end
    if sound then
        SFX.PLAY_SOUND(sound)
    end

    spawnEnemy(worldState, enemyGuid, enemyRefId, enemyInstance)
    -- TODO: function is called, but spawns nothing (spawning may be meaningless, cuz the armorless doesn't live long enough).
    -- TODO: perhaps change just to sound only and play with speed
    -- TODO: Also sound is not played
end

return m
