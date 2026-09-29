--============================================================
-- TIENDA DE VEGETALES
-- PUERTA AUTOMATICA + TP SUAVE
--
-- COLOCAR EN:
-- ServerScriptService > VegetableShopDoorServer
--
-- NECESITA EL LocalScript:
-- StarterPlayer > StarterPlayerScripts > VegetableShopTeleportClient
--
-- Este script mantiene el movimiento de las puertas que ya funcionaba
-- y mejora el TP con una transición visual coordinada con el cliente.
--============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================================
-- REMOTE PARA LA ANIMACION DEL TP
--============================================================

local TELEPORT_FX_REMOTE_NAME = "VegetableShopTeleportFX"

local teleportFX = ReplicatedStorage:FindFirstChild(TELEPORT_FX_REMOTE_NAME)

if teleportFX and not teleportFX:IsA("RemoteEvent") then
	teleportFX:Destroy()
	teleportFX = nil
end

if not teleportFX then
	teleportFX = Instance.new("RemoteEvent")
	teleportFX.Name = TELEPORT_FX_REMOTE_NAME
	teleportFX.Parent = ReplicatedStorage
end

--============================================================
-- CONFIGURACION
--============================================================

local DISTANCIA_ABRIR = 12
local DISTANCIA_TP = 4.5
local DISTANCIA_REACTIVAR_TP = 9

local TIEMPO_ABRIR = 0.55
local TIEMPO_CERRAR = 0.65
local ESPERA_CERRAR = 1.2

-- Duración de la parte oscura antes de mover al jugador.
-- Debe coincidir aproximadamente con FADE_OUT_TIME del LocalScript.
local TIEMPO_FADE_OUT = 0.28

-- Pequeña pausa después del PivotTo para que la física se estabilice.
local TIEMPO_ESTABILIZAR_TP = 0.10

local ALTURA_TP = 3

-- Tus ángulos que ya abren correctamente.
local ANGULO_PUERTA_EXTERIOR = -95
local ANGULO_PUERTA_INTERIOR = -95

--============================================================
-- BUSCAR EXTERIOR
--============================================================

local lobby = workspace:WaitForChild("Lobby")
local tiendaExterior = lobby:WaitForChild("Tienda de vegetales")
local puertaExteriorModelo = tiendaExterior:WaitForChild("Puerta tienda de cultivos")
local tpAfuera = tiendaExterior:WaitForChild("TpAfueraTienda")

--============================================================
-- BUSCAR INTERIOR
--============================================================

local interiores = workspace:WaitForChild("Interiores")
local tiendaInterior = interiores:WaitForChild("Tienda Cultivos")
local puertaInteriorModelo = tiendaInterior:WaitForChild("Puerta tienda de cultivos")
local tpAdentro = tiendaInterior:WaitForChild("TpAdentroTienda")

--============================================================
-- CONFIGURAR PUNTOS TP
--============================================================

local function prepararTP(part)
	if not part:IsA("BasePart") then
		error(part:GetFullName() .. " debe ser una Part")
	end

	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
end

prepararTP(tpAfuera)
prepararTP(tpAdentro)

--============================================================
-- CONTROLADOR DE PUERTA
-- Mantiene el sistema que ya te estaba abriendo bien.
--============================================================

local function crearPuerta(modelo, anguloAbierto, nombre)
	local hinge = modelo:WaitForChild("Hinge")

	if not hinge:IsA("BasePart") then
		error("[Tienda] " .. nombre .. ": Hinge no es BasePart")
	end

	local puerta = modelo:WaitForChild("Puerta")

	local union = puerta:FindFirstChild("Union")
	if not union then
		union = puerta:FindFirstChildWhichIsA("UnionOperation", true)
	end

	if not union then
		error("[Tienda] No encontre Union en " .. puerta:GetFullName())
	end

	local partes = {}

	if puerta:IsA("BasePart") then
		table.insert(partes, puerta)
	end

	for _, objeto in ipairs(puerta:GetDescendants()) do
		if objeto:IsA("BasePart") then
			table.insert(partes, objeto)
		end
	end

	-- La puerta no debe empujar al jugador.
	for _, parte in ipairs(partes) do
		parte.Anchored = true
		parte.CanCollide = false
		parte.CanTouch = false
	end

	local posicionesOriginales = {}

	for _, parte in ipairs(partes) do
		posicionesOriginales[parte] = hinge.CFrame:ToObjectSpace(parte.CFrame)
	end

	local angulo = Instance.new("NumberValue")
	angulo.Name = "DoorAngle_" .. nombre
	angulo.Value = 0

	local function actualizarPuerta()
		local rotacion = CFrame.Angles(0, math.rad(angulo.Value), 0)

		for _, parte in ipairs(partes) do
			if parte.Parent then
				parte.CFrame =
					hinge.CFrame
					* rotacion
					* posicionesOriginales[parte]
			end
		end
	end

	angulo:GetPropertyChangedSignal("Value"):Connect(actualizarPuerta)

	local abierta = false
	local tweenActual = nil
	local ultimoJugadorCerca = 0

	local function abrir()
		ultimoJugadorCerca = os.clock()

		if abierta then
			return
		end

		abierta = true

		if tweenActual then
			tweenActual:Cancel()
		end

		tweenActual = TweenService:Create(
			angulo,
			TweenInfo.new(
				TIEMPO_ABRIR,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{Value = anguloAbierto}
		)

		tweenActual:Play()
	end

	local function cerrar()
		if not abierta then
			return
		end

		abierta = false

		if tweenActual then
			tweenActual:Cancel()
		end

		tweenActual = TweenService:Create(
			angulo,
			TweenInfo.new(
				TIEMPO_CERRAR,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			),
			{Value = 0}
		)

		tweenActual:Play()
	end

	local function distanciaDesde(posicion)
		return (posicion - union.Position).Magnitude
	end

	return {
		Model = modelo,
		Hinge = hinge,
		Union = union,
		Abrir = abrir,
		Cerrar = cerrar,
		Distancia = distanciaDesde,

		EstaAbierta = function()
			return abierta
		end,

		UltimoCerca = function()
			return ultimoJugadorCerca
		end,
	}
end

local puertaExterior = crearPuerta(
	puertaExteriorModelo,
	ANGULO_PUERTA_EXTERIOR,
	"Exterior"
)

local puertaInterior = crearPuerta(
	puertaInteriorModelo,
	ANGULO_PUERTA_INTERIOR,
	"Interior"
)

--============================================================
-- BLOQUEO DE TP
--============================================================

local tpBloqueado = {}
local teleportando = {}

--============================================================
-- OBTENER PERSONAJE
--============================================================

local function obtenerPersonaje(player)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function obtenerRoot(player)
	local _, _, root = obtenerPersonaje(player)
	return root
end

--============================================================
-- CFRAME SEGURO
-- Solo conserva la dirección horizontal del Part del TP.
-- Así el personaje siempre aparece derecho.
--============================================================

local function obtenerCFrameSeguro(destino)
	local posicion = destino.Position + Vector3.new(0, ALTURA_TP, 0)
	local look = destino.CFrame.LookVector

	local direccionHorizontal = Vector3.new(
		look.X,
		0,
		look.Z
	)

	if direccionHorizontal.Magnitude < 0.01 then
		direccionHorizontal = Vector3.new(0, 0, -1)
	else
		direccionHorizontal = direccionHorizontal.Unit
	end

	return CFrame.lookAt(
		posicion,
		posicion + direccionHorizontal,
		Vector3.yAxis
	)
end

--============================================================
-- TELEPORT SUAVE
--============================================================

local function teleportar(player, destino, mensaje)
	if teleportando[player] then
		return
	end

	local character, humanoid, root = obtenerPersonaje(player)
	if not character or not humanoid or not root then
		return
	end

	teleportando[player] = true
	tpBloqueado[player] = true

	-- Detenemos al jugador desde que comienza la transición.
	local autoRotateAnterior = humanoid.AutoRotate
	humanoid.AutoRotate = false
	humanoid.Sit = false

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true

	-- 1) El cliente hace blur + zoom suave + fade.
	teleportFX:FireClient(
		player,
		"Out",
		mensaje or "Entrando..."
	)

	task.wait(TIEMPO_FADE_OUT)

	-- Validamos otra vez por si el personaje murió o desapareció.
	if
		not player.Parent
		or not character.Parent
		or not root.Parent
		or humanoid.Health <= 0
	then
		if root and root.Parent then
			root.Anchored = false
		end

		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = autoRotateAnterior
		end

		teleportando[player] = nil
		teleportFX:FireClient(player, "In")
		return
	end

	-- 2) Movemos mientras la pantalla ya está cubierta.
	character:PivotTo(
		obtenerCFrameSeguro(destino)
	)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	task.wait(TIEMPO_ESTABILIZAR_TP)

	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = false
	end

	if humanoid.Parent then
		humanoid.AutoRotate = autoRotateAnterior

		pcall(function()
			humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)
		end)
	end

	-- 3) El cliente vuelve a mostrar el mundo suavemente.
	teleportFX:FireClient(player, "In")

	-- Última limpieza de velocidad.
	task.defer(function()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end)

	task.delay(0.25, function()
		teleportando[player] = nil
	end)
end

--============================================================
-- LOOP PRINCIPAL
--============================================================

local acumulador = 0

RunService.Heartbeat:Connect(function(deltaTime)
	acumulador += deltaTime

	if acumulador < 0.08 then
		return
	end

	acumulador = 0

	local alguienExterior = false
	local alguienInterior = false

	for _, player in ipairs(Players:GetPlayers()) do
		local root = obtenerRoot(player)

		if root then
			local distanciaExterior =
				puertaExterior.Distancia(root.Position)

			local distanciaInterior =
				puertaInterior.Distancia(root.Position)

			-- Puerta exterior.
			if distanciaExterior <= DISTANCIA_ABRIR then
				alguienExterior = true
				puertaExterior.Abrir()
			end

			-- Puerta interior.
			if distanciaInterior <= DISTANCIA_ABRIR then
				alguienInterior = true
				puertaInterior.Abrir()
			end

			-- Reactivar TP cuando ya se alejó de ambas puertas.
			if tpBloqueado[player] then
				if
					distanciaExterior > DISTANCIA_REACTIVAR_TP
					and distanciaInterior > DISTANCIA_REACTIVAR_TP
					and not teleportando[player]
				then
					tpBloqueado[player] = nil
				end
			else
				-- Entrar.
				if distanciaExterior <= DISTANCIA_TP then
					task.spawn(
						teleportar,
						player,
						tpAdentro,
						"Entrando a la tienda..."
					)

					-- Salir.
				elseif distanciaInterior <= DISTANCIA_TP then
					task.spawn(
						teleportar,
						player,
						tpAfuera,
						"Saliendo de la tienda..."
					)
				end
			end
		end
	end

	-- Cerrar exterior.
	if
		not alguienExterior
		and puertaExterior.EstaAbierta()
	then
		if
			os.clock()
			- puertaExterior.UltimoCerca()
				>= ESPERA_CERRAR
		then
			puertaExterior.Cerrar()
		end
	end

	-- Cerrar interior.
	if
		not alguienInterior
		and puertaInterior.EstaAbierta()
	then
		if
			os.clock()
			- puertaInterior.UltimoCerca()
				>= ESPERA_CERRAR
		then
			puertaInterior.Cerrar()
		end
	end
end)

--============================================================
-- LIMPIEZA
--============================================================

Players.PlayerRemoving:Connect(function(player)
	tpBloqueado[player] = nil
	teleportando[player] = nil
end)
