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
