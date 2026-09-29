local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFAULT_LEVEL = 1
local MAX_LEVEL = 999999
local STORE_NAME = "PlayerLevelV2"
local LEGACY_STORE_NAME = "PlayerLevelV1"
local SET_REMOTE_NAME = "AdminSetLevel"
local ADD_REMOTE_NAME = "AdminAddLevel"
local NOTICE_REMOTE_NAME = "AdminLevelUpNotice"
local XP_EVENT_NAME = "AwardPlayerXP"
local ACTION_EVENT_NAME = "AwardGameAction"

-- XP centralizado por acciones reales del juego.
local ACTION_XP = {
	PlantCrop = 4,
	HarvestCrop = 8,
	HarvestTreeFruit = 10,
	BuyGardenPlot = 20,
	ChopTree = 15,
	HatchEgg = 25,
	PetUpgrade = 40,
	CompleteTrade = 15,
	BuyFurniture = 3,
}

-- Evita granjas de XP por spam.
local ACTION_COOLDOWN = {
	PlantCrop = 0.75,
	HarvestCrop = 0.40,
	HarvestTreeFruit = 0.40,
	BuyGardenPlot = 2,
	ChopTree = 1,
	HatchEgg = 2,
	PetUpgrade = 2,
	CompleteTrade = 300, -- 5 minutos por jugador
	BuyFurniture = 0.75,
}

local actionLastAt = {}

local levelStore = DataStoreService:GetDataStore(STORE_NAME)
local legacyLevelStore = DataStoreService:GetDataStore(LEGACY_STORE_NAME)

local ADMIN_USER_IDS = {
	[2763635937] = true, -- Tú
	[1075477843] = true, -- Tu compañero
}

local function isNumericValue(value)
	return value and (value:IsA("IntValue") or value:IsA("NumberValue"))
end

local function getOrCreateLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	return leaderstats
end

local function findLevelValue(player)
	local leaderstats = getOrCreateLeaderstats(player)
	local value = leaderstats:FindFirstChild("Nivel") or leaderstats:FindFirstChild("Level")
	if not isNumericValue(value) then
		value = Instance.new("IntValue")
		value.Name = "Nivel"
		value.Value = DEFAULT_LEVEL
		value.Parent = leaderstats
	end
	return value
end

local function findXPValue(player)
	local leaderstats = getOrCreateLeaderstats(player)
	local value = leaderstats:FindFirstChild("XP") or leaderstats:FindFirstChild("Experiencia")
	if not isNumericValue(value) then
		value = Instance.new("IntValue")
		value.Name = "XP"
		value.Value = 0
		value.Parent = leaderstats
	end
	return value
end

local function clampLevel(level)
	level = math.floor(tonumber(level) or DEFAULT_LEVEL)
	return math.clamp(level, DEFAULT_LEVEL, MAX_LEVEL)
end

local function xpNeededForLevel(level)
	level = clampLevel(level)
	return 100 + (level - 1) * 50
end

local function setLevelAttributes(player)
	local levelValue = findLevelValue(player)
	local xpValue = findXPValue(player)
	player:SetAttribute("PlayerLevel", levelValue.Value)
	player:SetAttribute("PlayerXP", xpValue.Value)
	player:SetAttribute("PlayerXPNeeded", xpNeededForLevel(levelValue.Value))
end

local function loadData(player)
	local level = DEFAULT_LEVEL
	local xp = 0
	if not RunService:IsStudio() then
		local ok, stored = pcall(function()
			return levelStore:GetAsync(tostring(player.UserId))
		end)
		if ok and typeof(stored) == "table" then
			level = clampLevel(stored.level)
			xp = math.max(0, math.floor(tonumber(stored.xp) or 0))
		elseif ok and typeof(stored) == "number" then
			level = clampLevel(stored)
		else
			local legacyOk, legacyStored = pcall(function()
				return legacyLevelStore:GetAsync(tostring(player.UserId))
			end)
			if legacyOk then level = clampLevel(legacyStored) end
		end
	end
	return level, xp
end

local function saveLevel(player)
	local levelValue = findLevelValue(player)
	local xpValue = findXPValue(player)
	if RunService:IsStudio() then return end
	pcall(function()
		levelStore:SetAsync(tostring(player.UserId), {
			level = clampLevel(levelValue.Value),
			xp = math.max(0, math.floor(tonumber(xpValue.Value) or 0)),
		})
	end)
end

local function isAdmin(player)
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return ADMIN_USER_IDS[player.UserId] == true
end

local function ensureRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local noticeRemote = ReplicatedStorage:FindFirstChild(NOTICE_REMOTE_NAME)
if noticeRemote and not noticeRemote:IsA("RemoteEvent") then
	noticeRemote:Destroy()
	noticeRemote = nil
end
if not noticeRemote then
	noticeRemote = Instance.new("RemoteEvent")
	noticeRemote.Name = NOTICE_REMOTE_NAME
	noticeRemote.Parent = ReplicatedStorage
end

local xpEvent = ReplicatedStorage:FindFirstChild(XP_EVENT_NAME)
if xpEvent and not xpEvent:IsA("BindableEvent") then
	xpEvent:Destroy()
	xpEvent = nil
end
if not xpEvent then
	xpEvent = Instance.new("BindableEvent")
	xpEvent.Name = XP_EVENT_NAME
	xpEvent.Parent = ReplicatedStorage
end

local actionEvent = ReplicatedStorage:FindFirstChild(ACTION_EVENT_NAME)
if actionEvent and not actionEvent:IsA("BindableEvent") then
	actionEvent:Destroy()
	actionEvent = nil
end
if not actionEvent then
	actionEvent = Instance.new("BindableEvent")
	actionEvent.Name = ACTION_EVENT_NAME
	actionEvent.Parent = ReplicatedStorage
end

local setRemote = ensureRemote(SET_REMOTE_NAME)
local addRemote = ensureRemote(ADD_REMOTE_NAME)

local function applyLevel(player, newLevel)
	local levelValue = findLevelValue(player)
	local previous = clampLevel(levelValue.Value)
	newLevel = clampLevel(newLevel)
	levelValue.Value = newLevel
	setLevelAttributes(player)
	if newLevel > previous then
		noticeRemote:FireClient(player, newLevel)
	end
	return newLevel
end

local function awardXP(player, amount, reason)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not player or not player.Parent then return end
	local levelValue = findLevelValue(player)
	local xpValue = findXPValue(player)
	xpValue.Value += amount
	while xpValue.Value >= xpNeededForLevel(levelValue.Value) and levelValue.Value < MAX_LEVEL do
		xpValue.Value -= xpNeededForLevel(levelValue.Value)
		applyLevel(player, levelValue.Value + 1)
	end
	setLevelAttributes(player)

	if reason then
		player:SetAttribute("LastXPReason", tostring(reason))
	end
end

xpEvent.Event:Connect(awardXP)

actionEvent.Event:Connect(function(player, actionName, multiplier)
	if not player or player.Parent ~= Players then
		return
	end

	actionName = tostring(actionName or "")
	local baseXP = ACTION_XP[actionName]
	if not baseXP then
		warn("[GranjaLevel] Acción XP desconocida: " .. actionName)
		return
	end

	local now = os.clock()
	local perPlayer = actionLastAt[player]
	if not perPlayer then
		perPlayer = {}
		actionLastAt[player] = perPlayer
	end

	local nextAllowed = perPlayer[actionName] or 0
	if now < nextAllowed then
		return
	end

	perPlayer[actionName] = now + (ACTION_COOLDOWN[actionName] or 0)

	multiplier = math.clamp(
		math.floor(tonumber(multiplier) or 1),
		1,
		10
	)

	awardXP(player, baseXP * multiplier, actionName)
end)

setRemote.OnServerInvoke = function(player, requestedLevel)
	if not isAdmin(player) then
		return false, "No tienes permiso para usar esta opcion.", nil
	end
	local newLevel = tonumber(requestedLevel)
	if not newLevel then
		return false, "Nivel invalido.", nil
	end
	findXPValue(player).Value = 0
	return true, "Nivel actualizado.", applyLevel(player, newLevel)
end

addRemote.OnServerInvoke = function(player, amount)
	if not isAdmin(player) then
		return false, "No tienes permiso para usar esta opcion.", nil
	end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false, "Cantidad invalida.", nil
	end
	awardXP(player, amount)
	return true, "XP agregado.", findLevelValue(player).Value
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("SuppressLevelUpNotice", true)

	local levelValue = findLevelValue(player)
	local xpValue = findXPValue(player)
	local level, xp = loadData(player)
	levelValue.Value = level
	xpValue.Value = xp
	setLevelAttributes(player)

	task.defer(function()
		if player.Parent == Players then
			player:SetAttribute("SuppressLevelUpNotice", false)
		end
	end)
end)

Players.PlayerRemoving:Connect(saveLevel)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveLevel(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		local levelValue = findLevelValue(player)
		local xpValue = findXPValue(player)
		if levelValue.Value <= 0 then
			local level, xp = loadData(player)
			levelValue.Value = level
			xpValue.Value = xp
		end
		setLevelAttributes(player)
	end)
end
