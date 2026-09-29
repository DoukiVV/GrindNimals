--============================================================
-- ADMIN FLY CHAT CLIENT V1.1 - SIN DATASTORE
-- Ubicacion: StarterPlayer > StarterPlayerScripts > AdminFlyChatClient
-- Tipo: LocalScript
--
-- IMPORTANTE:
-- Un LocalScript NO puede usar DataStoreService.
-- Este archivo solo escucha AdminFlyChatToggle enviado por servidor.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local ADMIN_USER_IDS = {
	[2763635937] = true,
	[1075477843] = true,
	[11621988902] = true,
	[2567510148] = true,
}

if ADMIN_USER_IDS[player.UserId] ~= true then
	return
end

local remote = ReplicatedStorage:WaitForChild("AdminFlyChatToggle")

local FLY_SPEED = 65

local flying = false
local root = nil
local humanoid = nil
local attachment = nil
local linearVelocity = nil
local alignOrientation = nil
local renderConnection = nil

local move = {
	Forward = false,
	Backward = false,
	Left = false,
	Right = false,
	Up = false,
	Down = false,
}

local keyMap = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",
	[Enum.KeyCode.Space] = "Up",
	[Enum.KeyCode.LeftControl] = "Down",
	[Enum.KeyCode.RightControl] = "Down",
	[Enum.KeyCode.Q] = "Down",
}

local function clearMovement()
	for key in pairs(move) do
		move[key] = false
	end
end

local function stopFly()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if linearVelocity then
		linearVelocity:Destroy()
		linearVelocity = nil
	end

	if alignOrientation then
		alignOrientation:Destroy()
		alignOrientation = nil
	end

	if attachment then
		attachment:Destroy()
		attachment = nil
	end

	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false

		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	if root and root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	clearMovement()

	root = nil
	humanoid = nil
	flying = false
	player:SetAttribute("AdminFlying", false)
end

local function getMoveVector()
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local vector = Vector3.zero

	if move.Forward then
		vector += camera.CFrame.LookVector
	end

	if move.Backward then
		vector -= camera.CFrame.LookVector
	end

	if move.Right then
		vector += camera.CFrame.RightVector
	end

	if move.Left then
		vector -= camera.CFrame.RightVector
	end

	if move.Up then
		vector += Vector3.yAxis
	end

	if move.Down then
		vector -= Vector3.yAxis
	end

	if vector.Magnitude > 0 then
		return vector.Unit
	end

	return Vector3.zero
end

local function startFly()
	if flying then
		return
	end

	local character = player.Character or player.CharacterAdded:Wait()

	humanoid = character:FindFirstChildOfClass("Humanoid")
	root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		warn("[AdminFly] Personaje no listo.")
		return
	end

	-- Limpia cualquier vuelo anterior con el mismo nombre.
	for _, name in ipairs({
		"AdminChatFlyAttachment",
		"AdminChatFlyVelocity",
		"AdminChatFlyOrientation",
		}) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	flying = true
	player:SetAttribute("AdminFlying", true)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	attachment = Instance.new("Attachment")
	attachment.Name = "AdminChatFlyAttachment"
	attachment.Parent = root

	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "AdminChatFlyVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Parent = root

	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "AdminChatFlyOrientation"
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 18
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Parent = root

	renderConnection = RunService.RenderStepped:Connect(function()
		if not flying or not root or not root.Parent then
			stopFly()
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		linearVelocity.VectorVelocity = getMoveVector() * FLY_SPEED

		local look = camera.CFrame.LookVector
		local horizontalLook = Vector3.new(look.X, 0, look.Z)

		if horizontalLook.Magnitude > 0.001 then
			alignOrientation.CFrame = CFrame.lookAt(
				root.Position,
				root.Position + horizontalLook.Unit
			)
		end
	end)
end

local function toggleFly()
	if flying then
		stopFly()
	else
		startFly()
	end
end

remote.OnClientEvent:Connect(toggleFly)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not flying then
		return
	end

	local direction = keyMap[input.KeyCode]
	if direction then
		move[direction] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local direction = keyMap[input.KeyCode]
	if direction then
		move[direction] = false
	end
end)

player.CharacterAdded:Connect(function()
	if flying then
		stopFly()
	end
end)

player:SetAttribute("AdminFlying", false)
