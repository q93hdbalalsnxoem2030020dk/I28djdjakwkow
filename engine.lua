local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer

-- Engine configuration
local config = {
    baseHorsepower = 1400,
    maxRPM = 6000,
    idleRPM = 800,
    movingThreshold = 0.5,
    -- Increased acceleration boost factor for auto acceleration
    autoAccelBoostFactor = 3.5  -- Increased from default for faster acceleration
}
config.torqueAtMaxRPM = config.baseHorsepower * 5252 / config.maxRPM
config.torqueCurveFactor = 0.8

-- State variables
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

-- Helper functions
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

-- Improved RPM calculation based on vehicle speed
local function calculateRPMFromSpeed(forwardSpeed)
    -- More responsive RPM calculation with better progression
    -- Use exponential curve for more realistic RPM behavior
    local normalizedSpeed = math.clamp(forwardSpeed / 200, 0, 1)
    local rpmRange = config.maxRPM - config.idleRPM
    
    -- Apply a quadratic curve to make RPM rise quickly at first then plateau near max
    local rpmFactor = math.pow(normalizedSpeed, 0.7)  -- Adjusted exponent for better curve
    local calculatedRPM = config.idleRPM + (rpmFactor * rpmRange)
    
    -- Add small variations to make it feel more realistic
    local jitter = math.random(-50, 50)
    
    return math.max(config.idleRPM, calculatedRPM + jitter)
end

local function updateRPMDisplay()
    if not ui.rpmBar or not ui.rpmText then return end
    
    local rpmPercentage = math.clamp((currentRPM - config.idleRPM) / (config.maxRPM - config.idleRPM), 0, 1)
    
    -- Update RPM text
    ui.rpmText.Text = math.floor(currentRPM) .. " RPM"
    
    -- Update bar size with tween
    local barGoal = {
        Size = UDim2.new(rpmPercentage, 0, 1, 0),
        BackgroundColor3 = (rpmPercentage < 0.7) and Color3.fromRGB(0, 255, 127) or
                         (rpmPercentage < 0.9) and Color3.fromRGB(255, 165, 0) or
                         Color3.fromRGB(255, 0, 0)
    }
    
    TweenService:Create(ui.rpmBar, TweenInfo.new(0.1), barGoal):Play()
end

-- Sound setup with improved reliability
local function setupSounds(car)
    if not car then return end
    
    -- Clean up existing sounds
    if sounds.engine then
        sounds.engine:Stop()
        sounds.engine:Destroy()
        sounds.engine = nil
    end
    
    if sounds.supercharger then
        sounds.supercharger:Stop()
        sounds.supercharger:Destroy()
        sounds.supercharger = nil
    end
    
    -- Create sound container
    local soundPart = car:FindFirstChild("EngineSoundPart")
    if not soundPart then
        soundPart = Instance.new("Part")
        soundPart.Name = "EngineSoundPart"
        soundPart.Transparency = 1
        soundPart.Anchored = true
        soundPart.CanCollide = false
        soundPart.Size = Vector3.new(1, 1, 1)
        soundPart.Parent = car
    end
    
    -- Position sound part in the front of the car
    local primaryPart = getMainPart(car)
    if primaryPart then
        soundPart.Position = primaryPart.Position + primaryPart.CFrame.LookVector * 3
    end
    
    -- Create engine sound with better properties
    sounds.engine = Instance.new("Sound")
    sounds.engine.Name = "EngineSound"
    sounds.engine.SoundId = "rbxassetid://7127584758" -- Engine sound
    sounds.engine.EmitterSize = 20
    sounds.engine.RollOffMode = Enum.RollOffMode.InverseTapered
    sounds.engine.RollOffMaxDistance = 100
    sounds.engine.RollOffMinDistance = 5
    sounds.engine.Volume = 0.8
    sounds.engine.Looped = true
    sounds.engine.Parent = soundPart
    
    -- Create supercharger sound
    sounds.supercharger = Instance.new("Sound")
    sounds.supercharger.Name = "SuperchargerSound"
    sounds.supercharger.SoundId = "rbxassetid://9043944885" -- Supercharger sound
    sounds.supercharger.EmitterSize = 15
    sounds.supercharger.RollOffMode = Enum.RollOffMode.InverseTapered
    sounds.supercharger.RollOffMaxDistance = 80
    sounds.supercharger.RollOffMinDistance = 3
    sounds.supercharger.Volume = 0.6
    sounds.supercharger.Looped = true
    sounds.supercharger.Parent = soundPart
    
    -- Ensure sounds are loaded before playing
    local function tryPlaySound(sound)
        if not sound.IsLoaded then
            sound.Loaded:Wait() -- Wait for the sound to load
        end
        if sound.Parent and engineActive then
            sound:Play()
        end
    end
    
    -- Play sounds if engine is active
    if engineActive then
        tryPlaySound(sounds.engine)
        tryPlaySound(sounds.supercharger)
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
            -- Update sound part position to follow the car
            if sounds.engine and sounds.engine.Parent then
                local soundPart = sounds.engine.Parent
                soundPart.Position = main.Position + main.CFrame.LookVector * 3
            end
            
            -- Auto-accelerate logic with enhanced speed
            if autoAccelerate and seat.Throttle == 0 then
                seat.Throttle = 1
            end
            
            if throttleActive then
                local currentVelocity = main.AssemblyLinearVelocity
                local forwardDir = seat.CFrame.LookVector
                local forwardSpeed = currentVelocity:Dot(forwardDir)

                -- Calculate RPM based on speed with improved method
                currentRPM = calculateRPMFromSpeed(forwardSpeed)
                
                -- Apply torque
                local torque = calculateTorque(currentRPM)
                local mass = main.AssemblyMass
                local speedScale = math.clamp(1 - (forwardSpeed / 220), 0.3, 1)  -- Adjusted speed range
                
                -- Apply additional boost factor for auto-accelerate
                local boostFactor = autoAccelerate and config.autoAccelBoostFactor or 1
                
                -- Calculate final impulse with boost factor
                local impulse = forwardDir * torque * speedScale * mass * dt * boostFactor
                
                main:ApplyImpulse(impulse)
            else
                -- More responsive RPM decrease when not accelerating
                currentRPM = math.max(config.idleRPM, currentRPM - 150)
            end
            
            -- Update sounds with improved response
            if sounds.engine then
                -- More dynamic pitch range for better sound
                sounds.engine.Pitch = math.clamp(0.5 + (currentRPM / config.maxRPM) * 1.5, 0.5, 2)
                if not sounds.engine.IsPlaying then sounds.engine:Play() end
            end
            
            if sounds.supercharger then
                -- Improved supercharger sound dynamics
                sounds.supercharger.Pitch = math.clamp(0.8 + (currentRPM / config.maxRPM) * 1.2, 1, 2)
                sounds.supercharger.Volume = math.clamp(0.3 + (currentRPM / config.maxRPM) * 0.5, 0.3, 0.8)
                if not sounds.supercharger.IsPlaying then sounds.supercharger:Play() end
            end
            
            -- Update UI
            updateRPMDisplay()
        end
    end)
end

-- UI Functions
local function toggleEngine()
    engineActive = not engineActive
    
    if engineActive then
        -- Turn on engine with enhanced visual feedback
        ui.engineBtn.ImageColor3 = Color3.fromRGB(255, 50, 50)
        TweenService:Create(ui.engineBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 48, 0, 48),
            BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        }):Play()
        
        local glowEffect = Instance.new("Frame")
        glowEffect.Name = "GlowEffect"
        glowEffect.Size = UDim2.new(1, 10, 1, 10)
        glowEffect.Position = UDim2.new(-0.125, 0, -0.125, 0)
        glowEffect.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        glowEffect.BackgroundTransparency = 0.7
        glowEffect.ZIndex = ui.engineBtn.ZIndex - 1
        glowEffect.Parent = ui.engineBtn
        
        TweenService:Create(glowEffect, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            BackgroundTransparency = 1
        }):Play()
        task.delay(0.5, function()
            if glowEffect then glowEffect:Destroy() end
        end)
        
        local seat = getVehicleSeat()
        if seat then
            local car = seat:FindFirstAncestorOfClass("Model")
            if car then
                setupSounds(car)
                boostThrottle(seat)
            end
        end
    else
        -- Turn off engine with smooth transition
        ui.engineBtn.ImageColor3 = Color3.fromRGB(0, 255, 127)
        TweenService:Create(ui.engineBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 40, 0, 40),
            BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        }):Play()
        
        -- Stop and clean up sounds
        if sounds.engine then
            sounds.engine:Stop()
            sounds.engine:Destroy()
            sounds.engine = nil
        end
        if sounds.supercharger then
            sounds.supercharger:Stop()
            sounds.supercharger:Destroy()
            sounds.supercharger = nil
        end
        
        currentRPM = config.idleRPM
        updateRPMDisplay()
        
        -- Disable auto-accelerate when engine is off
        if autoAccelerate then
            toggleAutoAccelerate()
        end
    end
end

local function toggleAutoAccelerate()
    autoAccelerate = not autoAccelerate
    
    if autoAccelerate then
        ui.autoBtn.ImageColor3 = Color3.fromRGB(255, 50, 50)
        TweenService:Create(ui.autoBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 45, 0, 45)}):Play()
    else
        ui.autoBtn.ImageColor3 = Color3.fromRGB(0, 200, 0)
        TweenService:Create(ui.autoBtn, TweenInfo.new(0.2), {Size = UDim2.new(0, 40, 0, 40)}):Play()
        
        -- Reset throttle
        local seat = getVehicleSeat()
        if seat and seat.Throttle > 0 then
            seat.Throttle = 0
        end
    end
end


local function createUI()
    -- Check if we already have a UI
    if ui.main and ui.main:IsDescendantOf(game) then
        ui.main:Destroy()
    end
    
    -- Make sure the player has a PlayerGui
    if not LP:FindFirstChild("PlayerGui") then
        return
    end
    
    -- Create or get the ScreenGui
    local screenGui = LP.PlayerGui:FindFirstChild("EngineBoostGui")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "EngineBoostGui"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = LP.PlayerGui
    end
    
    -- Create the main UI frame with a background and gradient
    ui.main = Instance.new("Frame")
    ui.main.Name = "EngineBoostUI"
    ui.main.Size = UDim2.new(0, 280, 0, 120)
    ui.main.Position = UDim2.new(0.5, -140, 0.05, 0)
    ui.main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    ui.main.BorderSizePixel = 0
    ui.main.Parent = screenGui
    
    -- Store original state for minimize/restore
    ui.originalSize = UDim2.new(0, 280, 0, 120)
    ui.originalPosition = ui.main.Position
    ui.isMinimized = false
    
    -- Add corner and gradient to main frame
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = ui.main
    
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 40, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 25))
    })
    gradient.Rotation = 45
    gradient.Parent = ui.main
    
    -- Create a top bar for title and close button
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 30)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    topBar.BorderSizePixel = 0
    topBar.Parent = ui.main
    
    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 10)
    topCorner.Parent = topBar
    
    -- Add corner modifier to fix bottom corners
    local cornerFix = Instance.new("Frame")
    cornerFix.Name = "CornerFix"
    cornerFix.Size = UDim2.new(1, 0, 0, 10)
    cornerFix.Position = UDim2.new(0, 0, 1, -10)
    cornerFix.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    cornerFix.BorderSizePixel = 0
    cornerFix.ZIndex = topBar.ZIndex
    cornerFix.Parent = topBar
    
    -- Title for the UI
    local titleText = Instance.new("TextLabel")
    titleText.Name = "Title"
    titleText.Size = UDim2.new(1, -60, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "ENGINE BOOST"
    titleText.Font = Enum.Font.GothamBlack
    titleText.TextColor3 = Color3.fromRGB(230, 230, 230)
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = topBar

    -- Close button
    local closeBtn = Instance.new("ImageButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -27, 0, 3)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Image = "rbxassetid://7733717646" -- X icon
    closeBtn.ImageColor3 = Color3.fromRGB(200, 200, 200)
    closeBtn.ScaleType = Enum.ScaleType.Fit
    closeBtn.Parent = topBar
    
    -- Minimize button
    local minimizeBtn = Instance.new("ImageButton")
    minimizeBtn.Name = "MinimizeButton"
    minimizeBtn.Size = UDim2.new(0, 24, 0, 24)
    minimizeBtn.Position = UDim2.new(1, -54, 0, 3)
    minimizeBtn.BackgroundTransparency = 1
    minimizeBtn.Image = "rbxassetid://7734056608" -- Minimize icon
    minimizeBtn.ImageColor3 = Color3.fromRGB(200, 200, 200)
    minimizeBtn.ScaleType = Enum.ScaleType.Fit
    minimizeBtn.Parent = topBar
    
    -- Create container for both buttons
    local buttonsContainer = Instance.new("Frame")
    buttonsContainer.Name = "ButtonsContainer"
    buttonsContainer.Size = UDim2.new(0, 130, 0, 60)
    buttonsContainer.Position = UDim2.new(0, 15, 0, 45)
    buttonsContainer.BackgroundTransparency = 1
    buttonsContainer.Parent = ui.main
    
    -- Create engine button with glow effect
    local engineHolder = Instance.new("Frame")
    engineHolder.Name = "EngineHolder"
    engineHolder.Size = UDim2.new(0, 60, 0, 60)
    engineHolder.Position = UDim2.new(0, 0, 0, 0)
    engineHolder.BackgroundTransparency = 1
    engineHolder.Parent = buttonsContainer
    
    -- Glow effect for engine button
    local engineGlow = Instance.new("ImageLabel")
    engineGlow.Name = "Glow"
    engineGlow.Size = UDim2.new(1.5, 0, 1.5, 0)
    engineGlow.Position = UDim2.new(0.5, -45, 0.5, -45)
    engineGlow.BackgroundTransparency = 1
    engineGlow.Image = "rbxassetid://7131300129" -- Glow effect
    engineGlow.ImageColor3 = Color3.fromRGB(0, 200, 0)
    engineGlow.ImageTransparency = 0.7
    engineGlow.ZIndex = 1
    engineGlow.Parent = engineHolder
    
    ui.engineBtn = Instance.new("ImageButton")
    ui.engineBtn.Name = "EngineButton"
    ui.engineBtn.Size = UDim2.new(0, 46, 0, 46)
    ui.engineBtn.Position = UDim2.new(0.5, -23, 0.5, -23)
    ui.engineBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    ui.engineBtn.ImageColor3 = Color3.fromRGB(0, 200, 0)
    ui.engineBtn.Image = "rbxassetid://7072707514" -- Power icon
    ui.engineBtn.ScaleType = Enum.ScaleType.Fit
    ui.engineBtn.BorderSizePixel = 0
    ui.engineBtn.ZIndex = 2
    ui.engineBtn.Parent = engineHolder
    
    -- Create auto-accelerate button with glow
    local autoHolder = Instance.new("Frame")
    autoHolder.Name = "AutoHolder"
    autoHolder.Size = UDim2.new(0, 60, 0, 60)
    autoHolder.Position = UDim2.new(0, 70, 0, 0)
    autoHolder.BackgroundTransparency = 1
    autoHolder.Parent = buttonsContainer
    
    -- Glow effect for auto button
    local autoGlow = Instance.new("ImageLabel")
    autoGlow.Name = "Glow"
    autoGlow.Size = UDim2.new(1.5, 0, 1.5, 0)
    autoGlow.Position = UDim2.new(0.5, -45, 0.5, -45)
    autoGlow.BackgroundTransparency = 1
    autoGlow.Image = "rbxassetid://7131300129" -- Glow effect
    autoGlow.ImageColor3 = Color3.fromRGB(0, 200, 0)
    autoGlow.ImageTransparency = 0.7
    autoGlow.ZIndex = 1
    autoGlow.Parent = autoHolder
    
    ui.autoBtn = Instance.new("ImageButton")
    ui.autoBtn.Name = "AutoButton"
    ui.autoBtn.Size = UDim2.new(0, 46, 0, 46)
    ui.autoBtn.Position = UDim2.new(0.5, -23, 0.5, -23)
    ui.autoBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    ui.autoBtn.ImageColor3 = Color3.fromRGB(0, 200, 0)
    ui.autoBtn.Image = "rbxassetid://7733658504" -- Speed icon
    ui.autoBtn.ScaleType = Enum.ScaleType.Fit
    ui.autoBtn.BorderSizePixel = 0
    ui.autoBtn.ZIndex = 2
    ui.autoBtn.Parent = autoHolder
    
    -- Add inner glow to buttons
    for _, btn in pairs({ui.engineBtn, ui.autoBtn}) do
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0) -- Makes it a circle
        corner.Parent = btn
        
        local innerStroke = Instance.new("UIStroke")
        innerStroke.Color = Color3.fromRGB(150, 150, 150)
        innerStroke.Thickness = 2
        innerStroke.Parent = btn
        
        local innerGlow = Instance.new("UIGradient")
        innerGlow.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))
        })
        innerGlow.Rotation = 135
        innerGlow.Parent = btn
    }
    
    -- Stylish labels for buttons
    local engineLabel = Instance.new("TextLabel")
    engineLabel.Size = UDim2.new(0, 60, 0, 20)
    engineLabel.Position = UDim2.new(0, 0, 0, -22)
    engineLabel.BackgroundTransparency = 1
    engineLabel.Text = "ENGINE"
    engineLabel.Font = Enum.Font.GothamBold
    engineLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    engineLabel.TextSize = 12
    engineLabel.Parent = engineHolder
    
    local autoLabel = Instance.new("TextLabel")
    autoLabel.Size = UDim2.new(0, 60, 0, 20)
    autoLabel.Position = UDim2.new(0, 0, 0, -22)
    autoLabel.BackgroundTransparency = 1
    autoLabel.Text = "AUTO"
    autoLabel.Font = Enum.Font.GothamBold
    autoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    autoLabel.TextSize = 12
    autoLabel.Parent = autoHolder
    
    -- Create modernized RPM meter
    local rpmFrame = Instance.new("Frame")
    rpmFrame.Name = "RPMMeter"
    rpmFrame.Size = UDim2.new(0, 120, 0, 24)
    rpmFrame.Position = UDim2.new(1, -135, 0.5, -12)
    rpmFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    rpmFrame.BorderSizePixel = 0
    rpmFrame.Parent = ui.main
    
    local rpmCorner = Instance.new("UICorner")
    rpmCorner.CornerRadius = UDim.new(0, 6)
    rpmCorner.Parent = rpmFrame
    
    -- Inner shadow effect for RPM meter
    local rpmInnerShadow = Instance.new("Frame")
    rpmInnerShadow.Size = UDim2.new(1, -4, 1, -4)
    rpmInnerShadow.Position = UDim2.new(0, 2, 0, 2)
    rpmInnerShadow.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    rpmInnerShadow.BorderSizePixel = 0
    rpmInnerShadow.ZIndex = 1
    rpmInnerShadow.Parent = rpmFrame
    
    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(0, 4)
    innerCorner.Parent = rpmInnerShadow
    
    ui.rpmBar = Instance.new("Frame")
    ui.rpmBar.Name = "RPMBar"
    ui.rpmBar.Size = UDim2.new(0, 0, 1, -6)
    ui.rpmBar.Position = UDim2.new(0, 3, 0, 3)
    ui.rpmBar.BackgroundColor3 = Color3.fromRGB(0, 255, 127)
    ui.rpmBar.BorderSizePixel = 0
    ui.rpmBar.ZIndex = 2
    ui.rpmBar.Parent = rpmInnerShadow
    
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 3)
    barCorner.Parent = ui.rpmBar
    
    -- Add gradient to RPM bar
    local barGradient = Instance.new("UIGradient")
    barGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 0.2)
    })
    barGradient.Rotation = 90
    barGradient.Parent = ui.rpmBar
    
    ui.rpmText = Instance.new("TextLabel")
    ui.rpmText.Name = "RPMText"
    ui.rpmText.Size = UDim2.new(1, 0, 1, 0)
    ui.rpmText.BackgroundTransparency = 1
    ui.rpmText.Text = config.idleRPM .. " RPM"
    ui.rpmText.Font = Enum.Font.GothamBold
    ui.rpmText.TextColor3 = Color3.fromRGB(230, 230, 230)
    ui.rpmText.TextSize = 14
    ui.rpmText.ZIndex = 3
    ui.rpmText.Parent = rpmFrame
    
    -- Add shadow effect
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
    
    -- Function to minimize the UI
    local function toggleMinimize()
        ui.isMinimized = not ui.isMinimized
        
        -- Store current position before minimizing
        if not ui.isMinimized then
            -- Restore original size and content
            TweenService:Create(ui.main, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = ui.originalSize,
                Position = ui.originalPosition
            }):Play()
            
            -- Wait for animation to complete before showing content
            task.delay(0.1, function()
                buttonsContainer.Visible = true
                rpmFrame.Visible = true
            end)
            
            -- Update minimize button icon
            minimizeBtn.Image = "rbxassetid://7734056608" -- Minimize icon
        else
            -- Store position before minimizing
            ui.originalPosition = ui.main.Position
            
            -- Hide content first
            buttonsContainer.Visible = false
            rpmFrame.Visible = false
            
            -- Minimize to a small square
            TweenService:Create(ui.main, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Size = UDim2.new(0, 50, 0, 50),
                Position = UDim2.new(ui.main.Position.X.Scale, ui.main.Position.X.Offset + 115, 
                                    ui.main.Position.Y.Scale, ui.main.Position.Y.Offset + 35)
            }):Play()
            
            -- Update minimize button icon
            minimizeBtn.Image = "rbxassetid://7733658504" -- Expand icon
        end
    end
    
    -- Make the UI draggable
    local dragging, dragStart, startPos = false, nil, nil
    
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = ui.main.Position
        end
    end)
    
    topBar.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            ui.main.Position = UDim2.new(
                startPos.X.Scale, 
                startPos.X.Offset + delta.X, 
                startPos.Y.Scale, 
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    topBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    -- Allow clicking on the minimized square to restore
    ui.main.InputBegan:Connect(function(input)
        if ui.isMinimized and 
           (input.UserInputType == Enum.UserInputType.MouseButton1 or 
            input.UserInputType == Enum.UserInputType.Touch) then
            toggleMinimize()
        end
    end)
    
    -- Connect button clicks
    closeBtn.MouseButton1Click:Connect(function()
        if ui.isMinimized then
            toggleMinimize() -- Restore first
            task.wait(0.3)   -- Wait for animation
        end
        
        -- Then minimize to tiny square
        TweenService:Create(ui.main, TweenInfo.new(0.3), {
            Size = UDim2.new(0, 30, 0, 30),
            Position = UDim2.new(ui.main.Position.X.Scale, ui.main.Position.X.Offset + 125, 
                                ui.main.Position.Y.Scale, ui.main.Position.Y.Offset + 45)
        }):Play()
        
        buttonsContainer.Visible = false
        rpmFrame.Visible = false
        titleText.Visible = false
        closeBtn.Visible = false
        minimizeBtn.Visible = false
        cornerFix.Visible = false
        
        ui.isMinimized = true
    end)
    
    minimizeBtn.MouseButton1Click:Connect(toggleMinimize)
    ui.engineBtn.MouseButton1Click:Connect(toggleEngine)
    ui.autoBtn.MouseButton1Click:Connect(toggleAutoAccelerate)
    
    -- Add hover effects for buttons
    for _, btn in pairs({ui.engineBtn, ui.autoBtn, closeBtn, minimizeBtn}) do
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {ImageTransparency = 0.1}):Play()
        end)
        
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {ImageTransparency = 0}):Play()
        end)
    end
    
    -- Update RPM display initially
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

-- Initialize and run
local function initialize()
    createUI()
    
    if LP.Character then
        onCharacterAdded(LP.Character)
    end
    LP.CharacterAdded:Connect(onCharacterAdded)
    
    -- Main loop
    coroutine.wrap(function()
        while true do
            task.wait(0.5)
            
            -- Check if in vehicle
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
                -- Turn off engine if not in vehicle
                toggleEngine()
            end
            
            -- Ensure UI exists
            if not ui.main or not ui.main:IsDescendantOf(game) then
                createUI()
            end
        end
    end)()
end

initialize()