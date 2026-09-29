--============================================================
-- FruitInventoryService - ORGANIZADO
-- Tipo: ModuleScript
--
-- Este modulo conserva la logica del script original.
-- Se inicia desde un bootstrap pequeno en ServerScriptService.
--============================================================

local FruitInventoryService = {}
local started = false

function FruitInventoryService.Start()
	if started then
		return
	end
	started = true

	--==============================================================
	-- FRUIT INVENTORY SERVICE V4.4
	-- STACKS REALES x99 + SHARED PLACES SAFE + RECOVERY HISTORIAL
	--
	-- UBICACION:
	--   ServerScriptService > FruitInventorySaveServer
	--
	-- TIPO:
	--   Script
	--
	-- USA EL MISMO DATASTORE:
	--   FruitInventory_v1
	--
	-- CAMBIO PRINCIPAL:
	--   Antes:
	--       297 frutas = 297 Tools
	--
	--   Ahora:
	--       297 Mango = 3 Tools:
	--           Mango x99
	--           Mango x99
	--           Mango x99
	--
	-- ATRIBUTOS DEL STACK:
	--   IsFruit = true
	--   FruitName = "Mango"
	--   ItemName = "Mango"
	--   FruitStackQuantity = 99
	--   Cantidad = 99
	--
	-- COMPATIBILIDAD:
	-- - Si otro sistema agrega una fruta Tool x1, se compacta.
	-- - Si otro sistema destruye un stack x99 para consumir UNA fruta,
	--   este script devuelve automáticamente x98.
	-- - Admin usa AddFruitInventory sin crear 99 Tools.
	-- - Si AvatarEditor reemplaza Backpack, se restauran los stacks.
	--==============================================================

	local Players = game:GetService("Players")
	local ServerStorage = game:GetService("ServerStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local DataStoreService = game:GetService("DataStoreService")

	--==============================================================
	-- CONFIG
	--==============================================================

	local STORE_NAME = "FruitInventory_v1"
	local STORE = DataStoreService:GetDataStore(STORE_NAME)

	-- V4.2:
	-- Marca que YA hicimos la recuperación histórica para ese jugador.
	-- Esto evita que, si algún día el jugador realmente se queda en 0 frutas,
	-- el sistema vuelva a revivir inventarios viejos.
	local RECOVERY_MARK_STORE =
		DataStoreService:GetDataStore(
			"FruitInventoryRecoveryV1"
		)

	local RECOVERY_MAX_VERSIONS = 50

	local STACK_LIMIT = 99
	local MAX_TOTAL_PER_FRUIT = 9999

	local SAVE_DELAY = 3
	local AUTOSAVE_SECONDS = 120
	local SAVE_RETRIES = 3
	local COMPACT_DELAY = 0.20

	--==============================================================
	-- CARPETAS
	--==============================================================

	local itemFolder = ServerStorage:WaitForChild("Item")
	local fruitFolder = itemFolder:WaitForChild("Frutas")

	--==============================================================
	-- ESTADO
	--==============================================================

	local playerState = {}
	local trackedFruitMeta = setmetatable({}, {__mode = "k"})
	local internalDestroy = setmetatable({}, {__mode = "k"})

	--==============================================================
	-- UTILIDADES
	--==============================================================

	local function trim(value)
		return tostring(value or "")
			:gsub("^%s+", "")
			:gsub("%s+$", "")
	end

	local function normalize(value)
		local text = trim(value):lower()

		text = text:gsub("á", "a")
		text = text:gsub("é", "e")
		text = text:gsub("í", "i")
		text = text:gsub("ó", "o")
		text = text:gsub("ú", "u")
		text = text:gsub("ü", "u")
		text = text:gsub("ñ", "n")
		text = text:gsub("[%s_%-]+", "")

		return text
	end

	local function cloneCounts(source)
		local result = {}

		for name, amount in pairs(source or {}) do
			local safeAmount =
				math.clamp(
					math.floor(
						tonumber(amount) or 0
					),
					0,
					MAX_TOTAL_PER_FRUIT
				)

			if safeAmount > 0 then
				result[name] = safeAmount
			end
		end

		return result
	end

	local function totalCounts(counts)
		local total = 0

		for _, amount in pairs(counts or {}) do
			total += math.max(
				0,
				math.floor(
					tonumber(amount) or 0
				)
			)
		end

		return total
	end

	--==============================================================
	-- TEMPLATES
	--==============================================================

	local templateByKey = {}

	local function canonicalNameFromTemplate(template)
		if not template then
			return nil
		end

		local name = trim(template.Name)

		if name == "" then
			name = trim(
				template:GetAttribute("FruitName")
			)
		end

		if name == "" then
			name = trim(
				template:GetAttribute("ItemName")
			)
		end

		return name
	end

	local function addTemplateAlias(value, template)
		local key = normalize(value)

		if key ~= "" then
			templateByKey[key] = template
		end
	end

	local function rebuildTemplateIndex()
		table.clear(templateByKey)

		for _, template in ipairs(
			fruitFolder:GetChildren()
			) do
			if template:IsA("Tool") then
				local canonical =
					canonicalNameFromTemplate(
						template
					)

				addTemplateAlias(
					template.Name,
					template
				)

				addTemplateAlias(
					template:GetAttribute(
						"FruitName"
					),
					template
				)

				addTemplateAlias(
					template:GetAttribute(
						"ItemName"
					),
					template
				)

				addTemplateAlias(
					template:GetAttribute(
						"BackpackDisplayName"
					),
					template
				)

				addTemplateAlias(
					canonical,
					template
				)

				-- V4.1: aliases de DataStore antiguo.
				if canonical and canonical ~= "" then
					addTemplateAlias(
						"Semilla" .. canonical,
						template
					)

					addTemplateAlias(
						"Semilla " .. canonical,
						template
					)

					addTemplateAlias(
						"Brote" .. canonical,
						template
					)

					addTemplateAlias(
						"Esporas" .. canonical,
						template
					)
				end

				if normalize(canonical) == "platano" then
					addTemplateAlias(
						"BrotePlatanero",
						template
					)
				end
			end
		end
	end

	rebuildTemplateIndex()

	fruitFolder.ChildAdded:Connect(function()
		task.defer(rebuildTemplateIndex)
	end)

	fruitFolder.ChildRemoved:Connect(function()
		task.defer(rebuildTemplateIndex)
	end)

	local function getLegacyFruitKeys(value)
		local clean = normalize(value)
		local keys = {}

		local function add(key)
			if key ~= "" and not table.find(keys, key) then
				table.insert(keys, key)
			end
		end

		add(clean)

		-- Versiones antiguas guardaron frutas con nombres de semilla:
		-- SemillaMango, Semilla Mango, BrotePlatanero, EsporasTrufaBlanca, etc.
		local stripped = clean

		if stripped:sub(1, 7) == "semilla" then
			stripped = stripped:sub(8)
		elseif stripped:sub(1, 5) == "brote" then
			stripped = stripped:sub(6)
		elseif stripped:sub(1, 7) == "esporas" then
			stripped = stripped:sub(8)
		end

		add(stripped)

		-- Alias histórico usado por las semillas de plátano.
		if stripped == "platanero" then
			add("platano")
		end

		-- Algunos datos viejos pudieron guardar "frutaMango".
		if stripped:sub(1, 5) == "fruta" then
			add(stripped:sub(6))
		end

		return keys
	end

	local function findTemplate(value)
		for _, key in ipairs(getLegacyFruitKeys(value)) do
			local template = templateByKey[key]

			if template then
				return template
			end
		end

		return nil
	end

	--==============================================================
	-- TOOL FRUTA / STACK
	--==============================================================

	local function looksLikeSeedName(value)
		local clean = normalize(value)

		return
			clean:sub(1, 7) == "semilla"
			or clean:sub(1, 5) == "brote"
			or clean:sub(1, 7) == "esporas"
	end

	local function getFruitTemplate(tool)
		if not tool or not tool:IsA("Tool") then
			return nil
		end

		-- Semillas jamás entran aquí.
		if tool:GetAttribute("IsSeed") == true then
			return nil
		end

		if tool:GetAttribute(
			"SeedStackQuantity"
			) ~= nil then
			return nil
		end

		if looksLikeSeedName(tool.Name)
			or looksLikeSeedName(
				tool:GetAttribute("ItemName")
			)
		then
			return nil
		end

		local candidates = {
			tool:GetAttribute("FruitName"),
			tool:GetAttribute("ItemName"),
			tool.Name,
		}

		for _, candidate in ipairs(candidates) do
			if candidate ~= nil then
				local template =
					findTemplate(candidate)

				if template then
					if tool:GetAttribute("IsFruit") == true
						or tool:GetAttribute("FruitName") ~= nil
						or tool:GetAttribute("ItemType") == "Fruta"
						or tool:GetAttribute("ItemType") == "Fruit"
						or tool:GetAttribute("ItemType") == "Cultivo"
						or tool:GetAttribute("ItemType") == "Crop"
					then
						return template
					end
				end
			end
		end

		-- Compatibilidad con frutas viejas:
		-- si coincide con Frutas y NO parece semilla.
		for _, candidate in ipairs(candidates) do
			if candidate ~= nil then
				local template =
					findTemplate(candidate)

				if template then
					return template
				end
			end
		end

		return nil
	end

	local function isFruitTool(tool)
		return getFruitTemplate(tool) ~= nil
	end

	local function getStackAmount(tool)
		if not tool or not tool:IsA("Tool") then
			return 0
		end

		local amount =
			tonumber(
				tool:GetAttribute(
					"FruitStackQuantity"
				)
			)

		if amount == nil then
			amount =
				tonumber(
					tool:GetAttribute(
						"Cantidad"
					)
				)
		end

		if amount == nil then
			amount = 1
		end

		return
			math.clamp(
				math.floor(amount),
				1,
				STACK_LIMIT
			)
	end

	local function applyFruitAttributes(
		tool,
		template,
		amount
	)
		if not tool or not template then
			return
		end

		amount =
			math.clamp(
				math.floor(
					tonumber(amount) or 1
				),
				1,
				STACK_LIMIT
			)

		local canonical =
			canonicalNameFromTemplate(
				template
			)

		tool.Name = canonical

		tool:SetAttribute(
			"ItemName",
			canonical
		)

		tool:SetAttribute(
			"FruitName",
			canonical
		)

		tool:SetAttribute(
			"ItemType",
			"Cultivo"
		)

		tool:SetAttribute(
			"IsFruit",
			true
		)

		tool:SetAttribute(
			"IsSeed",
			nil
		)

		tool:SetAttribute(
			"SeedStackQuantity",
			nil
		)

		tool:SetAttribute(
			"FruitStackQuantity",
			amount
		)

		-- Compatibilidad con sistemas que ya leen Cantidad.
		tool:SetAttribute(
			"Cantidad",
			amount
		)

		trackedFruitMeta[tool] = {
			templateName =
				template.Name,
			amount = amount,
		}
	end

	local function createStack(
		template,
		amount,
		parent
	)
		amount =
			math.clamp(
				math.floor(
					tonumber(amount) or 1
				),
				1,
				STACK_LIMIT
			)

		local clone =
			template:Clone()

		applyFruitAttributes(
			clone,
			template,
			amount
		)

		clone.Parent = parent

		return clone
	end

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

	--==============================================================
	-- BACKPACK ACTUAL
	--==============================================================

	local function getCurrentBackpack(player)
		local state =
			playerState[player]

		if state then
			local current =
				state.activeBackpack

			if current
				and current:IsA("Backpack")
				and current.Parent == player
				and not state.retiredContainers[
				current
				]
			then
				return current
			end
		end

		for _, child in ipairs(
			player:GetChildren()
			) do
			if child:IsA("Backpack") then
				if not state
					or not state.retiredContainers[
					child
					]
				then
					if state then
						state.activeBackpack =
							child
					end

					return child
				end
			end
		end

		return nil
	end

	--==============================================================
	-- ESCANEO LOGICO
	--==============================================================

	local function scanInventory(player)
		local counts = {}
		local seen = {}

		local function scan(container)
			if not container then
				return
			end

			local state =
				playerState[player]

			if state
				and state.retiredContainers[
				container
				]
			then
				return
			end

			for _, tool in ipairs(
				container:GetChildren()
				) do
				if tool:IsA("Tool")
					and not seen[tool]
				then
					seen[tool] = true

					local template =
						getFruitTemplate(tool)

					if template then
						local canonical =
							canonicalNameFromTemplate(
								template
							)

						local amount =
							getStackAmount(tool)

						counts[canonical] =
							(counts[canonical] or 0)
							+ amount
					end
				end
			end
		end

		scan(
			getCurrentBackpack(
				player
			)
		)

		scan(player.Character)

		return counts
	end

	--==============================================================
	-- COMPACTAR
	--
	-- 297 Tools x1 -> 3 Tools x99
	-- 125 -> x99 + x26
	--==============================================================

	local function compactBackpack(
		player,
		backpack
	)
		if not backpack
			or backpack.Parent ~= player
		then
			return
		end

		local state =
			playerState[player]

		if not state
			or not state.loaded
			or state.compacting
			or state.shuttingDown
		then
			return
		end

		state.compacting = true
		state.bulkMutating = true

		local groups = {}

		for _, child in ipairs(
			backpack:GetChildren()
			) do
			if child:IsA("Tool") then
				local template =
					getFruitTemplate(child)

				if template then
					local key =
						template.Name

					local group =
						groups[key]

					if not group then
						group = {
							template = template,
							tools = {},
							total = 0,
						}

						groups[key] = group
					end

					table.insert(
						group.tools,
						child
					)

					group.total +=
						getStackAmount(child)
				end
			end
		end

		for _, group in pairs(groups) do
			local total =
				math.max(
					0,
					math.floor(
						group.total
					)
				)

			local neededTools =
				math.ceil(
					total / STACK_LIMIT
				)

			for index = 1, neededTools do
				local amount =
					math.min(
						STACK_LIMIT,
						total
						- (
							(index - 1)
							* STACK_LIMIT
						)
					)

				local tool =
					group.tools[index]

				if tool
					and tool.Parent
					== backpack
				then
					applyFruitAttributes(
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

			for index =
				neededTools + 1,
				#group.tools
			do
				local tool =
					group.tools[index]

				if tool
					and tool.Parent
					== backpack
				then
					destroyInternal(tool)
				end
			end
		end

		state.bulkMutating = false
		state.compacting = false
	end

	--==============================================================
	-- CREAR STACKS DESDE CONTEOS
	--==============================================================

	local function addLogicalAmount(
		player,
		template,
		amount
	)
		local backpack =
			getCurrentBackpack(
				player
			)

		if not backpack then
			return 0
		end

		amount =
			math.max(
				0,
				math.floor(
					tonumber(amount) or 0
				)
			)

		local created = 0

		while amount > 0 do
			local stackAmount =
				math.min(
					STACK_LIMIT,
					amount
				)

			createStack(
				template,
				stackAmount,
				backpack
			)

			created += 1
			amount -= stackAmount
		end

		return created
	end

	local function ensureLogicalCounts(
		player,
		desiredCounts
	)
		local state =
			playerState[player]

		if not state
			or not state.loaded
			or state.shuttingDown
		then
			return
		end

		local backpack =
			getCurrentBackpack(
				player
			)

		if not backpack then
			return
		end

		state.bulkMutating = true

		local actual =
			scanInventory(
				player
			)

		local createdStacks = 0

		for fruitName, desiredAmount
			in pairs(desiredCounts or {})
		do
			local template =
				findTemplate(
					fruitName
				)

			if template then
				local currentAmount =
					math.max(
						0,
						math.floor(
							tonumber(
								actual[
								fruitName
								]
							) or 0
						)
					)

				local missing =
					math.max(
						0,
						math.floor(
							tonumber(
								desiredAmount
							) or 0
						)
						- currentAmount
					)

				if missing > 0 then
					createdStacks +=
						addLogicalAmount(
							player,
							template,
							missing
						)
				end
			end
		end

		state.bulkMutating = false

		compactBackpack(
			player,
			backpack
		)

		if createdStacks > 0 then
			player:SetAttribute(
				"FruitInventoryRevision",
				(tonumber(
					player:GetAttribute(
						"FruitInventoryRevision"
					)
					) or 0) + 1
			)
		end
	end

	--==============================================================
	-- DATASTORE
	--==============================================================

	local function sanitizeLoadedData(raw)
		local result = {}

		local info = {
			rawTotal = 0,
			recognizedTotal = 0,
			migratedEntries = 0,
			unknownPositive = {},
			unknownCounts = {},
		}

		if type(raw) ~= "table" then
			return result, info
		end

		-- Compatibilidad con posibles esquemas:
		-- { Mango = 99 }
		-- { counts = { Mango = 99 } }
		-- { fruits = { Mango = 99 } }
		local source = raw

		if type(raw.counts) == "table" then
			source = raw.counts
		elseif type(raw.fruits) == "table" then
			source = raw.fruits
		end

		for savedName, savedAmount in pairs(source) do
			if typeof(savedName) == "string"
				and typeof(savedAmount) == "number"
			then
				local amount =
					math.clamp(
						math.floor(savedAmount),
						0,
						MAX_TOTAL_PER_FRUIT
					)

				if amount > 0 then
					info.rawTotal += amount

					local template =
						findTemplate(savedName)

					if template then
						local canonical =
							canonicalNameFromTemplate(
								template
							)

						result[canonical] =
							(result[canonical] or 0)
							+ amount

						info.recognizedTotal += amount

						if normalize(savedName)
							~= normalize(canonical)
						then
							info.migratedEntries += 1
						end
					else
						table.insert(
							info.unknownPositive,
							{
								name = savedName,
								amount = amount,
							}
						)

						-- V4.3:
						-- El dato pertenece al inventario compartido aunque este
						-- Place no tenga el template local.
						info.unknownCounts[savedName] =
							(info.unknownCounts[savedName] or 0)
							+ amount
					end
				end
			end
		end

		return result, info
	end


	--==============================================================
	-- V4.2 - RECUPERAR HISTORIAL DEL MISMO DATASTORE
	--
	-- El Output confirmó que FruitInventory_v1 actualmente vale 0.
	-- Pero versiones anteriores de ese MISMO key pueden contener todavía
	-- las frutas que existían antes de que una versión vieja guardara 0.
	--
	-- Estrategia:
	-- 1) Solo si el valor ACTUAL es 0.
	-- 2) Solo si este jugador nunca fue recuperado antes.
	-- 3) Recorre versiones de NUEVA -> VIEJA.
	-- 4) Usa la PRIMERA versión reconocida con frutas > 0.
	--    Esa es la versión más cercana justo antes del borrado.
	--==============================================================

	local function recoveryKey(player)
		return "Recovered_" .. tostring(player.UserId)
	end

	local function wasHistoryRecoveryDone(player)
		local ok, result =
			pcall(function()
				return RECOVERY_MARK_STORE:GetAsync(
					recoveryKey(player)
				)
			end)

		if not ok then
			warn(
				"[FruitSaveV4.4] No pude leer marca recovery | "
					.. player.Name
					.. " | "
					.. tostring(result)
			)

			-- Si falla la marca, permitimos intentar recuperar.
			return false
		end

		return result == true
	end

	local function markHistoryRecoveryDone(player)
		local ok, err =
			pcall(function()
				RECOVERY_MARK_STORE:SetAsync(
					recoveryKey(player),
					true
				)
			end)

		if not ok then
			warn(
				"[FruitSaveV4.4] No pude guardar marca recovery | "
					.. player.Name
					.. " | "
					.. tostring(err)
			)
		end

		return ok
	end

	local function recoverLatestNonZeroVersion(player, key)
		if wasHistoryRecoveryDone(player) then
			return nil, nil
		end

		local okPages, pagesOrError =
			pcall(function()
				return STORE:ListVersionsAsync(
					key,
					Enum.SortDirection.Descending,
					nil,
					nil,
					50
				)
			end)

		if not okPages then
			warn(
				"[FruitSaveV4.4] No pude listar historial | "
					.. player.Name
					.. " | "
					.. tostring(pagesOrError)
			)

			return nil, nil
		end

		local pages = pagesOrError
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
							return STORE:GetVersionAsync(
								key,
								versionInfo.Version
							)
						end)

					if okVersion then
						local candidate, info =
							sanitizeLoadedData(raw)

						local candidateTotal =
							totalCounts(candidate)
						if candidateTotal > 0 then
							return candidate, {
								version =
									versionInfo.Version,
								total =
									candidateTotal,
								rawTotal =
									info.rawTotal,
								migratedEntries =
									info.migratedEntries,
								unknownCounts =
									cloneCounts(
										info.unknownCounts
									),
							}
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

		warn(
			"[FruitSaveV4.4] No encontre una version historica con frutas | "
				.. player.Name
		)

		return nil, nil
	end


	local function mergeUnavailableFruitCounts(player, counts)
		-- V4.4 FIX:
		-- Antes esta funcion se llamaba a si misma infinitamente.
		-- Ahora parte de una copia real de los conteos visibles.
		local snapshot =
			cloneCounts(counts)

		local state =
			playerState[player]

		if not state then
			return snapshot
		end

		for savedName, amount in pairs(
			state.unavailableCounts or {}
			) do
			if not findTemplate(savedName) then
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

	local function writeCounts(
		player,
		counts
	)
		-- V4.4 FIX SHARED PLACES:
		-- Preserva frutas guardadas cuyo template no existe en este Place.
		local snapshot =
			mergeUnavailableFruitCounts(
				player,
				counts
			)

		local key =
			"Player_"
			.. player.UserId

		local lastError

		for attempt = 1, SAVE_RETRIES do
			local ok, err =
				pcall(function()
					STORE:UpdateAsync(
						key,
						function()
							return snapshot
						end
					)
				end)

			if ok then
				return true
			end

			lastError = err

			task.wait(
				0.6 * attempt
			)
		end

		warn(
			"[FruitSaveV4.4] ERROR GUARDANDO | "
				.. player.Name
				.. " | "
				.. tostring(lastError)
		)

		return false
	end

	local function saveNow(
		player,
		useLiveScan
	)
		local state =
			playerState[player]

		if not state
			or not state.loaded
		then
			return false
		end

		local counts

		if useLiveScan ~= false
			and player.Parent == Players
			and not state.shuttingDown
		then
			counts =
				scanInventory(
					player
				)

			state.lastCounts =
				cloneCounts(
					counts
				)
		else
			counts =
				cloneCounts(
					state.lastCounts
				)
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
		local state =
			playerState[player]

		if not state
			or not state.loaded
			or state.shuttingDown
		then
			return
		end

		state.dirty = true
		state.saveToken += 1

		local token =
			state.saveToken

		task.delay(
			SAVE_DELAY,
			function()
				local current =
					playerState[player]

				if not current
					or not current.loaded
					or current.shuttingDown
					or current.saveToken
					~= token
					or player.Parent
					~= Players
				then
					return
				end

				current.lastCounts =
					scanInventory(
						player
					)

				saveNow(
					player,
					false
				)
			end
		)
	end

	--==============================================================
	-- UNA FRUTA ES CONSUMIDA / DESTRUIDA
	--
	-- Si el stack era x99 y un sistema hace tool:Destroy(),
	-- interpretamos que consumió UNA y regresamos x98.
	--==============================================================

	local function handleFruitRemoved(
		player,
		container,
		tool
	)
		if not tool:IsA("Tool") then
			return
		end

		local meta =
			trackedFruitMeta[tool]

		local template =
			getFruitTemplate(tool)

		if not meta
			and not template
		then
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

		if state.retiredContainers[
			container
			] then
			return
		end

		if internalDestroy[tool] then
			return
		end

		local templateName =
			meta and meta.templateName
			or (
				template
				and template.Name
			)

		local amount =
			meta and meta.amount
			or getStackAmount(tool)

		task.delay(
			0.08,
			function()
				local current =
					playerState[player]

				if not current
					or not current.loaded
					or current.shuttingDown
					or player.Parent
					~= Players
				then
					return
				end

				-- Solo se movió Backpack <-> Character.
				if tool.Parent ~= nil then
					return
				end

				if amount > 1 then
					local backpack =
						getCurrentBackpack(
							player
						)

					local fruitTemplate =
						findTemplate(
							templateName
						)

					if backpack
						and fruitTemplate
					then
						createStack(
							fruitTemplate,
							amount - 1,
							backpack
						)

						task.delay(
							COMPACT_DELAY,
							function()
								if backpack.Parent
									== player
								then
									compactBackpack(
										player,
										backpack
									)
								end
							end
						)
					end
				end

				task.delay(
					0.12,
					function()
						local latest =
							playerState[
						player
						]

						if latest
							and latest.loaded
						then
							latest.lastCounts =
								scanInventory(
									player
								)

							player:SetAttribute(
								"FruitInventoryRevision",
								(tonumber(
									player:GetAttribute(
										"FruitInventoryRevision"
									)
									) or 0) + 1
							)

							queueSave(
								player
							)
						end
					end
				)
			end
		)
	end

	--==============================================================
	-- CONECTAR CONTENEDOR
	--==============================================================

	local function connectContainer(
		player,
		container
	)
		if not container then
			return
		end

		local state =
			playerState[player]

		if not state then
			return
		end

		if state.connectedContainers[
			container
			] then
			return
		end

		state.connectedContainers[
		container
		] = true

		if container:IsA("Backpack") then
			container.AncestryChanged:Connect(
				function()
					local current =
						playerState[player]

					if not current then
						return
					end

					if container.Parent
						~= player
					then
						current.retiredContainers[
						container
						] = true

						if current.activeBackpack
							== container
						then
							current.activeBackpack =
								nil
						end
					end
				end
			)
		end

		container.ChildAdded:Connect(
			function(tool)
				if not tool:IsA("Tool") then
					return
				end

				task.defer(function()
					local current =
						playerState[player]

					if not current
						or not current.loaded
						or current.shuttingDown
						or current.bulkMutating
						or current.compacting
						or not tool.Parent
					then
						return
					end

					local template =
						getFruitTemplate(tool)

					if not template then
						return
					end

					applyFruitAttributes(
						tool,
						template,
						getStackAmount(tool)
					)

					task.delay(
						COMPACT_DELAY,
						function()
							local backpack =
								getCurrentBackpack(
									player
								)

							if backpack then
								compactBackpack(
									player,
									backpack
								)
							end

							local latest =
								playerState[
							player
							]

							if latest
								and latest.loaded
							then
								latest.lastCounts =
									scanInventory(
										player
									)

								player:SetAttribute(
									"FruitInventoryRevision",
									(tonumber(
										player:GetAttribute(
											"FruitInventoryRevision"
										)
										) or 0) + 1
								)

								queueSave(
									player
								)
							end
						end
					)
				end)
			end
		)

		container.ChildRemoved:Connect(
			function(tool)
				handleFruitRemoved(
					player,
					container,
					tool
				)
			end
		)
	end

	--==============================================================
	-- LIMPIAR SOLO FRUTAS ACTUALES
	--==============================================================

	local function clearFruitTools(player)
		local function clear(container)
			if not container then
				return
			end

			for _, tool in ipairs(
				container:GetChildren()
				) do
				if tool:IsA("Tool")
					and isFruitTool(tool)
				then
					destroyInternal(tool)
				end
			end
		end

		clear(
			getCurrentBackpack(
				player
			)
		)

		clear(player.Character)
	end

	--==============================================================
	-- RESTAURAR DESDE DATASTORE EN STACKS
	--==============================================================

	local function restoreFromCounts(
		player,
		counts
	)
		local backpack =
			getCurrentBackpack(
				player
			)
			or player:WaitForChild(
				"Backpack",
				10
			)

		if not backpack then
			return 0
		end

		local state =
			playerState[player]

		if state then
			state.activeBackpack =
				backpack
		end

		local createdStacks = 0

		for fruitName, amount
			in pairs(counts)
		do
			local template =
				findTemplate(
					fruitName
				)

			if template then
				local remaining =
					math.max(
						0,
						math.floor(
							tonumber(amount)
							or 0
						)
					)

				while remaining > 0 do
					local stackAmount =
						math.min(
							STACK_LIMIT,
							remaining
						)

					createStack(
						template,
						stackAmount,
						backpack
					)

					createdStacks += 1
					remaining -=
						stackAmount
				end
			end
		end

		return createdStacks
	end

	--==============================================================
	-- CARGAR
	--==============================================================

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
			shuttingDown = false,
			bulkMutating = false,
			compacting = false,
			activeBackpack = nil,

			connectedContainers =
				setmetatable(
					{},
					{__mode = "k"}
				),

			retiredContainers =
				setmetatable(
					{},
					{__mode = "k"}
				),
		}

		playerState[player] = state

		local backpack =
			player:WaitForChild(
				"Backpack"
			)

		state.activeBackpack =
			backpack

		connectContainer(
			player,
			backpack
		)

		local key =
			"Player_"
			.. player.UserId

		local loadedData = {}
		local loadInfo = {
			rawTotal = 0,
			recognizedTotal = 0,
			migratedEntries = 0,
			unknownPositive = {},
			unknownCounts = {},
		}

		local ok, result =
			pcall(function()
				return STORE:GetAsync(
					key
				)
			end)

		if ok then
			loadedData,
				loadInfo =
				sanitizeLoadedData(
					result
				)

			state.unavailableCounts =
				cloneCounts(
					loadInfo.unknownCounts
				)

			if totalCounts(
				state.unavailableCounts
				) > 0 then
				warn(
					"[FruitSaveV4.4] Este Place no tiene todos los templates de frutas | "
						.. player.Name
						.. " | frutas preservadas pero no visibles: "
						.. tostring(
							totalCounts(
								state.unavailableCounts
							)
						)
				)
			end

			if #loadInfo.unknownPositive > 0 then
				for _, entry in ipairs(loadInfo.unknownPositive) do
					warn(
						"[FruitSaveV4.4] DATO LEGACY NO RECONOCIDO | "
							.. tostring(entry.name)
							.. " x"
							.. tostring(entry.amount)
					)
				end
			end
		else
			warn(
				"[FruitSaveV4.4] ERROR CARGANDO | "
					.. player.Name
					.. " | "
					.. tostring(result)
			)
		end

		--========================================================
		-- V4.2:
		-- El valor actual ya está en 0. Intentar recuperar la
		-- versión inmediatamente anterior que todavía tenía frutas.
		--========================================================
		local recoveredFromHistory = false
		local recoveredHistoryInfo = nil

		if ok
			and totalCounts(loadedData) <= 0
			and loadInfo.rawTotal <= 0
		then
			local historicalCounts,
				historicalInfo =
				recoverLatestNonZeroVersion(
					player,
					key
				)

			if historicalCounts
				and totalCounts(
					historicalCounts
				) > 0
			then
				loadedData =
					cloneCounts(
						historicalCounts
					)

				recoveredFromHistory = true
				recoveredHistoryInfo =
					historicalInfo

				state.unavailableCounts =
					cloneCounts(
						historicalInfo
						and historicalInfo.unknownCounts
						or {}
					)
			end
		end

		-- V4.2:
		-- Si el DataStore vino vacío pero ya existen frutas reales en Backpack
		-- por una migración/otro sistema, no las destruimos.
		local liveBeforeRestore =
			scanInventory(player)

		if totalCounts(loadedData) <= 0
			and totalCounts(liveBeforeRestore) > 0
		then
			loadedData =
				cloneCounts(
					liveBeforeRestore
				)

			warn(
				"[FruitSaveV4.4] RECUPERACION DESDE BACKPACK | "
					.. player.Name
					.. " | frutas="
					.. tostring(
						totalCounts(
							loadedData
						)
					)
			)
		end

		state.bulkMutating = true

		clearFruitTools(player)

		local createdStacks =
			restoreFromCounts(
				player,
				loadedData
			)

		state.bulkMutating = false

		state.lastCounts =
			cloneCounts(
				loadedData
			)

		state.loaded = true

		-- V4.2:
		-- Una recuperación histórica se escribe INMEDIATAMENTE al valor actual.
		-- Solo después de confirmar ese guardado marcamos la recuperación como hecha.
		if recoveredFromHistory then
			state.lastCounts =
				cloneCounts(
					loadedData
				)

			local recoveredSaved =
				writeCounts(
					player,
					state.lastCounts
				)

			if recoveredSaved then
				markHistoryRecoveryDone(
					player
				)
			else
				warn(
					"[FruitSaveV4.4] Recovery cargado pero NO pude guardarlo; "
						.. "se volvera a intentar en el siguiente ingreso."
				)
			end
		end

		-- Si recuperamos nombres antiguos, guardamos luego en formato canónico.
		if not recoveredFromHistory
			and (
				loadInfo.migratedEntries > 0
					or (
						loadInfo.rawTotal <= 0
						and totalCounts(loadedData) > 0
					)
			)
		then
			queueSave(player)
		end

		player:SetAttribute(
			"FruitInventoryLoaded",
			true
		)

		player:SetAttribute(
			"FruitInventoryRevision",
			(tonumber(
				player:GetAttribute(
					"FruitInventoryRevision"
				)
				) or 0) + 1
		)

		if player.Character then
			connectContainer(
				player,
				player.Character
			)
		end

		-- Backpack nuevo por AvatarEditor / respawn.
		player.ChildAdded:Connect(
			function(child)
				if not child:IsA("Backpack") then
					return
				end

				local current =
					playerState[player]

				if not current then
					return
				end

				current.activeBackpack =
					child

				current.retiredContainers[
				child
				] = nil

				connectContainer(
					player,
					child
				)

				task.delay(
					0.18,
					function()
						local latest =
							playerState[
						player
						]

						if not latest
							or not latest.loaded
							or latest.shuttingDown
							or child.Parent
							~= player
						then
							return
						end

						ensureLogicalCounts(
							player,
							latest.lastCounts
						)

						compactBackpack(
							player,
							child
						)
					end
				)
			end
		)

		player.ChildRemoved:Connect(
			function(child)
				if not child:IsA("Backpack") then
					return
				end

				local current =
					playerState[player]

				if not current then
					return
				end

				current.retiredContainers[
				child
				] = true

				if current.activeBackpack
					== child
				then
					current.activeBackpack =
						nil
				end
			end
		)

		player.CharacterAdded:Connect(
			function(character)
				connectContainer(
					player,
					character
				)
			end
		)

		player.CharacterRemoving:Connect(
			function(character)
				local current =
					playerState[player]

				if not current
					or not current.loaded
					or current.shuttingDown
				then
					return
				end

				local currentBackpack =
					getCurrentBackpack(
						player
					)

				if currentBackpack then
					current.bulkMutating =
						true

					for _, tool in ipairs(
						character:GetChildren()
						) do
						if tool:IsA("Tool")
							and isFruitTool(
								tool
							)
						then
							tool.Parent =
								currentBackpack
						end
					end

					current.bulkMutating =
						false

					compactBackpack(
						player,
						currentBackpack
					)
				end
			end
		)
	end

	--==============================================================
	-- BRIDGE: FORCE SAVE
	--==============================================================

	local oldForce =
		ServerScriptService:FindFirstChild(
			"ForceFruitInventorySave"
		)

	if oldForce then
		oldForce:Destroy()
	end

	local forceSave =
		Instance.new(
			"BindableFunction"
		)

	forceSave.Name =
		"ForceFruitInventorySave"

	forceSave.Parent =
		ServerScriptService

	forceSave.OnInvoke =
		function(player)
			if not player
				or player.Parent
				~= Players
			then
				return
				false,
				"Jugador invalido."
			end

			local state =
			playerState[player]

			if not state
				or not state.loaded
			then
				return
				false,
				"Inventario no cargado."
			end

			state.lastCounts =
			scanInventory(
				player
			)

			local ok =
			saveNow(
				player,
				false
			)

			return
			ok,
			ok
			and "Guardado confirmado."
			or "No se pudo guardar."
		end

	--==============================================================
	-- BRIDGE: ADMIN / OTROS SISTEMAS
	--
	-- NO CREA 99 TOOLS.
	-- Actualiza el total lógico y crea solo los stacks faltantes.
	--==============================================================

	local oldAdd =
		ServerScriptService:FindFirstChild(
			"AddFruitInventory"
		)

	if oldAdd then
		oldAdd:Destroy()
	end

	local addFruit =
		Instance.new(
			"BindableFunction"
		)

	addFruit.Name =
		"AddFruitInventory"

	addFruit.Parent =
		ServerScriptService

	addFruit.OnInvoke =
		function(
			player,
			requestedName,
			requestedAmount
		)
		if not player
			or player.Parent
			~= Players
		then
			return
				false,
				"Jugador invalido.",
				nil
		end

		local state =
			playerState[player]

		if not state
			or not state.loaded
		then
			return
				false,
				"El inventario de frutas todavia esta cargando.",
				nil
		end

		local template =
			findTemplate(
				requestedName
			)

		if not template then
			return
				false,
				"No existe esa fruta.",
				nil
		end

		local amount =
			math.clamp(
				math.floor(
					tonumber(
						requestedAmount
					) or 1
				),
				1,
				STACK_LIMIT
			)

		local canonical =
			canonicalNameFromTemplate(
				template
			)

		local oldTotal =
			math.max(
				0,
				math.floor(
					tonumber(
						state.lastCounts[
						canonical
						]
					) or 0
				)
			)

		local newTotal =
			math.clamp(
				oldTotal + amount,
				0,
				MAX_TOTAL_PER_FRUIT
			)

		state.lastCounts[
		canonical
		] = newTotal

		ensureLogicalCounts(
			player,
			state.lastCounts
		)

		local backpack =
			getCurrentBackpack(
				player
			)

		if backpack then
			compactBackpack(
				player,
				backpack
			)
		end

		player:SetAttribute(
			"FruitInventoryRevision",
			(tonumber(
				player:GetAttribute(
					"FruitInventoryRevision"
				)
				) or 0) + 1
		)

		queueSave(player)
		return
			true,
			"Fruta entregada.",
			{
				name = canonical,
				display = canonical,
				amount = amount,
				total = newTotal,
			}
	end

	--==============================================================
	-- AUTOSAVE
	--==============================================================

	task.spawn(function()
		while true do
			task.wait(
				AUTOSAVE_SECONDS
			)

			for player, state
				in pairs(playerState)
			do
				if player.Parent
					== Players
					and state.loaded
					and state.dirty
					and not state.shuttingDown
				then
					state.lastCounts =
						scanInventory(
							player
						)

					saveNow(
						player,
						false
					)
				end
			end
		end
	end)

	--==============================================================
	-- PLAYERS
	--==============================================================

	Players.PlayerAdded:Connect(
		loadPlayer
	)

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(
			loadPlayer,
			player
		)
	end

	Players.PlayerRemoving:Connect(
		function(player)
			local state =
				playerState[player]

			if state
				and state.loaded
			then
				state.shuttingDown =
					true

				saveNow(
					player,
					false
				)
			end

			playerState[player] = nil
		end
	)

	--==============================================================
	-- CIERRE SERVIDOR
	--==============================================================

	game:BindToClose(function()
		local pending = 0

		for player, state
			in pairs(playerState)
		do
			if state.loaded then
				state.shuttingDown =
					true

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

		local started =
			os.clock()

		while pending > 0
			and os.clock() - started < 8
		do
			task.wait(0.05)
		end
	end)
end

return FruitInventoryService
