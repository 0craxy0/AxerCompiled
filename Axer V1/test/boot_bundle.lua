-- Axer offline test harness prelude: defines a mock Roblox + executor API
-- surface as globals. Concatenated before the embedded real sources.
-- This file runs inside the standalone Luau CLI (no Roblox globals exist).

--==========================================================================
-- Enum
--==========================================================================
local EnumTable = {}
local function makeEnum(name, values)
	local enumType = { Name = name }
	for _, valueName in values do
		enumType[valueName] = valueName
	end
	EnumTable[name] = enumType
	return enumType
end
Enum = setmetatable({}, { __index = EnumTable })
makeEnum('KeyCode', { 'RightShift', 'LeftControl', 'Delete', 'F' })
makeEnum('UserInputType', { 'MouseButton1', 'MouseButton2', 'Touch', 'MouseMovement', 'Keyboard' })
makeEnum('Font', { 'Gotham', 'GothamBold', 'GothamMedium' })
makeEnum('EasingStyle', { 'Quart', 'Sine' })
makeEnum('EasingDirection', { 'Out', 'In', 'InOut' })
makeEnum('ZIndexBehavior', { 'Sibling', 'Global' })
makeEnum('AutomaticSize', { 'None', 'X', 'Y', 'XY' })
makeEnum('SortOrder', { 'LayoutOrder', 'Name' })
makeEnum('FillDirection', { 'Horizontal', 'Vertical' })
makeEnum('TextXAlignment', { 'Left', 'Center', 'Right' })

--==========================================================================
-- Datatypes
--==========================================================================
Color3 = {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b, _type = 'Color3' } end,
}
UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset, _type = 'UDim' } end }
UDim2 = {
	new = function(xs, xo, ys, yo)
		return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo), _type = 'UDim2' }
	end,
}

--==========================================================================
-- Signals
--==========================================================================
local MockSignal = {}
MockSignal.__index = MockSignal
function MockSignal.new()
	return setmetatable({ _handlers = {} }, MockSignal)
end
function MockSignal:Connect(fn)
	local handler = { fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	return { Disconnect = function() handler.Connected = false end }
end
function MockSignal:Fire(...)
	for _, handler in self._handlers do
		if handler.Connected then
			local ok, err = pcall(handler.fn, ...)
			if not ok then error('signal handler error: '..tostring(err), 0) end
		end
	end
end

--==========================================================================
-- Instance mock
--==========================================================================
local InstanceMock = {}

-- Route `inst.Parent = x` through _setParent so Children lists stay accurate.
InstanceMock.__newindex = function(self, key, value)
	if key == 'Parent' then
		InstanceMock._setParent(self, value)
	else
		rawset(self, key, value)
	end
end

function InstanceMock.new(className, parent)
	local inst = setmetatable({
		ClassName = className,
		Name = className,
		Children = {},
		Parent = nil,
		_Destroyed = false,
		_Properties = {},
		_Signals = {},
	}, InstanceMock)
	if parent then
		InstanceMock._setParent(inst, parent)
	end
	return inst
end

local function getSignal(self, name)
	if not self._Signals[name] then
		self._Signals[name] = MockSignal.new()
	end
	return self._Signals[name]
end

function InstanceMock:_setParent(newParent)
	if rawget(self, 'Parent') then
		for i, child in self.Parent.Children do
			if child == self then
				table.remove(self.Parent.Children, i)
				break
			end
		end
	end
	rawset(self, 'Parent', newParent)
	if newParent then
		table.insert(newParent.Children, self)
	end
end

function InstanceMock:Destroy()
	self._Destroyed = true
	self:_setParent(nil)
end

function InstanceMock:FindFirstChild(name)
	for _, child in self.Children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function InstanceMock:WaitForChild(name)
	local found = self:FindFirstChild(name)
	if not found then
		found = InstanceMock.new('Folder')
		found.Name = name
		found.Parent = self
	end
	return found
end

function InstanceMock:IsA(className)
	return self.ClassName == className or className == 'Instance'
end

function InstanceMock:GetPropertyChangedSignal(prop)
	return getSignal(self, 'PropertyChanged:'..prop)
end

-- Structural properties must read as nil when unset, never fall through to
-- signal lookup (e.g. reading .Parent on a never-parented instance).
local StructuralProperties = {
	Parent = true,
	Children = true,
	Name = true,
	ClassName = true,
}

InstanceMock.__index = function(self, key)
	if StructuralProperties[key] then
		return nil
	end
	local special = InstanceMock['_'..key]
	if special then return special(self) end
	local method = InstanceMock[key]
	if method then return method end
	return getSignal(self, key)
end

InstanceMock.TweenPosition = function(self, ...) return true end

Instance = {
	new = function(className, parent)
		return InstanceMock.new(className, parent)
	end,
}

--==========================================================================
-- Services
--==========================================================================
LightingService = InstanceMock.new('Lighting')
LightingService.Brightness = 1
LightingService.Ambient = Color3.fromRGB(0, 0, 0)
LightingService.OutdoorAmbient = Color3.fromRGB(70, 70, 70)
LightingService.ClockTime = 12
LightingService.FogEnd = 100000
LightingService.GlobalShadows = true

TerrainService = InstanceMock.new('Terrain')
TerrainService.WaterWaveSize = 10
TerrainService.WaterWaveSpeed = 10
TerrainService.WaterReflectance = 0.5
TerrainService.WaterTransparency = 0.5

local WorkspaceService = InstanceMock.new('Workspace')
function WorkspaceService:FindFirstChildOfClass(className)
	if className == 'Terrain' then
		return TerrainService
	end
	return nil
end

local LocalPlayer = InstanceMock.new('Player')
PlayersService = InstanceMock.new('Players')
PlayersService.LocalPlayer = LocalPlayer

CoreGuiService = InstanceMock.new('CoreGui')

UserInputServiceMock = InstanceMock.new('UserInputService')
UserInputServiceMock.IsKeyDown = function(self, key) return false end
UserInputServiceMock.InputBegan = MockSignal.new()
UserInputServiceMock.InputChanged = MockSignal.new()
UserInputServiceMock.InputEnded = MockSignal.new()

RunServiceMock = InstanceMock.new('RunService')
RunServiceMock.RenderStepped = MockSignal.new()

local StatsMock = InstanceMock.new('Stats')
StatsMock.Network = {
	ServerStatsItem = {
		['Data Ping'] = { GetValue = function() return 42 end },
	},
}

local ServicesByName = {
	Lighting = LightingService,
	Workspace = WorkspaceService,
	Players = PlayersService,
	CoreGui = CoreGuiService,
	UserInputService = UserInputServiceMock,
	RunService = RunServiceMock,
	Stats = StatsMock,
}

game = {
	PlaceId = 0,
	JobId = 'test',
	GetService = function(self, name)
		assert(ServicesByName[name], 'GetService("'..tostring(name)..') is not mocked')
		return ServicesByName[name]
	end,
}
workspace = WorkspaceService

--==========================================================================
-- Executor API mocks (in-memory filesystem, request-based HTTP)
--==========================================================================
local memFiles = {}
local memFolders = {}

writefile = function(path, data) memFiles[path] = data end
readfile = function(path)
	local data = memFiles[path]
	if data == nil then error('file not found: '..path) end
	return data
end
isfile = function(path) return memFiles[path] ~= nil end
isfolder = function(path) return memFolders[path] == true end
makefolder = function(path) memFolders[path] = true end
listfiles = function(path)
	local out = {}
	for filePath in pairs(memFiles) do
		if filePath:sub(1, #path + 1) == path..'/' then
			table.insert(out, filePath)
		end
	end
	return out
end
delfile = function(path) memFiles[path] = nil end
TESTFILES = memFiles

request = function(opts)
	return { Body = 'ok', StatusCode = 200 }
end

shared = {}
local genvTable = {}
getgenv = function() return genvTable end

local realPrint = print
warn = function(...)
	realPrint('[warn]', ...)
end

--==========================================================================
-- Minimal task library (immediate execution is fine for the test)
--==========================================================================
task = {
	spawn = function(fn, ...)
		local args = { ... }
		local ok, err = coroutine.resume(coroutine.create(fn), (table.unpack or unpack)(args))
		if not ok then error('task.spawn error: '..tostring(err), 0) end
	end,
	defer = function(fn, ...) task.spawn(fn, ...) end,
	delay = function(_, fn, ...) task.spawn(fn) end,
	cancel = function() end,
	wait = function() end,
}

--==========================================================================
-- Minimal JSON (encode/decode for the save library round-trip)
--==========================================================================
local Json = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t', ['\r'] = '\\r' }

local function encodeValue(value)
	local tv = type(value)
	if tv == 'string' then
		return '"'..value:gsub('[%c"\\]', function(c)
			return escapes[c] or string.format('\\u%04x', c:byte())
		end)..'"'
	elseif tv == 'boolean' then
		return value and 'true' or 'false'
	elseif tv == 'number' then
		return tostring(value)
	elseif tv == 'table' then
		local isArray = #value > 0
		local parts = {}
		if isArray then
			for _, item in ipairs(value) do
				table.insert(parts, encodeValue(item))
			end
			return '['..table.concat(parts, ',')..']'
		else
			for key, item in pairs(value) do
				table.insert(parts, encodeValue(tostring(key))..':'..encodeValue(item))
			end
			return '{'..table.concat(parts, ',')..'}'
		end
	end
	error('cannot JSON-encode type: '..tv)
end

function Json.encode(value)
	return encodeValue(value)
end

function Json.decode(text)
	local pos = 1
	local function skipSpace()
		while pos <= #text and text:sub(pos, pos):match('%s') do
			pos += 1
		end
	end
	local parseValue
	local function parseString()
		assert(text:sub(pos, pos) == '"', 'expected string at '..pos)
		pos += 1
		local out = {}
		while pos <= #text do
			local c = text:sub(pos, pos)
			if c == '"' then
				pos += 1
				return table.concat(out)
			elseif c == '\\' then
				local nextChar = text:sub(pos + 1, pos + 1)
				if nextChar == 'n' then
					table.insert(out, '\n')
				elseif nextChar == 't' then
					table.insert(out, '\t')
				else
					table.insert(out, nextChar)
				end
				pos += 2
			else
				table.insert(out, c)
				pos += 1
			end
		end
		error('unterminated string')
	end
	parseValue = function()
		skipSpace()
		local c = text:sub(pos, pos)
		if c == '{' then
			pos += 1
			local obj = {}
			skipSpace()
			if text:sub(pos, pos) == '}' then
				pos += 1
				return obj
			end
			while true do
				skipSpace()
				local key = parseString()
				skipSpace()
				assert(text:sub(pos, pos) == ':', 'expected : at '..pos)
				pos += 1
				obj[key] = parseValue()
				skipSpace()
				local nextChar = text:sub(pos, pos)
				if nextChar == ',' then
					pos += 1
				elseif nextChar == '}' then
					pos += 1
					return obj
				else
					error('expected , or } at '..pos)
				end
			end
		elseif c == '[' then
			pos += 1
			local arr = {}
			skipSpace()
			if text:sub(pos, pos) == ']' then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, parseValue())
				skipSpace()
				local nextChar = text:sub(pos, pos)
				if nextChar == ',' then
					pos += 1
				elseif nextChar == ']' then
					pos += 1
					return arr
				else
					error('expected , or ] at '..pos)
				end
			end
		elseif c == '"' then
			return parseString()
		elseif text:sub(pos, pos + 3) == 'true' then
			pos += 4
			return true
		elseif text:sub(pos, pos + 4) == 'false' then
			pos += 5
			return false
		elseif text:sub(pos, pos + 3) == 'null' then
			pos += 4
			return nil
		else
			local startPos = pos
			while pos <= #text and text:sub(pos, pos):match('[%d%.%-%+]') do
				pos += 1
			end
			assert(pos > startPos, 'unexpected character at '..pos..': '..text:sub(pos, pos))
			return tonumber(text:sub(startPos, pos - 1))
		end
	end
	local result = parseValue()
	skipSpace()
	assert(pos > #text, 'trailing JSON content at '..pos)
	return result
end

HttpServiceMock = {
	JSONEncode = function(self, value) return Json.encode(value) end,
	JSONDecode = function(self, text) return Json.decode(text) end,
}
ServicesByName.HttpService = HttpServiceMock

--==========================================================================
-- Test helpers
--==========================================================================
TEST_FAILURES = {}
function CHECK(condition, message)
	if condition then
		print('  PASS: '..message)
	else
		table.insert(TEST_FAILURES, message)
		print('  FAIL: '..message)
	end
end
function CHECK_ERRORS()
	if #TEST_FAILURES > 0 then
		print('\n'..#TEST_FAILURES..' test(s) FAILED:')
		for _, message in TEST_FAILURES do
			print('  - '..message)
		end
		error('test suite failed')
	end
	print('\nAll tests passed.')
end
print = realPrint

TESTFILES["axer/libraries/util.lua"] = "-- Axer shared utilities: theme, signals, safe parenting, notifications.\n-- Loaded as: local Util = loadstring(source, 'util')(AxerCore)\n\nreturn function(Axer)\n\tlocal Util = {}\n\n\tUtil.Theme = {\n\t\tAccent = Color3.fromRGB(138, 43, 226),\n\t\tAccentDim = Color3.fromRGB(96, 30, 158),\n\t\tBackground = Color3.fromRGB(24, 24, 30),\n\t\tBackgroundSoft = Color3.fromRGB(32, 32, 40),\n\t\tBackgroundLight = Color3.fromRGB(44, 44, 54),\n\t\tStroke = Color3.fromRGB(60, 60, 74),\n\t\tText = Color3.fromRGB(235, 235, 240),\n\t\tTextDim = Color3.fromRGB(160, 160, 175),\n\t\tOn = Color3.fromRGB(120, 255, 160),\n\t\tOff = Color3.fromRGB(90, 90, 105),\n\t\tFont = Enum.Font.Gotham,\n\t\tFontBold = Enum.Font.GothamBold,\n\t}\n\n\t-- Tiny signal implementation (no BindableEvent overhead).\n\tlocal Signal = {}\n\tSignal.__index = Signal\n\n\tfunction Signal.new()\n\t\treturn setmetatable({ _handlers = {} }, Signal)\n\tend\n\n\tfunction Signal:Connect(fn)\n\t\tlocal handler = { fn = fn }\n\t\tself._handlers[handler] = true\n\t\treturn {\n\t\t\tDisconnect = function()\n\t\t\t\tself._handlers[handler] = nil\n\t\t\tend,\n\t\t}\n\tend\n\n\tfunction Signal:Fire(...)\n\t\tfor handler in pairs(self._handlers) do\n\t\t\ttask.spawn(handler.fn, ...)\n\t\tend\n\tend\n\n\tfunction Signal:Destroy()\n\t\ttable.clear(self._handlers)\n\tend\n\n\tUtil.Signal = Signal\n\tUtil.NewSignal = function()\n\t\treturn Signal.new()\n\tend\n\n\t-- Parent to CoreGui when possible, PlayerGui otherwise.\n\tfunction Util.SafeParent(instance)\n\t\tlocal ok = pcall(function()\n\t\t\tinstance.Parent = game:GetService('CoreGui')\n\t\tend)\n\t\tif ok and instance.Parent then\n\t\t\treturn 'CoreGui'\n\t\tend\n\t\tinstance.Parent = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')\n\t\treturn 'PlayerGui'\n\tend\n\n\t-- Round-cornered notification, bottom-right.\n\tfunction Util.Notify(text, duration)\n\t\tlocal holder = nil\n\t\tlocal okCore = pcall(function()\n\t\t\tholder = game:GetService('CoreGui'):FindFirstChild('AxerNotifications')\n\t\tend)\n\t\tif not okCore or not holder then\n\t\t\tlocal playerGui = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')\n\t\t\tholder = playerGui:FindFirstChild('AxerNotifications')\n\t\tend\n\t\tif not holder then\n\t\t\tholder = Instance.new('ScreenGui')\n\t\t\tholder.Name = 'AxerNotifications'\n\t\t\tholder.ResetOnSpawn = false\n\t\t\tholder.IgnoreGuiInset = true\n\t\t\tUtil.SafeParent(holder)\n\t\tend\n\n\t\tlocal frame = Instance.new('Frame')\n\t\tframe.Size = UDim2.new(0, 260, 0, 42)\n\t\tframe.Position = UDim2.new(1, 20, 1, -70)\n\t\tframe.BackgroundColor3 = Util.Theme.Background\n\t\tframe.BorderSizePixel = 0\n\t\tframe.Parent = holder\n\n\t\tlocal corner = Instance.new('UICorner')\n\t\tcorner.CornerRadius = UDim.new(0, 8)\n\t\tcorner.Parent = frame\n\n\t\tlocal stroke = Instance.new('UIStroke')\n\t\tstroke.Color = Util.Theme.Accent\n\t\tstroke.Thickness = 1\n\t\tstroke.Transparency = 0.4\n\t\tstroke.Parent = frame\n\n\t\tlocal label = Instance.new('TextLabel')\n\t\tlabel.Size = UDim2.new(1, -20, 1, 0)\n\t\tlabel.Position = UDim2.new(0, 12, 0, 0)\n\t\tlabel.BackgroundTransparency = 1\n\t\tlabel.Font = Util.Theme.Font\n\t\tlabel.TextSize = 14\n\t\tlabel.TextColor3 = Util.Theme.Text\n\t\tlabel.TextXAlignment = Enum.TextXAlignment.Left\n\t\tlabel.TextWrapped = true\n\t\tlabel.Text = text\n\t\tlabel.Parent = frame\n\n\t\tframe:TweenPosition(\n\t\t\tUDim2.new(1, -280, 1, -70),\n\t\t\tEnum.EasingDirection.Out,\n\t\t\tEnum.EasingStyle.Quart,\n\t\t\t0.3,\n\t\t\ttrue\n\t\t)\n\t\ttask.delay(duration or 3, function()\n\t\t\tframe:TweenPosition(\n\t\t\t\tUDim2.new(1, 20, 1, -70),\n\t\t\t\tEnum.EasingDirection.In,\n\t\t\t\tEnum.EasingStyle.Quart,\n\t\t\t\t0.25,\n\t\t\t\ttrue\n\t\t\t)\n\t\t\ttask.wait(0.3)\n\t\t\tframe:Destroy()\n\t\tend)\n\tend\n\n\treturn Util\nend\n"
TESTFILES["axer/libraries/shims.lua"] = "-- Axer compatibility layer: detects executor APIs, builds the Axer.Features\n-- capability set, and exposes unified wrappers so modules can degrade\n-- gracefully instead of crashing on weaker executors.\n-- Loaded as: local Features = loadstring(source, 'shims')(AxerCore)\n\nreturn function(Axer)\n\tlocal Shims = {}\n\n\tlocal HttpService = game:GetService('HttpService')\n\n\tlocal function detectHttp()\n\t\tlocal ok = pcall(function()\n\t\t\treturn game:HttpGet('https://github.com', true)\n\t\tend)\n\t\tif ok then\n\t\t\treturn 'HttpGet', function(url)\n\t\t\t\tlocal okCall, body = pcall(function()\n\t\t\t\t\treturn game:HttpGet(url, true)\n\t\t\t\tend)\n\t\t\t\tif not okCall then\n\t\t\t\t\terror('[Axer] HttpGet failed: '..tostring(body), 0)\n\t\t\t\tend\n\t\t\t\treturn body\n\t\t\tend\n\t\tend\n\t\tlocal requestFn = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)\n\t\tif type(requestFn) == 'function' then\n\t\t\treturn 'request', function(url)\n\t\t\t\tlocal okCall, res = pcall(function()\n\t\t\t\t\treturn requestFn({ Url = url, Method = 'GET' })\n\t\t\t\tend)\n\t\t\t\tif not okCall then\n\t\t\t\t\terror('[Axer] request failed: '..tostring(res), 0)\n\t\t\t\tend\n\t\t\t\treturn res and (res.Body or res.body) or nil\n\t\t\tend\n\t\tend\n\t\treturn nil, nil\n\tend\n\n\tlocal httpName, httpFn = detectHttp()\n\n\tShims.Features = {\n\t\tfs = type(writefile) == 'function' and type(readfile) == 'function' and type(isfile) == 'function',\n\t\thttp = httpFn ~= nil,\n\t\tidentifier = httpName,\n\t\tjson = typeof(HttpService) == 'Instance' and type(HttpService.JSONDecode) == 'function',\n\t\tgetcustomasset = type(getcustomasset) == 'function',\n\t\tqueue_on_teleport = type(queue_on_teleport) == 'function' or type(queueonteleport) == 'function',\n\t\tdebug = type(debug) == 'table' and type(debug.getinfo) == 'function',\n\t\tdrawables = type(Drawing) == 'table',\n\t\tmouse = type(mouse) == 'table',\n\t}\n\n\tShims.Http = httpFn or function()\n\t\terror('[Axer] No HTTP implementation available (tried game:HttpGet and request).', 0)\n\tend\n\n\t-- Unified filesystem wrappers: real FS when available, in-memory otherwise.\n\tlocal mem = {}\n\n\tif Shims.Features.fs then\n\t\tfunction Shims.ReadFile(path)\n\t\t\tlocal ok, res = pcall(readfile, path)\n\t\t\treturn ok and res or nil\n\t\tend\n\t\tfunction Shims.WriteFile(path, data)\n\t\t\treturn pcall(writefile, path, data)\n\t\tend\n\t\tfunction Shims.IsFile(path)\n\t\t\tlocal ok, res = pcall(isfile, path)\n\t\t\treturn ok and res == true\n\t\tend\n\t\tfunction Shims.IsFolder(path)\n\t\t\tlocal ok, res = pcall(isfolder, path)\n\t\t\treturn ok and res == true\n\t\tend\n\t\tfunction Shims.ListFiles(path)\n\t\t\tlocal ok, res = pcall(listfiles, path)\n\t\t\treturn ok and type(res) == 'table' and res or {}\n\t\tend\n\t\tfunction Shims.MakeFolder(path)\n\t\t\tlocal ok, exists = pcall(isfolder, path)\n\t\t\tif ok and exists then return true end\n\t\t\treturn pcall(makefolder, path)\n\t\tend\n\t\tfunction Shims.DelFile(path)\n\t\t\treturn pcall(delfile, path)\n\t\tend\n\telse\n\t\t-- Files exist per-session only.\n\t\tfunction Shims.ReadFile(path)\n\t\t\treturn mem[path]\n\t\tend\n\t\tfunction Shims.WriteFile(path, data)\n\t\t\tmem[path] = data\n\t\t\treturn true\n\t\tend\n\t\tfunction Shims.IsFile(path)\n\t\t\treturn mem[path] ~= nil\n\t\tend\n\t\tfunction Shims.IsFolder()\n\t\t\treturn false\n\t\tend\n\t\tfunction Shims.ListFiles()\n\t\t\treturn {}\n\t\tend\n\t\tfunction Shims.MakeFolder() end\n\t\tfunction Shims.DelFile(path)\n\t\t\tmem[path] = nil\n\t\tend\n\tend\n\n\treturn Shims\nend\n"
TESTFILES["axer/libraries/module.lua"] = "-- Axer module registry. Usage (inside a game module file):\n--   Axer.CreateModule{\n--       Name = 'Fullbright',\n--       Description = 'Removes darkness',\n--       Tab = 'Render',                    -- which GUI tab the module sits in\n--       Init = function(self) ... end,     -- called once after registration\n--       OnEnable = function(self) ... end, -- called on every enable\n--       OnDisable = function(self) ... end,\n--   }\n-- Modules get: self.Enabled, :Toggle(state?), :Track(connection) (auto-\n-- disconnected on disable), :AddOption(type, id, def) for GUI widgets,\n-- :GetOption(id), :SetOption(id, value).\n-- Loaded as: local ModuleLib = loadstring(source, 'module')(AxerCore)\n\nreturn function(Axer)\n\tlocal ModuleLib = {}\n\tlocal Module = {}\n\tModule.__index = Module\n\n\tlocal function noop() end\n\n\tlocal function disconnectAll(connections)\n\t\tfor _, conn in ipairs(connections) do\n\t\t\tpcall(function()\n\t\t\t\tconn:Disconnect()\n\t\t\tend)\n\t\tend\n\t\ttable.clear(connections)\n\tend\n\n\tfunction ModuleLib.new(core)\n\t\tlocal registry = {\n\t\t\tCore = core,\n\t\t\tModules = {},\n\t\t\tOrder = {},\n\t\t\tModuleAdded = core.Util.NewSignal(),\n\t\t}\n\t\treturn setmetatable(registry, { __index = ModuleLib })\n\tend\n\n\tfunction ModuleLib:CreateModule(def)\n\t\tassert(type(def) == 'table' and type(def.Name) == 'string', '[Axer] CreateModule: Name required')\n\t\tassert(self.Modules[def.Name] == nil, ('[Axer] Duplicate module name: %s'):format(def.Name))\n\n\t\tlocal mod = setmetatable({\n\t\t\tName = def.Name,\n\t\t\tDescription = def.Description or '',\n\t\t\tTab = def.Tab or 'Utility',\n\t\t\tEnabled = false,\n\t\t\t_Connections = {},\n\t\t\t_Options = {},\n\t\t\t_Def = def,\n\t\t\t_Core = self.Core,\n\t\t}, Module)\n\n\t\tfunction mod:Track(connection)\n\t\t\ttable.insert(self._Connections, connection)\n\t\t\treturn connection\n\t\tend\n\n\t\tfunction mod:AddOption(optionType, id, optionDef)\n\t\t\tlocal gui = self._Core.GuiLibrary\n\t\t\tif gui then\n\t\t\t\treturn gui:AddOption(self, optionType, id, optionDef)\n\t\t\tend\n\t\t\treturn nil\n\t\tend\n\n\t\tfunction mod:GetOption(id)\n\t\t\treturn self._Options[id] and self._Options[id].Value\n\t\tend\n\n\t\tfunction mod:SetOption(id, value)\n\t\t\tlocal option = self._Options[id]\n\t\t\tif option then\n\t\t\t\toption.Value = value\n\t\t\t\tif option.Set then\n\t\t\t\t\toption.Set(value)\n\t\t\t\tend\n\t\t\t\tif self._Core.SaveLibrary then\n\t\t\t\t\tself._Core.SaveLibrary:QueueSave()\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\n\t\tfunction mod:Toggle(state)\n\t\t\tlocal target = state == nil and not self.Enabled or state\n\t\t\tif target == self.Enabled then\n\t\t\t\treturn self.Enabled\n\t\t\tend\n\t\t\tself.Enabled = target\n\t\t\tif target then\n\t\t\t\t(self._Def.OnEnable or noop)(self)\n\t\t\telse\n\t\t\t\t(self._Def.OnDisable or noop)(self)\n\t\t\t\tdisconnectAll(self._Connections)\n\t\t\tend\n\t\t\tif self._Core.SaveLibrary then\n\t\t\t\tself._Core.SaveLibrary:QueueSave()\n\t\t\tend\n\t\t\tself._Core.ModuleToggled:Fire(self.Name, self.Enabled)\n\t\t\treturn self.Enabled\n\t\tend\n\n\t\tself.Modules[def.Name] = mod\n\t\ttable.insert(self.Order, mod.Name)\n\t\tself.ModuleAdded:Fire(mod)\n\t\tif def.Init then\n\t\t\ttask.spawn(def.Init, mod)\n\t\tend\n\t\treturn mod\n\tend\n\n\tfunction ModuleLib:GetModule(name)\n\t\treturn self.Modules[name]\n\tend\n\n\tfunction ModuleLib:GetAll()\n\t\treturn self.Modules\n\tend\n\n\tfunction ModuleLib:DisableAll()\n\t\tfor _, name in ipairs(self.Order) do\n\t\t\tlocal mod = self.Modules[name]\n\t\t\tif mod.Enabled then\n\t\t\t\tmod:Toggle(false)\n\t\t\tend\n\t\tend\n\tend\n\n\t-- Serializes all modules + option values for config saving.\n\tfunction ModuleLib:Serialize()\n\t\tlocal out = {}\n\t\tfor _, name in ipairs(self.Order) do\n\t\t\tlocal mod = self.Modules[name]\n\t\t\tlocal options = {}\n\t\t\tfor id, option in pairs(mod._Options) do\n\t\t\t\tif option.Save ~= false then\n\t\t\t\t\tlocal value = option.Value\n\t\t\t\t\tif typeof(value) == 'EnumItem' then\n\t\t\t\t\t\tvalue = value.Name\n\t\t\t\t\tend\n\t\t\t\t\toptions[id] = value\n\t\t\t\tend\n\t\t\tend\n\t\t\tout[name] = { Enabled = mod.Enabled, Options = options }\n\t\tend\n\t\treturn out\n\tend\n\n\t-- Restores state from a config table (GUI widgets update via option.Set).\n\tfunction ModuleLib:Restore(data)\n\t\tif type(data) ~= 'table' then\n\t\t\treturn\n\t\tend\n\t\tfor _, name in ipairs(self.Order) do\n\t\t\tlocal saved = data[name]\n\t\t\tlocal mod = self.Modules[name]\n\t\t\tif mod and type(saved) == 'table' then\n\t\t\t\tfor id, value in pairs(saved.Options or {}) do\n\t\t\t\t\tlocal option = mod._Options[id]\n\t\t\t\t\tif option then\n\t\t\t\t\t\tif option.EnumType and type(value) == 'string' then\n\t\t\t\t\t\t\tlocal ok, enumValue = pcall(function()\n\t\t\t\t\t\t\t\treturn option.EnumType[value]\n\t\t\t\t\t\t\tend)\n\t\t\t\t\t\t\toption.Value = ok and enumValue or option.Value\n\t\t\t\t\t\telse\n\t\t\t\t\t\t\toption.Value = value\n\t\t\t\t\t\tend\n\t\t\t\t\t\tif option.Set then\n\t\t\t\t\t\t\toption.Set(option.Value)\n\t\t\t\t\t\tend\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\tif saved.Enabled and not mod.Enabled then\n\t\t\t\t\tmod:Toggle(true)\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\tend\n\n\treturn ModuleLib\nend\n"
TESTFILES["axer/libraries/gui.lua"] = "-- Axer in-house GUI library.\n--   One ScreenGui, draggable window, Vape-style top tabs, module cards,\n--   option widgets (Toggle/Slider/List/Button/Keybind/TextBox), notifications.\n-- Modules register options via module:AddOption('Toggle', 'id', { ... }).\n-- Loaded as: local GuiLibrary = loadstring(source, 'gui')(AxerCore)\n\nreturn function(Axer)\n\tlocal GuiLibrary = {}\n\n\tlocal function theme()\n\t\treturn Axer.Util.Theme\n\tend\n\n\tlocal function notify(text, duration)\n\t\treturn Axer.Util.Notify(text, duration)\n\tend\n\n-- Parent the ScreenGui via CoreGui -> PlayerGui fallback.\nlocal function safeParent(gui)\n\tlocal ok = pcall(function()\n\t\tgui.Parent = game:GetService('CoreGui')\n\tend)\n\tif ok and gui.Parent then return end\n\tgui.Parent = game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')\nend\n\nfunction GuiLibrary.new(core)\n\tlocal self = setmetatable({}, { __index = GuiLibrary })\n\tself.Core = core\n\tself.ScreenGui = Instance.new('ScreenGui')\n\tself.ScreenGui.Name = 'AxerV1'\n\tself.ScreenGui.ResetOnSpawn = false\n\tself.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling\n\tsafeParent(self.ScreenGui)\n\n\tself.Tabs = {}\n\tself.TabOrder = {}\n\tself.CurrentTab = nil\n\tself.Open = false\n\tself.Root = nil\n\treturn self\nend\n\nfunction GuiLibrary:Build()\n\tif self.Root then return end\n\tlocal t = theme()\n\n\tlocal root = Instance.new('ScreenGui')\n\troot.Name = 'AxerWindow'\n\troot.ResetOnSpawn = false\n\tself.ScreenGui:Destroy()\n\tself.ScreenGui = root\n\tsafeParent(root)\n\tself.Root = root\n\n\tlocal window = Instance.new('Frame')\n\twindow.Name = 'Window'\n\twindow.Size = UDim2.new(0, 560, 0, 360)\n\twindow.Position = UDim2.new(0.5, -280, 0.5, -180)\n\twindow.BackgroundColor3 = t.Background\n\twindow.BorderSizePixel = 0\n\twindow.Active = true\n\twindow.Parent = root\n\n\tInstance.new('UICorner', window).CornerRadius = UDim.new(0, 10)\n\tlocal stroke = Instance.new('UIStroke', window)\n\tstroke.Color = t.Accent\n\tstroke.Thickness = 1.2\n\tstroke.Transparency = 0.35\n\n\t-- Title bar + drag.\n\tlocal titleBar = Instance.new('Frame')\n\ttitleBar.Name = 'TitleBar'\n\ttitleBar.Size = UDim2.new(1, 0, 0, 36)\n\ttitleBar.BackgroundTransparency = 1\n\ttitleBar.Parent = window\n\n\tlocal title = Instance.new('TextLabel')\n\ttitle.Size = UDim2.new(1, -40, 1, 0)\n\ttitle.Position = UDim2.new(0, 14, 0, 0)\n\ttitle.BackgroundTransparency = 1\n\ttitle.Font = t.FontBold\n\ttitle.TextSize = 16\n\ttitle.TextColor3 = t.Text\n\ttitle.TextXAlignment = Enum.TextXAlignment.Left\n\ttitle.Text = 'Axer V1'\n\ttitle.Parent = titleBar\n\n\tlocal dragInput, dragStart, startPos\n\tlocal dragging = false\n\ttitleBar.InputBegan:Connect(function(input)\n\t\tif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then\n\t\t\tdragging = true\n\t\t\tdragStart = input.Position\n\t\t\tstartPos = window.Position\n\t\t\tinput.Changed:Connect(function()\n\t\t\t\tif input.UserInputState == Enum.UserInputState.End then dragging = false end\n\t\t\tend)\n\t\tend\n\tend)\n\ttitleBar.InputChanged:Connect(function(input)\n\t\tif input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then\n\t\t\tdragInput = input\n\t\tend\n\tend)\n\tgame:GetService('UserInputService').InputChanged:Connect(function(input)\n\t\tif dragging and input == dragInput then\n\t\t\tlocal delta = input.Position - dragStart\n\t\t\twindow.Position = UDim2.new(\n\t\t\t\tstartPos.X.Scale, startPos.X.Offset + delta.X,\n\t\t\t\tstartPos.Y.Scale, startPos.Y.Offset + delta.Y\n\t\t\t)\n\t\tend\n\tend)\n\n\t-- Tab strip.\n\tlocal tabStrip = Instance.new('Frame')\n\ttabStrip.Name = 'TabStrip'\n\ttabStrip.Size = UDim2.new(1, -28, 0, 34)\n\ttabStrip.Position = UDim2.new(0, 14, 0, 36)\n\ttabStrip.BackgroundTransparency = 1\n\ttabStrip.Parent = window\n\tlocal stripLayout = Instance.new('UIListLayout', tabStrip)\n\tstripLayout.FillDirection = Enum.FillDirection.Horizontal\n\tstripLayout.Padding = UDim.new(0, 6)\n\n\t-- Content area: one page per tab.\n\tlocal content = Instance.new('Frame')\n\tcontent.Name = 'Content'\n\tcontent.Size = UDim2.new(1, -28, 1, -92)\n\tcontent.Position = UDim2.new(0, 14, 0, 78)\n\tcontent.BackgroundTransparency = 1\n\tcontent.Parent = window\n\n\tself.Window = window\n\tself.Content = content\n\tself.TabStrip = tabStrip\n\n\t-- Open/close keybind.\n\tgame:GetService('UserInputService').InputBegan:Connect(function(input, processed)\n\t\tif processed then return end\n\t\tif input.KeyCode == Enum.KeyCode.RightShift then\n\t\t\tself:SetOpen(not self.Open)\n\t\tend\n\tend)\n\n\tself:SetOpen(true)\nend\n\nfunction GuiLibrary:SetOpen(open)\n\tself.Open = open\n\tif self.Root then\n\t\tself.Root.Enabled = open\n\tend\nend\n\nfunction GuiLibrary:CreateTab(name)\n\tif self.Tabs[name] then return self.Tabs[name] end\n\tself:Build()\n\n\tlocal t = theme()\n\tlocal tabButton = Instance.new('TextButton')\n\ttabButton.Size = UDim2.new(0, 92, 1, 0)\n\ttabButton.BackgroundColor3 = t.BackgroundSoft\n\ttabButton.BorderSizePixel = 0\n\ttabButton.Font = t.Font\n\ttabButton.TextSize = 14\n\ttabButton.TextColor3 = t.TextDim\n\ttabButton.Text = name\n\ttabButton.AutoButtonColor = false\n\ttabButton.Parent = self.TabStrip\n\tInstance.new('UICorner', tabButton).CornerRadius = UDim.new(0, 8)\n\n\tlocal page = Instance.new('ScrollingFrame')\n\tpage.Name = name\n\tpage.Size = UDim2.new(1, 0, 1, 0)\n\tpage.BackgroundTransparency = 1\n\tpage.BorderSizePixel = 0\n\tpage.ScrollBarThickness = 4\n\tpage.ScrollBarImageColor3 = t.Accent\n\tpage.CanvasSize = UDim2.new(0, 0, 0, 0)\n\tpage.AutomaticCanvasSize = Enum.AutomaticSize.Y\n\tpage.Visible = false\n\tpage.Parent = self.Content\n\tlocal pageLayout = Instance.new('UIListLayout', page)\n\tpageLayout.Padding = UDim.new(0, 6)\n\tpageLayout.SortOrder = Enum.SortOrder.LayoutOrder\n\tlocal pad = Instance.new('UIPadding', page)\n\tpad.PaddingRight = UDim.new(0, 8)\n\n\tlocal tab = { Name = name, Button = tabButton, Page = page, Order = #self.TabOrder + 1 }\n\tself.Tabs[name] = tab\n\ttable.insert(self.TabOrder, name)\n\n\ttabButton.MouseButton1Click:Connect(function()\n\t\tself:SelectTab(name)\n\tend)\n\n\tif not self.CurrentTab then\n\t\tself:SelectTab(name)\n\tend\n\treturn tab\nend\n\nfunction GuiLibrary:SelectTab(name)\n\tlocal tab = self.Tabs[name]\n\tif not tab then return end\n\tself.CurrentTab = name\n\tlocal t = theme()\n\tfor _, other in pairs(self.Tabs) do\n\t\tother.Page.Visible = (other.Name == name)\n\t\tlocal selected = other.Name == name\n\t\tother.Button.BackgroundColor3 = selected and t.AccentDim or t.BackgroundSoft\n\t\tother.Button.TextColor3 = selected and t.Text or t.TextDim\n\tend\nend\n\n----------------------------------------------------------------------\n-- Option widgets\n----------------------------------------------------------------------\n\n-- Shared card: module name row + optional description + option container.\nfunction GuiLibrary:CreateModuleCard(mod)\n\tself:Build()\n\tlocal tab = self:CreateTab(mod.Tab)\n\tlocal t = theme()\n\n\tlocal card = Instance.new('Frame')\n\tcard.Name = mod.Name\n\tcard.Size = UDim2.new(1, 0, 0, 44)\n\tcard.BackgroundColor3 = t.BackgroundSoft\n\tcard.BorderSizePixel = 0\n\tcard.Parent = tab.Page\n\tInstance.new('UICorner', card).CornerRadius = UDim.new(0, 8)\n\n\tlocal layout = Instance.new('UIListLayout', card)\n\tlayout.Padding = UDim.new(0, 4)\n\tlayout.SortOrder = Enum.SortOrder.LayoutOrder\n\n\tlocal header = Instance.new('TextButton')\n\theader.Name = 'Header'\n\theader.Size = UDim2.new(1, 0, 0, 40)\n\theader.BackgroundTransparency = 1\n\theader.Font = t.Font\n\theader.TextSize = 14\n\theader.TextColor3 = t.Text\n\theader.TextXAlignment = Enum.TextXAlignment.Left\n\theader.Text = '  '..mod.Name\n\theader.Parent = card\n\n\tlocal dot = Instance.new('Frame')\n\tdot.Size = UDim2.new(0, 8, 0, 8)\n\tdot.Position = UDim2.new(1, -18, 0, 16)\n\tdot.BackgroundColor3 = t.Off\n\tdot.Parent = header\n\tInstance.new('UICorner', dot).CornerRadius = UDim.new(0, 8)\n\n\tif mod.Description ~= '' then\n\t\theader.TextSize = 13\n\t\tlocal desc = Instance.new('TextLabel')\n\t\tdesc.Size = UDim2.new(1, -36, 0, 14)\n\t\tdesc.Position = UDim2.new(0, 14, 0, 26)\n\t\tdesc.BackgroundTransparency = 1\n\t\tdesc.Font = t.Font\n\t\tdesc.TextSize = 11\n\t\tdesc.TextColor3 = t.TextDim\n\t\tdesc.TextXAlignment = Enum.TextXAlignment.Left\n\t\tdesc.Text = mod.Description\n\t\tdesc.Parent = card\n\tend\n\n\theader.MouseButton1Click:Connect(function()\n\t\tmod:Toggle()\n\tend)\n\n\tmod._Core.ModuleToggled:Connect(function(name, enabled)\n\t\tif name == mod.Name then\n\t\t\tdot.BackgroundColor3 = enabled and t.On or t.Off\n\t\tend\n\tend)\n\n\tlocal optionCount = 0\n\n\tlocal cardApi = {}\n\n\tlocal function autoSize()\n\t\tlocal height = 44 + optionCount * 30\n\t\tcard.Size = UDim2.new(1, 0, 0, height)\n\tend\n\n\tfunction cardApi.AddOption(optionType, id, def)\n\t\tdef = def or {}\n\t\toptionCount += 1\n\t\tlocal row = Instance.new('Frame')\n\t\trow.Name = id\n\t\trow.BackgroundColor3 = t.BackgroundLight\n\t\trow.BorderSizePixel = 0\n\t\trow.LayoutOrder = optionCount\n\t\trow.Parent = card\n\t\tInstance.new('UICorner', row).CornerRadius = UDim.new(0, 6)\n\t\trow.Size = UDim2.new(1, -8, 0, 26)\n\n\t\tlocal label = Instance.new('TextLabel')\n\t\tlabel.Size = UDim2.new(1, -16, 1, 0)\n\t\tlabel.Position = UDim2.new(0, 10, 0, 0)\n\t\tlabel.BackgroundTransparency = 1\n\t\tlabel.Font = t.Font\n\t\tlabel.TextSize = 12\n\t\tlabel.TextColor3 = t.TextDim\n\t\tlabel.TextXAlignment = Enum.TextXAlignment.Left\n\t\tlabel.Text = def.Name or id\n\t\tlabel.Parent = row\n\n\t\tlocal option = { Type = optionType, Name = def.Name or id, Value = def.Default, Save = def.Save ~= false }\n\n\t\t-- Widget construction per type.\n\t\tif optionType == 'Toggle' then\n\t\t\tlocal pill = Instance.new('TextButton')\n\t\t\tpill.Size = UDim2.new(0, 34, 0, 18)\n\t\t\tpill.Position = UDim2.new(1, -42, 0, 4)\n\t\t\tpill.BackgroundColor3 = t.Off\n\t\t\tpill.Text = ''\n\t\t\tpill.Font = t.Font\n\t\t\tpill.BorderSizePixel = 0\n\t\t\tpill.AutoButtonColor = false\n\t\t\tpill.Parent = row\n\t\t\tInstance.new('UICorner', pill).CornerRadius = UDim.new(0, 9)\n\n\t\t\tlocal knob = Instance.new('Frame')\n\t\t\tknob.Size = UDim2.new(0, 14, 0, 14)\n\t\t\tknob.Position = UDim2.new(0, 2, 0, 2)\n\t\t\tknob.BackgroundColor3 = t.Text\n\t\t\tknob.Parent = pill\n\t\t\tInstance.new('UICorner', knob).CornerRadius = UDim.new(0, 7)\n\n\t\t\tfunction option.Set(value)\n\t\t\t\toption.Value = value\n\t\t\t\tpill.BackgroundColor3 = value and t.Accent or t.Off\n\t\t\t\tknob.Position = value and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 2, 0, 2)\n\t\t\tend\n\t\t\tpill.MouseButton1Click:Connect(function()\n\t\t\t\toption.Set(not option.Value)\n\t\t\t\tif mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end\n\t\t\tend)\n\t\t\toption.Set(option.Value == true)\n\n\t\telseif optionType == 'Slider' then\n\t\t\tlocal value = Instance.new('TextLabel')\n\t\t\tvalue.Size = UDim2.new(0, 44, 1, 0)\n\t\t\tvalue.Position = UDim2.new(1, -52, 0, 0)\n\t\t\tvalue.BackgroundTransparency = 1\n\t\t\tvalue.Font = t.Font\n\t\t\tvalue.TextSize = 12\n\t\t\tvalue.TextColor3 = t.Text\n\t\t\tvalue.Text = tostring(def.Default or def.Min or 0)\n\t\t\tvalue.Parent = row\n\n\t\t\tlocal bar = Instance.new('TextButton')\n\t\t\tbar.Size = UDim2.new(1, -110, 0, 6)\n\t\t\tbar.Position = UDim2.new(0, 10, 0.5, -3)\n\t\t\tbar.BackgroundColor3 = t.Off\n\t\t\tbar.Text = ''\n\t\t\tbar.BorderSizePixel = 0\n\t\t\tbar.AutoButtonColor = false\n\t\t\tbar.Parent = row\n\t\t\tInstance.new('UICorner', bar).CornerRadius = UDim.new(0, 3)\n\n\t\t\tlocal fill = Instance.new('Frame')\n\t\t\tfill.Size = UDim2.new(0.5, 0, 1, 0)\n\t\t\tfill.BackgroundColor3 = t.Accent\n\t\t\tfill.BorderSizePixel = 0\n\t\t\tfill.Parent = bar\n\t\t\tInstance.new('UICorner', fill).CornerRadius = UDim.new(0, 3)\n\n\t\t\tlocal min = def.Min or 0\n\t\t\tlocal max = def.Max or 100\n\n\t\t\tlocal function setFromFraction(fraction)\n\t\t\t\t\tfraction = math.clamp(fraction, 0, 1)\n\t\t\t\t\tif max - min <= 0 then\n\t\t\t\t\t\toption.Value = min\n\t\t\t\t\t\tvalue.Text = tostring(min)\n\t\t\t\t\t\tfill.Size = UDim2.new(0, 0, 1, 0)\n\t\t\t\t\t\treturn\n\t\t\t\t\tend\n\t\t\t\t\tlocal raw = min + (max - min) * fraction\n\t\t\t\tlocal rounded = math.floor(raw + 0.5)\n\t\t\t\tif def.Step then\n\t\t\t\t\trounded = math.floor(raw / def.Step + 0.5) * def.Step\n\t\t\t\tend\n\t\t\t\toption.Value = rounded\n\t\t\t\tvalue.Text = tostring(rounded)\n\t\t\t\tfill.Size = UDim2.new(fraction, 0, 1, 0)\n\t\t\tend\n\n\t\t\tlocal draggingSlider = false\n\t\t\tbar.InputBegan:Connect(function(input)\n\t\t\t\tif input.UserInputType == Enum.UserInputType.MouseButton1 then\n\t\t\t\t\tdraggingSlider = true\n\t\t\t\t\tlocal absPos = bar.AbsolutePosition\n\t\t\t\t\tsetFromFraction((input.Position.X - absPos.X) / bar.AbsoluteSize.X)\n\t\t\t\tend\n\t\t\tend)\n\t\t\tgame:GetService('UserInputService').InputChanged:Connect(function(input)\n\t\t\t\tif draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then\n\t\t\t\t\tlocal absPos = bar.AbsolutePosition\n\t\t\t\t\tsetFromFraction((input.Position.X - absPos.X) / bar.AbsoluteSize.X)\n\t\t\t\tend\n\t\t\tend)\n\t\t\tgame:GetService('UserInputService').InputEnded:Connect(function(input)\n\t\t\t\tif input.UserInputType == Enum.UserInputType.MouseButton1 then\n\t\t\t\t\tdraggingSlider = false\n\t\t\t\t\tif mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end\n\t\t\t\tend\n\t\t\tend)\n\t\t\tsetFromFraction(((def.Default or min) - min) / (max - min))\n\n\t\telseif optionType == 'List' then\n\t\t\tlocal current = Instance.new('TextButton')\n\t\t\tcurrent.Size = UDim2.new(0, 120, 0, 20)\n\t\t\tcurrent.Position = UDim2.new(1, -128, 0, 3)\n\t\t\tcurrent.BackgroundColor3 = t.Background\n\t\t\tcurrent.Font = t.Font\n\t\t\tcurrent.TextSize = 12\n\t\t\tcurrent.TextColor3 = t.Text\n\t\t\tcurrent.Text = def.Default or (def.Options and def.Options[1]) or ''\n\t\t\tcurrent.BorderSizePixel = 0\n\t\t\tcurrent.AutoButtonColor = false\n\t\t\tcurrent.Parent = row\n\t\t\tInstance.new('UICorner', current).CornerRadius = UDim.new(0, 6)\n\n\t\t\toption.Value = current.Text\n\t\t\tlocal open = false\n\t\t\tlocal dropdown\n\t\t\tcurrent.MouseButton1Click:Connect(function()\n\t\t\t\tif open and dropdown then\n\t\t\t\t\tdropdown:Destroy()\n\t\t\t\t\tdropdown = nil\n\t\t\t\t\topen = false\n\t\t\t\t\treturn\n\t\t\t\tend\n\t\t\t\topen = true\n\t\t\t\tdropdown = Instance.new('ScrollingFrame')\n\t\t\t\tdropdown.Size = UDim2.new(0, 120, 0, math.min(#def.Options * 22, 88))\n\t\t\t\tdropdown.Position = UDim2.new(0, 0, 1, 4)\n\t\t\t\tdropdown.BackgroundColor3 = t.Background\n\t\t\t\tdropdown.BorderSizePixel = 0\n\t\t\t\tdropdown.ScrollBarThickness = 3\n\t\t\t\tdropdown.CanvasSize = UDim2.new(0, 0, 0, 0)\n\t\t\t\tdropdown.AutomaticCanvasSize = Enum.AutomaticSize.Y\n\t\t\t\tdropdown.Parent = current\n\t\t\t\tInstance.new('UICorner', dropdown).CornerRadius = UDim.new(0, 6)\n\t\t\t\tlocal listLayout = Instance.new('UIListLayout', dropdown)\n\t\t\t\tlistLayout.SortOrder = Enum.SortOrder.LayoutOrder\n\n\t\t\t\tfor i, entry in ipairs(def.Options or {}) do\n\t\t\t\t\tlocal item = Instance.new('TextButton')\n\t\t\t\t\titem.Size = UDim2.new(1, 0, 0, 22)\n\t\t\t\t\titem.BackgroundColor3 = t.Background\n\t\t\t\t\titem.Font = t.Font\n\t\t\t\t\titem.TextSize = 12\n\t\t\t\t\titem.TextColor3 = t.TextDim\n\t\t\t\t\titem.Text = entry\n\t\t\t\t\titem.BorderSizePixel = 0\n\t\t\t\t\titem.LayoutOrder = i\n\t\t\t\t\titem.AutoButtonColor = false\n\t\t\t\t\titem.Parent = dropdown\n\t\t\t\t\titem.MouseEnter:Connect(function() item.BackgroundColor3 = t.BackgroundLight end)\n\t\t\t\t\titem.MouseLeave:Connect(function() item.BackgroundColor3 = t.Background end)\n\t\t\t\t\titem.MouseButton1Click:Connect(function()\n\t\t\t\t\t\toption.Value = entry\n\t\t\t\t\t\tcurrent.Text = entry\n\t\t\t\t\t\tdropdown:Destroy()\n\t\t\t\t\t\tdropdown = nil\n\t\t\t\t\t\topen = false\n\t\t\t\t\t\tif def.Callback then def.Callback(entry) end\n\t\t\t\t\t\tif mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end\n\t\t\t\t\tend)\n\t\t\t\tend\n\t\t\tend)\n\n\t\telseif optionType == 'Button' then\n\t\t\trow.Active = true\n\t\t\tlabel.TextColor3 = t.Accent\n\t\t\trow.InputBegan:Connect(function(input)\n\t\t\t\tif input.UserInputType == Enum.UserInputType.MouseButton1 and def.Callback then\n\t\t\t\t\ttask.spawn(def.Callback)\n\t\t\t\tend\n\t\t\tend)\n\n\t\telseif optionType == 'Keybind' then\n\t\t\tlocal bind = Instance.new('TextButton')\n\t\t\tbind.Size = UDim2.new(0, 70, 0, 20)\n\t\t\tbind.Position = UDim2.new(1, -78, 0, 3)\n\t\t\tbind.BackgroundColor3 = t.Background\n\t\t\tbind.Font = t.Font\n\t\t\tbind.TextSize = 11\n\t\t\tbind.TextColor3 = t.Text\t\t\t\tlocal defaultBind = 'None'\n\t\t\t\tif def.Default then\n\t\t\t\t\tdefaultBind = (type(def.Default) == 'table' or type(def.Default) == 'userdata')\n\t\t\t\t\t\tand def.Default.Name\n\t\t\t\t\t\tor tostring(def.Default)\n\t\t\t\tend\n\t\t\t\tbind.Text = defaultBind\n\t\t\tbind.BorderSizePixel = 0\n\t\t\tbind.AutoButtonColor = false\n\t\t\tbind.Parent = row\n\t\t\tInstance.new('UICorner', bind).CornerRadius = UDim.new(0, 6)\n\n\t\t\toption.Value = def.Default\n\n\t\t\tbind.MouseButton1Click:Connect(function()\n\t\t\t\tbind.Text = '...'\n\t\t\t\tlocal conn\n\t\t\t\tconn = game:GetService('UserInputService').InputBegan:Connect(function(input, processed)\n\t\t\t\t\tif processed then return end\n\t\t\t\t\tif input.UserInputType == Enum.UserInputType.Keyboard then\n\t\t\t\t\t\toption.Value = input.KeyCode\n\t\t\t\t\t\tbind.Text = input.KeyCode.Name\n\t\t\t\t\t\tconn:Disconnect()\n\t\t\t\t\t\tif mod._Core.SaveLibrary then mod._Core.SaveLibrary:QueueSave() end\n\t\t\t\t\tend\n\t\t\t\tend)\n\t\t\tend)\n\t\t\tif def.Callback then\n\t\t\t\tgame:GetService('UserInputService').InputBegan:Connect(function(input, processed)\n\t\t\t\t\tif processed then return end\n\t\t\t\t\tif input.KeyCode == option.Value and input.UserInputType == Enum.UserInputType.Keyboard then\n\t\t\t\t\t\tdef.Callback()\n\t\t\t\t\tend\n\t\t\t\tend)\n\t\t\tend\n\n\t\telseif optionType == 'TextBox' then\n\t\t\tlocal box = Instance.new('TextBox')\n\t\t\tbox.Size = UDim2.new(0, 120, 0, 20)\n\t\t\tbox.Position = UDim2.new(1, -128, 0, 3)\n\t\t\tbox.BackgroundColor3 = t.Background\n\t\t\tbox.Font = t.Font\n\t\t\tbox.TextSize = 12\n\t\t\tbox.TextColor3 = t.Text\n\t\t\tbox.PlaceholderText = def.Placeholder or ''\n\t\t\tbox.Text = def.Default or ''\n\t\t\tbox.ClearTextOnFocus = false\n\t\t\tbox.BorderSizePixel = 0\n\t\t\tbox.Parent = row\n\t\t\tInstance.new('UICorner', box).CornerRadius = UDim.new(0, 6)\n\t\t\tbox:GetPropertyChangedSignal('Text'):Connect(function()\n\t\t\t\toption.Value = box.Text\n\t\t\tend)\n\t\t\toption.Value = box.Text\n\t\tend\n\n\t\t-- Register for config persistence.\n\t\tmod._Options[id] = option\n\t\tautoSize()\n\t\tif option.Set and option.Value ~= nil then\n\t\t\toption.Set(option.Value)\n\t\tend\n\t\treturn option\n\tend\n\n\tmod._Card = cardApi\n\treturn cardApi\nend\n\nfunction GuiLibrary:AddOption(mod, optionType, id, def)\n\t-- Route through the module card; create it lazily.\n\tlocal card = mod._Card or self:CreateModuleCard(mod)\n\treturn card.AddOption(optionType, id, def)\nend\n\nfunction GuiLibrary:Notify(text, duration)\n\tnotify(text, duration)\nend\n\nfunction GuiLibrary:Destroy()\n\tif self.Root then\n\t\tself.Root:Destroy()\n\t\tself.Root = nil\n\tend\nend\n\nreturn GuiLibrary\nend\n"
TESTFILES["axer/libraries/save.lua"] = "-- Axer config profiles. Persists module + option state per game as JSON:\n--   axer/profiles/<PlaceId>/config.json\n-- Loaded as: local SaveLib = loadstring(source, 'save')(AxerCore)\n\nreturn function(Axer)\n\tlocal SaveLib = {}\n\n\tfunction SaveLib.new(core)\n\t\tlocal self = setmetatable({}, { __index = SaveLib })\n\t\tself.Core = core\n\t\tself.Shims = core.Shims\n\t\tself.QueueTimer = nil\n\t\tself.PlaceId = tostring(game.PlaceId)\n\t\tself.ProfileDir = 'axer/profiles/'..self.PlaceId\n\t\tself.ConfigPath = self.ProfileDir..'/config.json'\n\n\t\tself.Shims.MakeFolder('axer/profiles')\n\t\tself.Shims.MakeFolder(self.ProfileDir)\n\t\treturn self\n\tend\n\n\tfunction SaveLib:Load()\n\t\tlocal raw = self.Shims.ReadFile(self.ConfigPath)\n\t\tif not raw then\n\t\t\treturn nil\n\t\tend\n\t\tlocal ok, decoded = pcall(function()\n\t\t\treturn game:GetService('HttpService'):JSONDecode(raw)\n\t\tend)\n\t\tif ok then\n\t\t\treturn decoded\n\t\tend\n\t\twarn('[Axer] Config file was corrupted, starting fresh:', self.ConfigPath)\n\t\treturn nil\n\tend\n\n\tfunction SaveLib:Save(data)\n\t\tlocal ok, encoded = pcall(function()\n\t\t\treturn game:GetService('HttpService'):JSONEncode(data)\n\t\tend)\n\t\tif not ok then\n\t\t\twarn('[Axer] Failed to encode config:', encoded)\n\t\t\treturn false\n\t\tend\n\t\treturn self.Shims.WriteFile(self.ConfigPath, encoded)\n\tend\n\n\t-- Debounced autosave: coalesces rapid changes into one write.\n\tfunction SaveLib:QueueSave()\n\t\tif self.QueueTimer then\n\t\t\ttask.cancel(self.QueueTimer)\n\t\tend\n\t\tself.QueueTimer = task.delay(1, function()\n\t\t\tself.QueueTimer = nil\n\t\t\tself:Save(self.Core.ModuleLibrary:Serialize())\n\t\tend)\n\tend\n\n\tfunction SaveLib:RestoreNow()\n\t\tlocal data = self:Load()\n\t\tif data then\n\t\t\tself.Core.ModuleLibrary:Restore(data)\n\t\tend\n\tend\n\n\tfunction SaveLib:Wipe()\n\t\tself.Shims.DelFile(self.ConfigPath)\n\tend\n\n\treturn SaveLib\nend\n"
TESTFILES["axer/main.lua"] = "-- Axer V1 core. Boot order: shims -> util -> registry -> GUI -> save -> game modules.\n-- Expects shared.AxerBootstrap.readFile (set by NewMainScript.lua) for sources;\n-- falls back to executor readfile (dev mode in Studio).\n\nlocal VERSION = '1.0.0'\n\nlocal bootstrap = shared.AxerBootstrap or {}\nlocal readFile = bootstrap.readFile\n\tor function(path)\n\t\tlocal ok, res = pcall(readfile, path)\n\t\treturn ok and res or nil\n\tend\n\nlocal function loadLib(name)\n\tlocal source = readFile('axer/libraries/'..name..'.lua')\n\tassert(type(source) == 'string', '[Axer] Missing library source: '..name)\n\tlocal chunk, err = loadstring(source, name)\n\tassert(chunk, '[Axer] Failed to compile '..name..': '..tostring(err))\n\tlocal ok, result = pcall(chunk)\n\tassert(ok, '[Axer] Library '..name..' errored: '..tostring(result))\n\treturn result\nend\n\nlocal Axer = {}\nAxer.Version = VERSION\n\nAxer.Util = loadLib('util')(Axer)\nAxer.Shims = loadLib('shims')(Axer)\nAxer.Features = Axer.Shims.Features\nAxer.ModuleToggled = Axer.Util.NewSignal()\n\nlocal ModuleLibrary = loadLib('module')(Axer).new(Axer)\nAxer.ModuleLibrary = ModuleLibrary\nlocal GuiLibrary = loadLib('gui')(Axer).new(Axer)\nAxer.GuiLibrary = GuiLibrary\nlocal SaveLibrary = loadLib('save')(Axer).new(Axer)\nAxer.SaveLibrary = SaveLibrary\n\n----------------------------------------------------------------------\n-- Public API\n----------------------------------------------------------------------\nAxer.CreateModule = function(def)\n\treturn ModuleLibrary:CreateModule(def)\nend\n\n-- Accepts both Axer.GetModule('Name') and Axer:GetModule('Name').\nAxer.GetModule = function(...)\n\tlocal args = { ... }\n\tif type(args[1]) == 'table' then\n\t\treturn ModuleLibrary:GetModule(args[2])\n\tend\n\treturn ModuleLibrary:GetModule(args[1])\nend\n\nAxer.Modules = ModuleLibrary\nAxer.Notify = function(text, duration)\n\tAxer.Util.Notify(text, duration)\nend\n\nfunction Axer.Panic()\n\tModuleLibrary:DisableAll()\n\tGuiLibrary:Destroy()\n\tAxer.Util.Notify('Axer disabled everything.', 2)\nend\n\n-- Panic keybind: LeftControl + RightShift.\ngame:GetService('UserInputService').InputBegan:Connect(function(input, processed)\n\tif processed then return end\n\tif input.KeyCode == Enum.KeyCode.RightShift\n\t\tand game:GetService('UserInputService'):IsKeyDown(Enum.KeyCode.LeftControl) then\n\t\tAxer.Panic()\n\tend\nend)\n\n-- Expose globally.\nshared.Axer = Axer\npcall(function()\n\tgetgenv().Axer = Axer\nend)\n\n----------------------------------------------------------------------\n-- Game modules (PlaceId-specific file first, fallback universal)\n----------------------------------------------------------------------\nlocal function runGameFile(path)\n\tlocal source = readFile(path)\n\tif type(source) ~= 'string' then\n\t\treturn false\n\tend\n\tlocal chunk, err = loadstring(source, path)\n\tif not chunk then\n\t\twarn('[Axer] Failed to compile '..path..': '..tostring(err))\n\t\treturn false\n\tend\n\tlocal ok, runErr = pcall(chunk, Axer)\n\tif not ok then\n\t\twarn('[Axer] '..path..' failed to run: '..tostring(runErr))\n\tend\n\treturn true\nend\n\nif not runGameFile('axer/games/'..game.PlaceId..'.lua') then\n\trunGameFile('axer/games/universal.lua')\nend\n\n-- Build GUI + restore saved config.\nGuiLibrary:Build()\nif Axer.Features.fs then\n\tSaveLibrary:RestoreNow()\nend\n\nAxer.Util.Notify(('Axer V1 loaded (%s, %s)'):format(\n\tVERSION,\n\tAxer.Features.fs and 'fs' or 'memory-only'\n), 4)\n\nreturn Axer\n"
TESTFILES["axer/games/universal.lua"] = "-- Axer universal modules: loaded for every game (PlaceId-specific files\n-- override this by being present). Keep modules client-side and benign here;\n-- game-specific behavior belongs in axer/games/<PlaceId>.lua.\n\n-- Game chunks receive Axer as a vararg (main.lua passes it); the global is\n-- the fallback when executed directly in an executor environment.\nlocal Axer = Axer or (...)\n\n-- Fullbright ---------------------------------------------------------------\nAxer.CreateModule({\n\tName = 'Fullbright',\n\tDescription = 'Brightens the world',\n\tTab = 'Render',\n\tOnEnable = function(self)\n\t\tlocal Lighting = game:GetService('Lighting')\n\t\tself._old = {\n\t\t\tBrightness = Lighting.Brightness,\n\t\t\tAmbient = Lighting.Ambient,\n\t\t\tOutdoorAmbient = Lighting.OutdoorAmbient,\n\t\t\tClockTime = Lighting.ClockTime,\n\t\t\tFogEnd = Lighting.FogEnd,\n\t\t\tGlobalShadows = Lighting.GlobalShadows,\n\t\t}\n\t\tLighting.Brightness = 2\n\t\tLighting.Ambient = Color3.fromRGB(200, 200, 200)\n\t\tLighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)\n\t\tLighting.ClockTime = 14\n\t\tLighting.FogEnd = 1e6\n\t\tLighting.GlobalShadows = false\n\tend,\n\tOnDisable = function(self)\n\t\tlocal Lighting = game:GetService('Lighting')\n\t\tif self._old then\n\t\t\tLighting.Brightness = self._old.Brightness\n\t\t\tLighting.Ambient = self._old.Ambient\n\t\t\tLighting.OutdoorAmbient = self._old.OutdoorAmbient\n\t\t\tLighting.ClockTime = self._old.ClockTime\n\t\t\tLighting.FogEnd = self._old.FogEnd\n\t\t\tLighting.GlobalShadows = self._old.GlobalShadows\n\t\t\tself._old = nil\n\t\tend\n\tend,\n})\n\n-- FPS Booster --------------------------------------------------------------\nAxer.CreateModule({\n\tName = 'FPS Booster',\n\tDescription = 'Lowers rendering quality for more FPS',\n\tTab = 'Render',\n\tOnEnable = function(self)\n\t\tlocal Lighting = game:GetService('Lighting')\n\t\tlocal Terrain = workspace:FindFirstChildOfClass('Terrain')\n\t\tself._old = {\n\t\t\tWaterWaveSize = Terrain and Terrain.WaterWaveSize or 0,\n\t\t\tWaterWaveSpeed = Terrain and Terrain.WaterWaveSpeed or 10,\n\t\t\tWaterReflectance = Terrain and Terrain.WaterReflectance or 0,\n\t\t\tWaterTransparency = Terrain and Terrain.WaterTransparency or 0.5,\n\t\t\tShadows = Lighting.GlobalShadows,\n\t\t}\n\t\tif Terrain then\n\t\t\tTerrain.WaterWaveSize = 0\n\t\t\tTerrain.WaterWaveSpeed = 0\n\t\t\tTerrain.WaterReflectance = 0\n\t\t\tTerrain.WaterTransparency = 1\n\t\tend\n\t\tLighting.GlobalShadows = false\n\t\t-- Effects: remove particles/beams under a cap on every render step is\n\t\t-- too aggressive for a default module; just disable expensive services.\n\t\tpcall(function()\n\t\t\tgame:GetService('Lighting').ChildAdded:Connect(function(child)\n\t\t\t\tif child:IsA('PostEffect') then\n\t\t\t\t\tchild.Enabled = false\n\t\t\t\tend\n\t\t\tend)\n\t\tend)\n\tend,\n\tOnDisable = function(self)\n\t\tlocal Lighting = game:GetService('Lighting')\n\t\tlocal Terrain = workspace:FindFirstChildOfClass('Terrain')\n\t\tif self._old then\n\t\t\tif Terrain then\n\t\t\t\tTerrain.WaterWaveSize = self._old.WaterWaveSize\n\t\t\t\tTerrain.WaterWaveSpeed = self._old.WaterWaveSpeed\n\t\t\t\tTerrain.WaterReflectance = self._old.WaterReflectance\n\t\t\t\tTerrain.WaterTransparency = self._old.WaterTransparency\n\t\t\tend\n\t\t\tLighting.GlobalShadows = self._old.Shadows\n\t\t\tself._old = nil\n\t\tend\n\tend,\n})\n\n-- Panic Button -------------------------------------------------------------\nAxer.CreateModule({\n\tName = 'Panic Button',\n\tDescription = 'Keybind that disables every module instantly',\n\tTab = 'Utility',\n\tInit = function(self)\n\t\tself:AddOption('Keybind', 'panicKey', {\n\t\t\tName = 'Panic key',\n\t\t\tDefault = Enum.KeyCode.Delete,\n\t\t\tCallback = function()\n\t\t\t\tAxer.Panic()\n\t\t\tend,\n\t\t})\n\tend,\n})\n\n-- HUD Overlay --------------------------------------------------------------\nAxer.CreateModule({\n\tName = 'HUD Overlay',\n\tDescription = 'Simple FPS and ping counter in the corner',\n\tTab = 'Render',\n\tOnEnable = function(self)\n\t\tlocal Players = game:GetService('Players')\n\t\tlocal RunService = game:GetService('RunService')\n\t\tlocal Stats = game:GetService('Stats')\n\n\t\tlocal gui = Instance.new('ScreenGui')\n\t\tgui.Name = 'AxerHudOverlay'\n\t\tgui.ResetOnSpawn = false\n\t\tlocal label = Instance.new('TextLabel')\n\t\tlabel.Size = UDim2.new(0, 180, 0, 24)\n\t\tlabel.Position = UDim2.new(0, 10, 0, 10)\n\t\tlabel.BackgroundColor3 = Axer.Util.Theme.Background\n\t\tlabel.BackgroundTransparency = 0.35\n\t\tlabel.TextColor3 = Axer.Util.Theme.Text\n\t\tlabel.Font = Axer.Util.Theme.Font\n\t\tlabel.TextSize = 13\n\t\tlabel.Text = ''\n\t\tlabel.Parent = gui\n\t\tAxer.Util.SafeParent(gui)\n\n\t\tlocal frameCount, lastRefresh = 0, os.clock()\n\t\tself:Track(RunService.RenderStepped:Connect(function()\n\t\t\tframeCount += 1\n\t\t\tlocal now = os.clock()\n\t\t\tif now - lastRefresh >= 0.5 then\n\t\t\t\tlocal fps = math.floor(frameCount / (now - lastRefresh) + 0.5)\n\t\t\t\tlocal ping = 0\n\t\t\t\tpcall(function()\n\t\t\t\t\tping = math.floor(Stats.Network.ServerStatsItem['Data Ping']:GetValue() + 0.5)\n\t\t\t\tend)\n\t\t\t\tlabel.Text = ('FPS %d | Ping %d ms'):format(fps, ping)\n\t\t\t\tframeCount, lastRefresh = 0, now\n\t\t\tend\n\t\tend))\n\t\tself._gui = gui\n\tend,\n\tOnDisable = function(self)\n\t\tif self._gui then\n\t\t\tself._gui:Destroy()\n\t\t\tself._gui = nil\n\t\tend\n\tend,\n})\n\nAxer.Notify('Universal modules registered.', 3)\n"
print("[boot] executing axer/main.lua through the loadstring pipeline")
Axer = assert(loadstring(TESTFILES["axer/main.lua"], "main"))()

-- Axer offline boot test (body). The runner seeds the real axer sources into
-- the mock filesystem, boots the real axer/main.lua, then runs these checks.

print('== Axer offline boot test ==')

CHECK(type(Axer) == 'table' and type(Axer.CreateModule) == 'function', 'main boot exposed Axer API')
CHECK(shared.Axer == Axer, 'Axer exposed via shared')
CHECK(type(Axer.Features) == 'table' and Axer.Features.fs == true, 'mock executor filesystem detected')
CHECK(type(Axer.Util) == 'table' and type(Axer.Util.Notify) == 'function', 'util library loaded')
CHECK(type(Axer.ModuleLibrary) == 'table' and type(Axer.ModuleLibrary.Serialize) == 'function', 'module library loaded')
CHECK(type(Axer.GuiLibrary) == 'table' and type(Axer.GuiLibrary.CreateModuleCard) == 'function', 'gui library loaded')
local AxerGuiLibrary = Axer.GuiLibrary
CHECK(type(Axer.SaveLibrary) == 'table' and type(Axer.SaveLibrary.QueueSave) == 'function', 'save library loaded')

-- LocalPlayer should have been parented into CoreGui by the GUI.
CHECK(CoreGuiService:FindFirstChild('AxerWindow') ~= nil
	or PlayersService.LocalPlayer:FindFirstChild('AxerWindow') ~= nil,
	'window screen gui created')

-- Universal modules registered.
local fullbright = Axer:GetModule('Fullbright')
local fps = Axer:GetModule('FPS Booster')
local panic = Axer:GetModule('Panic Button')
local hud = Axer:GetModule('HUD Overlay')
CHECK(fullbright ~= nil, 'Fullbright registered')
CHECK(fps ~= nil, 'FPS Booster registered')
CHECK(panic ~= nil, 'Panic Button registered')
CHECK(hud ~= nil, 'HUD Overlay registered')

-- Toggle Fullbright and verify it mutates Lighting, then reverts.
fullbright:Toggle(true)
CHECK(fullbright.Enabled == true, 'Fullbright enables')
CHECK(LightingService.GlobalShadows == false, 'Fullbright disables shadows')
fullbright:Toggle(false)
CHECK(fullbright.Enabled == false, 'Fullbright disables')
CHECK(LightingService.GlobalShadows == true, 'Fullbright restores shadows')

-- FPS Booster round trip.
fps:Toggle(true)
CHECK(TerrainService.WaterWaveSize == 0, 'FPS Booster flattens water waves')
fps:Toggle(false)
CHECK(TerrainService.WaterWaveSize == 10, 'FPS Booster restores water waves')

-- HUD enables, renders a frame tick, disables cleanly.
hud:Toggle(true)
RunServiceMock.RenderStepped:Fire()
task.wait()
hud:Toggle(false)
CHECK(hud._gui == nil, 'HUD destroys its gui on disable')

-- Options + config persistence round trip through the mocked filesystem.
panic:Toggle(true)
CHECK(panic:GetOption('panicKey') == 'Delete', 'panic keybind option default registered')

-- Give the debounced autosave a chance to flush (task.delay runs immediately
-- in the harness, but QueueSave uses a fresh timer each call).
Axer.SaveLibrary:QueueSave()
local raw = TESTFILES['axer/profiles/0/config.json']
CHECK(type(raw) == 'string', 'config json written to mocked filesystem')

local decoded = HttpServiceMock:JSONDecode(raw)
CHECK(decoded['Panic Button'] ~= nil, 'config contains Panic Button state')
CHECK(decoded['Panic Button'].Enabled == true, 'config records enabled module')

-- Restore into a fresh state: disable everything, restore from disk.
Axer.ModuleLibrary:DisableAll()
CHECK(panic.Enabled == false, 'DisableAll disables modules')
Axer.SaveLibrary:RestoreNow()
CHECK(panic.Enabled == true, 'RestoreNow re-enables module from config')

-- CreateModule guard rails.
local okDup = pcall(function()
	Axer.CreateModule({ Name = 'Fullbright' })
end)
CHECK(not okDup, 'duplicate module names rejected')

-- Panic tears down the GUI.
Axer.Panic()
CHECK(panic.Enabled == false, 'panic disables modules')
CHECK(AxerGuiLibrary.Root == nil, 'panic destroys the GUI')

CHECK_ERRORS()

