--============================================================
-- PetFrankViewportController
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > Client > PetFrankViewportController
--
-- Responsabilidad:
-- - Corregir CurrentPetPreview
-- - Corregir NextPetPreview
-- - Mostrar mascota base 3D en requisitos de Frank
--
-- NO controla Slot 2.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local petsShared = ReplicatedStorage
	:WaitForChild("GameShared")
	:WaitForChild("Pets")

local PetNames = require(petsShared:WaitForChild("PetNames"))
local ClientFolder = petsShared:WaitForChild("Client")
local PetModelResolver = require(ClientFolder:WaitForChild("PetModelResolver"))

local PetFrankViewportController = {}

local started = false
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findTextLabelByText(text)
	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("TextLabel") and obj.Text == text then
			return obj
		end
	end

	return nil
end

local function addBasePetViewportToRequirement(req)
	if typeof(req) ~= "table" or req.kind ~= "Pet" then
		return
	end

	local label = findTextLabelByText(tostring(req.name or ""))
	if not label then
		return
	end

	local card = label.Parent
	if not card or not card:IsA("GuiObject") then
		return
	end

	local viewport = card:FindFirstChild("BasePetRequirementViewport")

	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name = "BasePetRequirementViewport"
		viewport.BackgroundTransparency = 1
		viewport.Position = UDim2.fromOffset(6, 5)
		viewport.Size = UDim2.new(1, -12, 0, 64)
		viewport.Ambient = Color3.fromRGB(255, 255, 255)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		viewport.ZIndex = math.max(card.ZIndex + 2, label.ZIndex)
		viewport.Parent = card
	end

	PetModelResolver.SetViewportModel(
		viewport,
		PetModelResolver.FindBaseModel(req.petName or req.name)
	)

	label.Position = UDim2.fromOffset(4, 68)
	label.Size = UDim2.new(1, -8, 0, 30)
	label.Text = PetNames.Canonical(req.petName or req.name)
	label.TextWrapped = true
	label.TextScaled = true

	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")

	if not constraint then
		constraint = Instance.new("UITextSizeConstraint")
		constraint.Parent = label
	end

	constraint.MinTextSize = 7
	constraint.MaxTextSize = 11
end

function PetFrankViewportController.Start()
	if started then
		return
	end
	started = true

	-- Esto permite usar el mismo paquete en mundos donde Frank no existe.
	local petUpgradeSystem = ReplicatedStorage:FindFirstChild("PetUpgradeSystem")

	if not petUpgradeSystem then
		print("[PetFrankViewportController] INACTIVO | este mundo no tiene PetUpgradeSystem.")
		return
	end

	local GetUpgradeInfo = petUpgradeSystem:FindFirstChild("GetUpgradeInfo")
	local OpenUpgradeUI = petUpgradeSystem:FindFirstChild("OpenUpgradeUI")

	if not GetUpgradeInfo
		or not GetUpgradeInfo:IsA("RemoteFunction")
		or not OpenUpgradeUI
		or not OpenUpgradeUI:IsA("RemoteEvent") then

		warn("[PetFrankViewportController] PetUpgradeSystem incompleto.")
		return
	end

	local function patchFrankNow()
		local ok, data = pcall(function()
			return GetUpgradeInfo:InvokeServer()
		end)

		if not ok or typeof(data) ~= "table" or not data.ok then
			return
		end

		local currentViewport =
			playerGui:FindFirstChild("CurrentPetPreview", true)

		if currentViewport
			and currentViewport:IsA("ViewportFrame") then

			local currentModel

			if PetModelResolver.NormalizeTier(data.currentTier) == "Base" then
				currentModel =
					PetModelResolver.FindBaseModel(data.petName)
			else
				currentModel =
					PetModelResolver.FindVariantModel(
						data.currentTier,
						data.petName
					)
			end

			PetModelResolver.SetViewportModel(
				currentViewport,
				currentModel
			)
		end

		local nextViewport =
			playerGui:FindFirstChild("NextPetPreview", true)

		if nextViewport
			and nextViewport:IsA("ViewportFrame")
			and not data.maxLevel then

			PetModelResolver.SetViewportModel(
				nextViewport,
				PetModelResolver.FindVariantModel(
					data.nextTier,
					data.petName
				)
			)
		end

		for _, req in ipairs(data.requirements or {}) do
			if req.kind == "Pet" then
				addBasePetViewportToRequirement(req)
			end
		end
	end

	local function patchFrankRepeatedly()
		for _, delayTime in ipairs({
			0.05,
			0.25,
			0.55,
			0.9,
			1.3,
			}) do
			task.delay(delayTime, patchFrankNow)
		end
	end

	OpenUpgradeUI.OnClientEvent:Connect(
		patchFrankRepeatedly
	)

	player:GetAttributeChangedSignal(
		"SelectedBackpackPetTier"
	):Connect(patchFrankRepeatedly)

	playerGui.DescendantAdded:Connect(function(obj)
		if obj.Name == "CurrentPetPreview"
			or obj.Name == "NextPetPreview"
			or obj.Name == "FruitIcon" then

			task.defer(patchFrankNow)
		end
	end)
end

return PetFrankViewportController
