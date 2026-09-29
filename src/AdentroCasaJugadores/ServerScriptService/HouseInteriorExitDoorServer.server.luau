--============================================================
-- GRINDNIMALS - HOUSE INTERIOR EXIT DOOR V1
--
-- PLACE:
-- AdentroCasaJugadores
--
-- UBICACION:
-- ServerScriptService > HouseInteriorExitDoorServer
-- Tipo: Script
--
-- IMPORTANTE:
-- NO reemplaza HouseDoorPairTravelSystem.
-- Ese script sigue controlando Interior <-> Jardin.
--
-- ESTE script controla:
-- CasaN > DoorTps > DoorSpawn
-- La puerta que tiene el cartel "Salir" y regresa a CasaJugadores.
--
-- Estructura esperada:
--
-- Workspace
-- > Casas
--   > Casa1 / Casa2 / ...
--     > DoorTps
--       > DoorSpawn
--         > PuertaDesign
--           > Hinge
--           > Puerta
--             > Union
--         > MuroNegro
--
-- Los datos para regresar al servidor exterior YA los coloca
-- InteriorSlotCoordinator:
-- ExteriorPlaceId / ExteriorJobId / ExteriorHouseNumber /
-- ExteriorHouseName.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local ServerScriptService = game:GetService("ServerScriptService")

--============================================================
-- CONFIG
--============================================================

local DISTANCIA_ABRIR = 12
local DISTANCIA_SALIR = 4.25
local DISTANCIA_CERRAR = 14

local TIEMPO_ABRIR = 0.55
local TIEMPO_CERRAR = 0.65
local ESPERA_CERRAR = 1.15

-- Si abre hacia el lado incorrecto cambia -95 por 95.
local ANGULO_SALIR = -95

local Casas = workspace:WaitForChild("Casas")

local fadeEvent =
	ReplicatedStorage:FindFirstChild("HouseTravelFade")

local worldTeleportEvent =
	ReplicatedStorage:FindFirstChild("WorldTeleportEvent")

--============================================================
-- HELPERS
--============================================================

local function findBasePart(root, name)
	if not root then
		return nil
	end

	local direct = root:FindFirstChild(name)

	if direct and direct:IsA("BasePart") then
		return direct
	end

	local deep = root:FindFirstChild(name, true)

	if deep and deep:IsA("BasePart") then
		return deep
	end

	return nil
end

local function assignedHouseNumber(player)
	for _, attributeName in ipairs({
		"InteriorSlotNumber",
		"HouseNumber",
		"InteriorHouseNumber",
		"AssignedHouseNumber",
		"HouseSlot",
		"InteriorSlot",
		}) do
		local number =
			tonumber(
				player:GetAttribute(
					attributeName
				)
			)

		if number then
			return number
		end
	end

	return nil
end

local function findHouse(number)
	if not number then
		return nil
	end

	local house =
		Casas:FindFirstChild(
			"Casa" .. tostring(number)
		)
		or Casas:FindFirstChild(
			"Casa " .. tostring(number)
		)

	return house
		and house:IsA("Model")
		and house
		or nil
end

local function findDoorSpawn(house)
	if not house then
		return nil
	end

	local doorTps =
		house:FindFirstChild(
			"DoorTps"
		)

	if not doorTps then
		return nil
	end

	local door =
		doorTps:FindFirstChild(
			"DoorSpawn"
		)

	if door then
		return door
	end

	-- Respaldo por si cambiaste el nombre, pero mantuviste el cartel.
	for _, child in ipairs(doorTps:GetChildren()) do
		local key =
			tostring(child.Name)
			:lower()
			:gsub("[%s_%-]+", "")

		if key == "doorspawn"
			or key == "salir"
			or key == "exit"
			or key == "doorexit"
		then
			return child
		end
	end

	return nil
end

local function distanceToPartVolume(part, worldPosition)
	local localPoint =
		part.CFrame:PointToObjectSpace(
			worldPosition
		)

	local half =
		part.Size * 0.5

	local closest =
		Vector3.new(
			math.clamp(
				localPoint.X,
				-half.X,
				half.X
			),
			math.clamp(
				localPoint.Y,
				-half.Y,
				half.Y
			),
			math.clamp(
				localPoint.Z,
				-half.Z,
				half.Z
			)
		)

	return (
		localPoint - closest
	).Magnitude
end

--============================================================
-- CONTROLADOR DE LA PUERTA "SALIR"
--============================================================

local function createExitDoorController(house)
	local door =
		findDoorSpawn(house)

	if not door then
		warn(
			"[InteriorExitDoor] "
				.. house.Name
				.. " no tiene DoorTps > DoorSpawn."
		)
		return nil
	end

	local design =
		door:FindFirstChild(
			"PuertaDesign"
		)
		or door:FindFirstChild(
			"PuertaDesign",
			true
		)

	if not design then
		warn(
			"[InteriorExitDoor] Falta PuertaDesign en "
				.. door:GetFullName()
		)
		return nil
	end

	local hinge =
		design:FindFirstChild(
			"Hinge"
		)
		or design:FindFirstChild(
			"Hinge",
			true
		)

	if not hinge
		or not hinge:IsA("BasePart")
	then
		warn(
			"[InteriorExitDoor] Falta Hinge en "
				.. door:GetFullName()
		)
		return nil
	end

	local puerta =
		design:FindFirstChild(
			"Puerta"
		)
		or design:FindFirstChild(
			"Puerta",
			true
		)

	if not puerta then
		warn(
			"[InteriorExitDoor] Falta Puerta en "
				.. door:GetFullName()
		)
		return nil
	end

	local union =
		(
			puerta:IsA("BasePart")
			and puerta
		)
		or puerta:FindFirstChild(
			"Union"
		)
		or puerta:FindFirstChild(
			"Union",
			true
		)
		or puerta:FindFirstChildWhichIsA(
			"UnionOperation",
			true
		)
		or puerta:FindFirstChildWhichIsA(
			"BasePart",
			true
		)

	if not union
		or not union:IsA("BasePart")
	then
		warn(
			"[InteriorExitDoor] Falta Union/BasePart de la hoja en "
				.. door:GetFullName()
		)
		return nil
	end

	local sensor =
		findBasePart(
			door,
			"MuroNegro"
		)
		or union

	sensor.CanCollide = false
	sensor.CanTouch = true

	local movingParts = {}

	if puerta:IsA("BasePart") then
		table.insert(
			movingParts,
			puerta
		)
	end

	for _, object in ipairs(
		puerta:GetDescendants()
		) do
		if object:IsA("BasePart") then
			table.insert(
				movingParts,
				object
			)
		end
	end

	-- Si por estructura rara no agregamos nada, mover Union.
	if #movingParts == 0 then
		table.insert(
			movingParts,
			union
		)
	end

	local originalOffsets = {}

	for _, part in ipairs(movingParts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false

		originalOffsets[part] =
			hinge.CFrame:ToObjectSpace(
				part.CFrame
			)
	end

	local angle =
		Instance.new("NumberValue")

	angle.Name =
		"InteriorExitDoorAngle_"
		.. house.Name

	angle.Value = 0

	local currentTween = nil
	local opened = false
	local lastNear = 0

	local function updateDoor()
		if not hinge.Parent then
			return
		end

		local rotation =
			CFrame.Angles(
				0,
				math.rad(
					angle.Value
				),
				0
			)

		for part, offset in pairs(
			originalOffsets
			) do
			if part.Parent then
				part.CFrame =
					hinge.CFrame
					* rotation
					* offset

				part.AssemblyLinearVelocity =
					Vector3.zero

				part.AssemblyAngularVelocity =
					Vector3.zero
			end
		end
	end

	angle
		:GetPropertyChangedSignal(
			"Value"
		)
		:Connect(
			updateDoor
		)

	local function open()
		lastNear = os.clock()

		if opened then
			return
		end

		opened = true

		if currentTween then
			currentTween:Cancel()
		end

		currentTween =
			TweenService:Create(
				angle,
				TweenInfo.new(
					TIEMPO_ABRIR,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Value = ANGULO_SALIR,
				}
			)

		currentTween:Play()
	end

	local function close()
		if not opened then
			return
		end

		opened = false

		if currentTween then
			currentTween:Cancel()
		end

		currentTween =
			TweenService:Create(
				angle,
				TweenInfo.new(
					TIEMPO_CERRAR,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				),
				{
					Value = 0,
				}
			)

		currentTween:Play()
	end

	updateDoor()

	return {
		House = house,
		Door = door,
		Sensor = sensor,
		Open = open,
		Close = close,
		IsOpen = function()
			return opened
		end,
		LastNear = function()
			return lastNear
		end,
		Distance = function(position)
			return distanceToPartVolume(
				sensor,
				position
			)
		end,
	}
end

--============================================================
-- REGISTRAR CASAS
--============================================================

local controllers = {}
local controllerByHouse = {}

local function registerHouse(house)
	if not house:IsA("Model") then
		return
	end

	if controllerByHouse[house] then
		return
	end

	local controller =
		createExitDoorController(
			house
		)

	if controller then
		controllerByHouse[house] =
			controller

		table.insert(
			controllers,
			controller
		)

		print(
			"[InteriorExitDoor] Puerta SALIR registrada:",
			house:GetFullName(),
			"| sensor:",
			controller.Sensor:GetFullName()
		)
	end
end

for _, house in ipairs(
	Casas:GetChildren()
	) do
	registerHouse(house)
end

Casas.ChildAdded:Connect(
	function(house)
		task.wait(0.5)
		registerHouse(house)
	end
)

--============================================================
-- GUARDADO ANTES DE SALIR
--============================================================

local function invokeOptionalSave(name, player)
	local object =
		ServerScriptService:FindFirstChild(
			name
		)

	if not object
		or not object:IsA("BindableFunction")
	then
		return
	end

	pcall(function()
		object:Invoke(
			player
		)
	end)
end

local function forceSaves(player)
	invokeOptionalSave(
		"ForceSeedInventorySave",
		player
	)

	invokeOptionalSave(
		"ForceFruitInventorySave",
		player
	)
end

--============================================================
-- REGRESAR AL SERVIDOR DE CASA JUGADORES
--============================================================

local teleporting = {}

local function teleportBackToExterior(player)
	if teleporting[player] then
		return
	end

	if player:GetAttribute(
		"HouseInteriorLoaded"
		) ~= true
	then
		return
	end

	local placeId =
		tonumber(
			player:GetAttribute(
				"ExteriorPlaceId"
			)
		)

	local jobId =
		tostring(
			player:GetAttribute(
				"ExteriorJobId"
			)
			or ""
		)

	local exteriorHouseNumber =
		tonumber(
			player:GetAttribute(
				"ExteriorHouseNumber"
			)
		)

	local exteriorHouseName =
		tostring(
			player:GetAttribute(
				"ExteriorHouseName"
			)
			or ""
		)

	if not placeId then
		warn(
			"[InteriorExitDoor] "
				.. player.Name
				.. " no tiene ExteriorPlaceId."
		)
		return
	end

	teleporting[player] = true

	player:SetAttribute(
		"HouseTravelState",
		"Travelling"
	)

	-- CRITICO:
	-- InteriorSlotCoordinator usa esto para NO liberar la casa
	-- exterior cuando estamos regresando normalmente.
	player:SetAttribute(
		"ReturningToExterior",
		true
	)

	forceSaves(player)

	if fadeEvent
		and fadeEvent:IsA("RemoteEvent")
	then
		fadeEvent:FireClient(
			player,
			"out",
			0.28,
			"Saliendo a Casa Jugadores"
		)
	elseif worldTeleportEvent
		and worldTeleportEvent:IsA("RemoteEvent")
	then
		worldTeleportEvent:FireClient(
			player,
			"Saliendo a Casa Jugadores"
		)
	end

	task.wait(0.32)

	-- TeleportService no funciona realmente en Studio.
	if RunService:IsStudio() then
		warn(
			"[InteriorExitDoor] STUDIO: la puerta SI funciona. "
				.. "El regreso a CasaJugadores debe probarse "
				.. "en el juego publicado."
		)

		player:SetAttribute(
			"ReturningToExterior",
			false
		)

		player:SetAttribute(
			"HouseTravelState",
			"Ready"
		)

		teleporting[player] = nil

		if fadeEvent
			and fadeEvent:IsA("RemoteEvent")
		then
			fadeEvent:FireClient(
				player,
				"in",
				0.25
			)
		end

		return
	end

	local teleportData = {
		Route = "InteriorToExterior",
		OwnerUserId = player.UserId,
		ExteriorHouseNumber =
			exteriorHouseNumber,
		ExteriorHouseName =
			exteriorHouseName,
		ReturningFromInterior = true,
	}

	local ok, err

	if jobId ~= ""
		and jobId ~= "STUDIO_TEST"
	then
		ok, err =
			pcall(function()
				TeleportService:TeleportToPlaceInstance(
					placeId,
					jobId,
					player,
					nil,
					teleportData
				)
			end)
	else
		local options =
			Instance.new("TeleportOptions")

		options:SetTeleportData(
			teleportData
		)

		ok, err =
			pcall(function()
				TeleportService:TeleportAsync(
					placeId,
					{player},
					options
				)
			end)
	end

	if not ok then
		warn(
			"[InteriorExitDoor] Fallo regreso de "
				.. player.Name
				.. ": "
				.. tostring(err)
		)

		player:SetAttribute(
			"ReturningToExterior",
			false
		)

		player:SetAttribute(
			"HouseTravelState",
			"Ready"
		)

		teleporting[player] = nil

		if fadeEvent
			and fadeEvent:IsA("RemoteEvent")
		then
			fadeEvent:FireClient(
				player,
				"in",
				0.25
			)
		end
	end
end

--============================================================
-- LOOP DE PROXIMIDAD
--============================================================

local accumulator = 0

RunService.Heartbeat:Connect(
	function(dt)
		accumulator += dt

		if accumulator < 0.08 then
			return
		end

		accumulator = 0

		local nearController = {}

		for _, player in ipairs(
			Players:GetPlayers()
			) do
			local character =
				player.Character

			local humanoid =
				character
				and character:FindFirstChildOfClass(
					"Humanoid"
				)

			local root =
				character
				and character:FindFirstChild(
					"HumanoidRootPart"
				)

			if humanoid
				and root
				and humanoid.Health > 0
				and not teleporting[player]
				and player:GetAttribute(
					"HouseInteriorLoaded"
				) == true
			then
				local number =
					assignedHouseNumber(
						player
					)

				local house =
					findHouse(
						number
					)

				local controller =
					house
					and controllerByHouse[
				house
				]

				if controller then
					local distance =
						controller.Distance(
							root.Position
						)

					if distance
						<= DISTANCIA_ABRIR
					then
						nearController[
						controller
						] = true

						controller.Open()
					end

					local ignoreUntil =
						tonumber(
							player:GetAttribute(
								"IgnoreDoorSpawnUntil"
							)
						)
						or 0

					local ready =
						player:GetAttribute(
							"HouseTravelState"
						) ~= "Travelling"
						and os.clock()
						>= ignoreUntil

					if ready
						and distance
						<= DISTANCIA_SALIR
					then
						task.spawn(
							teleportBackToExterior,
							player
						)
					end
				end
			end
		end

		for _, controller in ipairs(
			controllers
			) do
			if not nearController[
				controller
				]
					and controller.IsOpen()
					and (
						os.clock()
						- controller.LastNear()
					) >= ESPERA_CERRAR
			then
				controller.Close()
			end
		end
	end
)

Players.PlayerRemoving:Connect(
	function(player)
		teleporting[player] = nil
	end
)

print(
	"[InteriorExitDoor] V1 ACTIVO | puertas SALIR registradas: "
		.. tostring(#controllers)
		.. " | DoorSpawn abre + regreso a CasaJugadores."
)
