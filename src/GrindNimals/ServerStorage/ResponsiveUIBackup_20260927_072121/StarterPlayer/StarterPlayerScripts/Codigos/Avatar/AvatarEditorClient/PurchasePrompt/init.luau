local PurchasePrompt = {}
PurchasePrompt.__index = PurchasePrompt

local Marketplace = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local templatePrompt = script.Container


function PurchasePrompt.new(overlayFrame)
	
	local self = setmetatable({
		
		overlayFrame = overlayFrame
		
	}, PurchasePrompt)
	
	local function activated(inputObject)
		self:Clear()
	end
	
	overlayFrame.Activated:Connect(activated)
	
	return self
	
end


function PurchasePrompt:Clear()
	
	self.overlayFrame.Visible = false
	self.overlayFrame:ClearAllChildren()
	
end


function PurchasePrompt:Prompt(id)
	
	local productInfo
	pcall(function()
		productInfo = Marketplace:GetProductInfo(id)
	end)
	
	self:Clear()
	self.overlayFrame.Visible = true
	
	local function cancel(inputObject)
		self:Clear()
	end
	
	local function confirm(inputObject)
		pcall(function()
			Marketplace:PromptPurchase(player, productInfo.AssetId)
		end)
	end
	
	local promptFrame = templatePrompt:Clone()
	promptFrame.PromptBody.ProductInfo.ProductDescription.ProductDescriptionText.Text = productInfo.Name
	promptFrame.PromptBody.ProductInfo.ItemPreviewImage.ItemPreviewImageContainer.ItemImage.Image = "rbxthumb://type=Asset&id=" .. productInfo.AssetId .. "&w=150&h=150"
	if productInfo.IsPublicDomain then
		promptFrame.PromptButtons.Confirm.PriceTextLabel.Text = "Free"
	elseif productInfo.IsForSale then
		promptFrame.PromptButtons.Confirm.PriceTextLabel.Text = productInfo.PriceInRobux
	else
		promptFrame.PromptButtons.Confirm.PriceTextLabel.Text = "Not for sale"
	end
	promptFrame.PromptButtons.Cancel.Activated:Connect(cancel)
	promptFrame.PromptButtons.Confirm.Activated:Connect(confirm)
	
	promptFrame.Parent = self.overlayFrame
	
end


return PurchasePrompt