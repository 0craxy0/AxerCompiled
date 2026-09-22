-- Axer compatibility layer: detects executor APIs, builds the Axer.Features
-- capability set, and exposes unified wrappers so modules can degrade
-- gracefully instead of crashing on weaker executors.
-- Loaded as: local Features = loadstring(source, 'shims')(AxerCore)

return function(Axer)
	local Shims = {}

	local HttpService = game:GetService('HttpService')

	local function detectHttp()
		local ok = pcall(function()
			return game:HttpGet('https://github.com', true)
		end)
		if ok then
			return 'HttpGet', function(url)
				local okCall, body = pcall(function()
					return game:HttpGet(url, true)
				end)
				if not okCall then
					error('[Axer] HttpGet failed: '..tostring(body), 0)
				end
				return body
			end
		end
		local requestFn = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
		if type(requestFn) == 'function' then
			return 'request', function(url)
				local okCall, res = pcall(function()
					return requestFn({ Url = url, Method = 'GET' })
				end)
				if not okCall then
					error('[Axer] request failed: '..tostring(res), 0)
				end
				return res and (res.Body or res.body) or nil
			end
		end
		return nil, nil
	end

	local httpName, httpFn = detectHttp()

	Shims.Features = {
		fs = type(writefile) == 'function' and type(readfile) == 'function' and type(isfile) == 'function',
		http = httpFn ~= nil,
		identifier = httpName,
		json = typeof(HttpService) == 'Instance' and type(HttpService.JSONDecode) == 'function',
		getcustomasset = type(getcustomasset) == 'function',
		queue_on_teleport = type(queue_on_teleport) == 'function' or type(queueonteleport) == 'function',
		debug = type(debug) == 'table' and type(debug.getinfo) == 'function',
		drawables = type(Drawing) == 'table',
		mouse = type(mouse) == 'table',
	}

	Shims.Http = httpFn or function()
		error('[Axer] No HTTP implementation available (tried game:HttpGet and request).', 0)
	end

	-- Unified filesystem wrappers: real FS when available, in-memory otherwise.
	local mem = {}

	if Shims.Features.fs then
		function Shims.ReadFile(path)
			local ok, res = pcall(readfile, path)
			return ok and res or nil
		end
		function Shims.WriteFile(path, data)
			return pcall(writefile, path, data)
		end
		function Shims.IsFile(path)
			local ok, res = pcall(isfile, path)
			return ok and res == true
		end
		function Shims.IsFolder(path)
			local ok, res = pcall(isfolder, path)
			return ok and res == true
		end
		function Shims.ListFiles(path)
			local ok, res = pcall(listfiles, path)
			return ok and type(res) == 'table' and res or {}
		end
		function Shims.MakeFolder(path)
			local ok, exists = pcall(isfolder, path)
			if ok and exists then return true end
			return pcall(makefolder, path)
		end
		function Shims.DelFile(path)
			return pcall(delfile, path)
		end
	else
		-- Files exist per-session only.
		function Shims.ReadFile(path)
			return mem[path]
		end
		function Shims.WriteFile(path, data)
			mem[path] = data
			return true
		end
		function Shims.IsFile(path)
			return mem[path] ~= nil
		end
		function Shims.IsFolder()
			return false
		end
		function Shims.ListFiles()
			return {}
		end
		function Shims.MakeFolder() end
		function Shims.DelFile(path)
			mem[path] = nil
		end
	end

	return Shims
end
