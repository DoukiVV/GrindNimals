--============================================================
-- FAROS NOCHE SERVER V7 - BRILLO SUAVE
-- Ubicacion:
-- ServerScriptService > FarosNightServer
-- Tipo: Script
--
-- CORRECCION:
-- La V5 bajaba demasiado el Range y quitaba el aspecto encendido.
-- Esta version mantiene:
--   * Brightness = 0.30
--   * Range original de cada faro (por ejemplo 70)
--   * Color frio/blanco suave
--   * Bombilla clara SIN Neon exagerado
--
-- DIA:
--   * Luz apagada
--
-- NOCHE:
--   * Luz encendida
--   * Brightness 0.30
--   * Range original
--
-- Compatible con /day /night /auto.
--============================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local worldTime = ReplicatedStorage:WaitForChild("WorldTime")
local phaseValue = worldTime:WaitForChild("Phase")

local farosFolder = Workspace:WaitForChild("Faros")

--============================================================
-- CONFIG
--============================================================

local CHECK_INTERVAL = 0.5

-- Lo que dijiste que te gusto.
local NIGHT_BRIGHTNESS = 0.30

-- Luz fria pero colorida.
local NIGHT_LIGHT_COLOR = Color3.fromRGB(225, 238, 255)

-- La pieza visible de la bombilla.
local NIGHT_PART_COLOR = Color3.fromRGB(195, 210, 225)

-- Neon, pero con un color mas apagado para que brille sin molestar.
local NIGHT_PART_MATERIAL = Enum.Material.Neon
local DAY_PART_MATERIAL = Enum.Material.SmoothPlastic

--============================================================
-- GUARDAR CONFIG ORIGINAL
--============================================================

local lightOriginal = {}
local partOriginal = {}

local function isLight(object)
	return object:IsA("PointLight")
		or object:IsA("SpotLight")
		or object:IsA("SurfaceLight")
end

local function findLampPart(light)
	local parent = light and light.Parent

	if parent and parent:IsA("BasePart") then
		return parent
	end

	if parent then
		return parent:FindFirstAncestorWhichIsA("BasePart")
	end

	return nil
end

local function rememberLight(light)
	if not lightOriginal[light] then
		lightOriginal[light] = {
			Range = light:IsA("PointLight") and light.Range or nil,
			Color = light.Color,
			Shadows = light.Shadows,
		}
	end

	local part = findLampPart(light)

	if part and not partOriginal[part] then
		partOriginal[part] = {
			Color = part.Color,
			Material = part.Material,
		}
	end
end

--============================================================
-- ENCENDER / APAGAR
--============================================================

local function setLightState(light, enabled)
	rememberLight(light)

	local info = lightOriginal[light]
	local part = findLampPart(light)

	if enabled then
		light.Enabled = true
		light.Brightness = NIGHT_BRIGHTNESS
		light.Color = NIGHT_LIGHT_COLOR
		light.Shadows = false

		-- IMPORTANTE:
		-- NO reducimos el Range.
		-- Conserva el que ya tenias configurado (ej. 70).
		if light:IsA("PointLight") and info and info.Range then
			light.Range = info.Range
		end

		-- Bombilla con brillo visible, pero mas suave que antes.
		if part then
			part.Material = NIGHT_PART_MATERIAL
			part.Color = NIGHT_PART_COLOR
		end
	else
		light.Enabled = false
		light.Brightness = 0

		if light:IsA("PointLight") and info and info.Range then
			light.Range = info.Range
		end

		if part then
			local originalPart = partOriginal[part]

			part.Material = DAY_PART_MATERIAL

			if originalPart then
				part.Color = originalPart.Color
			end
		end
	end
end

local function shouldBeOn()
	return phaseValue.Value == "Noche"
end

local function updateAllFaros()
	local enabled = shouldBeOn()
	local count = 0

	for _, object in ipairs(farosFolder:GetDescendants()) do
		if isLight(object) then
			setLightState(object, enabled)
			count += 1
		end
	end

	return count
end

--============================================================
-- CAMBIO DIA / NOCHE
--============================================================

phaseValue:GetPropertyChangedSignal("Value"):Connect(function()
	local count = updateAllFaros()

	if shouldBeOn() then
		print(
			"[Faros] Noche: "
				.. tostring(count)
				.. " luces ON | Brightness 0.30 | Range original."
		)
	else
		print(
			"[Faros] Dia: "
				.. tostring(count)
				.. " luces OFF."
		)
	end
end)

--============================================================
-- FAROS NUEVOS
--============================================================

farosFolder.DescendantAdded:Connect(function(object)
	task.defer(function()
		if isLight(object) then
			setLightState(object, shouldBeOn())
		end
	end)
end)

farosFolder.DescendantRemoving:Connect(function(object)
	lightOriginal[object] = nil
	partOriginal[object] = nil
end)

--============================================================
-- REFUERZO
--============================================================

task.spawn(function()
	while farosFolder.Parent do
		updateAllFaros()
		task.wait(CHECK_INTERVAL)
	end
end)

local count = updateAllFaros()

print(
	"[Faros] V7 BRILLO SUAVE activo | "
		.. tostring(count)
		.. " luces encontradas | fase: "
		.. tostring(phaseValue.Value)
)
