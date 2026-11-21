--!strict
-- One modal popup at a time: title, message, and one or two buttons.
--   PopupController.show("Pedestals full!", "Sell them?", "Sell", "Keep", function(confirmed) ... end)
--
-- Expects StarterGui.Popup (ScreenGui, ResetOnSpawn off, Enabled off) with descendants
--   TitleLabel (TextLabel), BodyLabel (TextLabel), ConfirmButton (TextButton), CancelButton (TextButton)
-- If it's missing, a plain placeholder popup is built.

local Players = game:GetService("Players")

local PopupController = {}

local localPlayer = Players.LocalPlayer

local gui: ScreenGui? = nil
local titleLabel: TextLabel? = nil
local bodyLabel: TextLabel? = nil
local confirmButton: TextButton? = nil
local cancelButton: TextButton? = nil
local onClose: ((confirmed: boolean) -> ())? = nil

-- How long to wait for StarterGui.Popup to be copied into PlayerGui.
local GUI_WAIT_SECONDS = 5

local function buildPlaceholder(playerGui: PlayerGui): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "Popup"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.DisplayOrder = 10

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(340, 200)
	frame.BackgroundColor3 = Color3.fromRGB(30, 45, 75)
	frame.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame

	local function text(className: string, name: string, position: UDim2, size: UDim2): any
		local item = Instance.new(className) :: any
		item.Name = name
		item.Position = position
		item.Size = size
		item.Font = Enum.Font.FredokaOne
		item.TextScaled = true
		item.TextColor3 = Color3.new(1, 1, 1)
		item.Parent = frame
		return item
	end
	local title = text("TextLabel", "TitleLabel", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 34))
	title.BackgroundTransparency = 1
	local body = text("TextLabel", "BodyLabel", UDim2.fromOffset(16, 52), UDim2.new(1, -32, 0, 80))
	body.BackgroundTransparency = 1
	body.TextScaled = false
	body.TextSize = 18
	body.TextWrapped = true
	local confirm = text("TextButton", "ConfirmButton", UDim2.new(0, 16, 1, -56), UDim2.new(0.5, -24, 0, 42))
	confirm.BackgroundColor3 = Color3.fromRGB(80, 190, 110)
	local cancel = text("TextButton", "CancelButton", UDim2.new(0.5, 8, 1, -56), UDim2.new(0.5, -24, 0, 42))
	cancel.BackgroundColor3 = Color3.fromRGB(120, 130, 150)

	screen.Parent = playerGui
	return screen
end

local function find(root: Instance, name: string, className: string): any
	local found = root:FindFirstChild(name, true)
	if found and found:IsA(className) then
		return found
	end
	warn(string.format("[PopupController] Missing StarterGui.Popup.%s (%s)", name, className))
	return nil
end

local function close(confirmed: boolean)
	if gui then
		gui.Enabled = false
	end
	local callback = onClose
	onClose = nil
	if callback then
		callback(confirmed)
	end
end

-- `cancelText` nil = single-button popup. A new popup replaces (and cancels) an open one.
function PopupController.show(
	title: string,
	body: string,
	confirmText: string,
	cancelText: string?,
	callback: ((confirmed: boolean) -> ())?
)
	if not gui then
		warn("[PopupController] Popup not ready: " .. title)
		return
	end
	if onClose then
		close(false)
	end
	onClose = callback
	if titleLabel then
		titleLabel.Text = title
	end
	if bodyLabel then
		bodyLabel.Text = body
	end
	if confirmButton then
		confirmButton.Text = confirmText
	end
	if cancelButton then
		cancelButton.Visible = cancelText ~= nil
		cancelButton.Text = cancelText or ""
	end
	gui.Enabled = true
end

function PopupController.init() end

-- Looked up in start (not init) so waiting for the GUI never delays other controllers.
function PopupController.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local found = playerGui:WaitForChild("Popup", GUI_WAIT_SECONDS)
	if not (found and found:IsA("ScreenGui")) then
		warn("[PopupController] StarterGui.Popup (ScreenGui) is missing. Using a placeholder popup.")
		found = buildPlaceholder(playerGui)
	end
	gui = found :: ScreenGui
	local root = found :: Instance
	titleLabel = find(root, "TitleLabel", "TextLabel")
	bodyLabel = find(root, "BodyLabel", "TextLabel")
	confirmButton = find(root, "ConfirmButton", "TextButton")
	cancelButton = find(root, "CancelButton", "TextButton")
	if confirmButton then
		confirmButton.Activated:Connect(function()
			close(true)
		end)
	end
	if cancelButton then
		cancelButton.Activated:Connect(function()
			close(false)
		end)
	end
end

return PopupController
