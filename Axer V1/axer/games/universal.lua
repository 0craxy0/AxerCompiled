-- Axer universal modules: loaded for every game (PlaceId-specific files
-- override this by being present). Keep modules client-side and benign here;
-- game-specific behavior belongs in axer/games/<PlaceId>.lua.

-- Game chunks receive Axer as a vararg (main.lua passes it); the global is
-- the fallback when executed directly in an executor environment.
local Axer = Axer or (...)

-- Fullbright ---------------------------------------------------------------
Axer.CreateModule({
	Name = 'Fullbright',
	Description = 'Brightens the world',
	Tab = 'Render',
	OnEnable = function(self)
		local Lighting = game:GetService('Lighting')
		self._old = {
			Brightness = Lighting.Brightness,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			ClockTime = Lighting.ClockTime,
			FogEnd = Lighting.FogEnd,
			GlobalShadows = Lighting.GlobalShadows,
		}
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.fromRGB(200, 200, 200)
		Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
		Lighting.ClockTime = 14
		Lighting.FogEnd = 1e6
		Lighting.GlobalShadows = false
	end,
	OnDisable = function(self)
		local Lighting = game:GetService('Lighting')
		if self._old then
			Lighting.Brightness = self._old.Brightness
			Lighting.Ambient = self._old.Ambient
			Lighting.OutdoorAmbient = self._old.OutdoorAmbient
			Lighting.ClockTime = self._old.ClockTime
			Lighting.FogEnd = self._old.FogEnd
			Lighting.GlobalShadows = self._old.GlobalShadows
			self._old = nil
		end
	end,
})

-- FPS Booster --------------------------------------------------------------
Axer.CreateModule({
	Name = 'FPS Booster',
	Description = 'Lowers rendering quality for more FPS',
	Tab = 'Render',
	OnEnable = function(self)
		local Lighting = game:GetService('Lighting')
		local Terrain = workspace:FindFirstChildOfClass('Terrain')
		self._old = {
			WaterWaveSize = Terrain and Terrain.WaterWaveSize or 0,
			WaterWaveSpeed = Terrain and Terrain.WaterWaveSpeed or 10,
			WaterReflectance = Terrain and Terrain.WaterReflectance or 0,
			WaterTransparency = Terrain and Terrain.WaterTransparency or 0.5,
			Shadows = Lighting.GlobalShadows,
		}
		if Terrain then
			Terrain.WaterWaveSize = 0
			Terrain.WaterWaveSpeed = 0
			Terrain.WaterReflectance = 0
			Terrain.WaterTransparency = 1
		end
		Lighting.GlobalShadows = false
		-- Effects: remove particles/beams under a cap on every render step is
		-- too aggressive for a default module; just disable expensive services.
		pcall(function()
			game:GetService('Lighting').ChildAdded:Connect(function(child)
				if child:IsA('PostEffect') then
					child.Enabled = false
				end
			end)
		end)
	end,
	OnDisable = function(self)
		local Lighting = game:GetService('Lighting')
		local Terrain = workspace:FindFirstChildOfClass('Terrain')
		if self._old then
			if Terrain then
				Terrain.WaterWaveSize = self._old.WaterWaveSize
				Terrain.WaterWaveSpeed = self._old.WaterWaveSpeed
				Terrain.WaterReflectance = self._old.WaterReflectance
				Terrain.WaterTransparency = self._old.WaterTransparency
			end
			Lighting.GlobalShadows = self._old.Shadows
			self._old = nil
		end
	end,
})

-- Panic Button -------------------------------------------------------------
Axer.CreateModule({
	Name = 'Panic Button',
	Description = 'Keybind that disables every module instantly',
	Tab = 'Utility',
	Init = function(self)
		self:AddOption('Keybind', 'panicKey', {
			Name = 'Panic key',
			Default = Enum.KeyCode.Delete,
			Callback = function()
				Axer.Panic()
			end,
		})
	end,
})

-- HUD Overlay --------------------------------------------------------------
Axer.CreateModule({
	Name = 'HUD Overlay',
	Description = 'Simple FPS and ping counter in the corner',
	Tab = 'Render',
	OnEnable = function(self)
		local Players = game:GetService('Players')
		local RunService = game:GetService('RunService')
		local Stats = game:GetService('Stats')

		local gui = Instance.new('ScreenGui')
		gui.Name = 'AxerHudOverlay'
		gui.ResetOnSpawn = false
		local label = Instance.new('TextLabel')
		label.Size = UDim2.new(0, 180, 0, 24)
		label.Position = UDim2.new(0, 10, 0, 10)
		label.BackgroundColor3 = Axer.Util.Theme.Background
		label.BackgroundTransparency = 0.35
		label.TextColor3 = Axer.Util.Theme.Text
		label.Font = Axer.Util.Theme.Font
		label.TextSize = 13
		label.Text = ''
		label.Parent = gui
		Axer.Util.SafeParent(gui)

		local frameCount, lastRefresh = 0, os.clock()
		self:Track(RunService.RenderStepped:Connect(function()
			frameCount += 1
			local now = os.clock()
			if now - lastRefresh >= 0.5 then
				local fps = math.floor(frameCount / (now - lastRefresh) + 0.5)
				local ping = 0
				pcall(function()
					ping = math.floor(Stats.Network.ServerStatsItem['Data Ping']:GetValue() + 0.5)
				end)
				label.Text = ('FPS %d | Ping %d ms'):format(fps, ping)
				frameCount, lastRefresh = 0, now
			end
		end))
		self._gui = gui
	end,
	OnDisable = function(self)
		if self._gui then
			self._gui:Destroy()
			self._gui = nil
		end
	end,
})

Axer.Notify('Universal modules registered.', 3)
