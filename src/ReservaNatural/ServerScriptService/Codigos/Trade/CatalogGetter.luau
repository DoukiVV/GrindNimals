--[[

	19 -- All Accessories
	9 -- Hat
	20 -- HairAccessory
	21 -- FaceAccessory
	22 -- NeckAccessory
	23 -- ShoulderAccessory
	24 -- FrontAccessory
	25 -- BackAccessory
	26 -- WaistAccessory
	
	4 -- Faces+Heads
	10 -- Faces
	15 -- Heads

--]]

local Http = game:GetService("HttpService")

local subcategory = 9
local url = "https://search.roblox.com/catalog/json?Subcategory=" .. subcategory .. "&IncludeNotForSale=true&ResultsPerPage=60&PageNumber="

local pages = 25

local assets = {}

for i = 1, pages do
	local urlPage = url .. i
	local data = Http:JSONEncode(Http:GetAsync(urlPage))
	data = Http:JSONDecode(data)
	
	for ii = 1, #data do
		local asset = data[ii]
		
		local id = asset.AssetId
		local name = asset.Name
		
		assets[#assets + 1] = "{Id = " ..id .. ", Name = \"" .. name .. "\"}"
	end
	print(i)
end

local source = "return { \n\t" .. table.concat(assets, ",\n\t") .. "\n}"
local module = Instance.new("ModuleScript")
module.Source = source
module.Parent = workspace