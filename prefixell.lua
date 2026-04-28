package.path =(arg[0]:match("@?(.*[/\\])") or "./").."?.lua;"..package.path
local is_windows = package.config:sub(1,1) == "\\"
local prefixell = require('compiler')
local comp = prefixell:new()

local function run_lua(code, show_result)
  if not code then return end
  local chunk, err = load("return " .. code)
  if not chunk then chunk, err = load(code) end
  if chunk then
    local status, res = pcall(chunk)
    if status then
      if show_result and res ~= nil and type(res) ~= "function" and type(res) ~= "table" then
        print(":=> " .. tostring(res))
      elseif show_result and type(res) == "table" then
        print(":=> " .. (tdump and tdump(res) or tostring(res)))
      end
    else
      print("runtime error: " .. tostring(res))
    end
  else
    print("error in compiled code: " .. tostring(err))
  end
end

if arg[1] == "c" then
  if arg[2] and arg[3] then
    local inp, err = io.open(arg[2], 'r')
    if not inp then error("error opening source file: " .. err) end
    local lua_code, comp_err = comp:compile(inp:read('*a'))
    inp:close()
    if comp_err then
      print(comp_err)
      os.exit(1)
    end
    local out = io.open(arg[3], "w")
    out:write(prefixell.init_code .. "\n" .. lua_code)
    out:close()
  else
    print("please provide both source and output file.")
  end
elseif arg[1] == "r" then
  local dbg, show_p = false, true
  load(prefixell.init_code)()
  if arg[2] then
    local inp, err = io.open(arg[2], 'r')
    if not inp then error("error opening source file: " .. err) end
    local lua_code, comp_err = comp:compile(inp:read('*a'))
    inp:close()
    if comp_err then print(comp_err) else run_lua(lua_code, show_p) end
  end
  while true do
    io.write("> ")
    local repl_inp = io.read()
    if not repl_inp or repl_inp == ":q" then break end
    if repl_inp == ":h" then
      print("Commands:\n :q - quit\n :d - toggle debug (show lua)\n :p - toggle printing results\n :h - help")
    elseif repl_inp == ":d" then
      dbg = not dbg
      print("debug: " .. tostring(dbg))
    elseif repl_inp == ":p" then
      show_p = not show_p
      print("print results: " .. tostring(show_p))
    elseif repl_inp ~= "" then
      local lua_code, comp_err = comp:compile(repl_inp)
      if comp_err then
        print(comp_err)
      else
        if dbg then print(lua_code) end
        run_lua(lua_code, show_p)
      end
    end
  end
elseif arg[1] == "build" then
  local cfg_path = "cfg.lc.lua"
  local cfg_func, err = loadfile(cfg_path)
  if not cfg_func then
    print("Could not find " .. cfg_path)
    os.exit(1)
  end
  local cfg, target = cfg_func(), arg[2]
  local function get_output_path(file)
    if cfg.outputs and cfg.outputs[file] then return cfg.outputs[file] end
    return file:gsub("%.lc$", ".lua")
  end
  local function run_target(target_name)
    local t = cfg.targets[target_name]
    if not t then return end
    if t.prerun then for _, pre in ipairs(t.prerun) do run_target(pre) end end
    for _, cmd in ipairs(t) do
      if type(cmd) == "string" then
        print("Running: " .. cmd)
        local success = os.execute(cmd)
        if not success then os.exit(1) end
      end
    end
  end
  if target and cfg.targets and cfg.targets[target] then run_target(target)
  else
    local seen, building = {}, {}
    local function build_file(file, is_entry)
      is_entry = is_entry or false
      if seen[file] then return end
      if building[file] then error("Circular dependency: " .. file) end
      building[file] = true
      local out_path = get_output_path(file)
      local f_lc, open_err = io.open(file, "r")
      if not f_lc then error("Could not open " .. file .. ": " .. tostring(open_err)) end
      local content = f_lc:read("*a")
      f_lc:close()
      print("Building: " .. file .. " -> " .. out_path)
      local lua_code, c_err = comp:compile(content)
      if not c_err then
        local out, out_err = io.open(out_path, "w")
        if not out then error("Could not open " .. out_path .. ": " .. tostring(out_err)) end
        out:write((is_entry and (prefixell.init_code .. "\n") or "") .. lua_code)
        out:close()
      else error("Error in " .. file .. ":\n" .. c_err)  end
      building[file], seen[file] = nil, true
    end
    local function process_deps(deps) for key, value in pairs(deps) do if type(key) == "string" then process_deps(value); build_file(key) elseif type(value) == "table" then process_deps(value) else build_file(value) end end end
    local status, build_err = pcall(function()
      if cfg.dep_list then process_deps(cfg.dep_list) end
      if cfg.entry then build_file(cfg.entry, true) end
    end)
    if not status then
      print("Build failed: " .. tostring(build_err))
      os.exit(1)
    end
  end
elseif arg[1] == "pkg" then
  local action,pkg_path,pkgs_dir = arg[2],arg[3],"pkgs"
  local function check_git()
    local success = os.execute("git --version > " .. (package.config:sub(1,1) == "\\" and "nul" or "/dev/null") .. " 2>&1")
    if not success then print("Error: 'git' is not installed or not in PATH. Please install Git to use pkg features.") os.exit(1) end
  end
  local function parse_url(input)
    local host_map = { gh = "github.com", gl = "gitlab.com", cb = "codeberg.org" }
    local prefix, path = input:match("^(%w+):(.+)$")
    if prefix and host_map[prefix] then
      local repo, branch = path:match("([^@]+)@?([^@]*)")
      return "https://" .. host_map[prefix] .. "/" .. repo, branch ~= "" and branch or nil
    end
    return input, nil
  end
  local function download_pkg(url, branch,should_build)
    check_git()
    local name = url:match("([^/]+)$"):gsub("%.git$", "")
    local target = pkgs_dir .. "/" .. name
    print("Cloning " .. url .. " into " .. target .. "...")
    local cmd = string.format("git clone --depth 1 %s %s %s 2> %s || (cd %s && git pull)", branch and ("-b " .. branch) or "",  url, target,(package.config:sub(1,1) == "\\" and "nul" or "/dev/null"),target)
    if os.execute(cmd) then
      print("Successfully downloaded: " .. name)
      if should_build and io.open(target .. "/cfg.lc.lua", "r") then
        print("Prefixell project detected. Building...")
        print("Build package " .. name .. "? (y/n)")
        if io.read() ~= "y" then return end
        os.execute("cd " .. target .. " && prefixell build")
      end
      return name
    else
      print("Failed to download package.")
      return nil
    end
  end
  if action == "add" or action == "dl" then
    if not pkg_path then print("Usage: pkg " .. action .. " <url|shorthand>") os.exit(1) end
    os.execute((is_windows and "mkdir "..pkgs_dir.."2>nul") or "mkdir -p " .. pkgs_dir)
    local url, branch = parse_url(pkg_path)
    local name = download_pkg(url, branch,action == "add")
    if name then print("\nRemember to add '" .. name .. "' to 'pkgs' list in cfg.lc.lua or ur finished") end
  elseif action == "sync" then
    local cfg_func = loadfile("cfg.lc.lua")
    if not cfg_func then print("cfg.lc.lua not found.") os.exit(1) end
    local cfg = cfg_func()
    if cfg.pkgs then
      if cfg.pkgs.add then for _, p in ipairs(cfg.pkgs.add) do local url, branch = parse_url(p); download_pkg(url, branch,true) end end
      if cfg.pkgs.dl then for _, p in ipairs(cfg.pkgs.dl) do local url, branch = parse_url(p); download_pkg(url, branch,false) end end
    end
  else
    print([[
prefixell package manager:
  add <provider: gh|gl|cb>:user/name[@branch :optional] -> download package from provider and build it if its a prefixell project
  dl <provider: gh|gl|cb>:user/name[@branch :optional] -> just download
  sync -> downloads (and build if specified) packages stated in cfg.lc.lua]])
  end
elseif arg[1] == "init" then
  local cfg = io.open("cfg.lc.lua","w")
  cfg:write([[
return {
  entry = "main.lc",
  dep_list = {},
  outputs = {},
  pkgs = { 
    add = {},
    dl = {}
  },
  targets = {}
}]])
  cfg:close()
else
  print([[
prefixell cli:
  c <input.lc> <output.lua> -> compile source to lua
  r <optional_entry.lc> -> read-eval-print-loop
  build <target: optional> -> build the project based on cfg.lc.lua,or run the given target
  pkg <add|dl|sync> -> prefixell package manager]])
end