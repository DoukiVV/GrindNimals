--============================================================
-- BANK DOLLARS TO DIAMONDS SERVER
-- Ubicacion: ServerScriptService > BankDollarsToDiamondsServer
-- Tipo: Script
--
-- NPC:
-- Damian
-- Wiwin
-- Oliver
--
-- CAMBIO:
-- 100$ = 1 Diamante
-- 500$ = 5 Diamantes
--
-- William NO usa este sistema.
-- William conserva su sistema inverso:
-- 1 Diamante = 100$
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DOLLARS_PER_DIAMOND = 100
local MAX_DIAMONDS_PER_EXCHANGE = 10000
local EXCHANGE_COOLDOWN = 0.75
local MAX_SERVER_DISTANCE = 40

local MONEY_NAMES = {
	"Dolares",
	"Dólares",
	"Dollars",
	"Cash",
	"Money",
	"Dinero",
	"Monedas",
}

local NPC_CONFIG = {
	Damian = {
		promptName = "DamianBankPrompt",
		displayName = "Damian",
		modelNames = {"Damian"},
	},
	Wiwin = {
		promptName = "WiwinBankPrompt",
		displayName = "Wiwin",

		-- Compatibilidad: funciona aunque en Workspace el modelo
		-- todavia se llame "El cajero del Oxxo".
		modelNames = {"Wiwin", "El cajero del Oxxo"},
	},
	Oliver = {
		promptName = "OliverBankPrompt",
		displayName = "Oliver",
		modelNames = {"Oliver"},
	},
}

--============================================================
-- REMOTES
--============================================================

local folder = ReplicatedStorage:FindFirstChild("BankDollarsToDiamondsSystem")

if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BankDollarsToDiamondsSystem"
	folder.Parent = ReplicatedStorage
end

local function ensureRemoteFunction(name)
	local remote = folder:FindFirstChild(name)

	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

local GetExchangeState = ensureRemoteFunction("GetExchangeState")
local ExchangeDollarsForDiamonds = ensureRemoteFunction("ExchangeDollarsForDiamonds")

folder:SetAttribute("DollarsPerDiamond", DOLLARS_PER_DIAMOND)

local busy = {}
local lastExchangeAt = {}

--============================================================
-- MONEY HELPERS
--============================================================

local function isNumericValue(value)
	return value and (value:IsA("IntValue") or value:IsA("NumberValue"))
end

local function findDollars(player)
	local leaderstats = player:FindFirstChild("leaderstats")

	local containers = {
		leaderstats,
		player:FindFirstChild("Stats"),
		player:FindFirstChild("Data"),
		player,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, name in ipairs(MONEY_NAMES) do
				local value = container:FindFirstChild(name)

				if isNumericValue(value) then
					return value
				end
			end
		end
	end

	return nil
end

local function findDiamonds(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local value = leaderstats:FindFirstChild("Diamantes")

	if isNumericValue(value) then
		return value
	end

	return nil
end

local function waitForValue(getter, player, timeout)
	local started = os.clock()

	repeat
		local value = getter(player)

		if value then
			return value
		end

		task.wait(0.1)
	until not player.Parent or os.clock() - started >= (timeout or 8)

	return nil
end

--============================================================
-- NPC HELPERS
--============================================================

local function getBank()
	local interiores = Workspace:FindFirstChild("Interiores")
	return interiores and interiores:FindFirstChild("Interior banco")
end

local function findNpc(npcName)
	local bank = getBank()
	if not bank then
		return nil
	end

	local config = NPC_CONFIG[npcName]
	if not config then
		return nil
	end

	-- 1) Busca por los nombres aceptados del modelo.
	for _, modelName in ipairs(config.modelNames or {npcName}) do
		local direct = bank:FindFirstChild(modelName)

		if direct and direct:IsA("Model") then
			return direct
		end
	end

	for _, object in ipairs(bank:GetDescendants()) do
		if object:IsA("Model") then
			for _, modelName in ipairs(config.modelNames or {npcName}) do
				if object.Name == modelName then
					return object
				end
			end
		end
	end

	-- 2) Fallback MUY robusto:
	-- si el prompt ya existe, usa el modelo ancestro de ese prompt.
	for _, object in ipairs(bank:GetDescendants()) do
		if object:IsA("ProximityPrompt")
			and object.Name == config.promptName
		then
			local model = object:FindFirstAncestorOfClass("Model")
			if model then
				return model
			end
		end
	end

	return nil
end

local function getNpcPrompt(npcName)
	local bank = getBank()
	local config = NPC_CONFIG[npcName]

	if not bank or not config then
		return nil
	end

	-- Primero busca por nombre de prompt en todo el banco.
	for _, object in ipairs(bank:GetDescendants()) do
		if object:IsA("ProximityPrompt")
			and object.Name == config.promptName
		then
			return object
		end
	end

	-- Fallback: busca dentro del modelo.
	local npc = findNpc(npcName)

	if npc then
		return npc:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	return nil
end

local function getPromptWorldPosition(prompt)
	if not prompt then
		return nil
	end

	local parent = prompt.Parent

	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end

	if parent and parent:IsA("BasePart") then
		return parent.Position
	end

	return nil
end

local function getNpcRoot(npc)
	if not npc then
		return nil
	end

	-- R15/R6 normal.
	local root = npc:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end

	-- PrimaryPart si existe.
	if npc.PrimaryPart and npc.PrimaryPart:IsA("BasePart") then
		return npc.PrimaryPart
	end

	-- IMPORTANTE: recursive=true. Algunos NPC tienen las piezas
	-- dentro de submodelos/carpetas.
	return npc:FindFirstChildWhichIsA("BasePart", true)
end

local function getNpcWorldPosition(npcName)
	-- Mejor referencia: la misma pieza donde esta el ProximityPrompt.
	local prompt = getNpcPrompt(npcName)
	local promptPosition = getPromptWorldPosition(prompt)

	if promptPosition then
		return promptPosition
	end

	local npc = findNpc(npcName)
	local root = getNpcRoot(npc)

	if root then
		return root.Position
	end

	-- Ultimo fallback: GetPivot funciona aunque no haya PrimaryPart.
	if npc then
		local ok, pivot = pcall(function()
			return npc:GetPivot()
		end)

		if ok then
			return pivot.Position
		end
	end

	return nil
end

local function ensurePrompt(npcName, config)
	local npc = findNpc(npcName)
	if not npc then
		return false
	end

	-- Si ya existe un prompt correcto, NO exigimos HumanoidRootPart.
	local prompt = getNpcPrompt(npcName)

	if not prompt then
		prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	if not prompt then
		local root = getNpcRoot(npc)

		if not root then
			return false
		end

		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = root
	end

	prompt.Name = config.promptName
	prompt.ActionText = "Hablar"
	prompt.ObjectText = config.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = math.max(prompt.HoldDuration, 0.55)
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 14)
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true

	return true
end

task.spawn(function()
	for attempt = 1, 40 do
		local allReady = true

		for npcName, config in pairs(NPC_CONFIG) do
			if not ensurePrompt(npcName, config) then
				allReady = false
			end
		end

		if allReady then
			return
		end

		if attempt == 1 or attempt % 10 == 0 then
			local missing = {}

			for npcName in pairs(NPC_CONFIG) do
				if not findNpc(npcName) then
					table.insert(missing, npcName)
				end
			end

			warn(
				"[BankDollarDiamond] Esperando NPC del banco. Faltan: "
					.. (#missing > 0 and table.concat(missing, ", ") or "prompt/root")
			)
		end

		task.wait(0.5)
	end
end)

local function playerNearNpc(player, npcName)
	local character = player.Character
	local playerRoot =
		character
		and character:FindFirstChild("HumanoidRootPart")

	if not playerRoot or not playerRoot:IsA("BasePart") then
		return false
	end

	local npcPosition = getNpcWorldPosition(npcName)

	if not npcPosition then
		warn(
			"[BankDollarDiamond] No pude obtener posicion para "
				.. tostring(npcName)
		)
		return false
	end

	local distance =
		(playerRoot.Position - npcPosition).Magnitude

	-- Debug util para Studio si vuelve a fallar.
	if distance > MAX_SERVER_DISTANCE then
		warn(
			"[BankDollarDiamond] Distancia rechazada | "
				.. tostring(npcName)
				.. " | "
				.. string.format("%.1f", distance)
				.. " studs"
		)
	end

	return distance <= MAX_SERVER_DISTANCE
end

--============================================================
-- STATE
--============================================================

local function makeState(player, npcName)
	local dollarsValue = findDollars(player)
	local diamondsValue = findDiamonds(player)

	local dollars = dollarsValue
		and math.max(0, math.floor(tonumber(dollarsValue.Value) or 0))
		or 0

	local diamonds = diamondsValue
		and math.max(0, math.floor(tonumber(diamondsValue.Value) or 0))
		or 0

	return {
		dollars = dollars,
		diamonds = diamonds,
		dollarsPerDiamond = DOLLARS_PER_DIAMOND,
		maxAffordable = math.floor(dollars / DOLLARS_PER_DIAMOND),
		npcName = npcName,
	}
end

GetExchangeState.OnServerInvoke = function(player, npcName)
	if typeof(npcName) ~= "string" or not NPC_CONFIG[npcName] then
		npcName = "Damian"
	end

	waitForValue(findDollars, player, 8)
	waitForValue(findDiamonds, player, 8)

	return makeState(player, npcName)
end

--============================================================
-- EXCHANGE: DOLLARS -> DIAMONDS
--============================================================

ExchangeDollarsForDiamonds.OnServerInvoke = function(player, npcName, requestedDiamonds)
	if typeof(npcName) ~= "string" or not NPC_CONFIG[npcName] then
		return {
			ok = false,
			message = "Empleado invalido.",
			state = makeState(player, "Damian"),
		}
	end

	if busy[player] then
		return {
			ok = false,
			message = "Espera a que termine el cambio anterior.",
			state = makeState(player, npcName),
		}
	end

	local now = os.clock()
	local previous = lastExchangeAt[player] or -math.huge

	if now - previous < EXCHANGE_COOLDOWN then
		return {
			ok = false,
			message = "Espera un momento.",
			state = makeState(player, npcName),
		}
	end

	if not playerNearNpc(player, npcName) then
		return {
			ok = false,
			message = "Acercate al empleado para hacer el cambio.",
			state = makeState(player, npcName),
		}
	end

	local amount = tonumber(requestedDiamonds)

	if not amount
		or amount ~= amount
		or amount == math.huge
		or amount == -math.huge
	then
		return {
			ok = false,
			message = "Cantidad invalida.",
			state = makeState(player, npcName),
		}
	end

	amount = math.floor(amount)

	if amount < 1 then
		return {
			ok = false,
			message = "Debes comprar al menos 1 Diamante.",
			state = makeState(player, npcName),
		}
	end

	amount = math.clamp(amount, 1, MAX_DIAMONDS_PER_EXCHANGE)

	busy[player] = true
	lastExchangeAt[player] = now

	local dollars = waitForValue(findDollars, player, 5)
	local diamonds = waitForValue(findDiamonds, player, 5)

	if not dollars or not diamonds then
		busy[player] = nil

		return {
			ok = false,
			message = "Tus monedas aun no terminaron de cargar.",
			state = makeState(player, npcName),
		}
	end

	local cost = amount * DOLLARS_PER_DIAMOND

	if dollars.Value < cost then
		busy[player] = nil

		return {
			ok = false,
			message = "No tienes suficientes Dolares.",
			state = makeState(player, npcName),
		}
	end

	-- Operacion real solo en servidor.
	dollars.Value -= cost
	diamonds.Value += amount

	local state = makeState(player, npcName)

	busy[player] = nil

	return {
		ok = true,
		message =
			"Cambiaste "
			.. tostring(cost)
			.. "$ por "
			.. tostring(amount)
			.. (amount == 1 and " Diamante." or " Diamantes."),
		cost = cost,
		receivedDiamonds = amount,
		state = state,
	}
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastExchangeAt[player] = nil
end)
