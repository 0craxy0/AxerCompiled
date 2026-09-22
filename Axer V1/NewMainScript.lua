--[[
	Axer V1 — bootstrap entry point.

	This is the only file users need to execute:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/<you>/AxerCompiled/main/NewMainScript.lua", true))()

	- Mirrors the axer/ folder layout in a GitHub repo (see REPO below).
	- Caches downloaded files in the executor filesystem; re-downloads only
	  when the pinned commit changes or a file loses its cache watermark.
	- Without filesystem APIs it still runs, just fully in-memory per session.
	- Developer mode: set shared.AxerDeveloper = true BEFORE executing to load
	  straight from the local `axer/` folder next to this script (Studio).
]]

local REPO = 'user/AxerCompiled' -- TODO: replace with '<owner>/<repo>'
local BRANCH = 'main'
local CACHE = 'axer'
local FOLDERS = { CACHE, CACHE..'/games', CACHE..'/profiles', CACHE..'/assets', CACHE..'/libraries' }

-- Cache watermark: any downloaded .lua file starts with this line. Files with
-- the watermark are safe to delete on update; user files never carry it.
local WATERMARK = '--axer-cache: managed file, safe to auto-delete\n'

----------------------------------------------------------------------
-- Minimal executor shims (this file must not depend on axer/libraries)
----------------------------------------------------------------------
local isfolder = isfolder or function() return false end
local isfile = isfile or function() return false end
local makefolder = makefolder or function() end
local writefile = writefile or function() end
local readfile = readfile or function() return nil end
local listfiles = listfiles or function() return {} end
local delfile = delfile or function() end
local HAS_FS = type(writefile) == 'function' and type(readfile) == 'function' and type(isfile) == 'function'

local function httpGet(url)
	if type(game) == 'table' or type(game) == 'userdata' then
		local ok, res = pcall(function() return game:HttpGet(url, true) end)
		if ok and res then return res end
	end
	local requestFn = request or http_request or (syn and syn.request)
	if requestFn then
		local ok, res = pcall(function()
			local r = requestFn({ Url = url, Method = 'GET' })
			return r and (r.Body or r.body)
		end)
		if ok and res then return res end
	end
	error('[Axer] No working HTTP implementation; cannot download '..url, 0)
end

local function readLocal(path)
	-- Dev mode / Studio: read from the workspace copy next to this script.
	local suc, res = pcall(readfile, path)
	return suc and res or nil
end

----------------------------------------------------------------------
-- Cache management
----------------------------------------------------------------------
if not shared.AxerDeveloper then
	for _, folder in FOLDERS do
		if not isfolder(folder) then
			pcall(makefolder, folder)
		end
	end
end

local function downloadFile(path)
	if shared.AxerDeveloper then
		local src = readLocal(path)
		if src then return src end
		error('[Axer] dev mode: missing local file '..path, 0)
	end

	-- 1. Fresh cached copy?
	if HAS_FS and isfile(path) then
		local ok, cached = pcall(readfile, path)
		if ok and type(cached) == 'string' and #cached > 0 and cached:sub(1, #WATERMARK) == WATERMARK then
			return cached
		end
		-- missing or user-owned file: fall through to download
	end

	-- 2. Download and cache (only when we have somewhere to put it).
	local url = ('https://raw.githubusercontent.com/%s/%s/%s'):format(REPO, BRANCH, path)
	local res = httpGet(url)
	if res == '404: Not Found' or res:find('^404:') then
		error('[Axer] '..path..' not found in '..REPO..'@'..BRANCH, 0)
	end
	if HAS_FS then
		pcall(writefile, path, WATERMARK..res)
	end
	return WATERMARK..res
end

local function wipeFolder(path)
	if not HAS_FS or not isfolder(path) then return end
	local ok, files = pcall(listfiles, path)
	if not ok or type(files) ~= 'table' then return end
	for _, file in files do
		if file:find('loader') then continue end
		if isfile(file) then
			local okRead, content = pcall(readfile, file)
			if okRead and type(content) == 'string' and content:sub(1, #WATERMARK) == WATERMARK then
				pcall(delfile, file)
			end
		end
	end
end

if not shared.AxerDeveloper then
	-- Commit pinning: JSON API first, HTML scrape as fallback (Vape-style).
	local commit
	local okApi, apiBody = pcall(httpGet, ('https://api.github.com/repos/%s/commits/%s'):format(REPO, BRANCH))
	if okApi and apiBody then
		local okJson, decoded = pcall(function()
			local HttpService = game:GetService('HttpService')
			return HttpService:JSONDecode(apiBody)
		end)
		if okJson and type(decoded) == 'table' then
			commit = type(decoded.sha) == 'string' and decoded.sha
				or (type(decoded.commit) == 'table' and type(decoded.commit.tree) == 'table' and decoded.commit.tree.sha)
		end
	end
	if not commit then
		local okScrape, page = pcall(httpGet, 'https://github.com/'..REPO)
		if okScrape and page then
			local pos = page:find('currentOid', 1, true)
			commit = pos and page:sub(pos + 13, pos + 52) or nil
			if commit and #commit ~= 40 then commit = nil end
		end
	end
	commit = (commit and #commit == 40) and commit or BRANCH

	local commitPath = CACHE..'/profiles/commit.txt'
	local cachedCommit = HAS_FS and isfile(commitPath) and readLocal(commitPath) or ''
	if commit == BRANCH or cachedCommit ~= commit then
		-- New upstream version: drop every watermarked cache file, keep user files.
		for _, folder in FOLDERS do
			wipeFolder(folder)
		end
	end
	if HAS_FS then
		pcall(writefile, commitPath, commit)
	end
end

-- Expose the file pipeline so axer/main.lua can pull libraries, assets and
-- game modules through the same cache (download-on-demand, watermark-stamped).
shared.AxerBootstrap = { readFile = downloadFile }

return loadstring(downloadFile(CACHE..'/main.lua'), 'main')()
