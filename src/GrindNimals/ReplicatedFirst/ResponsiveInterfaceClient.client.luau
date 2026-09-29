-- GrindNimals responsive UI adapter
-- Keeps the authored visual layout intact. It only scales oversized panels down
-- when the current viewport cannot contain them, and preserves the established
-- HUD locations instead of redesigning/reflowing them per-device.

local Players = game:GetService("Players")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local targets = {}
local queued = false
local cameraConnection

local excludedScreens = {
	TouchGui = true,
	Freecam = true,
	EggCareClickCursorGui = true,
}

local EDGE_MARGIN = 10
local LARGE_PANEL_MIN_WIDTH = 280
local LARGE_PANEL_MIN_HEIGHT = 250

local function viewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function getOrCreateScale(object)
	local scale = object:FindFirstChild("ResponsiveScale")
		or object:FindFirstChild("ContentScale")
		or object:FindFirstChild("ViewportFitScale")
		or object:FindFirstChildOfClass("UIScale")

	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "ViewportFitScale"
		scale.Scale = 1
		scale.Parent = object
	end

	return scale
end

local function fitTarget(object, state)
	if not object.Parent or not object:IsDescendantOf(playerGui) then
		return
	end

	local parent = object.Parent
	if not parent:IsA("GuiBase2d") then
		return
	end

	local parentSize = parent.AbsoluteSize
	if parentSize.X < 1 or parentSize.Y < 1 then
		return
	end

	local size = object.Size
	local unscaledWidth = parentSize.X * size.X.Scale + size.X.Offset
	local unscaledHeight = parentSize.Y * size.Y.Scale + size.Y.Offset
	if unscaledWidth <= 0 or unscaledHeight <= 0 then
		return
	end

	local scaleObject = state.scale
	if not scaleObject.Parent then
		return
	end

	-- If another UI script intentionally changes an existing UIScale, respect
	-- that value as the new authored/requested scale.
	if math.abs(scaleObject.Scale - state.applied) > 0.0001 then
		state.requested = scaleObject.Scale
	end

	local anchor = object.AnchorPoint
	local position = object.Position
	local anchorX = parentSize.X * position.X.Scale + position.X.Offset
	local anchorY = parentSize.Y * position.Y.Scale + position.Y.Offset

	local availableWidth = math.max(1, parentSize.X - EDGE_MARGIN * 2)
	local availableHeight = math.max(1, parentSize.Y - EDGE_MARGIN * 2)

	-- Work out how much room exists around the object's CURRENT authored anchor.
	-- This deliberately does not change Position or AnchorPoint.
	if anchorX >= 0 and anchorX <= parentSize.X then
		if anchor.X > 0 then
			availableWidth = math.min(
				availableWidth,
				math.max(1, anchorX - EDGE_MARGIN) / anchor.X
			)
		end
		if anchor.X < 1 then
			availableWidth = math.min(
				availableWidth,
				math.max(1, parentSize.X - anchorX - EDGE_MARGIN) / (1 - anchor.X)
			)
		end
	end

	if anchorY >= 0 and anchorY <= parentSize.Y then
		if anchor.Y > 0 then
			availableHeight = math.min(
				availableHeight,
				math.max(1, anchorY - EDGE_MARGIN) / anchor.Y
			)
		end
		if anchor.Y < 1 then
			availableHeight = math.min(
				availableHeight,
				math.max(1, parentSize.Y - anchorY - EDGE_MARGIN) / (1 - anchor.Y)
			)
		end
	end

	-- Never enlarge an interface beyond its authored scale. On smaller screens,
	-- shrink uniformly so text, strokes, icons and spacing keep their proportions.
	local fitted = math.min(
		state.requested,
		availableWidth / unscaledWidth,
		availableHeight / unscaledHeight
	)

	fitted = math.clamp(fitted, 0.35, state.requested)
	state.applied = fitted

	if math.abs(scaleObject.Scale - fitted) > 0.0001 then
		scaleObject.Scale = fitted
	end
end

local function fit(object)
	if targets[object] then
		return
	end

	local scale = getOrCreateScale(object)
	local state = {
		scale = scale,
		requested = scale.Scale,
		applied = scale.Scale,
		connections = {},
	}

	targets[object] = state

	local function update()
		fitTarget(object, state)
	end

	for _, property in { "Size", "Position", "AnchorPoint", "Visible" } do
		table.insert(state.connections, object:GetPropertyChangedSignal(property):Connect(update))
	end

	table.insert(state.connections, scale:GetPropertyChangedSignal("Scale"):Connect(update))

	if object.Parent:IsA("GuiBase2d") then
		table.insert(
			state.connections,
			object.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
		)
	end

	table.insert(state.connections, object.Destroying:Connect(function()
		for _, connection in state.connections do
			connection:Disconnect()
		end
		targets[object] = nil
	end))

	update()
end

local function shouldFit(object)
	if not object:IsA("GuiObject") then
		return false
	end

	local parent = object.Parent
	if not parent or not parent:IsA("GuiBase2d") then
		return false
	end

	local topLevel = parent:IsA("ScreenGui")
	local parentIsFullScreen = parent:IsA("GuiObject")
		and parent.Size.X.Scale >= 0.95
		and parent.Size.Y.Scale >= 0.95

	if not (topLevel or parentIsFullScreen) then
		return false
	end

	if object.Name:find("Cursor") or object.Name:find("Layer") then
		return false
	end

	local size = object.Size
	local fixedLargePanel = size.X.Scale == 0
		and size.Y.Scale == 0
		and (size.X.Offset >= LARGE_PANEL_MIN_WIDTH or size.Y.Offset >= LARGE_PANEL_MIN_HEIGHT)

	local parentSize = parent.AbsoluteSize
	local oversizedNow = parentSize.X > 0
		and parentSize.Y > 0
		and (
			object.AbsoluteSize.X > parentSize.X - EDGE_MARGIN * 2
			or object.AbsoluteSize.Y > parentSize.Y - EDGE_MARGIN * 2
		)

	return fixedLargePanel or oversizedNow
end

local function keepEstablishedHudLayout()
	-- These are the existing GrindNimals desktop locations that were already in
	-- the project before this revision. They stay identical across device classes.
	-- Only the physical button size becomes slightly smaller on compact screens.
	local view = viewport()
	local compact = view.X < 1000 or view.Y < 600
	local buttonSize = compact and 48 or 64

	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		local actions = hud:FindFirstChild("BotonesGame")
		local backpack = hud:FindFirstChild("Backpack")
		local settings = hud:FindFirstChild("Ajustes")

		local tradeButton = actions and actions:FindFirstChild("ButtonTrato")
		if tradeButton and tradeButton:IsA("GuiObject") then
			tradeButton.AnchorPoint = Vector2.new(1, 0)
			tradeButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
			tradeButton.Position = UDim2.new(1, -12, 0, 150)
		end

		local backpackButton = backpack and backpack:FindFirstChild("IconoBackpack")
		if backpackButton and backpackButton:IsA("GuiObject") then
			backpackButton.AnchorPoint = Vector2.new(0, 0.5)
			backpackButton.Size = UDim2.fromOffset(buttonSize + 8, buttonSize + 8)
			backpackButton.Position = UDim2.new(0, 12, 0.42, 0)
		end

		local settingsButton = settings and settings:FindFirstChild("ButtonConfig")
		if settingsButton and settingsButton:IsA("GuiObject") then
			settingsButton.AnchorPoint = Vector2.new(1, 0)
			settingsButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
			settingsButton.Position = UDim2.new(1, -12, 0, 286)
		end

		local settingsFrame = settings and settings:FindFirstChild("Frame")
		if settingsFrame and settingsFrame:IsA("GuiObject") then
			settingsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			settingsFrame.Position = UDim2.fromScale(0.5, 0.5)
			fit(settingsFrame)
		end

		-- Keep the currency artwork in the same top-right locations. Those images
		-- contain transparent padding, so changing their position would visibly
		-- shift the artwork even if the ImageLabel bounds looked similar.
		local money = hud:FindFirstChild("Dinero")
		if money and money:IsA("GuiObject") then
			money.AnchorPoint = Vector2.new(1, 0)
			money.Position = UDim2.new(1, -4, 0, -62)
		end

		local diamonds = hud:FindFirstChild("Diamantes")
		if diamonds and diamonds:IsA("GuiObject") then
			diamonds.AnchorPoint = Vector2.new(1, 0)
			diamonds.Position = UDim2.new(1, -20, 0, -3)
		end
	end

	local avatar = playerGui:FindFirstChild("AvatarEditor")
	if avatar then
		local toggle = avatar:FindFirstChild("Toggle")
		if toggle and toggle:IsA("GuiObject") then
			toggle.AnchorPoint = Vector2.new(1, 0)
			toggle.Size = UDim2.fromOffset(buttonSize, buttonSize)
			toggle.Position = UDim2.new(1, -12, 0, 218)
		end

		-- Do NOT reorganize Catalog/Viewer on portrait devices. The complete
		-- AvatarEditor keeps its authored layout and is fitted as one panel if
		-- necessary, preserving the original design.
		local main = avatar:FindFirstChild("Main")
		if main and main:IsA("GuiObject") then
			fit(main)
		end
	end

	local clock = playerGui:FindFirstChild("GameClockGui")
	local clockFrame = clock and clock:FindFirstChild("ClockFrame")
	if clockFrame and clockFrame:IsA("GuiObject") then
		clockFrame.AnchorPoint = Vector2.zero
		clockFrame.Position = UDim2.fromOffset(12, 4)
	end

	local tutorial = playerGui:FindFirstChild("GrindNimalsTutorialGui")
	local helpButton = tutorial and tutorial:FindFirstChild("HelpButton")
	if helpButton and helpButton:IsA("GuiObject") then
		helpButton.AnchorPoint = Vector2.zero
		helpButton.Position = UDim2.fromOffset(16, 50)
	end
end

local function visit(object, screen)
	if object:IsA("ScreenGui") then
		if excludedScreens[object.Name] then
			return
		end

		-- We intentionally keep each ScreenGui's authored inset settings. Changing
		-- ScreenInsets/IgnoreGuiInset here would move the entire interface.
		screen = object
	elseif object:IsA("GuiObject") and screen then
		if shouldFit(object) then
			fit(object)
		end
	end

	for _, child in object:GetChildren() do
		if child:IsA("GuiBase2d") then
			visit(child, screen)
		end
	end
end

local function refresh()
	queued = false

	keepEstablishedHudLayout()
	visit(playerGui, nil)

	for object, state in targets do
		fitTarget(object, state)
	end
end

local function schedule()
	if queued then
		return
	end

	queued = true
	task.defer(refresh)
end

playerGui.DescendantAdded:Connect(function(object)
	if object:IsA("GuiObject") or object:IsA("ScreenGui") then
		schedule()
	end
end)

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

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()
