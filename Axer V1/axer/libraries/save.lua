-- Axer config profiles. Persists module + option state per game as JSON:
--   axer/profiles/<PlaceId>/config.json
-- Loaded as: local SaveLib = loadstring(source, 'save')(AxerCore)

return function(Axer)
	local SaveLib = {}

	function SaveLib.new(core)
		local self = setmetatable({}, { __index = SaveLib })
		self.Core = core
		self.Shims = core.Shims
		self.QueueTimer = nil
		self.PlaceId = tostring(game.PlaceId)
		self.ProfileDir = 'axer/profiles/'..self.PlaceId
		self.ConfigPath = self.ProfileDir..'/config.json'

		self.Shims.MakeFolder('axer/profiles')
		self.Shims.MakeFolder(self.ProfileDir)
		return self
	end

	function SaveLib:Load()
		local raw = self.Shims.ReadFile(self.ConfigPath)
		if not raw then
			return nil
		end
		local ok, decoded = pcall(function()
			return game:GetService('HttpService'):JSONDecode(raw)
		end)
		if ok then
			return decoded
		end
		warn('[Axer] Config file was corrupted, starting fresh:', self.ConfigPath)
		return nil
	end

	function SaveLib:Save(data)
		local ok, encoded = pcall(function()
			return game:GetService('HttpService'):JSONEncode(data)
		end)
		if not ok then
			warn('[Axer] Failed to encode config:', encoded)
			return false
		end
		return self.Shims.WriteFile(self.ConfigPath, encoded)
	end

	-- Debounced autosave: coalesces rapid changes into one write.
	function SaveLib:QueueSave()
		if self.QueueTimer then
			task.cancel(self.QueueTimer)
		end
		self.QueueTimer = task.delay(1, function()
			self.QueueTimer = nil
			self:Save(self.Core.ModuleLibrary:Serialize())
		end)
	end

	function SaveLib:RestoreNow()
		local data = self:Load()
		if data then
			self.Core.ModuleLibrary:Restore(data)
		end
	end

	function SaveLib:Wipe()
		self.Shims.DelFile(self.ConfigPath)
	end

	return SaveLib
end
