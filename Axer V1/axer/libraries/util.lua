-- Axer shared utilities: theme, signals, safe parenting, notifications.
-- Loaded as: local Util = loadstring(source, 'util')(AxerCore)

return function(Axer)
	local Util = {}

	Util.Theme = {
		Accent = Color3.fromRGB(138, 43, 226),
		AccentDim = Color3.fromRGB(96, 30, 158),
		Background = Color3.fromRGB(24, 24, 30),
		BackgroundSoft = Color3.fromRGB(32, 32, 40),
		BackgroundLight = Color3.fromRGB(44, 44, 54),
		Stroke = Color3.fromRGB(60, 60, 74),
		Text = Color3.fromRGB(235, 235, 240),
		TextDim = Color3.fromRGB(160, 160, 175),
		On = Color3.fromRGB(120, 255, 160),
		Off = Color3.fromRGB(90, 90, 105),
		Font = Enum.Font.Gotham,
		FontBold = Enum.Font.GothamBold,
	}

	-- Tiny signal implementation (no BindableEvent overhead).
	local Signal = {}
	Signal.__index = Signal

	function Signal.new()
		return setmetatable({ _handlers = {} }, Signal)
	end

	function Signal:Connect(fn)
		local handler = { fn = fn }
		self._handlers[handler] = true
		return {
			Disconnect = function()
				self._handlers[handler] = nil
			end,
		}
	end

	function Signal:Fire(...)
		for handler in pairs(self._handlers) do
			task.spawn(handler.fn, ...)
		end
	end

	function Signal:Destroy()
		table.clear(self._handlers)
	end

	Util.Signal = Signal
	Util.NewSignal = function()
		return Signal.new()
	end

	-- Parent to CoreGui when possible, PlayerGui otherwise.
	function Util.SafeParent(instance)
		local ok = pcall(function()
			instance.Parent = game:GetService('CoreGui')
		end)
		if ok and instance.Parent then
			return 'CoreGui'
		end
		instance.Parent = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')
		return 'PlayerGui'
	end

	-- Round-cornered notification, bottom-right.
	function Util.Notify(text, duration)
		local holder = nil
		local okCore = pcall(function()
			holder = game:GetService('CoreGui'):FindFirstChild('AxerNotifications')
		end)
		if not okCore or not holder then
			local playerGui = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')
			holder = playerGui:FindFirstChild('AxerNotifications')
		end
		if not holder then
			holder = Instance.new('ScreenGui')
			holder.Name = 'AxerNotifications'
			holder.ResetOnSpawn = false
			holder.IgnoreGuiInset = true
			Util.SafeParent(holder)
		end

		local frame = Instance.new('Frame')
		frame.Size = UDim2.new(0, 260, 0, 42)
		frame.Position = UDim2.new(1, 20, 1, -70)
		frame.BackgroundColor3 = Util.Theme.Background
		frame.BorderSizePixel = 0
		frame.Parent = holder

		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame

		local stroke = Instance.new('UIStroke')
		stroke.Color = Util.Theme.Accent
		stroke.Thickness = 1
		stroke.Transparency = 0.4
		stroke.Parent = frame

		local label = Instance.new('TextLabel')
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 12, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Util.Theme.Font
		label.TextSize = 14
		label.TextColor3 = Util.Theme.Text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Text = text
		label.Parent = frame

		frame:TweenPosition(
			UDim2.new(1, -280, 1, -70),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quart,
			0.3,
			true
		)
		task.delay(duration or 3, function()
			frame:TweenPosition(
				UDim2.new(1, 20, 1, -70),
				Enum.EasingDirection.In,
				Enum.EasingStyle.Quart,
				0.25,
				true
			)
			task.wait(0.3)
			frame:Destroy()
		end)
	end

	return Util
end
