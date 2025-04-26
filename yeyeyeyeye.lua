local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer

local config = {
    baseHorsepower = 1400,
    maxRPM = 7000,
    idleRPM = 800,
    movingThreshold = 0.5,
    autoAccelBoostFactor = 3.6
}
config.torqueAtMaxRPM = config.baseHorsepower * 5252 / config.maxRPM
config.torqueCurveFactor = 0.8

local engineActive = false
local autoAccelerate = false
local currentRPM = config.idleRPM
local throttleTracker = {}
local sounds = {
    engine = nil,
    supercharger = nil
}
local ui = {
    main = nil,
    engineBtn = nil,
    autoBtn = nil,
    rpmBar = nil,
    rpmText = nil
}
local prevPosition = nil

local function getMainPart(model)
    if model.PrimaryPart then return model.PrimaryPart end
    local bestPart, bestWeight = nil, 0
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part.Anchored == false then
            local weight = part:GetMass()
            if weight > bestWeight then
                bestWeight = weight
                bestPart = part
            end
        end
    end
    return bestPart
end

local function getVehicleSeat()
    local char = LP.Character
    if not char then return nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    local seat = hum.SeatPart
    if seat and seat:IsA("VehicleSeat") then return seat end
    return nil
end

local function calculateTorque(rpm)
    rpm = math.min(rpm, config.maxRPM)
    return config.torqueAtMaxRPM * (1 - (rpm - config.idleRPM) / config.maxRPM) * config.torqueCurveFactor
end

local function calculateRPMFromSpeed(forwardSpeed)

    local normalizedSpeed = math.clamp(forwardSpeed / 200, 0, 1)
    local rpmRange = config.maxRPM - config.idleRPM

    local rpmFactor = math.pow(normalizedSpeed, 0.7)
    local calculatedRPM = config.idleRPM + (rpmFactor * rpmRange)

    local jitter = math.random(-50, 50)

    return math.max(config.idleRPM, calculatedRPM + jitter)
end

local function updateRPMDisplay()
    if not ui.rpmBar or not ui.rpmText then return end

    local rpmPercentage = math.clamp((currentRPM - config.idleRPM) / (config.maxRPM - config.idleRPM), 0, 1)

    ui.rpmText.Text = math.floor(currentRPM) .. " RPM"

    local barGoal = {
        Size = UDim2.new(rpmPercentage, 0, 1, 0),
        BackgroundColor3 = (rpmPercentage < 0.7) and Color3.fromRGB(0, 255, 127) or
                         (rpmPercentage < 0.9) and Color3.fromRGB(255, 165, 0) or
                         Color3.fromRGB(255, 0, 0)
    }

    TweenService:Create(ui.rpmBar, TweenInfo.new(0.1), barGoal):Play()
end

local function setupSounds(car)
    if not car then return end

    if sounds.engine and sounds.engine.Parent then
        sounds.engine:Stop()
        sounds.engine:Destroy()
    end

    if sounds.supercharger and sounds.supercharger.Parent then
        sounds.supercharger:Stop()
        sounds.supercharger:Destroy()
    end

    local soundPart = car:FindFirstChild("EngineSoundPart")
    if not soundPart then
        soundPart = Instance.new("Part")
        soundPart.Name = "EngineSoundPart"
        soundPart.Transparency = 1
        soundPart.Anchored = false
        soundPart.CanCollide = false
        soundPart.Size = Vector3.new(1, 1, 1)
        soundPart.Parent = car

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = soundPart
        weld.Part1 = getMainPart(car)
        weld.Parent = soundPart
    end

    local primaryPart = getMainPart(car)
    if primaryPart then
        soundPart.Position = primaryPart.Position + primaryPart.CFrame.LookVector * 3
    end

    -- Updated V12 engine sound ID - more prominent V12 sound
    sounds.engine = Instance.new("Sound")
    sounds.engine.Name = "EngineSound"
    sounds.engine.SoundId = "rbxassetid://9114192565" -- V12 engine sound ID
    sounds.engine.EmitterSize = 20
    sounds.engine.RollOffMode = Enum.RollOffMode.InverseTapered
    sounds.engine.RollOffMaxDistance = 100
    sounds.engine.RollOffMinDistance = 5
    sounds.engine.Volume = 2 -- Reduced from 50 to more reasonable level
    sounds.engine.Looped = true
    sounds.engine.PlaybackSpeed = 0.8 -- Slightly lower pitch for deeper sound
    sounds.engine.Parent = soundPart

    -- Updated supercharger sound ID
    sounds.supercharger = Instance.new("Sound")
    sounds.supercharger.Name = "SuperchargerSound"
    sounds.supercharger.SoundId = "rbxassetid://138080021" -- Better supercharger whine
    sounds.supercharger.EmitterSize = 15
    sounds.supercharger.RollOffMode = Enum.RollOffMode.InverseTapered
    sounds.supercharger.RollOffMaxDistance = 80
    sounds.supercharger.RollOffMinDistance = 3
    sounds.supercharger.Volume = 0.5 -- Reduced from 30 to more reasonable level
    sounds.supercharger.Looped = true
    sounds.supercharger.Parent = soundPart

    -- Make sure both sounds play and can be heard
    if engineActive then
        -- Use PlayOnRemove = false to prevent issues when destroying sounds
        sounds.engine.PlayOnRemove = false
        sounds.supercharger.PlayOnRemove = false
        
        -- Add a small delay between playing sounds to prevent audio clipping
        sounds.engine:Play()
        delay(0.1, function()
            if sounds.supercharger and sounds.supercharger.Parent then
                sounds.supercharger:Play()
            end
        end)
        
        -- Set up DistanceEffect for better sound falloff
        local distanceEffect = Instance.new("DistortionSoundEffect")
        distanceEffect.Level = 0.1
        distanceEffect.Parent = sounds.engine
        
        local eqEffect = Instance.new("EqualizerSoundEffect")
        eqEffect.HighGain = 2
        eqEffect.MidGain = 1
        eqEffect.LowGain = 3 -- Emphasize bass for engine sound
        eqEffect.Parent = sounds.engine
    end
end

local function boostThrottle(seat)
    if throttleTracker[seat] then return end
    throttleTracker[seat] = true

    RunService.RenderStepped:Connect(function(dt)
        if not seat or not seat:IsDescendantOf(game) then return end

        local throttleActive = autoAccelerate or seat.Throttle ~= 0
        local car = seat:FindFirstAncestorOfClass("Model")
        local main = car and getMainPart(car)

        if main and engineActive then

            if sounds.engine and sounds.engine.Parent then
                local soundPart = sounds.engine.Parent
                soundPart.Position = main.Position + main.CFrame.LookVector * 3
            end

            if autoAccelerate and seat.Throttle == 0 then
                seat.Throttle = 1
            end

            if throttleActive then
                local currentVelocity = main.AssemblyLinearVelocity
                local forwardDir = seat.CFrame.LookVector
                local forwardSpeed = currentVelocity:Dot(forwardDir)

                currentRPM = calculateRPMFromSpeed(forwardSpeed)

                local torque = calculateTorque(currentRPM)
                local mass = main.AssemblyMass
                local speedScale = math.clamp(1 - (forwardSpeed / 220), 0.3, 1)

                local boostFactor = autoAccelerate and config.autoAccelBoostFactor or 1
                local impulse = forwardDir * torque * speedScale * mass * dt * boostFactor

                main:ApplyImpulse(impulse)
            else

                currentRPM = math.max(config.idleRPM, currentRPM - 150)
            end

            if sounds.engine then

                sounds.engine.Pitch = math.clamp(0.5 + (currentRPM / config.maxRPM) * 1.5, 0.5, 2)
                if not sounds.engine.IsPlaying then sounds.engine:Play() end
            end

            if sounds.supercharger then

                sounds.supercharger.Pitch = math.clamp(0.8 + (currentRPM / config.maxRPM) * 1.2, 1, 2)
                sounds.supercharger.Volume = math.clamp(0.3 + (currentRPM / config.maxRPM) * 0.5, 0.3, 0.8)
                if not sounds.supercharger.IsPlaying then sounds.supercharger:Play() end
            end

            updateRPMDisplay()
        end
    end)
end

local function toggleEngine()
    engineActive = not engineActive

    if engineActive then

        ui.engineBtn.ImageColor3 = Color3.fromRGB(0, 200, 0)
        TweenService:Create(ui.engineBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 45, 0, 45)}):Play()

        local seat = getVehicleSeat()
        if seat then
            local car = seat:FindFirstAncestorOfClass("Model")
            if car then
                setupSounds(car)
                boostThrottle(seat)
            end
        end
    else

        ui.engineBtn.ImageColor3 = Color3.fromRGB(255, 50, 30)
        TweenService:Create(ui.engineBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 40, 0, 40)}):Play()

        if sounds.engine then sounds.engine:Stop() end
        if sounds.supercharger then sounds.supercharger:Stop() end

        currentRPM = config.idleRPM
        updateRPMDisplay()

        if autoAccelerate then
            toggleAutoAccelerate()
        end
    end
end

local function toggleAutoAccelerate()
    autoAccelerate = not autoAccelerate

    if autoAccelerate then
        ui.autoBtn.ImageColor3 = Color3.fromRGB(0, 200, 0)
        TweenService:Create(ui.autoBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 45, 0, 45)}):Play()
    else
        ui.autoBtn.ImageColor3 = Color3.fromRGB(255, 50, 30)
        TweenService:Create(ui.autoBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 40, 0, 40)}):Play()

        local seat = getVehicleSeat()
        if seat and seat.Throttle > 0 then
            seat.Throttle = 0
        end
    end
end

local function createUI()

    if ui.main and ui.main:IsDescendantOf(game) then
        ui.main:Destroy()
    end

    if not LP:FindFirstChild("PlayerGui") then
        return
    end

    local screenGui = LP.PlayerGui:FindFirstChild("EngineBoostGui")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "EngineBoostGui"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = LP.PlayerGui
    end

    local isCollapsed = false
    local uiState = {
        engineActive = engineActive,
        autoAccelerate = autoAccelerate
    }

    ui.main = Instance.new("Frame")
    ui.main.Name = "EngineBoostUI"
    ui.main.Size = UDim2.new(0, 280, 0, 120)
    ui.main.Position = UDim2.new(0.5, -140, 0.05, 0)
    ui.main.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    ui.main.BackgroundTransparency = 0.2
    ui.main.BorderSizePixel = 0
    ui.main.Parent = screenGui

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    titleBar.BackgroundTransparency = 0.1
    titleBar.BorderSizePixel = 0
    titleBar.Parent = ui.main

    local titleGradient = Instance.new("UIGradient")
    titleGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 35, 45))
    }
    titleGradient.Rotation = 90
    titleGradient.Parent = titleBar

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "ENGINE BOOST                      | @sxc_qq1"
    titleText.Font = Enum.Font.GothamBold
    titleText.TextColor3 = Color3.fromRGB(220, 220, 240)
    titleText.TextSize = 16
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = ui.main

    local mainGradient = Instance.new("UIGradient")
    mainGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 35, 45)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 30))
    }
    mainGradient.Rotation = 45
    mainGradient.Parent = ui.main

    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, 0, 1, -30)
    contentFrame.Position = UDim2.new(0, 0, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = ui.main

    local buttonsContainer = Instance.new("Frame")
    buttonsContainer.Name = "ButtonsContainer"
    buttonsContainer.Size = UDim2.new(0, 140, 0, 70)
    buttonsContainer.Position = UDim2.new(0, 10, 0.5, -35)
    buttonsContainer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    buttonsContainer.BackgroundTransparency = 0.9
    buttonsContainer.BorderSizePixel = 0
    buttonsContainer.Parent = contentFrame

    local buttonContainerCorner = Instance.new("UICorner")
    buttonContainerCorner.CornerRadius = UDim.new(0, 12)
    buttonContainerCorner.Parent = buttonsContainer

    local engineHolder = Instance.new("Frame")
    engineHolder.Name = "EngineHolder"
    engineHolder.Size = UDim2.new(0, 65, 0, 70)
    engineHolder.Position = UDim2.new(0, 0, 0, 0)
    engineHolder.BackgroundTransparency = 1
    engineHolder.Parent = buttonsContainer

    ui.engineBtn = Instance.new("ImageButton")
    ui.engineBtn.Name = "EngineButton"
    ui.engineBtn.Size = UDim2.new(0, 45, 0, 45)
    ui.engineBtn.Position = UDim2.new(0.5, -22.5, 0.5, -15)
    ui.engineBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    ui.engineBtn.ImageColor3 = engineActive and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 50, 30)
    ui.engineBtn.Image = "rbxassetid://7072707514"
    ui.engineBtn.ScaleType = Enum.ScaleType.Fit
    ui.engineBtn.BorderSizePixel = 0
    ui.engineBtn.Parent = engineHolder

    local autoHolder = Instance.new("Frame")
    autoHolder.Name = "AutoHolder"
    autoHolder.Size = UDim2.new(0, 65, 0, 70)
    autoHolder.Position = UDim2.new(1, -65, 0, 0)
    autoHolder.BackgroundTransparency = 1
    autoHolder.Parent = buttonsContainer

    ui.autoBtn = Instance.new("ImageButton")
    ui.autoBtn.Name = "AutoButton"
    ui.autoBtn.Size = UDim2.new(0, 45, 0, 45)
    ui.autoBtn.Position = UDim2.new(0.5, -22.5, 0.5, -15)
    ui.autoBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    ui.autoBtn.ImageColor3 = autoAccelerate and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(255, 50, 30)
    ui.autoBtn.Image = "rbxassetid://7733658504"
    ui.autoBtn.ScaleType = Enum.ScaleType.Fit
    ui.autoBtn.BorderSizePixel = 0
    ui.autoBtn.Parent = autoHolder

    for _, btn in pairs({ui.engineBtn, ui.autoBtn}) do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = btn

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(130, 130, 160)
        stroke.Thickness = 2
        stroke.Parent = btn

        local glow = Instance.new("ImageLabel")
        glow.Size = UDim2.new(1.5, 0, 1.5, 0)
        glow.Position = UDim2.new(0.5, 0, 0.5, 0)
        glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.BackgroundTransparency = 1
        glow.Image = "rbxassetid://4996891970"
        glow.ImageColor3 = btn.ImageColor3
        glow.ImageTransparency = 0.7
        glow.ZIndex = -1
        glow.Parent = btn
    end

    local function createShadowText(parent, text, pos)

        local shadow = Instance.new("TextLabel")
        shadow.Size = UDim2.new(0, 65, 0, 20)
        shadow.Position = pos + UDim2.new(0, 1, 0, 1)
        shadow.BackgroundTransparency = 1
        shadow.Text = text
        shadow.Font = Enum.Font.GothamBold
        shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
        shadow.TextTransparency = 0.7
        shadow.TextSize = 12
        shadow.Parent = parent

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0, 65, 0, 20)
        label.Position = pos
        label.BackgroundTransparency = 1
        label.Text = text
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(220, 220, 240)
        label.TextSize = 12
        label.Parent = parent

        return label
    end

    createShadowText(engineHolder, "ENGINE", UDim2.new(0, 0, 0, -20))
    createShadowText(autoHolder, "AUTO", UDim2.new(0, 0, 0, -20))

    local rpmContainer = Instance.new("Frame")
    rpmContainer.Name = "RPMContainer"
    rpmContainer.Size = UDim2.new(0, 120, 0, 70)
    rpmContainer.Position = UDim2.new(1, -130, 0.5, -35)
    rpmContainer.BackgroundTransparency = 1
    rpmContainer.Parent = contentFrame

    createShadowText(rpmContainer, "                  'Speed", UDim2.new(0, 0, 0, 5))

    local rpmFrame = Instance.new("Frame")
    rpmFrame.Name = "RPMMeter"
    rpmFrame.Size = UDim2.new(0, 120, 0, 24)
    rpmFrame.Position = UDim2.new(0, 0, 0.5, 5)
    rpmFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    rpmFrame.BorderSizePixel = 0
    rpmFrame.Parent = rpmContainer

    local rpmCorner = Instance.new("UICorner")
    rpmCorner.CornerRadius = UDim.new(0, 6)
    rpmCorner.Parent = rpmFrame

    local rpmStroke = Instance.new("UIStroke")
    rpmStroke.Color = Color3.fromRGB(60, 60, 80)
    rpmStroke.Thickness = 1
    rpmStroke.Parent = rpmFrame

    for i = 1, 10 do
        local tick = Instance.new("Frame")
        tick.Size = UDim2.new(0, 1, 0.7, 0)
        tick.Position = UDim2.new(i/10, -1, 0.15, 0)
        tick.BackgroundColor3 = Color3.fromRGB(120, 120, 140)
        tick.BackgroundTransparency = 0.5
        tick.BorderSizePixel = 0
        tick.Parent = rpmFrame
    end

    ui.rpmBar = Instance.new("Frame")
    ui.rpmBar.Name = "RPMBar"
    ui.rpmBar.Size = UDim2.new((currentRPM - config.idleRPM) / (config.maxRPM - config.idleRPM), 0, 1, 0)
    ui.rpmBar.Position = UDim2.new(0, 0, 0, 0)
    ui.rpmBar.BackgroundColor3 = Color3.fromRGB(0, 255, 127)
    ui.rpmBar.BorderSizePixel = 0
    ui.rpmBar.Parent = rpmFrame

    local rpmGradient = Instance.new("UIGradient")
    rpmGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 220, 100)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(220, 180, 0)),
        ColorSequenceKeypoint.new(0.9, Color3.fromRGB(220, 80, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
    }
    rpmGradient.Parent = ui.rpmBar

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 6)
    barCorner.Parent = ui.rpmBar

    ui.rpmText = Instance.new("TextLabel")
    ui.rpmText.Name = "RPMText"
    ui.rpmText.Size = UDim2.new(1, 0, 1, 0)
    ui.rpmText.BackgroundTransparency = 1
    ui.rpmText.Text = math.floor(currentRPM) .. " RPM"
    ui.rpmText.Font = Enum.Font.GothamSemibold
    ui.rpmText.TextColor3 = Color3.fromRGB(255, 255, 255)
    ui.rpmText.TextSize = 14
    ui.rpmText.TextStrokeTransparency = 0.7
    ui.rpmText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    ui.rpmText.Parent = rpmFrame

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.7
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.ZIndex = -1
    shadow.Parent = ui.main

    local miniUI = Instance.new("Frame")
    miniUI.Name = "MiniUI"
    miniUI.Size = UDim2.new(0, 50, 0, 50)
    miniUI.Position = ui.main.Position
    miniUI.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    miniUI.BackgroundTransparency = 0.2
    miniUI.BorderSizePixel = 0
    miniUI.Visible = false
    miniUI.Parent = screenGui

    local miniCorner = Instance.new("UICorner")
    miniCorner.CornerRadius = UDim.new(0, 8)
    miniCorner.Parent = miniUI

    local miniIcon = Instance.new("ImageLabel")
    miniIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
    miniIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    miniIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    miniIcon.BackgroundTransparency = 1
    miniIcon.Image = "rbxassetid://7072707514"
    miniIcon.ImageColor3 = Color3.fromRGB(220, 220, 240)
    miniIcon.ScaleType = Enum.ScaleType.Fit
    miniIcon.Parent = miniUI

    local miniGlow = Instance.new("ImageLabel")
    miniGlow.Size = UDim2.new(1.3, 0, 1.3, 0)
    miniGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
    miniGlow.AnchorPoint = Vector2.new(0.5, 0.5)
    miniGlow.BackgroundTransparency = 1
    miniGlow.Image = "rbxassetid://4996891970"
    miniGlow.ImageColor3 = engineActive and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 200, 0)
    miniGlow.ImageTransparency = 0.7
    miniGlow.ZIndex = -1
    miniGlow.Parent = miniUI

    local miniShadow = Instance.new("ImageLabel")
    miniShadow.Size = UDim2.new(1, 20, 1, 20)
    miniShadow.Position = UDim2.new(0, -10, 0, -10)
    miniShadow.BackgroundTransparency = 1
    miniShadow.Image = "rbxassetid://1316045217"
    miniShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    miniShadow.ImageTransparency = 0.7
    miniShadow.ScaleType = Enum.ScaleType.Slice
    miniShadow.SliceCenter = Rect.new(10, 10, 118, 118)
    miniShadow.ZIndex = -1
    miniShadow.Parent = miniUI

    local function makeDraggable(frame)
        local dragging, dragStart, startPos = false, nil, nil

        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
            end
        end)

        frame.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )

                if frame == ui.main then
                    miniUI.Position = frame.Position
                else

                    ui.main.Position = frame.Position
                end
            end
        end)

        frame.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    makeDraggable(ui.main)
    makeDraggable(miniUI)

    ui.engineBtn.MouseButton1Click:Connect(toggleEngine)
    ui.autoBtn.MouseButton1Click:Connect(toggleAutoAccelerate)

    for _, btn in pairs({ui.engineBtn, ui.autoBtn}) do
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(45, 45, 60)}):Play()
        end)

        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(30, 30, 45)}):Play()
        end)
    end

    spawn(function()
        while true do
            if miniUI.Visible then
                TweenService:Create(miniIcon, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Size = UDim2.new(0.65, 0, 0.65, 0)
                }):Play()
                wait(1)
                TweenService:Create(miniIcon, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Size = UDim2.new(0.7, 0, 0.7, 0)
                }):Play()
                wait(1)
            else
                wait(0.5)
            end
        end
    end)

    updateRPMDisplay()
    return ui.main
end

local function onCharacterAdded(character)
    if character then
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
        if humanoidRootPart then
            prevPosition = humanoidRootPart.Position
        end
    end
end

local function initialize()
    createUI()

    if LP.Character then
        onCharacterAdded(LP.Character)
    end
    LP.CharacterAdded:Connect(onCharacterAdded)

    coroutine.wrap(function()
        while true do
            task.wait(0.5)

            local seat = getVehicleSeat()
            if seat then
                local car = seat:FindFirstAncestorOfClass("Model")
                if car then
                    if engineActive then
                        setupSounds(car)
                        boostThrottle(seat)
                    end
                end
            elseif engineActive then

                toggleEngine()
            end

            if not ui.main or not ui.main:IsDescendantOf(game) then
                createUI()
            end
        end
    end)()
end

initialize()
