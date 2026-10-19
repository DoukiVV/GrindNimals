-- GrindNimals | Mobile HUD V4 - stable safe areas and original hotbar only
-- Authored from the game's actual HUD and LocalScripts in the .rbxl backup.
--
-- Desktop and laptop: this script makes NO UI modifications.
-- Landscape touch devices: one owner for the persistent HUD, with margins
-- for rounded screens and device emulator overlays.
-- Original icon art, callbacks, inventory contents and animations are intact.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local originalProperties = setmetatable({}, { __mode = "k" })
local originalScriptStates = setmetatable({}, { __mode = "k" })
local managedScales = setmetatable({}, { __mode = "k" })
local visitedGuis = setmetatable({}, { __mode = "k" })
local slotConnections = setmetatable({}, { __mode = "k" })
local touchButtonsHidden = setmetatable({}, { __mode = "k" })

local queued = false
local wasMobile = false
local cameraConnection
local requestLayout

local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function isMobile()
    local size = viewport()
    return UserInputService.TouchEnabled
        and size.X > size.Y
        and size.Y <= 820
end

local function guiChild(parent, name)
    local obj = parent and parent:FindFirstChild(name)
    return obj and obj:IsA("GuiObject") and obj or nil
end

local function remember(obj)
    if obj and not originalProperties[obj] then
        originalProperties[obj] = {
            anchor = obj.AnchorPoint,
            position = obj.Position,
            size = obj.Size,
            zindex = obj.ZIndex,
        }
    end
end

local function place(obj, anchor, position, size)
    if not obj then return end
    remember(obj)
    if obj.AnchorPoint ~= anchor then obj.AnchorPoint = anchor end
    if obj.Position ~= position then obj.Position = position end
    if size and obj.Size ~= size then obj.Size = size end
end

local function scaleGui(obj, value)
    if not obj then return end
    local scale = obj:FindFirstChild("GNMobileScale")
    if scale and not scale:IsA("UIScale") then return end
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "GNMobileScale"
        scale.Scale = 1
        scale.Parent = obj
    end
    managedScales[scale] = true
    if math.abs(scale.Scale - value) > 0.001 then scale.Scale = value end
end

local function stopDuplicatedScalers()
    -- These original scripts scale every GuiObject recursively. Disable them
    -- only on mobile, and remove only the UI scales created by old adapters.
    for _, name in ipairs({ "HUD", "AvatarEditor", "TradeGui", "GameClockGui" }) do
        local screen = playerGui:FindFirstChild(name)
        if screen and not visitedGuis[screen] then
            visitedGuis[screen] = true
            for _, desc in ipairs(screen:GetDescendants()) do
                if desc:IsA("LocalScript") and desc.Name == "DeviceResponsiveScaler" then
                    originalScriptStates[desc] = desc.Enabled
                    desc.Enabled = false
                elseif desc:IsA("UIScale") and (
                    desc.Name == "DeviceResponsiveScale"
                    or desc.Name == "ResponsiveDeviceScale"
                    or desc.Name == "ViewportFitScale"
                ) then
                    desc:Destroy()
                end
            end
        end
    end
end

local function restoreForPC()
    for obj, saved in pairs(originalProperties) do
        if obj.Parent then
            obj.AnchorPoint = saved.anchor
            obj.Position = saved.position
            obj.Size = saved.size
            obj.ZIndex = saved.zindex
        end
    end
    for s in pairs(managedScales) do
        if s.Parent then s:Destroy() end
    end
    for s, enabled in pairs(originalScriptStates) do
        if s.Parent then s.Enabled = enabled end
    end
    table.clear(originalProperties)
    table.clear(originalScriptStates)
    table.clear(managedScales)
    table.clear(visitedGuis)
    wasMobile = false
end

local function manageSlot(slot, index, view)
    if not slot then return end
    if not slotConnections[slot] then
        local connections = {}
        for _, name in ipairs({ "Position", "Size" }) do
            table.insert(connections, slot:GetPropertyChangedSignal(name):Connect(function()
                -- QuickInventoryController rerenders on equip/unequip.
                -- Apply geometry after its render, never touch item data.
                if isMobile() then requestLayout() end
            end))
        end
        slotConnections[slot] = connections
    end

    -- Round slot artwork uses 1.48x/1.56x image layers: leave more
    -- breathing room than the base button's dimensions suggest.
    local side = math.floor(math.clamp(view.Y * 0.10, 46, 54) + 0.5)
    local spacing = math.floor(math.clamp(view.X * 0.098, 85, 113) + 0.5)
    -- Use a nearly fixed inset, instead of a percentage that raises the
    -- hotbar as the device resolution grows.
    local bottom = math.floor(math.clamp(view.Y * 0.163, 77, 85))
    local offset = ({ [1] = 0, [2] = -spacing, [3] = spacing })[index]

    place(slot, Vector2.new(0.5, 0.5),
        UDim2.new(0.5, offset, 1, -bottom),
        UDim2.fromOffset(side, side))
end

local function fixLoadingCover()
    -- Background extends behind the rounded corners; inner logo/progress
    -- retain their own responsive scaling from GameStartLoadingClient.
    for _, name in ipairs({ "GameStartLoadingGui", "WorldTeleportLoadingGui" }) do
        local screen = playerGui:FindFirstChild(name)
        if screen and screen:IsA("ScreenGui") then
            screen.IgnoreGuiInset = true
            pcall(function() screen.ScreenInsets = Enum.ScreenInsets.None end)
            pcall(function() screen.ClipToDeviceSafeArea = false end)
            local group = guiChild(screen, "LoadingGroup")
            if group then
                group.AnchorPoint = Vector2.zero
                group.Position = UDim2.fromScale(0, 0)
                group.Size = UDim2.fromScale(1, 1)
                group.ZIndex = math.max(2, group.ZIndex)
                local fill = screen:FindFirstChild("GNFullBleedBackground")
                if not fill then
                    fill = Instance.new("Frame")
                    fill.Name = "GNFullBleedBackground"
                    fill.BorderSizePixel = 0
                    fill.BackgroundTransparency = 0
                    fill.ZIndex = 1
                    fill.Parent = screen
                end
                fill.BackgroundColor3 = group.BackgroundColor3
                fill.Position = UDim2.fromOffset(-180, -180)
                fill.Size = UDim2.new(1, 360, 1, 360)
            end
        end
    end
end

local function layoutPhone()
    local view = viewport()
    local height, width = view.Y, view.X

    -- A deliberate three-button column at the far right, not in the center.
    -- y stops above the bottom emulator touch/capture controls.
    local actionRight = math.floor(math.clamp(width * 0.216, 145, 235))
    local currencyRight = math.floor(math.clamp(width * 0.17, 120, 205))
    local bagLeft = math.floor(math.clamp(width * 0.070, 62, 93))

    local actionScale = math.clamp(height / 650, 0.62, 0.78)
    local bagScale = math.clamp(height / 690, 0.60, 0.74)
    local cashScale = math.clamp(height / 870, 0.46, 0.64)

    local hud = playerGui:FindFirstChild("HUD")
    if hud then
        local trade = guiChild(hud:FindFirstChild("BotonesGame"), "ButtonTrato")
        local bag = guiChild(hud:FindFirstChild("Backpack"), "IconoBackpack")
        local gear = guiChild(hud:FindFirstChild("Ajustes"), "ButtonConfig")
        local money = guiChild(hud, "Dinero")
        local diamonds = guiChild(hud, "Diamantes")

        place(trade, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, 0.35, 0),
            UDim2.fromOffset(60, 60))
        place(gear, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, 0.61, 0),
            UDim2.fromOffset(60, 60))
        place(bag, Vector2.new(0.5, 0.5),
            UDim2.new(0, bagLeft, 0.48, 0),
            UDim2.fromOffset(68, 68))
        scaleGui(trade, actionScale)
        scaleGui(gear, actionScale)
        scaleGui(bag, bagScale)

        place(money, Vector2.new(1, 0),
            UDim2.new(1, -currencyRight, 0, -26),
            UDim2.fromOffset(190, 170))
        place(diamonds, Vector2.new(1, 0),
            UDim2.new(1, -currencyRight - 8, 0, 21),
            UDim2.fromOffset(145, 130))
        scaleGui(money, cashScale)
        scaleGui(diamonds, cashScale)

        local inventory = hud:FindFirstChild("Inventario")
        if inventory then
            for index = 1, 3 do
                manageSlot(guiChild(inventory, tostring(index)), index, view)
            end
        end
    end

    local avatar = playerGui:FindFirstChild("AvatarEditor")
    local toggle = guiChild(avatar, "Toggle")
    if toggle then
        -- AvatarEditorClient already connects Toggle.Activated to its
        -- open/close/save function. Keep that SAME button accessible when
        -- Main/Catalog is open; do not invent a second close action.
        place(toggle, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, 0.48, 0),
            UDim2.fromOffset(60, 60))
        scaleGui(toggle, actionScale)
        remember(toggle)
        toggle.ZIndex = math.max(120, toggle.ZIndex)
        if player:GetAttribute("AvatarEditorOpen") == true then
            toggle.Active = true
            toggle.Visible = true
        end
    end

    -- Clock is positioned after Roblox's top-left menu, with its ORIGINAL
    -- ResponsiveScale controlled only by GameClockClient (not doubled).
    local clock = playerGui:FindFirstChild("GameClockGui")
    local clockFrame = guiChild(clock, "ClockFrame")
    if clockFrame then
        place(clockFrame, Vector2.zero,
            UDim2.fromOffset(math.floor(math.clamp(width * 0.265, 255, 320)), 10),
            nil)
    end

    fixLoadingCover()
end


-- The original QuickInventoryController creates a *second* 1/2/3 row
-- through ContextActionService BindActionAtPriority(..., true).
-- Its existing ImageButtons and their Activated callbacks remain untouched.
local redundantTouchActions = {
    "QuickInventorySlot1",
    "QuickInventorySlot2",
    "QuickInventorySlot3",
    -- Extra touch shortcuts visible on top of the authored buttons.
    -- Only the touch buttons are hidden; keyboard/gamepad bindings remain.
    "RunDeviceAction",
    "PetMenuDeviceAction",
}
local function hideRedundantTouchControls()
    if not isMobile() then
        for button, previousVisibility in pairs(touchButtonsHidden) do
            if button.Parent then button.Visible = previousVisibility end
            touchButtonsHidden[button] = nil
        end
        return
    end

    for _, actionName in ipairs(redundantTouchActions) do
        local ok, button = pcall(function()
            return ContextActionService:GetButton(actionName)
        end)
        if ok and button and button:IsA("GuiObject") then
            if touchButtonsHidden[button] == nil then
                touchButtonsHidden[button] = button.Visible
            end
            if button.Visible then button.Visible = false end
        end
    end

    -- "Cerrar" belongs to the pet-upgrade UI. Only hide its redundant
    -- touch shortcut while no upgrade/dialog is open, so phone players
    -- can still close the actual upgrade dialog when they need it.
    local upgrading = playerGui:FindFirstChild("PetUpgradeGui")
    local dialogue = playerGui:FindFirstChild("FrankDialogueGui")
    local menuOpen = (upgrading and upgrading:IsA("ScreenGui") and upgrading.Enabled)
        or (dialogue and dialogue:IsA("ScreenGui") and dialogue.Enabled)
    local ok, button = pcall(function()
        return ContextActionService:GetButton("PetUpgradeCloseDeviceAction")
    end)
    if ok and button and button:IsA("GuiObject") then
        if touchButtonsHidden[button] == nil then
            touchButtonsHidden[button] = button.Visible
        end
        button.Visible = not not menuOpen
    end
end

local function refresh()
    queued = false
    if isMobile() then
        wasMobile = true
        stopDuplicatedScalers()
        layoutPhone()
    elseif wasMobile then
        restoreForPC()
    end
    hideRedundantTouchControls()
    -- No desktop branch: preserve all authored 1080p positions, sizes,
    -- animations and their original local controller scripts.
end

requestLayout = function()
    if queued then return end
    queued = true
    task.defer(refresh)
end

local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    cameraConnection = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(requestLayout)
    requestLayout()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
player:GetAttributeChangedSignal("AvatarEditorOpen"):Connect(requestLayout)
playerGui.ChildAdded:Connect(function(child)
    if child:IsA("ScreenGui") then requestLayout() end
end)

bindCamera()
task.delay(0.3, requestLayout)
task.delay(1.5, requestLayout)
task.delay(4, requestLayout)

-- Action buttons can be created after the HUD has loaded or after respawn.
-- Poll only the few known ContextActionService buttons: no broad GUI hiding.
task.spawn(function()
    while player.Parent do
        hideRedundantTouchControls()
        task.wait(0.5)
    end
end)
