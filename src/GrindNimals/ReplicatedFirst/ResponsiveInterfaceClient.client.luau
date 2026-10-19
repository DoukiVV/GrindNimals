-- GrindNimals | Mobile HUD V6 - original currency artwork proportions and raised right buttons
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
local oldResponsiveScales = setmetatable({}, { __mode = "k" })
local originalTextScaled = setmetatable({}, { __mode = "k" })
local originalDiamondWrap = setmetatable({}, { __mode = "k" })

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
        and size.Y <= 1100
end


-- Use aspect ratio AND usable viewport height: a high-resolution iPhone
-- should not accidentally be treated as a tablet.
local function deviceProfile(view)
    local aspect = view.X / math.max(view.Y, 1)
    local phone = aspect >= 1.90 or view.Y <= 580

    if phone and (view.X <= 950 or view.Y <= 450) then
        return {
            name = "telefono-pequeno",
            right = 54, bag = 40, cash = 95, clock = 215,
            actionSize = 58, actionScale = 0.76,
            bagSize = 76, bagScale = 0.86, cashScale = 0.66,
            slot = 51, spacing = 89, bottom = 64,
            clockBoost = 1.38, clockY = 10,
            tradeY = 0.29, avatarY = 0.43, gearY = 0.57,
        }
    elseif phone then
        return {
            name = "telefono-grande",
            right = 75, bag = 56, cash = 156, clock = 335,
            actionSize = 62, actionScale = 0.79,
            bagSize = 79, bagScale = 0.90, cashScale = 0.72,
            slot = 56, spacing = 108, bottom = 75,
            clockBoost = 1.42, clockY = 12,
            tradeY = 0.29, avatarY = 0.43, gearY = 0.57,
        }
    else
        return {
            name = "tablet",
            right = 85, bag = 67, cash = 177, clock = 320,
            actionSize = 68, actionScale = 0.87,
            bagSize = 83, bagScale = 0.94, cashScale = 0.82,
            slot = 62, spacing = 116, bottom = 90,
            clockBoost = 1.30, clockY = 13,
            tradeY = 0.29, avatarY = 0.43, gearY = 0.58,
        }
    end
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
    -- Disable the original generic scaler only in landscape touch mode.
    -- Neutralize its UIScales reversibly (do not Destroy them), allowing
    -- switching back to PC preview in the same Play session.
    for _, name in ipairs({ "HUD", "AvatarEditor", "TradeGui", "GameClockGui" }) do
        local screen = playerGui:FindFirstChild(name)
        if screen then
            for _, desc in ipairs(screen:GetDescendants()) do
                if desc:IsA("LocalScript") and desc.Name == "DeviceResponsiveScaler" then
                    if originalScriptStates[desc] == nil then
                        originalScriptStates[desc] = desc.Enabled
                    end
                    if desc.Enabled then desc.Enabled = false end
                elseif desc:IsA("UIScale") and (
                    desc.Name == "DeviceResponsiveScale"
                    or desc.Name == "ResponsiveDeviceScale"
                    or desc.Name == "ViewportFitScale"
                ) then
                    if oldResponsiveScales[desc] == nil then
                        oldResponsiveScales[desc] = desc.Scale
                    end
                    if desc.Scale ~= 1 then desc.Scale = 1 end
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
    for s, prior in pairs(oldResponsiveScales) do
        if s.Parent then s.Scale = prior end
    end
    for label, old in pairs(originalTextScaled) do
        if label.Parent then label.TextScaled = old end
    end
    for label, old in pairs(originalDiamondWrap) do
        if label.Parent then label.TextWrapped = old end
    end
    for s, enabled in pairs(originalScriptStates) do
        if s.Parent then s.Enabled = enabled end
    end
    table.clear(originalProperties)
    table.clear(originalScriptStates)
    table.clear(oldResponsiveScales)
    table.clear(originalTextScaled)
    table.clear(originalDiamondWrap)
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
                if isMobile() then requestLayout() end
            end))
        end
        slotConnections[slot] = connections
    end
    local profile = deviceProfile(view)
    local offset = ({ [1] = 0, [2] = -profile.spacing, [3] = profile.spacing })[index]
    place(slot, Vector2.new(0.5, 0.5),
        UDim2.new(0.5, offset, 1, -profile.bottom),
        UDim2.fromOffset(profile.slot, profile.slot))
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
    local width = view.X
    local profile = deviceProfile(view)

    -- "Margin" is the center distance from the respective screen edge.
    -- The right column stays reachable without invading the currencies.
    local actionRight = math.max(profile.right, math.floor(width * 0.045))
    local bagLeft = math.max(30, math.min(profile.bag, math.floor(width * 0.075)))
    local currencyRight = math.max(profile.cash, math.floor(width * 0.115))
    local clockX = math.min(profile.clock, math.floor(width * 0.275))

    local hud = playerGui:FindFirstChild("HUD")
    if hud then
        local trade = guiChild(hud:FindFirstChild("BotonesGame"), "ButtonTrato")
        local bag = guiChild(hud:FindFirstChild("Backpack"), "IconoBackpack")
        local gear = guiChild(hud:FindFirstChild("Ajustes"), "ButtonConfig")
        local money = guiChild(hud, "Dinero")
        local diamonds = guiChild(hud, "Diamantes")

        place(trade, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, profile.tradeY, 0),
            UDim2.fromOffset(profile.actionSize, profile.actionSize))
        place(gear, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, profile.gearY, 0),
            UDim2.fromOffset(profile.actionSize, profile.actionSize))
        place(bag, Vector2.new(0.5, 0.5),
            UDim2.new(0, bagLeft, 0.49, 0),
            UDim2.fromOffset(profile.bagSize, profile.bagSize))

        scaleGui(trade, profile.actionScale)
        scaleGui(gear, profile.actionScale)
        scaleGui(bag, profile.bagScale)

        -- Use the artwork's original 1080p aspect ratios:
        --   Dinero:    0.2121W : 0.3873H => approximately 0.974 : 1
        --   Diamantes: 0.1537W : 0.3087H => approximately 0.886 : 1
        -- These are images with embedded number TextLabels. Narrowing only
        -- their height deforms the icons and crowds the text.
        local imageScale = math.clamp(view.Y / 660, 0.63, 0.83)
        local moneyY = -math.floor(math.clamp(view.Y * 0.11, 38, 70))
        -- Match the phone layout tested previously: smaller diamonds below cash.
        local diamondY = moneyY + 58
        place(money, Vector2.new(1, 0),
            UDim2.new(1, -currencyRight, 0, moneyY),
            UDim2.fromOffset(190, 195))
        place(diamonds, Vector2.new(1, 0),
            UDim2.new(1, -(currencyRight - 8), 0, diamondY),
            UDim2.fromOffset(132, 148))
        scaleGui(money, imageScale)
        scaleGui(diamonds, imageScale * 0.82)

        -- In the original Studio backup Money.TextLabel used 50px and
        -- Diamonds.TextLabel 35px without TextScaled. At phone widths,
        -- values such as "10,592" overflow their smaller text regions.
        -- Scale to available space while retaining authored alignment.
        for _, container in ipairs({money, diamonds}) do
            local label = container and container:FindFirstChild("TextLabel")
            if label and label:IsA("TextLabel") then
                if originalTextScaled[label] == nil then
                    originalTextScaled[label] = label.TextScaled
                end
                label.TextScaled = true
            end
        end

        -- Actual StarterGui > HUD > Diamantes > TextLabel from the backup:
        -- Position = (0.193759, 0.396578), Size = (0.604481, 0.200132)
        -- TextWrapped = true, TextSize = 35. Once the gem is reduced on mobile,
        -- five-digit values wrap into two lines / clip against its frame.
        -- Expand only the text field, not the artwork, and prevent wrapping.
        local diamondText = diamonds and diamonds:FindFirstChild("TextLabel")
        if diamondText and diamondText:IsA("TextLabel") then
            if originalDiamondWrap[diamondText] == nil then
                originalDiamondWrap[diamondText] = diamondText.TextWrapped
            end
            place(diamondText, Vector2.zero,
                UDim2.fromScale(0.24, 0.385),
                UDim2.fromScale(0.755, 0.24))
            diamondText.TextWrapped = false
            diamondText.TextScaled = true
            diamondText.TextTruncate = Enum.TextTruncate.None
        end

        -- QuickInventoryController owns contents/actions. Reposition only
        -- the three original HUD image buttons, not any duplicate CAS keys.
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
        -- Same button that AvatarEditorClient uses to open and close.
        place(toggle, Vector2.new(0.5, 0.5),
            UDim2.new(1, -actionRight, profile.avatarY, 0),
            UDim2.fromOffset(profile.actionSize, profile.actionSize))
        scaleGui(toggle, profile.actionScale)
        remember(toggle)
        toggle.ZIndex = math.max(120, toggle.ZIndex)
        if player:GetAttribute("AvatarEditorOpen") == true then
            toggle.Active = true
            toggle.Visible = true
        end
    end

    local clock = playerGui:FindFirstChild("GameClockGui")
    local clockFrame = guiChild(clock, "ClockFrame")
    if clockFrame then
        place(clockFrame, Vector2.zero,
            UDim2.fromOffset(clockX, profile.clockY), nil)
        -- GameClockClient already sets ResponsiveScale to 0.92..1.28.
        -- GNMobileScale is a controlled readability boost, mobile only.
        scaleGui(clockFrame, profile.clockBoost)
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
