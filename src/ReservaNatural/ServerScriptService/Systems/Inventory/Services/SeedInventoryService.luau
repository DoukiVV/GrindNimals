--============================================================
-- SeedInventoryService - ORGANIZADO
-- Tipo: ModuleScript
--
-- Este modulo conserva la logica del script original.
-- Se inicia desde un bootstrap pequeno en ServerScriptService.
--============================================================

local SeedInventoryService = {}
local started = false

function SeedInventoryService.Start()
	if started then
		return
	end
	started = true

	--============================================================
	-- SEED INVENTORY SAVE SERVER V9.1 - STACKS + NO TOCAR FRUTAS
	--
	-- TIPO:
	-- Script
	--
	-- UBICACION:
	-- ServerScriptService > SeedInventorySaveServer
	--
	-- IMPORTANTE:
	-- REEMPLAZA COMPLETAMENTE tu SeedInventorySaveServer V8.
	-- NO dejes V6 y V7 juntos.
	--
	-- OBJETIVO:
	-- Antes:
	--   1105 semillas = 1105 Tools
	--
	-- Ahora:
	--   cada Tool puede representar hasta 99 semillas.
	--   1105 semillas se convierten en pocos Tools.
	--
	-- COMPATIBILIDAD:
	-- - Migra correctamente desde JulianSeedInventory_v4 (V6)
	-- - Compatible con tu Julian actual aunque todavía clone x1.
	-- - Compatible con tu GardenPlanting actual aunque haga semilla:Destroy().
	-- - Compatible con semillas recibidas al cosechar.
	-- - Evita volver a duplicar semillas cuando Backpack se reemplaza.
	--
	-- ATRIBUTOS DEL STACK:
	--   SeedStackQuantity
	--   Cantidad
	--   IsSeed
	--   ItemType
	--   ItemName
	--   SeedCropName
	--
	-- MAXIMO POR TOOL: 99
	--============================================================

	local Players = game:GetService("Players")
	local ServerStorage = game:GetService("ServerStorage")
	local DataStoreService = game:GetService("DataStoreService")
	local ServerScriptService = game:GetService("ServerScriptService")

	--============================================================
	-- CONFIG
	--============================================================

	--============================================================
	-- DATASTORES REALES
	--
	-- V6 NO guardaba principalmente en SeedInventory_v1.
	-- Guardaba en JulianSeedInventory_v4.
	--
	-- V9 usa un DataStore NUEVO para stacks y deja V4 intacto
	-- como respaldo de recuperación.
	--============================================================

	local STORE =
		DataStoreService:GetDataStore(
			"JulianSeedInventory_v5Stack"
		)

	local STORE_V4 =
		DataStoreService:GetDataStore(
			"JulianSeedInventory_v4"
		)

	local STORE_V3 =
		DataStoreService:GetDataStore(
			"JulianSeedInventory_v3"
		)

	local STORE_V2 =
		DataStoreService:GetDataStore(
			"JulianSeedInventory_v2"
		)

	local STORE_V1 =
		DataStoreService:GetDataStore(
			"SeedInventory_v1"
		)

	local STACK_LIMIT = 99

	-- Espera para compactar compras de Julian.
	-- Julian primero crea sus Tools y luego llama ForceSeedInventorySave.
	-- Esperar evita interferir con su sistema de revertir una compra.
	local COMPACT_DELAY = 0.45

	-- Guardado por cambios normales.
	local SAVE_DELAY = 4

	-- Autosave mucho menos agresivo que antes.
	local AUTOSAVE_SECONDS = 120

	local SAVE_RETRIES = 3

	--============================================================
	-- RECUPERACION V8
	--
	-- Tus logs anteriores mostraban 1105 semillas antes de que el
	-- DataStore terminara guardando 0. Si el valor actual está vacío,
	-- V8 revisa versiones anteriores de SeedInventory_v1.
	--
	-- Primero busca una versión cercana a 1105. Si no existe,
	-- usa la versión NO VACÍA más cercana encontrada.
	--============================================================

	local RECOVERY_TARGET_TOTAL = 1105
	local RECOVERY_MAX_VERSIONS = 50

	--============================================================
	-- CARPETAS
	--============================================================

	local itemFolder = ServerStorage:WaitForChild("Item")
	local semillasFolder = itemFolder:WaitForChild("Semillas")

	--============================================================
	-- ESTADO
	--============================================================

	local playerState = {}

	-- Tool -> información guardada mientras existe.
	local trackedSeedMeta = setmetatable({}, {__mode = "k"})

	-- Tools destruidos por ESTE script no deben contar como consumo.
	local internalDestroy = setmetatable({}, {__mode = "k"})

	--============================================================
	-- HELPERS
	--============================================================

	local function trim(value)
		return tostring(value or ""):match("^%s*(.-)%s*$")
	end

	local function normalize(value)
		local text = trim(value):lower()

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

	local function cloneCounts(source)
		local result = {}

		for name, amount in pairs(source or {}) do
			if typeof(name) == "string" and typeof(amount) == "number" then
				local safe = math.max(0, math.floor(amount))

				if safe > 0 then
					result[name] = safe
				end
			end
		end

		return result
	end

	local function totalCounts(counts)
		local total = 0

		for _, amount in pairs(counts or {}) do
			total += math.max(0, math.floor(tonumber(amount) or 0))
		end

		return total
	end

	--============================================================
	-- INDICE DE TEMPLATES
	--============================================================

	local templateByKey = {}

	local function cropKeyFromName(value)
		local key = normalize(value)

		for _, prefix in ipairs({
			"semillade",
			"semilla",
			"brote",
			"esporasde",
			"esporas",
			}) do
			if key:sub(1, #prefix) == prefix then
				key = key:sub(#prefix + 1)
				break
			end
		end

		return key
	end

	local function addTemplateKey(key, tool)
		key = normalize(key)

		if key ~= "" then
			templateByKey[key] = tool
		end
	end

	local function rebuildTemplateIndex()
		table.clear(templateByKey)

		for _, tool in ipairs(semillasFolder:GetChildren()) do
			if tool:IsA("Tool") then
				addTemplateKey(tool.Name, tool)
				addTemplateKey(cropKeyFromName(tool.Name), tool)

				local itemName = tool:GetAttribute("ItemName")
				if typeof(itemName) == "string" and itemName ~= "" then
					addTemplateKey(itemName, tool)
					addTemplateKey(cropKeyFromName(itemName), tool)
				end

				local crop = tool:GetAttribute("SeedCropName")
				if typeof(crop) == "string" and crop ~= "" then
					addTemplateKey(crop, tool)
				end
			end
		end
	end

	rebuildTemplateIndex()

	semillasFolder.ChildAdded:Connect(function()
		task.defer(rebuildTemplateIndex)
	end)

	semillasFolder.ChildRemoved:Connect(function()
		task.defer(rebuildTemplateIndex)
	end)

	local function getTemplate(tool)
		if not tool or not tool:IsA("Tool") then
			return nil
		end

		--========================================================
		-- V9.1 CRITICO:
		-- UNA FRUTA NUNCA PUEDE ENTRAR AL SISTEMA DE SEMILLAS.
		--
		-- Antes, Mango/Naranja/Coco/Carambola coincidían por nombre con
		-- templates de ServerStorage > Item > Semillas. SeedSaveV9 los
		-- convertía en IsSeed=true y compactaba 99 frutas en 1 Tool.
		-- Resultado: el inventario de frutas terminaba mostrando x1.
		--========================================================
		if tool:GetAttribute("IsFruit") == true then
			return nil
		end

		local fruitName = tool:GetAttribute("FruitName")
		if typeof(fruitName) == "string" and fruitName ~= "" then
			return nil
		end

		if tool:GetAttribute("IsSeed") == true then
			local crop = tool:GetAttribute("SeedCropName")
			local itemName = tool:GetAttribute("ItemName")

			for _, candidate in ipairs({
				tool.Name,
				itemName,
				crop,
				cropKeyFromName(tool.Name),
				cropKeyFromName(itemName),
				}) do
				if candidate ~= nil then
					local template = templateByKey[normalize(candidate)]
						or templateByKey[cropKeyFromName(candidate)]

					if template then
						return template
					end
				end
			end
		end

		for _, candidate in ipairs({
			tool.Name,
			tool:GetAttribute("ItemName"),
			tool:GetAttribute("SeedCropName"),
			cropKeyFromName(tool.Name),
			cropKeyFromName(tool:GetAttribute("ItemName")),
			}) do
			if candidate ~= nil then
				local template = templateByKey[normalize(candidate)]
					or templateByKey[cropKeyFromName(candidate)]

				if template then
					return template
				end
			end
		end

		return nil
	end

	--============================================================
	-- CANTIDAD LOGICA DEL TOOL
	--============================================================

	local function getStackAmount(tool)
		if not tool or not tool:IsA("Tool") then
			return 0
		end

		local amount = tonumber(tool:GetAttribute("SeedStackQuantity"))

		if amount == nil then
			amount = tonumber(tool:GetAttribute("Cantidad"))
		end

		if amount == nil then
			-- Semillas viejas: cada Tool equivalía a 1.
			amount = 1
		end

		return math.clamp(math.floor(amount), 1, STACK_LIMIT)
	end

	local function applySeedAttributes(tool, template, amount)
		if not tool or not template then
			return
		end

		-- Respaldo V9.1: jamás modificar una fruta aunque otro caller se equivoque.
		if tool:GetAttribute("IsFruit") == true then
			return
		end

		amount = math.clamp(math.floor(tonumber(amount) or 1), 1, STACK_LIMIT)

		local itemName = template:GetAttribute("ItemName")

		if typeof(itemName) ~= "string" or itemName == "" then
			itemName = template.Name
		end

		local crop = tool:GetAttribute("SeedCropName")

		if typeof(crop) ~= "string" or crop == "" then
			crop = template:GetAttribute("SeedCropName")
		end

		if typeof(crop) ~= "string" or crop == "" then
			crop = cropKeyFromName(itemName)
		end

		tool.Name = template.Name

		tool:SetAttribute("ItemName", itemName)
		tool:SetAttribute("ItemType", "Cultivo")
		tool:SetAttribute("IsSeed", true)

		if crop and crop ~= "" then
			tool:SetAttribute("SeedCropName", crop)
		end

		local display = tool:GetAttribute("BackpackDisplayName")
		local templateDisplay = template:GetAttribute("BackpackDisplayName")

		if (typeof(display) ~= "string" or display == "")
			and typeof(templateDisplay) == "string"
			and templateDisplay ~= ""
		then
			tool:SetAttribute("BackpackDisplayName", templateDisplay)
		end

		tool:SetAttribute("SeedStackQuantity", amount)
		tool:SetAttribute("Cantidad", amount)

		trackedSeedMeta[tool] = {
			templateName = template.Name,
			amount = amount,
		}
	end

	--============================================================
	-- CREAR STACK
	--============================================================

	local function createStack(template, amount, parent)
		amount = math.clamp(math.floor(tonumber(amount) or 1), 1, STACK_LIMIT)

		local clone = template:Clone()

		applySeedAttributes(clone, template, amount)

		clone.Parent = parent

		return clone
	end

	--============================================================
	-- CONTENEDORES DEL JUGADOR
	--============================================================

	local function getPlayerBackpacks(player)
		local result = {}

		for _, child in ipairs(player:GetChildren()) do
			if child:IsA("Backpack") then
				table.insert(result, child)
			end
		end

		return result
	end

	local function getCurrentBackpack(player)
		return player:FindFirstChildOfClass("Backpack")
			or player:WaitForChild("Backpack", 5)
	end

	--============================================================
	-- ESCANEAR INVENTARIO LOGICO
	--============================================================

	local function scanInventory(player)
		local counts = {}

		local function scan(container)
			if not container then
				return
			end

			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					local template = getTemplate(child)

					if template then
						local amount = getStackAmount(child)

						applySeedAttributes(child, template, amount)

						counts[template.Name] =
							(counts[template.Name] or 0)
							+ amount
					end
				end
			end
		end

		for _, backpack in ipairs(getPlayerBackpacks(player)) do
			scan(backpack)
		end

		scan(player.Character)

		return counts
	end

	--============================================================
	-- SANITIZAR DATASTORE
	--============================================================

	local function sanitizeLoadedData(raw)
		local result = {}
		local unavailable = {}

		if typeof(raw) ~= "table" then
			return result, unavailable
		end

		for savedName, amount in pairs(raw) do
			if typeof(savedName) == "string"
				and typeof(amount) == "number"
			then
				local safeAmount =
					math.clamp(
						math.floor(amount),
						0,
						999999
					)

				if safeAmount > 0 then
					local template =
						templateByKey[normalize(savedName)]
						or templateByKey[cropKeyFromName(savedName)]

					if template then
						result[template.Name] =
							(result[template.Name] or 0)
							+ safeAmount
					else
						-- V9.2:
						-- Este Place no tiene el template, pero EL DATO NO SE BORRA.
						-- Así CasaJugadores/Bosque no pueden sobrescribir el
						-- inventario completo del Lobby con un inventario parcial.
						unavailable[savedName] =
							(unavailable[savedName] or 0)
							+ safeAmount
					end
				end
			end
		end

		return result, unavailable
	end

	--============================================================
	-- RECUPERAR VERSION ANTERIOR NO VACIA
	--============================================================

	local function sanitizeLegacyPayload(raw)
		if typeof(raw) ~= "table" then
			return {}
		end

		if typeof(raw.seeds) == "table" then
			return sanitizeLoadedData(raw.seeds)
		end

		return sanitizeLoadedData(raw)
	end

	local function emergencyDeduplicate(counts, targetTotal)
		local total =
			totalCounts(counts)

		if total < targetTotal * 1.70
			or total > targetTotal * 2.30
		then
			return cloneCounts(counts), false
		end

		local result = {}

		-- El bug V6 produjo 2198 a partir de 1105 + 1093.
		-- Ceil(x/2) es una buena reconstrucción de la copia original.
		for name, amount in pairs(counts) do
			result[name] =
				math.max(
					0,
					math.ceil(
						(tonumber(amount) or 0) / 2
					)
				)
		end

		local current =
			totalCounts(result)

		local names = {}

		for name, amount in pairs(result) do
			if amount > 0 then
				table.insert(names, name)
			end
		end

		table.sort(
			names,
			function(a, b)
				return
					(result[a] or 0)
					>
				(result[b] or 0)
			end
		)

		if #names == 0 then
			return result, true
		end

		-- Ajustar solamente si hace falta para llegar al total
		-- confirmado por tus logs: 1105.
		local index = 1

		while current < targetTotal do
			local name =
				names[
			((index - 1) % #names) + 1
			]

			result[name] =
				(result[name] or 0) + 1

			current += 1
			index += 1
		end

		index = 1

		while current > targetTotal do
			local name =
				names[
			((index - 1) % #names) + 1
			]

			if (result[name] or 0) > 0 then
				result[name] -= 1
				current -= 1
			end

			index += 1

			if index > 100000 then
				break
			end
		end

		return result, true
	end

	local function recoverFromV6Stores(key)
		local candidates = {}

		local function addCandidate(
			sourceName,
			counts,
			version
		)
			local total =
				totalCounts(counts)

			if total <= 0 then
				return nil
			end

			local candidate = {
				source = sourceName,
				counts = cloneCounts(counts),
				total = total,
				version = version,
			}

			table.insert(
				candidates,
				candidate
			)

			-- Preferencia absoluta:
			-- el Output confirmó 1105 antes de la duplicación.
			if total == RECOVERY_TARGET_TOTAL then
				return candidate
			end

			return nil
		end

		--========================================================
		-- 1) HISTORIAL DEL DATASTORE REAL DE V6
		-- JulianSeedInventory_v4
		--========================================================

		local okPages, pagesOrError =
			pcall(function()
				return STORE_V4:ListVersionsAsync(
					key,
					Enum.SortDirection.Descending,
					nil,
					nil,
					50
				)
			end)

		if okPages then
			local pages =
				pagesOrError

			local checked = 0

			while checked < RECOVERY_MAX_VERSIONS do
				local currentPage =
					pages:GetCurrentPage()

				for _, versionInfo in ipairs(currentPage) do
					if checked >= RECOVERY_MAX_VERSIONS then
						break
					end

					checked += 1

					if not versionInfo.IsDeleted then
						local okVersion, raw =
							pcall(function()
								return STORE_V4:GetVersionAsync(
									key,
									versionInfo.Version
								)
							end)

						if okVersion then
							local counts =
								sanitizeLegacyPayload(raw)

							local exact =
								addCandidate(
									"JulianSeedInventory_v4 HISTORIAL",
									counts,
									versionInfo.Version
								)

							if exact then
								return
									exact.counts,
									exact
							end
						end
					end
				end

				if pages.IsFinished then
					break
				end

				local okAdvance =
					pcall(function()
						pages:AdvanceToNextPageAsync()
					end)

				if not okAdvance then
					break
				end
			end
		else
			warn(
				"[SeedSaveV9.2] No pude listar historial V4: "
					.. tostring(pagesOrError)
			)
		end

		--========================================================
		-- 2) VALOR ACTUAL DE V4
		--========================================================

		local okV4, rawV4 =
			pcall(function()
				return STORE_V4:GetAsync(key)
			end)

		if okV4 then
			local countsV4 =
				sanitizeLegacyPayload(rawV4)

			local exact =
				addCandidate(
					"JulianSeedInventory_v4 ACTUAL",
					countsV4,
					nil
				)

			if exact then
				return exact.counts, exact
			end
		end

		--========================================================
		-- 3) V3 / V2
		--========================================================

		for _, info in ipairs({
			{
				name = "JulianSeedInventory_v3",
				store = STORE_V3,
			},
			{
				name = "JulianSeedInventory_v2",
				store = STORE_V2,
			},
			}) do
			local okLegacy, rawLegacy =
				pcall(function()
					return info.store:GetAsync(key)
				end)

			if okLegacy then
				local counts =
					sanitizeLegacyPayload(rawLegacy)

				local exact =
					addCandidate(
						info.name,
						counts,
						nil
					)

				if exact then
					return exact.counts, exact
				end
			end
		end

		--========================================================
		-- 4) V1
		--========================================================

		local okV1, rawV1 =
			pcall(function()
				return STORE_V1:GetAsync(key)
			end)

		if okV1 then
			local counts =
				sanitizeLegacyPayload(rawV1)

			local exact =
				addCandidate(
					"SeedInventory_v1",
					counts,
					nil
				)

			if exact then
				return exact.counts, exact
			end
		end

		if #candidates == 0 then
			return nil, nil
		end

		-- Elegir el candidato más cercano a 1105.
		table.sort(
			candidates,
			function(a, b)
				local da =
					math.abs(
						a.total
						- RECOVERY_TARGET_TOTAL
					)

				local db =
					math.abs(
						b.total
						- RECOVERY_TARGET_TOTAL
					)

				return da < db
			end
		)

		local best =
			candidates[1]

		-- Si lo único que queda es el inventario duplicado de 2198,
		-- reconstruirlo de forma controlada a 1105.
		local deduped, usedDedup =
			emergencyDeduplicate(
				best.counts,
				RECOVERY_TARGET_TOTAL
			)

		if usedDedup then
			return
				deduped,
				{
					source =
					best.source
					.. " + DEDUPLICACION 2198->1105",
					total =
					totalCounts(deduped),
					version =
					best.version,
					deduplicated = true,
				}
		end

		return best.counts, best
	end

	--============================================================
	-- DESTRUIR INTERNAMENTE SIN CONTARLO COMO CONSUMO
	--============================================================

	local function destroyInternal(tool)
		if not tool then
			return
		end

		internalDestroy[tool] = true

		pcall(function()
			tool:Destroy()
		end)

		task.delay(1, function()
			internalDestroy[tool] = nil
		end)
	end

	--============================================================
	-- COMPACTAR BACKPACK
	--
	-- Ejemplo:
	-- 99 Tools de Mango x1 -> 1 Tool Mango con Cantidad=99
	-- 150 -> 2 Tools: 99 + 51
	--============================================================

	local function compactBackpack(player, backpack)
		if not backpack or not backpack.Parent then
			return
		end

		local state = playerState[player]

		if not state or not state.loaded or state.compacting then
			return
		end

		state.compacting = true

		local groups = {}

		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				local template = getTemplate(child)

				if template then
					local group = groups[template.Name]

					if not group then
						group = {
							template = template,
							tools = {},
							total = 0,
						}

						groups[template.Name] = group
					end

					local amount = getStackAmount(child)

					table.insert(group.tools, child)
					group.total += amount
				end
			end
		end

		for _, group in pairs(groups) do
			local total = group.total
			local neededTools = math.ceil(total / STACK_LIMIT)

			-- Reutilizar Tools existentes primero.
			for index = 1, neededTools do
				local amount =
					math.min(
						STACK_LIMIT,
						total - ((index - 1) * STACK_LIMIT)
					)

				local tool = group.tools[index]

				if tool and tool.Parent == backpack then
					applySeedAttributes(
						tool,
						group.template,
						amount
					)
				else
					createStack(
						group.template,
						amount,
						backpack
					)
				end
			end

			-- Destruir sobrantes.
			for index = neededTools + 1, #group.tools do
				local tool = group.tools[index]

				if tool and tool.Parent == backpack then
					destroyInternal(tool)
				end
			end
		end

		state.compacting = false
	end

	--============================================================
	-- ASEGURAR CONTEOS SIN DUPLICAR
	--
	-- Se usa si Roblox crea/reemplaza Backpack.
	-- SOLO crea la diferencia faltante.
	--============================================================

	local function ensureLogicalCounts(player, desiredCounts)
		local backpack = getCurrentBackpack(player)

		if not backpack then
			return
		end

		local actual = scanInventory(player)

		for templateName, desiredAmount in pairs(desiredCounts or {}) do
			local template =
				templateByKey[normalize(templateName)]

			local currentAmount =
				actual[templateName]
				or 0

			local missing =
				math.max(
					0,
					math.floor(desiredAmount)
					- currentAmount
				)

			if template and missing > 0 then
				while missing > 0 do
					local amount =
						math.min(
							STACK_LIMIT,
							missing
						)

					createStack(
						template,
						amount,
						backpack
					)

					missing -= amount
				end
			end
		end

		compactBackpack(player, backpack)
	end

	--============================================================
	-- RESTORE INICIAL
	--============================================================

	local function clearSeedTools(player)
		local function clear(container)
			if not container then
				return
			end

			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and getTemplate(child) then
					destroyInternal(child)
				end
			end
		end

		for _, backpack in ipairs(getPlayerBackpacks(player)) do
			clear(backpack)
		end

		clear(player.Character)
	end

	local function restoreFromCounts(player, counts)
		local backpack = getCurrentBackpack(player)

		if not backpack then
			return 0
		end

		local createdTools = 0

		for templateName, amount in pairs(counts) do
			local template =
				templateByKey[normalize(templateName)]

			if template then
				local remaining =
					math.max(
						0,
						math.floor(amount)
					)

				while remaining > 0 do
					local stack =
						math.min(
							STACK_LIMIT,
							remaining
						)

					createStack(
						template,
						stack,
						backpack
					)

					createdTools += 1
					remaining -= stack
				end
			end
		end

		return createdTools
	end

	--============================================================
	-- DATASTORE
	--============================================================

	local function mergeUnavailableSeedCounts(player, counts)
		local snapshot = cloneCounts(counts)
		local state = playerState[player]

		if not state then
			return snapshot
		end

		for savedName, amount in pairs(
			state.unavailableCounts or {}
			) do
			-- Si este Place todavía NO tiene ese template, conservar el dato
			-- exactamente como llegó del DataStore.
			local template =
				templateByKey[normalize(savedName)]
				or templateByKey[cropKeyFromName(savedName)]

			if not template then
				snapshot[savedName] =
					(snapshot[savedName] or 0)
					+ math.max(
						0,
						math.floor(
							tonumber(amount) or 0
						)
					)
			end
		end

		return snapshot
	end

	local function writeCounts(player, counts)
		local key =
			"Player_" .. player.UserId

		local snapshot =
			mergeUnavailableSeedCounts(
				player,
				counts
			)

		local logicalTotal =
			totalCounts(snapshot)

		local state =
			playerState[player]

		-- Si la carga actual quedó vacía y la recuperación falló,
		-- NO permitimos sobrescribir más historial con otro 0.
		if logicalTotal <= 0
			and state
			and state.recoveryLocked
		then
			warn(
				"[SeedSaveV9.2] GUARDADO 0 BLOQUEADO por seguridad | "
					.. player.Name
			)

			return false
		end

		local lastError

		for attempt = 1, SAVE_RETRIES do
			local ok, err =
				pcall(function()
					STORE:UpdateAsync(
						key,
						function()
							return cloneCounts(snapshot)
						end
					)
				end)

			if ok then
				return true
			end

			lastError = err
			task.wait(0.5 * attempt)
		end

		warn(
			"[SeedSaveV9.2] ERROR GUARDANDO "
				.. player.Name
				.. ": "
				.. tostring(lastError)
		)

		return false
	end

	local function saveNow(player, useLiveScan)
		local state = playerState[player]

		if not state or not state.loaded then
			return false
		end

		local counts

		if useLiveScan ~= false and player.Parent == Players then
			counts = scanInventory(player)
			state.lastCounts = cloneCounts(counts)
		else
			counts = cloneCounts(state.lastCounts)
		end

		local ok =
			writeCounts(
				player,
				counts
			)

		if ok then
			state.dirty = false
		end

		return ok
	end

	local function queueSave(player)
		local state = playerState[player]

		if not state
			or not state.loaded
			or state.shuttingDown
		then
			return
		end

		state.dirty = true
		state.saveToken += 1

		local token = state.saveToken

		task.delay(SAVE_DELAY, function()
			local current =
				playerState[player]

			if not current
				or not current.loaded
				or current.shuttingDown
				or current.saveToken ~= token
				or player.Parent ~= Players
			then
				return
			end

			current.lastCounts =
				scanInventory(player)

			saveNow(player, false)
		end)
	end

	--============================================================
	-- CUANDO UNA SEMILLA ES DESTRUIDA POR GARDENPLANTING
	--
	-- Tu GardenPlanting actual hace:
	--     semilla:Destroy()
	--
	-- Si el Tool representaba x99:
	-- destruimos x1 lógico y recreamos x98.
	--============================================================

	local function handleSeedRemoved(player, container, tool)
		if not tool:IsA("Tool") then
			return
		end

		local meta =
			trackedSeedMeta[tool]

		local template =
			getTemplate(tool)

		if not meta and not template then
			return
		end

		local state =
			playerState[player]

		if not state
			or not state.loaded
			or state.shuttingDown
		then
			return
		end

		-- Backpack retirado/reemplazado:
		-- NO interpretar su destrucción como "plantar".
		if state.retiredContainers[container] then
			return
		end

		if internalDestroy[tool] then
			return
		end

		local templateName =
			meta and meta.templateName
			or (template and template.Name)

		local amount =
			meta and meta.amount
			or getStackAmount(tool)

		task.delay(0.08, function()
			local current =
				playerState[player]

			if not current
				or not current.loaded
				or current.shuttingDown
				or player.Parent ~= Players
			then
				return
			end

			-- Solo se movió Backpack <-> Character.
			if tool.Parent ~= nil then
				return
			end

			-- Si era x1, consumirlo elimina el Tool completo.
			-- Si era xN, devolver N-1.
			if amount > 1 then
				local currentBackpack =
					getCurrentBackpack(player)

				local seedTemplate =
					templateByKey[normalize(templateName)]

				if currentBackpack and seedTemplate then
					createStack(
						seedTemplate,
						amount - 1,
						currentBackpack
					)

					task.delay(
						COMPACT_DELAY,
						function()
							if currentBackpack.Parent then
								compactBackpack(
									player,
									currentBackpack
								)
							end
						end
					)
				end
			end

			-- El total lógico bajó exactamente 1.
			task.delay(0.12, function()
				local latest =
					playerState[player]

				if latest and latest.loaded then
					latest.lastCounts =
						scanInventory(player)

					queueSave(player)
				end
			end)
		end)
	end

	--============================================================
	-- CONECTAR CONTENEDOR
	--============================================================

	local function connectContainer(player, container)
		if not container then
			return
		end

		local state = playerState[player]

		if not state then
			return
		end

		if state.connectedContainers[container] then
			return
		end

		state.connectedContainers[container] = true

		-- Registrar semillas que ya existen.
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local template = getTemplate(child)

				if template then
					applySeedAttributes(
						child,
						template,
						getStackAmount(child)
					)
				end
			end
		end

		container.ChildAdded:Connect(function(child)
			if not child:IsA("Tool") then
				return
			end

			task.defer(function()
				if not child.Parent then
					return
				end

				local template =
					getTemplate(child)

				if not template then
					return
				end

				applySeedAttributes(
					child,
					template,
					getStackAmount(child)
				)

				local current =
					playerState[player]

				if not current
					or not current.loaded
					or current.shuttingDown
				then
					return
				end

				-- Nueva semilla recibida/comprada.
				-- Marcar dirty, pero guardar con debounce.
				current.lastCounts =
					scanInventory(player)

				queueSave(player)

				-- Solo compactamos Backpack, no Character equipado.
				if container:IsA("Backpack") then
					task.delay(
						COMPACT_DELAY,
						function()
							if container.Parent == player then
								compactBackpack(
									player,
									container
								)

								local latest =
									playerState[player]

								if latest and latest.loaded then
									latest.lastCounts =
										scanInventory(player)
								end
							end
						end
					)
				end
			end)
		end)

		container.ChildRemoved:Connect(function(child)
			handleSeedRemoved(
				player,
				container,
				child
			)
		end)
	end

	--============================================================
	-- CARGAR JUGADOR
	--============================================================

	local function loadPlayer(player)
		if playerState[player] then
			return
		end

		local state = {
			loaded = false,
			dirty = false,
			saveToken = 0,
			lastCounts = {},
			unavailableCounts = {},
			compacting = false,
			shuttingDown = false,
			recoveryLocked = false,
			recoveredFromVersion = false,

			connectedContainers = setmetatable({}, {__mode = "k"}),
			retiredContainers = setmetatable({}, {__mode = "k"}),
		}

		playerState[player] = state

		local backpack =
			player:WaitForChild("Backpack")

		connectContainer(
			player,
			backpack
		)

		local key =
			"Player_" .. player.UserId

		local loadedData = {}
		local unavailableCounts = {}

		local ok, result =
			pcall(function()
				return STORE:GetAsync(key)
			end)

		if ok then
			loadedData,
				unavailableCounts =
				sanitizeLoadedData(result)

			state.unavailableCounts =
				cloneCounts(
					unavailableCounts
				)

			if totalCounts(
				state.unavailableCounts
				) > 0 then
				warn(
					"[SeedSaveV9.2] Este Place no tiene todos los templates de semillas | "
						.. player.Name
						.. " | semillas preservadas pero no visibles: "
						.. tostring(
							totalCounts(
								state.unavailableCounts
							)
						)
				)
			end
		else
			warn(
				"[SeedSaveV9.2] ERROR CARGANDO "
					.. player.Name
					.. ": "
					.. tostring(result)
			)
		end

		--========================================================
		-- RECUPERACION AUTOMATICA
		--
		-- El Output anterior mostró que V7 leyó 0.
		-- Si el valor actual está vacío, NO lo damos por perdido:
		-- buscamos las versiones previas de la misma key.
		--========================================================

		if (
			totalCounts(loadedData)
				+ totalCounts(
					state.unavailableCounts
				)
			) <= 0 then
			warn(
				"[SeedSaveV9.2] Inventario Stack vacío. Buscando datos reales de V6..."
			)

			local recovered, recoveryInfo =
				recoverFromV6Stores(key)

			if recovered
				and totalCounts(recovered) > 0
			then
				loadedData =
					cloneCounts(recovered)

				state.unavailableCounts = {}

				state.recoveredFromVersion =
					true

				state.recoveryLocked =
					false

				-- Restaurar también la key principal para que el próximo
				-- inicio ya cargue normalmente.
				local repairOk, repairError =
					pcall(function()
						STORE:SetAsync(
							key,
							cloneCounts(
								loadedData
							)
						)
					end)

				if repairOk then
				else
					warn(
						"[SeedSaveV9.2] Recuperé las semillas pero no pude crear el Stack store todavía: "
							.. tostring(repairError)
					)
				end
			else
				state.recoveryLocked =
					true

				warn(
					"[SeedSaveV9.2] NO encontré datos en V4/V3/V2/V1. "
						.. "Por seguridad NO guardaré otro 0."
				)
			end
		end

		--========================================================
		-- MIGRACION A STACKS
		--========================================================

		local createdStacks = 0

		if totalCounts(loadedData) > 0 then
			clearSeedTools(player)

			createdStacks =
				restoreFromCounts(
					player,
					loadedData
				)
		end

		state.lastCounts =
			cloneCounts(loadedData)

		state.loaded = true

		player:SetAttribute(
			"SeedInventoryLoaded",
			true
		)

		player:SetAttribute(
			"SeedInventoryStackVersion",
			92
		)

		if player.Character then
			connectContainer(
				player,
				player.Character
			)
		end

		--========================================================
		-- CHARACTER
		--========================================================

		player.CharacterAdded:Connect(function(character)
			connectContainer(
				player,
				character
			)
		end)

		player.CharacterRemoving:Connect(function(character)
			local current =
				playerState[player]

			if not current
				or not current.loaded
				or current.shuttingDown
			then
				return
			end

			local currentBackpack =
				getCurrentBackpack(player)

			if currentBackpack then
				-- Regresar cualquier stack equipado.
				for _, child in ipairs(character:GetChildren()) do
					if child:IsA("Tool")
						and getTemplate(child)
					then
						child.Parent =
							currentBackpack
					end
				end
			end

			current.lastCounts =
				scanInventory(player)

			queueSave(player)
		end)

		--========================================================
		-- BACKPACK REEMPLAZADO
		--
		-- V6 duplicaba aquí.
		-- V7 compara contra lastCounts y SOLO repone faltantes.
		--========================================================

		player.ChildAdded:Connect(function(child)
			if not child:IsA("Backpack") then
				return
			end

			local current =
				playerState[player]

			if not current then
				return
			end

			current.retiredContainers[child] =
				nil

			connectContainer(
				player,
				child
			)

			task.delay(0.60, function()
				local latest =
					playerState[player]

				if not latest
					or not latest.loaded
					or latest.shuttingDown
					or child.Parent ~= player
				then
					return
				end

				ensureLogicalCounts(
					player,
					latest.lastCounts
				)

				latest.lastCounts =
					scanInventory(player)
			end)
		end)

		player.ChildRemoved:Connect(function(child)
			if not child:IsA("Backpack") then
				return
			end

			local current =
				playerState[player]

			if not current then
				return
			end

			current.retiredContainers[child] =
				true

			if current.loaded
				and not current.shuttingDown
			then
				task.delay(0.75, function()
					local latest =
						playerState[player]

					if not latest
						or not latest.loaded
						or latest.shuttingDown
						or player.Parent ~= Players
					then
						return
					end

					ensureLogicalCounts(
						player,
						latest.lastCounts
					)
				end)
			end
		end)
	end

	--============================================================
	-- FORCE SAVE PARA JULIAN
	--============================================================

	local oldForce =
		ServerScriptService:FindFirstChild(
			"ForceSeedInventorySave"
		)

	if oldForce then
		oldForce:Destroy()
	end

	local forceSave =
		Instance.new("BindableFunction")

	forceSave.Name =
		"ForceSeedInventorySave"

	forceSave.Parent =
		ServerScriptService

	forceSave.OnInvoke = function(player)
		if not player
			or player.Parent ~= Players
		then
			return false, "Jugador inválido."
		end

		local state =
			playerState[player]

		if not state
			or not state.loaded
		then
			return false, "El inventario de semillas todavía está cargando."
		end

		-- IMPORTANTE:
		-- Julian puede haber creado 99 Tools hace milisegundos.
		-- scanInventory suma cada x1 correctamente incluso ANTES de compactar.
		state.lastCounts =
			scanInventory(player)

		if totalCounts(state.lastCounts) > 0 then
			state.recoveryLocked = false
		end

		local ok =
			saveNow(
				player,
				false
			)

		if ok then
			-- Después del guardado ya podemos compactar.
			local backpack =
				getCurrentBackpack(player)

			if backpack then
				task.delay(
					COMPACT_DELAY,
					function()
						if backpack.Parent == player then
							compactBackpack(
								player,
								backpack
							)
						end
					end
				)
			end

			return true, "Guardado confirmado V7."
		end

		return false, "DataStore no confirmó el guardado."
	end

	--============================================================
	-- AUTOSAVE
	--============================================================

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)

			for player, state in pairs(playerState) do
				if player.Parent == Players
					and state.loaded
					and state.dirty
					and not state.shuttingDown
				then
					state.lastCounts =
						scanInventory(player)

					saveNow(
						player,
						false
					)
				end
			end
		end
	end)

	--============================================================
	-- PLAYERS
	--============================================================

	Players.PlayerAdded:Connect(loadPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(
			loadPlayer,
			player
		)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state =
			playerState[player]

		if state and state.loaded then
			-- Primero congelamos callbacks.
			state.shuttingDown = true

			-- Capturar snapshot final.
			state.lastCounts =
				scanInventory(player)

			saveNow(
				player,
				false
			)
		end

		playerState[player] = nil
	end)

	--============================================================
	-- CIERRE
	--============================================================

	game:BindToClose(function()
		local pending = 0

		for player, state in pairs(playerState) do
			if state.loaded then
				state.shuttingDown = true
				state.lastCounts =
					scanInventory(player)

				pending += 1

				task.spawn(function()
					saveNow(
						player,
						false
					)

					pending -= 1
				end)
			end
		end

		local started = os.clock()

		while pending > 0
			and os.clock() - started < 7
		do
			task.wait(0.05)
		end
	end)
end

return SeedInventoryService
