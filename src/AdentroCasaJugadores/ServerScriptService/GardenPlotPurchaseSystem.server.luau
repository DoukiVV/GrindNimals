--!strict
-- Compra de ampliaciones del jardín por jugador.
-- Las zonas base quedan desbloqueadas por defecto; los Terreno... se compran por nivel y dinero.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local gardensFolder = Workspace:WaitForChild("Jardin")
local plotStore = DataStoreService:GetDataStore("PlayerGardenPlots_v1")

--============================================================
-- XP POR ACCIONES DEL JUEGO
-- Busca el sistema central de nivel en el servidor.
-- Si AwardGameAction no existe todavía, usa AwardPlayerXP como respaldo.
--============================================================
local function awardGameActionXP(player, actionName, fallbackXP)
	if not player or player.Parent ~= Players then
		return
	end

	local actionEvent = ReplicatedStorage:FindFirstChild("AwardGameAction")
	if actionEvent and actionEvent:IsA("BindableEvent") then
		actionEvent:Fire(player, actionName)
		return
	end

	local xpEvent = ReplicatedStorage:FindFirstChild("AwardPlayerXP")
	if xpEvent and xpEvent:IsA("BindableEvent") then
		xpEvent:Fire(player, fallbackXP, actionName)
	end
end


local plotNoticeRemote = ReplicatedStorage:FindFirstChild("GardenPlotNotice")
if not (plotNoticeRemote and plotNoticeRemote:IsA("RemoteEvent")) then
	plotNoticeRemote = Instance.new("RemoteEvent")
	plotNoticeRemote.Name = "GardenPlotNotice"
	plotNoticeRemote.Parent = ReplicatedStorage
end

local DEFAULT_LEVEL = 1
local PLOT_RULES = {
	ZonaDePlantado = {
		Id = "BaseCultivos",
		DisplayName = "Cultivos gratis",
		DefaultUnlocked = true,
		RequiredLevel = 1,
		Cost = 0,
	},
	ZonaDePlantadoArboles = {
		Id = "BaseArboles",
		DisplayName = "Arboles gratis",
		DefaultUnlocked = true,
		RequiredLevel = 1,
		Cost = 0,
	},
	TerrenoCultivos = {
		Id = "CultivosNivel3",
		DisplayName = "Terreno de cultivos nivel 3",
		DefaultUnlocked = false,
		RequiredLevel = 3,
		Cost = 3000,
	},
	TerrenoArboles = {
		Id = "ArbolesNivel5",
		DisplayName = "Terreno de arboles nivel 5",
		DefaultUnlocked = false,
		RequiredLevel = 5,
		Cost = 5000,
	},
}

local ownedByUser: {[number]: {[string]: boolean}} = {}
local purchaseCooldown: {[number]: number} = {}

local function trim(value: any): string
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function ensureLeaderstats(player: Player): Folder
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
	return leaderstats :: Folder
end

local function findNumberValue(parent: Instance, names: {string}): NumberValue?
	for _, name in ipairs(names) do
		local value = parent:FindFirstChild(name)
		if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
			return value :: NumberValue
		end
	end
	return nil
end

local function moneyValue(player: Player): NumberValue
	local leaderstats = ensureLeaderstats(player)
	local value = findNumberValue(leaderstats, {"Dolares", "Dollars", "Cash", "Money", "Dinero"})
	if value then return value end
	local dollars = Instance.new("IntValue")
	dollars.Name = "Dolares"
	dollars.Value = 0
	dollars.Parent = leaderstats
	return dollars
end

local function levelValue(player: Player): NumberValue
	local leaderstats = ensureLeaderstats(player)
	local value = findNumberValue(leaderstats, {"Nivel", "Level"})
	if value then return value end
	local level = Instance.new("IntValue")
	level.Name = "Nivel"
	level.Value = DEFAULT_LEVEL
	level.Parent = leaderstats
	return level
end

local function gardenNumberFromInstance(instance: Instance): number?
	local current: Instance? = instance
	for _ = 1, 12 do
		if not current then break end
		local number = current.Name:match("^Jardin%s*(%d+)$")
		if number then return tonumber(number) end
		current = current.Parent
	end
	return nil
end

local function gardenForNumber(number: number?): Model?
	if not number then return nil end
	local garden = gardensFolder:FindFirstChild("Jardin " .. tostring(number))
		or gardensFolder:FindFirstChild("Jardin" .. tostring(number))
	return garden and garden:IsA("Model") and garden or nil
end

local function playerOwnsGarden(player: Player, gardenNumber: number?): boolean
	return typeof(gardenNumber) == "number" and tonumber(player:GetAttribute("HouseNumber")) == gardenNumber
end

local function keyForPlayer(player: Player): string
	return "Plots_" .. tostring(player.UserId)
end

local function defaultOwned(): {[string]: boolean}
	local owned = {}
	for _, rule in pairs(PLOT_RULES) do
		if rule.DefaultUnlocked then owned[rule.Id] = true end
	end
	return owned
end

local function loadOwned(player: Player): {[string]: boolean}
	local owned = defaultOwned()
	local ok, data = pcall(function()
		return plotStore:GetAsync(keyForPlayer(player))
	end)
	if ok and type(data) == "table" and type(data.Owned) == "table" then
		for plotId, value in pairs(data.Owned) do
			if value == true then owned[tostring(plotId)] = true end
		end
	end
	ownedByUser[player.UserId] = owned
	return owned
end

local function saveOwned(player: Player)
	local owned = ownedByUser[player.UserId]
	if not owned then return end
	task.spawn(function()
		local ok, err = pcall(function()
			plotStore:SetAsync(keyForPlayer(player), {
				Version = 1,
				UpdatedAt = os.time(),
				Owned = owned,
			})
		end)
		if not ok then warn("[GardenPlotPurchase] No se pudo guardar: " .. tostring(err)) end
	end)
end

local function setZoneVisual(zone: BasePart, unlocked: boolean)
	zone:SetAttribute("GardenPlotUnlocked", unlocked)
	zone.Transparency = unlocked and 0 or 0.45
	zone.CanCollide = unlocked
	zone.CanQuery = true
end

local function setSlotsUnlocked(zone: BasePart, unlocked: boolean)
	for _, child in ipairs(zone:GetChildren()) do
		local slot = child.Name == "SlotPlantar" and (child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart", true)) or nil
		if slot and slot:IsA("BasePart") then
			slot:SetAttribute("GardenPlotUnlocked", unlocked)
			slot.CanCollide = false
			slot.CanTouch = false
			local prompt = slot:FindFirstChild("GardenPlantPrompt") or slot:FindFirstChildOfClass("ProximityPrompt")
			if prompt and prompt:IsA("ProximityPrompt") and not slot:GetAttribute("GardenOccupied") then
				prompt.Enabled = unlocked
			end
		end
	end
end

local function notifyPlot(player: Player, kind: string, message: string)
	(plotNoticeRemote :: RemoteEvent):FireClient(player, kind, message)
end

local function plotKindText(rule: any): string
	return tostring(rule.Id):find("Arboles", 1, true) and "para arboles" or "de cultivos"
end

local function ensureSign(zone: BasePart, rule: any, unlocked: boolean, canBuy: boolean)
	local old = zone:FindFirstChild("GardenPlotPurchaseSign")
	if old then old:Destroy() end
	if unlocked then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "GardenPlotPurchaseSign"
	gui.Adornee = zone
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Size = UDim2.fromOffset(260, 76)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.35, 0)
	gui.Parent = zone

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 244, 205)
	label.TextStrokeColor3 = Color3.fromRGB(52, 35, 22)
	label.TextStrokeTransparency = 0.05
	if canBuy then
		label.Text = string.format("Comprar terreno\n$%d", rule.Cost)
	else
		label.Text = string.format("Debes ser nivel %d", rule.RequiredLevel)
	end
	label.Parent = gui
end

local function ensurePurchasePrompt(zone: BasePart, rule: any)
	local prompt = zone:FindFirstChild("GardenPlotPurchasePrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GardenPlotPurchasePrompt"
		prompt.Parent = zone
	end
	prompt.ActionText = "Comprar"
	prompt.ObjectText = "$" .. tostring(rule.Cost)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.6
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	return prompt :: ProximityPrompt
end

local function applyZoneForPlayer(player: Player, zone: BasePart, rule: any)
	local gardenNumber = gardenNumberFromInstance(zone)
	local owned = ownedByUser[player.UserId] or loadOwned(player)
	local unlocked = rule.DefaultUnlocked or owned[rule.Id] == true
	local canBuy = levelValue(player).Value >= rule.RequiredLevel
	setZoneVisual(zone, unlocked)
	setSlotsUnlocked(zone, unlocked)
	ensureSign(zone, rule, unlocked, canBuy)

	local prompt = zone:FindFirstChild("GardenPlotPurchasePrompt")
	if unlocked then
		if prompt then prompt:Destroy() end
		return
	end

	local purchasePrompt = ensurePurchasePrompt(zone, rule)
	purchasePrompt.Enabled = canBuy
	if purchasePrompt:GetAttribute("Connected") then return end
	purchasePrompt:SetAttribute("Connected", true)
	purchasePrompt.Triggered:Connect(function(triggeringPlayer)
		if not playerOwnsGarden(triggeringPlayer, gardenNumber) then return end
		local now = os.clock()
		if now - (purchaseCooldown[triggeringPlayer.UserId] or 0) < 0.8 then return end
		purchaseCooldown[triggeringPlayer.UserId] = now

		local currentOwned = ownedByUser[triggeringPlayer.UserId] or loadOwned(triggeringPlayer)
		if currentOwned[rule.Id] == true then
			applyZoneForPlayer(triggeringPlayer, zone, rule)
			return
		end

		local level = levelValue(triggeringPlayer)
		if level.Value < rule.RequiredLevel then
			notifyPlot(triggeringPlayer, "error", string.format("Debes ser nivel %d", rule.RequiredLevel))
			return
		end
		local money = moneyValue(triggeringPlayer)
		if money.Value < rule.Cost then
			notifyPlot(triggeringPlayer, "error", "Dinero insuficiente")
			return
		end

		money.Value -= rule.Cost
		currentOwned[rule.Id] = true
		ownedByUser[triggeringPlayer.UserId] = currentOwned
		saveOwned(triggeringPlayer)
		applyGardenForPlayer(triggeringPlayer)
		awardGameActionXP(triggeringPlayer, "BuyGardenPlot", 20)
		notifyPlot(triggeringPlayer, "success", "Nuevo terreno comprado")
	end)
end

function applyGardenForPlayer(player: Player)
	local gardenNumber = tonumber(player:GetAttribute("HouseNumber"))
	local garden = gardenForNumber(gardenNumber)
	if not garden then return end
	for zoneName, rule in pairs(PLOT_RULES) do
		local zone = garden:FindFirstChild(zoneName, true)
		if zone and zone:IsA("BasePart") then
			applyZoneForPlayer(player, zone, rule)
		end
	end
end

local function watchPlayer(player: Player)
	local level = levelValue(player)
	moneyValue(player)
	loadOwned(player)
	level.Changed:Connect(function()
		task.defer(function() applyGardenForPlayer(player) end)
	end)
	player:GetAttributeChangedSignal("HouseNumber"):Connect(function()
		task.defer(function() applyGardenForPlayer(player) end)
	end)
	player:GetAttributeChangedSignal("InteriorSlotNumber"):Connect(function()
		task.defer(function() applyGardenForPlayer(player) end)
	end)
	task.spawn(function()
		for _ = 1, 80 do
			if not player.Parent then return end
			if tonumber(player:GetAttribute("HouseNumber")) then
				applyGardenForPlayer(player)
				return
			end
			task.wait(0.25)
		end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	ownedByUser[player.UserId] = nil
	purchaseCooldown[player.UserId] = nil
end)

print("[GardenPlotPurchase] Sistema activo: terrenos por nivel y dinero.")
