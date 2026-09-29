--!strict
-- ============================================================
-- INTERIOR SLOT COORDINATOR V4.2
-- Tipo: Script
-- Ubicación: AdentroCasaJugadores > ServerScriptService
--             > InteriorSlotCoordinator
--
-- Corrige:
-- - Al cerrar Roblox dentro de la casa, avisa inmediatamente al
--   servidor exterior para que marque la casa como desocupada.
-- - Al salir al lobby desde el interior, también libera la casa.
-- - Al regresar normalmente a CasaJugadores NO libera la casa.
-- ============================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local casasFolder = Workspace:WaitForChild("Casas")

local HouseSessionMap =
	MemoryStoreService:GetHashMap(
		"BlockFarmHouseSessions_v4"
	)

local HOUSE_RELEASE_CHANNEL =
	"HouseExteriorRelease_v1"

local TOTAL_INTERIOR_SLOTS = 8
local SESSION_TTL = 120
local HEARTBEAT_INTERVAL = 20

local ARRIVAL_WALK_DISTANCE = 5.8
local ARRIVAL_WALK_SPEED = 8
local ARRIVAL_TIMEOUT = 3

local occupiedSlots: {[number]: number} = {}
local sessions: {[number]: any} = {}

local function ensureRemote(name: string): RemoteEvent
	local existing =
		ReplicatedStorage:FindFirstChild(name)

	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage

	return remote
end

local fadeEvent = ensureRemote("HouseTravelFade")
local controlLockEvent =
	ensureRemote("HouseTravelControlLock")
local autoWalkEvent =
	ensureRemote("HouseTravelAutoWalk")
local autoWalkFinishedEvent =
	ensureRemote("HouseTravelAutoWalkFinished")

local pendingWalkTokens:
	{[number]: {Token: string, Done: boolean}} = {}

autoWalkFinishedEvent.OnServerEvent:Connect(
	function(player, token)
		local pending =
			pendingWalkTokens[player.UserId]

		if pending and pending.Token == token then
			pending.Done = true
		end
	end
)

local function findHouse(number: number): Model?
	local object =
		casasFolder:FindFirstChild(
			"Casa" .. tostring(number)
		)
		or casasFolder:FindFirstChild(
			"Casa " .. tostring(number)
		)

	return object
		and object:IsA("Model")
		and object
		or nil
end

local function findFreeSlot(): number?
	for number = 1, TOTAL_INTERIOR_SLOTS do
		if not occupiedSlots[number]
			and findHouse(number)
		then
			return number
		end
	end

	return nil
end

local function findEntranceSpawn(
	house: Model
): BasePart?
	local spawn =
		house:FindFirstChild(
			"SpawnEntradaPoint",
			true
		)

	return spawn
		and spawn:IsA("BasePart")
		and spawn
		or nil
end

local function findDoorSpawnTrigger(
	house: Model
): BasePart?
	local doorTps = house:FindFirstChild("DoorTps")
	local doorSpawn =
		doorTps
		and doorTps:FindFirstChild("DoorSpawn")

	local trigger =
		doorSpawn
		and doorSpawn:FindFirstChild(
			"MuroNegro",
			true
		)

	return trigger
		and trigger:IsA("BasePart")
		and trigger
		or nil
end

local function horizontalUnit(
	vector: Vector3,
	fallback: Vector3
): Vector3
	local flat =
		Vector3.new(vector.X, 0, vector.Z)

	if flat.Magnitude < 0.05 then
		local fallbackFlat =
			Vector3.new(
				fallback.X,
				0,
				fallback.Z
			)

		return fallbackFlat.Magnitude > 0.05
			and fallbackFlat.Unit
			or Vector3.new(0, 0, -1)
	end

	return flat.Unit
end

local function readTeleportData(
	player: Player
): any?
	local joinData = player:GetJoinData()

	local data =
		type(joinData) == "table"
		and joinData.TeleportData
		or nil

	if type(data) == "table"
		and data.Route == "ExteriorToInterior"
		and tonumber(data.OwnerUserId)
		== player.UserId
		and tonumber(data.ExteriorHouseNumber)
		and type(data.ExteriorHouseName)
		== "string"
		and tonumber(data.ExteriorPlaceId)
		and type(data.ExteriorJobId)
		== "string"
	then
		return data
	end

	if RunService:IsStudio() then
		return {
			Route = "ExteriorToInterior",
			OwnerUserId = player.UserId,
			ExteriorHouseName =
				"Casa Jugador1",
			ExteriorHouseNumber = 1,
			ExteriorPlaceId = game.PlaceId,
			ExteriorJobId = "STUDIO_TEST",
			StudioTest = true,
		}
	end

	return nil
end

local function writeSession(
	player: Player,
	state: string
)
	local data = sessions[player.UserId]

	if not data or data.StudioTest then
		return
	end

	data.State = state
	data.UpdatedAt = os.time()

	local ok, err = pcall(function()
		HouseSessionMap:SetAsync(
			"user_" .. tostring(player.UserId),
			data,
			SESSION_TTL
		)
	end)

	if not ok then
		warn("[InteriorSlot] No se pudo renovar la sesión de "
			.. player.Name
			.. ": "
			.. tostring(err))
	end
end

local function placeAndWalkPlayer(
	player: Player,
	house: Model
)
	local function run(character: Model)
		task.wait(0.8)

		local root =
			character:FindFirstChild(
				"HumanoidRootPart"
			)

		local humanoid =
			character:FindFirstChildOfClass(
				"Humanoid"
			)

		local spawn =
			findEntranceSpawn(house)

		local doorTrigger =
			findDoorSpawnTrigger(house)

		if not root or not humanoid or not spawn then
			warn("[InteriorSlot] Faltan personaje o SpawnEntradaPoint en "
				.. house:GetFullName())
			return
		end

		local direction =
			doorTrigger
			and horizontalUnit(
				spawn.Position
				- doorTrigger.Position,
				spawn.CFrame.LookVector
			)
			or horizontalUnit(
				spawn.CFrame.LookVector,
				Vector3.new(0, 0, -1)
			)

		player:SetAttribute(
			"HouseTravelState",
			"Travelling"
		)

		player:SetAttribute(
			"IgnoreAllHouseDoorsUntil",
			os.clock() + 3.5
		)

		player:SetAttribute(
			"IgnoreDoorSpawnUntil",
			os.clock() + 4
		)

		controlLockEvent:FireClient(player, true)

		root.Anchored = true
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)

		local startPosition =
			spawn.Position
			+ Vector3.new(0, 3, 0)

		character:PivotTo(
			CFrame.lookAt(
				startPosition,
				startPosition + direction
			)
		)

		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		fadeEvent:FireClient(
			player,
			"out",
			0.05,
			""
		)

		task.wait(0.18)

		root.Anchored = false
		humanoid.WalkSpeed = ARRIVAL_WALK_SPEED
		humanoid.AutoRotate = false

		local token =
			HttpService:GenerateGUID(false)

		pendingWalkTokens[player.UserId] = {
			Token = token,
			Done = false,
		}

		fadeEvent:FireClient(
			player,
			"in",
			0.34
		)

		autoWalkEvent:FireClient(
			player,
			token,
			direction,
			ARRIVAL_WALK_DISTANCE,
			ARRIVAL_WALK_SPEED,
			ARRIVAL_TIMEOUT
		)

		local started = os.clock()

		while player.Parent
			and character.Parent
			and pendingWalkTokens[player.UserId]
			and not pendingWalkTokens[player.UserId].Done
			and os.clock() - started
			< ARRIVAL_TIMEOUT + 0.75
		do
			task.wait()
		end

		pendingWalkTokens[player.UserId] = nil

		if humanoid.Parent then
			humanoid:Move(
				Vector3.zero,
				false
			)
			humanoid.WalkSpeed = 16
			humanoid.AutoRotate = true
		end

		if root.Parent then
			root.Anchored = false
			root.AssemblyLinearVelocity =
				Vector3.zero
			root.AssemblyAngularVelocity =
				Vector3.zero
		end

		player:SetAttribute(
			"HouseTravelState",
			"Ready"
		)

		controlLockEvent:FireClient(
			player,
			false
		)
	end

	player.CharacterAdded:Connect(run)

	if player.Character then
		task.spawn(run, player.Character)
	end
end

local function setupPlayer(player: Player)
	player:SetAttribute(
		"HouseInteriorLoaded",
		false
	)

	player:SetAttribute(
		"HouseTravelState",
		"Loading"
	)

	local arrival = readTeleportData(player)

	if not arrival then
		player:Kick(
			"No se pudo validar tu entrada a la casa."
		)
		return
	end

	local slot = findFreeSlot()

	if not slot then
		player:Kick(
			"No hay interiores libres en este servidor. Inténtalo otra vez."
		)
		return
	end

	local house = findHouse(slot)

	if not house then
		return
	end

	occupiedSlots[slot] = player.UserId

	sessions[player.UserId] = {
		UserId = player.UserId,
		InteriorSlotNumber = slot,
		ExteriorHouseName =
			arrival.ExteriorHouseName,
		ExteriorHouseNumber =
			tonumber(arrival.ExteriorHouseNumber),
		ExteriorPlaceId =
			tonumber(arrival.ExteriorPlaceId),
		ExteriorJobId =
			tostring(arrival.ExteriorJobId),
		State = "Interior",
		UpdatedAt = os.time(),
		StudioTest =
			arrival.StudioTest == true,
	}

	player:SetAttribute("HouseNumber", slot)
	player:SetAttribute(
		"InteriorSlotNumber",
		slot
	)
	player:SetAttribute(
		"ExteriorHouseName",
		arrival.ExteriorHouseName
	)
	player:SetAttribute(
		"ExteriorHouseNumber",
		tonumber(
			arrival.ExteriorHouseNumber
		)
	)
	player:SetAttribute(
		"ExteriorPlaceId",
		tonumber(arrival.ExteriorPlaceId)
	)
	player:SetAttribute(
		"ExteriorJobId",
		tostring(arrival.ExteriorJobId)
	)
	player:SetAttribute(
		"InteriorSlotReady",
		true
	)
	player:SetAttribute(
		"HouseLocation",
		"Interior"
	)

	house:SetAttribute(
		"RuntimeOwnerUserId",
		player.UserId
	)

	house:SetAttribute(
		"RuntimeOwnerName",
		player.Name
	)

	writeSession(player, "Interior")
	placeAndWalkPlayer(player, house)

	print(string.format(
		"[InteriorSlot] %s: exterior=%s, slot interior=Casa%d",
		player.Name,
		tostring(arrival.ExteriorHouseName),
		slot
		))
end

local function publishExteriorRelease(
	player: Player,
	sessionData: any,
	reason: string
)
	if type(sessionData) ~= "table"
		or sessionData.StudioTest == true
	then
		return
	end

	local ok, err = pcall(function()
		MessagingService:PublishAsync(
			HOUSE_RELEASE_CHANNEL,
			{
				Action = "ReleaseExterior",
				UserId = player.UserId,
				ExteriorHouseName =
					sessionData.ExteriorHouseName,
				ExteriorHouseNumber =
					sessionData.ExteriorHouseNumber,
				ExteriorJobId =
					sessionData.ExteriorJobId,
				Reason = reason,
				UpdatedAt = os.time(),
			}
		)
	end)

	if not ok then
		warn("[InteriorSlot] No se pudo avisar la liberación exterior de "
			.. player.Name
			.. ": "
			.. tostring(err))
	end
end

local function releaseSlot(player: Player)
	local userId = player.UserId
	local sessionData = sessions[userId]

	local returningToExterior =
		player:GetAttribute(
			"ReturningToExterior"
		) == true

	-- Si no está regresando por DoorSpawn, significa que cerró Roblox,
	-- perdió conexión o salió al lobby. Se borra la sesión y se avisa
	-- al servidor exterior de inmediato.
	if not returningToExterior then
		pcall(function()
			HouseSessionMap:RemoveAsync(
				"user_" .. tostring(userId)
			)
		end)

		local reason =
			player:GetAttribute("LeavingToLobby") == true
			and "salió al lobby desde el interior"
			or "cerró Roblox o perdió conexión dentro de la casa"

		publishExteriorRelease(
			player,
			sessionData,
			reason
		)
	end

	local slot =
		tonumber(
			player:GetAttribute(
				"InteriorSlotNumber"
			)
		)

	if slot
		and occupiedSlots[slot] == userId
	then
		occupiedSlots[slot] = nil

		local house = findHouse(slot)

		if house
			and tonumber(
				house:GetAttribute(
					"RuntimeOwnerUserId"
				)
			) == userId
		then
			house:SetAttribute(
				"RuntimeOwnerUserId",
				nil
			)
			house:SetAttribute(
				"RuntimeOwnerName",
				nil
			)
		end

		print("[InteriorSlot] Casa"
			.. tostring(slot)
			.. " interior liberada para otro jugador.")
	end

	pendingWalkTokens[userId] = nil
	sessions[userId] = nil
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(releaseSlot)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

task.spawn(function()
	while task.wait(HEARTBEAT_INTERVAL) do
		for _, player in ipairs(
			Players:GetPlayers()
			) do
			if player:GetAttribute(
				"LeavingToLobby"
				) ~= true
					and player:GetAttribute(
						"ReturningToExterior"
					) ~= true
			then
				writeSession(
					player,
					"Interior"
				)
			end
		end
	end
end)

print("[InteriorSlot] Coordinador V4.2 iniciado: "
	.. "liberación exterior inmediata activa.")