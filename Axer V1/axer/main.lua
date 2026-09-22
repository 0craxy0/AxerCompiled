-- Axer V1 core. Boot order: shims -> util -> registry -> GUI -> save -> game modules.
-- Expects shared.AxerBootstrap.readFile (set by NewMainScript.lua) for sources;
-- falls back to executor readfile (dev mode in Studio).

local VERSION = '1.0.0'

local bootstrap = shared.AxerBootstrap or {}
local readFile = bootstrap.readFile
	or function(path)
		local ok, res = pcall(readfile, path)
		return ok and res or nil
	end

local function loadLib(name)
	local source = readFile('axer/libraries/'..name..'.lua')
	assert(type(source) == 'string', '[Axer] Missing library source: '..name)
	local chunk, err = loadstring(source, name)
	assert(chunk, '[Axer] Failed to compile '..name..': '..tostring(err))
	local ok, result = pcall(chunk)
	assert(ok, '[Axer] Library '..name..' errored: '..tostring(result))
	return result
end

local Axer = {}
Axer.Version = VERSION

Axer.Util = loadLib('util')(Axer)
Axer.Shims = loadLib('shims')(Axer)
Axer.Features = Axer.Shims.Features
Axer.ModuleToggled = Axer.Util.NewSignal()

local ModuleLibrary = loadLib('module')(Axer).new(Axer)
Axer.ModuleLibrary = ModuleLibrary
local GuiLibrary = loadLib('gui')(Axer).new(Axer)
Axer.GuiLibrary = GuiLibrary
local SaveLibrary = loadLib('save')(Axer).new(Axer)
Axer.SaveLibrary = SaveLibrary

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
Axer.CreateModule = function(def)
	return ModuleLibrary:CreateModule(def)
end

-- Accepts both Axer.GetModule('Name') and Axer:GetModule('Name').
Axer.GetModule = function(...)
	local args = { ... }
	if type(args[1]) == 'table' then
		return ModuleLibrary:GetModule(args[2])
	end
	return ModuleLibrary:GetModule(args[1])
end

Axer.Modules = ModuleLibrary
Axer.Notify = function(text, duration)
	Axer.Util.Notify(text, duration)
end

function Axer.Panic()
	ModuleLibrary:DisableAll()
	GuiLibrary:Destroy()
	Axer.Util.Notify('Axer disabled everything.', 2)
end

-- Panic keybind: LeftControl + RightShift.
game:GetService('UserInputService').InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift
		and game:GetService('UserInputService'):IsKeyDown(Enum.KeyCode.LeftControl) then
		Axer.Panic()
	end
end)

-- Expose globally.
shared.Axer = Axer
pcall(function()
	getgenv().Axer = Axer
end)

----------------------------------------------------------------------
-- Game modules (PlaceId-specific file first, fallback universal)
----------------------------------------------------------------------
local function runGameFile(path)
	-- Optional: missing per-game files are normal (some executors even raise on
	-- 404 rather than returning the body); universal.lua is the fallback.
	local okFetch, source = pcall(readFile, path, true)
	if not okFetch or type(source) ~= 'string' then
		return false
	end
	local chunk, err = loadstring(source, path)
	if not chunk then
		warn('[Axer] Failed to compile '..path..': '..tostring(err))
		return false
	end
	local ok, runErr = pcall(chunk, Axer)
	if not ok then
		warn('[Axer] '..path..' failed to run: '..tostring(runErr))
	end
	return true
end

if not runGameFile('axer/games/'..game.PlaceId..'.lua') then
	runGameFile('axer/games/universal.lua')
end

-- Build GUI + restore saved config.
GuiLibrary:Build()
if Axer.Features.fs then
	SaveLibrary:RestoreNow()
end

Axer.Util.Notify(('Axer V1 loaded (%s, %s)'):format(
	VERSION,
	Axer.Features.fs and 'fs' or 'memory-only'
), 4)

return Axer
