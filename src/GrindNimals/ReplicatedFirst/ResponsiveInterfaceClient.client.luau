-- GrindNimals: test-only responsive HUD revision.
-- Inspected the active StarterGui + LocalScripts in GrindNimals-ui-backup.rbxl.
-- Avoid competing UIScales; each script-created UI still owns its original layout.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREEN_OWNERS = { "HUD", "TradeGui", "GameClockGui", "AvatarEditor" }
local REMOVABLE_SCALES = {
    DeviceResponsiveScale = true,
    ResponsiveDeviceScale = true,
    ViewportFitScale = true,
}
local cameraConnection
local queued = false

local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function compactViewport()
    local v = viewport()
    return v.X < 1000 or v.Y < 600
end

local function removeNamedScales(root, names)
    if not root then return end
    for _, child in ipairs(root:GetDescendants()) do
        if child:IsA("UIScale") and names[child.Name] then
            child:Destroy()
        end
    end
end

local function useHudScale(object, factor)
    if not (object and object:IsA("GuiObject")) then return end
    local scale = object:FindFirstChild("GrindNimalsHudScale")
    if scale and not scale:IsA("UIScale") then return end
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "GrindNimalsHudScale"
        scale.Parent = object
    end
    scale.Scale = factor
end

local function manageOriginalScaler(screen, compact)
    if not screen then return end
    local scriptScaler = screen:FindFirstChild("DeviceResponsiveScaler")
    if scriptScaler and scriptScaler:IsA("LocalScript") then
        scriptScaler.Enabled = not compact
    end
    if compact then
        removeNamedScales(screen, REMOVABLE_SCALES)
    else
        removeNamedScales(screen, { GrindNimalsHudScale = true })
    end
end

local function manageHud()
    if not compactViewport() then return end
    local hud = playerGui:FindFirstChild("HUD")
    if not hud then return end

    local view = viewport()
    local ratio = math.clamp(math.min(view.X / 980, view.Y / 540), 0.55, 1)
    local buttonFactor = math.clamp(ratio, 0.72, 1)

    local actions = hud:FindFirstChild("BotonesGame")
    local backpack = hud:FindFirstChild("Backpack")
    local settings = hud:FindFirstChild("Ajustes")

    -- Preserve all original button sizes and Position values from StarterGui.
    -- A single UIScale maintains each button's proportions on mobile.
    useHudScale(actions and actions:FindFirstChild("ButtonTrato"), buttonFactor)
    useHudScale(backpack and backpack:FindFirstChild("IconoBackpack"), buttonFactor)
    useHudScale(settings and settings:FindFirstChild("ButtonConfig"), buttonFactor)

    -- MoneyDisplayClient and DiamondDisplayClient only update text, not layout.
    -- Scale their outer artwork and anchor it to the same top-right zone.
    local money = hud:FindFirstChild("Dinero")
    if money and money:IsA("GuiObject") then
        money.AnchorPoint = Vector2.new(1, 0)
        money.Position = UDim2.fromScale(0.99, -0.08)
        money.Size = UDim2.fromScale(0.2121, 0.3873)
        useHudScale(money, 0.61)
    end

    local diamonds = hud:FindFirstChild("Diamantes")
    if diamonds and diamonds:IsA("GuiObject") then
        diamonds.AnchorPoint = Vector2.new(1, 0)
        diamonds.Position = UDim2.fromScale(0.99, 0.09)
        diamonds.Size = UDim2.fromScale(0.1537, 0.3087)
        useHudScale(diamonds, 0.61)
    end

    -- QuickInventoryController independently sizes/repositions slots 1,2,3
    -- using ViewportSize. Never overwrite its slot layout or QuickSlotScale.
end

local function manageAvatar()
    if not compactViewport() then return end
    local avatar = playerGui:FindFirstChild("AvatarEditor")
    local toggle = avatar and avatar:FindFirstChild("Toggle")
    local v = viewport()
    local factor = math.clamp(math.min(v.X / 980, v.Y / 540), 0.72, 1)
    useHudScale(toggle, factor)
    -- AvatarEditorClient owns the tabs, catalog, viewer and animations.
end

local function refresh()
    queued = false
    local compact = compactViewport()
    for _, screenName in ipairs(SCREEN_OWNERS) do
        manageOriginalScaler(playerGui:FindFirstChild(screenName), compact)
    end
    manageHud()
    manageAvatar()
end

local function schedule()
    if queued then return end
    queued = true
    task.defer(refresh)
end

local function bindCamera()
    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
    local camera = workspace.CurrentCamera
    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule)
    end
    schedule()
end

playerGui.ChildAdded:Connect(function(object)
    if object:IsA("ScreenGui") then schedule() end
end)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

-- Dynamically generated interfaces can arrive after the initial connection.
task.delay(1, schedule)
task.delay(3, schedule)
