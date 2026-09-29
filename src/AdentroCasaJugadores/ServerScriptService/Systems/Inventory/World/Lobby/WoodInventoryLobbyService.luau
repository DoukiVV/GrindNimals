--============================================================
-- WoodInventoryLobbyService - ORGANIZADO
-- Tipo: ModuleScript
--
-- Este modulo conserva la logica del script original.
-- Se inicia desde un bootstrap pequeno en ServerScriptService.
--============================================================

local WoodInventoryLobbyService = {}
local started = false

function WoodInventoryLobbyService.Start()
	if started then
		return
	end
	started = true

	--============================================================
	-- WOOD INVENTORY LOBBY V2 - TRADE BRIDGE
	--
	-- UBICACION:
	-- ServerScriptService > WoodInventoryLobbyServer
	-- TIPO: Script
	--
	-- SOLO PARA EL LOBBY.
	--
	-- OBJETIVO:
	-- - Cargar y mostrar la madera conseguida en el Bosque.
	-- - Mantener los stacks visibles x99.
	-- - Permitir que TradeServer transfiera madera en el LOBBY
	--   SIN necesitar TreeChopServer ni Workspace.Arboles.
	--
	-- DataStore compartido con Bosque:
	-- TreeWoodInventoryV1
	--
	-- CREA:
	-- ServerStorage > TreeWoodBridge
	--   > GetWoodState   (BindableFunction)
	--   > TransferWood   (BindableFunction)
	--
	-- IMPORTANTE:
	-- En el LOBBY NO debes tener TreeChopServer.
	--============================================================

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local DataStoreService = game:GetService("DataStoreService")
	local ServerStorage = game:GetService("ServerStorage")

	local STORE_NAME = "TreeWoodInventoryV1"
	local MAX_STACK = 99
	local AUTOSAVE_SECONDS = 60

	local WOOD_TYPES = {
		"MaderaRoble",
		"MaderaAbedul",
		"MaderaAbeto",
	}

	local VALID_WOOD_TYPES = {
		MaderaRoble = true,
		MaderaAbedul = true,
		MaderaAbeto = true,
	}

	local DISPLAY_NAMES = {
		MaderaRoble = "Madera Roble",
		MaderaAbedul = "Madera Abedul",
		MaderaAbeto = "Madera Abeto",
	}

	local woodStore =
		DataStoreService:GetDataStore(
			STORE_NAME
		)

	local loadedCounts = {}
	local loaded = {}
	local syncing = {}
	local transferLocks = {}

	--============================================================
	-- HELPERS
	--============================================================

	local function normalize(text)
		text =
			tostring(
				text or ""
			):lower()

		text =
			text
			:gsub("á", "a")
			:gsub("é", "e")
			:gsub("í", "i")
			:gsub("ó", "o")
			:gsub("ú", "u")
			:gsub("ü", "u")
			:gsub("ñ", "n")
			:gsub("[%s_%-%.,]+", "")

		return text
	end

	local function canonicalWoodType(name)
		local key =
			normalize(
				name
			)

		if key == "maderaroble" then
			return "MaderaRoble"
		elseif key == "maderaabedul" then
			return "MaderaAbedul"
		elseif key == "maderaabeto" then
			return "MaderaAbeto"
		end

		return nil
	end

	local function defaultCounts()
		return {
			MaderaRoble = 0,
			MaderaAbedul = 0,
			MaderaAbeto = 0,
		}
	end

	local function copyCounts(source)
		source =
			source
			or defaultCounts()

		return {
			MaderaRoble =
				math.max(
					0,
					math.floor(
						tonumber(
							source.MaderaRoble
						) or 0
					)
				),

			MaderaAbedul =
				math.max(
					0,
					math.floor(
						tonumber(
							source.MaderaAbedul
						) or 0
					)
				),

			MaderaAbeto =
				math.max(
					0,
					math.floor(
						tonumber(
							source.MaderaAbeto
						) or 0
					)
				),
		}
	end

	local function sanitizeCounts(raw)
		if typeof(raw) ~= "table" then
			return defaultCounts()
		end

		local source =
			typeof(raw.Counts) == "table"
			and raw.Counts
			or raw

		return copyCounts(source)
	end

	local function findTemplate(woodType)
		local exact =
			ReplicatedStorage:FindFirstChild(
				woodType
			)

		if exact
			and exact:IsA("Tool")
		then
			return exact
		end

		local wanted =
			normalize(
				DISPLAY_NAMES[woodType]
				or woodType
			)

		for _, child in ipairs(
			ReplicatedStorage:GetChildren()
			) do
			if child:IsA("Tool") then
				local candidate =
					normalize(
						child:GetAttribute("ItemName")
						or child.Name
					)

				if candidate == wanted
					or canonicalWoodType(candidate) == woodType
				then
					return child
				end
			end
		end

		return nil
	end

	local function getWoodTypeFromTool(tool)
		if not tool
			or not tool:IsA("Tool")
		then
			return nil
		end

		return
			canonicalWoodType(
				tool:GetAttribute("WoodType")
				or tool:GetAttribute("ItemName")
				or tool.Name
			)
	end

	local function configureWood(
		tool,
		woodType,
		amount
	)
		local displayName =
			DISPLAY_NAMES[woodType]
			or woodType

		amount =
			math.clamp(
				math.floor(
					tonumber(amount)
					or 1
				),
				1,
				MAX_STACK
			)

		-- La madera del Lobby es solo inventario.
		-- Quitamos scripts/prompt de plantillas por seguridad.
		for _, object in ipairs(
			tool:GetDescendants()
			) do
			if object:IsA("Script")
				or object:IsA("LocalScript")
				or object:IsA("ProximityPrompt")
			then
				object:Destroy()
			end
		end

		tool:SetAttribute("EsMadera", true)
		tool:SetAttribute("WoodType", woodType)
		tool:SetAttribute("WoodStackQuantity", amount)
		tool:SetAttribute("Cantidad", amount)
		tool:SetAttribute("ItemType", "Material")
		tool:SetAttribute("ItemName", displayName)
		tool:SetAttribute("BackpackDisplayName", displayName)

		tool.CanBeDropped = false
		tool.Name = displayName
	end

	local function clearExistingWood(player)
		local containers = {
			player.Character,
			player:FindFirstChildOfClass("Backpack"),
		}

		for _, container in ipairs(containers) do
			if container then
				for _, child in ipairs(
					container:GetChildren()
					) do
					if child:IsA("Tool")
						and getWoodTypeFromTool(child)
					then
						child:Destroy()
					end
				end
			end
		end
	end

	--============================================================
	-- GUARDADO
	--============================================================

	local function saveWood(player)
		if not loaded[player] then
			return false
		end

		local counts =
			loadedCounts[player]

		if not counts then
			return false
		end

		local payload = {
			Version = 1,
			UpdatedAt = os.time(),
			Counts = copyCounts(counts),
		}

		local success, err =
			pcall(function()
				woodStore:SetAsync(
					"Player_"
					.. tostring(
						player.UserId
					),
					payload
				)
			end)

		if not success then
			warn(
				"[WoodLobby] Error guardando madera:",
				player.Name,
				err
			)

			return false
		end

		return true
	end

	--============================================================
	-- SINCRONIZAR TOOLS
	--============================================================

	local function syncWood(player)
		if syncing[player] then
			return
		end

		local counts =
			loadedCounts[player]

		if not counts then
			return
		end

		local backpack =
			player:FindFirstChildOfClass(
				"Backpack"
			)

		if not backpack then
			return
		end

		syncing[player] = true

		clearExistingWood(player)

		for _, woodType in ipairs(
			WOOD_TYPES
			) do
			local total =
				math.max(
					0,
					math.floor(
						tonumber(
							counts[woodType]
						) or 0
					)
				)

			if total > 0 then
				local template =
					findTemplate(
						woodType
					)

				if not template
					or not template:IsA("Tool")
				then
					warn(
						"[WoodLobby] Falta ReplicatedStorage >",
						woodType
					)
				else
					local remaining = total

					while remaining > 0 do
						local amount =
							math.min(
								MAX_STACK,
								remaining
							)

						local clone =
							template:Clone()

						configureWood(
							clone,
							woodType,
							amount
						)

						clone.Parent =
							backpack

						remaining -= amount
					end
				end
			end
		end

		syncing[player] = nil
	end

	--============================================================
	-- CARGAR
	--============================================================

	local function loadWood(player)
		if loaded[player] then
			return
		end

		local success, raw =
			pcall(function()
				return woodStore:GetAsync(
					"Player_"
					.. tostring(
						player.UserId
					)
				)
			end)

		if not success then
			warn(
				"[WoodLobby] Error cargando madera:",
				player.Name,
				raw
			)

			raw = nil
		end

		loadedCounts[player] =
			sanitizeCounts(
				raw
			)

		loaded[player] = true

		player:WaitForChild("Backpack")

		syncWood(player)
	end

	local function ensureLoaded(player)
		if loaded[player]
			and loadedCounts[player]
		then
			return true
		end

		loadWood(player)

		return
			loaded[player] == true
			and loadedCounts[player] ~= nil
	end

	--============================================================
	-- BRIDGE SERVER-ONLY PARA TRADE
	--============================================================

	local oldBridge =
		ServerStorage:FindFirstChild(
			"TreeWoodBridge"
		)

	if oldBridge then
		oldBridge:Destroy()
	end

	local bridge =
		Instance.new("Folder")

	bridge.Name =
		"TreeWoodBridge"

	bridge.Parent =
		ServerStorage

	local getWoodState =
		Instance.new(
			"BindableFunction"
		)

	getWoodState.Name =
		"GetWoodState"

	getWoodState.Parent =
		bridge

	local transferWood =
		Instance.new(
			"BindableFunction"
		)

	transferWood.Name =
		"TransferWood"

	transferWood.Parent =
		bridge

	getWoodState.OnInvoke =
		function(player)
			if not player
				or player.Parent ~= Players
			then
				return {
					Success = false,
					Counts = defaultCounts(),
				}
			end

			if not ensureLoaded(player) then
				return {
					Success = false,
					Counts = defaultCounts(),
				}
			end

			return {
				Success = true,
				Counts =
				copyCounts(
					loadedCounts[player]
				),
			}
		end

	transferWood.OnInvoke =
		function(
			sender,
			receiver,
			woodType,
			requestedAmount
		)
		if not sender
			or not receiver
			or sender == receiver
			or sender.Parent ~= Players
			or receiver.Parent ~= Players
		then
			return {
				Success = false,
				Message =
					"Jugadores no validos.",
			}
		end

		woodType =
			canonicalWoodType(
				woodType
			)

		if not woodType
			or not VALID_WOOD_TYPES[
			woodType
			]
		then
			return {
				Success = false,
				Message =
					"Tipo de madera no valido.",
			}
		end

		local amount =
			math.floor(
				tonumber(
					requestedAmount
				) or 0
			)

		if amount < 1
			or amount > 9999
		then
			return {
				Success = false,
				Message =
					"Cantidad de madera no valida.",
			}
		end

		if not ensureLoaded(sender)
			or not ensureLoaded(receiver)
		then
			return {
				Success = false,
				Message =
					"Los inventarios de madera aun estan cargando.",
			}
		end

		local firstId =
			math.min(
				sender.UserId,
				receiver.UserId
			)

		local secondId =
			math.max(
				sender.UserId,
				receiver.UserId
			)

		local lockKey =
			tostring(firstId)
			.. ":"
			.. tostring(secondId)

		if transferLocks[lockKey] then
			return {
				Success = false,
				Message =
					"Ya hay una transferencia de madera en proceso.",
			}
		end

		transferLocks[lockKey] = true

		local function finish(result)
			transferLocks[lockKey] = nil
			return result
		end

		local senderCounts =
			loadedCounts[sender]

		local receiverCounts =
			loadedCounts[receiver]

		local senderCurrent =
			math.max(
				0,
				math.floor(
					tonumber(
						senderCounts[
						woodType
						]
					) or 0
				)
			)

		if senderCurrent < amount then
			return finish({
				Success = false,
				Message =
					"No tienes suficiente "
					.. (
						DISPLAY_NAMES[
						woodType
						]
						or "madera"
					)
					.. ".",
			})
		end

		local receiverCurrent =
			math.max(
				0,
				math.floor(
					tonumber(
						receiverCounts[
						woodType
						]
					) or 0
				)
			)

		-- Cambiar primero el estado autoritativo.
		senderCounts[woodType] =
			senderCurrent - amount

		receiverCounts[woodType] =
			receiverCurrent + amount

		local syncOk, syncErr =
			pcall(function()
				syncWood(sender)
				syncWood(receiver)
			end)

		if not syncOk then
			-- Rollback.
			senderCounts[woodType] =
				senderCurrent

			receiverCounts[woodType] =
				receiverCurrent

			pcall(syncWood, sender)
			pcall(syncWood, receiver)

			return finish({
				Success = false,
				Message =
					"No se pudo sincronizar la madera: "
					.. tostring(
						syncErr
					),
			})
		end

		-- Guardado inmediato de ambos.
		local saveA =
			saveWood(sender)

		local saveB =
			saveWood(receiver)

		if not saveA
			or not saveB
		then
			-- Conservamos el estado actual en memoria.
			-- El autosave/PlayerRemoving volvera a intentarlo.
			warn(
				"[WoodLobby] Transferencia hecha pero un guardado inmediato fallo."
			)
		end

		return finish({
			Success = true,
			WoodType = woodType,
			Amount = amount,
			SenderRemaining =
				senderCounts[woodType],
			ReceiverTotal =
				receiverCounts[woodType],
		})
	end

	--============================================================
	-- PLAYER
	--============================================================

	local function setupPlayer(player)
		task.spawn(
			loadWood,
			player
		)

		player.CharacterAdded:Connect(
			function()
				task.delay(
					0.65,
					function()
						if player.Parent == Players then
							syncWood(player)
						end
					end
				)
			end
		)

		player.ChildAdded:Connect(
			function(child)
				if child:IsA("Backpack") then
					task.delay(
						0.30,
						function()
							if player.Parent == Players then
								syncWood(player)
							end
						end
					)
				end
			end
		)
	end

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		setupPlayer(player)
	end

	Players.PlayerAdded:Connect(
		setupPlayer
	)

	task.spawn(function()
		while true do
			task.wait(
				AUTOSAVE_SECONDS
			)

			for _, player in ipairs(
				Players:GetPlayers()
				) do
				if loaded[player] then
					task.spawn(
						saveWood,
						player
					)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(
		function(player)
			if loaded[player] then
				saveWood(player)
			end

			loadedCounts[player] = nil
			loaded[player] = nil
			syncing[player] = nil
		end
	)

	game:BindToClose(function()
		for _, player in ipairs(
			Players:GetPlayers()
			) do
			if loaded[player] then
				saveWood(player)
			end
		end
	end)
end

return WoodInventoryLobbyService
