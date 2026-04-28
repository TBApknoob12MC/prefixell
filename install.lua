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