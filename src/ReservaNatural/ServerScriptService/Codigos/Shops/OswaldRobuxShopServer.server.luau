--============================================================
-- OSWALD ROBUX SHOP SERVER
-- Ubicacion: ServerScriptService > OswaldRobuxShopServer
-- Tipo: Script
--
-- IMPORTANTE:
-- Este script NO usa MarketplaceService.ProcessReceipt.
-- El ProcessReceipt se integra en BrizabelleEggServer para que
-- no existan dos manejadores y no se rompa la compra instantanea
-- del huevo.
--============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PRODUCTS = {
	[3709750798] = {dollars = 750, robux = 150},
	[3709750847] = {dollars = 2500, robux = 500},
	[3709750869] = {dollars = 7500, robux = 1500},
	[3709750906] = {dollars = 55000, robux = 5000},
}

local folder = ReplicatedStorage:FindFirstChild("OswaldRobuxShopSystem")

if not folder then
	folder = Instance.new("Folder")
	folder.Name = "OswaldRobuxShopSystem"
	folder.Parent = ReplicatedStorage
end

local purchaseResult = folder:FindFirstChild("PurchaseResult")
if purchaseResult and not purchaseResult:IsA("RemoteEvent") then
	purchaseResult:Destroy()
	purchaseResult = nil
end

if not purchaseResult then
	purchaseResult = Instance.new("RemoteEvent")
	purchaseResult.Name = "PurchaseResult"
	purchaseResult.Parent = folder
end

local getProducts = folder:FindFirstChild("GetProducts")
if getProducts and not getProducts:IsA("RemoteFunction") then
	getProducts:Destroy()
	getProducts = nil
end

if not getProducts then
	getProducts = Instance.new("RemoteFunction")
	getProducts.Name = "GetProducts"
	getProducts.Parent = folder
end

getProducts.OnServerInvoke = function()
	local result = {}

	for productId, info in pairs(PRODUCTS) do
		table.insert(result, {
			productId = productId,
			dollars = info.dollars,
			robux = info.robux,
		})
	end

	table.sort(result, function(a, b)
		return a.dollars < b.dollars
	end)

	return result
end

local function findOswald()
	local interiores = Workspace:FindFirstChild("Interiores")
	local bank = interiores and interiores:FindFirstChild("Interior banco")

	if not bank then
		return nil
	end

	local direct = bank:FindFirstChild("Oswald")
	if direct and direct:IsA("Model") then
		return direct
	end

	for _, object in ipairs(bank:GetDescendants()) do
		if object:IsA("Model") and object.Name == "Oswald" then
			return object
		end
	end

	return nil
end

local function ensurePrompt()
	local oswald = findOswald()
	if not oswald then
		return false
	end

	local root = oswald:FindFirstChild("HumanoidRootPart")
		or oswald.PrimaryPart
		or oswald:FindFirstChildWhichIsA("BasePart")

	if not root then
		return false
	end

	local prompt = root:FindFirstChild("OswaldBankPrompt")

	if not prompt then
		-- Reutiliza uno que ya exista dentro de Oswald.
		prompt = oswald:FindFirstChildWhichIsA("ProximityPrompt", true)

		if prompt then
			prompt.Name = "OswaldBankPrompt"
		else
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "OswaldBankPrompt"
			prompt.Parent = root
		end
	end

	prompt.ActionText = "Hablar"
	prompt.ObjectText = "Oswald"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = math.max(prompt.HoldDuration, 0.55)
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 14)
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true

	return true
end

task.spawn(function()
	for attempt = 1, 60 do
		if ensurePrompt() then
			return
		end

		if attempt == 1 or attempt % 10 == 0 then
			warn("[OswaldRobuxShop] Esperando a Oswald...")
		end

		task.wait(0.5)
	end
end)