-- 主题加载
if fs.exists("/config/theme.lua") then
    local theme = require("..config.theme") 
    theme.apply()
end
-- 获取用户名
local username = settings.get("user.name")
-- 开机动画
local function playComplexBootAnimation()
    -- 获取屏幕尺寸
    local w, h = term.getSize()
    term.setBackgroundColour(colors.black)
    term.clear()

  -- 1. 定义大屏专属的 ASCII Logo (纯标准字符，完全兼容 CC:T)
    local logo = {
        "   ____ ____      _    _____ _____   ___  ____   ",
        "  / ___|  _ \\    / \\  |  ___|_   _| / _ \\/ ___|  ",
        " | |   | |_) |  / _ \\ | |_    | |  | | | \\___ \\  ",
        " | |___|  _ <  / ___ \\|  _|   | |  | |_| |___) | ",
        "  \\____|_| \\_\\/_/   \\_\\_|     |_|   \\___/|____/  "
    }

    local logoWidth = #logo[1]
    local logoHeight = #logo
    local startX = math.floor((w - logoWidth) / 2) + 1
    local startY = math.floor(h / 2) - 6 -- 整体稍微向上偏移，给底部留空间

    -- 2. 动态绘制 Logo (从上到下逐行扫描，伴随主题色渐变)
    for i, line in ipairs(logo) do
        term.setCursorPos(startX, startY + i - 1)
        
        -- 使用主题色进行垂直渐变
        if i < 3 then 
            term.setTextColour(colors.purple)    -- Mauve
        elseif i < 5 then 
            term.setTextColour(colors.lightBlue) -- Blue
        else 
            term.setTextColour(colors.green)     -- Teal
        end

        -- 逐字符打印，产生极其快速的“渲染”残影效果
        for j = 1, #line do
            term.setCursorPos(startX + j - 1, startY + i - 1)
            write(line:sub(j, j))
            -- 为了让动画够快且流畅，每 3 个字符才 sleep 一次
            if j % 24 == 0 then os.sleep(0.01) end
        end
    end

    os.sleep(0.2)

    -- 3. 左下角模拟系统内核加载日志
    local logs = {
        "Initializing CraftOS kernel...",
        "Mounting virtual file systems... [OK]",
        "Loading NodeNet RPC drivers... [OK]",
        "Calibrating peripheral interfaces...",
        "Bypassing security protocols... [OK]",
        "Starting daemon processes... [OK]"
    }

    term.setTextColour(colors.lightGray) -- Surface2 颜色
    for i, logStr in ipairs(logs) do
        -- 固定在左下角区域打印
        term.setCursorPos(3, h - #logs + i - 1)
        write(logStr)
        os.sleep(math.random(5, 15) / 100) -- 随机加载时间，更真实
    end

    -- 4. 居中流体进度条伴随百分比显示
    local barWidth = math.min(50, w - 20) -- 进度条最大宽度为50
    local barX = math.floor((w - barWidth) / 2) + 1
    local barY = startY + logoHeight + 2

    -- 绘制进度条外框/底色
    term.setCursorPos(barX, barY)
    term.setTextColour(colors.gray) -- Surface0 颜色
    write(string.rep("-", barWidth))

    -- 填充进度条
    for i = 1, barWidth do
        term.setCursorPos(barX + i - 1, barY)
        
        -- 进度条颜色随进度变化
        if i / barWidth < 0.4 then
            term.setTextColour(colors.cyan)   -- Sky
        elseif i / barWidth < 0.8 then
            term.setTextColour(colors.blue)   -- Lavender
        else
            term.setTextColour(colors.lime)   -- Green
        end
        
        write("=>") -- 使用实心方块填充
        
        -- 动态更新右侧的百分比
        local percent = math.floor((i / barWidth) * 100)
        term.setCursorPos(barX + barWidth + 2, barY)
        term.setTextColour(colors.white) -- Text 颜色
        write(string.format("%3d%%", percent))

        if i%2==0 then os.sleep(math.random(1, 4) / 100)
        end
   end

    -- 5. 加载完成后的闪烁提示文字
    os.sleep(0.1)
    local readyText = string.format("> Hello, %s! <",username)
    local rx = math.floor((w - #readyText) / 2) + 1
    
    for i = 1, 3 do
        term.setCursorPos(rx, barY + 2)
        if i % 2 == 1 then
            term.setTextColour(colors.lime)
            write(readyText)
        else
            -- 用黑色覆盖实现闪烁效果
            term.setTextColour(colors.black)
            write(string.rep(" ", #readyText))
        end
        os.sleep(1)
    end

    -- 6. 优雅地退出动画，重置屏幕状态
    term.setBackgroundColour(colors.black)
    term.setTextColour(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

-- 容错处理：确保只有高级电脑/显示器才会运行此动画
if term.isColor() then
    playComplexBootAnimation()
end

