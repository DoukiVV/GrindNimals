-- AvatarToggleAlinearConConfiguraciones.client.luau
-- TIPO: LocalScript
-- ROJO: src/GrindNimals/ReplicatedFirst/
-- STUDIO: ReplicatedFirst > AvatarToggleAlinearConConfiguraciones
-- Solo sincroniza el centro horizontal de Vestirse con Configuraciones.
-- No cambia Y, tamano, camara, catalogo ni la logica de los botones.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local RENDER_NAME = "GrindNimals_AlinearVestirseConConfiguraciones"

local toggle
local config
local lastLookup = 0

local function findButtons()
    local avatarGui = playerGui:FindFirstChild("AvatarEditor")
    local hud = playerGui:FindFirstChild("HUD")
    local ajustes = hud and hud:FindFirstChild("Ajustes")

    local candidateToggle = avatarGui and avatarGui:FindFirstChild("Toggle")
    local candidateConfig = ajustes and ajustes:FindFirstChild("ButtonConfig")

    toggle = candidateToggle and candidateToggle:IsA("GuiObject") and candidateToggle or nil
    config = candidateConfig and candidateConfig:IsA("GuiObject") and candidateConfig or nil
end

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, function()
    local now = os.clock()
    if now - lastLookup >= 0.5 or not toggle or not config or not toggle.Parent or not config.Parent then
        lastLookup = now
        findButtons()
    end
    if not toggle or not config then
        return
    end

    local targetX = config.AbsolutePosition.X + config.AbsoluteSize.X * 0.5
    local currentX = toggle.AbsolutePosition.X + toggle.AbsoluteSize.X * 0.5
    local difference = targetX - currentX

    if math.abs(difference) < 0.8 then
        return
    end

    -- Solo tocamos X. Los otros sistemas conservan Y, tamano y animaciones.
    -- Un UIScale puede reducir el movimiento real por pixel de Offset;
    -- por eso este ajuste pequeno converge sin hacer cambios bruscos.
    local pos = toggle.Position
    local step = math.clamp(difference, -70, 70)
    toggle.Position = UDim2.new(
        pos.X.Scale, pos.X.Offset + step,
        pos.Y.Scale, pos.Y.Offset
    )
end)
