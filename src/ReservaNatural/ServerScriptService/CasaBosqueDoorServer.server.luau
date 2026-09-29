--============================================================
-- CASA BOSQUE
-- PUERTA AUTOMATICA + TP SUAVE
--
-- UBICACION:
-- ServerScriptService > CasaBosqueDoorServer
--
-- EXTERIOR:
-- Workspace
-- └─ Casa bosque
--    ├─ Puerta tienda de cultivos
--    │  ├─ Hinge
--    │  └─ Puerta
--    │     └─ Union
--    └─ TpCasaBosque
--
-- INTERIOR:
-- Workspace
-- └─ Interior casa bosque
--    ├─ Puerta tienda de cultivos
--    │  ├─ Hinge
--    │  └─ Puerta
--    │     └─ Union
--    └─ TpCasaInteriorBosque
--
-- CREA:
-- ReplicatedStorage.CasaBosqueTeleportFX
--============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================================
-- CONFIGURACION
--============================================================

local DISTANCIA_ABRIR = 12
local DISTANCIA_TP = 4.5
local DISTANCIA_REACTIVAR_TP = 9

local TIEMPO_ABRIR = 0.55
local TIEMPO_CERRAR = 0.65
local ESPERA_CERRAR = 1.2

local TIEMPO_FADE_OUT = 0.28
local TIEMPO_ESTABILIZAR_TP = 0.10

local ALTURA_TP = 3

-- Si abre hacia el lado incorrecto:
-- cambia -95 por 95.
local ANGULO_PUERTA_EXTERIOR = -95
local ANGULO_PUERTA_INTERIOR = -95

--============================================================
-- REMOTE
--============================================================

local REMOTE_NAME = "CasaBosqueTeleportFX"

local teleportFX =
	ReplicatedStorage:FindFirstChild(REMOTE_NAME)

if teleportFX and not teleportFX:IsA("RemoteEvent") then
	teleportFX:Destroy()
	teleportFX = nil
end

if not teleportFX then
	teleportFX = Instance.new("RemoteEvent")
	teleportFX.Name = REMOTE_NAME
	teleportFX.Parent = ReplicatedStorage
end

--============================================================
-- BUSCAR OBJETOS
--============================================================

local casaExterior =
	workspace:WaitForChild("Casa bosque")

local interiorBosque =
	workspace:WaitForChild("Interior casa bosque")

local puertaExteriorModelo =
	casaExterior:WaitForChild(
		"Puerta tienda de cultivos"
	)

local puertaInteriorModelo =
	interiorBosque:WaitForChild(
		"Puerta tienda de cultivos"
	)

local tpExterior =
	casaExterior:WaitForChild(
		"TpCasaBosque"
	)

local tpInterior =
	interiorBosque:WaitForChild(
		"TpCasaInteriorBosque"
	)

--============================================================
-- VALIDAR TP
--============================================================

local function prepararTP(part)

	if not part:IsA("BasePart") then
		error(
			"[CasaBosque] "
				.. part:GetFullName()
				.. " debe ser BasePart."
		)
	end

	part.Transparency = 1
	part.Anchored = true

	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

end

prepararTP(tpExterior)
prepararTP(tpInterior)

--============================================================
-- CREAR PUERTA
--
-- MISMO METODO DE LA TIENDA:
-- Hinge = pivote.
-- Union = referencia de distancia.
-- Todas las partes dentro de Puerta giran juntas.
--============================================================

local function crearPuerta(
	modelo,
	anguloAbierto,
	nombre
)

	--------------------------------------------------------
	-- HINGE
	--------------------------------------------------------

	local hinge =
		modelo:WaitForChild("Hinge")

	if not hinge:IsA("BasePart") then
		error(
			"[CasaBosque] "
				.. nombre
				.. ": Hinge debe ser BasePart."
		)
	end

	hinge.Anchored = true

	--------------------------------------------------------
	-- PUERTA
	--------------------------------------------------------

	local puerta =
		modelo:WaitForChild("Puerta")

	--------------------------------------------------------
	-- UNION
	--------------------------------------------------------

	local union =
		puerta:FindFirstChild("Union")

	if not union then

		union =
			puerta:FindFirstChildWhichIsA(
				"UnionOperation",
				true
			)

	end

	if not union then
		error(
			"[CasaBosque] No encontre Union dentro de "
				.. puerta:GetFullName()
		)
	end

	--------------------------------------------------------
	-- PARTES QUE GIRAN
	--------------------------------------------------------

	local partes = {}

	if puerta:IsA("BasePart") then
		table.insert(
			partes,
			puerta
		)
	end

	for _, objeto in ipairs(
		puerta:GetDescendants()
		) do

		if objeto:IsA("BasePart") then
			table.insert(
				partes,
				objeto
			)
		end

	end

	--------------------------------------------------------
	-- CONFIGURAR
	--------------------------------------------------------

	for _, parte in ipairs(partes) do

		parte.Anchored = true

		-- Para que no empuje al jugador.
		parte.CanCollide = false
		parte.CanTouch = false

	end

	--------------------------------------------------------
	-- POSICIONES ORIGINALES
	--------------------------------------------------------

	local posicionesOriginales = {}

	for _, parte in ipairs(partes) do

		posicionesOriginales[parte] =
			hinge.CFrame:ToObjectSpace(
				parte.CFrame
			)

	end

	--------------------------------------------------------
	-- ANGULO
	--------------------------------------------------------

	local angulo =
		Instance.new("NumberValue")

	angulo.Name =
		"CasaBosqueDoorAngle_" .. nombre

	angulo.Value = 0
	angulo.Parent = script

	--------------------------------------------------------
	-- ACTUALIZAR
	--------------------------------------------------------

	local function actualizarPuerta()

		local rotacion =
			CFrame.Angles(
				0,
				math.rad(angulo.Value),
				0
			)

		for _, parte in ipairs(partes) do

			if parte.Parent then

				parte.CFrame =
					hinge.CFrame
					* rotacion
					* posicionesOriginales[parte]

			end

		end

	end

	angulo:GetPropertyChangedSignal(
		"Value"
	):Connect(actualizarPuerta)

	--------------------------------------------------------
	-- ESTADO
	--------------------------------------------------------

	local abierta = false
	local tweenActual = nil
	local ultimoJugadorCerca = 0

	--------------------------------------------------------
	-- ABRIR
	--------------------------------------------------------

	local function abrir()

		ultimoJugadorCerca =
			os.clock()

		if abierta then
			return
		end

		abierta = true

		if tweenActual then
			tweenActual:Cancel()
		end

		tweenActual =
			TweenService:Create(
				angulo,

				TweenInfo.new(
					TIEMPO_ABRIR,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),

				{
					Value = anguloAbierto
				}
			)

		tweenActual:Play()

	end

	--------------------------------------------------------
	-- CERRAR
	--------------------------------------------------------

	local function cerrar()

		if not abierta then
			return
		end

		abierta = false

		if tweenActual then
			tweenActual:Cancel()
		end

		tweenActual =
			TweenService:Create(
				angulo,

				TweenInfo.new(
					TIEMPO_CERRAR,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				),

				{
					Value = 0
				}
			)

		tweenActual:Play()

	end

	--------------------------------------------------------
	-- DISTANCIA
	--------------------------------------------------------

	local function distanciaDesde(posicion)

		return (
			posicion - union.Position
		).Magnitude

	end

	return {

		Model = modelo,
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

--============================================================
-- CREAR PUERTAS
--============================================================

local puertaExterior =
	crearPuerta(
		puertaExteriorModelo,
		ANGULO_PUERTA_EXTERIOR,
		"Exterior"
	)

local puertaInterior =
	crearPuerta(
		puertaInteriorModelo,
		ANGULO_PUERTA_INTERIOR,
		"Interior"
	)

--============================================================
-- ESTADO TP
--============================================================

local tpBloqueado = {}
local teleportando = {}

--============================================================
-- PERSONAJE
--============================================================

local function obtenerPersonaje(player)

	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if
		not humanoid
		or not root
		or humanoid.Health <= 0
	then

		return nil, nil, nil

	end

	return character, humanoid, root

end

local function obtenerRoot(player)

	local _, _, root =
		obtenerPersonaje(player)

	return root

end

--============================================================
-- POSICION SEGURA DEL TP
--============================================================

local function obtenerCFrameSeguro(destino)

	local posicion =
		destino.Position
		+ Vector3.new(
			0,
			ALTURA_TP,
			0
		)

	local look =
		destino.CFrame.LookVector

	local horizontal =
		Vector3.new(
			look.X,
			0,
			look.Z
		)

	if horizontal.Magnitude < 0.01 then

		horizontal =
			Vector3.new(
				0,
				0,
				-1
			)

	else

		horizontal =
			horizontal.Unit

	end

	return CFrame.lookAt(
		posicion,
		posicion + horizontal,
		Vector3.yAxis
	)

end

--============================================================
-- TELEPORT SUAVE
--============================================================

local function teleportar(
	player,
	destino,
	mensaje
)

	if teleportando[player] then
		return
	end

	local character,
		humanoid,
		root =
		obtenerPersonaje(player)

	if
		not character
		or not humanoid
		or not root
	then
		return
	end

	teleportando[player] = true
	tpBloqueado[player] = true

	--------------------------------------------------------
	-- BLOQUEAR JUGADOR
	--------------------------------------------------------

	local autoRotateAnterior =
		humanoid.AutoRotate

	humanoid.AutoRotate = false
	humanoid.Sit = false

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	root.Anchored = true

	--------------------------------------------------------
	-- OSCURECER
	--------------------------------------------------------

	teleportFX:FireClient(
		player,
		"Out",
		mensaje
	)

	task.wait(
		TIEMPO_FADE_OUT
	)

	--------------------------------------------------------
	-- VALIDAR
	--------------------------------------------------------

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
			humanoid.AutoRotate =
				autoRotateAnterior
		end

		teleportando[player] = nil

		teleportFX:FireClient(
			player,
			"In"
		)

		return
	end

	--------------------------------------------------------
	-- TELETRANSPORTAR
	--------------------------------------------------------

	character:PivotTo(
		obtenerCFrameSeguro(
			destino
		)
	)

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	task.wait(
		TIEMPO_ESTABILIZAR_TP
	)

	--------------------------------------------------------
	-- DESBLOQUEAR
	--------------------------------------------------------

	if root.Parent then

		root.AssemblyLinearVelocity =
			Vector3.zero

		root.AssemblyAngularVelocity =
			Vector3.zero

		root.Anchored = false

	end

	if humanoid.Parent then

		humanoid.AutoRotate =
			autoRotateAnterior

		pcall(function()

			humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)

		end)

	end

	--------------------------------------------------------
	-- MOSTRAR
	--------------------------------------------------------

	teleportFX:FireClient(
		player,
		"In"
	)

	task.delay(
		0.25,
		function()

			teleportando[player] = nil

		end
	)

end

--============================================================
-- LOOP
--============================================================

local acumulador = 0

RunService.Heartbeat:Connect(
	function(deltaTime)

		acumulador += deltaTime

		if acumulador < 0.08 then
			return
		end

		acumulador = 0

		local alguienExterior = false
		local alguienInterior = false

		for _, player in ipairs(
			Players:GetPlayers()
			) do

			local root =
				obtenerRoot(player)

			if root then

				local distanciaExterior =
					puertaExterior.Distancia(
						root.Position
					)

				local distanciaInterior =
					puertaInterior.Distancia(
						root.Position
					)

				--------------------------------------------
				-- ABRIR EXTERIOR
				--------------------------------------------

				if
					distanciaExterior
					<= DISTANCIA_ABRIR
				then

					alguienExterior = true
					puertaExterior.Abrir()

				end

				--------------------------------------------
				-- ABRIR INTERIOR
				--------------------------------------------

				if
					distanciaInterior
					<= DISTANCIA_ABRIR
				then

					alguienInterior = true
					puertaInterior.Abrir()

				end

				--------------------------------------------
				-- REACTIVAR TP
				--------------------------------------------

				if tpBloqueado[player] then

					if
						distanciaExterior
						> DISTANCIA_REACTIVAR_TP
						and
						distanciaInterior
						> DISTANCIA_REACTIVAR_TP
						and
						not teleportando[player]
					then

						tpBloqueado[player] = nil

					end

				else

					----------------------------------------
					-- ENTRAR
					----------------------------------------

					if
						distanciaExterior
						<= DISTANCIA_TP
					then

						task.spawn(
							teleportar,
							player,
							tpInterior,
							"Entrando a la casa..."
						)

						----------------------------------------
						-- SALIR
						----------------------------------------

					elseif
						distanciaInterior
						<= DISTANCIA_TP
					then

						task.spawn(
							teleportar,
							player,
							tpExterior,
							"Saliendo de la casa..."
						)

					end

				end

			end

		end

		--------------------------------------------
		-- CERRAR EXTERIOR
		--------------------------------------------

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

		--------------------------------------------
		-- CERRAR INTERIOR
		--------------------------------------------

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

	end
)

--============================================================
-- LIMPIEZA
--============================================================

Players.PlayerRemoving:Connect(
	function(player)

		tpBloqueado[player] = nil
		teleportando[player] = nil

	end
)

--============================================================
-- LISTO
--============================================================

print(
	"[CasaBosque] Puertas + TP suave funcionando."
)

print(
	"[CasaBosque] Exterior:",
	casaExterior:GetFullName()
)

print(
	"[CasaBosque] Entrada:",
	tpExterior:GetFullName()
)

print(
	"[CasaBosque] Interior:",
	interiorBosque:GetFullName()
)

print(
	"[CasaBosque] Destino:",
	tpInterior:GetFullName()
)