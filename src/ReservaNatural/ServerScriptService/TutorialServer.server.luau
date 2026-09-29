local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local system = ReplicatedStorage:WaitForChild("TutorialSystem")
local config = require(system:WaitForChild("TutorialConfig"))
local shared = require(system:WaitForChild("TutorialShared"))

local remotes = system:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = system
end

local function ensureRemote(name, className)
	local found = remotes:FindFirstChild(name)
	if found and not found:IsA(className) then
		warn("[TutorialV6.17] " .. name .. " tenia tipo incorrecto (" .. found.ClassName .. "). Se reemplazara por " .. className)
		found:Destroy()
		found = nil
	end
	if not found then
		found = Instance.new(className)
		found.Name = name
		found.Parent = remotes
	end
	return found
end

local RequestState = ensureRemote("RequestState", "RemoteFunction")
local ClientAction = ensureRemote("ClientAction", "RemoteEvent")
local StateRemote = ensureRemote("State", "RemoteEvent")
local CompletedRemote = ensureRemote("TutorialCompleted", "RemoteEvent")
local ActionCompleted = ensureRemote("ActionCompleted", "BindableEvent")

local stepById, stepOrder = shared.BuildStepMap(config)
local store = DataStoreService:GetDataStore(config.DATASTORE_NAME)

local cache = {}
local saving = {}
local saveAgain = {}
local stepRuntime = {}

print("[TutorialV6.17] SERVER ACTIVO | DataStore:", config.DATASTORE_NAME, "| Version:", config.TUTORIAL_VERSION)

-- Acciones que un LocalScript puede reportar.
-- No dan dinero/items; solo permiten avanzar el tutorial.
local CLIENT_REPORTABLE = {
	PET_MENU_OPENED = true,
	PET_CARE_USED = true,
	FREE_EGG_CLAIMED = true,
	FRANK_DEMO_DONE = true,
}

local function countOwnedEggs(player)
	local inventory = player:FindFirstChild("TradePetsInventory")
	if not inventory then return 0 end
	local total = 0
	for _, item in ipairs(inventory:GetDescendants()) do
		if item:IsA("IntValue") or item:IsA("NumberValue") then
			local itemName = tostring(item:GetAttribute("ItemName") or item.Name)
			if itemName == "Huevo Mascota" then
				total += math.max(0, tonumber(item.Value) or 0)
			end
		end
	end
	return total
end

local function captureStepRuntime(player, stepId)
	local runtime = stepRuntime[player]
	if not runtime then runtime = {}; stepRuntime[player] = runtime end
	if stepId == "BUY_FREE_EGG" then
		runtime.FreeEggBaseline = countOwnedEggs(player)
	else
		runtime.FreeEggBaseline = nil
	end
end

local function isAdmin(player)
	if RunService:IsStudio() then return true end
	for _, id in ipairs(config.ADMIN_USER_IDS or {}) do
		if id == player.UserId then return true end
	end
	return false
end

local function normalizeTutorialStep(stepId)
	stepId = tostring(stepId or "")

	-- V6.9: Casa Jugadores ya NO forma parte del tutorial inicial.
	-- Cualquier progreso viejo o cualquier config antigua que intente mandar
	-- a estos pasos se redirige directamente al portal del bosque.
	if stepId == "GO_PLAYER_HOUSE" or stepId == "HOUSE_REST" then
		return "GO_FOREST_PORTAL"
	end

	return stepId
end

local function defaultData()
	return {
		Version = config.TUTORIAL_VERSION,
		Step = config.FIRST_STEP,
		Completed = false,
		FreeStarterEggClaimed = false,
		FreeStarterAxeClaimed = false,
	}
end

local function cleanData(raw)
	if typeof(raw) ~= "table" then
		return defaultData()
	end

	-- Si alguna vez reutilizas el mismo DataStore y subes de version,
	-- los jugadores vuelven a empezar esa nueva version una sola vez.
	if tonumber(raw.Version) ~= config.TUTORIAL_VERSION then
		return defaultData()
	end

	local step = normalizeTutorialStep(raw.Step or config.FIRST_STEP)
	if not stepById[step] then step = config.FIRST_STEP end

	return {
		Version = config.TUTORIAL_VERSION,
		Step = step,
		Completed = raw.Completed == true,
		FreeStarterEggClaimed = raw.FreeStarterEggClaimed == true,
		FreeStarterAxeClaimed = raw.FreeStarterAxeClaimed == true,
	}
end

local function applyAttributes(player)
	local data = cache[player]
	if not data then return end

	player:SetAttribute("TutorialStep", data.Step)
	player:SetAttribute("TutorialCompleted", data.Completed)
	player:SetAttribute("TutorialLocked", not data.Completed)
	player:SetAttribute("FreeStarterEggClaimed", data.FreeStarterEggClaimed == true)
	player:SetAttribute("FreeStarterAxeClaimed", data.FreeStarterAxeClaimed == true)

	-- El sistema de nivel debe revisar este atributo ANTES de mostrar
	-- cualquier aviso de Level Up.
	player:SetAttribute("SuppressLevelUpNotice", not data.Completed)
end

local function snapshot(data)
	return {
		Version = config.TUTORIAL_VERSION,
		Step = data.Step,
		Completed = data.Completed == true,
		FreeStarterEggClaimed = data.FreeStarterEggClaimed == true,
		FreeStarterAxeClaimed = data.FreeStarterAxeClaimed == true,
	}
end

local function saveNow(player)
	local data = cache[player]
	if not data then return end

	if saving[player] then
		saveAgain[player] = true
		return
	end

	saving[player] = true
	repeat
		saveAgain[player] = nil
		local copy = snapshot(data)
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(player.UserId), function()
				return copy
			end)
		end)
		if not ok then
			warn("[TutorialV6.17] Save failed for " .. player.Name .. ": " .. tostring(err))
		end
	until not saveAgain[player]
	saving[player] = nil
end

local function sendState(player)
	local data = cache[player]
	if not data then return end
	applyAttributes(player)
	StateRemote:FireClient(player, snapshot(data), stepById[data.Step], #config.Steps, config)
end

local function setStep(player, stepId, shouldSave)
	stepId = normalizeTutorialStep(stepId)
	local data = cache[player]
	if not data or not stepById[stepId] then return end
	if data.Step == stepId then
		sendState(player)
		return
	end

	data.Step = stepId
	captureStepRuntime(player, stepId)
	applyAttributes(player)
	if shouldSave then task.spawn(saveNow, player) end
	sendState(player)
end

local function completeTutorial(player)
	local data = cache[player]
	if not data then return end

	data.Completed = true
	data.Step = "TUTORIAL_COMPLETE"
	applyAttributes(player)
	task.spawn(saveNow, player)
	CompletedRemote:FireClient(player)
	sendState(player)
end

local function advance(player, shouldSave)
	local data = cache[player]
	if not data or data.Completed then return false end

	local step = stepById[data.Step]
	if not step then return false end
	if step.CompleteTutorial then
		completeTutorial(player)
		return true
	end

	local nextId = normalizeTutorialStep(step.SaveNextBeforeTeleport or step.Next)
	if nextId and stepById[nextId] then
		local nextStep = stepById[nextId]

		-- V6.17:
		-- Si el siguiente paso es el final, completamos INMEDIATAMENTE.
		-- Así NO aparece ningún panel "EMPEZAR".
		if nextStep.CompleteTutorial == true or nextStep.AutoComplete == true then
			completeTutorial(player)
			return true
		end

		setStep(player, nextId, shouldSave ~= false)
		return true
	end
	return false
end

--============================================================
-- COMANDOS DEBUG V5.3
-- Compatible con TextChatService moderno y Player.Chatted clasico.
--============================================================
local function handleDebugCommand(player, command, stepId)
	if not player or not cache[player] then return false end
	if not (config.DEBUG_TUTORIAL and isAdmin(player)) then return false end

	command = string.lower(tostring(command or ""))
	if command == "reset" then
		cache[player] = defaultData()
		stepRuntime[player] = {}
		captureStepRuntime(player, cache[player].Step)
		applyAttributes(player)
		-- Guardamos y reenviamos inmediatamente. El guardado va en paralelo
		-- para que la UI vuelva al PASO 1 sin esperar DataStore.
		task.spawn(saveNow, player)
		sendState(player)
		print("[TutorialV6.17] Tutorial reiniciado para", player.Name)
		return true
	elseif command == "next" then
		advance(player, true)
		return true
	elseif command == "previous" then
		local st = stepById[cache[player].Step]
		if st then
			setStep(player, stepOrder[math.max(1, (st.Index or 1) - 1)], true)
		end
		return true
	elseif command == "goto" and stepId and stepById[stepId] then
		setStep(player, stepId, true)
		return true
	elseif command == "complete" then
		completeTutorial(player)
		return true
	elseif command == "state" then
		sendState(player)
		return true
	end

	sendState(player)
	return false
end

local function parseTutorialCommand(rawMessage)
	local args = string.split(tostring(rawMessage or ""), " ")
	local first = string.lower(args[1] or "")
	if first == "/tutorial" or first == "tutorial" then
		return args[2], args[3]
	end
	-- TextChatCommand puede entregar solo el texto restante segun version.
	return args[1], args[2]
end

local function isAlreadyComplete(player, step)
	-- Ya NO se completan compras solo por tener un item.
	-- Ya NO se completan todos los PORTAL solo por acercarse.
	if step.AdvanceOnReach == true then
		local target = shared.FindTarget(step, player)
		return target ~= nil and shared.DistanceToCharacter(player, target) <= (step.Radius or 6)
	end
	return false
end

local function tryCompleteCurrent(player, reason, payload)
	local data = cache[player]
	if not data or data.Completed then return false end

	local step = stepById[data.Step]
	if not step then return false end

	if isAlreadyComplete(player, step) then
		return advance(player, true)
	end

	if step.Type == "INFO" and reason == "continue" then
		return advance(player, true)
	end

	if step.RequiredAction and reason == step.RequiredAction then
		return advance(player, true)
	end

	if step.OptionalAction and (reason == "continue" or reason == "optional") then
		return advance(player, true)
	end

	return false
end

RequestState.OnServerInvoke = function(player)
	-- Evita la carrera de inicio: el cliente puede preguntar antes de que
	-- termine GetAsync. Esperamos un poco en vez de devolver nil para siempre.
	local deadline = os.clock() + 12
	while player.Parent and not cache[player] and os.clock() < deadline do
		task.wait(0.05)
	end

	local data = cache[player]
	return data and snapshot(data) or nil, data and stepById[data.Step] or nil, #config.Steps, config
end

ClientAction.OnServerEvent:Connect(function(player, action, payload)
	payload = typeof(payload) == "table" and payload or {}

	if action == "Continue" then
		tryCompleteCurrent(player, "continue", payload)
	elseif action == "FinalButton" then
		local step = cache[player] and stepById[cache[player].Step]
		if step and step.CompleteTutorial then completeTutorial(player) end
	elseif action == "ReportAction" then
		local name = tostring(payload.Name or "")
		if CLIENT_REPORTABLE[name] then
			if name == "FREE_EGG_CLAIMED" then
				local data = cache[player]
				local step = data and stepById[data.Step]
				local runtime = stepRuntime[player] or {}
				local baseline = tonumber(runtime.FreeEggBaseline)
				local currentCount = countOwnedEggs(player)
				if step and step.Id == "BUY_FREE_EGG"
					and baseline ~= nil
					and currentCount > baseline
				then
					data.FreeStarterEggClaimed = true
					applyAttributes(player)
					task.spawn(saveNow, player)
					tryCompleteCurrent(player, name, payload)
				end
			elseif name == "FRANK_DEMO_DONE" then
				-- Respaldo contra carreras entre el Prompt de Frank y su UI.
				-- Si el cliente termina la explicacion mientras aun figura GO_FRANK,
				-- primero entramos a FRANK_EXAMPLE y luego lo completamos.
				local data = cache[player]
				local step = data and stepById[data.Step]
				if step and step.Id == "GO_FRANK" then
					advance(player, true)
					data = cache[player]
					step = data and stepById[data.Step]
				end
				if step and step.Id == "FRANK_EXAMPLE" then
					tryCompleteCurrent(player, name, payload)
				end
			else
				tryCompleteCurrent(player, name, payload)
			end
		end
	elseif action == "Debug" then
		handleDebugCommand(player, payload.Command, payload.Step)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local data = cache[player]
	local step = data and stepById[data.Step]
	if not step or step.Type ~= "PROXIMITY_PROMPT" then return end

	local wantedPrompt = step.Target and step.Target.PromptName
	if wantedPrompt and prompt.Name ~= wantedPrompt then return end

	local target = shared.FindTarget(step, player)
	-- Si la ruta del NPC cambio pero el PromptName correcto sigue existiendo,
	-- no bloqueamos el tutorial.
	if not target or prompt:IsDescendantOf(target) then
		advance(player, true)
	end
end)

-- Este BindableEvent es para scripts DEL SERVIDOR.
-- BrizabelleEggServer / LexAxeShopServer / TreeChopServer /
-- PetBushSearchServer / servidor de necesidades pueden hacer:
-- ActionCompleted:Fire(player, "NOMBRE_ACCION")
ActionCompleted.Event:Connect(function(player, actionName, payload)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local data = cache[player]
	if not data then return end

	actionName = tostring(actionName)
	if actionName == "FREE_EGG_CLAIMED" then
		data.FreeStarterEggClaimed = true
		applyAttributes(player)
		task.spawn(saveNow, player)
	elseif actionName == "FREE_AXE_CLAIMED" then
		data.FreeStarterAxeClaimed = true
		applyAttributes(player)
		task.spawn(saveNow, player)
	end

	tryCompleteCurrent(player, actionName, payload)
end)

--============================================================
-- V6.15 - GATE ESTRICTO DE LA CASA DE LEX
--
-- RESERVE_TALK_LEX NO puede mostrarse mientras el jugador siga
-- afuera. Esto también corrige partidas antiguas que quedaron
-- guardadas en RESERVE_TALK_LEX antes de entrar a la casa.
--============================================================
local function isInsideLexInterior(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local interior = workspace:FindFirstChild("Interior casa bosque")
	if not interior then
		return false
	end

	-- Primero usamos el punto real al que teletransporta CasaBosqueDoorServer.
	local anchor = interior:FindFirstChild("TpCasaInteriorBosque", true)
	if anchor and anchor:IsA("BasePart") then
		if (root.Position - anchor.Position).Magnitude <= 45 then
			return true
		end
	end

	-- Respaldo: si cambia el punto de TP, comprobamos si el jugador está
	-- físicamente dentro del volumen del modelo Interior casa bosque.
	if interior:IsA("Model") then
		local ok, cf, size = pcall(function()
			local modelCf, modelSize = interior:GetBoundingBox()
			return modelCf, modelSize
		end)
		if ok and cf and size then
			local localPos = cf:PointToObjectSpace(root.Position)
			local margin = 8
			if math.abs(localPos.X) <= size.X * 0.5 + margin
				and math.abs(localPos.Y) <= size.Y * 0.5 + margin
				and math.abs(localPos.Z) <= size.Z * 0.5 + margin
			then
				return true
			end
		end
	end

	return false
end

local function forceCorrectLexStep(player)
	local data = cache[player]
	if not data or data.Completed then
		return false
	end

	if data.Step == "RESERVE_TALK_LEX" and not isInsideLexInterior(player) then
		data.Step = "RESERVE_ENTER_INTERIOR"
		captureStepRuntime(player, data.Step)
		applyAttributes(player)
		task.spawn(saveNow, player)
		print("[TutorialV6.17] Lex estaba marcado afuera -> RESERVE_ENTER_INTERIOR para", player.Name)
		return true
	end

	return false
end

local function bindPlayer(player)
	local ok, raw = pcall(function()
		return store:GetAsync(tostring(player.UserId))
	end)

	if not ok then
		warn("[TutorialV6.17] Load failed for " .. player.Name .. ": " .. tostring(raw))
	end

	cache[player] = cleanData(ok and raw or nil)

	-- V6.11: si el jugador ya aparecio dentro de Reserva Natural pero el
	-- ultimo guardado quedo en GO_FOREST_PORTAL por una carrera de teleport,
	-- continuamos directamente con Lex. Nunca lo mandamos de regreso al Lobby.
	local naturalWorld = config.Worlds and config.Worlds.NaturalReserve
	local isNaturalReserve = false
	for _, placeId in ipairs((naturalWorld and naturalWorld.PlaceIds) or {}) do
		if game.PlaceId == placeId then
			isNaturalReserve = true
			break
		end
	end
	if isNaturalReserve and cache[player].Step == "GO_FOREST_PORTAL" then
		cache[player].Step = "RESERVE_ENTER_SHOP"
		print("[TutorialV6.17] Reserva Natural detectada -> RESERVE_ENTER_SHOP para", player.Name)
		task.spawn(saveNow, player)
	end

	-- Si una sesion anterior se habia guardado en Casa Jugadores,
	-- cleanData ya la convierte a GO_FOREST_PORTAL. Guardamos esa migracion.
	if ok and typeof(raw) == "table" then
		local oldStep = tostring(raw.Step or "")
		if oldStep == "GO_PLAYER_HOUSE" or oldStep == "HOUSE_REST" then
			print("[TutorialV6.17] Migrando", player.Name, oldStep, "-> GO_FOREST_PORTAL")
			task.spawn(saveNow, player)
		end
	end

	-- Antes de mandar el primer estado al cliente, corregimos progreso viejo.
	-- Así NO aparece ni un frame del marcador LEX mientras el jugador está afuera.
	if isNaturalReserve and cache[player].Step == "RESERVE_TALK_LEX" then
		local character = player.Character
		if not character then
			character = player.CharacterAdded:Wait()
		end
		if character then
			character:WaitForChild("HumanoidRootPart", 5)
		end
		forceCorrectLexStep(player)
	end

	captureStepRuntime(player, cache[player].Step)
	applyAttributes(player)
	print("[TutorialV6.17] Estado cargado para", player.Name, "| Step:", cache[player].Step, "| Completed:", cache[player].Completed)
	sendState(player)

	-- Respaldo para el chat clasico. El comando principal moderno se
	-- registra abajo con TextChatCommand.
	player.Chatted:Connect(function(message)
		local command, stepId = parseTutorialCommand(message)
		if string.lower(tostring(message)):sub(1, 9) == "/tutorial" then
			handleDebugCommand(player, command, stepId)
		end
	end)

	-- V6.15: además de AdvanceOnReach, protegemos el paso de Lex.
	task.spawn(function()
		while player.Parent and cache[player] and not cache[player].Completed do
			local data = cache[player]
			local step = data and stepById[data.Step]

			if step and step.Id == "RESERVE_TALK_LEX" and not isInsideLexInterior(player) then
				if forceCorrectLexStep(player) then
					sendState(player)
				end
			elseif step and step.Id == "RESERVE_ENTER_INTERIOR" and isInsideLexInterior(player) then
				-- En cuanto el TP realmente dejó al jugador adentro, recién ahora
				-- habilitamos HABLA CON LEX y su marcador amarillo.
				advance(player, true)
			elseif step and step.AdvanceOnReach then
				tryCompleteCurrent(player, "reach", {})
			end

			task.wait(0.20)
		end
	end)
end

-- V5.4: NO creamos TextChatCommand desde el servidor.
-- Algunas experiencias/configuraciones de chat pueden lanzar error al crear
-- ese comando y detener TODO TutorialServer antes de conectar PlayerAdded.
-- El tutorial no depende del chat para funcionar.
-- Para debug, ClientAction acepta action="Debug" y Player.Chatted queda como respaldo.

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	saveNow(player)
	cache[player] = nil
	saving[player] = nil
	saveAgain[player] = nil
	stepRuntime[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(bindPlayer, player)
end

-- Comando moderno OPCIONAL y protegido. Si Roblox cambia el chat o falla
-- TextChatCommand, el tutorial sigue funcionando porque todo esto va en pcall.
task.defer(function()
	local ok, err = pcall(function()
		local oldCommand = TextChatService:FindFirstChild("GrindNimalsTutorialCommand")
		if oldCommand then oldCommand:Destroy() end

		local tutorialCommand = Instance.new("TextChatCommand")
		tutorialCommand.Name = "GrindNimalsTutorialCommand"
		tutorialCommand.PrimaryAlias = "/tutorial"
		tutorialCommand.Parent = TextChatService

		tutorialCommand.Triggered:Connect(function(originTextSource, unfilteredText)
			if not originTextSource then return end
			local plr = Players:GetPlayerByUserId(originTextSource.UserId)
			if not plr then return end
			local command, stepId = parseTutorialCommand(unfilteredText)
			handleDebugCommand(plr, command, stepId)
		end)
	end)
	if ok then
		print("[TutorialV6.17] Comando /tutorial registrado.")
	else
		warn("[TutorialV6.15] No se pudo registrar /tutorial, pero el tutorial sigue activo:", err)
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveNow(player)
	end
end)
