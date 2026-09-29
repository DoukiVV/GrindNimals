--============================================================
-- PetModelResolver
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > Client > PetModelResolver
--
-- Responsabilidad:
-- - Encontrar modelo base
-- - Encontrar modelo segun pañuelo/tier
-- - Dibujar modelos en ViewportFrame
--
-- NO escucha eventos y NO toca Slot 2/Frank por si solo.
--============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local petsShared = ReplicatedStorage
	:WaitForChild("GameShared")
	:WaitForChild("Pets")

local PetNames = require(petsShared:WaitForChild("PetNames"))
local petViews = ReplicatedStorage:WaitForChild("MascotasView")

local PetModelResolver = {}

local VARIANT_FOLDERS = {
	Comun = "Mascotas pañuelos grises",
	["Poco comun"] = "Mascotas pañuelos verdes",
	Raro = "Mascotas pañuelos azul",
	Epico = "Mascotas pañuelos morado",
	Legendario = "Mascotas pañuelos dorado",
}

function PetModelResolver.NormalizeTier(tier)
	tier = tostring(tier or "Base")
	if tier == "" then
		return "Base"
	end
	return tier
end

function PetModelResolver.CanonicalPetName(name)
	return PetNames.Canonical(name)
end

function PetModelResolver.FindBaseModel(petName)
	petName = PetNames.Canonical(petName)

	local exact = petViews:FindFirstChild(petName)
	if exact and exact:IsA("Model") then
		return exact
	end

	local modelName = PetNames.ToModelName(petName)
	local modelExact = petViews:FindFirstChild(modelName)
	if modelExact and modelExact:IsA("Model") then
		return modelExact
	end

	for _, obj in ipairs(petViews:GetChildren()) do
		if obj:IsA("Model") then
			local a = PetNames.Normalize(obj.Name)
			local b = PetNames.Normalize(petName)
			local c = PetNames.Normalize(modelName)

			if a == b
				or a == c
				or a:find(b, 1, true)
				or b:find(a, 1, true)
				or a:find(c, 1, true)
				or c:find(a, 1, true) then
				return obj
			end

			if PetNames.IsSheepName(obj.Name)
				and PetNames.IsSheepName(petName) then
				return obj
			end
		end
	end

	return nil
end

function PetModelResolver.FindVariantFolder(tier)
	local folderName = VARIANT_FOLDERS[PetModelResolver.NormalizeTier(tier)]
	if not folderName then
		return nil
	end

	for _, root in ipairs({Workspace, ReplicatedStorage}) do
		local animals = root:FindFirstChild("Animales pañuelos")

		if animals then
			local direct = animals:FindFirstChild(folderName)
			if direct then
				return direct
			end
		end

		local nested = root:FindFirstChild(folderName, true)
		if nested then
			return nested
		end
	end

	return nil
end

function PetModelResolver.FindVariantModel(tier, petName)
	tier = PetModelResolver.NormalizeTier(tier)
	petName = PetNames.Canonical(petName)

	if tier == "Base" then
		return PetModelResolver.FindBaseModel(petName)
	end

	local folder = PetModelResolver.FindVariantFolder(tier)
	if not folder then
		return nil
	end

	local exact = folder:FindFirstChild(petName)
	if exact and exact:IsA("Model") then
		return exact
	end

	local modelName = PetNames.ToModelName(petName)
	local modelExact = folder:FindFirstChild(modelName)
	if modelExact and modelExact:IsA("Model") then
		return modelExact
	end

	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("Model") then
			if PetNames.NamesMatch(obj.Name, petName)
				or PetNames.NamesMatch(obj.Name, modelName) then
				return obj
			end
		end
	end

	return nil
end

local function cleanCloneForViewport(source)
	local clone = source:Clone()

	for _, object in ipairs(clone:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
		elseif object:IsA("Script")
			or object:IsA("LocalScript")
			or object:IsA("ModuleScript") then
			object:Destroy()
		elseif object:IsA("ParticleEmitter")
			or object:IsA("Trail")
			or object:IsA("Beam") then
			object.Enabled = false
		end
	end

	return clone
end

function PetModelResolver.SetViewportModel(viewport, sourceModel)
	if not viewport or not viewport:IsA("ViewportFrame") then
		return
	end

	viewport:ClearAllChildren()

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PetViewportWorld"
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Name = "PetViewportCamera"
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if not sourceModel then
		return
	end

	local clone = cleanCloneForViewport(sourceModel)
	clone.Parent = worldModel

	local root = clone:FindFirstChild("HumanoidRootPart", true)
		or clone.PrimaryPart
		or clone:FindFirstChildWhichIsA("BasePart", true)

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundVisiblePart = false

	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart")
			and part.Name ~= "HumanoidRootPart"
			and part.Transparency < 0.98 then

			foundVisiblePart = true
			local half = part.Size * 0.5

			for _, x in ipairs({-1, 1}) do
				for _, y in ipairs({-1, 1}) do
					for _, z in ipairs({-1, 1}) do
						local point = part.CFrame:PointToWorldSpace(
							Vector3.new(half.X * x, half.Y * y, half.Z * z)
						)

						minV = Vector3.new(
							math.min(minV.X, point.X),
							math.min(minV.Y, point.Y),
							math.min(minV.Z, point.Z)
						)

						maxV = Vector3.new(
							math.max(maxV.X, point.X),
							math.max(maxV.Y, point.Y),
							math.max(maxV.Z, point.Z)
						)
					end
				end
			end
		end
	end

	local visualCenter
	local visualSize

	if foundVisiblePart then
		visualCenter = (minV + maxV) * 0.5
		visualSize = maxV - minV
	else
		local boxCf, boxSize = clone:GetBoundingBox()
		visualCenter = boxCf.Position
		visualSize = boxSize
	end

	local front = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	local up = root and root.CFrame.UpVector or Vector3.new(0, 1, 0)
	local right = root and root.CFrame.RightVector or Vector3.new(1, 0, 0)

	local projectedWidth = math.max(visualSize.X, visualSize.Z)
	local projectedHeight = visualSize.Y

	local targetHalfExtent = math.max(
		projectedHeight * 0.5,
		projectedWidth * 0.5,
		0.5
	)

	local halfFov = math.rad(camera.FieldOfView * 0.5)
	local distance = targetHalfExtent / math.tan(halfFov)

	local sideOffset = distance

	camera.CFrame = CFrame.lookAt(
		visualCenter
			+ front * distance
			+ right * sideOffset
			+ up * (visualSize.Y * 0.04),

		visualCenter + up * (visualSize.Y * 0.04),
		up
	)
end

return PetModelResolver
