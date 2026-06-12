-- 1. 加载并应用你的主题
local theme = require("..config.theme")
theme.apply()

local ws_url = "ws://localhost:12789"
local username = "xingjian"
local hostname = "EQ14"

-- 设置初始背景和文本颜色，并清屏
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)

print("Connecting to " .. ws_url .. "...")

local ws, err = http.websocket(ws_url)
if not ws then
    term.setTextColor(colors.red)
    printError("连接失败: " .. tostring(err))
    return
end

term.setTextColor(colors.green)
print("=== Host Connected ===")
term.setTextColor(colors.gray)
print("input 'exit_ssh' to exit")
print("------------------------------")
sleep(1)
term.clear()
term.setCursorPos(1, 1)

-- [核心功能] 路径格式化：只保留父级和当前目录
local function formatPath(path)
    -- 1. 替换家目录为 ~
    path = path:gsub("^/home/" .. username, "~")
        
    -- 2. 处理根目录或已经是 ~ 的情况
    if path == "/" or path == "~" then return path end
        
    -- 3. 按 / 分割路径
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
        
    -- 4. 只有一级目录 (例如 /etc 或 ~/Downloads)
    if #parts == 1 then
        return (path:sub(1,1) == "/" and "/" or "") .. parts[1]
    end
        
    -- 5. 提取最后两级目录
    local last = parts[#parts]
    local parent = parts[#parts - 1]
        
    if parent == "~" then
        return "~/" .. last
    end
        
    return parent .. "/" .. last
end

-- [新增] 智能打印函数：根据换行符数量决定是否分页
local function smartPrint(text)
    if text == "" then return end
    
    -- 统计文本中的换行符数量
    local _, newlines = text:gsub("\n", "")
    
    -- 根据阈值（30行）决定打印方式
    if newlines >= 15 then
        textutils.pagedPrint(text)
    else
        write(text)
    end
end

local current_path = "~"
local cmd_history = {} -- 用于存储命令历史的表

-- 建立连接后，先偷偷发个 pwd 获取初始真实路径
ws.send("cd /home/xingjian")
ws.send("pwd")
while true do
    local msg = ws.receive(0.1)
    if msg then 
        local p = msg:gsub("[\r\n]", "")
        if p ~= "" then current_path = formatPath(p) end
    else 
        break 
    end
end

-- 核心交互循环
while true do
    -- 1. 打印带路径的彩色提示符 (完美复刻 Linux 风格)
    term.setTextColor(colors.lime)
    write(username .. "@" .. hostname)
    term.setTextColor(colors.white)
    write(":")
    term.setTextColor(colors.blue)
    write(current_path)
    term.setTextColor(colors.white)
    write("$ ")
        
    -- 2. 读取输入 (传入 cmd_history)
    term.setTextColor(colors.lightBlue)
    local input = read(nil, cmd_history)
        
    if input == "exit_ssh" then
        ws.close()
        break
    elseif input == "clear" then
        -- 拦截 clear 命令，在本地终端执行清屏并将光标复位
        term.clear()
        term.setCursorPos(1, 1)
    elseif not input:match("^%s*$") then
        
        -- 将非空输入加入历史记录表，并限制最大保留 100 条
        table.insert(cmd_history, input)
        if #cmd_history > 100 then
            table.remove(cmd_history, 1)
        end
                
        -- [黑科技] 在用户的命令后面偷偷拼接 echo "$(pwd)"，并用 __PWD__ 作为魔法标记
        local magic_cmd = input .. "; echo \"__PWD__$(pwd)\""
        ws.send(magic_cmd)
                
        term.setTextColor(colors.white)
        local output_buffer = ""
                
        -- 3. 接收输出 (修复：增加流式输出拦截，防止无限死循环)
        while true do
            local msg = ws.receive(0.1)
            if msg then
                output_buffer = output_buffer .. msg
                
                -- 实时尝试在当前缓冲区寻找魔法标记
                local pwd_start = output_buffer:find("__PWD__")
                if pwd_start then
                    -- 提取前面的真正输出并打印
                    local display_output = output_buffer:sub(1, pwd_start - 1)
                    smartPrint(display_output)
                                
                    -- 提取 __PWD__ 后的路径字符串，更新 current_path
                    local raw_path = output_buffer:sub(pwd_start + 7)
                    raw_path = raw_path:gsub("[\r\n]", "") -- 清除换行符
                    if raw_path ~= "" then
                        current_path = formatPath(raw_path)
                    end
                    break
                else
                    -- [修复核心] 如果是一直刷新的长日志，不等超时，一边收一边打
                    local _, newlines = output_buffer:gsub("\n", "")
                    if newlines >= 30 or #output_buffer > 2048 then
                        -- 把前面绝大部分内容打印出来，留下最后 15 个字符防截断 __PWD__
                        local chunk = output_buffer:sub(1, -16)
                        smartPrint(chunk)
                        -- 将剩下的字符重新放回 buffer
                        output_buffer = output_buffer:sub(-15)
                    end
                end
            else
                -- 超时说明一小段输出结束（或者碰到了交互式等待）
                -- 把剩下的内容打印出来，并跳出接收循环以允许用户下一次输入
                if output_buffer ~= "" then
                    smartPrint(output_buffer)
                end
                break
            end
        end
    end
end

term.setTextColor(colors.yellow)
print("\n=== SSH disconnected ===")
term.setTextColor(colors.white)
