local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local mainGui = Instance.new("ScreenGui")
mainGui.Name = "MainWallhopGui"
mainGui.Parent = CoreGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 120, 0, 220)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.new(0, 0, 0)
mainFrame.BackgroundTransparency = 0.4
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = mainGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.new(0, 0, 0)
mainStroke.Thickness = 2
mainStroke.Parent = mainFrame

local mainTitle = Instance.new("TextLabel")
mainTitle.Size = UDim2.new(0, 120, 0, 20)
mainTitle.Position = UDim2.new(0, 0, 0, 5)
mainTitle.BackgroundTransparency = 1
mainTitle.Text = "Made by sxc_qq1"
mainTitle.TextColor3 = Color3.new(1, 1, 1)
mainTitle.TextScaled = true
mainTitle.Parent = mainFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 15, 0, 15)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.BackgroundColor3 = Color3.new(1, 0, 0)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextScaled = true
closeBtn.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeBtn

local iconFrame = Instance.new("TextButton")
iconFrame.Size = UDim2.new(0, 30, 0, 30)
iconFrame.Position = mainFrame.Position
iconFrame.BackgroundColor3 = Color3.new(0, 0, 0)
iconFrame.BackgroundTransparency = 0.9
iconFrame.BorderSizePixel = 0
iconFrame.Active = true
iconFrame.Draggable = true
iconFrame.Visible = false
iconFrame.Text = ""
iconFrame.Parent = mainGui

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0, 8)
iconCorner.Parent = iconFrame

local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.new(1, 1, 1)
iconStroke.Thickness = 2
iconStroke.Parent = iconFrame

local iconLabel = Instance.new("TextLabel")
iconLabel.Size = UDim2.new(1, 0, 1, 0)
iconLabel.BackgroundTransparency = 1
iconLabel.Text = "wh"
iconLabel.TextColor3 = Color3.new(1, 1, 1)
iconLabel.TextScaled = true
iconLabel.Parent = iconFrame

local function createBtn(name, pos)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 100, 0, 30)
    button.Position = pos
    button.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextScaled = true
    button.Text = name
    button.Parent = mainFrame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = button

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.new(0.5, 0.5, 0.5)
    btnStroke.Thickness = 2
    btnStroke.Parent = button

    return button
end

local vertBtn = createBtn("Movement flick: OFF", UDim2.new(0, 10, 0, 40))
local horzBtn = createBtn("WallHop: OFF", UDim2.new(0, 10, 0, 80))

local additionalLabel = Instance.new("TextLabel")
additionalLabel.Size = UDim2.new(0, 100, 0, 20)
additionalLabel.Position = UDim2.new(0, 10, 0, 110)
additionalLabel.BackgroundTransparency = 1
additionalLabel.Text = "Additional"
additionalLabel.TextColor3 = Color3.new(1, 1, 1)
additionalLabel.TextSize = 14
additionalLabel.Font = Enum.Font.GothamSemibold
additionalLabel.Parent = mainFrame

local shiftlockBtn = createBtn("Shiftlock", UDim2.new(0, 10, 0, 140))
local nonShiftlockBtn = createBtn("Non-Shiftlock", UDim2.new(0, 10, 0, 180))

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local human = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local cam = workspace.CurrentCamera

local vertActive = false
local horzActive = false
local isShiftlockUser = false
local isNonShiftlockUser = false
local hopTimer = 0
local isWallhopping = false
local lastHopTime = 0

local function refreshChar()
    char = player.Character or player.CharacterAdded:Wait()
    human = char:WaitForChild("Humanoid")
    root = char:WaitForChild("HumanoidRootPart")
end

player.CharacterAdded:Connect(refreshChar)

local function detectWall(dir, offset)
    local rayOrigin = root.Position + (offset or Vector3.new(0, 0, 0))
    local rayDirection = dir * 5
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {char}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
    return result
end

local function getWallNormal()
    local directions = {
        root.CFrame.LookVector,
        root.CFrame.RightVector,
        -root.CFrame.RightVector,
        root.CFrame.LookVector + root.CFrame.RightVector,
        root.CFrame.LookVector - root.CFrame.RightVector,
        -root.CFrame.LookVector,
        root.CFrame.LookVector + root.CFrame.RightVector * 0.5,
        root.CFrame.LookVector - root.CFrame.RightVector * 0.5,
    }
    for _, dir in ipairs(directions) do
        local result = detectWall(dir)
        if result then
            return result.Normal, dir
        end
    end
    return nil, nil
end

local function lockToWall(wallNormal)
    if wallNormal and isNonShiftlockUser then
        root.CFrame = CFrame.new(root.Position, root.Position - wallNormal)
    end
end

local function vertTurn()
    local wallNormal, hitDir = getWallNormal()
    if wallNormal then
        local origDir = root.CFrame.LookVector
        if isNonShiftlockUser then
            lockToWall(wallNormal)
            origDir = -wallNormal
        end
        local adjustAngle = math.acos(wallNormal:Dot(-hitDir)) - math.pi/2
        root.CFrame = root.CFrame * CFrame.Angles(0, adjustAngle, 0)
        task.wait(0.01)
        root.CFrame = CFrame.new(root.Position, root.Position + origDir)
    end
end

local function horzTurn()
    local wallNormal, hitDir = getWallNormal()
    if wallNormal then
        local origDir = root.CFrame.LookVector
        if isNonShiftlockUser then
            lockToWall(wallNormal)
            origDir = -wallNormal
        end
        local adjustAngle = math.acos(wallNormal:Dot(-hitDir)) - math.pi/2
        root.CFrame = root.CFrame * CFrame.Angles(0, adjustAngle, 0)
        task.wait(0.015)
        root.CFrame = CFrame.new(root.Position, root.Position + origDir)
    end
end

local function vertJump()
    if human:GetState() == Enum.HumanoidStateType.Freefall then
        isWallhopping = true
        lastHopTime = tick()
        vertTurn()
        human.Jump = true
        hopTimer = tick() + 0.1
        task.wait(0.1)
    end
end

local function horzJump()
    if human:GetState() == Enum.HumanoidStateType.Freefall then
        isWallhopping = true
        lastHopTime = tick()
        horzTurn()
        human.Jump = true
        hopTimer = tick() + 0.1
        task.wait(0.1)
    end
end

local zoomInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local isMinimized = false

closeBtn.MouseButton1Click:Connect(function()
    if not isMinimized then
        local startPos = mainFrame.Position
        mainFrame.Visible = false
        iconFrame.Position = startPos
        iconFrame.Visible = true
        TweenService:Create(iconFrame, zoomInfo, {Size = UDim2.new(0, 30, 0, 30)}):Play()
        isMinimized = true
    end
end)

iconFrame.MouseButton1Click:Connect(function()
    if isMinimized then
        local startPos = iconFrame.Position
        iconFrame.Visible = false
        mainFrame.Position = startPos
        mainFrame.Visible = true
        TweenService:Create(mainFrame, zoomInfo, {Size = UDim2.new(0, 120, 0, 220)}):Play()
        isMinimized = false
    end
end)

RunService.RenderStepped:Connect(function()
    if tick() < hopTimer then return end

    if isNonShiftlockUser then
        if isWallhopping then
            local wallNormal = getWallNormal()
            if wallNormal then
                lockToWall(wallNormal)
            end
            -- Check if free falling and no jump for 0.8 seconds
            if human:GetState() == Enum.HumanoidStateType.Freefall and tick() - lastHopTime > 0.8 then
                isWallhopping = false -- Stop flicking and unlock
            end
        end
    else
        -- For shiftlock users, reset isWallhopping immediately after hop
        if isWallhopping then
            isWallhopping = false
        end
    end

    local wallResult = detectWall(root.CFrame.LookVector)
    local edgeResult = detectWall(Vector3.new(1, 0, 0), Vector3.new(0, -2, 0))
    local fallSpeed = root.Velocity.Y

    if vertActive and wallResult and fallSpeed < -4 then
        vertJump()
    end

    if horzActive and edgeResult and fallSpeed < -4 then
        horzJump()
    end
end)

vertBtn.MouseButton1Click:Connect(function()
    vertActive = not vertActive
    if vertActive then
        vertBtn.Text = "Movement flick: ON"
        TweenService:Create(vertBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0, 1, 0)}):Play()
    else
        vertBtn.Text = "Movement flick: OFF"
        TweenService:Create(vertBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    end
end)

horzBtn.MouseButton1Click:Connect(function()
    horzActive = not horzActive
    if horzActive then
        horzBtn.Text = "WallHop: ON"
        TweenService:Create(horzBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(1, 1, 0)}):Play()
    else
        horzBtn.Text = "WallHop: OFF"
        TweenService:Create(horzBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    end
end)

shiftlockBtn.MouseButton1Click:Connect(function()
    isShiftlockUser = not isShiftlockUser
    isNonShiftlockUser = false
    if isShiftlockUser then
        shiftlockBtn.Text = "Shiftlock"
        nonShiftlockBtn.Text = "Non-Shiftlock"
        TweenService:Create(shiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0, 1, 0)}):Play()
        TweenService:Create(nonShiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    else
        shiftlockBtn.Text = "Shiftlock"
        TweenService:Create(shiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    end
end)

nonShiftlockBtn.MouseButton1Click:Connect(function()
    isNonShiftlockUser = not isNonShiftlockUser
    isShiftlockUser = false
    if isNonShiftlockUser then
        nonShiftlockBtn.Text = "Non-Shiftlock"
        shiftlockBtn.Text = "Shiftlock"
        TweenService:Create(nonShiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(1, 1, 0)}):Play()
        TweenService:Create(shiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    else
        nonShiftlockBtn.Text = "Non-Shiftlock"
        TweenService:Create(nonShiftlockBtn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)}):Play()
    end
end)