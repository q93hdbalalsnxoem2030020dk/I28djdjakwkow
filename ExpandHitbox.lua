local hitboxSize = Vector3.new(8, 8, 8)
local damage = 10
local projectileLifetime = 10
local player = game.Players.LocalPlayer
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local runService = game:GetService("RunService")

local function createHitbox(targetPlayer)
    if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local rootPart = targetPlayer.Character.HumanoidRootPart
        local hitboxRegion = Region3.new(rootPart.Position - hitboxSize / 2, rootPart.Position + hitboxSize / 2)
        return hitboxRegion
    end
end

local function detectAmmoHit(ammo)
    local hitSuccessful = false
    for _, targetPlayer in ipairs(players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hitboxRegion = createHitbox(targetPlayer)
            if hitboxRegion:ContainsPoint(ammo.Position) then
                local humanoid = targetPlayer.Character:FindFirstChild("Humanoid")
                if humanoid then
                    humanoid:TakeDamage(damage)
                    ammo:Destroy()
                    hitSuccessful = true
                    break
                end
            end
        end
    end
end

local function detectDaHoodAmmo(ammo)
    if ammo.Parent and ammo.Parent:IsA("Tool") then
        local tool = ammo.Parent
        if tool.Name == "Gun" or tool.Name == "Rifle" then
            detectAmmoHit(ammo)
        end
    else
        detectAmmoHit(ammo)
    end
end

local function monitorProjectiles()
    workspace.ChildAdded:Connect(function(newObject)
        if newObject:IsA("BasePart") and newObject.Parent and newObject.Parent ~= player.Character then
            local timeout = projectileLifetime
            local ammo = newObject
            detectDaHoodAmmo(ammo)
            runService.Heartbeat:Connect(function()
                if ammo and ammo.Parent then
                    detectAmmoHit(ammo)
                end
            end)
            wait(timeout)
            if ammo and ammo.Parent then
                ammo:Destroy()
            end
        end
    end)
end

local function updatePlayerHitboxes()
    for _, targetPlayer in ipairs(players:GetPlayers()) do
        if targetPlayer ~= player and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Humanoid") then
            createHitbox(targetPlayer)
        end
    end
end

local function updateHitboxPositions()
    for _, targetPlayer in ipairs(players:GetPlayers()) do
        if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local rootPart = targetPlayer.Character.HumanoidRootPart
            local hitboxRegion = createHitbox(targetPlayer)
            runService.Heartbeat:Connect(function()
                if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    hitboxRegion = Region3.new(rootPart.Position - hitboxSize / 2, rootPart.Position + hitboxSize / 2)
                end
            end)
        end
    end
end

runService.RenderStepped:Connect(updatePlayerHitboxes)
monitorProjectiles()
players.PlayerAdded:Connect(function(newPlayer)
    newPlayer.CharacterAdded:Connect(function()
        updatePlayerHitboxes()
    end)
end)
