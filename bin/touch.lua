-- touch.lua
local args = { ... }

if #args < 1 then
    printError("Usage: touch <file>")
    return
end

local filepath = shell.resolve(args[1])

-- 在真实的 Linux 中 touch 会更新文件修改时间
-- CC:T 中如果没有这个文件，我们就创建一个空的
if not fs.exists(filepath) then
    local file = fs.open(filepath, "w")
    if file then
        file.close()
    else
        printError("touch: cannot create '" .. args[1] .. "'")
    end
end
