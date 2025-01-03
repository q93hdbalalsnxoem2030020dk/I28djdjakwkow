local plr = game.Players.LocalPlayer

local function replText(inst)
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then
        if inst.Text == "RAMPAGE" then
            inst.Text = "What am I?"
        end
    elseif inst:IsA("Frame") or inst:IsA("ScreenGui") then
        for _, child in pairs(inst:GetChildren()) do
            replText(child)
        end
    end
end

local function findReplace()
    local allInst = game:GetDescendants()

    for _, inst in pairs(allInst) do
        replText(inst)
    end
end

findReplace()

local tool1 = Instance.new("Tool")
tool1.Name = "避ける"
tool1.RequiresHandle = false
tool1.CanBeDropped = false
tool1.Parent = plr:WaitForChild("Backpack")

local anim1 = Instance.new("Animation")
anim1.AnimationId = "rbxassetid://13497875049"
local anim2 = Instance.new("Animation")
anim2.AnimationId = "rbxassetid://13499771836"

local sfx = Instance.new("Sound")
sfx.SoundId = "rbxassetid://14145620741"
sfx.Volume = 2
sfx.Parent = plr.Character:WaitForChild("HumanoidRootPart")

local msgSent = false

local function avoidIfAttacked()
    local char = plr.Character or plr.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart")

    if not hrp then return end

    for _, otherPlr in pairs(game.Players:GetPlayers()) do
        if otherPlr ~= plr and otherPlr.Character and otherPlr.Character:FindFirstChild("HumanoidRootPart") then
            local otherChar = otherPlr.Character
            local otherHRP = otherChar.HumanoidRootPart
            local myHRP = char.HumanoidRootPart

            local distance = (otherHRP.Position - myHRP.Position).Magnitude
            local facingDirection = (otherHRP.CFrame.LookVector:Dot((myHRP.Position - otherHRP.Position).Unit)) > 0.5
            local velocity = otherHRP.Velocity

            if distance < 20 and facingDirection and velocity.Magnitude >= 0.5 then
                local offset = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
                myHRP.CFrame = otherHRP.CFrame + offset
                sfx:Play()
            end
        end
    end
end

local function playAnims()
    tool1.Enabled = false

    local char = plr.Character or plr.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    
    local animTrack1 = hum:LoadAnimation(anim1)
    local animTrack2 = hum:LoadAnimation(anim2)

    animTrack1:Play()

    animTrack1.Stopped:Connect(function()
        if hrp then
            hrp.CFrame = hrp.CFrame - hrp.CFrame.LookVector * 20
            sfx:Play()

            if not msgSent then
                local args = {"e", "All"}
                game.ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(unpack(args))
                msgSent = true
            end

            animTrack2:Play()

            local dashDist = 20
            local dashSpd = 0.01
            local dashDur = 2
            local endTime = tick() + dashDur

            while tick() < endTime do
                local rightVec = hrp.CFrame.RightVector
                local offsetX = math.sin(tick() * math.pi * 100) * dashDist
                hrp.CFrame = hrp.CFrame + (rightVec * offsetX)
                wait(dashSpd)
            end

            animTrack2.Stopped:Connect(function()
                tool1.Enabled = true

                local avoidDur = 25
                local avoidEndTime = tick() + avoidDur

                while tick() < avoidEndTime do
                    avoidIfAttacked()
                    wait(0.1)
                end
            end)
        end
    end)
end

tool1.Activated:Connect(playAnims)

local tool2 = Instance.new("Tool")
tool2.Name = "颯爽と Speed"
tool2.RequiresHandle = false
tool2.CanBeDropped = false
tool2.Parent = plr:WaitForChild("Backpack")

local dashAnim = Instance.new("Animation")
dashAnim.AnimationId = "rbxassetid://13497875049"

local function dashEffect()
    tool2.Enabled = false

    local char = plr.Character or plr.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")

    local dashAnimTrack = hum:LoadAnimation(dashAnim)
    dashAnimTrack:Play()

    local dashTime = 2
    local dashEnd = tick() + dashTime

    while tick() < dashEnd do
        local rightVec = hrp.CFrame.RightVector
        local offsetX = math.sin(tick() * math.pi * 100) * 20
        hrp.CFrame = hrp.CFrame + (rightVec * offsetX)

        if hum.MoveDirection.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + (hum.MoveDirection.Unit * 5)
        end

        wait(0.05)
    end

    tool2.Enabled = true
end

tool2.Activated:Connect(dashEffect)

local tool3 = Instance.new("Tool")
tool3.Name = "ライト Speed"
tool3.RequiresHandle = false
tool3.CanBeDropped = false
tool3.Parent = plr:WaitForChild("Backpack")

local speed = Instance.new("Animation")
speed.AnimationId = "rbxassetid://13633468484" 

local function SpeedOfLight()
    tool3.Enabled = false
    
    local char = plr.Character or plr.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")

    local speedTrack = hum:LoadAnimation(speed)
    speedTrack:Play()

    local speedTime = 4
    local speedEnd = tick() + speedTime

    while tick() < speedEnd do
        if hum.MoveDirection.Magnitude > 0 then
            hum.WalkSpeed = 20
            hrp.CFrame = hrp.CFrame + (hum.MoveDirection.Unit * 8)
        end
        wait(0.05)

    end

    hum.WalkSpeed = 16
    tool3.Enabled = true
end

tool3.Activated:Connect(SpeedOfLight)
