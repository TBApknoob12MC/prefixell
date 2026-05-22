package.path =(arg[0]:match("@?(.*[/\\])") or "./").."?.lua;"..package.path
local sep = package.config:sub(1,1); local is_windows = sep == "\\"
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
    io.write("> ") io.flush()
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
  local function get_global_dir()
    if is_windows then local base = os.getenv("LOCALAPPDATA") or (os.getenv("USERPROFILE") .. "\\AppData\\Local"); return base .. "\\prefixell\\pkgs" end
    local base = os.getenv("XDG_DATA_HOME")
    if not base or base == "" then base = (os.getenv("HOME") or "") .. "/.local/share" end
    return base .. "/prefixell/pkgs"
  end
  local global_pkgs_dir = get_global_dir():gsub("[\\/]+", is_windows and "\\" or "/")
  local is_global,add_to_cfg = false, true ; for _,v in ipairs(arg) do if v == "-g" or v == "--global" then is_global = true end if v == "-p" or v == "--prevent-add" then add_to_cfg = false end end
  local action,pkg_path,pkgs_dir = arg[2],arg[3],(is_global and global_pkgs_dir or "pkgs")
  local function check_git()
    local success = os.execute("git --version > " .. (package.config:sub(1,1) == "\\" and "nul" or "/dev/null") .. " 2>&1")
    if not success then print("Error: 'git' is not installed or not in PATH. Please install Git to use pkg features.") os.exit(1) end
  end
  local function parse_url(input)
    local host_map = { gh = "github.com", gl = "gitlab.com", cb = "codeberg.org" }
    if input:find("^https?://") or input:find("^git:@") then
      local url_part, branch = input:match("([^@]+)@?([^@]*)")
      return url_part, (branch ~= "" and branch or nil)
    end
    local prefix, path = input:match("^(%w+):(.+)$")
    if prefix and host_map[prefix] then
      local repo, branch = path:match("([^@]+)@?([^@]*)")
      return "https://" .. host_map[prefix] .. "/" .. repo, branch ~= "" and branch or nil
    end
    return input, nil
  end
  local function download_pkg(url, branch,should_build)
    check_git()
    local name = url:gsub("/+$",""):match("([^/]+)$"):gsub("%.git$", "")
    local target = pkgs_dir .. "/" .. name
    print("Cloning " .. url .. " into " .. target .. "...")
    local cmd = string.format("git clone --depth 1 %s %s %s 2> %s || git -C %s pull", branch and ("-b " .. branch) or "",  url, target,(is_windows and "nul" or "/dev/null"),target)
    if os.execute(cmd) then
      print("Successfully downloaded: " .. name)
      if should_build and io.open(target .. "/cfg.lc.lua", "r") then
        print("Prefixell project detected. Building...")
        print("Build package " .. name .. "? (y/n)")
        if io.read():sub(1,1):lower() ~= "y" then return end
        os.execute("cd '" .. target .. "' && prefixell build")
      end
      return name
    else
      print("Failed to download package.")
      return nil
    end
  end
  if action == "add" or action == "dl" then
    if not pkg_path then print("Usage: pkg " .. action .. " <url|shorthand>") os.exit(1) end
    os.execute((is_windows and "mkdir "..pkgs_dir.." 2>nul") or "mkdir -p " .. pkgs_dir)
    local url, branch = parse_url(pkg_path)
    local name = download_pkg(url, branch,action == "add")
    if name and add_to_cfg and not is_global then
      local f = io.open("cfg.lc.lua","r")
      if f then 
        local content = f:read("*a"); f:close()
        local target_key = (action == "add") and "add" or "dl"
        if not content:find(string.format("%q",pkg_path)) then
          local nc,count = content:gsub(target_key.."%s*=%s*{",target_key.."= { "..string.format("%q",pkg_path)..", ")
          if count > 0 then
            local out = io.open("cfg.lc.lua","w"); out:write(nc); out:close()
            print("Added '" .. pkg_path .. "' to cfg.lc.lua (" .. target_key .. ")")
          else print("Warning: Could not automatically update cfg.lc.lua (table not found).") end
        else print("Note: Package already exists in cfg.lc.lua.") end
      end
    end
  elseif action == "sync" then
    local cfg_func = loadfile("cfg.lc.lua")
    if not cfg_func then print("cfg.lc.lua not found.") os.exit(1) end
    local cfg = cfg_func()
    if cfg.pkgs then
      if cfg.pkgs.add then for _, p in ipairs(cfg.pkgs.add) do local url, branch = parse_url(p); download_pkg(url, branch,true) end end
      if cfg.pkgs.dl then for _, p in ipairs(cfg.pkgs.dl) do local url, branch = parse_url(p); download_pkg(url, branch,false) end end
    end
  elseif action == "self-up" then
    if is_global then
      local n = download_pkg("https://github.com/TBApknoob12MC/prefixell",nil,false)
      local pref_dir = pkgs_dir..sep..n
      local i_cmd = "cd '"..pref_dir.."' && lua install.lua"
      print("Running: "..i_cmd) ; if not os.execute(i_cmd) then print("something wrong happened\ncopy the command and run it manually") end
    else print("use with -g flag: ' prefixell pkg self-up -g '") end
  else
print([[
prefixell package manager
Usage: prefixell pkg [option] <action> <url|shorthand>
Options:
  -g or --global -> Use global directory (]] .. global_pkgs_dir .. [[)
  -p or --prevent-add -> prevent auto insert of package data into cfg.lc.lua in pkg add or pkg dl
Actions:
  add  <id>[@branch: optional] -> Download and build if it's a prefixell project
  dl   <id>[@branch: optional] -> Download only (no build)
  sync -> Download/build packages defined in cfg.lc.lua
  self-up -g -> update prefixell itself
Identifiers (<id>):
  gh:user/repo -> GitHub
  gl:user/repo -> GitLab
  cb:user/repo -> Codeberg
  https://url/repo -> Full Git URL
]])
  end
elseif arg[1] == "init" then
  print("Name of entry file (type main.lc for default): "); local entry = io.read()
  print("config:\nentry file: "..entry.."\nConfirm (y/n): "); local confirm = io.read():sub(1,1):lower() == "y"
  if not confirm then print("Cancelling init") os.exit(1) end
  local cfg = io.open("cfg.lc.lua","w")
  cfg:write([[
return {
  entry = "]]..(entry or "main.lc" )..[[",
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
