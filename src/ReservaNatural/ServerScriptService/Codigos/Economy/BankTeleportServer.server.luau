--============================================================
-- BANCO - TELEPORT + TRANSICION SUAVE
--
-- COLOCAR EN:
-- ServerScriptService > BankTeleportServer
--
-- NECESITA:
-- StarterPlayer > StarterPlayerScripts > BankTeleportClient
--
-- Al entrar:
-- exterior -> TpInteriorbank
--
-- Al salir:
-- interior -> posicion guardada afuera
--
-- Incluye:
-- - fade/blur coordinado con el cliente
-- - bloqueo anti-rebote
-- - personaje estabilizado
--============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--============================================================
-- REMOTE
--============================================================

local REMOTE_NAME = "BankTeleportFX"

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)

if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end

if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

--============================================================
-- CONFIG
--============================================================

local DISTANCIA_TP = 4.5
local DISTANCIA_REACTIVAR = 9

local ALTURA_INTERIOR = 3
local ALTURA_RETORNO = 1.5

local TIEMPO_FADE_OUT = 0.28
local TIEMPO_ESTABILIZAR = 0.12

--============================================================
-- REFERENCES
--============================================================

local lobby = workspace:WaitForChild("Lobby")
local banco = lobby:WaitForChild("Banco")
local puertasExterior = banco:WaitForChild("Puertas del banco")

local interiores = workspace:WaitForChild("Interiores")
local interiorBanco = interiores:WaitForChild("Interior banco")

local puertasInterior =
	interiorBanco:WaitForChild("Puertas del interior del banco")

--============================================================
-- BUSCAR TpInteriorbank DE FORMA ROBUSTA
--
-- En tu estructura TpInteriorbank está dentro de:
-- Interior banco > Puertas del interior del banco > TpInteriorbank
-- por eso NO debemos usar interiorBanco:WaitForChild("TpInteriorbank").
--============================================================

local tpInterior = interiorBanco:FindFirstChild("TpInteriorbank", true)

if not tpInterior then
	error(
		"[BankTeleport] No encontré TpInteriorbank dentro de "
			.. interiorBanco:GetFullName()
	)
end

if not tpInterior:IsA("BasePart") then
	error(
		"[BankTeleport] TpInteriorbank existe pero no es una BasePart: "
			.. tpInterior:GetFullName()
	)
end

--============================================================
-- BUSCAR TpExteriorbank
--
-- Tu estructura:
-- Workspace > Lobby > Banco > TpExteriorbank
--============================================================

local tpExterior = banco:FindFirstChild("TpExteriorbank", true)

if not tpExterior then
	error(
		"[BankTeleport] No encontré TpExteriorbank dentro de "
			.. banco:GetFullName()
	)
end

if not tpExterior:IsA("BasePart") then
	error(
		"[BankTeleport] TpExteriorbank existe pero no es una BasePart: "
			.. tpExterior:GetFullName()
	)
end

tpInterior.Anchored = true
tpInterior.CanCollide = false
tpInterior.CanTouch = false
tpInterior.CanQuery = false
tpInterior.Transparency = 1

tpExterior.Anchored = true
tpExterior.CanCollide = false
tpExterior.CanTouch = false
tpExterior.CanQuery = false
tpExterior.Transparency = 1

--============================================================
-- CENTRO
--============================================================

local function obtenerCentro(root)
	local partes = {}

	if root:IsA("BasePart") then
		table.insert(partes, root)
	end

	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("BasePart") then
			table.insert(partes, obj)
		end
	end

	if #partes == 0 then
		error("[BankTeleport] No hay BaseParts en " .. root:GetFullName())
	end

	local total = Vector3.zero

	for _, parte in ipairs(partes) do
		total += parte.Position
	end

	return total / #partes
end

local centroExterior = obtenerCentro(puertasExterior)
local centroInterior = obtenerCentro(puertasInterior)

--============================================================
-- ESTADO
--============================================================

local estados = {}

local function getEstado(player)
	local estado = estados[player]

	if not estado then
		estado = {
			returnCFrame = nil,
			blockedSide = nil,
			teleportando = false,
		}

		estados[player] = estado
	end

	return estado
end

--============================================================
-- PERSONAJE
--============================================================

local function getCharacterData(player)
	local character = player.Character

	if not character then
		return nil, nil, nil
	end

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	local root =
		character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or not root
		or humanoid.Health <= 0
	then
		return nil, nil, nil
	end

	return character, humanoid, root
end

--============================================================
-- CFRAME RECTO
--============================================================

local function cframeRectoDesdePart(part, altura)
	local position =
		part.Position
		+ Vector3.new(
			0,
			altura or 0,
			0
		)

	local look = part.CFrame.LookVector

	local horizontal =
		Vector3.new(
			look.X,
			0,
			look.Z
		)

	if horizontal.Magnitude < 0.01 then
		horizontal = Vector3.new(0, 0, -1)
	else
		horizontal = horizontal.Unit
	end

	return CFrame.lookAt(
		position,
		position + horizontal,
		Vector3.yAxis
	)
end

--============================================================
-- TP
--============================================================

local function teleportar(player, targetCFrame, side, mensaje)
	local estado = getEstado(player)

	if estado.teleportando then
		return
	end

	local character, humanoid, root =
		getCharacterData(player)

	if not character or not humanoid or not root then
		return
	end

	estado.teleportando = true
	estado.blockedSide = side

	local autoRotateAnterior =
		humanoid.AutoRotate

	humanoid.Sit = false
	humanoid.AutoRotate = false

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true

	-- El cliente oscurece primero.
	remote:FireClient(
		player,
		"Out",
		mensaje
	)

	task.wait(TIEMPO_FADE_OUT)

	if not player.Parent
		or not character.Parent
		or not root.Parent
	then
		if root and root.Parent then
			root.Anchored = false
		end

		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = autoRotateAnterior
		end

		estado.teleportando = false
		remote:FireClient(player, "In")
		return
	end

	character:PivotTo(targetCFrame)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	task.wait(TIEMPO_ESTABILIZAR)

	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = false
	end

	if humanoid.Parent then
		humanoid.AutoRotate = autoRotateAnterior
	end

	-- Mostrar el destino.
	remote:FireClient(player, "In")

	task.delay(0.22, function()
		estado.teleportando = false
	end)
end

--============================================================
-- ENTRAR
--============================================================

local function entrar(player)
	local estado = getEstado(player)

	local _, _, root = getCharacterData(player)

	if not root then
		return
	end

	estado.returnCFrame =
		root.CFrame
		+ Vector3.new(
			0,
			ALTURA_RETORNO,
			0
		)

	teleportar(
		player,
		cframeRectoDesdePart(
			tpInterior,
			ALTURA_INTERIOR
		),
		"Interior",
		"Entrando al banco..."
	)
end

--============================================================
-- SALIR
--============================================================

local function salir(player)
	local destino =
		cframeRectoDesdePart(
			tpExterior,
			3
		)

	teleportar(
		player,
		destino,
		"Exterior",
		"Saliendo del banco..."
	)
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

	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root =
			getCharacterData(player)

		if root then
			local estado =
				getEstado(player)

			local distanciaExterior =
				(root.Position - centroExterior).Magnitude

			local distanciaInterior =
				(root.Position - centroInterior).Magnitude

			-- Desbloquear cuando ya se alejó del destino.
			if estado.blockedSide == "Interior" then
				if distanciaInterior > DISTANCIA_REACTIVAR then
					estado.blockedSide = nil
				end

			elseif estado.blockedSide == "Exterior" then
				if distanciaExterior > DISTANCIA_REACTIVAR then
					estado.blockedSide = nil
				end
			end

			if not estado.blockedSide
				and not estado.teleportando
			then
				if distanciaExterior <= DISTANCIA_TP then
					task.spawn(
						entrar,
						player
					)

				elseif distanciaInterior <= DISTANCIA_TP then
					task.spawn(
						salir,
						player
					)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	estados[player] = nil
end)