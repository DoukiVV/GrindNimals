--============================================================
-- ADMIN DIAMONDS CLIENT
-- Ubicacion:
-- StarterPlayer > StarterPlayerScripts > AdminDiamondsClient
-- Tipo: LocalScript
--
-- NO reemplaza tu AdminDevMenuClient_PRO.
-- Se agrega automaticamente dentro de:
-- AdminDevMenu > Panel > Content > JugadorPage
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AdminSetDiamonds =
	ReplicatedStorage:WaitForChild(
		"AdminSetDiamonds",
		20
	)

local AdminAddDiamonds =
	ReplicatedStorage:WaitForChild(
		"AdminAddDiamonds",
		20
	)

if not AdminSetDiamonds or not AdminAddDiamonds then
	warn("[AdminDiamondsClient] Faltan remotes.")
	return
end

-- Tu menu privado actual solo carga para estas cuentas.
local ADMIN_USER_IDS = {
	[2763635937] = true,
	[1075477843] = true,
	[11621988902] = true,
	[2567510148] = true,
}

if ADMIN_USER_IDS[player.UserId] ~= true then
	return
end

local C = {
	CARD = Color3.fromRGB(30, 35, 43),
	CARD2 = Color3.fromRGB(38, 44, 54),
	STROKE = Color3.fromRGB(66, 77, 92),
	BLUE = Color3.fromRGB(45, 137, 245),
	GREEN = Color3.fromRGB(55, 171, 91),
	RED = Color3.fromRGB(202, 76, 84),
	TEXT = Color3.fromRGB(245, 248, 255),
	SUB = Color3.fromRGB(165, 177, 193),
}

local function corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 7)
	c.Parent = object
end

local function stroke(object)
	local s = Instance.new("UIStroke")
	s.Color = C.STROKE
	s.Thickness = 1
	s.Transparency = 0.25
	s.Parent = object
end

local function pad(object, left, right, top, bottom)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left or 0)
	p.PaddingRight = UDim.new(0, right or left or 0)
	p.PaddingTop = UDim.new(0, top or 0)
	p.PaddingBottom = UDim.new(0, bottom or top or 0)
	p.Parent = object
end

local function findAdminMenu()
	-- Menu actual del proyecto.
	local gui = playerGui:FindFirstChild("AdminDevMenu")

	if gui then
		return gui
	end

	-- Compatibilidad con alguna version PRO V2 anterior.
	gui = playerGui:FindFirstChild("AdminDevMenuV2")

	if gui then
		return gui
	end

	local started = os.clock()

	repeat
		gui =
			playerGui:FindFirstChild("AdminDevMenu")
			or playerGui:FindFirstChild("AdminDevMenuV2")

		if gui then
			return gui
		end

		task.wait(0.1)
	until os.clock() - started >= 20

	return nil
end

local gui = findAdminMenu()

if not gui then
	warn("[AdminDiamondsClient] No encontre AdminDevMenu.")
	return
end

local panel = gui:FindFirstChild("Panel")

if not panel then
	warn("[AdminDiamondsClient] No encontre Panel.")
	return
end

local content =
	panel:FindFirstChild("Content")

if not content then
	warn("[AdminDiamondsClient] No encontre Content.")
	return
end

local playerPage =
	content:FindFirstChild("JugadorPage")
	or content:FindFirstChild("Jugador")

if not playerPage then
	warn("[AdminDiamondsClient] No encontre JugadorPage.")
	return
end

if playerPage:FindFirstChild("AdminDiamondsSection") then
	return
end

--============================================================
-- SECCION
--============================================================

local section = Instance.new("Frame")
section.Name = "AdminDiamondsSection"
section.BackgroundColor3 = C.CARD
section.BorderSizePixel = 0
section.Size = UDim2.new(1, 0, 0, 10)
section.AutomaticSize = Enum.AutomaticSize.Y
section.LayoutOrder = 50
section.Parent = playerPage

corner(section, 9)
stroke(section)
pad(section, 12, 12, 10, 12)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = section

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 20)
title.Font = Enum.Font.GothamBold
title.Text = "Diamantes"
title.TextColor3 = C.TEXT
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = section

local current = Instance.new("TextLabel")
current.BackgroundTransparency = 1
current.Size = UDim2.new(1, 0, 0, 20)
current.Font = Enum.Font.Gotham
current.Text = "Actual: cargando..."
current.TextColor3 = C.SUB
current.TextSize = 12
current.TextXAlignment = Enum.TextXAlignment.Left
current.Parent = section

local input = Instance.new("TextBox")
input.Name = "DiamondAmount"
input.ClearTextOnFocus = false
input.BackgroundColor3 = C.CARD2
input.BorderSizePixel = 0
input.Size = UDim2.new(1, 0, 0, 34)
input.Font = Enum.Font.Gotham
input.PlaceholderText = "Cantidad de diamantes"
input.PlaceholderColor3 = C.SUB
input.Text = ""
input.TextColor3 = C.TEXT
input.TextSize = 13
input.Parent = section

corner(input, 7)
stroke(input)

local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.Size = UDim2.new(1, 0, 0, 36)
row.Parent = section

local setButton = Instance.new("TextButton")
setButton.AutoButtonColor = false
setButton.BackgroundColor3 = C.BLUE
setButton.BorderSizePixel = 0
setButton.Position = UDim2.new(0, 0, 0, 0)
setButton.Size = UDim2.new(0.5, -4, 1, 0)
setButton.Font = Enum.Font.GothamBold
setButton.Text = "Poner exacto"
setButton.TextColor3 = C.TEXT
setButton.TextSize = 13
setButton.Parent = row

corner(setButton, 7)
stroke(setButton)

local addButton = Instance.new("TextButton")
addButton.AutoButtonColor = false
addButton.BackgroundColor3 = C.GREEN
addButton.BorderSizePixel = 0
addButton.Position = UDim2.new(0.5, 4, 0, 0)
addButton.Size = UDim2.new(0.5, -4, 1, 0)
addButton.Font = Enum.Font.GothamBold
addButton.Text = "Agregar"
addButton.TextColor3 = C.TEXT
addButton.TextSize = 13
addButton.Parent = row

corner(addButton, 7)
stroke(addButton)

--============================================================
-- DIAMANTES ACTUALES
--============================================================

local diamondConnection = nil

local function formatNumber(value)
	value = math.max(
		0,
		math.floor(tonumber(value) or 0)
	)

	local text = tostring(value)

	while true do
		local nextText, count =
			text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")

		text = nextText

		if count == 0 then
			break
		end
	end

	return text
end

local function findDiamondValue()
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats then
		local value = leaderstats:FindFirstChild("Diamantes")

		if value
			and (
				value:IsA("IntValue")
					or value:IsA("NumberValue")
			)
		then
			return value
		end
	end

	return nil
end

local function refreshCurrent()
	local value = findDiamondValue()

	if value then
		current.Text =
			"Actual: "
			.. formatNumber(value.Value)
			.. " Diamantes"
	else
		current.Text = "Actual: 0 Diamantes"
	end
end

local function bindValue()
	if diamondConnection then
		diamondConnection:Disconnect()
		diamondConnection = nil
	end

	local value = findDiamondValue()

	if value then
		diamondConnection =
			value:GetPropertyChangedSignal("Value"):Connect(
				refreshCurrent
			)
	end

	refreshCurrent()
end

local leaderstats =
	player:FindFirstChild("leaderstats")
	or player:WaitForChild("leaderstats", 20)

if leaderstats then
	leaderstats.ChildAdded:Connect(function(child)
		if child.Name == "Diamantes" then
			task.defer(bindValue)
		end
	end)
end

bindValue()

--============================================================
-- INPUT / REMOTES
--============================================================

input:GetPropertyChangedSignal("Text"):Connect(function()
	local cleaned =
		tostring(input.Text):gsub("[^%d]", "")

	if input.Text ~= cleaned then
		input.Text = cleaned
	end
end)

local function invoke(remote, amount)
	local ok, success, message, value =
		pcall(function()
			return remote:InvokeServer(amount)
		end)

	if not ok then
		return false, "Error al contactar servidor.", nil
	end

	return success, message, value
end

setButton.Activated:Connect(function()
	local amount = tonumber(input.Text)

	if not amount then
		current.Text = "Escribe una cantidad valida."
		current.TextColor3 = C.RED
		return
	end

	local success, message, value =
		invoke(AdminSetDiamonds, amount)

	if success then
		current.TextColor3 = C.SUB
		current.Text =
			"Actual: "
			.. formatNumber(value)
			.. " Diamantes"
	else
		current.TextColor3 = C.RED
		current.Text = tostring(message)
	end
end)

addButton.Activated:Connect(function()
	local amount = tonumber(input.Text)

	if not amount or amount <= 0 then
		current.Text = "Escribe una cantidad mayor a 0."
		current.TextColor3 = C.RED
		return
	end

	local success, message, value =
		invoke(AdminAddDiamonds, amount)

	if success then
		current.TextColor3 = C.SUB
		current.Text =
			"Actual: "
			.. formatNumber(value)
			.. " Diamantes"
	else
		current.TextColor3 = C.RED
		current.Text = tostring(message)
	end
end)
