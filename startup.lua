-- startup.lua
local PATH = {
    "/bin",
    "/game"
}

local current_path = shell.path()

local path_set = {}
for segment in string.gmatch(current_path, "[^:]+") do
    path_set[segment] = true
end

for _, path in ipairs(PATH) do
    if not path_set[path] then
        current_path = current_path .. ":" .. path
        path_set[path] = true
    end
end

shell.setPath(current_path)

-- 别名设置
shell.setAlias("nvim", "vim")
shell.setAlias("fastfetch", "neofetch")
shell.setAlias("y", "yazi")
shell.setAlias("rg", "grep")
shell.setAlias("falling", "/game/falling.lua")

if fs.exists("/bin/boot.lua") then
    shell.run("/bin/boot.lua")
end

term.clear()
term.setCursorPos(1, 1)

-- 启动我们的自定义美化 Shell
while true do
    shell.run("/bin/crash.lua")
end
