-- SensibilidadeCamera.luau
-- Troca a sensibilidade de câmera no toque, em qualquer jogo.
--
-- COMO FUNCIONA (importante entender, já que o freedom.lua não funcionava):
-- A Roblox NÃO expõe sensibilidade de toque como propriedade/Instance dentro
-- do CameraModule — por isso ":FindFirstChild('TouchSensitivityX')" sempre
-- dava nil. A forma que funciona é ASSUMIR a câmera (CameraType = Scriptable)
-- e recalcular a rotação manualmente a partir do gesto UserInputService.TouchPan,
-- que é o MESMO evento que o CameraModule nativo usa por baixo dos panos.
-- Ou seja: a gente não "hackeia" nada do jogo, só substitui o controlador de
-- câmera padrão por um nosso, com um multiplicador de sensibilidade ajustável.
--
-- LIMITAÇÕES CONHECIDAS (teste antes de usar em qualquer lugar sério):
-- 1) Não tem anti-clipping (a câmera padrão evita atravessar paredes com
--    raycast; esta versão simples não faz isso ainda).
-- 2) Se o jogo já usa uma câmera Scriptable própria (alguns FPS/jogos
--    autorais fazem isso), os dois vão brigar pelo controle. É exatamente
--    a "interferência" que você desconfiou — por isso o botão ON/OFF abaixo
--    desliga tudo na hora e devolve a câmera padrão.
-- 3) Se a rotação vertical parecer invertida pro seu gosto, troca o sinal
--    de "deltaPitch" (procure o comentário "-- inverter aqui se quiser").

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SAVE_FILE = "camera_sensitivity.txt"
local DEFAULT_DATA = { sensitivity = 1.0 }

-- Mesmo padrão de save/load do MobileButtom (funciona só se o executor
-- tiver writefile/readfile; senão guarda só na sessão)
local function loadSavedData()
	if typeof(readfile) == "function" then
		local ok, raw = pcall(readfile, SAVE_FILE)
		if ok and raw then
			local okDecode, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if okDecode and typeof(decoded) == "table" and decoded.sensitivity then
				return { sensitivity = decoded.sensitivity }
			end
		end
	end
	return DEFAULT_DATA
end

local function saveData(data)
	if typeof(writefile) == "function" then
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(data)
		end)
		if ok then
			pcall(writefile, SAVE_FILE, encoded)
		end
	end
end

local savedData = loadSavedData()

-- Remove GUI anterior (se o script rodar de novo no mesmo teste)
local oldGui = playerGui:FindFirstChild("SensitivityGuiExecutor")
if oldGui then oldGui:Destroy() end

----------------------------------------------------------------
-- ESTADO DA CÂMERA ORBITAL
----------------------------------------------------------------

local camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
end)

local BASE_SENSITIVITY = 0.004 -- converte pixels de toque em radianos
local MIN_PITCH = math.rad(-80)
local MAX_PITCH = math.rad(85)
local MIN_DISTANCE = 2
local HEAD_OFFSET = Vector3.new(0, 2, 0)

local yaw, pitch, distance = 0, 0, 10
local sensitivityMultiplier = savedData.sensitivity
local overrideEnabled = false -- começa desligado por segurança; liga pelo botão

-- Recalcula yaw/pitch/distance a partir de onde a câmera padrão já estava,
-- pra não dar "pulo" visual no exato momento em que a gente assume o controle
local function syncFromCurrentCamera(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local target = root.Position + HEAD_OFFSET
	local dir = camera.CFrame.Position - target
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, 1) * distance
	end

	distance = math.max(dir.Magnitude, MIN_DISTANCE)
	local normalized = dir.Unit
	yaw = math.atan2(normalized.X, normalized.Z)
	pitch = math.asin(math.clamp(normalized.Y, -1, 1))
end

local function updateCamera()
	if not overrideEnabled then return end

	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local target = root.Position + HEAD_OFFSET
	local backVector = Vector3.new(
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		math.cos(pitch) * math.cos(yaw)
	)
	local camPos = target + backVector * distance
	camera.CFrame = CFrame.lookAt(camPos, target)
end

----------------------------------------------------------------
-- LIGAR / DESLIGAR O OVERRIDE
----------------------------------------------------------------

local function setOverrideEnabled(enabled)
	overrideEnabled = enabled
	if enabled then
		if player.Character then
			syncFromCurrentCamera(player.Character)
		end
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

player.CharacterAdded:Connect(function(character)
	if overrideEnabled then
		character:WaitForChild("HumanoidRootPart", 5)
		syncFromCurrentCamera(character)
		camera.CameraType = Enum.CameraType.Scriptable
	end
end)

----------------------------------------------------------------
-- INPUT: TouchPan é o gesto de arrastar na tela (mesmo que a câmera nativa usa)
----------------------------------------------------------------

local lastTotal = Vector2.new()

UserInputService.TouchPan:Connect(function(_touchPositions, totalTranslation, _velocity, state)
	if not overrideEnabled then return end

	if state == Enum.UserInputState.Begin then
		lastTotal = Vector2.new()
		return
	end

	if state == Enum.UserInputState.Change then
		local delta = totalTranslation - lastTotal
		lastTotal = totalTranslation

		local scale = BASE_SENSITIVITY * sensitivityMultiplier
		local deltaYaw = -delta.X * scale
		local deltaPitch = -delta.Y * scale -- inverter aqui se quiser (trocar o sinal)

		yaw += deltaYaw
		pitch = math.clamp(pitch + deltaPitch, MIN_PITCH, MAX_PITCH)
	end
end)

RunService:BindToRenderStep("SensitivityCameraOverride", Enum.RenderPriority.Camera.Value, updateCamera)

----------------------------------------------------------------
-- UI (mesmo estilo visual do MobileButtom)
----------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SensitivityGuiExecutor"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Engrenagem (fica no canto inferior ESQUERDO pra não brigar com o MobileButtom,
-- que usa o canto inferior direito)
local gearToggle = Instance.new("TextButton")
gearToggle.Size = UDim2.new(0, 36, 0, 36)
gearToggle.Position = UDim2.new(0, 12, 1, -12)
gearToggle.AnchorPoint = Vector2.new(0, 1)
gearToggle.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
gearToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
gearToggle.Font = Enum.Font.GothamBold
gearToggle.TextSize = 16
gearToggle.Text = "🎯"
gearToggle.ZIndex = 5
gearToggle.Parent = screenGui

local gearCorner = Instance.new("UICorner")
gearCorner.CornerRadius = UDim.new(1, 0)
gearCorner.Parent = gearToggle

-- Painel
local panel = Instance.new("Frame")
panel.Name = "SensitivityPanel"
panel.Size = UDim2.new(0, 220, 0, 130)
panel.Position = UDim2.new(0, 12, 1, -56)
panel.AnchorPoint = Vector2.new(0, 1)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.ZIndex = 5
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 10)
panelPadding.PaddingLeft = UDim.new(0, 12)
panelPadding.PaddingRight = UDim.new(0, 12)
panelPadding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Padding = UDim.new(0, 10)
panelLayout.Parent = panel

-- Botão ON/OFF
local statusButton = Instance.new("TextButton")
statusButton.Size = UDim2.new(1, 0, 0, 32)
statusButton.LayoutOrder = 1
statusButton.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
statusButton.TextColor3 = Color3.fromRGB(255, 255, 255)
statusButton.Font = Enum.Font.GothamBold
statusButton.TextSize = 14
statusButton.Text = "DESLIGADO (toque pra ligar)"
statusButton.ZIndex = 5
statusButton.Parent = panel

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 8)
statusCorner.Parent = statusButton

local function refreshStatusButton()
	if overrideEnabled then
		statusButton.BackgroundColor3 = Color3.fromRGB(0, 170, 90)
		statusButton.Text = "LIGADO (toque pra desligar)"
	else
		statusButton.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
		statusButton.Text = "DESLIGADO (toque pra ligar)"
	end
end

statusButton.Activated:Connect(function()
	setOverrideEnabled(not overrideEnabled)
	refreshStatusButton()
end)

-- Slider genérico (idêntico ao do MobileButtom)
local function createSlider(parent, layoutOrder, labelPrefix, min, max, initial, step, formatFn, onChange)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 40)
	container.BackgroundTransparency = 1
	container.LayoutOrder = layoutOrder
	container.Parent = parent

	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.new(1, 0, 0, 16)
	labelText.BackgroundTransparency = 1
	labelText.TextColor3 = Color3.fromRGB(255, 255, 255)
	labelText.Font = Enum.Font.Gotham
	labelText.TextSize = 13
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.Parent = container

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 24)
	track.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local thumb = Instance.new("Frame")
	thumb.Size = UDim2.new(0, 20, 0, 20)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.new(0, 0, 0.5, 0)
	thumb.BackgroundColor3 = Color3.fromRGB(0, 170, 220)
	thumb.BorderSizePixel = 0
	thumb.Active = true
	thumb.Parent = track

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	local currentValue = initial

	local function fractionFromValue(v)
		return math.clamp((v - min) / (max - min), 0, 1)
	end

	local function refresh()
		thumb.Position = UDim2.new(fractionFromValue(currentValue), 0, 0.5, 0)
		labelText.Text = labelPrefix .. ": " .. formatFn(currentValue)
	end

	local dragging = false

	local function setFromAbsoluteX(absoluteX)
		local trackPos = track.AbsolutePosition.X
		local trackWidth = track.AbsoluteSize.X
		if trackWidth <= 0 then return end
		local fraction = math.clamp((absoluteX - trackPos) / trackWidth, 0, 1)
		local value = min + fraction * (max - min)
		if step and step > 0 then
			value = math.floor(value / step + 0.5) * step
		end
		currentValue = math.clamp(value, min, max)
		refresh()
		onChange(currentValue)
	end

	local function beginDrag(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromAbsoluteX(input.Position.X)
		end
	end

	thumb.InputBegan:Connect(beginDrag)
	track.InputBegan:Connect(beginDrag)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromAbsoluteX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	refresh()

	return {
		getValue = function()
			return currentValue
		end,
	}
end

local sensitivitySlider = createSlider(
	panel, 2, "Sensibilidade", 0.1, 3, sensitivityMultiplier, 0.05,
	function(v) return string.format("%.2fx", v) end,
	function(v)
		sensitivityMultiplier = v
		saveData({ sensitivity = v })
	end
)

gearToggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

refreshStatusButton()
