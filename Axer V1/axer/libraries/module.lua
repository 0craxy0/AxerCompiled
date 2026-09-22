-- Axer module registry. Usage (inside a game module file):
--   Axer.CreateModule{
--       Name = 'Fullbright',
--       Description = 'Removes darkness',
--       Tab = 'Render',                    -- which GUI tab the module sits in
--       Init = function(self) ... end,     -- called once after registration
--       OnEnable = function(self) ... end, -- called on every enable
--       OnDisable = function(self) ... end,
--   }
-- Modules get: self.Enabled, :Toggle(state?), :Track(connection) (auto-
-- disconnected on disable), :AddOption(type, id, def) for GUI widgets,
-- :GetOption(id), :SetOption(id, value).
-- Loaded as: local ModuleLib = loadstring(source, 'module')(AxerCore)

return function(Axer)
	local ModuleLib = {}
	local Module = {}
	Module.__index = Module

	local function noop() end

	local function disconnectAll(connections)
		for _, conn in ipairs(connections) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		table.clear(connections)
	end

	function ModuleLib.new(core)
		local registry = {
			Core = core,
			Modules = {},
			Order = {},
			ModuleAdded = core.Util.NewSignal(),
		}
		return setmetatable(registry, { __index = ModuleLib })
	end

	function ModuleLib:CreateModule(def)
		assert(type(def) == 'table' and type(def.Name) == 'string', '[Axer] CreateModule: Name required')
		assert(self.Modules[def.Name] == nil, ('[Axer] Duplicate module name: %s'):format(def.Name))

		local mod = setmetatable({
			Name = def.Name,
			Description = def.Description or '',
			Tab = def.Tab or 'Utility',
			Enabled = false,
			_Connections = {},
			_Options = {},
			_Def = def,
			_Core = self.Core,
		}, Module)

		function mod:Track(connection)
			table.insert(self._Connections, connection)
			return connection
		end

		function mod:AddOption(optionType, id, optionDef)
			local gui = self._Core.GuiLibrary
			if gui then
				return gui:AddOption(self, optionType, id, optionDef)
			end
			return nil
		end

		function mod:GetOption(id)
			return self._Options[id] and self._Options[id].Value
		end

		function mod:SetOption(id, value)
			local option = self._Options[id]
			if option then
				option.Value = value
				if option.Set then
					option.Set(value)
				end
				if self._Core.SaveLibrary then
					self._Core.SaveLibrary:QueueSave()
				end
			end
		end

		function mod:Toggle(state)
			local target = state == nil and not self.Enabled or state
			if target == self.Enabled then
				return self.Enabled
			end
			self.Enabled = target
			if target then
				(self._Def.OnEnable or noop)(self)
			else
				(self._Def.OnDisable or noop)(self)
				disconnectAll(self._Connections)
			end
			if self._Core.SaveLibrary then
				self._Core.SaveLibrary:QueueSave()
			end
			self._Core.ModuleToggled:Fire(self.Name, self.Enabled)
			return self.Enabled
		end

		self.Modules[def.Name] = mod
		table.insert(self.Order, mod.Name)
		self.ModuleAdded:Fire(mod)
		if def.Init then
			task.spawn(def.Init, mod)
		end
		return mod
	end

	function ModuleLib:GetModule(name)
		return self.Modules[name]
	end

	function ModuleLib:GetAll()
		return self.Modules
	end

	function ModuleLib:DisableAll()
		for _, name in ipairs(self.Order) do
			local mod = self.Modules[name]
			if mod.Enabled then
				mod:Toggle(false)
			end
		end
	end

	-- Serializes all modules + option values for config saving.
	function ModuleLib:Serialize()
		local out = {}
		for _, name in ipairs(self.Order) do
			local mod = self.Modules[name]
			local options = {}
			for id, option in pairs(mod._Options) do
				if option.Save ~= false then
					local value = option.Value
					if typeof(value) == 'EnumItem' then
						value = value.Name
					end
					options[id] = value
				end
			end
			out[name] = { Enabled = mod.Enabled, Options = options }
		end
		return out
	end

	-- Restores state from a config table (GUI widgets update via option.Set).
	function ModuleLib:Restore(data)
		if type(data) ~= 'table' then
			return
		end
		for _, name in ipairs(self.Order) do
			local saved = data[name]
			local mod = self.Modules[name]
			if mod and type(saved) == 'table' then
				for id, value in pairs(saved.Options or {}) do
					local option = mod._Options[id]
					if option then
						if option.EnumType and type(value) == 'string' then
							local ok, enumValue = pcall(function()
								return option.EnumType[value]
							end)
							option.Value = ok and enumValue or option.Value
						else
							option.Value = value
						end
						if option.Set then
							option.Set(option.Value)
						end
					end
				end
				if saved.Enabled and not mod.Enabled then
					mod:Toggle(true)
				end
			end
		end
	end

	return ModuleLib
end
