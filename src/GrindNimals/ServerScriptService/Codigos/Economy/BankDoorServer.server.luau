--============================================================
-- BANCO - PUERTAS DOBLES EXTERIOR + INTERIOR
--
-- COLOCAR EN:
-- ServerScriptService > BankDoorServer
--
-- Mantiene el sistema de pivote en el BORDE OPUESTO de "Orilla".
-- "Orilla" NO gira.
--
-- Abre:
-- 1) Workspace > Lobby > Banco > Puertas del banco
-- 2) Workspace > Interiores > Interior banco > Puertas del interior del banco
--
-- Las dos hojas de cada entrada abren al mismo tiempo.
--============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--============================================================
-- CONFIGURACION
--============================================================

local DISTANCIA_ABRIR = 13

local ANGULO_DERECHA = 78
local ANGULO_IZQUIERDA = -78

local TIEMPO_ABRIR = 0.62
local TIEMPO_CERRAR = 0.72
local ESPERA_CERRAR = 1.20

--============================================================
-- HELPERS
--============================================================

local function normalizeName(value)
	local text = tostring(value or ""):lower()

	text = text
		:gsub("á", "a")
		:gsub("é", "e")
		:gsub("í", "i")
		:gsub("ó", "o")
		:gsub("ú", "u")
		:gsub("ü", "u")
		:gsub("ñ", "n")

	text = text:gsub("[%s_%-]+", "")

	return text
end

local function findRecursive(root, wantedNames)
	local wanted = {}

	for _, name in ipairs(wantedNames) do
		wanted[normalizeName(name)] = true
	end

	for _, child in ipairs(root:GetChildren()) do
		if wanted[normalizeName(child.Name)] then
			return child
		end
	end

	for _, obj in ipairs(root:GetDescendants()) do
		if wanted[normalizeName(obj.Name)] then
			return obj
		end
	end

	return nil
end

local function findOrilla(modelo)
	local orilla = findRecursive(
		modelo,
		{
			"Orilla",
			"Border",
			"Pivot",
		}
	)

	if orilla and orilla:IsA("BasePart") then
		return orilla
	end

	return nil
end

local function getMovingParts(modelo, orilla)
	local partes = {}

	if modelo:IsA("BasePart") and modelo ~= orilla then
		table.insert(partes, modelo)
	end

	for _, obj in ipairs(modelo:GetDescendants()) do
		if obj:IsA("BasePart") and obj ~= orilla then
			table.insert(partes, obj)
		end
	end

	return partes
end

local function getAverageCenter(partes)
	local total = Vector3.zero
	local count = 0

	for _, parte in ipairs(partes) do
		total += parte.Position
		count += 1
	end

	if count == 0 then
		return Vector3.zero
	end

	return total / count
end

-- Usa el BORDE OPUESTO de Orilla como bisagra.
local function getHingeEdgePosition(orilla, movingCenter)
	local localPoint = orilla.CFrame:PointToObjectSpace(movingCenter)
	local offsetLocal

	if math.abs(localPoint.X) >= math.abs(localPoint.Z) then
		local side = localPoint.X >= 0 and 1 or -1
		side = -side

		offsetLocal = Vector3.new(
			(orilla.Size.X * 0.5) * side,
			0,
			0
		)
	else
		local side = localPoint.Z >= 0 and 1 or -1
		side = -side

		offsetLocal = Vector3.new(
			0,
			0,
			(orilla.Size.Z * 0.5) * side
		)
	end

	return orilla.CFrame:PointToWorldSpace(offsetLocal)
end

--============================================================
-- UNA HOJA DE PUERTA
--============================================================

local function crearHoja(modelo, anguloAbierto, nombre)
	local orilla = findOrilla(modelo)

	if not orilla then
		error("[Banco] " .. nombre .. " no tiene una BasePart llamada Orilla.")
	end

	orilla.Anchored = true

	local partes = getMovingParts(modelo, orilla)

	if #partes == 0 then
		error("[Banco] " .. nombre .. " no tiene piezas moviles.")
	end

	for _, parte in ipairs(partes) do
		parte.Anchored = true
		parte.CanTouch = false
	end

	local movingCenter = getAverageCenter(partes)

	local pivotPosition = getHingeEdgePosition(
		orilla,
		movingCenter
	)

	local pivot = CFrame.new(pivotPosition)
	local offsets = {}

	for _, parte in ipairs(partes) do
		offsets[parte] = pivot:ToObjectSpace(parte.CFrame)
	end

	local oldAngle = modelo:FindFirstChild("BankDoorAngle_" .. nombre)
	if oldAngle then
		oldAngle:Destroy()
	end

	local angleValue = Instance.new("NumberValue")
	angleValue.Name = "BankDoorAngle_" .. nombre
	angleValue.Value = 0
	angleValue.Parent = modelo

	local function actualizar()
		local rotation = CFrame.Angles(
			0,
			math.rad(angleValue.Value),
			0
		)

		for _, parte in ipairs(partes) do
			if parte.Parent then
				parte.CFrame =
					pivot
					* rotation
					* offsets[parte]
			end
		end
	end

	angleValue:GetPropertyChangedSignal("Value"):Connect(actualizar)

	local abierta = false
	local tweenActual = nil

	local function moverA(target, time, direction)
		if tweenActual then
			tweenActual:Cancel()
		end

		tweenActual = TweenService:Create(
			angleValue,
			TweenInfo.new(
				time,
				Enum.EasingStyle.Quint,
				direction
			),
			{
				Value = target
			}
		)

		tweenActual:Play()
	end

	local function abrir()
		if abierta then
			return
		end

		abierta = true

		moverA(
			anguloAbierto,
			TIEMPO_ABRIR,
			Enum.EasingDirection.Out
		)
	end

	local function cerrar()
		if not abierta then
			return
		end

		abierta = false

		moverA(
			0,
			TIEMPO_CERRAR,
			Enum.EasingDirection.InOut
		)
	end

	return {
		Abrir = abrir,
		Cerrar = cerrar,

		GetPivotPosition = function()
			return pivotPosition
		end,
	}
end

--============================================================
-- UN PAR DE PUERTAS
--============================================================

local function crearPar(contenedor, nombrePar)
	local derecha = findRecursive(
		contenedor,
		{
			"Puerta derecha",
			"PuertaDerecha",
			"Derecha",
		}
	)

	local izquierda = findRecursive(
		contenedor,
		{
			"Puerta izquierda",
			"PuertaIzquierda",
			"Izquierda",
		}
	)

	if not derecha then
		error("[Banco] No encontre Puerta derecha en " .. contenedor:GetFullName())
	end

	if not izquierda then
		error("[Banco] No encontre Puerta izquierda en " .. contenedor:GetFullName())
	end

	local hojaDerecha = crearHoja(
		derecha,
		ANGULO_DERECHA,
		nombrePar .. "_Derecha"
	)

	local hojaIzquierda = crearHoja(
		izquierda,
		ANGULO_IZQUIERDA,
		nombrePar .. "_Izquierda"
	)

	local centro =
		(
			hojaDerecha.GetPivotPosition()
			+
			hojaIzquierda.GetPivotPosition()
		)
		/ 2

	local abiertas = false
	local ultimoCerca = 0

	return {
		Centro = centro,

		Abrir = function()
			ultimoCerca = os.clock()

			if abiertas then
				return
			end

			abiertas = true

			hojaDerecha.Abrir()
			hojaIzquierda.Abrir()
		end,

		CerrarSiToca = function()
			if not abiertas then
				return
			end

			if os.clock() - ultimoCerca >= ESPERA_CERRAR then
				abiertas = false

				hojaDerecha.Cerrar()
				hojaIzquierda.Cerrar()
			end
		end,

		MarcarCerca = function()
			ultimoCerca = os.clock()
		end,
	}
end

--============================================================
-- BUSCAR EXTERIOR
--============================================================

local lobby = workspace:WaitForChild("Lobby")
local banco = lobby:WaitForChild("Banco")

local puertasExterior = findRecursive(
	banco,
	{
		"Puertas del banco",
		"Puertas banco",
		"PuertasBanco",
	}
)

if not puertasExterior then
	error("[Banco] No encontre 'Puertas del banco'.")
end

--============================================================
-- BUSCAR INTERIOR
--============================================================

local interiores = workspace:WaitForChild("Interiores")
local interiorBanco = interiores:WaitForChild("Interior banco")

local puertasInterior = findRecursive(
	interiorBanco,
	{
		"Puertas del interior del banco",
		"Puertas interior banco",
		"PuertasInteriorBanco",
	}
)

if not puertasInterior then
	error("[Banco] No encontre 'Puertas del interior del banco'.")
end

local exterior = crearPar(puertasExterior, "Exterior")
local interior = crearPar(puertasInterior, "Interior")

--============================================================
-- DISTANCIA
--============================================================

local function alguienCerca(posicion)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character

		local humanoid =
			character
			and character:FindFirstChildOfClass("Humanoid")

		local root =
			character
			and character:FindFirstChild("HumanoidRootPart")

		if humanoid and root and humanoid.Health > 0 then
			if (root.Position - posicion).Magnitude <= DISTANCIA_ABRIR then
				return true
			end
		end
	end

	return false
end

--============================================================
-- LOOP
--============================================================

local acumulador = 0

RunService.Heartbeat:Connect(function(dt)
	acumulador += dt

	if acumulador < 0.08 then
		return
	end

	acumulador = 0

	-- Exterior
	if alguienCerca(exterior.Centro) then
		exterior.MarcarCerca()
		exterior.Abrir()
	else
		exterior.CerrarSiToca()
	end

	-- Interior
	if alguienCerca(interior.Centro) then
		interior.MarcarCerca()
		interior.Abrir()
	else
		interior.CerrarSiToca()
	end
end)
