--============================================================
-- BANK NPC NAMES + PROMPTS SERVER V3
-- Ubicacion: ServerScriptService > BankNpcHideNamesServer
-- Tipo: Script
--
-- CORRIGE DOS COSAS:
-- 1) Oculta los nombres flotantes reales de los NPC.
-- 2) Si un NPC tiene un ProximityPrompt copiado con nombre/ texto
--    de William, lo corrige al nombre del NPC correspondiente.
--
-- NPC:
-- Damian
-- El cajero del Oxxo
-- Oliver
-- Oswald
-- William
--============================================================

local Workspace = game:GetService("Workspace")

local NPC_CONFIG = {
	["damian"] = {
		displayName = "Damian",
		promptName = "DamianBankPrompt",
	},
	["wiwin"] = {
		displayName = "Wiwin",
		promptName = "WiwinBankPrompt",
	},
	["oliver"] = {
		displayName = "Oliver",
		promptName = "OliverBankPrompt",
	},
	["oswald"] = {
		displayName = "Oswald",
		promptName = "OswaldBankPrompt",
	},
	["william"] = {
		displayName = "William",
		promptName = "WilliamBankPrompt",
	},
}

local function normalize(value)
	local text = tostring(value or ""):lower()

	text = text:gsub("á", "a")
	text = text:gsub("é", "e")
	text = text:gsub("í", "i")
	text = text:gsub("ó", "o")
	text = text:gsub("ú", "u")
	text = text:gsub("ñ", "n")
	text = text:gsub("[%s_%-%.]+", "")

	return text
end

local function getBank()
	local interiores = Workspace:FindFirstChild("Interiores")
	if not interiores then
		return nil
	end

	return interiores:FindFirstChild("Interior banco")
end

local function getConfig(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	return NPC_CONFIG[normalize(model.Name)]
end

local function getBankNpcFromDescendant(object)
	local bank = getBank()
	if not bank or not object then
		return nil
	end

	local current = object

	while current and current ~= bank do
		if current:IsA("Model") and getConfig(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function hideHumanoidNames(model)
	-- Busca TODOS los Humanoid dentro del NPC, no solo hijos directos.
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Humanoid") then
			-- La combinacion mas fuerte para evitar el nombre default.
			object.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			object.NameDisplayDistance = 0
			object.HealthDisplayDistance = 0

			-- Espacio invisible: por si otro script reactiva DisplayDistanceType.
			object.DisplayName = " "
		end
	end
end

local function hideNameBillboards(model)
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BillboardGui") then
			-- Los ProximityPrompt personalizados NO son BillboardGui dentro
			-- del NPC; el sistema StyledProximityPrompts crea su GUI en PlayerGui.
			object.Enabled = false
		end
	end
end

local function getMainPrompt(model)
	-- Primero revisa HumanoidRootPart.
	local root = model:FindFirstChild("HumanoidRootPart")

	if root then
		local prompt = root:FindFirstChildWhichIsA("ProximityPrompt")

		if prompt then
			return prompt
		end
	end

	-- Fallback: cualquier prompt dentro del NPC.
	return model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function fixPrompt(model)
	local config = getConfig(model)
	if not config then
		return
	end

	local prompt = getMainPrompt(model)

	-- William SI debe tener prompt porque abre el banco.
	if not prompt and config.promptName == "WilliamBankPrompt" then
		local root = model:FindFirstChild("HumanoidRootPart")
			or model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart")

		if root then
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = root
		end
	end

	-- Para Damian/Oliver/etc. no creamos una interaccion nueva si
	-- todavia no tienen una. Pero si ya existe, corregimos su nombre.
	if not prompt then
		return
	end

	prompt.Name = config.promptName
	prompt.ActionText = "Hablar"
	prompt.ObjectText = config.displayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = math.max(prompt.HoldDuration, 0.45)
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 12)
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
end

local function fixNpc(model)
	local config = getConfig(model)
	if not config then
		return
	end

	hideHumanoidNames(model)
	hideNameBillboards(model)
	fixPrompt(model)
end

local function setupAll()
	local bank = getBank()

	if not bank then
		return false
	end

	for _, object in ipairs(bank:GetDescendants()) do
		if object:IsA("Model") and getConfig(object) then
			fixNpc(object)
		end
	end

	-- Tambien revisa hijos directos por si el modelo aun no tiene descendants.
	for _, child in ipairs(bank:GetChildren()) do
		if child:IsA("Model") and getConfig(child) then
			fixNpc(child)
		end
	end

	return true
end

-- Carga inicial.
task.spawn(function()
	for attempt = 1, 60 do
		if setupAll() then
			break
		end

		if attempt == 1 or attempt % 10 == 0 then
			warn("[BankNpcNames] Esperando Interior banco...")
		end

		task.wait(0.5)
	end
end)

-- Si se agrega/reconstruye algo dentro de un NPC, vuelve a corregirlo.
Workspace.DescendantAdded:Connect(function(object)
	task.defer(function()
		local npc = getBankNpcFromDescendant(object)

		if npc then
			fixNpc(npc)
		elseif object:IsA("Model") and getConfig(object) then
			fixNpc(object)
		end
	end)
end)

-- Refuerzo fuerte porque algunos scripts pueden volver a poner DisplayName.
task.spawn(function()
	while true do
		task.wait(0.5)

		local bank = getBank()

		if bank then
			for _, object in ipairs(bank:GetDescendants()) do
				if object:IsA("Model") and getConfig(object) then
					hideHumanoidNames(object)
					hideNameBillboards(object)
				end
			end

			for _, child in ipairs(bank:GetChildren()) do
				if child:IsA("Model") and getConfig(child) then
					hideHumanoidNames(child)
					hideNameBillboards(child)
				end
			end
		end
	end
end)