--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local rendering = require(ReplicatedStorage.Game.rendering)
local interpolationBuffer = require(ReplicatedStorage.Game.rendering.interpolationBuffer)

--// PLAYER
local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart")
end)

--// MODULES (CACHE)
local Packets = require(ReplicatedStorage.Modules:WaitForChild("Packets"))

--// TIME
local function getServerTime()
    local ok, res = pcall(function()
        return require(ReplicatedStorage.Modules.Clock).getServerTime(true)
    end)
    return ok and res or tick()
end

--// TARGET LIST
local TargetList = {
    ["Gold Pot"] = {enabled = true, priority = 1},
    ["Golden Gold Pot"] = {enabled = true, priority = 2},
    ["Golden Mega Gold Pot"] = {enabled = true, priority = 3},
    ["Golden Omega Gold Pot"] = {enabled = true, priority = 4},
    ["Mega Gold Pot"] = {enabled = true, priority = 3},
    ["Omega Gold Pot"] = {enabled = true, priority = 4},
    ["Water Pot"] = {enabled = true, priority = 0},
    ["Empty Pot"] = {enabled = false, priority = 0},
}

--// SETTINGS
local AUTO_SWING = false
local STICK_TO_TARGET = false
local PLACE_POT = false
local MOVE_SPEED = 19

local lastSwing = 0

--// GUI
local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name = "PotFarmUI"

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 260, 0, 300)
frame.Position = UDim2.new(0.3, 0, 0.3, 0)
frame.BackgroundColor3 = Color3.fromRGB(25,25,25)
frame.BorderSizePixel = 0
Instance.new("UICorner", frame)

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1,0,0,25)
title.Text = "Target Farm"
title.TextColor3 = Color3.new(1,1,1)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 14

local function makeBtn(txt, y)
    local b = Instance.new("TextButton", frame)
    b.Size = UDim2.new(0.9,0,0,25)
    b.Position = UDim2.new(0.05,0,0,y)
    b.Text = txt
    b.BackgroundColor3 = Color3.fromRGB(40,40,40)
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    Instance.new("UICorner", b)
    return b
end

local swingBtn = makeBtn("Auto Swing: OFF", 30)
local placeBtn = makeBtn("Place Pots: OFF", 60)
local moveBtn = makeBtn("Move To Target: OFF", 90)
local speedBtn = makeBtn("Move Speed: 19", 120)

local listFrame = Instance.new("Frame", frame)
listFrame.Size = UDim2.new(1,0,0,160)
listFrame.Position = UDim2.new(0,0,0,130)
listFrame.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout", listFrame)
layout.Padding = UDim.new(0,5)

for name, data in pairs(TargetList) do
    local btn = Instance.new("TextButton", listFrame)
    btn.Size = UDim2.new(1,-10,0,22)
    btn.Text = name .. " [" .. (data.enabled and "ON" or "OFF") .. "]"
    btn.BackgroundColor3 = Color3.fromRGB(35,35,35)
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    Instance.new("UICorner", btn)

    btn.MouseButton1Click:Connect(function()
        data.enabled = not data.enabled
        btn.Text = name .. " [" .. (data.enabled and "ON" or "OFF") .. "]"
    end)
end

swingBtn.MouseButton1Click:Connect(function()
    AUTO_SWING = not AUTO_SWING
    swingBtn.Text = "Auto Swing: " .. (AUTO_SWING and "ON" or "OFF")
end)

placeBtn.MouseButton1Click:Connect(function()
    PLACE_POT = not PLACE_POT
    placeBtn.Text = "Place Pots: " .. (PLACE_POT and "ON" or "OFF")
end)

moveBtn.MouseButton1Click:Connect(function()
    STICK_TO_TARGET = not STICK_TO_TARGET
    moveBtn.Text = "Move To Target: " .. (STICK_TO_TARGET and "ON" or "OFF")
end)

speedBtn.MouseButton1Click:Connect(function()
    MOVE_SPEED += 1
    if MOVE_SPEED > 19 then MOVE_SPEED = 1 end
    speedBtn.Text = "Move Speed: " .. MOVE_SPEED
end)

--// ENTITY CACHE (NO MORE LAG 🔥)
local Entities = {}

local function isValidTarget(v)
    return v:IsA("Model") and v:GetAttribute("EntityID") and TargetList[v.Name]
end

for _, v in ipairs(workspace:GetDescendants()) do
    if isValidTarget(v) then
        Entities[#Entities+1] = v
    end
end

workspace.DescendantAdded:Connect(function(v)
    if isValidTarget(v) then
        Entities[#Entities+1] = v
    end
end)

workspace.DescendantRemoving:Connect(function(v)
    for i = #Entities, 1, -1 do
        if Entities[i] == v then
            table.remove(Entities, i)
        end
    end
end)

--// GET BEST TARGET
local function getBestTarget()
    local best, bestScore = nil, math.huge

    for _, v in ipairs(Entities) do
        local data = TargetList[v.Name]
        if data and data.enabled then
            local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
            if part then
                local dist = (root.Position - part.Position).Magnitude
                local score = dist - (data.priority * 25)

                if score < bestScore then
                    bestScore = score
                    best = v
                end
            end
        end
    end

    return best
end

--// MOVE
local function moveTo(target)
    if not target then return end

    local part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
    if not part then return end

    -- player references (grab them fresh so nothing is nil)
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then return end

    -- move slightly above the pot
    local targetPos = part.Position + Vector3.new(0, part.Size.Y/2 + 3, 0)

    local dist = (root.Position - targetPos).Magnitude
    if dist < 3 then return end

    -- THIS is the line that actually moves you
    humanoid:MoveTo(targetPos)

    -- jump if the pot is higher than you
    if targetPos.Y - root.Position.Y >= 0.1 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

--// SWING
local MAX_DISTANCE = 25
local SWING_COOLDOWN = 0.08

local function swingNearby()
    local now = getServerTime()
    if now - lastSwing < SWING_COOLDOWN then return end
    lastSwing = now

    local rootPos = root.Position

    local hits = {}
    local hitCount = 0

    for i = 1, #Entities do
        local v = Entities[i]
        local data = TargetList[v.Name]

        if data and data.enabled then
            local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
            if part then
                -- faster distance check (no Magnitude calculation)
                if (rootPos - part.Position).Magnitude <= MAX_DISTANCE then
                    local id = v:GetAttribute("EntityID")
                    if id then
                        hitCount += 1
                        hits[hitCount] = id
                    end
                end
            end
        end
    end

    if hitCount > 0 then
        Packets.SwingTool.send({
            entityIDs = hits,
            cframe = char:GetPivot(),
            timestamp = now,
            buffer = interpolationBuffer.getBuffer(rendering.clientBuffer)
        })
    end
end

--// FUNCTION
local function placeRandomPot()
    if not char or not root then return end

    -- random position around player
    local radius = math.random(4, 30) -- how far from player
    local angle = math.rad(math.random(0, 360))

    local offset = Vector3.new(
        math.cos(angle) * radius,
        0,
        math.sin(angle) * radius
    )

    local rayOrigin = root.Position + offset
    local rayDirection = Vector3.new(0, -200, 0)

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {char}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

    if result then
        local groundPos = result.Position

        Packets.PlaceStructure.send({
            cframe = CFrame.new(groundPos),
            buildingName = "Empty Pot"
        })
    end
end

--// LOOP (THROTTLED = BIG FPS BOOST)
local target
local lastTargetUpdate = 0

RunService.RenderStepped:Connect(function()
    local now = tick()

    if now - lastTargetUpdate > 0.12 then
        lastTargetUpdate = now
        target = getBestTarget()
    end

    if not target then return end

    if STICK_TO_TARGET and target then
        moveTo(target)
    end

    if PLACE_POT then
        placeRandomPot()
    end

    if AUTO_SWING then
        swingNearby()
    end
end)

--// OUTSIDE TOGGLE BUTTON (DRAGGABLE)
local toggleGui = Instance.new("ScreenGui", game.CoreGui)
toggleGui.Name = "PotFarm_Toggle"

local toggleBtn = Instance.new("TextButton", toggleGui)
toggleBtn.Size = UDim2.new(0, 120, 0, 30)
toggleBtn.Position = UDim2.new(0, 20, 0.5, 0)
toggleBtn.Text = "Hide UI"
toggleBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
Instance.new("UICorner", toggleBtn)

-- toggle logic
toggleBtn.MouseButton1Click:Connect(function()
    gui.Enabled = not gui.Enabled
    toggleBtn.Text = gui.Enabled and "Hide UI" or "Show UI"
end)

--// GENERIC DRAG FUNCTION (REUSABLE 🔥)
local function makeDraggable(obj)
    local dragging = false
    local dragStart = nil
    local startPos = nil

    local function update(input)
        local delta = input.Position - dragStart
        obj.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end

    obj.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            
            dragging = true
            dragStart = input.Position
            startPos = obj.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    obj.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                update(input)
            end
        end
    end)
end

--// APPLY DRAGGING
makeDraggable(toggleBtn)
makeDraggable(frame)
