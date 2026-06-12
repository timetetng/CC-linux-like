-- pwd.lua
local dir = shell.dir()

if dir == "" then
    print("/")
else
    print("/" .. dir)
end
