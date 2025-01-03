-- sxc_qq1
local Services = {
    RunService = game:GetService("RunService"),
    Players = game:GetService("Players"),
    Camera = game:GetService("Workspace").CurrentCamera
}

local Settings = {
    ["Tracer"] = {
        ["Color"] = Color3.fromRGB(255, 255, 255),
        ["Thickness"] = 1
    },
    ["Box"] = {
        ["Color"] = Color3.fromRGB(255, 255, 255),
        ["Thickness"] = 1,
        ["Size"] = Vector2.new(50, 50)
    },
    ["Highlight"] = {
        ["Color"] = Color3.fromRGB(255, 255, 255),
        ["FillTransparency"] = 0.7,
        ["OutlineTransparency"] = 0.2
    },
    ["Billboard"] = {
        ["TextColor"] = Color3.fromRGB(255, 255, 255),
        ["StudsOffset"] = Vector3.new(0, 3, 0),
        ["Size"] = UDim2.new(0, 100, 0, 25)
    }
}

local Functions = {}

Functions["CreateTracer"] = function(player)
    if player == Services.Players.LocalPlayer then return end
    local tracer = Drawing.new("Line")
    tracer.Color = Settings["Tracer"]["Color"]
    tracer.Thickness = Settings["Tracer"]["Thickness"]
    tracer.Transparency = 1
    return tracer
end

Functions["CreateBox"] = function(player)
    if player == Services.Players.LocalPlayer then return end
    local box = Drawing.new("Square")
    box.Color = Settings["Box"]["Color"]
    box.Thickness = Settings["Box"]["Thickness"]
    box.Filled = false
    box.Size = Settings["Box"]["Size"]
    box.Transparency = 1
    return box
end

Functions["CreateHighlight"] = function(character)
    local highlight = Instance.new("Highlight")
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Settings["Highlight"]["Color"]
    highlight.FillTransparency = Settings["Highlight"]["FillTransparency"]
    highlight.OutlineTransparency = Settings["Highlight"]["OutlineTransparency"]
    highlight.Parent = game:GetService("CoreGui")
    return highlight
end

Functions["CreateBillboard"] = function(player)
    if player == Services.Players.LocalPlayer then return end
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Adornee = player.Character:FindFirstChild("Head")
    billboardGui.Size = Settings["Billboard"]["Size"]
    billboardGui.StudsOffset = Settings["Billboard"]["StudsOffset"]
    billboardGui.AlwaysOnTop = true
    
    local textLabel = Instance.new("TextLabel", billboardGui)
    textLabel.Text = player.Name
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Settings["Billboard"]["TextColor"]
    textLabel.TextStrokeTransparency = 0
    
    billboardGui.Parent = game:GetService("CoreGui")
    return billboardGui
end

Functions["IsFacingPlayer"] = function(player)
    local localPlayer = Services.Players.LocalPlayer
    local character = localPlayer.Character
    if not character then return false end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart or not player.Character then return false end

    local playerPosition = player.Character:FindFirstChild("HumanoidRootPart").Position
    local direction = (playerPosition - humanoidRootPart.Position).unit
    local facingDirection = humanoidRootPart.CFrame.LookVector

    return (direction:Dot(facingDirection) > 0.5) -- 0.5 corresponds 60-degree
end

Functions["updateESP"] = function()
    for _, player in pairs(Services.Players:GetPlayers()) do
        if player ~= Services.Players.LocalPlayer and player.Character then
            local tracer = Functions["CreateTracer"](player)
            local box = Functions["CreateBox"](player)
            local highlight = Functions["CreateHighlight"](player.Character)
            local billboard = Functions["CreateBillboard"](player)

            Services.RunService.Heartbeat:Connect(function()
                if player.Character then
                    if Functions["IsFacingPlayer"](player) then
                        Functions["UpdateTracer"](tracer, player.Character)
                        Functions["UpdateBox"](box, player.Character)
                    else
                        tracer.Visible = false
                        box.Visible = false
                    end
                else
                    tracer.Visible = false
                    box.Visible = false
                end
            end)
        end
    end
end

Functions["MonitorPlayer"] = function(player)
    player.CharacterAdded:Connect(function(character)
        Functions["updateESP"]()
    end)
end

Services.Players.PlayerAdded:Connect(function(player)
    Functions["MonitorPlayer"](player)
end)

Functions["updateESP"]()