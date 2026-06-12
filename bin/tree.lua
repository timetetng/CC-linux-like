-- tree.lua
local args = { ... }
local targetDir = args[1] or "."
local startPath = shell.resolve(targetDir)

if not fs.exists(startPath) then
    printError("tree: " .. targetDir .. ": No such file or directory")
    return
end

-- 递归打印函数
local function printTree(path, prefix)
    if not fs.isDir(path) then return end
    
    local files = fs.list(path)
    table.sort(files) -- 让输出按字母顺序排列，更美观
    
    for i, file in ipairs(files) do
        local isLast = (i == #files)
        -- 判断是否是该层级的最后一个文件，决定使用哪个分支符号
        local pointer = isLast and "└── " or "├── "
        local fullPath = fs.combine(path, file)
        
        print(prefix .. pointer .. file)
        
        -- 如果是文件夹，则进入递归
        if fs.isDir(fullPath) then
            -- 最后一项的子目录不需要垂直线 "│"
            local extension = isLast and "    " or "│   "
            printTree(fullPath, prefix .. extension)
        end
    end
end

print(targetDir)
printTree(startPath, "")
