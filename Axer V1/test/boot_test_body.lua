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
