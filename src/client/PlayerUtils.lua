--!strict
warn("[player-util] loaing")
assert(game:GetService("RunService"):IsClient(), `{script.Name} is a client module!`)

local TIMEOUT = 15 -- sec

-- Type definitions for interacting with Roblox's PlayerModule

export type PlayerModule = {
    GetControls: (PlayerModule) -> ControlModule,
    -- TODO: Add other methods
}

export type ControlModule = {
    activeController: BaseCharacterControllerType,
    humanoid: Humanoid,
    controlsEnabled: boolean,
    GetMoveVector: (ControlModule) -> Vector3,
    calculateRawMoveVector: (ControlModule, Humanoid, cameraRelativeMoveVector: Vector3) -> Vector3,
}

export type BaseCharacterControllerType = {
    GetMoveVector: (BaseCharacterControllerType) -> Vector3,
    IsMoveVectorCameraRelative: (BaseCharacterControllerType) -> boolean,
    GetIsJumping: (BaseCharacterControllerType) -> boolean,
    Enable: (BaseCharacterControllerType, enable: boolean) -> boolean,
    enabled: boolean,
}

-- Wait for the game to load
task.wait(5)

warn("[game] loaded")
local LocalPlayer: Player = game.Players.LocalPlayer or game.Players.PlayerAdded:Wait(TIMEOUT)
warn("[local-player] loaded")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", TIMEOUT) :: PlayerGui
warn("[player-gui] loaded")
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts", TIMEOUT) :: Instance
warn("[player-scripts] loaded")
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
warn("[character] loaded")
local Humanoid = Character:WaitForChild("Humanoid", TIMEOUT) :: Humanoid
warn("[humanoid] loaded")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", TIMEOUT) :: BasePart
warn("[humanoid-root-part] loaded")
local PlayerModule = require(PlayerScripts:WaitForChild("PlayerModule", TIMEOUT)) :: PlayerModule
assert(PlayerModule, "PlayerModule not found!")

local Controls = PlayerModule:GetControls()
assert(Controls, "PlayerModule does not have a ControlModule!")

-- @note: Will be inlined by the compiler, workaround for a strange type-checking bug
local function _get_active_controller(): BaseCharacterControllerType
    return Controls.activeController
end

--- @return Vector3 direction + aceeleration encoded as magnitude at [0, 1]
local function GetInputMoveVector(): Vector3
    if not (_get_active_controller().enabled and Controls.humanoid) then
        return Vector3.zero
    end
    local cameraRelative = _get_active_controller():IsMoveVectorCameraRelative()
    local moveVector = _get_active_controller():GetMoveVector()
    --[[
    if cameraRelative then
        moveVector = Controls:calculateRawMoveVector(Controls.humanoid, moveVector)
    end
    --]]
    -- we need to normalize acceleration if it's greater than 1.0, like when holding down two keys in WASD mode
    if moveVector.Magnitude > 1.0 then
        moveVector = moveVector.Unit
    end
    return moveVector
end

local function GetIsJumping(): boolean
    return _get_active_controller():GetIsJumping()
end

--- Predict where the player will be after deltaTime seconds based on current input
--- @param deltaTime number -- Time in seconds to predict ahead
--- @return Vector3 -- Predicted world position
local function GetPredictedPosition(deltaTime: number): Vector3
    local currentPosition = HumanoidRootPart.Position
    local inputVector = GetInputMoveVector()
    
    -- If no input, player stays in place
    if inputVector.Magnitude == 0 then
        return currentPosition
    end
    
    -- Get movement speed from humanoid
    local walkSpeed = Humanoid.WalkSpeed
    
    -- Calculate velocity based on input direction and walk speed
    local velocity = inputVector * walkSpeed
    
    -- Predict position: position = current + velocity * time
    local predictedPosition = currentPosition + (velocity * deltaTime)
    
    return predictedPosition
end

--- Get predicted position accounting for current velocity (more accurate)
--- @param deltaTime number -- Time in seconds to predict ahead
--- @return Vector3 -- Predicted world position
local function GetPredictedPositionWithVelocity(deltaTime: number): Vector3
    local currentPosition = HumanoidRootPart.Position
    local currentVelocity = HumanoidRootPart.AssemblyLinearVelocity
    local inputVector = GetInputMoveVector()
    
    -- Use current velocity as base, but factor in input for direction changes
    local velocity = currentVelocity
    
    -- If there's input, blend with intended direction
    if inputVector.Magnitude > 0 then
        local targetVelocity = inputVector * Humanoid.WalkSpeed
        -- Simple blend - you might want to adjust this based on your needs
        velocity = velocity:Lerp(targetVelocity, 0.5)
    end
    
    -- Predict position
    local predictedPosition = currentPosition + (velocity * deltaTime)
    
    return predictedPosition
end

warn("[PlayerUtil] Loaded")

return {
    Humanoid = Humanoid,
    HumanoidRootPart = HumanoidRootPart,
    LocalPlayer = LocalPlayer,
    PlayerGui = PlayerGui,
    PlayerScripts = PlayerScripts,
    Character = Character,
    Controls = Controls,
    PlayerModule = PlayerModule,
    GetInputMoveVector = GetInputMoveVector,
    GetIsJumping = GetIsJumping,
    GetPredictedPosition = GetPredictedPosition,
    GetPredictedPositionWithVelocity = GetPredictedPositionWithVelocity,
}
