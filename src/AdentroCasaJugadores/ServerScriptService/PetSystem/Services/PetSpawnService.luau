--============================================================
-- PetSpawnService V1
-- Tipo: ModuleScript
-- Ubicacion:
-- ServerScriptService > PetSystem > Services > PetSpawnService
--
-- FASE 3A:
-- Extrae TODA la logica actual de PetServer:
-- - equipar
-- - validar inventario/tier
-- - buscar modelo base/pañuelo
-- - crear fuente del PetRenderer
-- - restaurar al respawn
-- - destruir mascotas del jugador
--
-- IMPORTANTE:
-- Conserva el comportamiento del PetServer actual.
-- BrizabelleEggServer TODAVIA no se modifica en esta fase.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PetSpawnService = {}

--============================================================
-- CONFIG / CONTRATOS EXISTENTES
--============================================================

local PET_COLLISION_GROUP = "Pets"

local EGG_NAME = "Huevo Mascota"

local SLEEP_LOCK_ATTR = "BrizabellePetSleeping"
local SLEEP_RESTORE_PET_ATTR = "BrizabelleRestorePetAfterSleep"
local SLEEP_RESTORE_UNTIL_ATTR = "BrizabelleRestorePetUntil"

local DIRTY_EGG_TEMPLATE_NAME = "Huevo sucio"

local PetsFolder = ReplicatedStorage:WaitForChild("Mascotas")
local EquipEvent = ReplicatedStorage:WaitForChild("EquipPet")

-- Se conservan EXACTAMENTE los alias que usaba el PetServer actual.
local PET_NAME_ALIASES = {
	["HuevoBrizabelle"] = "Huevo Mascota",
	["PezDorado"] = "Pez dorado",
}

local VARIANT_FOLDERS = {
	Comun = "Mascotas pañuelos grises",
	["Poco comun"] = "Mascotas pañuelos verdes",
	Raro = "Mascotas pañuelos azul",
	Epico = "Mascotas pañuelos morado",
	Legendario = "Mascotas pañuelos dorado",
}

--============================================================
-- RUNTIME
--============================================================

local started = false
local restoreTokens = {}

local playerConnections = {}
local globalConnections = {}

-- Evita que los SetAttribute hechos por SpawnPet vuelvan a disparar
-- otra restauración y reconstruyan visualmente la mascota varias veces.
local internalSelectionWrite = {}

--============================================================
-- HELPERS
--============================================================

local function normalizeTier(tier)
	tier = tostring(tier or "Base")

	if tier == "" then
		return "Base"
	end

	return tier
end

local function normalizeName(value)
	local clean = tostring(value or ""):lower()

	clean = clean
		:gsub("á", "a")
		:gsub("é", "e")
		:gsub("í", "i")
		:gsub("ó", "o")
		:gsub("ú", "u")
		:gsub("ñ", "n")

	clean = clean:gsub("[%s_%-]+", "")

	return clean
end

local function isSheepName(value)
	return normalizeName(value):find("oveja", 1, true) ~= nil
end

local function normalizeInventoryPetName(petName)
	petName = tostring(petName or "")

	return PET_NAME_ALIASES[petName] or petName
end

--============================================================
-- INVENTARIO
--============================================================

function PetSpawnService.GetInventoryPetValue(
	player,
	petName,
	requestedTier
)
	petName = normalizeInventoryPetName(petName)

	requestedTier =
		requestedTier ~= nil
		and normalizeTier(requestedTier)
		or nil

	local container =
		player:FindFirstChild("TradePetsInventory")

	if not container then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("IntValue")
			or child:IsA("NumberValue") then

			local itemName =
				normalizeInventoryPetName(
					child:GetAttribute("ItemName")
					or child.Name
				)

			local itemTier =
				normalizeTier(
					child:GetAttribute("UpgradeTier")
				)

			if itemName == petName
				and (
					requestedTier == nil
						or itemTier == requestedTier
				) then

				return child
			end
		end
	end

	return nil
end

--============================================================
-- MODELOS
--============================================================

local function resolvePetName(petName)
	if PetsFolder:FindFirstChild(petName) then
		return petName
	end

	local alias = PET_NAME_ALIASES[petName]

	if alias
		and PetsFolder:FindFirstChild(alias) then

		return alias
	end

	return petName
end

local function findVariantFolder(tier)
	local folderName =
		VARIANT_FOLDERS[normalizeTier(tier)]

	if not folderName then
		return nil
	end

	for _, root in ipairs({
		Workspace,
		ReplicatedStorage,
		}) do

		local animals =
			root:FindFirstChild("Animales pañuelos")

		if animals then
			local direct =
				animals:FindFirstChild(folderName)

			if direct then
				return direct
			end
		end

		local nested =
			root:FindFirstChild(folderName, true)

		if nested then
			return nested
		end
	end

	return nil
end

function PetSpawnService.FindPetTemplate(
	petName,
	tier
)
	tier = normalizeTier(tier)

	if tier == "Base"
		or petName == EGG_NAME then

		return PetsFolder:FindFirstChild(petName)
	end

	local folder = findVariantFolder(tier)

	if not folder then
		warn(
			"[PetSpawnService] No se encontró carpeta para tier:",
			tier
		)

		return nil
	end

	local exact = folder:FindFirstChild(petName)

	if exact
		and exact:IsA("Model") then

		return exact
	end

	for _, object in ipairs(folder:GetDescendants()) do
		if object:IsA("Model") then

			if normalizeName(object.Name)
				== normalizeName(petName) then

				return object
			end

			if isSheepName(object.Name)
				and isSheepName(petName) then

				return object
			end
		end
	end

	return nil
end

--============================================================
-- MASCOTAS ACTIVAS
--============================================================

local function isPetOfPlayer(object, userId)
	return object:IsA("Model")
		and object:GetAttribute("Owner") == userId
		and object:GetAttribute("PetType") ~= nil
end

function PetSpawnService.FindActivePet(
	player,
	petName
)
	petName =
		petName ~= nil
		and normalizeInventoryPetName(petName)
		or nil

	for _, object in ipairs(Workspace:GetChildren()) do
		if isPetOfPlayer(
			object,
			player.UserId
			) then

			if not petName then
				return object
			end

			local objectPetName =
				normalizeInventoryPetName(
					object:GetAttribute("PetType")
				)

			if objectPetName == petName then
				return object
			end
		end
	end

	return nil
end

function PetSpawnService.DestroyAllPets(playerOrUserId)
	local userId

	if typeof(playerOrUserId) == "Instance"
		and playerOrUserId:IsA("Player") then

		userId = playerOrUserId.UserId
	else
		userId = tonumber(playerOrUserId)
	end

	if not userId then
		return
	end

	for _, object in ipairs(Workspace:GetChildren()) do
		if isPetOfPlayer(object, userId) then
			object:Destroy()
		end
	end
end

function PetSpawnService.DestroyPet(
	player,
	petName
)
	if not player then
		return
	end

	petName =
		normalizeInventoryPetName(petName)

	for _, object in ipairs(Workspace:GetChildren()) do
		if isPetOfPlayer(
			object,
			player.UserId
			) then

			local objectPetName =
				normalizeInventoryPetName(
					object:GetAttribute("PetType")
				)

			if objectPetName == petName then
				object:Destroy()
			end
		end
	end
end

--============================================================
-- HUEVO SUCIO
--============================================================

local function getDirtyEggVisualPart()
	local candidateNames = {
		"Huevo sucio",
		"Huevo Sucio",
		"HuevoSucio",
	}

	for _, root in ipairs({
		Workspace,
		ReplicatedStorage,
		ServerStorage,
		}) do
		for _, candidateName in ipairs(candidateNames) do
			local template =
				root:FindFirstChild(
					candidateName,
					true
				)

			if template then
				if template:IsA("BasePart") then
					return template
				end

				local preferred =
					template:FindFirstChild(
						"Huevo Sucio",
						true
					)
					or template:FindFirstChild(
						"Torso",
						true
					)

				if preferred
					and preferred:IsA("BasePart") then

					return preferred
				end

				local anyPart =
					template:FindFirstChildWhichIsA(
						"BasePart",
						true
					)

				if anyPart then
					return anyPart
				end
			end
		end
	end

	warn(
		"[PetSpawnService] No encontré el template 'Huevo sucio'."
	)

	return nil
end

local function applyDirtyEggAppearance(model)
	local dirtyVisual =
		getDirtyEggVisualPart()

	local oldTorso =
		model:FindFirstChild(
			"Torso",
			true
		)

	local root =
		model:FindFirstChild(
			"HumanoidRootPart"
		)

	if not dirtyVisual
		or not oldTorso
		or not oldTorso:IsA("BasePart")
		or not root then

		return
	end

	local dirtyTorso =
		dirtyVisual:Clone()

	dirtyTorso.Name = "Torso"
	dirtyTorso.CFrame = oldTorso.CFrame
	dirtyTorso.Anchored = oldTorso.Anchored
	dirtyTorso.CanCollide = oldTorso.CanCollide
	dirtyTorso.CanTouch = oldTorso.CanTouch
	dirtyTorso.CanQuery = oldTorso.CanQuery
	dirtyTorso.Massless = oldTorso.Massless
	dirtyTorso.CastShadow = oldTorso.CastShadow
	dirtyTorso.Parent = oldTorso.Parent

	for _, joint in ipairs(root:GetChildren()) do
		if joint:IsA("Motor6D")
			and joint.Part1 == oldTorso then

			joint.Part1 = dirtyTorso
		end
	end

	oldTorso:Destroy()

	model:SetAttribute(
		"DirtyEggVisual",
		true
	)
end

--============================================================
-- PREPARAR FUENTE DE PETRENDERER
--============================================================

local function configureServerSource(
	pet,
	petRoot
)
	pet.PrimaryPart = petRoot

	for _, object in ipairs(
		pet:GetDescendants()
		) do

		if object:IsA("BasePart") then
			object.Anchored =
				object == petRoot

			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
			object.CastShadow = false
			object.CollisionGroup =
				PET_COLLISION_GROUP
		end
	end

	local humanoid =
		pet:FindFirstChildOfClass(
			"Humanoid"
		)

	if humanoid then
		pcall(function()
			humanoid.EvaluateStateMachine =
				false
		end)

		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end
end

--============================================================
-- SPAWN PRINCIPAL
--============================================================

function PetSpawnService.SpawnPet(
	player,
	petName,
	requestedTier
)
	if not player
		or player.Parent ~= Players then

		return nil
	end

	-- Un SpawnPet explícito gana sobre cualquier RestoreSelectedPet
	-- retrasado que haya sido programado por cambios de atributos.
	restoreTokens[player] =
		(restoreTokens[player] or 0) + 1

	if player:GetAttribute(
		SLEEP_LOCK_ATTR
		) == true then

		return nil
	end

	if typeof(petName) ~= "string" then
		return nil
	end

	petName =
		normalizeInventoryPetName(petName)

	if petName == "" then
		PetSpawnService.DestroyAllPets(player)
		return nil
	end

	local resolvedPetName =
		resolvePetName(petName)

	local selectedTier =
		normalizeTier(
			requestedTier
			or player:GetAttribute(
				"SelectedBackpackPetTier"
			)
			or "Base"
		)

	--========================================================
	-- RESTAURACION DESPUES DE DORMIR
	--========================================================

	local restorePet =
		normalizeInventoryPetName(
			player:GetAttribute(
				SLEEP_RESTORE_PET_ATTR
			)
			or ""
		)

	local restoreUntil =
		tonumber(
			player:GetAttribute(
				SLEEP_RESTORE_UNTIL_ATTR
			)
		)
		or 0

	if resolvedPetName == EGG_NAME
		and restorePet ~= ""
		and os.clock() < restoreUntil
		and PetSpawnService.GetInventoryPetValue(
			player,
			restorePet
		) then

		resolvedPetName =
			resolvePetName(restorePet)

		local restoreValue =
			PetSpawnService.GetInventoryPetValue(
				player,
				resolvedPetName
			)

		selectedTier =
			restoreValue
			and normalizeTier(
				restoreValue:GetAttribute(
					"UpgradeTier"
				)
			)
			or "Base"

		player:SetAttribute(
			"SelectedBackpackPet",
			resolvedPetName
		)

		player:SetAttribute(
			"SelectedBackpackPetTier",
			selectedTier
		)
	end

	--========================================================
	-- VALIDACION DEL INVENTARIO
	--========================================================

	local petValue =
		PetSpawnService.GetInventoryPetValue(
			player,
			resolvedPetName,
			selectedTier
		)

	--========================================================
	-- TIER ESTRICTO V1.2
	--
	-- Nunca cambiar silenciosamente de Base -> Comun/Raro/etc.
	-- Si el jugador eligió Perro Base, SOLO puede salir Perro Base.
	--========================================================

	if not petValue then
		warn(
			"[PetSpawnService] El jugador no posee exactamente:",
			resolvedPetName,
			"tier:",
			selectedTier
		)

		return nil
	end

	selectedTier =
		normalizeTier(
			petValue:GetAttribute(
				"UpgradeTier"
			)
			or selectedTier
		)

	--========================================================
	-- V1.3: REUTILIZAR FUENTE SI YA ES EXACTAMENTE LA MISMA
	--========================================================

	local exactActive = nil

	for _, object in ipairs(
		Workspace:GetChildren()
		) do
		if isPetOfPlayer(
			object,
			player.UserId
			) then

			local objectName =
				normalizeInventoryPetName(
					object:GetAttribute(
						"PetType"
					)
				)

			local objectTier =
				normalizeTier(
					object:GetAttribute(
						"UpgradeTier"
					)
				)

			if objectName == resolvedPetName
				and objectTier == selectedTier then

				if not exactActive then
					exactActive = object
				else
					-- Limpiar duplicados que hayan quedado de versiones previas.
					object:Destroy()
				end
			end
		end
	end

	if exactActive
		and exactActive.Parent == Workspace then

		-- Solo puede existir una fuente follower por jugador.
		for _, object in ipairs(
			Workspace:GetChildren()
			) do
			if object ~= exactActive
				and isPetOfPlayer(
					object,
					player.UserId
				) then

				object:Destroy()
			end
		end

		internalSelectionWrite[player] = true

		if player:GetAttribute(
			"SelectedBackpackPet"
			) ~= resolvedPetName then

			player:SetAttribute(
				"SelectedBackpackPet",
				resolvedPetName
			)
		end

		if normalizeTier(
			player:GetAttribute(
				"SelectedBackpackPetTier"
			)
			) ~= selectedTier then

			player:SetAttribute(
				"SelectedBackpackPetTier",
				selectedTier
			)
		end

		internalSelectionWrite[player] = nil

		return exactActive
	end

	PetSpawnService.DestroyAllPets(player)

	--========================================================
	-- NO CREAR PET SI ESTA EN LA CAMA
	--========================================================

	local sleepingEgg =
		Workspace:FindFirstChild(
			"BrizabelleSleepingEgg_"
			.. player.UserId
		)

	local sleepingPet =
		Workspace:FindFirstChild(
			"BrizabelleSleepingPet_"
			.. player.UserId
		)

	if petValue:GetAttribute(
		"Resting"
		) == true then

		if sleepingEgg or sleepingPet then
			return nil
		end

		petValue:SetAttribute(
			"Resting",
			false
		)
	end

	if sleepingEgg or sleepingPet then
		return nil
	end

	--========================================================
	-- MODELO
	--========================================================

	local useDirtyEgg =
		resolvedPetName == EGG_NAME
		and petValue:GetAttribute(
			"Dirty"
		) == true

	local template =
		PetSpawnService.FindPetTemplate(
			resolvedPetName,
			selectedTier
		)

	if not template
		or not template:IsA("Model") then

		warn(
			"[PetSpawnService] No existe modelo para:",
			resolvedPetName,
			"tier:",
			selectedTier
		)

		return nil
	end

	local character = player.Character

	local playerRoot =
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not playerRoot then
		return nil
	end

	local pet = template:Clone()
	pet.Name = resolvedPetName

	if useDirtyEgg then
		applyDirtyEggAppearance(pet)
	end

	local petRoot =
		pet:FindFirstChild(
			"HumanoidRootPart"
		)
		or pet.PrimaryPart
		or pet:FindFirstChildWhichIsA(
			"BasePart",
			true
		)

	if not petRoot
		or not petRoot:IsA("BasePart") then

		warn(
			"[PetSpawnService] La mascota no tiene HumanoidRootPart/BasePart:",
			resolvedPetName,
			selectedTier
		)

		pet:Destroy()
		return nil
	end

	configureServerSource(
		pet,
		petRoot
	)

	-- Contrato usado por PetRenderer, Trade y Frank.
	pet:SetAttribute(
		"Owner",
		player.UserId
	)

	pet:SetAttribute(
		"PetType",
		resolvedPetName
	)

	pet:SetAttribute(
		"UpgradeTier",
		selectedTier
	)

	pet:SetAttribute(
		"IsMoving",
		false
	)

	pet:SetAttribute(
		"PetRenderSource",
		true
	)

	internalSelectionWrite[player] = true

	if player:GetAttribute(
		"SelectedBackpackPet"
		) ~= resolvedPetName then

		player:SetAttribute(
			"SelectedBackpackPet",
			resolvedPetName
		)
	end

	if normalizeTier(
		player:GetAttribute(
			"SelectedBackpackPetTier"
		)
		) ~= selectedTier then

		player:SetAttribute(
			"SelectedBackpackPetTier",
			selectedTier
		)
	end

	internalSelectionWrite[player] = nil

	pet.Parent = Workspace

	pcall(function()
		pet.ModelStreamingMode =
			Enum.ModelStreamingMode.Persistent
	end)

	pet:PivotTo(
		playerRoot.CFrame
			* CFrame.new(0, 0, 4)
	)

	return pet
end

--============================================================
-- RESTAURAR SELECCION
--============================================================

function PetSpawnService.RestoreSelectedPet(
	player
)
	restoreTokens[player] =
		(restoreTokens[player] or 0) + 1

	local token =
		restoreTokens[player]

	task.spawn(function()
		local container =
			player:WaitForChild(
				"TradePetsInventory",
				15
			)

		if not container
			or not player.Parent then

			return
		end

		local startedAt = os.clock()

		while player.Parent
			and os.clock() - startedAt < 12 do

			if restoreTokens[player]
				~= token then

				return
			end

			local petName =
				player:GetAttribute(
					"SelectedBackpackPet"
				)

			local tier =
				normalizeTier(
					player:GetAttribute(
						"SelectedBackpackPetTier"
					)
				)

			if typeof(petName) == "string"
				and petName ~= "" then

				petName =
					normalizeInventoryPetName(
						petName
					)

				local owned =
					PetSpawnService.GetInventoryPetValue(
						player,
						petName,
						tier
					)

				-- V1.2:
				-- No buscar "cualquier tier" si el seleccionado no existe.
				-- Eso era lo que convertía una selección Base en pañuelo.

				local character =
					player.Character

				local root =
					character
					and character:FindFirstChild(
						"HumanoidRootPart"
					)

				if owned and root then
					task.wait(0.35)

					if restoreTokens[player]
						== token
						and player.Parent
						and player.Character
						== character then

						PetSpawnService.SpawnPet(
							player,
							petName,
							tier
						)
					end

					return
				end
			end

			task.wait(0.2)
		end
	end)
end

--============================================================
-- PLAYER SETUP
--============================================================

local function addPlayerConnection(
	player,
	connection
)
	playerConnections[player] =
		playerConnections[player] or {}

	table.insert(
		playerConnections[player],
		connection
	)
end

function PetSpawnService.SetupPlayer(
	player
)
	if playerConnections[player] then
		return
	end

	playerConnections[player] = {}

	addPlayerConnection(
		player,
		player.CharacterAdded:Connect(function()
			PetSpawnService.DestroyAllPets(player)

			PetSpawnService.RestoreSelectedPet(
				player
			)
		end)
	)

	addPlayerConnection(
		player,
		player:GetAttributeChangedSignal(
			"SelectedBackpackPet"
		):Connect(function()

			if internalSelectionWrite[player] then
				return
			end

			if player.Character then
				PetSpawnService.RestoreSelectedPet(
					player
				)
			end
		end)
	)

	addPlayerConnection(
		player,
		player:GetAttributeChangedSignal(
			"SelectedBackpackPetTier"
		):Connect(function()

			if internalSelectionWrite[player] then
				return
			end

			if player.Character then
				PetSpawnService.RestoreSelectedPet(
					player
				)
			end
		end)
	)

	if player.Character then
		PetSpawnService.RestoreSelectedPet(
			player
		)
	end
end

function PetSpawnService.CleanupPlayer(
	player
)
	restoreTokens[player] = nil
	internalSelectionWrite[player] = nil

	local connections =
		playerConnections[player]

	playerConnections[player] = nil

	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	PetSpawnService.DestroyAllPets(player)
end

--============================================================
-- START
--============================================================

function PetSpawnService.Start()
	if started then
		return
	end

	started = true

	pcall(function()
		PhysicsService:RegisterCollisionGroup(
			PET_COLLISION_GROUP
		)
	end)

	PhysicsService:CollisionGroupSetCollidable(
		PET_COLLISION_GROUP,
		"Default",
		false
	)

	PhysicsService:CollisionGroupSetCollidable(
		PET_COLLISION_GROUP,
		PET_COLLISION_GROUP,
		false
	)

	table.insert(
		globalConnections,
		EquipEvent.OnServerEvent:Connect(
			function(player, petName, tier)
				PetSpawnService.SpawnPet(
					player,
					petName,
					tier
				)
			end
		)
	)

	table.insert(
		globalConnections,
		Players.PlayerAdded:Connect(
			PetSpawnService.SetupPlayer
		)
	)

	table.insert(
		globalConnections,
		Players.PlayerRemoving:Connect(
			PetSpawnService.CleanupPlayer
		)
	)

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		PetSpawnService.SetupPlayer(player)
	end
end
return PetSpawnService
