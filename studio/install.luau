--[[
Install ForgeVFX (the VFX Forge emit module, VFX-DL-1.1) into ReplicatedStorage of the open place.
Run it from the Studio command bar or a plugin context (e.g. the Studio MCP execute_luau), in Edit mode.

It pulls the sources of REF from this GitHub repo and rebuilds the Rojo tree
(src -> ModuleScript "ForgeVFX", src/<dir> -> Folder, pkg -> Folder), rewriting the
.luaurc string requires ("@mod/utility", "./logger") into instance requires, like the release's darklua bundle.

Use in game code:
	local vfx = require(game.ReplicatedStorage.ForgeVFX)
	vfx.init()
	vfx.emit(someModelOrPart)
]]
local REPO, REF = "arelixsz/forge-vfx", "v2.4.0"
local ALIAS = { pkg = { "pkg" }, mod = { "mod" }, obj = { "obj" }, vfx = { "effects" }, srv = { "services" }, root = {} }

local Http = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local function index(parts: { string }): string
	local s = "__forge"
	for _, p in parts do
		s ..= string.format("[%q]", p)
	end
	return s
end

-- dirParts: the module's folder path under the root, e.g. {"mod"} for src/mod/attributes.luau
local function rewrite(src: string, dirParts: { string }, isRoot: boolean): string
	src = src:gsub('require%(%s*"([^"]+)"%s*%)', function(spec: string)
		local parts
		local alias, rest = spec:match("^@(%w+)/?(.*)$")
		if alias then
			parts = table.clone(assert(ALIAS[alias], "unknown require alias @" .. alias))
		else
			parts = table.clone(dirParts)
			rest = spec
		end
		for seg in rest:gmatch("[^/]+") do
			if seg == ".." then
				table.remove(parts)
			elseif seg ~= "." then
				table.insert(parts, seg)
			end
		end
		return "require(" .. index(parts) .. ")"
	end)
	local head = isRoot and "local __forge = script" or 'local __forge = script:FindFirstAncestor("ForgeVFX")'
	-- keep --! directives (--!native, --!nolint) on the first lines
	local pos = 1
	while src:sub(pos, pos + 2) == "--!" do
		local nl = src:find("\n", pos, true)
		if not nl then
			break
		end
		pos = nl + 1
	end
	return src:sub(1, pos - 1) .. head .. "\n" .. src:sub(pos)
end

local was = Http.HttpEnabled
Http.HttpEnabled = true
local ok, err = pcall(function()
	local tree = Http:JSONDecode(Http:GetAsync(
		string.format("https://api.github.com/repos/%s/git/trees/%s?recursive=1", REPO, REF)
	))
	local root = Instance.new("ModuleScript")
	root.Name = "ForgeVFX"
	local n = 0
	for _, item in tree.tree do
		local path: string = item.path
		local top = path:match("^(%w+)/")
		if item.type ~= "blob" or not path:match("%.luau$") or (top ~= "src" and top ~= "pkg") then
			continue
		end
		local src = Http:GetAsync(string.format("https://raw.githubusercontent.com/%s/%s/%s", REPO, REF, path))
		local parts = string.split(path:gsub("%.luau$", ""), "/")
		if top == "src" then
			table.remove(parts, 1) -- src is the root itself
		end
		local name = table.remove(parts)
		if path == "src/init.luau" then
			root.Source = rewrite(src, {}, true)
		else
			local parent: Instance = root
			for _, dir in parts do
				parent = parent:FindFirstChild(dir) or (function()
					local f = Instance.new("Folder")
					f.Name = dir
					f.Parent = parent
					return f
				end)()
			end
			local m = Instance.new("ModuleScript")
			m.Name = name
			m.Source = rewrite(src, parts, false)
			m.Parent = parent
		end
		n += 1
	end
	assert(n > 0 and root.Source ~= "", "no sources found at " .. REPO .. "@" .. REF)
	local old = RS:FindFirstChild("ForgeVFX")
	if old then
		old:Destroy()
	end
	root:SetAttribute("ForgeVFXRef", REPO .. "@" .. REF)
	root.Parent = RS
	print(string.format("ForgeVFX %s installed: %d modules in ReplicatedStorage.ForgeVFX", REF, n))
end)
Http.HttpEnabled = was
if not ok then
	warn("ForgeVFX install failed: " .. tostring(err))
end
