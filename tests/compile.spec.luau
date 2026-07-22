--!nonstrict
-- Syntax gate: luau-compiles every module under src/ (client files included —
-- nothing else exercises those headlessly). Catches parse errors in seconds.
-- Run outside Studio:  lune run tests/compile.spec.luau

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local root = if fs.isDir("src") then "src" elseif fs.isDir("../src") then "../src" else nil
if not root then
	print("FAIL run from the repo root (src/ not found)")
	process.exit(1)
end

local files = {}
local function collect(dir)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path)
		elseif string.match(name, "%.luau$") then
			table.insert(files, path)
		end
	end
end
collect(root)
table.sort(files)

local failed = 0
for _, path in files do
	local ok, err = pcall(function()
		luau.compile(fs.readFile(path))
	end)
	if ok then
		print(`  ok  {path}`)
	else
		failed += 1
		print(`FAIL {path} — {tostring(err)}`)
	end
end

if failed > 0 then
	print(`\n{failed} file(s) failed to compile.`)
	process.exit(1)
end
print(`\nAll {#files} files compile.`)
