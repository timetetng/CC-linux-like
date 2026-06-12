-- cat.lua (or less.lua) - A syntax-highlighted pager for CC:Tweaked
local tArgs = { ... }
if #tArgs == 0 then
    print("Usage: cat <filename>")
    return
end

local sPath = shell.resolve(tArgs[1])
if not fs.exists(sPath) then
    printError("File not found: " .. sPath)
    return
end
if fs.isDir(sPath) then
    printError("Cannot read a directory.")
    return
end

local w, h = term.getSize()
local scrollX, scrollY = 0, 0
local tLines = {}
local tLineLexStates = {}
local bRunning = true

-- Colors
local isColour = term.isColour()

if isColour and term.setPaletteColor then
    term.setPaletteColor(colours.black, 0x1e1e2e)     -- Base (主背景)
    term.setPaletteColor(colours.white, 0xcdd6f4)     -- Text (主文本)
    term.setPaletteColor(colours.lightGrey, 0x181825) -- Mantle (状态栏背景，比主背景稍暗)
    term.setPaletteColor(colours.grey, 0xbac2de)      -- Subtext1 (状态栏次级文本，柔和不刺眼)
end

local textColour, bgColour, barBg, barText
if isColour then
    bgColour = colours.black
    textColour = colours.white
    barBg = colours.lightGrey
    barText = colours.grey
else
    bgColour = colours.black
    textColour = colours.white
    barBg = colours.white
    barText = colours.black
end

-- Syntax Lexer Loading
local tokens = require("cc.internal.syntax.parser").tokens
local lex_one = require("cc.internal.syntax.lexer").lex_one
local token_colours = {
    [tokens.STRING] = isColour and colours.red or textColour,
    [tokens.COMMENT] = isColour and colours.green or colours.lightGrey,
    [tokens.NUMBER] = isColour and colours.magenta or textColour,
}
local keywordColour = isColour and colours.yellow or textColour
local keywords = {
    "AND", "BREAK", "DO", "ELSE", "ELSEIF", "END", "FALSE", "FOR", "FUNCTION",
    "GOTO", "IF", "IN", "LOCAL", "NIL", "NOT", "OR", "REPEAT", "RETURN", "THEN",
    "TRUE", "UNTIL", "WHILE"
}
for _, kw in ipairs(keywords) do token_colours[tokens[kw]] = keywordColour end
for _, token in pairs(tokens) do
    if not token_colours[token] then token_colours[token] = textColour end
end
local lex_context = { line = function() end, report = function() end }

-- Load and Pre-lex file
local function loadFile(_sPath)
    local file = fs.open(_sPath, "r")
    local sLine = file.readLine()
    while sLine do
        table.insert(tLines, sLine)
        sLine = file.readLine()
    end
    file.close()

    if #tLines == 0 then table.insert(tLines, "") end

    -- Pre-calculate lex states for the whole file so random access scrolling highlights correctly
    local state = false
    for i, contents in ipairs(tLines) do
        tLineLexStates[i] = state
        local pos, token, _, finish, continuation = 1
        if state then
            token, finish, _, continuation = state[1](lex_context, contents, table.unpack(state, 2))
        else
            token, _, finish, _, continuation = lex_one(lex_context, contents, 1)
        end

        while token do
            pos = finish + 1
            if continuation then break end
            token, _, finish, _, continuation = lex_one(lex_context, contents, pos)
        end
        if continuation == nil then continuation = false end
        state = continuation or false
    end
end

local function drawText()
    term.setBackgroundColor(bgColour)
    for i = 1, h - 1 do
        local lineIdx = scrollY + i
        term.setCursorPos(1 - scrollX, i)
        term.clearLine()
        
        if lineIdx <= #tLines then
            local contents = tLines[lineIdx]
            local pos, token, _, finish, continuation = 1
            local lex_state = tLineLexStates[lineIdx]
            
            if lex_state then
                token, finish, _, continuation = lex_state[1](lex_context, contents, table.unpack(lex_state, 2))
            else
                token, _, finish, _, continuation = lex_one(lex_context, contents, 1)
            end

            local colour = textColour
            term.setTextColor(colour)

            while token do
                local new_colour = token_colours[token]
                if new_colour ~= colour then
                    term.setTextColor(new_colour)
                    colour = new_colour
                end
                term.write(contents:sub(pos, finish))
                pos = finish + 1
                if continuation then break end
                token, _, finish, _, continuation = lex_one(lex_context, contents, pos)
            end
            term.write(contents:sub(pos))
        end
    end
end

local function drawStatusBar()
    term.setCursorPos(1, h)
    term.setBackgroundColor(barBg)
    term.setTextColor(barText)
    term.clearLine()
    
    local percent = math.floor(((scrollY + h - 1) / math.max(1, #tLines)) * 100)
    if percent > 100 then percent = 100 end
    if scrollY == 0 and #tLines <= h - 1 then percent = 100 end

    local status = string.format(" %s | Lines: %d | %d%% | Press 'q' to quit", fs.getName(sPath), #tLines, percent)
    term.write(status)
end

local function draw()
    drawText()
    drawStatusBar()
end

-- Init
loadFile(sPath)
term.clear()
term.setCursorBlink(false)

draw()

-- Input Loop
local lastChar = ""
while bRunning do
    -- 同时捕获所有事件，不限制只拉取 "key"
    local event, p1, p2 = os.pullEvent()

    if event == "key" then
        local key = p1
        -- 保留原版方向键和功能键的支持
        if key == keys.up then
            scrollY = math.max(0, scrollY - 1)
        elseif key == keys.down then
            scrollY = math.min(math.max(0, #tLines - (h - 1)), scrollY + 1)
        elseif key == keys.pageUp then
            scrollY = math.max(0, scrollY - (h - 1))
        elseif key == keys.pageDown then
            scrollY = math.min(math.max(0, #tLines - (h - 1)), scrollY + (h - 1))
        elseif key == keys.left then
            scrollX = math.max(0, scrollX - 5)
        elseif key == keys.right then
            scrollX = scrollX + 5
        elseif key == keys.home then
            scrollY = 0
        elseif key == keys["end"] then
            scrollY = math.max(0, #tLines - (h - 1))
        end

    elseif event == "char" then
        local char = p1
        -- Vim 逻辑映射
        if char == "q" then
            bRunning = false
        elseif char == "j" then
            scrollY = math.min(math.max(0, #tLines - (h - 1)), scrollY + 1)
        elseif char == "k" then
            scrollY = math.max(0, scrollY - 1)
        elseif char == "h" then
            scrollX = math.max(0, scrollX - 5)
        elseif char == "l" then
            scrollX = scrollX + 5
        elseif char == "n" then
            -- n: 下一页
            scrollY = math.min(math.max(0, #tLines - (h - 1)), scrollY + (h - 1))
        elseif char == "N" then
            -- N: 上一页
            scrollY = math.max(0, scrollY - (h - 1))
        elseif char == "G" then
            -- G: 跳到末尾
            scrollY = math.max(0, #tLines - (h - 1))
        elseif char == "g" then
            -- gg: 跳到开头 (需要记录上一次按键)
            if lastChar == "g" then
                scrollY = 0
                lastChar = "" -- 触发后清空状态
            else
                lastChar = "g"
            end
        end

        -- 如果按下的不是 g，重置连续按键状态
        if char ~= "g" then
            lastChar = ""
        end
    end

    draw()
end
-- Cleanup
term.setBackgroundColor(colours.black)
term.setTextColor(colours.white)
term.clear()
term.setCursorPos(1, 1)
