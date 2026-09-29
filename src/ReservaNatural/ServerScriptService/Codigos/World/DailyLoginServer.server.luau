--============================================================
-- DAILY LOGIN SERVER V2
-- Ubicacion: ServerScriptService > DailyLoginServer
-- Tipo: Script
--
-- FUNCIONAMIENTO:
-- Dia 1: 5 Diamantes
-- Dia 2: 50 Dolares
-- Dia 3: 100 Dolares
-- Dia 4: 150 Dolares
-- Dia 5: 200 Dolares
-- Dia 6: 5 Diamantes
-- Dia 7: 1 Huevo Mascota
--
-- IMPORTANTE:
-- * El tiempo usa os.time(), por lo que SIGUE PASANDO aunque
--   el jugador cierre Roblox o el servidor se apague.
-- * Cada recompensa siguiente se habilita 24 horas despues.
-- * Si pasan 48 horas desde el ultimo reclamo sin reclamar,
--   la racha vuelve al Dia 1.
-- * Despues del Dia 7, la siguiente recompensa vuelve al Dia 1.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

--============================================================
-- CONFIG
--============================================================

local STORE_NAME = "DailyLoginRewardsV1" -- conserva tus datos actuales
local DIAMOND_STORE_NAME = "PlayerDiamondsV1"

local CLAIM_INTERVAL = 24 * 60 * 60       -- 24 horas
local STREAK_BREAK_TIME = 48 * 60 * 60   -- 48 horas
local EGG_NAME = "Huevo Mascota"
local MAX_DIAMONDS = 999999999

local REWARDS = {
	[1] = {kind = "Diamonds", amount = 5, display = "5 Diamantes"},
	[2] = {kind = "Dollars", amount = 50, display = "50 Dolares"},
	[3] = {kind = "Dollars", amount = 100, display = "100 Dolares"},
	[4] = {kind = "Dollars", amount = 150, display = "150 Dolares"},
	[5] = {kind = "Dollars", amount = 200, display = "200 Dolares"},
	[6] = {kind = "Diamonds", amount = 5, display = "5 Diamantes"},
	[7] = {kind = "Egg", amount = 1, display = "Huevo Mascota"},
}

local MONEY_NAMES = {
	"Dolares",
	"Dólares",
	"Dollars",
	"Cash",
	"Money",
	"Dinero",
	"Monedas",
}

local dailyStore = DataStoreService:GetDataStore(STORE_NAME)
local diamondStore = DataStoreService:GetDataStore(DIAMOND_STORE_NAME)

local dailyCache = {}
local diamondsLoaded = {}
local claimBusy = {}

--============================================================
-- REMOTES
--============================================================

local systemFolder = ReplicatedStorage:FindFirstChild("DailyLoginSystem")
if not systemFolder then
	systemFolder = Instance.new("Folder")
	systemFolder.Name = "DailyLoginSystem"
	systemFolder.Parent = ReplicatedStorage
end

local function ensureRemoteFunction(name)
	local remote = systemFolder:FindFirstChild(name)

	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = systemFolder
	end

	return remote
end

local GetDailyState = ensureRemoteFunction("GetDailyState")
local ClaimDailyReward = ensureRemoteFunction("ClaimDailyReward")

--============================================================
-- HELPERS
--============================================================

local function isNumericValue(value)
	return value and (value:IsA("IntValue") or value:IsA("NumberValue"))
end

local function getOrCreateLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats and not leaderstats:IsA("Folder") then
		leaderstats:Destroy()
		leaderstats = nil
	end

	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	return leaderstats
end

local function findDollars(player)
	local containers = {
		player:FindFirstChild("leaderstats"),
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

local function waitForDollars(player, timeout)
	local started = os.clock()

	repeat
		local value = findDollars(player)
		if value then
			return value
		end
		task.wait(0.1)
	until not player.Parent or os.clock() - started >= (timeout or 10)

	return nil
end

--============================================================
-- DIAMANTES
--============================================================

local function getDiamondValue(player)
	local leaderstats = getOrCreateLeaderstats(player)
	local value = leaderstats:FindFirstChild("Diamantes")

	if value and not isNumericValue(value) then
		value:Destroy()
		value = nil
	end

	if not value then
		value = Instance.new("IntValue")
		value.Name = "Diamantes"
		value.Value = 0
		value.Parent = leaderstats
	end

	return value
end

local function loadDiamonds(player)
	local value = getDiamondValue(player)

	if diamondsLoaded[player] then
		return value
	end

	local ok, saved = pcall(function()
		return diamondStore:GetAsync(tostring(player.UserId))
	end)

	if ok and typeof(saved) == "number" then
		value.Value = math.clamp(math.floor(saved), 0, MAX_DIAMONDS)
	elseif not ok then
		warn("[DailyLogin] Error cargando diamantes de " .. player.Name .. ": " .. tostring(saved))
	end

	diamondsLoaded[player] = true
	return value
end

local function saveDiamonds(player)
	if not player then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Diamantes")

	if not isNumericValue(value) then
		return
	end

	local amount = math.clamp(math.floor(tonumber(value.Value) or 0), 0, MAX_DIAMONDS)

	local ok, err = pcall(function()
		diamondStore:SetAsync(tostring(player.UserId), amount)
	end)

	if not ok then
		warn("[DailyLogin] Error guardando diamantes de " .. player.Name .. ": " .. tostring(err))
	end
end

--============================================================
-- DATOS DIARIOS
--============================================================

local function cleanData(raw)
	local data = typeof(raw) == "table" and raw or {}

	local lastClaimAt = math.max(
		0,
		math.floor(tonumber(data.lastClaimAt) or 0)
	)

	-- Migracion automatica desde la primera version.
	-- La V1 guardaba lastClaimDay como numero de dia UTC.
	-- Usar el inicio de ese dia conserva aproximadamente el
	-- mismo tiempo que ya mostraba tu contador anterior.
	if lastClaimAt <= 0 then
		local oldDay = tonumber(data.lastClaimDay)
		if oldDay and oldDay > 0 then
			lastClaimAt = math.floor(oldDay) * 86400
		end
	end

	return {
		lastClaimAt = lastClaimAt,
		cycleDay = math.clamp(
			math.floor(tonumber(data.cycleDay) or 0),
			0,
			7
		),
		lastClaimToken = typeof(data.lastClaimToken) == "string"
			and data.lastClaimToken
			or "",
	}
end

local function loadDailyData(player)
	if dailyCache[player] then
		return dailyCache[player]
	end

	local ok, saved = pcall(function()
		return dailyStore:GetAsync(tostring(player.UserId))
	end)

	local data
	if ok then
		data = cleanData(saved)
	else
		warn("[DailyLogin] Error cargando recompensas de " .. player.Name .. ": " .. tostring(saved))
		data = cleanData(nil)
	end

	dailyCache[player] = data
	return data
end

local function getView(data)
	data = cleanData(data)

	local now = os.time()

	-- Primera vez.
	if data.lastClaimAt <= 0 or data.cycleDay <= 0 then
		return {
			canClaim = true,
			currentDay = 1,
			nextClaimAt = now,
			streakReset = false,
		}
	end

	local elapsed = now - data.lastClaimAt

	-- Si dejo pasar demasiado tiempo, vuelve al Dia 1.
	if elapsed >= STREAK_BREAK_TIME then
		return {
			canClaim = true,
			currentDay = 1,
			nextClaimAt = now,
			streakReset = true,
		}
	end

	local nextDay = (data.cycleDay % 7) + 1
	local nextClaimAt = data.lastClaimAt + CLAIM_INTERVAL

	return {
		canClaim = now >= nextClaimAt,
		currentDay = nextDay,
		nextClaimAt = nextClaimAt,
		streakReset = false,
	}
end

local function rewardsForClient()
	local list = {}

	for day = 1, 7 do
		local reward = REWARDS[day]
		list[day] = {
			kind = reward.kind,
			amount = reward.amount,
			display = reward.display,
		}
	end

	return list
end

local function publicState(player, dataOverride)
	local data = dataOverride or loadDailyData(player)
	local view = getView(data)

	return {
		canClaim = view.canClaim,
		currentDay = view.currentDay,
		nextClaimAt = view.nextClaimAt,
		serverNow = os.time(),
		streakReset = view.streakReset,
		lastCompletedDay = data.cycleDay,
		rewards = rewardsForClient(),
	}
end

--============================================================
-- HUEVO MASCOTA
--============================================================

local function waitForPetContainer(player)
	local container = player:FindFirstChild("TradePetsInventory")

	if container and container:IsA("Folder") then
		return container
	end

	container = player:WaitForChild("TradePetsInventory", 15)

	if container and container:IsA("Folder") then
		task.wait(0.35)
		return container
	end

	return nil
end

local function findEggValue(container)
	for _, child in ipairs(container:GetChildren()) do
		if isNumericValue(child) then
			local itemName = tostring(child:GetAttribute("ItemName") or child.Name)

			if itemName == EGG_NAME or child.Name == EGG_NAME then
				return child
			end
		end
	end

	return nil
end

local function giveEgg(player)
	local container = waitForPetContainer(player)

	if not container then
		return false, "Tu inventario de mascotas no termino de cargar."
	end

	local egg = findEggValue(container)

	if not egg then
		egg = Instance.new("IntValue")
		egg.Name = EGG_NAME
		egg.Value = 0
		egg:SetAttribute("ItemName", EGG_NAME)
		egg:SetAttribute("UpgradeTier", "Base")
		egg:SetAttribute("Progress", 0)
		egg:SetAttribute("Energy", 100)
		egg:SetAttribute("Dirty", false)
		egg:SetAttribute("Tired", false)
		egg:SetAttribute("Resting", false)
		egg:SetAttribute("TradeUID", HttpService:GenerateGUID(false))
		egg.Parent = container
	end

	egg.Value += 1

	if player:GetAttribute("BrizabelleEggProgress") == nil then
		player:SetAttribute("BrizabelleEggProgress", 0)
	end

	return true
end

--============================================================
-- PREPARAR / ENTREGAR RECOMPENSA
--============================================================

local function prepareReward(player, day)
	local reward = REWARDS[day]

	if not reward then
		return false, "Recompensa invalida."
	end

	if reward.kind == "Dollars" then
		if not waitForDollars(player, 10) then
			return false, "No se encontro el valor Dolares."
		end
	elseif reward.kind == "Diamonds" then
		loadDiamonds(player)
	elseif reward.kind == "Egg" then
		if not waitForPetContainer(player) then
			return false, "Tu inventario de mascotas aun no esta listo."
		end
	end

	return true
end

local function grantReward(player, day)
	local reward = REWARDS[day]

	if reward.kind == "Diamonds" then
		local diamonds = loadDiamonds(player)
		diamonds.Value = math.clamp(diamonds.Value + reward.amount, 0, MAX_DIAMONDS)
		task.spawn(saveDiamonds, player)
		return true, "+" .. tostring(reward.amount) .. " Diamantes"

	elseif reward.kind == "Dollars" then
		local dollars = findDollars(player)

		if not dollars then
			return false, "No se encontro Dolares."
		end

		dollars.Value += reward.amount
		return true, "+" .. tostring(reward.amount) .. "$"

	elseif reward.kind == "Egg" then
		local ok, err = giveEgg(player)

		if not ok then
			return false, err
		end

		return true, "+1 Huevo Mascota"
	end

	return false, "Tipo de recompensa invalido."
end

--============================================================
-- REMOTES
--============================================================

GetDailyState.OnServerInvoke = function(player)
	return publicState(player)
end

ClaimDailyReward.OnServerInvoke = function(player)
	if claimBusy[player] then
		return {
			ok = false,
			message = "Espera un momento.",
			state = publicState(player),
		}
	end

	claimBusy[player] = true

	local data = loadDailyData(player)
	local view = getView(data)

	if not view.canClaim then
		claimBusy[player] = nil

		return {
			ok = false,
			message = "Aun no esta lista tu siguiente recompensa.",
			state = publicState(player),
		}
	end

	local rewardDay = view.currentDay
	local ready, readyMessage = prepareReward(player, rewardDay)

	if not ready then
		claimBusy[player] = nil

		return {
			ok = false,
			message = readyMessage,
			state = publicState(player),
		}
	end

	local token = HttpService:GenerateGUID(false)
	local now = os.time()
	local previousData = cleanData(data)

	local ok, savedOrErr = pcall(function()
		return dailyStore:UpdateAsync(tostring(player.UserId), function(old)
			local current = cleanData(old)
			local currentView = getView(current)

			if not currentView.canClaim then
				return current
			end

			current.lastClaimAt = now
			current.cycleDay = currentView.currentDay
			current.lastClaimToken = token

			return current
		end)
	end)

	if not ok then
		claimBusy[player] = nil

		return {
			ok = false,
			message = "No se pudo guardar tu recompensa. Intenta otra vez.",
			state = publicState(player),
		}
	end

	local saved = cleanData(savedOrErr)
	dailyCache[player] = saved

	if saved.lastClaimToken ~= token then
		claimBusy[player] = nil

		return {
			ok = false,
			message = "La recompensa ya fue reclamada.",
			state = publicState(player, saved),
		}
	end

	local granted, grantMessage = grantReward(player, rewardDay)

	if not granted then
		-- Rollback si fallo la entrega.
		pcall(function()
			dailyStore:UpdateAsync(tostring(player.UserId), function(old)
				local current = cleanData(old)

				if current.lastClaimToken == token then
					return previousData
				end

				return current
			end)
		end)

		dailyCache[player] = previousData
		claimBusy[player] = nil

		return {
			ok = false,
			message = grantMessage or "No se pudo entregar la recompensa.",
			state = publicState(player, previousData),
		}
	end

	claimBusy[player] = nil

	return {
		ok = true,
		message = "Dia " .. tostring(rewardDay) .. ": " .. tostring(grantMessage),
		rewardDay = rewardDay,
		state = publicState(player, saved),
	}
end

--============================================================
-- JUGADORES
--============================================================

local function setupPlayer(player)
	loadDiamonds(player)
	loadDailyData(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveDiamonds(player)
	dailyCache[player] = nil
	diamondsLoaded[player] = nil
	claimBusy[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveDiamonds(player)
	end

	task.wait(1)
end)

task.spawn(function()
	while true do
		task.wait(30)

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveDiamonds, player)
		end
	end
end)
