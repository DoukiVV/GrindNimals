--============================================================
-- PetSlot2Controller
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > Client > PetSlot2Controller
--
-- Responsabilidad:
-- - Sincronizar SelectedBackpackPet con Quick Slot 2
-- - Dibujar el modelo 3D real del tier en Slot 2
-- - Reequipar la mascota guardada cuando termina de cargar
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local petsShared = ReplicatedStorage
	:WaitForChild("GameShared")
	:WaitForChild("Pets")

local PetNames = require(petsShared:WaitForChild("PetNames"))
local ClientFolder = petsShared:WaitForChild("Client")
local PetModelResolver = require(ClientFolder:WaitForChild("PetModelResolver"))

local PetSlot2Controller = {}

local started = false
local connections = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local quickSlotEvent = ReplicatedStorage:WaitForChild("BackpackQuickSlotEvent")

local updateToken = 0
local slot2Container = nil
local slotRefreshSerial = 0

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function syncQuickSlot2()
	updateToken += 1
	local token = updateToken

	task.defer(function()
		if token ~= updateToken then
			return
		end

		local petName = player:GetAttribute("SelectedBackpackPet")
		if typeof(petName) ~= "string" or petName == "" then
			return
		end

		petName = PetNames.Canonical(petName)

		local tier = PetModelResolver.NormalizeTier(
			player:GetAttribute("SelectedBackpackPetTier")
		)

		if petName == PetNames.EGG_NAME then
			tier = "Base"

			if player:GetAttribute("SelectedBackpackPetTier") ~= "Base" then
				player:SetAttribute("SelectedBackpackPetTier", "Base")
			end
		end

		quickSlotEvent:Fire(2, {
			kind = "Pet",
			name = petName,
			tier = tier,
		})
	end)
end

local function isReasonableSlotContainer(gui)
	if not gui or not gui:IsA("GuiObject") then
		return false
	end

	local size = gui.AbsoluteSize

	if size.X < 45
		or size.Y < 45
		or size.X > 190
		or size.Y > 190 then
		return false
	end

	local ratio = size.X / math.max(size.Y, 1)
	return ratio > 0.65 and ratio < 1.45
end

local function scoreSlot2Candidate(label, ancestor)
	local score = 0
	local name = ancestor.Name:lower()

	if name:find("slot2", 1, true)
		or name:find("slot_2", 1, true)
		or name:find("slot 2", 1, true) then
		score += 100
	end

	if name:find("slot", 1, true)
		or name:find("quick", 1, true)
		or name:find("hotbar", 1, true)
		or name:find("backpack", 1, true) then
		score += 20
	end

	local labelPos = label.AbsolutePosition + label.AbsoluteSize / 2
	local ancestorPos = ancestor.AbsolutePosition + ancestor.AbsoluteSize / 2
	local distance = (labelPos - ancestorPos).Magnitude

	score += math.max(0, 30 - distance * 0.15)

	local size = ancestor.AbsoluteSize
	score -= math.abs(size.X - 90) * 0.08
	score -= math.abs(size.Y - 90) * 0.08

	return score
end

local function findSlot2Container()
	local best = nil
	local bestScore = -math.huge

	for _, obj in ipairs(playerGui:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
			and tostring(obj.Text):match("^%s*2%s*$")
			and obj.Visible then

			local ancestor = obj.Parent
			local depth = 0

			while ancestor and ancestor ~= playerGui and depth < 6 do
				if isReasonableSlotContainer(ancestor) then
					local score = scoreSlot2Candidate(obj, ancestor)

					if score > bestScore then
						bestScore = score
						best = ancestor
					end
				end

				ancestor = ancestor.Parent
				depth += 1
			end
		end
	end

	return best
end

local function clearSlot2PetVisual(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		if child.Name == "SelectedPetTierWorld"
			or child.Name == "SelectedPetTierViewport"
			or child.Name == "PetSystemViewport" then
			child:Destroy()
		end
	end
end

local function renderSelectedPetInSlot2()
	local petName = player:GetAttribute("SelectedBackpackPet")

	if typeof(petName) ~= "string" or petName == "" then
		if slot2Container then
			clearSlot2PetVisual(slot2Container)
		end
		return
	end

	petName = PetNames.Canonical(petName)

	local tier = PetModelResolver.NormalizeTier(
		player:GetAttribute("SelectedBackpackPetTier")
	)

	local model

	if tier == "Base" then
		model = PetModelResolver.FindBaseModel(petName)
	else
		model = PetModelResolver.FindVariantModel(tier, petName)
	end

	if not model then
		model = PetModelResolver.FindBaseModel(petName)
	end

	if not model then
		return
	end

	if not slot2Container or not slot2Container.Parent then
		slot2Container = findSlot2Container()
	end

	if not slot2Container then
		return
	end

	clearSlot2PetVisual(slot2Container)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "SelectedPetTierViewport"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.46)
	viewport.Size = UDim2.fromScale(0.90, 0.90)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.ZIndex = math.max(slot2Container.ZIndex + 10, 20)
	viewport.Active = false
	viewport.Parent = slot2Container

	PetModelResolver.SetViewportModel(viewport, model)
	viewport.Name = "SelectedPetTierViewport"
end

local function queueSlot2ModelRefresh()
	slotRefreshSerial += 1
	local serial = slotRefreshSerial

	renderSelectedPetInSlot2()

	task.delay(0.08, function()
		if serial == slotRefreshSerial then
			renderSelectedPetInSlot2()
		end
	end)
end

local function restoreSavedSelection()
	task.spawn(function()
		local startedAt = os.clock()

		while os.clock() - startedAt < 15 do
			local selected = player:GetAttribute("SelectedBackpackPet")

			if typeof(selected) == "string" and selected ~= "" then
				syncQuickSlot2()
				queueSlot2ModelRefresh()

				local equipEvent = ReplicatedStorage:FindFirstChild("EquipPet")

				if equipEvent and equipEvent:IsA("RemoteEvent") then
					equipEvent:FireServer(
						selected,
						PetModelResolver.NormalizeTier(
							player:GetAttribute("SelectedBackpackPetTier")
						)
					)
				end

				break
			end

			task.wait(0.2)
		end
	end)
end

function PetSlot2Controller.Start()
	if started then
		return
	end
	started = true

	connect(
		player:GetAttributeChangedSignal("SelectedBackpackPet"),
		function()
			syncQuickSlot2()
			queueSlot2ModelRefresh()
		end
	)

	connect(
		player:GetAttributeChangedSignal("SelectedBackpackPetTier"),
		function()
			syncQuickSlot2()
			queueSlot2ModelRefresh()
		end
	)

	connect(quickSlotEvent.Event, function(slotIndex, data)
		if slotIndex == 2
			and typeof(data) == "table"
			and data.kind == "Pet" then

			task.defer(queueSlot2ModelRefresh)
		end
	end)

	connect(playerGui.DescendantAdded, function(obj)
		if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
			and tostring(obj.Text):match("^%s*2%s*$") then

			slot2Container = nil
			task.defer(queueSlot2ModelRefresh)
		end
	end)

	task.defer(syncQuickSlot2)
	queueSlot2ModelRefresh()
	restoreSavedSelection()
end

return PetSlot2Controller
