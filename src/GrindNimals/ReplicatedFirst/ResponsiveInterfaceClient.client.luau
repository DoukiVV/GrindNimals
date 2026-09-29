-- GrindNimals responsive UI adapter
-- Goal: preserve the authored layout/visual zones on every device.
-- We scale interfaces uniformly when needed; we do not redesign/reflow them.

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
local REFERENCE_VIEWPORT = Vector2.new(1280, 720)

local function viewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or REFERENCE_VIEWPORT
end

local function viewportScale()
	local view = viewport()
	local proportional = math.min(
		view.X / REFERENCE_VIEWPORT.X,
		view.Y / REFERENCE_VIEWPORT.Y
	)
	-- Do not force a large minimum. Studio's device emulator and some phones
	-- can expose a much smaller effective viewport than 1280x720.
	return math.clamp(proportional, 0.22, 1)
end

local function isCompact()
	local view = viewport()
	return view.X < 1000 or view.Y < 600
end

local function isLandscapePhone()
	local view = viewport()
	local aspect = view.X / math.max(1, view.Y)
	return view.X > view.Y and view.Y <= 650 and aspect >= 1.45
end

local function ensureNamedScale(object, name)
	local scale = object:FindFirstChild(name)
	if scale and not scale:IsA("UIScale") then
		scale = nil
	end

	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = name
		scale.Scale = 1
		scale.Parent = object
	end

	return scale
end

local function applyDeviceScale(object, value)
	if not object or not object:IsA("GuiObject") then
		return
	end

	object:SetAttribute("ResponsiveManagedByAdapter", true)
	local scale = ensureNamedScale(object, "ResponsiveDeviceScale")
	scale.Scale = value
end

local function fitScaleForCurrentAnchor(object, maximum)
	if not object or not object.Parent or not object.Parent:IsA("GuiBase2d") then
		return maximum or 1
	end

	local parentSize = object.Parent.AbsoluteSize
	if parentSize.X < 1 or parentSize.Y < 1 then
		return maximum or 1
	end

	local size = object.Size
	local width = parentSize.X * size.X.Scale + size.X.Offset
	local height = parentSize.Y * size.Y.Scale + size.Y.Offset
	if width <= 0 or height <= 0 then
		return maximum or 1
	end

	local anchor = object.AnchorPoint
	local position = object.Position
	local x = parentSize.X * position.X.Scale + position.X.Offset
	local y = parentSize.Y * position.Y.Scale + position.Y.Offset

	local availableWidth = math.max(1, parentSize.X - EDGE_MARGIN * 2)
	local availableHeight = math.max(1, parentSize.Y - EDGE_MARGIN * 2)

	if x >= 0 and x <= parentSize.X then
		if anchor.X > 0 then
			availableWidth = math.min(
				availableWidth,
				math.max(1, x - EDGE_MARGIN) / anchor.X
			)
		end
		if anchor.X < 1 then
			availableWidth = math.min(
				availableWidth,
				math.max(1, parentSize.X - x - EDGE_MARGIN) / (1 - anchor.X)
			)
		end
	end

	if y >= 0 and y <= parentSize.Y then
		if anchor.Y > 0 then
			availableHeight = math.min(
				availableHeight,
				math.max(1, y - EDGE_MARGIN) / anchor.Y
			)
		end
		if anchor.Y < 1 then
			availableHeight = math.min(
				availableHeight,
				math.max(1, parentSize.Y - y - EDGE_MARGIN) / (1 - anchor.Y)
			)
		end
	end

	local fitted = math.min(
		maximum or 1,
		availableWidth / width,
		availableHeight / height
	)

	return math.clamp(fitted, 0.35, maximum or 1)
end

local function fitTarget(object, state)
	if not object.Parent or not object:IsDescendantOf(playerGui) then
		return
	end

	if object:GetAttribute("ResponsiveManagedByAdapter") == true then
		return
	end

	local fitted = fitScaleForCurrentAnchor(object, state.requested)
	state.applied = fitted

	if math.abs(state.scale.Scale - fitted) > 0.0001 then
		state.scale.Scale = fitted
	end
end

local function fit(object)
	if not object or not object:IsA("GuiObject") then
		return
	end
	if object:GetAttribute("ResponsiveManagedByAdapter") == true then
		return
	end
	if targets[object] then
		return
	end

	-- IMPORTANT: use only our own scale. Never grab a random UIScale belonging
	-- to hover/click animations or another UI system.
	local scale = ensureNamedScale(object, "ViewportFitScale")
	local state = {
		scale = scale,
		requested = 1,
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
	if object:GetAttribute("ResponsiveManagedByAdapter") == true then
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


local function isCurrencyText(text)
	text = tostring(text or "")
	if text:find("%$") then
		return true
	end

	-- Diamonds in GrindNimals are shown as a plain number below the money.
	-- Keep this conservative: only short numeric/comma strings qualify.
	return text:match("^%s*[%d,%.]+%s*$") ~= nil and #text <= 14
end

local function findLocalCurrencyContainer(textObject)
	local view = viewport()
	local current = textObject
	local best = textObject

	while current.Parent and current.Parent:IsA("GuiObject") do
		local parent = current.Parent
		local size = parent.AbsoluteSize

		-- Currency artwork is a compact top-right cluster. Stop before climbing
		-- into a full-screen HUD container.
		if size.X <= view.X * 0.46 and size.Y <= view.Y * 0.48 then
			best = parent
			current = parent
		else
			break
		end
	end

	return best
end

local function scaleDetectedCurrency()
	local view = viewport()
	if view.X < 1 or view.Y < 1 then
		return
	end

	local seen = {}

	for _, object in playerGui:GetDescendants() do
		if (object:IsA("TextLabel") or object:IsA("TextButton"))
			and object.Visible
			and isCurrencyText(object.Text) then

			local pos = object.AbsolutePosition
			local size = object.AbsoluteSize
			local centerX = pos.X + size.X * 0.5
			local centerY = pos.Y + size.Y * 0.5

			if centerX >= view.X * 0.58 and centerY <= view.Y * 0.34 then
				local container = findLocalCurrencyContainer(object)
				if container and container:IsA("GuiObject") and not seen[container] then
					seen[container] = true

					local scaleObject = ensureNamedScale(container, "ResponsiveDeviceScale")
					container:SetAttribute("ResponsiveManagedByAdapter", true)

					local currentScale = math.max(0.001, scaleObject.Scale)
					local baseWidth = container.AbsoluteSize.X / currentScale
					local baseHeight = container.AbsoluteSize.Y / currentScale

					-- Match the visual footprint of the reference preview:
					-- each currency card should consume only a small part of
					-- the top-right corner, regardless of how it was authored.
					local targetWidth = math.max(42, view.X * 0.19)
					local targetHeight = math.max(30, view.Y * 0.22)
					local desired = math.min(
						1,
						targetWidth / math.max(1, baseWidth),
						targetHeight / math.max(1, baseHeight)
					)

					scaleObject.Scale = math.clamp(desired, 0.18, 1)
				end
			end
		end
	end
end


local function findGuiObjectAnywhere(name)
	local object = playerGui:FindFirstChild(name, true)
	if object and object:IsA("GuiObject") then
		return object
	end
	return nil
end

local function scaleNamedCurrencyContainers()
	local view = viewport()
	local compact = isCompact()
	local landscapePhone = isLandscapePhone()
	if not compact and not landscapePhone then
		return
	end

	-- These are the actual runtime objects shown in Studio Explorer. They may be
	-- created/controlled by MoneyDisplayClient and DiamondDisplayClient, so we
	-- scale the OUTER containers instead of fighting their TextLabel properties.
	local money = findGuiObjectAnywhere("Dinero")
	local diamonds = findGuiObjectAnywhere("Diamantes")

	local ratio
	if landscapePhone then
		ratio = math.min(view.X / 980, view.Y / 540)
	else
		ratio = viewportScale()
	end

	-- Reference preview uses compact cards in the top-right corner.
	local scale = math.clamp(ratio * 0.62, 0.24, 0.62)

	if money then
		money.AnchorPoint = Vector2.new(1, 0)
		money.Position = UDim2.new(1, -10, 0, 8)
		applyDeviceScale(money, scale)
	end

	if diamonds then
		diamonds.AnchorPoint = Vector2.new(1, 0)
		diamonds.Position = UDim2.new(1, -10, 0, 56)
		applyDeviceScale(diamonds, scale)
	end
end

local function layoutKnownInterfaces()
	local compact = isCompact()
	local landscapePhone = isLandscapePhone()
	local proportional = viewportScale()

	-- Mobile landscape is tuned to match the Studio preview reference:
	-- left backpack, three right-side buttons, currency at top-right,
	-- while leaving the quick-slot bar untouched at the bottom.
	local buttonScale
	local currencyScale
	local smallHudScale
	local panelScale
	local avatarScale

	if landscapePhone then
		-- Keep the same composition as the 980x540 Studio preview, but scale
		-- according to the ACTUAL viewport. Very small emulated viewports need
		-- to go well below 0.6 or the top-right HUD gets clipped.
		local widthRatio = viewport().X / 980
		local heightRatio = viewport().Y / 540
		local previewRatio = math.min(widthRatio, heightRatio)

		buttonScale = math.clamp(previewRatio, 0.38, 0.82)
		currencyScale = math.clamp(previewRatio * 0.92, 0.28, 0.72)
		smallHudScale = math.clamp(previewRatio, 0.38, 0.82)
		panelScale = math.clamp(previewRatio, 0.42, 0.78)
		avatarScale = math.clamp(previewRatio, 0.42, 0.80)
	elseif compact then
		buttonScale = math.clamp(proportional, 0.38, 0.84)
		currencyScale = math.clamp(proportional * 0.92, 0.28, 0.72)
		smallHudScale = math.clamp(proportional, 0.38, 0.84)
		panelScale = math.clamp(proportional, 0.42, 0.80)
		avatarScale = math.clamp(proportional, 0.42, 0.82)
	else
		buttonScale = 1
		currencyScale = 1
		smallHudScale = 1
		panelScale = 1
		avatarScale = 1
	end

	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		local actions = hud:FindFirstChild("BotonesGame")
		local backpack = hud:FindFirstChild("Backpack")
		local settings = hud:FindFirstChild("Ajustes")

		local tradeButton = actions and actions:FindFirstChild("ButtonTrato")
		if tradeButton and tradeButton:IsA("GuiObject") then
			tradeButton.AnchorPoint = Vector2.new(1, 0.5)
			tradeButton.Size = UDim2.fromOffset(64, 64)
			if landscapePhone then
				tradeButton.Position = UDim2.new(1, -18, 0.37, 0)
			else
				tradeButton.Position = UDim2.new(1, -12, 0, 182)
			end
			applyDeviceScale(tradeButton, buttonScale)
		end

		local backpackButton = backpack and backpack:FindFirstChild("IconoBackpack")
		if backpackButton and backpackButton:IsA("GuiObject") then
			backpackButton.AnchorPoint = Vector2.new(0, 0.5)
			backpackButton.Size = UDim2.fromOffset(72, 72)
			if landscapePhone then
				backpackButton.Position = UDim2.new(0, 24, 0.48, 0)
			else
				backpackButton.Position = UDim2.new(0, 12, 0.42, 0)
			end
			applyDeviceScale(backpackButton, buttonScale)
		end

		local settingsButton = settings and settings:FindFirstChild("ButtonConfig")
		if settingsButton and settingsButton:IsA("GuiObject") then
			settingsButton.AnchorPoint = Vector2.new(1, 0.5)
			settingsButton.Size = UDim2.fromOffset(64, 64)
			if landscapePhone then
				settingsButton.Position = UDim2.new(1, -18, 0.63, 0)
			else
				settingsButton.Position = UDim2.new(1, -12, 0, 318)
			end
			applyDeviceScale(settingsButton, buttonScale)
		end

		local settingsFrame = settings and settings:FindFirstChild("Frame")
		if settingsFrame and settingsFrame:IsA("GuiObject") then
			settingsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			settingsFrame.Size = UDim2.fromOffset(270, 170)
			settingsFrame.Position = UDim2.fromScale(0.5, 0.5)
			local fitted = math.min(panelScale, fitScaleForCurrentAnchor(settingsFrame, panelScale))
			applyDeviceScale(settingsFrame, fitted)
		end

		local money = hud:FindFirstChild("Dinero")
		if money and money:IsA("GuiObject") then
			money.AnchorPoint = Vector2.new(1, 0)
			money.Size = UDim2.fromOffset(190, 170)
			if landscapePhone then
				money.Position = UDim2.new(1, -8, 0, -34)
			else
				money.Position = UDim2.new(1, -4, 0, -62)
			end
			applyDeviceScale(money, currencyScale)
		end

		local diamonds = hud:FindFirstChild("Diamantes")
		if diamonds and diamonds:IsA("GuiObject") then
			diamonds.AnchorPoint = Vector2.new(1, 0)
			diamonds.Size = UDim2.fromOffset(145, 130)
			if landscapePhone then
				diamonds.Position = UDim2.new(1, -16, 0, 18)
			else
				diamonds.Position = UDim2.new(1, -20, 0, -3)
			end
			applyDeviceScale(diamonds, currencyScale)
		end
	end

	local avatar = playerGui:FindFirstChild("AvatarEditor")
	if avatar then
		local toggle = avatar:FindFirstChild("Toggle")
		if toggle and toggle:IsA("GuiObject") then
			toggle.AnchorPoint = Vector2.new(1, 0.5)
			toggle.Size = UDim2.fromOffset(64, 64)
			if landscapePhone then
				toggle.Position = UDim2.new(1, -18, 0.50, 0)
			else
				toggle.Position = UDim2.new(1, -12, 0, 250)
			end
			applyDeviceScale(toggle, buttonScale)
		end

		-- Keep the avatar editor composition intact; only scale the entire panel.
		local main = avatar:FindFirstChild("Main")
		if main and main:IsA("GuiObject") then
			local fitted = math.min(avatarScale, fitScaleForCurrentAnchor(main, avatarScale))
			applyDeviceScale(main, fitted)
		end
	end

	local clock = playerGui:FindFirstChild("GameClockGui")
	local clockFrame = clock and clock:FindFirstChild("ClockFrame")
	if clockFrame and clockFrame:IsA("GuiObject") then
		clockFrame.AnchorPoint = Vector2.zero
		clockFrame.Size = UDim2.fromOffset(110, 42)
		clockFrame.Position = UDim2.fromOffset(12, 4)
		applyDeviceScale(clockFrame, smallHudScale)
	end

	local tutorial = playerGui:FindFirstChild("GrindNimalsTutorialGui")
	local helpButton = tutorial and tutorial:FindFirstChild("HelpButton")
	if helpButton and helpButton:IsA("GuiObject") then
		helpButton.AnchorPoint = Vector2.zero
		helpButton.Size = UDim2.fromOffset(48, 48)
		helpButton.Position = UDim2.fromOffset(16, 50)
		applyDeviceScale(helpButton, smallHudScale)
	end
end
local function visit(object, screen)
	if object:IsA("ScreenGui") then
		if excludedScreens[object.Name] then
			return
		end

		-- Preserve the ScreenGui's authored inset behavior so the entire layout
		-- does not jump to a different coordinate system.
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

	layoutKnownInterfaces()
	scaleNamedCurrencyContainers()
	scaleDetectedCurrency()
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
