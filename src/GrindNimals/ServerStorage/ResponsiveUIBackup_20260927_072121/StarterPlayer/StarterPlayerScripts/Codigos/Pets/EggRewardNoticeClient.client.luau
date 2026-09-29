local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BrizabelleEggSystem")
local EggNotify = remotes:WaitForChild("EggNotify")
local petViews = ReplicatedStorage:WaitForChild("MascotasView")

local FONT = Enum.Font.FredokaOne
local FOOD_ALERT_IMAGE = "rbxassetid://119551068943459"
local RARITY_COLORS = {
	["Comun"] = Color3.fromRGB(190, 190, 190),
	["Poco comun"] = Color3.fromRGB(42, 224, 80),
	["Raro"] = Color3.fromRGB(63, 128, 255),
	["Epico"] = Color3.fromRGB(168, 83, 255),
	["Legendario"] = Color3.fromRGB(255, 205, 55),
}

-- Texto que se mostrará específicamente al mejorar una mascota.
-- Los nombres internos del sistema se mantienen iguales para no romper nada.
local UPGRADE_RARITY_DISPLAY = {
	["Comun"] = "Común",
	["Poco comun"] = "Raro",
	["Raro"] = "Muy raro",
	["Epico"] = "Épico",
	["Legendario"] = "Legendario",
}

local UPGRADE_VARIANT_FOLDERS = {
	["Comun"] = "Mascotas pañuelos grises",
	["Poco comun"] = "Mascotas pañuelos verdes",
	["Raro"] = "Mascotas pañuelos azul",
	["Epico"] = "Mascotas pañuelos morado",
	["Legendario"] = "Mascotas pañuelos dorado",
}

local PET_NAME_ALIASES = {
	["Pajarillo"] = "Perico",
	["PezDorado"] = "Pez dorado",
	["Oveja de rosario"] = "Oveja",
}

local function normalizePetName(value)
	local text = tostring(value or ""):lower()
	text = text:gsub("á","a"):gsub("é","e"):gsub("í","i"):gsub("ó","o"):gsub("ú","u"):gsub("ñ","n")
	text = text:gsub("[%s_%-]+","")
	return text
end

local function canonicalPetName(name)
	name = tostring(name or "")
	return PET_NAME_ALIASES[name] or name
end

local gui = playerGui:FindFirstChild("EggRewardNoticeGui")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "EggRewardNoticeGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Parent = playerGui
end

local holder = gui:FindFirstChild("RewardHolder")
if not holder then
	holder = Instance.new("Frame")
	holder.Name = "RewardHolder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.42)
	holder.Size = UDim2.fromOffset(560, 270)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Name = "RewardScale"
	scale.Scale = 0.3
	scale.Parent = holder

	local modelGlow = Instance.new("Frame")
	modelGlow.Name = "ModelGlow"
	modelGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	modelGlow.Position = UDim2.fromScale(0.5, 0.52)
	modelGlow.Size = UDim2.fromOffset(172, 172)
	modelGlow.BackgroundColor3 = Color3.fromRGB(255, 213, 80)
	modelGlow.BackgroundTransparency = 0.2
	modelGlow.Parent = holder
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = modelGlow
	local glowStroke = Instance.new("UIStroke")
	glowStroke.Name = "GlowStroke"
	glowStroke.Thickness = 5
	glowStroke.Color = Color3.fromRGB(95, 55, 16)
	glowStroke.Parent = modelGlow

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "PetViewport"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.52)
	viewport.Size = UDim2.fromOffset(190, 190)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Parent = holder

	local titleShadow = Instance.new("TextLabel")
	titleShadow.Name = "TitleShadow"
	titleShadow.BackgroundTransparency = 1
	titleShadow.Position = UDim2.fromOffset(4, 5)
	titleShadow.Size = UDim2.new(1, 0, 0, 70)
	titleShadow.Font = FONT
	titleShadow.TextScaled = true
	titleShadow.TextColor3 = Color3.fromRGB(59, 31, 10)
	titleShadow.TextStrokeColor3 = Color3.fromRGB(59, 31, 10)
	titleShadow.TextStrokeTransparency = 0
	titleShadow.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 70)
	title.Font = FONT
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 249, 219)
	title.TextStrokeColor3 = Color3.fromRGB(79, 42, 13)
	title.TextStrokeTransparency = 0
	title.Parent = holder

	local rarityShadow = Instance.new("TextLabel")
	rarityShadow.Name = "RarityShadow"
	rarityShadow.BackgroundTransparency = 1
	rarityShadow.Position = UDim2.new(0, 4, 1, -59)
	rarityShadow.Size = UDim2.new(1, 0, 0, 46)
	rarityShadow.Font = FONT
	rarityShadow.TextScaled = true
	rarityShadow.TextColor3 = Color3.fromRGB(59, 31, 10)
	rarityShadow.TextStrokeTransparency = 1
	rarityShadow.Parent = holder

	local rarity = Instance.new("TextLabel")
	rarity.Name = "Rarity"
	rarity.BackgroundTransparency = 1
	rarity.Position = UDim2.new(0, 0, 1, -64)
	rarity.Size = UDim2.new(1, 0, 0, 46)
	rarity.Font = FONT
	rarity.TextScaled = true
	rarity.TextStrokeColor3 = Color3.fromRGB(74, 42, 16)
	rarity.TextStrokeTransparency = 0
	rarity.Parent = holder
end

local scale = holder:WaitForChild("RewardScale")
local glow = holder:WaitForChild("ModelGlow")
local viewport = holder:WaitForChild("PetViewport")
local title = holder:WaitForChild("Title")
local titleShadow = holder:WaitForChild("TitleShadow")
local rarityLabel = holder:WaitForChild("Rarity")
local rarityShadow = holder:WaitForChild("RarityShadow")

local topNotice = gui:FindFirstChild("TopEggNotice")
if not topNotice then
	topNotice = Instance.new("TextLabel")
	topNotice.Name = "TopEggNotice"
	topNotice.AnchorPoint = Vector2.new(0.5, 0.5)
	topNotice.Position = UDim2.fromScale(0.5, 0.18)
	topNotice.Size = UDim2.fromOffset(780, 110)
	topNotice.BackgroundTransparency = 1
	topNotice.Font = FONT
	topNotice.TextScaled = false
	topNotice.TextSize = 54
	topNotice.TextWrapped = true
	topNotice.TextColor3 = Color3.fromRGB(255, 249, 219)
	topNotice.TextStrokeColor3 = Color3.fromRGB(79, 42, 13)
	topNotice.TextStrokeTransparency = 0
	topNotice.TextTransparency = 1
	topNotice.Visible = true
	topNotice.ZIndex = 50
	topNotice.Parent = gui
end
local topNoticeScale = topNotice:FindFirstChild("TopNoticeScale") or Instance.new("UIScale")
topNoticeScale.Name = "TopNoticeScale"
topNoticeScale.Parent = topNotice

topNotice.TextScaled = false
topNotice.TextSize = 54
topNotice.TextWrapped = true

local topNoticeSub = gui:FindFirstChild("TopEggNoticeSub")
if not topNoticeSub then
	topNoticeSub = Instance.new("TextLabel")
	topNoticeSub.Name = "TopEggNoticeSub"
	topNoticeSub.AnchorPoint = Vector2.new(0.5, 0.5)
	topNoticeSub.Position = UDim2.fromScale(0.5, 0.235)
	topNoticeSub.Size = UDim2.fromOffset(680, 42)
	topNoticeSub.BackgroundTransparency = 1
	topNoticeSub.Font = FONT
	topNoticeSub.TextScaled = false
	topNoticeSub.TextSize = 28
	topNoticeSub.TextWrapped = true
	topNoticeSub.TextColor3 = Color3.fromRGB(255, 236, 176)
	topNoticeSub.TextStrokeColor3 = Color3.fromRGB(79, 42, 13)
	topNoticeSub.TextStrokeTransparency = 0
	topNoticeSub.TextTransparency = 1
	topNoticeSub.Visible = true
	topNoticeSub.ZIndex = 50
	topNoticeSub.Parent = gui
end
local topNoticeSubScale = topNoticeSub:FindFirstChild("TopNoticeSubScale") or Instance.new("UIScale")
topNoticeSubScale.Name = "TopNoticeSubScale"
topNoticeSubScale.Parent = topNoticeSub

topNoticeSub.TextScaled = false
topNoticeSub.TextSize = 28

topNoticeSub.TextWrapped = true

local topNoticeIcon = gui:FindFirstChild("TopEggNoticeIcon")
if not topNoticeIcon then
	topNoticeIcon = Instance.new("ViewportFrame")
	topNoticeIcon.Name = "TopEggNoticeIcon"
	topNoticeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	topNoticeIcon.Position = UDim2.fromScale(0.5, 0.235)
	topNoticeIcon.Size = UDim2.fromOffset(90, 90)
	topNoticeIcon.BackgroundTransparency = 1
	topNoticeIcon.Ambient = Color3.fromRGB(255, 255, 255)
	topNoticeIcon.LightColor = Color3.fromRGB(255, 255, 255)
	topNoticeIcon.Visible = false
	topNoticeIcon.ZIndex = 50
	topNoticeIcon.Parent = gui
end
local topNoticeIconScale = topNoticeIcon:FindFirstChild("TopNoticeIconScale") or Instance.new("UIScale")
topNoticeIconScale.Name = "TopNoticeIconScale"
topNoticeIconScale.Parent = topNoticeIcon

local zzzHolder = gui:FindFirstChild("TopEggNoticeZzz")
if not zzzHolder then
	zzzHolder = Instance.new("Frame")
	zzzHolder.Name = "TopEggNoticeZzz"
	zzzHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	zzzHolder.Position = UDim2.fromScale(0.5, 0.225)
	zzzHolder.Size = UDim2.fromOffset(170, 80)
	zzzHolder.BackgroundTransparency = 1
	zzzHolder.Visible = false
	zzzHolder.ZIndex = 51
	zzzHolder.Parent = gui
	local specs = {
		{ text = "Z", x = 0.28, y = 0.68, size = 40 },
		{ text = "z", x = 0.52, y = 0.48, size = 31 },
		{ text = "z", x = 0.72, y = 0.28, size = 23 },
	}
	for index, spec in ipairs(specs) do
		local label = Instance.new("TextLabel")
		label.Name = "SleepZ" .. index
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(spec.x, spec.y)
		label.Size = UDim2.fromOffset(spec.size + 18, spec.size + 18)
		label.BackgroundTransparency = 1
		label.Font = FONT
		label.Text = spec.text
		label.TextSize = spec.size
		label.TextColor3 = Color3.fromRGB(235, 245, 255)
		label.TextStrokeColor3 = Color3.fromRGB(38, 48, 88)
		label.TextStrokeTransparency = 0
		label.TextTransparency = 1
		label.ZIndex = zzzHolder.ZIndex + 1
		label:SetAttribute("BaseX", spec.x)
		label:SetAttribute("BaseY", spec.y)
		label:SetAttribute("BaseSize", spec.size)
		label.Parent = zzzHolder
	end
end
local zzzHolderScale = zzzHolder:FindFirstChild("ZzzScale") or Instance.new("UIScale")
zzzHolderScale.Name = "ZzzScale"
zzzHolderScale.Parent = zzzHolder

local foodIcon = gui:FindFirstChild("TopEggNoticeFoodIcon")
if not foodIcon then
	foodIcon = Instance.new("ImageLabel")
	foodIcon.Name = "TopEggNoticeFoodIcon"
	foodIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	foodIcon.Position = UDim2.fromScale(0.5, 0.235)
	foodIcon.Size = UDim2.fromOffset(96, 96)
	foodIcon.BackgroundTransparency = 1
	foodIcon.Image = FOOD_ALERT_IMAGE
	foodIcon.ImageTransparency = 1
	foodIcon.ScaleType = Enum.ScaleType.Fit
	foodIcon.Visible = false
	foodIcon.ZIndex = 52
	foodIcon.Parent = gui
end
local foodIconScale = foodIcon:FindFirstChild("FoodIconScale") or Instance.new("UIScale")
foodIconScale.Name = "FoodIconScale"
foodIconScale.Parent = foodIcon

local activeTweens = {}
local noticeQueue = {}
local noticePlaying = false
local noticeCooldowns = {}
local token = 0

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do tween:Cancel() end
	table.clear(activeTweens)
end

local function playTween(instance, info, goal)
	local tween = TweenService:Create(instance, info, goal)
	table.insert(activeTweens, tween)
	tween:Play()
	return tween
end

local function clearViewport()
	for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
end

local function clearTopNoticeIcon()
	for _, child in ipairs(topNoticeIcon:GetChildren()) do
		if not child:IsA("UIScale") then
			child:Destroy()
		end
	end
end

local function putDirtyEggInTopNoticeIcon()
	clearTopNoticeIcon()
	local source = workspace:FindFirstChild("Huevo sucio")
	if not source then
		source = petViews:FindFirstChild("Huevo Mascota")
	end
	if not source then return false end
	local model = source:Clone()
	model.Parent = topNoticeIcon
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	local camera = Instance.new("Camera")
	camera.Parent = topNoticeIcon
	topNoticeIcon.CurrentCamera = camera
	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z, 1)
	local center = cf.Position
	camera.CFrame = CFrame.new(center + Vector3.new(maxSize * 1.2, maxSize * 0.55, maxSize * 2.0), center)
	camera.FieldOfView = 30
	return true
end

local function findRewardPetSource(petName, tier)
	petName = canonicalPetName(petName)
	tier = tostring(tier or "")

	if tier ~= "" and tier ~= "Base" then
		local folderName = UPGRADE_VARIANT_FOLDERS[tier]

		if folderName then
			for _, root in ipairs({workspace, ReplicatedStorage}) do
				local animals = root:FindFirstChild("Animales pañuelos")
				local folder = animals and animals:FindFirstChild(folderName)

				if not folder then
					folder = root:FindFirstChild(folderName, true)
				end

				if folder then
					local exact = folder:FindFirstChild(petName)
					if exact and exact:IsA("Model") then
						return exact
					end

					local wanted = normalizePetName(petName)
					for _, object in ipairs(folder:GetDescendants()) do
						if object:IsA("Model") then
							local n = normalizePetName(object.Name)
							if n == wanted
								or n:find(wanted, 1, true)
								or wanted:find(n, 1, true) then
								return object
							end
						end
					end
				end
			end
		end
	end

	local exact = petViews:FindFirstChild(petName)
	if exact then
		return exact
	end

	local wanted = normalizePetName(petName)
	for _, object in ipairs(petViews:GetChildren()) do
		if object:IsA("Model") then
			local n = normalizePetName(object.Name)
			if n == wanted
				or n:find(wanted, 1, true)
				or wanted:find(n, 1, true) then
				return object
			end
		end
	end

	return nil
end

local function putModelInViewport(petName, tier)
	clearViewport()

	local source = findRewardPetSource(petName, tier)
	if not source then
		warn("[EggRewardNotice] No se encontró modelo:", petName, tier)
		return
	end

	local sourceViewport = source:FindFirstChildWhichIsA("ViewportFrame")
	local sourceModel = sourceViewport and sourceViewport:FindFirstChildWhichIsA("Model") or nil
	local model = sourceModel and sourceModel:Clone() or source:Clone()

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z, 1)
	local center = cf.Position

	-- Misma presentación que ya usabas en huevo/eclosión,
	-- solo que admite el modelo con pañuelo.
	camera.CFrame = CFrame.new(
		center + Vector3.new(maxSize * 1.4, maxSize * 0.65, maxSize * 2.0),
		center
	)
	camera.FieldOfView = 32
end

local function playTextNoticeNow(message, subtitle)
	cancelTweens()
	local showDirtyIcon = subtitle == "__DIRTY_EGG__"
	local showSleepZzz = subtitle == "Zzz..."
	local showFoodIcon = subtitle == "__FOOD_ALERT__"
	topNotice.Text = tostring(message or "")
	topNoticeSub.Text = (showDirtyIcon or showSleepZzz or showFoodIcon) and "" or tostring(subtitle or "")
	topNotice.Visible = true
	topNoticeSub.Visible = not showDirtyIcon and not showSleepZzz and not showFoodIcon and subtitle ~= nil and tostring(subtitle) ~= ""
	zzzHolder.Visible = showSleepZzz
	foodIcon.Visible = showFoodIcon
	foodIcon.ImageTransparency = showFoodIcon and 0 or 1
	topNoticeIcon.Visible = showDirtyIcon and putDirtyEggInTopNoticeIcon()
	topNotice.Position = UDim2.fromScale(0.5, 0.165)
	topNoticeSub.Position = UDim2.fromScale(0.5, 0.235)
	topNoticeIcon.Position = UDim2.fromScale(0.5, 0.235)
	zzzHolder.Position = UDim2.fromScale(0.5, 0.225)
	foodIcon.Position = UDim2.fromScale(0.5, 0.23)
	topNotice.Rotation = -7
	topNoticeSub.Rotation = -4
	topNoticeIcon.Rotation = -8
	zzzHolder.Rotation = -4
	foodIcon.Rotation = -8
	topNotice.TextTransparency = 0
	topNotice.TextStrokeTransparency = 0
	topNoticeSub.TextTransparency = 0
	topNoticeSub.TextStrokeTransparency = 0
	topNoticeScale.Scale = 0.58
	topNoticeSubScale.Scale = 0.7
	topNoticeIconScale.Scale = 0.55
	zzzHolderScale.Scale = 0.62
	foodIconScale.Scale = 0.55
	if showSleepZzz then
		for index, label in ipairs(zzzHolder:GetChildren()) do
			if label:IsA("TextLabel") then
				local baseX = label:GetAttribute("BaseX") or 0.5
				local baseY = label:GetAttribute("BaseY") or 0.5
				local baseSize = label:GetAttribute("BaseSize") or 30
				label.Position = UDim2.fromScale(baseX, baseY + 0.18)
				label.TextTransparency = 1
				label.TextStrokeTransparency = 1
				label.TextSize = baseSize
				task.delay(index * 0.12, function()
					if zzzHolder.Visible and label.Parent then
						playTween(label, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(baseX, baseY - 0.1), TextTransparency = 0, TextStrokeTransparency = 0.05, TextSize = baseSize + 6 })
					end
				end)
			end
		end
	end
	playTween(topNoticeScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 })
	playTween(topNotice, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.145), Rotation = 3 })
	playTween(topNoticeSubScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	playTween(topNoticeSub, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.215), Rotation = 1 })
	playTween(topNoticeIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	playTween(topNoticeIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.215), Rotation = 0 })
	playTween(zzzHolderScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	playTween(zzzHolder, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.21), Rotation = 0 })
	playTween(foodIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	playTween(foodIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.21), Rotation = 0, ImageTransparency = showFoodIcon and 0 or 1 })
	task.wait(0.18)
	playTween(topNoticeScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	playTween(topNotice, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 })
	task.wait(2.2)
	playTween(topNotice, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.105), Rotation = 5, TextTransparency = 1, TextStrokeTransparency = 1 })
	playTween(topNoticeScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	playTween(topNoticeSub, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.185), TextTransparency = 1, TextStrokeTransparency = 1 })
	playTween(topNoticeSubScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	playTween(topNoticeIcon, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.185) })
	playTween(topNoticeIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	playTween(zzzHolder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.18), Rotation = 5 })
	playTween(zzzHolderScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	playTween(foodIcon, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.18), Rotation = 5, ImageTransparency = 1 })
	playTween(foodIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 })
	for _, label in ipairs(zzzHolder:GetChildren()) do
		if label:IsA("TextLabel") then
			playTween(label, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end
	task.wait(0.34)
	topNotice.TextTransparency = 1
	topNotice.TextStrokeTransparency = 1
	topNoticeSub.TextTransparency = 1
	topNoticeSub.TextStrokeTransparency = 1
	topNotice.Visible = true
	topNoticeSub.Visible = true
	topNoticeIcon.Visible = false
	zzzHolder.Visible = false
	foodIcon.Visible = false
	foodIcon.ImageTransparency = 1
	clearTopNoticeIcon()
end

local function playNoticeNow(message, petName, rarity, subtitle, upgradeTier)
	if petName == nil then
		playTextNoticeNow(message, subtitle)
		return
	end
	cancelTweens()
	clearViewport()
	holder.Visible = true

	-- En una mejora, upgradeTier contiene el tier interno real.
	-- Así "Raro" visible puede ser verde sin afectar el "Raro" azul
	-- que usa el sistema normal de huevos.
	local rarityColor =
		(upgradeTier and RARITY_COLORS[upgradeTier])
		or RARITY_COLORS[rarity]
		or Color3.fromRGB(255, 214, 84)
	local textOnly = petName == nil
	title.Text = message
	titleShadow.Text = message
	rarityLabel.Text = rarity and tostring(rarity) or ""
	rarityShadow.Text = rarityLabel.Text
	rarityLabel.TextColor3 = rarityColor
	glow.BackgroundColor3 = rarityColor
	local glowStroke = glow:FindFirstChild("GlowStroke")
	if glowStroke then glowStroke.Color = Color3.fromRGB(84, 45, 14) end
	if petName then putModelInViewport(petName, upgradeTier) end

	holder.Visible = true
	holder.Rotation = -10
	holder.Position = textOnly and UDim2.fromScale(0.5, 0.30) or UDim2.fromScale(0.5, 0.48)
	scale.Scale = 0.16
	viewport.Rotation = -8
	title.TextTransparency = 0
	title.TextStrokeTransparency = 0
	titleShadow.TextTransparency = 0.08
	rarityLabel.TextTransparency = textOnly and 1 or 0
	rarityLabel.TextStrokeTransparency = textOnly and 1 or 0
	rarityShadow.TextTransparency = 1
	glow.Visible = not textOnly
	viewport.Visible = not textOnly
	glow.BackgroundTransparency = textOnly and 1 or 0.18
	title.Size = textOnly and UDim2.new(1, 0, 0, 96) or UDim2.new(1, 0, 0, 70)
	titleShadow.Size = title.Size

	playTween(scale, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	playTween(holder, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0, Position = textOnly and UDim2.fromScale(0.5, 0.24) or UDim2.fromScale(0.5, 0.42)})
	if not textOnly then
		playTween(viewport, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0})
	end

	task.wait(3.4)
	playTween(scale, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.78})
	playTween(holder, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = textOnly and UDim2.fromScale(0.5, 0.16) or UDim2.fromScale(0.5, 0.32), Rotation = 5})
	playTween(title, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1})
	playTween(titleShadow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
	playTween(rarityLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1})
	playTween(rarityShadow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
	if not textOnly then playTween(glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}) end
	task.wait(0.45)
	holder.Visible = false
	glow.Visible = true
	viewport.Visible = true
	clearViewport()
end

local function processNoticeQueue()
	while #noticeQueue > 0 do
		local nextNotice = table.remove(noticeQueue, 1)
		local ok, err = pcall(function()
			playNoticeNow(
				nextNotice.message,
				nextNotice.petName,
				nextNotice.rarity,
				nextNotice.subtitle,
				nextNotice.upgradeTier
			)
		end)
		if not ok then
			warn("[EggRewardNotice] No se pudo mostrar alerta:", err)
			holder.Visible = true
			task.wait(2.4)
			holder.Visible = false
		end
	end
	noticePlaying = false
end

function showNotice(message, petName, rarity, cooldownKey, subtitle, upgradeTier)
	local now = os.clock()
	if cooldownKey then
		local nextAllowed = noticeCooldowns[cooldownKey] or 0
		if now < nextAllowed then return end
		noticeCooldowns[cooldownKey] = now + 45
		for index = #noticeQueue, 1, -1 do
			if noticeQueue[index].cooldownKey == cooldownKey then
				table.remove(noticeQueue, index)
			end
		end
	end
	table.insert(noticeQueue, {
		message = message,
		petName = petName,
		rarity = rarity,
		cooldownKey = cooldownKey,
		subtitle = subtitle,
		upgradeTier = upgradeTier,
	})
	if noticePlaying then return end
	noticePlaying = true
	task.spawn(processNoticeQueue)
end

local needAlert = gui:FindFirstChild("PetNeedAlert")
if not needAlert then
	needAlert = Instance.new("Frame")
	needAlert.Name = "PetNeedAlert"
	needAlert.AnchorPoint = Vector2.new(0.5, 0)
	needAlert.Position = UDim2.fromScale(0.5, 0.115)
	needAlert.Size = UDim2.fromOffset(760, 170)
	needAlert.BackgroundTransparency = 1
	needAlert.Visible = false
	needAlert.ZIndex = 200
	needAlert.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromOffset(760, 82)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 249, 219)
	label.TextStrokeColor3 = Color3.fromRGB(79, 42, 13)
	label.TextStrokeTransparency = 0
	label.ZIndex = needAlert.ZIndex + 1
	label.Parent = needAlert

	local icon = Instance.new("ImageLabel")
	icon.Name = "FoodIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.52)
	icon.Size = UDim2.fromOffset(124, 124)
	icon.BackgroundTransparency = 1
	icon.Image = FOOD_ALERT_IMAGE
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = needAlert.ZIndex + 2
	icon.Parent = needAlert

	local sleep = Instance.new("TextLabel")
	sleep.Name = "SleepIcon"
	sleep.AnchorPoint = Vector2.new(0.5, 0)
	sleep.Position = UDim2.fromScale(0.5, 0.52)
	sleep.Size = UDim2.fromOffset(190, 88)
	sleep.BackgroundTransparency = 1
	sleep.Font = FONT
	sleep.Text = "Zzz"
	sleep.TextScaled = true
	sleep.TextColor3 = Color3.fromRGB(235, 245, 255)
	sleep.TextStrokeColor3 = Color3.fromRGB(38, 48, 88)
	sleep.TextStrokeTransparency = 0
	sleep.ZIndex = needAlert.ZIndex + 2
	sleep.Parent = needAlert

	local scaleObject = Instance.new("UIScale")
	scaleObject.Name = "NeedAlertScale"
	scaleObject.Scale = 1
	scaleObject.Parent = needAlert
end

local needAlertToken = 0
local function showNeedAlert(text, mode)
	needAlertToken += 1
	local myToken = needAlertToken
	local titleLabel = needAlert:FindFirstChild("Title")
	local food = needAlert:FindFirstChild("FoodIcon")
	local sleep = needAlert:FindFirstChild("SleepIcon")
	local scaleObject = needAlert:FindFirstChild("NeedAlertScale")
	if not titleLabel or not food or not sleep or not scaleObject then return end
	titleLabel.Text = tostring(text or "")
	food.Visible = mode == "Food"
	sleep.Visible = mode == "Sleep"
	needAlert.Visible = true
	needAlert.Position = UDim2.fromScale(0.5, 0.135)
	scaleObject.Scale = 0.84
	titleLabel.TextTransparency = 0
	titleLabel.TextStrokeTransparency = 0
	food.ImageTransparency = mode == "Food" and 0 or 1
	sleep.TextTransparency = mode == "Sleep" and 0 or 1
	sleep.TextStrokeTransparency = mode == "Sleep" and 0 or 1
	TweenService:Create(needAlert, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.105) }):Play()
	TweenService:Create(scaleObject, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(10, function()
		if myToken ~= needAlertToken then return end
		TweenService:Create(needAlert, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.075) }):Play()
		TweenService:Create(titleLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(food, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 }):Play()
		TweenService:Create(sleep, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.28)
		if myToken == needAlertToken then
			needAlert.Visible = false
		end
	end)
end

-- =============================================================
-- EVENTO LOCAL PARA REUTILIZAR ESTA MISMA ANIMACIÓN EN FRANK
-- =============================================================
local upgradeRewardEvent = gui:FindFirstChild("PetUpgradeRewardLocal")

if upgradeRewardEvent and not upgradeRewardEvent:IsA("BindableEvent") then
	upgradeRewardEvent:Destroy()
	upgradeRewardEvent = nil
end

if not upgradeRewardEvent then
	upgradeRewardEvent = Instance.new("BindableEvent")
	upgradeRewardEvent.Name = "PetUpgradeRewardLocal"
	upgradeRewardEvent.Parent = gui
end

upgradeRewardEvent.Event:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end

	local petName = tostring(data.petName or "Mascota")
	local tier = tostring(data.tier or data.rarity or "Comun")

	-- Nombres visibles pedidos para la mejora:
	-- Comun       = Común / gris
	-- Poco comun  = Raro / verde
	-- Raro        = Muy raro / azul
	-- Epico       = Épico / morado
	-- Legendario  = Legendario / dorado
	local display = UPGRADE_RARITY_DISPLAY[tier]
		or tostring(data.display or data.rarity or tier)

	-- EXACTAMENTE la animación de recompensa de huevo/eclosión.
	showNotice(
		"Tu " .. petName .. " fue mejorada",
		petName,
		display,
		nil,
		nil,
		tier
	)
end)

EggNotify.OnClientEvent:Connect(function(kind, data)
	if kind == "Purchased" then
		showNotice("Adquiriste un huevo mascota", "Huevo Mascota", nil)
	elseif kind == "Dirty" then
		showNotice("Huevo mascota", nil, nil, "Dirty", "__DIRTY_EGG__")
	elseif kind == "Tired" then
		local petName = typeof(data) == "table" and tostring(data.petName or "") or ""
		local titleText = petName ~= "" and ("Tu " .. petName .. " tiene sueño") or "Tu huevo mascota tiene sueño"
		needAlert.Visible = false
		task.spawn(playTextNoticeNow, titleText, "Zzz...")
	elseif kind == "Hungry" then
		local petName = typeof(data) == "table" and tostring(data.petName or "") or ""
		local titleText = petName ~= "" and ("Tu " .. petName .. " tiene hambre") or "Tu mascota tiene hambre"
		needAlert.Visible = false
		task.spawn(playTextNoticeNow, titleText, "__FOOD_ALERT__")
	elseif kind == "SleepStarted" or kind == "Rested" then
		return
	elseif kind == "Ready" then
		showNotice("El huevo ya se rompera", "Huevo Mascota", nil)
	elseif kind == "Hatched" and typeof(data) == "table" then
		local petName = tostring(data.petName or "Mascota")
		showNotice("Obtuviste: " .. petName, petName, data.rarity)
	end
end)