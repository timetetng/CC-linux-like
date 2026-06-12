-- grep.lua
local args = { ... }

-- 检查参数数量
if #args < 2 then
    printError("Usage: grep <pattern> <file>")
    return
end

local pattern = args[1]
local filepath = shell.resolve(args[2])

-- 验证文件有效性
if not fs.exists(filepath) then
    printError("grep: " .. args[2] .. ": No such file or directory")
    return
elseif fs.isDir(filepath) then
    printError("grep: " .. args[2] .. ": Is a directory")
    return
end

-- 打开并读取文件
local file = fs.open(filepath, "r")
if not file then
    printError("grep: Cannot open file")
    return
end

while true do
    local line = file.readLine()
    if not line then break end -- 读到文件末尾退出
    
    -- 如果当前行包含匹配的模式，则打印该行
    if string.find(line, pattern) then
        print(line)
    end
end

file.close()
