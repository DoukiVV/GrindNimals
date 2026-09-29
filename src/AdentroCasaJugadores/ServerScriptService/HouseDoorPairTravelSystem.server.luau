--============================================================
-- HOUSE DOOR PAIR TRAVEL V5.8 - UNION REAL + SPAWN JARDIN INTERIOR
--
-- PLACE:
-- AdentroCasaJugadores
--
-- UBICACION:
-- ServerScriptService > HouseDoorPairTravelSystem
-- Tipo: Script
--
-- REEMPLAZA:
-- tu HouseDoorPairTravelSystem actual.
--
-- SOLO CONTROLA:
-- Casa interior -> Jardin
-- Jardin -> Casa interior
--
-- NO controla la puerta "Salir" que cambia de Place.
--
-- ESTRUCTURA ESPERADA por casa:
--
-- Workspace
-- > Casas
--   > Casa1 / Casa2 / ...
--     > DoorTps
--       > DoorGarden
--         > PuertaDesign
--           > Hinge
--           > Puerta
--             > Union
--         > MuroNegro
--       > DoorCasa / DoorHouse
--         > PuertaDesign
--           > Hinge
--           > Puerta
--             > Union
--         > MuroNegro
--
--     > SpawnEntradaPoint
--     > SpawnJardinPoint
--
-- La puerta abre EXACTAMENTE con la misma idea que Julian:
-- rota todas las partes de "Puerta" alrededor de "Hinge".
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--============================================================
-- CONFIG
--============================================================

local DISTANCIA_ABRIR = 12
local DISTANCIA_TP = 4.5
local DISTANCIA_REACTIVAR = 6

local TIEMPO_ABRIR = 0.55
local TIEMPO_CERRAR = 0.65
local ESPERA_CERRAR = 1.2

local TIEMPO_FADE_OUT = 0.28
local TIEMPO_ESTABILIZAR = 0.08
local ALTURA_TP = 2.7

-- Si una puerta abre al lado contrario:
-- cambia -95 por 95.
local ANGULO_JARDIN = -95
local ANGULO_CASA = -95

--============================================================
-- REMOTE FX
--============================================================

local REMOTE_NAME = "HouseTravelFX"

local travelFX =
	ReplicatedStorage:FindFirstChild(
		REMOTE_NAME
	)

if travelFX
	and not travelFX:IsA("RemoteEvent") then

	travelFX:Destroy()
	travelFX = nil
end

if not travelFX then
	travelFX = Instance.new("RemoteEvent")
	travelFX.Name = REMOTE_NAME
	travelFX.Parent = ReplicatedStorage
end

--============================================================
-- HELPERS
--============================================================

local function normalize(text)
	text =
		tostring(text or "")
		:lower()
		:gsub("á", "a")
		:gsub("é", "e")
		:gsub("í", "i")
		:gsub("ó", "o")
		:gsub("ú", "u")
		:gsub("ñ", "n")
		:gsub("[%s_%-]+", "")

	return text
end

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

local function gardenNumberFromHouse(house)
	return tonumber(
		tostring(house.Name):match("(%d+)$")
	)
end

local function findGardenSpawn(house)
	local number =
		gardenNumberFromHouse(house)

	-- Estructura real del usuario:
	-- Workspace > Jardin > Jardin 1 > SpawnPoint
	-- (también soporta Jardin1, Jardín, Jardines, etc.)
	local gardenRoot =
		workspace:FindFirstChild("Jardin")
		or workspace:FindFirstChild("Jardín")
		or workspace:FindFirstChild("Jardines")

	if gardenRoot and number then
		local candidates = {
			"Jardin " .. tostring(number),
			"Jardin" .. tostring(number),
			"Jardín " .. tostring(number),
			"Jardín" .. tostring(number),
		}

		for _, name in ipairs(candidates) do
			local garden =
				gardenRoot:FindFirstChild(name)

			if garden then
				local spawn =
					findBasePart(
						garden,
						"SpawnPoint"
					)
					or findBasePart(
						garden,
						"SpawnJardinPoint"
					)

				if spawn then
					return spawn
				end
			end
		end

		-- Respaldo: buscar cualquier JardinN cuyo nombre termine
		-- en el mismo número que la CasaN.
		for _, garden in ipairs(
			gardenRoot:GetChildren()
			) do
			local gardenNumber =
				tonumber(
					tostring(garden.Name):match("(%d+)$")
				)

			if gardenNumber == number then
				local spawn =
					findBasePart(
						garden,
						"SpawnPoint"
					)
					or findBasePart(
						garden,
						"SpawnJardinPoint"
					)

				if spawn then
					return spawn
				end
			end
		end
	end

	-- Compatibilidad con la estructura anterior.
	return findBasePart(
		house,
		"SpawnJardinPoint"
	)
end

local function getHeaderText(doorModel)
	local anchor =
		doorModel:FindFirstChild(
			"DoorHeaderSignAnchor",
			true
		)

	if not anchor then
		return ""
	end

	for _, object in ipairs(
		anchor:GetDescendants()
		) do
		if object:IsA("TextLabel")
			or object:IsA("TextButton") then

			local text =
				tostring(
					object.Text or ""
				)

			if text ~= "" then
				return text
			end
		end
	end

	return ""
end

local function classifyDoor(doorModel)
	local key =
		normalize(
			doorModel.Name
		)

	-- Estructura real:
	-- DoorGarden = Casa -> Jardin
	-- DoorSpawn  = Jardin -> Casa
	if key == "doorgarden" then
		return "Jardin"
	end

	if key == "doorspawn" then
		return "Casa"
	end

	local headerKey =
		normalize(
			getHeaderText(
				doorModel
			)
		)

	local combined =
		key .. headerKey

	if combined:find("garden", 1, true)
		or combined:find("jardin", 1, true) then

		return "Jardin"
	end

	if combined:find("house", 1, true)
		or combined:find("casa", 1, true)
		or combined:find("entrada", 1, true)
		or combined:find("spawn", 1, true) then

		return "Casa"
	end

	return nil
end

local function getOwnerUserId(house)
	local value =
		house:FindFirstChild(
			"OwnerUserId"
		)

	if value
		and value:IsA("ValueBase") then

		return tonumber(value.Value)
	end

	return tonumber(
		house:GetAttribute(
			"RuntimeOwnerUserId"
		)
	)
		or tonumber(
			house:GetAttribute(
				"OwnerUserId"
			)
		)
end

local function playerHouseNumber(player)
	for _, attrName in ipairs({
		"InteriorHouseNumber",
		"InteriorSlotNumber",
		"HouseNumber",
		"AssignedHouseNumber",
		"HouseSlot",
		"InteriorSlot",
		}) do
		local value =
			tonumber(
				player:GetAttribute(
					attrName
				)
			)

		if value then
			return value
		end
	end

	return nil
end

local function canUseHouse(player, house)
	if player:GetAttribute(
		"HouseInteriorLoaded"
		) == false then
		return false
	end

	local expectedNumber =
		tonumber(
			house.Name:match(
				"(%d+)$"
			)
		)

	local assigned =
		playerHouseNumber(player)

	if expectedNumber
		and assigned then

		return expectedNumber
			== assigned
	end

	local ownerId =
		getOwnerUserId(house)

	if ownerId then
		return ownerId
			== player.UserId
	end

	return true
end

local function getCharacter(player)
	local character =
		player.Character

	if not character then
		return nil
	end

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not humanoid
		or not root
		or humanoid.Health <= 0 then

		return nil
	end

	return character,
		humanoid,
		root
end

local function safeDestinationCFrame(part)
	local position =
		part.Position
		+ Vector3.new(
			0,
			ALTURA_TP,
			0
		)

	local look =
		part.CFrame.LookVector

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
		position,
		position + horizontal,
		Vector3.yAxis
	)
end

--============================================================
-- PUERTA ESTILO JULIAN
--============================================================

local function createDoorController(
	doorModel,
	openAngle,
	label
)
	local design =
		doorModel:FindFirstChild(
			"PuertaDesign"
		)
		or doorModel:FindFirstChild(
			"PuertaDesign",
			true
		)
		or doorModel

	local hinge =
		design:FindFirstChild(
			"Hinge"
		)
		or design:FindFirstChild(
			"Hinge",
			true
		)

	if not hinge
		or not hinge:IsA("BasePart") then

		warn(
			"[HouseDoor] Falta Hinge en "
				.. doorModel:GetFullName()
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
			"[HouseDoor] Falta Puerta en "
				.. doorModel:GetFullName()
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
		or puerta:FindFirstChildWhichIsA(
			"UnionOperation",
			true
		)
		or puerta:FindFirstChildWhichIsA(
			"BasePart",
			true
		)

	if not union then
		warn(
			"[HouseDoor] Falta Union en "
				.. doorModel:GetFullName()
		)

		return nil
	end

	local parts = {}

	if puerta:IsA("BasePart") then
		table.insert(
			parts,
			puerta
		)
	end

	for _, object in ipairs(
		puerta:GetDescendants()
		) do
		if object:IsA("BasePart") then
			table.insert(
				parts,
				object
			)
		end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
	end

	local originalOffsets = {}

	for _, part in ipairs(parts) do
		originalOffsets[part] =
			hinge.CFrame:ToObjectSpace(
				part.CFrame
			)
	end

	local angle =
		Instance.new("NumberValue")

	angle.Name =
		"HouseDoorAngle_"
		.. label

	angle.Value = 0

	local function updateDoor()
		local rotation =
			CFrame.Angles(
				0,
				math.rad(angle.Value),
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

	local opened = false
	local currentTween = nil
	local lastNear = 0

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
					Value =
					openAngle,
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

	local sensor =
		findBasePart(
			doorModel,
			"MuroNegro"
		)
		or union

	if sensor then
		sensor.CanCollide = false
		sensor.CanTouch = true
	end

	return {
		DoorModel = doorModel,
		Union = union,
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
			-- Distancia al volumen real del sensor, no a su centro.
			local localPoint =
				sensor.CFrame:PointToObjectSpace(
					position
				)

			local half =
				sensor.Size * 0.5

			local closest =
				Vector3.new(
					math.clamp(localPoint.X, -half.X, half.X),
					math.clamp(localPoint.Y, -half.Y, half.Y),
					math.clamp(localPoint.Z, -half.Z, half.Z)
				)

			return (
				localPoint - closest
			).Magnitude
		end,
	}
end

--============================================================
-- PUERTA REAL DEL JARDIN
--============================================================

local function findGardenForHouse(house)
	local number =
		tonumber(
			tostring(house.Name):match("(%d+)$")
		)

	if not number then
		return nil
	end

	local expectedNames = {
		["jardin" .. tostring(number)] = true,
		["jardín" .. tostring(number)] = true,
	}

	local function normalizedName(value)
		return tostring(value or "")
			:lower()
			:gsub("á", "a")
			:gsub("é", "e")
			:gsub("í", "i")
			:gsub("ó", "o")
			:gsub("ú", "u")
			:gsub("[%s_%-]+", "")
	end

	-- Primero buscar dentro del contenedor normal Workspace.Jardin.
	local gardenRoot =
		workspace:FindFirstChild("Jardin")
		or workspace:FindFirstChild("Jardín")
		or workspace:FindFirstChild("Jardines")

	if gardenRoot then
		for _, garden in ipairs(
			gardenRoot:GetDescendants()
			) do
			if (
				garden:IsA("Model")
					or garden:IsA("Folder")
				)
					and expectedNames[
				normalizedName(garden.Name)
				]
			then
				local spawn =
					findBasePart(
						garden,
						"SpawnPoint"
					)
					or findBasePart(
						garden,
						"SpawnJardinPoint"
					)

				if spawn then
					return garden
				end
			end
		end

		for _, garden in ipairs(
			gardenRoot:GetChildren()
			) do
			local gardenNumber =
				tonumber(
					tostring(garden.Name):match("(%d+)$")
				)

			if gardenNumber == number then
				local spawn =
					findBasePart(
						garden,
						"SpawnPoint"
					)
					or findBasePart(
						garden,
						"SpawnJardinPoint"
					)

				if spawn then
					return garden
				end
			end
		end
	end

	-- Respaldo: buscar cualquier JardinN real dentro de Workspace,
	-- pero exigir que tenga SpawnPoint.
	for _, garden in ipairs(
		workspace:GetDescendants()
		) do
		if (
			garden:IsA("Model")
				or garden:IsA("Folder")
			)
		then
			local gardenNumber =
				tonumber(
					tostring(garden.Name):match("(%d+)$")
				)

			if gardenNumber == number
				and normalizedName(garden.Name):find(
					"jardin",
					1,
					true
				) then

				local spawn =
					findBasePart(
						garden,
						"SpawnPoint"
					)
					or findBasePart(
						garden,
						"SpawnJardinPoint"
					)

				if spawn then
					return garden
				end
			end
		end
	end

	return nil
end

local function isUsableDoorRoot(object)
	if not (
		object:IsA("Model")
			or object:IsA("Folder")
		) then
		return false
	end

	local design =
		object:FindFirstChild("PuertaDesign")
		or object:FindFirstChild(
			"PuertaDesign",
			true
		)

	if not design then
		return false
	end

	local hinge =
		design:FindFirstChild("Hinge", true)

	local puerta =
		design:FindFirstChild("Puerta", true)

	local union =
		puerta
		and (
			puerta:FindFirstChild("Union", true)
			or puerta:FindFirstChildWhichIsA(
				"UnionOperation",
				true
			)
			or puerta:FindFirstChildWhichIsA(
				"BasePart",
				true
			)
		)

	return hinge ~= nil
		and union ~= nil
end

local function gardenDoorScore(object)
	local score = 0

	local key =
		normalize(object.Name)

	local header =
		normalize(
			getHeaderText(object)
		)

	if key:find("casa", 1, true)
		or key:find("house", 1, true)
	then
		score += 20
	end

	if key:find("spawn", 1, true)
		or key:find("door", 1, true)
	then
		score += 8
	end

	if header:find("casa", 1, true)
		or header:find("house", 1, true)
	then
		score += 30
	end

	if object:FindFirstChild(
		"MuroNegro",
		true
		) then
		score += 5
	end

	return score
end

local function textAroundObject(object, garden)
	local parts = {}
	local current = object

	for _ = 1, 5 do
		if not current
			or current == garden then
			break
		end

		table.insert(
			parts,
			normalize(
				current.Name
			)
		)

		for _, descendant in ipairs(
			current:GetDescendants()
			) do
			if descendant:IsA("TextLabel")
				or descendant:IsA("TextButton") then

				local text =
					normalize(
						descendant.Text
					)

				if text ~= "" then
					table.insert(
						parts,
						text
					)
				end
			end
		end

		current = current.Parent
	end

	return table.concat(
		parts,
		" "
	)
end

local function validDoorDesign(design)
	if not design
		or not (
			design:IsA("Model")
				or design:IsA("Folder")
		) then

		return false
	end

	if normalize(design.Name)
		~= "puertadesign" then

		return false
	end

	local hinge =
		design:FindFirstChild(
			"Hinge",
			true
		)

	local puerta =
		design:FindFirstChild(
			"Puerta",
			true
		)

	local union =
		puerta
		and (
			puerta:FindFirstChild(
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
		)

	return hinge
		and hinge:IsA("BasePart")
		and union
		and union:IsA("BasePart")
end

local function findGardenReturnDoor(
	garden,
	spawnJardin
)
	if not garden then
		return nil
	end

	local bestDesign = nil
	local bestScore = -math.huge

	-- V5.5:
	-- Busca directamente cada PuertaDesign real del jardín.
	-- Ya no acepta ModeloJardin como si fuera una puerta completa.
	for _, object in ipairs(
		garden:GetDescendants()
		) do
		if validDoorDesign(object) then
			local hinge =
				object:FindFirstChild(
					"Hinge",
					true
				)

			local score = 0

			local surroundingText =
				textAroundObject(
					object,
					garden
				)

			if surroundingText:find(
				"casa",
				1,
				true
				) then
				score += 1000
			end

			if surroundingText:find(
				"house",
				1,
				true
				) then
				score += 1000
			end

			if surroundingText:find(
				"spawn",
				1,
				true
				) then
				score += 200
			end

			-- La puerta "Casa" normalmente está junto al SpawnPoint
			-- donde llegas desde el interior.
			if spawnJardin
				and hinge then

				local distance =
					(
						hinge.Position
						- spawnJardin.Position
					).Magnitude

				score +=
					math.max(
						0,
						500 - distance * 10
					)
			end

			if score > bestScore then
				bestScore = score
				bestDesign = object
			end
		end
	end

	return bestDesign
end

--============================================================
-- PUERTA REAL "CASA" EN CASAEXT
--
-- Estructura confirmada:
--
-- Workspace
-- > CasaExt
--   > Casa Jugador1
--     > Casa
--       > Door
--         > Puerta
--           > Doorframe
--             > Hinge
--             > Part
--             > Part
--             > Part
--             > Puerta   <-- hoja que gira
--         > MuroNegro
--
-- Esta puerta NO está dentro de JardinN.
--============================================================

local function findCasaExtHouse(number)
	local root =
		workspace:FindFirstChild("CasaExt")

	if not root then
		return nil
	end

	for _, candidateName in ipairs({
		"Casa Jugador" .. tostring(number),
		"Casa Jugador " .. tostring(number),
		"CasaJugador" .. tostring(number),
		}) do
		local candidate =
			root:FindFirstChild(candidateName)

		if candidate then
			return candidate
		end
	end

	for _, candidate in ipairs(
		root:GetChildren()
		) do
		local candidateNumber =
			tonumber(
				tostring(candidate.Name):match("(%d+)$")
			)

		if candidateNumber == number then
			return candidate
		end
	end

	return nil
end

local function findCasaExtDoor(number)
	local extHouse =
		findCasaExtHouse(number)

	if not extHouse then
		return nil
	end

	--========================================================
	-- ESTRUCTURA REAL CONFIRMADA:
	--
	-- CasaExt
	-- > Casa Jugador1
	--   > Casa
	--   > Door        <-- ES HERMANO de "Casa", no hijo
	--     > Puerta
	--       > Doorframe
	--         > Hinge
	--         > Part
	--         > Part
	--         > Part
	--         > Puerta
	--     > ExteriorDoorHeaderSignAnchor
	--     > MuroNegro
	--
	-- V5.6 buscaba Casa > Door y por eso daba 0/8.
	--========================================================

	local door =
		extHouse:FindFirstChild("Door")

	-- Compatibilidad por si alguna casa vieja sí lo tiene dentro de Casa.
	if not door then
		local casa =
			extHouse:FindFirstChild("Casa")

		if casa then
			door =
				casa:FindFirstChild(
					"Door"
				)
				or casa:FindFirstChild(
					"Door",
					true
				)
		end
	end

	-- Último respaldo dentro de Casa JugadorN.
	if not door then
		door =
			extHouse:FindFirstChild(
				"Door",
				true
			)
	end

	if not door then
		return nil
	end

	local outerPuerta =
		door:FindFirstChild(
			"Puerta"
		)
		or door:FindFirstChild(
			"Puerta",
			true
		)

	if not outerPuerta then
		return nil
	end

	local doorframe =
		outerPuerta:FindFirstChild(
			"Doorframe"
		)
		or outerPuerta:FindFirstChild(
			"Doorframe",
			true
		)

	if not doorframe then
		return nil
	end

	local hinge =
		doorframe:FindFirstChild(
			"Hinge"
		)
		or doorframe:FindFirstChild(
			"Hinge",
			true
		)

	if not hinge
		or not hinge:IsA("BasePart") then

		return nil
	end

	-- La hoja real es la "Puerta" que está DENTRO de Doorframe.
	local leaf =
		doorframe:FindFirstChild(
			"Puerta"
		)

	if not leaf then
		for _, object in ipairs(
			doorframe:GetChildren()
			) do
			if normalize(
				object.Name
				) == "puerta"
					and (
						object:IsA("BasePart")
						or object:IsA("Model")
					) then

				leaf = object
				break
			end
		end
	end

	if not leaf then
		return nil
	end

	--========================================================
	-- V5.8:
	-- LA PIEZA QUE REALMENTE MUEVE LA PUERTA ES "Union".
	--
	-- Estructura:
	-- Door
	-- > Puerta
	--   > Doorframe
	--     > Puerta
	--       > Union
	--========================================================

	local union =
		leaf:FindFirstChild(
			"Union"
		)
		or leaf:FindFirstChild(
			"Union",
			true
		)

	if not union
		or not union:IsA("BasePart") then

		return nil
	end

	local sensor =
		door:FindFirstChild(
			"MuroNegro"
		)
		or door:FindFirstChild(
			"MuroNegro",
			true
		)

	local sensorPart =
		sensor
		and sensor:IsA("BasePart")
		and sensor
		or nil

	if not sensorPart then
		if leaf:IsA("BasePart") then
			sensorPart = leaf
		else
			sensorPart =
				leaf:FindFirstChildWhichIsA(
					"BasePart",
					true
				)
		end
	end

	if not sensorPart then
		return nil
	end

	return {
		Root = door,
		OuterPuerta = outerPuerta,
		Doorframe = doorframe,
		Hinge = hinge,
		Leaf = leaf,
		Union = union,
		Sensor = sensorPart,
	}
end

local function createCasaExtDoorController(
	doorInfo,
	openAngle,
	label
)
	if not doorInfo
		or not doorInfo.Hinge
		or not doorInfo.Union
		or not doorInfo.Sensor then

		return nil
	end

	local hinge =
		doorInfo.Hinge

	local union =
		doorInfo.Union

	local sensor =
		doorInfo.Sensor

	-- La Union es la única pieza que rotamos.
	union.Anchored = true
	union.CanCollide = false

	sensor.CanCollide = false
	sensor.CanTouch = true

	local closedOffset =
		hinge.CFrame:ToObjectSpace(
			union.CFrame
		)

	local angleValue =
		Instance.new("NumberValue")

	angleValue.Name =
		"HouseCasaExtUnionAngle_"
		.. label

	angleValue.Value = 0

	local currentTween = nil
	local opened = false
	local lastNear = 0

	local function updateDoor()
		if not union.Parent
			or not hinge.Parent then

			return
		end

		union.CFrame =
			hinge.CFrame
			* CFrame.Angles(
				0,
				math.rad(
					angleValue.Value
				),
				0
			)
			* closedOffset

		union.AssemblyLinearVelocity =
			Vector3.zero

		union.AssemblyAngularVelocity =
			Vector3.zero
	end

	angleValue
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
				angleValue,
				TweenInfo.new(
					TIEMPO_ABRIR,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Value =
					openAngle,
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
				angleValue,
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

		task.delay(
			TIEMPO_CERRAR + 0.05,
			function()
				if not opened
					and union.Parent
					and hinge.Parent then

					angleValue.Value = 0
					updateDoor()
				end
			end
		)
	end

	local function distanceToSensor(position)
		local localPoint =
			sensor.CFrame:PointToObjectSpace(
				position
			)

		local half =
			sensor.Size * 0.5

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

	-- Asegurar posición cerrada inicial.
	updateDoor()

	return {
		DoorModel =
			doorInfo.Root,

		Union =
			union,

		Sensor =
			sensor,

		Open =
			open,

		Close =
			close,

		IsOpen =
			function()
				return opened
			end,

		LastNear =
			function()
				return lastNear
			end,

		Distance =
			distanceToSensor,
	}
end

--============================================================
-- CONSTRUIR TODAS LAS PUERTAS
--============================================================

local Casas =
	workspace:WaitForChild(
		"Casas"
	)

local controllers = {}

local interiorToGardenCount = 0
local gardenToInteriorCount = 0

local function addController(
	door,
	house,
	kind,
	destination,
	message,
	angle,
	prebuiltController
)
	if not destination then
		return false
	end

	local controller =
		prebuiltController
		or (
			door
			and createDoorController(
				door,
				angle,
				house.Name
				.. "_"
				.. kind
			)
		)

	if not controller then
		return false
	end

	controller.House = house
	controller.Kind = kind
	controller.Destination = destination
	controller.Message = message

	table.insert(
		controllers,
		controller
	)

	return true
end

local function registerHouse(house)
	if not house:IsA("Model") then
		return
	end

	local doorRoot =
		house:FindFirstChild(
			"DoorTps"
		)

	if not doorRoot then
		warn(
			"[HouseDoor] "
				.. house.Name
				.. " no tiene DoorTps."
		)
		return
	end

	local spawnEntrada =
		findBasePart(
			house,
			"SpawnEntradaPoint"
		)

	-- V5.8:
	-- Este es el destino CORRECTO cuando vuelves del jardín.
	-- SpawnEntradaPoint pertenece a la entrada/salida exterior.
	local spawnInteriorDesdeJardin =
		findBasePart(
			house,
			"SpawnJardinPoint"
		)

	local garden =
		findGardenForHouse(
			house
		)

	local spawnJardin =
		garden
		and (
			findBasePart(
				garden,
				"SpawnPoint"
			)
			or findBasePart(
				garden,
				"SpawnJardinPoint"
			)
		)
		or nil

	--========================================================
	-- CASA -> JARDIN
	-- Esta puerta sí vive dentro de CasaN > DoorTps.
	--========================================================

	local doorGarden =
		doorRoot:FindFirstChild(
			"DoorGarden"
		)

	if not doorGarden then
		for _, door in ipairs(
			doorRoot:GetChildren()
			) do
			if classifyDoor(door)
				== "Jardin" then

				doorGarden = door
				break
			end
		end
	end

	if doorGarden
		and spawnJardin then

		if addController(
			doorGarden,
			house,
			"Jardin",
			spawnJardin,
			"Saliendo al jardin",
			ANGULO_JARDIN
			) then

			interiorToGardenCount += 1
		end
	elseif not spawnJardin then
		warn(
			"[HouseDoor] "
				.. house.Name
				.. " no encontró "
				.. "Workspace.Jardin.Jardin N.SpawnPoint"
		)
	end

	--========================================================
	-- JARDIN -> CASA
	--
	-- V5.6:
	-- La puerta física "Casa" NO está dentro de JardinN.
	-- Está en:
	-- Workspace > CasaExt > Casa JugadorN > Casa > Door
	--========================================================

	local number =
		tonumber(
			tostring(house.Name):match("(%d+)$")
		)

	local casaExtDoorInfo =
		number
		and findCasaExtDoor(number)
		or nil

	local casaExtController =
		casaExtDoorInfo
		and createCasaExtDoorController(
			casaExtDoorInfo,
			ANGULO_CASA,
			house.Name
			.. "_CasaExt"
		)
		or nil

	if casaExtController
		and spawnInteriorDesdeJardin then

		if addController(
			casaExtDoorInfo.Root,
			house,
			"Casa",
			spawnInteriorDesdeJardin,
			"Entrando a la Casa",
			ANGULO_CASA,
			casaExtController
			) then

			gardenToInteriorCount += 1

			casaExtDoorInfo.Root:SetAttribute(
				"HouseTravelGardenReturnDoor",
				true
			)

			casaExtDoorInfo.Root:SetAttribute(
				"HouseTravelTargetHouse",
				house.Name
			)

			casaExtDoorInfo.Root:SetAttribute(
				"HouseTravelDoorSource",
				"CasaExt"
			)

			casaExtDoorInfo.Root:SetAttribute(
				"HouseTravelMovingPart",
				casaExtDoorInfo.Union:GetFullName()
			)

			casaExtDoorInfo.Root:SetAttribute(
				"HouseTravelDestination",
				spawnInteriorDesdeJardin:GetFullName()
			)
		end
	else
		if not casaExtController then
			warn(
				"[HouseDoor] No encontré puerta CasaExt para "
					.. house.Name
					.. " | esperado: CasaExt > Casa JugadorN > Door"
			)
		end

		if not spawnInteriorDesdeJardin then
			warn(
				"[HouseDoor] "
					.. house.Name
					.. " no tiene SpawnJardinPoint."
			)
		end
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
-- TELEPORT LOCAL
--============================================================

local teleporting = {}
local blocked = {}

local function localTeleport(
	player,
	controller
)
	if teleporting[player] then
		return
	end

	if not canUseHouse(
		player,
		controller.House
		) then
		return
	end

	local character,
		humanoid,
		root =
		getCharacter(player)

	if not character then
		return
	end

	teleporting[player] = true
	blocked[player] = true

	local oldAutoRotate =
		humanoid.AutoRotate

	humanoid.AutoRotate = false
	humanoid.Sit = false

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	root.Anchored = true

	travelFX:FireClient(
		player,
		"Out",
		controller.Message
	)

	task.wait(
		TIEMPO_FADE_OUT
	)

	if not player.Parent
		or not character.Parent
		or not root.Parent
		or humanoid.Health <= 0 then

		if root.Parent then
			root.Anchored = false
		end

		humanoid.AutoRotate =
			oldAutoRotate

		teleporting[player] = nil

		travelFX:FireClient(
			player,
			"In"
		)

		return
	end

	character:PivotTo(
		safeDestinationCFrame(
			controller.Destination
		)
	)

	if controller.Kind == "Jardin" then
		player:SetAttribute(
			"HouseLocation",
			"Garden"
		)
	else
		player:SetAttribute(
			"HouseLocation",
			"Interior"
		)
	end

	root.AssemblyLinearVelocity =
		Vector3.zero

	root.AssemblyAngularVelocity =
		Vector3.zero

	task.wait(
		TIEMPO_ESTABILIZAR
	)

	if root.Parent then
		root.Anchored = false
	end

	if humanoid.Parent then
		humanoid.AutoRotate =
			oldAutoRotate

		pcall(function()
			humanoid:ChangeState(
				Enum.HumanoidStateType.GettingUp
			)
		end)
	end

	travelFX:FireClient(
		player,
		"In"
	)

	task.delay(
		0.25,
		function()
			teleporting[player] =
				nil
		end
	)
end

--============================================================
-- LOOP
--============================================================

local accumulator = 0

RunService.Heartbeat:Connect(
	function(dt)
		accumulator += dt

		if accumulator < 0.08 then
			return
		end

		accumulator = 0

		local nearDoor = {}

		for _, player in ipairs(
			Players:GetPlayers()
			) do
			local _,
			_,
			root =
				getCharacter(player)

			if root then
				-- FIX V5.1:
				-- El bloqueo solo se libera cuando el jugador está
				-- lejos de TODAS las puertas de su casa.
				if blocked[player]
					and not teleporting[player] then

					local nearestDistance =
						math.huge

					for _, controller in ipairs(
						controllers
						) do
						if canUseHouse(
							player,
							controller.House
							) then
							nearestDistance =
								math.min(
									nearestDistance,
									controller.Distance(
										root.Position
									)
								)
						end
					end

					if nearestDistance
						> DISTANCIA_REACTIVAR then

						blocked[player] = nil
					end
				end

				for _, controller in ipairs(
					controllers
					) do
					if canUseHouse(
						player,
						controller.House
						) then

						local distance =
							controller.Distance(
								root.Position
							)

						if distance
							<= DISTANCIA_ABRIR then

							nearDoor[controller] =
								true

							controller.Open()
						end

						if not blocked[player]
							and not teleporting[player]
							and distance
							<= DISTANCIA_TP then

							task.spawn(
								localTeleport,
								player,
								controller
							)

							break
						end
					end
				end
			end
		end

		for _, controller in ipairs(
			controllers
			) do
			if not nearDoor[controller]
				and controller.IsOpen()
				and (
					os.clock()
					- controller.LastNear()
				) >= ESPERA_CERRAR then

				controller.Close()
			end
		end
	end
)

Players.PlayerRemoving:Connect(
	function(player)
		teleporting[player] = nil
		blocked[player] = nil
	end
)

print(
	"[HouseDoorPairTravel] V5.8 ACTIVO | "
		.. "Casa->Jardin: "
		.. tostring(interiorToGardenCount)
		.. " | Jardin->Casa: "
		.. tostring(gardenToInteriorCount)
		.. " | mueve UNION | destino SpawnJardinPoint."
)
