--[[
Copyright 2026 TBApknoob12MC

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.]]
local function get_shell_configs()
  local home = os.getenv("HOME")
  local shells = { {path = home .. "/.bashrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}, {path = home .. "/.zshrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}, {path = home .. "/.config/fish/config.fish", export = 'set -gx PATH $HOME/.local/bin $PATH'}, {path = home .. "/.profile", export = 'export PATH="$HOME/.local/bin:$PATH"'},{path = home .. "/.ashrc", export = 'export PATH="$HOME/.local/bin:$PATH"'}}
  for _, shell in ipairs(shells) do
    local f = io.open(shell.path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      if not content:find(".local/bin") then local wf = io.open(shell.path, "a"); wf:write("\n" .. shell.export .. "\n"); wf:close() end
    end
  end
end
local is_win = package.config:sub(1,1) == "\\"
local lua_bin = arg[-1]
local cwd = io.popen(is_win and "cd" or "pwd"):read("*l")
local src = cwd .. "/prefixell.lua"
if is_win then
  local dest = os.getenv("USERPROFILE") .. "\\prefixell.bat"
  local f = io.open(dest, "w")
  f:write("@echo off\n\"" .. lua_bin .. "\" \"" .. src .. "\" %*")
  f:close()
  print("Installed: " .. dest)
else
  local bin_dir = os.getenv("HOME") .. "/.local/bin"
  os.execute("mkdir -p " .. bin_dir)
  local dest = bin_dir .. "/prefixell"
  local f = io.open(dest, "w")
  f:write("#!/bin/sh\n" .. lua_bin .. " " .. src .. " \"$@\"")
  f:close()
  os.execute("chmod +x " .. dest)
  get_shell_configs()
  print("Installed: " .. dest .. "\nRestart your shell or source your config.")
end