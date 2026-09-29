local Button = {}
Button.__index = Button

local templateButton = script.ImageButton


function Button.new(buttonData)
	
	--[[
		buttonData = {
			guiButton = guiButton,
			Name = "",
			Icon = "",
			AssetId = 000,
			ActivatedCallback = function,
			DetailsCallback = function,
		}
	--]]
	
	local guiButton = buttonData.guiButton
	if guiButton == nil then
		guiButton = templateButton:Clone()
	end
	
	local tooltipFrame = guiButton:FindFirstChild("Tooltip")
	local selectedFrame = guiButton:FindFirstChild("Selected")
	local iconImage = guiButton:FindFirstChild("Icon")
	local moreButton = guiButton:FindFirstChild("More")
	
	guiButton.Name = buttonData.Name or guiButton.Name
	if iconImage then
		guiButton.Icon.Image = buttonData.Icon or guiButton.Icon.Image
	end
	
	local self = setmetatable({
		
		guiButton = guiButton,
		selectedFrame = selectedFrame,
		AssetId = buttonData.AssetId
		
	}, Button)
	
	local function inputBegan(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch then
			if tooltipFrame then
				tooltipFrame.Visible = true
			end
			if moreButton and buttonData.DetailsCallback then
				moreButton.Visible = true
			end
		end
	end
	
	local function inputEnded(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch then
			if tooltipFrame then
				tooltipFrame.Visible = false
			end
			if moreButton and buttonData.DetailsCallback then
				moreButton.Visible = false
			end
		end
	end
	
	local function activated(inputObject)
		if buttonData.ActivatedCallback then
			buttonData.ActivatedCallback(inputObject)
		end
	end
	
	if moreButton and buttonData.DetailsCallback then
		local function touchLongPress(touchPositions, inputState)
			if inputState == Enum.UserInputState.Begin then
				buttonData.DetailsCallback()
			end
		end
		guiButton.TouchLongPress:Connect(touchLongPress)
		moreButton.Activated:Connect(buttonData.DetailsCallback)
	end
	
	guiButton.InputBegan:Connect(inputBegan)
	guiButton.InputEnded:Connect(inputEnded)
	guiButton.Activated:Connect(activated)
	
	return self
	
end


function Button:Parent(parent)
	
	self.guiButton.Parent = parent
	
end


function Button:SetSelected(selected)
	
	if self.selectedFrame then
		self.selectedFrame.Visible = selected
	end
	
end


function Button:Destroy()
	
	self.selectedFrame = nil
	self.guiButton:Destroy()
	self.guiButton = nil
	setmetatable(self, nil)
	
end


return Button