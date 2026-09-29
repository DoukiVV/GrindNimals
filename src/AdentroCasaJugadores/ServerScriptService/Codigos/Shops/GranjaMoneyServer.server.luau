local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFAULT_DOLLARS = 0
local MAX_DOLLARS = 999999999999999
local REMOTE_NAME = "AdminSetDollars"
local STORE_NAME = "PlayerDollarsV1"
local moneyStore = DataStoreService:GetDataStore(STORE_NAME)

local MONEY_NAMES = {
	"Dolares",
	"Dólares",
	"Dollars",
	"Cash",
	"Money",
	"Dinero",
	"Monedas",
}

local ADMIN_USER_IDS = {
	[2763635937] = true, -- Tú
	[1075477843] = true, -- Tu compañero
}

local function isNumericValue(value)
	return value and (value:IsA("IntValue") or value:IsA("NumberValue"))
end

local function findMoneyValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, name in ipairs(MONEY_NAMES) do
			local value = leaderstats:FindFirstChild(name)
			if isNumericValue(value) then
				return value
			end
		end
	end
	for _, name in ipairs(MONEY_NAMES) do
		local value = player:FindFirstChild(name)
		if isNumericValue(value) then
			return value
		end
	end
	return nil
end

local function loadDollars(player)
	local success, value = pcall(function()
		return moneyStore:GetAsync(tostring(player.UserId))
	end)
	if success and typeof(value) == "number" and value >= 0 then
		return math.clamp(math.floor(value), 0, MAX_DOLLARS)
	end
	return DEFAULT_DOLLARS
end

local function saveDollars(player)
	local money = findMoneyValue(player)
	if not money then return end
	local amount = math.clamp(math.floor(tonumber(money.Value) or 0), 0, MAX_DOLLARS)
	pcall(function()
		moneyStore:SetAsync(tostring(player.UserId), amount)
	end)
end

local function ensureMoney(player)
	local value = findMoneyValue(player)
	if value then
		return value
	end
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
	local dollars = Instance.new("IntValue")
	dollars.Name = "Dolares"
	dollars.Value = loadDollars(player)
	dollars.Parent = leaderstats
	return dollars
end

local function isAdmin(player)
	return player ~= nil and ADMIN_USER_IDS[player.UserId] == true
end

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteFunction") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

remote.OnServerInvoke = function(player, requestedAmount)
	if not isAdmin(player) then
		return false, "No tienes permiso para usar esta opcion.", nil
	end
	local amount = tonumber(requestedAmount)
	if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
		return false, "La cantidad no es valida.", nil
	end
	amount = math.clamp(math.floor(amount), 0, MAX_DOLLARS)
	local money = ensureMoney(player)
	money.Value = amount
	saveDollars(player)
	return true, "Dolares actualizados.", money.Value
end

Players.PlayerAdded:Connect(ensureMoney)
Players.PlayerRemoving:Connect(saveDollars)
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveDollars(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(ensureMoney, player)
end