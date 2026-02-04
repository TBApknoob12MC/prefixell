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
else
  print([[
prefixell cli:
  c <input.lc> <output.lua> -> compile source to lua
  r <optional_entry.lc>    -> read-eval-print-loop
  ]])
end