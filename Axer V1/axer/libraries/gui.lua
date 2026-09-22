-- Axer in-house GUI library.
--   One ScreenGui, draggable window, Vape-style top tabs, module cards,
--   option widgets (Toggle/Slider/List/Button/Keybind/TextBox), notifications.
-- Modules register options via module:AddOption('Toggle', 'id', { ... }).
-- Loaded as: local GuiLibrary = loadstring(source, 'gui')(AxerCore)

return function(Axer)
	local GuiLibrary = {}

	local function theme()
		return Axer.Util.Theme
	end

	local function notify(text, duration)
		return Axer.Util.Notify(text, duration)
	end

-- Parent the ScreenGui via CoreGui -> PlayerGui fallback.
local function safeParent(gui)
	local ok = pcall(function()
		gui.Parent = game:GetService('CoreGui')
	end)
	if ok and gui.Parent then return end
	gui.Parent = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')
end

function GuiLibrary.new(core)
	local self = setmetatable({}, { __index = GuiLibrary })
	self.Core = core
	self.ScreenGui = Instance.new('ScreenGui')
	self.ScreenGui.Name = 'AxerV1'
	self.ScreenGui.ResetOnSpawn = false
	self.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	safeParent(self.ScreenGui)

	self.Tabs = {}
	self.TabOrder = {}
	self.CurrentTab = nil
	self.Open = false
	self.Root = nil
	return self
end

function GuiLibrary:Build()
	if self.Root then return end
	local t = theme()

	local root = Instance.new('ScreenGui')
	root.Name = 'AxerWindow'
	root.ResetOnSpawn = false
	self.ScreenGui:Destroy()
	self.ScreenGui = root
	safeParent(root)
	self.Root = root

	local window = Instance.new('Frame')
	window.Name = 'Window'
	window.Size = UDim2.new(0, 560, 0, 360)
	window.Position = UDim2.new(0.5, -280, 0.5, -180)
	window.BackgroundColor3 = t.Background
	window.BorderSizePixel = 0
	window.Active = true
	window.Parent = root

	Instance.new('UICorner', window).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new('UIStroke', window)
	stroke.Color = t.Accent
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35

	-- Title bar + drag.
	local titleBar = Instance.new('Frame')
	titleBar.Name = 'TitleBar'
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = window

	local title = Instance.new('TextLabel')
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = t.FontBold
	title.TextSize = 16
	title.TextColor3 = t.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = 'Axer V1'
	title.Parent = titleBar

	local dragInput, dragStart, startPos
	local dragging = false
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	titleBar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	game:GetService('UserInputService').InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	-- Tab strip.
	local tabStrip = Instance.new('Frame')
	tabStrip.Name = 'TabStrip'
	tabStrip.Size = UDim2.new(1, -28, 0, 34)
	tabStrip.Position = UDim2.new(0, 14, 0, 36)
	tabStrip.BackgroundTransparency = 1
	tabStrip.Parent = window
	local stripLayout = Instance.new('UIListLayout', tabStrip)
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, 6)

	-- Content area: one page per tab.
	local content = Instance.new('Frame')
	content.Name = 'Content'
	content.Size = UDim2.new(1, -28, 1, -92)
	content.Position = UDim2.new(0, 14, 0, 78)
	content.BackgroundTransparency = 1
	content.Parent = window

	self.Window = window
	self.Content = content
	self.TabStrip = tabStrip

	-- Open/close keybind.
	game:GetService('UserInputService').InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			self:SetOpen(not self.Open)
		end
	end)

	self:SetOpen(true)
end

function GuiLibrary:SetOpen(open)
	self.Open = open
	if self.Root then
		self.Root.Enabled = open
	end
end

function GuiLibrary:CreateTab(name)
	if self.Tabs[name] then return self.Tabs[name] end
	self:Build()

	local t = theme()
	local tabButton = Instance.new('TextButton')
	tabButton.Size = UDim2.new(0, 92, 1, 0)
	tabButton.BackgroundColor3 = t.BackgroundSoft
	tabButton.BorderSizePixel = 0
	tabButton.Font = t.Font
	tabButton.TextSize = 14
	tabButton.TextColor3 = t.TextDim
	tabButton.Text = name
	tabButton.AutoButtonColor = false
	tabButton.Parent = self.TabStrip
	Instance.new('UICorner', tabButton).CornerRadius = UDim.new(0, 8)

	local page = Instance.new('ScrollingFrame')
	page.Name = name
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = t.Accent
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = self.Content
	local pageLayout = Instance.new('UIListLayout', page)
	pageLayout.Padding = UDim.new(0, 6)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local pad = Instance.new('UIPadding', page)
	pad.PaddingRight = UDim.new(0, 8)

	local tab = { Name = name, Button = tabButton, Page = page, Order = #self.TabOrder + 1 }
	self.Tabs[name] = tab
	table.insert(self.TabOrder, name)

	tabButton.MouseButton1Click:Connect(function()
		self:SelectTab(name)
	end)

	if not self.CurrentTab then
		self:SelectTab(name)
	end
	return tab
end

function GuiLibrary:SelectTab(name)
	local tab = self.Tabs[name]
	if not tab then return end
	self.CurrentTab = name
	local t = theme()
	for _, other in pairs(self.Tabs) do
		other.Page.Visible = (other.Name == name)
		local selected = other.Name == name
		other.Button.BackgroundColor3 = selected and t.AccentDim or t.BackgroundSoft
		other.Button.TextColor3 = selected and t.Text or t.TextDim
	end
end

----------------------------------------------------------------------
-- Option widgets
----------------------------------------------------------------------

-- Shared card: module name row + optional description + option container.
function GuiLibrary:CreateModuleCard(mod)
	self:Build()
	local tab = self:CreateTab(mod.Tab)
	local t = theme()

	local card = Instance.new('Frame')
	card.Name = mod.Name
	card.Size = UDim2.new(1, 0, 0, 44)
	card.BackgroundColor3 = t.BackgroundSoft
	card.BorderSizePixel = 0
	card.Parent = tab.Page
	Instance.new('UICorner', card).CornerRadius = UDim.new(0, 8)

	local layout = Instance.new('UIListLayout', card)
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local header = Instance.new('TextButton')
	header.Name = 'Header'
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundTransparency = 1
	header.Font = t.Font
	header.TextSize = 14
	header.TextColor3 = t.Text
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = '  '..mod.Name
	header.Parent = card

	local dot = Instance.new('Frame')
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.Position = UDim2.new(1, -18, 0, 16)
	dot.BackgroundColor3 = t.Off
	dot.Parent = header
	Instance.new('UICorner', dot).CornerRadius = UDim.new(0, 8)

	if mod.Description ~= '' then
		header.TextSize = 13
		local desc = Instance.new('TextLabel')
		desc.Size = UDim2.new(1, -36, 0, 14)
		desc.Position = UDim2.new(0, 14, 0, 26)
		desc.BackgroundTransparency = 1
		desc.Font = t.Font
		desc.TextSize = 11
		desc.TextColor3 = t.TextDim
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = mod.Description
		desc.Parent = card
	end

	header.MouseButton1Click:Connect(function()
		mod:Toggle()
	end)

	mod._Core.ModuleToggled:Connect(function(name, enabled)
		if name == mod.Name then
			dot.BackgroundColor3 = enabled and t.On or t.Off
		end
	end)

	local optionCount = 0

	local cardApi = {}

	local function autoSize()
		local height = 44 + optionCount * 30
		card.Size = UDim2.new(1, 0, 0, height)
	end

	function cardApi.AddOption(optionType, id, def)
		def = def or {}
		optionCount += 1
		local row = Instance.new('Frame')
		row.Name = id
		row.BackgroundColor3 = t.BackgroundLight
		row.BorderSizePixel = 0
		row.LayoutOrder = optionCount
		row.Parent = card
		Instance.new('UICorner', row).CornerRadius = UDim.new(0, 6)
		row.Size = UDim2.new(1, -8, 0, 26)

		local label = Instance.new('TextLabel')
		label.Size = UDim2.new(1, -16, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = t.Font
		label.TextSize = 12
		label.TextColor3 = t.TextDim
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = def.Name or id
		label.Parent = row

		local option = { Type = optionType, Name = def.Name or id, Value = def.Default, Save = def.Save ~= false }

		-- Widget construction per type.
		if optionType == 'Toggle' then
			local pill = Instance.new('TextButton')
			pill.Size = UDim2.new(0, 34, 0, 18)
			pill.Position = UDim2.new(1, -42, 0, 4)
			pill.BackgroundColor3 = t.Off
			pill.Text = ''
			pill.Font = t.Font
			pill.BorderSizePixel = 0
			pill.AutoButtonColor = false
			pill.Parent = row
			Instance.new('UICorner', pill).CornerRadius = UDim.new(0, 9)

			local knob = Instance.new('Frame')
			knob.Size = UDim2.new(0, 14, 0, 14)
			knob.Position = UDim2.new(0, 2, 0, 2)
			knob.BackgroundColor3 = t.Text
			knob.Parent = pill
			Instance.new('UICorner', knob).CornerRadius = UDim.new(0, 7)

			function option.Set(value)
				option.Value = value
				pill.BackgroundColor3 = value and t.Accent or t.Off
				knob.Position = value and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 2, 0, 2)
			end
			pill.MouseButton1Click:Connect(function()
				option.Set(not option.Value)
				if mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end
			end)
			option.Set(option.Value == true)

		elseif optionType == 'Slider' then
			local value = Instance.new('TextLabel')
			value.Size = UDim2.new(0, 44, 1, 0)
			value.Position = UDim2.new(1, -52, 0, 0)
			value.BackgroundTransparency = 1
			value.Font = t.Font
			value.TextSize = 12
			value.TextColor3 = t.Text
			value.Text = tostring(def.Default or def.Min or 0)
			value.Parent = row

			local bar = Instance.new('TextButton')
			bar.Size = UDim2.new(1, -110, 0, 6)
			bar.Position = UDim2.new(0, 10, 0.5, -3)
			bar.BackgroundColor3 = t.Off
			bar.Text = ''
			bar.BorderSizePixel = 0
			bar.AutoButtonColor = false
			bar.Parent = row
			Instance.new('UICorner', bar).CornerRadius = UDim.new(0, 3)

			local fill = Instance.new('Frame')
			fill.Size = UDim2.new(0.5, 0, 1, 0)
			fill.BackgroundColor3 = t.Accent
			fill.BorderSizePixel = 0
			fill.Parent = bar
			Instance.new('UICorner', fill).CornerRadius = UDim.new(0, 3)

			local min = def.Min or 0
			local max = def.Max or 100

			local function setFromFraction(fraction)
					fraction = math.clamp(fraction, 0, 1)
					if max - min <= 0 then
						option.Value = min
						value.Text = tostring(min)
						fill.Size = UDim2.new(0, 0, 1, 0)
						return
					end
					local raw = min + (max - min) * fraction
				local rounded = math.floor(raw + 0.5)
				if def.Step then
					rounded = math.floor(raw / def.Step + 0.5) * def.Step
				end
				option.Value = rounded
				value.Text = tostring(rounded)
				fill.Size = UDim2.new(fraction, 0, 1, 0)
			end

			local draggingSlider = false
			bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					draggingSlider = true
					local absPos = bar.AbsolutePosition
					setFromFraction((input.Position.X - absPos.X) / bar.AbsoluteSize.X)
				end
			end)
			game:GetService('UserInputService').InputChanged:Connect(function(input)
				if draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
					local absPos = bar.AbsolutePosition
					setFromFraction((input.Position.X - absPos.X) / bar.AbsoluteSize.X)
				end
			end)
			game:GetService('UserInputService').InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					draggingSlider = false
					if mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end
				end
			end)
			setFromFraction(((def.Default or min) - min) / (max - min))

		elseif optionType == 'List' then
			local current = Instance.new('TextButton')
			current.Size = UDim2.new(0, 120, 0, 20)
			current.Position = UDim2.new(1, -128, 0, 3)
			current.BackgroundColor3 = t.Background
			current.Font = t.Font
			current.TextSize = 12
			current.TextColor3 = t.Text
			current.Text = def.Default or (def.Options and def.Options[1]) or ''
			current.BorderSizePixel = 0
			current.AutoButtonColor = false
			current.Parent = row
			Instance.new('UICorner', current).CornerRadius = UDim.new(0, 6)

			option.Value = current.Text
			local open = false
			local dropdown
			current.MouseButton1Click:Connect(function()
				if open and dropdown then
					dropdown:Destroy()
					dropdown = nil
					open = false
					return
				end
				open = true
				dropdown = Instance.new('ScrollingFrame')
				dropdown.Size = UDim2.new(0, 120, 0, math.min(#def.Options * 22, 88))
				dropdown.Position = UDim2.new(0, 0, 1, 4)
				dropdown.BackgroundColor3 = t.Background
				dropdown.BorderSizePixel = 0
				dropdown.ScrollBarThickness = 3
				dropdown.CanvasSize = UDim2.new(0, 0, 0, 0)
				dropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y
				dropdown.Parent = current
				Instance.new('UICorner', dropdown).CornerRadius = UDim.new(0, 6)
				local listLayout = Instance.new('UIListLayout', dropdown)
				listLayout.SortOrder = Enum.SortOrder.LayoutOrder

				for i, entry in ipairs(def.Options or {}) do
					local item = Instance.new('TextButton')
					item.Size = UDim2.new(1, 0, 0, 22)
					item.BackgroundColor3 = t.Background
					item.Font = t.Font
					item.TextSize = 12
					item.TextColor3 = t.TextDim
					item.Text = entry
					item.BorderSizePixel = 0
					item.LayoutOrder = i
					item.AutoButtonColor = false
					item.Parent = dropdown
					item.MouseEnter:Connect(function() item.BackgroundColor3 = t.BackgroundLight end)
					item.MouseLeave:Connect(function() item.BackgroundColor3 = t.Background end)
					item.MouseButton1Click:Connect(function()
						option.Value = entry
						current.Text = entry
						dropdown:Destroy()
						dropdown = nil
						open = false
						if def.Callback then def.Callback(entry) end
						if mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end
					end)
				end
			end)

		elseif optionType == 'Button' then
			row.Active = true
			label.TextColor3 = t.Accent
			row.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and def.Callback then
					task.spawn(def.Callback)
				end
			end)

		elseif optionType == 'Keybind' then
			local bind = Instance.new('TextButton')
			bind.Size = UDim2.new(0, 70, 0, 20)
			bind.Position = UDim2.new(1, -78, 0, 3)
			bind.BackgroundColor3 = t.Background
			bind.Font = t.Font
			bind.TextSize = 11
			bind.TextColor3 = t.Text				local defaultBind = 'None'
				if def.Default then
					defaultBind = (type(def.Default) == 'table' or type(def.Default) == 'userdata')
						and def.Default.Name
						or tostring(def.Default)
				end
				bind.Text = defaultBind
			bind.BorderSizePixel = 0
			bind.AutoButtonColor = false
			bind.Parent = row
			Instance.new('UICorner', bind).CornerRadius = UDim.new(0, 6)

			option.Value = def.Default

			bind.MouseButton1Click:Connect(function()
				bind.Text = '...'
				local conn
				conn = game:GetService('UserInputService').InputBegan:Connect(function(input, processed)
					if processed then return end
					if input.UserInputType == Enum.UserInputType.Keyboard then
						option.Value = input.KeyCode
						bind.Text = input.KeyCode.Name
						conn:Disconnect()
						if mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end
					end
				end)
			end)
			if def.Callback then
				game:GetService('UserInputService').InputBegan:Connect(function(input, processed)
					if processed then return end
					if input.KeyCode == option.Value and input.UserInputType == Enum.UserInputType.Keyboard then
						def.Callback()
					end
				end)
			end

		elseif optionType == 'TextBox' then
			local box = Instance.new('TextBox')
			box.Size = UDim2.new(0, 120, 0, 20)
			box.Position = UDim2.new(1, -128, 0, 3)
			box.BackgroundColor3 = t.Background
			box.Font = t.Font
			box.TextSize = 12
			box.TextColor3 = t.Text
			box.PlaceholderText = def.Placeholder or ''
			box.Text = def.Default or ''
			box.ClearTextOnFocus = false
			box.BorderSizePixel = 0
			box.Parent = row
			Instance.new('UICorner', box).CornerRadius = UDim.new(0, 6)
			box:GetPropertyChangedSignal('Text'):Connect(function()
				option.Value = box.Text
			end)
			option.Value = box.Text
		end

		-- Register for config persistence.
		mod._Options[id] = option
		autoSize()
		if option.Set and option.Value ~= nil then
			option.Set(option.Value)
		end
		return option
	end

	mod._Card = cardApi
	return cardApi
end

function GuiLibrary:AddOption(mod, optionType, id, def)
	-- Route through the module card; create it lazily.
	local card = mod._Card or self:CreateModuleCard(mod)
	return card.AddOption(optionType, id, def)
end

function GuiLibrary:Notify(text, duration)
	notify(text, duration)
end

function GuiLibrary:Destroy()
	if self.Root then
		self.Root:Destroy()
		self.Root = nil
	end
end

return GuiLibrary
end
