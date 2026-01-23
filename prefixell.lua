local prefixell = require('compiler')
local comp = prefixell:new()

local function run_lua(code)
  if not code then return end
  local chunk, err = load(code)
  if chunk then
    local status, rerr = pcall(chunk)
    if not status then print("runtime error: " .. tostring(rerr)) end
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
  local dbg = false
  load(prefixell.init_code)()
  if arg[2] then
    local inp, err = io.open(arg[2], 'r')
    if not inp then error("error opening source file: " .. err) end
    local lua_code, comp_err = comp:compile(inp:read('*a'))
    inp:close()
    if comp_err then print(comp_err) else run_lua(lua_code) end
  end
  while true do
    io.write("> ")
    local repl_inp = io.read()
    if not repl_inp or repl_inp == ":q" then break end
    if repl_inp == ":d" then
      dbg = not dbg
    elseif repl_inp ~= "" then
      local lua_code, comp_err = comp:compile(repl_inp)
      if comp_err then
        print(comp_err)
      else
        if dbg then print(lua_code) end
        run_lua(lua_code)
      end
    end
  end
else
  print([[
prefixell cli:
  c <input.lc> <output.lua> -> compile source to lua
  r <optional_entry.lc>    -> read-eval-print-loop
  ]])
end