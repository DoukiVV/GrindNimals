local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local targets = {}
local queued = false

local excluded = {TouchGui = true, Freecam = true, EggCareClickCursorGui = true}
local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function fitTarget(object, state)
    if not object.Parent then return end
    local parentSize = object.Parent.AbsoluteSize
    if parentSize.X < 1 or parentSize.Y < 1 then return end
    local size = object.Size
    local width = parentSize.X * size.X.Scale + size.X.Offset
    local height = parentSize.Y * size.Y.Scale + size.Y.Offset
    if width <= 0 or height <= 0 then return end
    local scale = state.scale
    if not scale.Parent then return end
    if math.abs(scale.Scale - state.applied) > 0.0001 then
        state.requested = scale.Scale
    end
    local anchor = object.AnchorPoint
    local position = object.Position
    local x = parentSize.X * position.X.Scale + position.X.Offset
    local y = parentSize.Y * position.Y.Scale + position.Y.Offset
    local availableWidth = math.max(1, parentSize.X - 20)
    local availableHeight = math.max(1, parentSize.Y - 20)
    -- Preserve authored positions and slide animations; only fit anchored panels.
    if x >= 0 and x <= parentSize.X then
        if anchor.X > 0 then availableWidth = math.min(availableWidth, math.max(1, x - 10) / anchor.X) end
        if anchor.X < 1 then availableWidth = math.min(availableWidth, math.max(1, parentSize.X - x - 10) / (1 - anchor.X)) end
    end
    if y >= 0 and y <= parentSize.Y then
        if anchor.Y > 0 then availableHeight = math.min(availableHeight, math.max(1, y - 10) / anchor.Y) end
        if anchor.Y < 1 then availableHeight = math.min(availableHeight, math.max(1, parentSize.Y - y - 10) / (1 - anchor.Y)) end
    end
    state.applied = math.min(state.requested, availableWidth / width, availableHeight / height)
    if math.abs(scale.Scale - state.applied) > 0.0001 then scale.Scale = state.applied end
end

local function fit(object)
    if targets[object] then return end
    local scale = object:FindFirstChild("ResponsiveScale")
        or object:FindFirstChild("ContentScale")
        or object:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "ViewportFitScale"
        scale.Parent = object
    end
    local state = {scale = scale, requested = scale.Scale, applied = scale.Scale, connections = {}}
    targets[object] = state
    local function update() fitTarget(object, state) end
    for _, property in {"Size", "Position", "AnchorPoint"} do
        table.insert(state.connections, object:GetPropertyChangedSignal(property):Connect(update))
    end
    table.insert(state.connections, scale:GetPropertyChangedSignal("Scale"):Connect(update))
    table.insert(state.connections, object.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(update))
    table.insert(state.connections, object.Destroying:Connect(function()
        for _, connection in state.connections do connection:Disconnect() end
        targets[object] = nil
    end))
    update()
end

local function place(object, size, position, anchor)
    if not object or not object:IsA("GuiObject") then return end
    object.AnchorPoint = anchor
    object.Size = size
    object.Position = position
end

local function layoutHud()
    local view = viewport()
    local compact = view.X < 1000 or view.Y < 600
    local button = compact and 48 or 64
    local hud = playerGui:FindFirstChild("HUD")
    if hud then
        local actions = hud:FindFirstChild("BotonesGame")
        local backpack = hud:FindFirstChild("Backpack")
        local settings = hud:FindFirstChild("Ajustes")
        local y = compact and 62 or 150
        place(actions and actions:FindFirstChild("ButtonTrato"), UDim2.fromOffset(button, button), UDim2.new(1, -12, 0, y), Vector2.new(1, 0))
        place(backpack and backpack:FindFirstChild("IconoBackpack"), UDim2.fromOffset(button + 8, button + 8), UDim2.new(0, 12, 0.42, 0), Vector2.new(0, 0.5))
        place(settings and settings:FindFirstChild("ButtonConfig"), UDim2.fromOffset(button, button), UDim2.new(1, -12, 0, y + (button + 4) * 2), Vector2.new(1, 0))
        place(settings and settings:FindFirstChild("Frame"), UDim2.fromOffset(270, 170), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
        -- Currency images contain transparent padding around their visible artwork.
        place(hud:FindFirstChild("Dinero"), UDim2.fromOffset(190, 170), UDim2.new(1, -4, 0, -62), Vector2.new(1, 0))
        place(hud:FindFirstChild("Diamantes"), UDim2.fromOffset(145, 130), UDim2.new(1, -20, 0, -3), Vector2.new(1, 0))
    end
    local avatar = playerGui:FindFirstChild("AvatarEditor")
    if avatar then
        place(avatar:FindFirstChild("Toggle"), UDim2.fromOffset(button, button), UDim2.new(1, -12, 0, (compact and 62 or 150) + button + 4), Vector2.new(1, 0))
        local main = avatar:FindFirstChild("Main")
        if main then
            local portrait = view.X < view.Y
            local catalog = main:FindFirstChild("Catalog")
            local viewer = main:FindFirstChild("Viewer")
            if catalog then catalog.Size = portrait and UDim2.fromScale(1, 0.70) or UDim2.fromScale(0.66, 1) end
            if viewer then viewer.Size = portrait and UDim2.fromScale(1, 0.30) or UDim2.fromScale(0.34, 1) end
        end
    end
    local clock = playerGui:FindFirstChild("GameClockGui")
    place(clock and clock:FindFirstChild("ClockFrame"), UDim2.fromOffset(110, 42), UDim2.fromOffset(12, 4), Vector2.zero)
    local tutorial = playerGui:FindFirstChild("GrindNimalsTutorialGui")
    place(tutorial and tutorial:FindFirstChild("HelpButton"), UDim2.fromOffset(48, 48), UDim2.fromOffset(16, 50), Vector2.zero)
end

local function visit(object, screen)
    if object:IsA("ScreenGui") then
        if excluded[object.Name] then return end
        screen = object
        if object.Name ~= "Cell Shading" and not object.Name:find("Loading") and not object.Name:find("Teleport") then
            object.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
        end
    elseif object:IsA("GuiObject") and screen then
        local size = object.Size
        local parent = object.Parent
        local topLevel = parent:IsA("ScreenGui")
        local fullParent = parent:IsA("GuiObject") and parent.Size.X.Scale >= 0.95 and parent.Size.Y.Scale >= 0.95
        if (topLevel or fullParent) and size.X.Scale == 0 and size.Y.Scale == 0
            and (size.X.Offset >= 280 or size.Y.Offset >= 250)
            and not object.Name:find("Cursor") and not object.Name:find("Layer") then
            fit(object)
        end
    end
    if targets[object] then return end
    for _, child in object:GetChildren() do
        if child:IsA("GuiBase2d") then visit(child, screen) end
    end
end

local function refresh()
    queued = false
    layoutHud()
    visit(playerGui, nil)
    for object, state in targets do fitTarget(object, state) end
end
local function schedule()
    if queued then return end
    queued = true
    task.defer(refresh)
end
playerGui.DescendantAdded:Connect(function(object)
    if object:IsA("GuiObject") or object:IsA("ScreenGui") then schedule() end
end)
local cameraConnection
local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule) end
    schedule()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()