local Asset = game:GetService("AssetService")
local Marketplace = game:GetService("MarketplaceService")

local bundles = 700

local parts = {
	leftArms = {},
	leftLegs = {},
	rightArms = {},
	rightLegs = {},
	torso = {},
}

for i = 1, bundles do
	local success, bundleDetails = pcall(function()
		return Asset:GetBundleDetailsAsync(i)
	end)
	if success then
		for j = 1, #bundleDetails.Items do
			local itemData = bundleDetails.Items[j]
			local productInfo
			local success = pcall(function()
				productInfo = Marketplace:GetProductInfo(itemData.Id)
			end)
			if productInfo then
				if productInfo.AssetTypeId == 28 then
					parts.rightArms[#parts.rightArms + 1] = "{Id = " ..itemData.Id .. ", Name = \"" .. itemData.Name .. "\"}"
				elseif productInfo.AssetTypeId == 29 then
					parts.leftArms[#parts.leftArms + 1] = "{Id = " ..itemData.Id .. ", Name = \"" .. itemData.Name .. "\"}"
				elseif productInfo.AssetTypeId == 30 then
					parts.leftLegs[#parts.leftLegs + 1] = "{Id = " ..itemData.Id .. ", Name = \"" .. itemData.Name .. "\"}"
				elseif productInfo.AssetTypeId == 31 then
					parts.rightLegs[#parts.rightLegs + 1] = "{Id = " ..itemData.Id .. ", Name = \"" .. itemData.Name .. "\"}"
				elseif productInfo.AssetTypeId == 27 then
					parts.torso[#parts.torso + 1] = "{Id = " ..itemData.Id .. ", Name = \"" .. itemData.Name .. "\"}"
				end
			else
				print("failed", i)
			end
			wait(0.6)
		end
	end
end

for part, list in next, parts do
	local source = "return { \n\t" .. table.concat(list, ",\n\t") .. "\n}"
	local module = Instance.new("ModuleScript")
	module.Source = source
	module.Name = part
	module.Parent = workspace
end