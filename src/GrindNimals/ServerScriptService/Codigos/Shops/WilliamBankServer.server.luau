--============================================================
-- WILLIAM BANK SERVER V2
-- Ubicacion: ServerScriptService > WilliamBankServer
-- Tipo: Script
--
-- CAMBIO CORRECTO:
--      1 Diamante = 100 Dolares
--      5 Diamantes = 500 Dolares
--
-- SEGURIDAD:
-- * El servidor calcula los dolares recibidos.
-- * El cliente solo solicita cuantos diamantes quiere cambiar.
-- * Valida saldo real de diamantes.
-- * Valida distancia real hasta William.
-- * Anti-spam y bloqueo por jugador.
--
-- PERSISTENCIA:
-- Modifica los mismos valores "Diamantes" y "Dolares" que ya
-- existen en tu juego. DailyLoginServer guarda Diamantes y
-- GranjaMoneyServer guarda Dolares.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--============================================================
-- CONFIG
--============================================================

local DOLLARS_PER_DIAMOND = 100
local MAX_DIAMONDS_PER_EXCHANGE = 10000
local EXCHANGE_COOLDOWN = 0.75
local MAX_SERVER_DISTANCE = 24

local MONEY_NAMES = {
	"Dolares",
	"Dólares",
	"Dollars",
	"Cash",
	"Money",
	"Dinero",
	"Monedas",
}

--============================================================
-- REMOTES
--============================================================

local folder = ReplicatedStorage:FindFirstChild("WilliamBankSystem")

if not folder then
	folder = Instance.new("Folder")
	folder.Name = "WilliamBankSystem"
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

local GetBankState = ensureRemoteFunction("GetBankState")
local ExchangeDiamondsForDollars = ensureRemoteFunction("ExchangeDiamondsForDollars")

-- Borra el remoto viejo para evitar confusiones con versiones anteriores.
local oldRemote = folder:FindFirstChild("ExchangeDollarsForDiamonds")
if oldRemote then
	oldRemote:Destroy()
end

folder:SetAttribute("DollarsPerDiamond", DOLLARS_PER_DIAMOND)

--============================================================
-- HELPERS
--============================================================

local busy = {}
local lastExchangeAt = {}

local function isNumericValue(value)
	return value and (value:IsA("IntValue") or value:IsA("NumberValue"))
end

local function getLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats and leaderstats:IsA("Folder") then
		return leaderstats
	end

	return nil
end

local function findDollars(player)
	local containers = {
		getLeaderstats(player),
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
	local leaderstats = getLeaderstats(player)

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
-- WILLIAM
--============================================================

local function findWilliam()
	local interiores = Workspace:FindFirstChild("Interiores")

	if interiores then
		local bank = interiores:FindFirstChild("Interior banco")
		local william = bank and bank:FindFirstChild("William")

		if william and william:IsA("Model") then
			return william
		end

		for _, object in ipairs(interiores:GetDescendants()) do
			if object:IsA("Model") and object.Name == "William" then
				return object
			end
		end
	end

	return nil
end

local function getWilliamRoot()
	local william = findWilliam()

	if not william then
		return nil
	end

	return william:FindFirstChild("HumanoidRootPart")
		or william.PrimaryPart
		or william:FindFirstChildWhichIsA("BasePart")
end

local function ensureWilliamPrompt()
	local william = findWilliam()

	if not william then
		return false
	end

	local root = william:FindFirstChild("HumanoidRootPart")
		or william.PrimaryPart
		or william:FindFirstChildWhichIsA("BasePart")

	if not root then
		return false
	end

	local prompt = root:FindFirstChild("WilliamBankPrompt")

	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "WilliamBankPrompt"
		prompt.Parent = root
	end

	prompt.ActionText = "Hablar"
	prompt.ObjectText = "William"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.55
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true

	return true
end

task.spawn(function()
	for attempt = 1, 30 do
		if ensureWilliamPrompt() then
			return
		end

		if attempt == 1 or attempt % 10 == 0 then
			warn("[WilliamBank] Esperando a William...")
		end

		task.wait(1)
	end

	warn("[WilliamBank] No se pudo encontrar a William.")
end)

local function playerIsNearWilliam(player)
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local williamRoot = getWilliamRoot()

	if not playerRoot or not williamRoot then
		return false
	end

	return (playerRoot.Position - williamRoot.Position).Magnitude <= MAX_SERVER_DISTANCE
end

--============================================================
-- STATE
--============================================================

local function makeState(player)
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

		-- Ahora MAX depende de cuantos diamantes tenga el jugador.
		maxExchangeable = diamonds,
	}
end

GetBankState.OnServerInvoke = function(player)
	waitForValue(findDollars, player, 8)
	waitForValue(findDiamonds, player, 8)

	return makeState(player)
end

--============================================================
-- CAMBIO: DIAMANTES -> DOLARES
--============================================================

ExchangeDiamondsForDollars.OnServerInvoke = function(player, requestedDiamonds)
	if busy[player] then
		return {
			ok = false,
			message = "Espera a que termine el cambio anterior.",
			state = makeState(player),
		}
	end

	local now = os.clock()
	local previous = lastExchangeAt[player] or -math.huge

	if now - previous < EXCHANGE_COOLDOWN then
		return {
			ok = false,
			message = "Espera un momento antes de volver a cambiar.",
			state = makeState(player),
		}
	end

	if not playerIsNearWilliam(player) then
		return {
			ok = false,
			message = "Acercate a William para hacer el cambio.",
			state = makeState(player),
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
			state = makeState(player),
		}
	end

	amount = math.floor(amount)

	if amount < 1 then
		return {
			ok = false,
			message = "Debes cambiar al menos 1 Diamante.",
			state = makeState(player),
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
			state = makeState(player),
		}
	end

	if diamonds.Value < amount then
		busy[player] = nil

		return {
			ok = false,
			message = "No tienes suficientes Diamantes.",
			state = makeState(player),
		}
	end

	local dollarsReceived = amount * DOLLARS_PER_DIAMOND

	-- Operacion real SOLO en servidor.
	diamonds.Value -= amount
	dollars.Value += dollarsReceived

	local state = makeState(player)

	busy[player] = nil

	return {
		ok = true,
		message =
			"Cambiaste "
			.. tostring(amount)
			.. (amount == 1 and " Diamante" or " Diamantes")
			.. " por "
			.. tostring(dollarsReceived)
			.. "$.",
		spentDiamonds = amount,
		receivedDollars = dollarsReceived,
		state = state,
	}
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	lastExchangeAt[player] = nil
end)