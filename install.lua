--[[
Copyright 2026 TBApknoob12MC

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.]]
local function get_shell_configs()
  local home = os.getenv("HOME"); if not home then print("HOME env variable not set"); return end
  local shells = { {path = home .. "/.bashrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}, {path = home .. "/.zshrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}, {path = home .. "/.config/fish/config.fish", export = 'set -gx PATH $HOME/.local/bin $PATH'}, {path = home .. "/.profile", export = 'export PATH="$HOME/.local/bin:$PATH"'},{path = home .. "/.ashrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}}
  for _, shell in ipairs(shells) do
    local is_cfgd, rc_name = false, shell.path:match("([^/]+)$"); print("found: "..rc_name)
    local f = io.open(shell.path,"r")
    if f then 
      for line in io.lines(shell.path) do
        local trimmed = line:gsub("^%s+","")
        if not trimmed:find("^#") then if trimmed:find(".local/bin",1,true) then is_cfgd = true; break end end
      end
        if not is_cfgd then print(home.."/.local/bin not found in "..rc_name.." : Append '"..shell.export.."' to path? (y/n): "); if io.read():sub(1,1):lower() == "y" then local wf = io.open(shell.path, "a"); if wf then wf:write("\n" .. shell.export .. "\n"); wf:close(); print(rc_name.." updated") else print("failed to open "..rc_name.." for writing") end end else print(home.."/.local/bin possibly in path") end
    else
      print("Skipping "..rc_name.." (not found)")
    end
  end
end
local is_win = package.config:sub(1,1) == "\\"
local lua_bin = arg[-1]
local cwd = io.popen(is_win and "cd" or "pwd"):read("*l")
local src = cwd .. (is_win and "\\" or "/").."prefixell.lua"
if is_win then
  local user_prof = os.getenv("USERPROFILE")
  local dest = user_prof .. "\\prefixell.bat"
  local f = io.open(dest, "w"); if f then f:write("@echo off\nset \"PREFIXELL_ID="..(arg[1] or 0).."\"& set \"PREFIXELL_LUA="..lua_bin.."\"& \"" .. lua_bin .. "\" \"" .. src .. "\" %*") f:close() end
  local cur_path = os.getenv("PATH") or ""
  if not cur_path:find(user_prof, 1, true) then
    print("\nUSERPROFILE (" .. user_prof .. ") not in PATH.")
    print("Add it automatically? (y/n): ")
    if io.read():sub(1,1):lower() == "y" then
      local success = os.execute(string.format([[powershell -NoProfile -Command "$dir='%s'; $p=[Environment]::GetEnvironmentVariable('Path','User'); if ($p -split ';' -notcontains $dir) { $new = $p.TrimEnd(';') + ';' + $dir; [Environment]::SetEnvironmentVariable('Path', $new, 'User') }"]], user_prof))
      if success then
        print("Installed: " .. dest)
        print("PATH updated. RESTART your terminal to prefixell it")
      else print("Failed to update PATH via PowerShell. You shall add manually") end
    else
      print("Installed: " .. dest)
      print("You shall add " .. user_prof .. " to your PATH manually")
    end
  else
    print("Installed: " .. dest)
    print("You can now prefixell it ("..user_prof.." already in PATH)")
  end
else
  local bin_dir = os.getenv("HOME") .. "/.local/bin"
  os.execute("mkdir -p " .. bin_dir)
  local dest = bin_dir .. "/prefixell"
  local f = io.open(dest, "w")
  f:write("#!/bin/sh\nPREFIXELL_ID=\""..(arg[1] or 0).."\" PREFIXELL_LUA=\""..lua_bin .."\" ".. lua_bin .. " " .. src .. " \"$@\"")
  f:close()
  os.execute("chmod +x " .. dest)
  get_shell_configs()
  print("Installed: " .. dest .. "\nRestart your shell or source your config.")
end