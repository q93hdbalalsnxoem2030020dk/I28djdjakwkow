--// Settings
local hitboxSize = Vector3.new(8, 8, 8) -- Expanded hitbox size
local damage = 10 -- Damage dealt per hit

--// Variables
local player = game.Players.LocalPlayer
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

--// Functions
local function isValidProjectile(object)
    -- Advanced detection: Checks properties like velocity, trajectory, and naming
    if object:IsA("BasePart") then
        local isMoving = object.Velocity.Magnitude > 100 -- Threshold for movement speed
        local commonNames = { "bullet", "projectile", "knife", "ammo", "shell" }
        for _, name in ipairs(commonNames) do
            if object.Name:lower():find(name) then
                return true
            end
        end
        return isMoving
    end
    return false
end

local function getHitboxRegion(targetPlayer)
    if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local rootPart = targetPlayer.Character.HumanoidRootPart
        return Region3.new(
            rootPart.Position - hitboxSize / 2,
            rootPart.Position + hitboxSize / 2
        )
    end
    return nil
end

local function detectProjectileHit(projectile)
    for _, targetPlayer in ipairs(players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") then
            local humanoid = targetPlayer.Character.Humanoid
            local hitboxRegion = getHitboxRegion(targetPlayer)

            if hitboxRegion and hitboxRegion:ContainsPoint(projectile.Position) then
                humanoid:TakeDamage(damage)
                projectile:Destroy()
                return
            end
        end
    end
end

local function monitorProjectiles()
    workspace.ChildAdded:Connect(function(newObject)
        if isValidProjectile(newObject) then
            -- Track projectile's position in real-time
            local connection
            connection = runService.Heartbeat:Connect(function()
                if newObject and newObject.Parent then
                    detectProjectileHit(newObject)
                else
                    connection:Disconnect()
                end
            end)
        end
    end)
end

local function initializeHitboxes()
    for _, targetPlayer in ipairs(players:GetPlayers()) do
        if targetPlayer ~= player then
            targetPlayer.CharacterAdded:Connect(function()
                getHitboxRegion(targetPlayer)
            end)
        end
    end
end

--// Main
initializeHitboxes()
monitorProjectiles()
