-- CC-Vim (vim) - A Vim-like editor for CC:Tweaked
-- Based on original CC:T edit.lua

local tArgs = { ... }
if #tArgs == 0 then
    print("Usage: cvim <path>")
    return
end

local sPath = shell.resolve(tArgs[1])
local bReadOnly = fs.isReadOnly(sPath)
if fs.exists(sPath) and fs.isDir(sPath) then
    print("Cannot edit a directory.")
    return
end

if not fs.exists(sPath) and not string.find(sPath, "%.") then
    local sExtension = settings.get("edit.default_extension")
    if sExtension ~= "" and type(sExtension) == "string" then
        sPath = sPath .. "." .. sExtension
    end
end

local x, y = 1, 1
local w, h = term.getSize()
local scrollX, scrollY = 0, 0
local tLines, tLineLexStates = {}, {}
local bRunning = true

-- Vim States
local mode = "NORMAL" -- NORMAL, INSERT, VISUAL, COMMAND
local cmdBuffer = ""
local clipboard = {}
local visualStartY = 1
local lastNormalChar = ""

-- Colours
local isColour = term.isColour()

if isColour and term.setPaletteColor then
    term.setPaletteColor(colours.black, 0x1e1e2e)  -- Base (主背景)
    term.setPaletteColor(colours.white, 0xcdd6f4)  -- Text (主文本)
    term.setPaletteColor(colours.yellow, 0xf9e2af) -- Yellow (高亮和关键字)
    term.setPaletteColor(colours.red, 0xf38ba8)    -- Red (错误信息)
    term.setPaletteColor(colours.grey, 0x181825)   -- Surface2 (选中/可视模式背景)
    
    -- 状态栏颜色
    term.setPaletteColor(colours.blue, 0x89b4fa)   -- Blue (NORMAL 模式)
    term.setPaletteColor(colours.green, 0xa6e3a1)  -- Green (INSERT 模式)
    term.setPaletteColor(colours.purple, 0xcba6f7) -- Mauve/Purple (VISUAL 模式)
end

local highlightColour, keywordColour, textColour, bgColour, errorColour, visualColour
if isColour then
    bgColour = colours.black
    textColour = colours.white
    highlightColour = colours.yellow
    keywordColour = colours.yellow
    errorColour = colours.red
    visualColour = colours.grey
else
    bgColour = colours.black
    textColour = colours.white
    highlightColour = colours.white
    keywordColour = colours.white
    errorColour = colours.white
    visualColour = colours.lightGrey
end
local status_text = ""

local function load(_sPath)
    tLines = {}
    if fs.exists(_sPath) then
        local file = io.open(_sPath, "r")
        local sLine = file:read()
        while sLine do
            table.insert(tLines, sLine)
            table.insert(tLineLexStates, false)
            sLine = file:read()
        end
        file:close()
    end
    if #tLines == 0 then
        table.insert(tLines, "")
        table.insert(tLineLexStates, false)
    end
end

local function save(_sPath)
    local sDir = _sPath:sub(1, _sPath:len() - fs.getName(_sPath):len())
    if not fs.exists(sDir) then fs.makeDir(sDir) end
    local file, err = fs.open(_sPath, "w")
    if file then
        for _, sLine in ipairs(tLines) do file.write(sLine .. "\n") end
        file.close()
        return true
    end
    return false, err
end

-- Syntax Lexer loading
local tokens = require("cc.internal.syntax.parser").tokens
local lex_one = require("cc.internal.syntax.lexer").lex_one
local token_colours = {
    [tokens.STRING] = isColour and colours.red or textColour,
    [tokens.COMMENT] = isColour and colours.green or colours.lightGrey,
    [tokens.NUMBER] = isColour and colours.magenta or textColour,
    [tokens.AND] = keywordColour, [tokens.BREAK] = keywordColour, [tokens.DO] = keywordColour,
    [tokens.ELSE] = keywordColour, [tokens.ELSEIF] = keywordColour, [tokens.END] = keywordColour,
    [tokens.FALSE] = keywordColour, [tokens.FOR] = keywordColour, [tokens.FUNCTION] = keywordColour,
    [tokens.GOTO] = keywordColour, [tokens.IF] = keywordColour, [tokens.IN] = keywordColour,
    [tokens.LOCAL] = keywordColour, [tokens.NIL] = keywordColour, [tokens.NOT] = keywordColour,
    [tokens.OR] = keywordColour, [tokens.REPEAT] = keywordColour, [tokens.RETURN] = keywordColour,
    [tokens.THEN] = keywordColour, [tokens.TRUE] = keywordColour, [tokens.UNTIL] = keywordColour,
    [tokens.WHILE] = keywordColour,
}
for _, token in pairs(tokens) do
    if not token_colours[token] then token_colours[token] = textColour end
end
local lex_context = { line = function() end, report = function() end }

local tCompletions, nCompletion
local tCompleteEnv = _ENV

local function complete(sLine)
    if settings.get("edit.autocomplete") then
        local nStartPos = string.find(sLine, "[a-zA-Z0-9_%.:]+$")
        if nStartPos then sLine = string.sub(sLine, nStartPos) end
        if #sLine > 0 then return textutils.complete(sLine, tCompleteEnv) end
    end
    return nil
end

local function recomplete()
    local sLine = tLines[y]
    if mode == "INSERT" and not bReadOnly and x == #sLine + 1 then
        tCompletions = complete(sLine)
        if tCompletions and #tCompletions > 0 then
            nCompletion = 1
        else
            nCompletion = nil
        end
    else
        tCompletions = nil
        nCompletion = nil
    end
end

local function writeCompletion()
    if nCompletion then
        local sCompletion = tCompletions[nCompletion]
        term.setTextColor(colours.white)
        term.setBackgroundColor(colours.grey)
        term.write(sCompletion)
        term.setTextColor(textColour)
        term.setBackgroundColor(bgColour)
    end
end

local function shallowEqual(x, y)
    if x == y then return true end
    if type(x) ~= "table" or type(y) ~= "table" then return false end
    if #x ~= #y then return false end
    for i = 1, #x do if x[i] ~= y[i] then return false end end
    return true
end

local function redrawLines(line, endLine)
    if not endLine then endLine = line end
    local colour = term.getTextColour()
    local changed = false

    local vStart = math.min(y, visualStartY)
    local vEnd = math.max(y, visualStartY)

    while (changed or line <= endLine) and line - scrollY < h do
        term.setCursorPos(1 - scrollX, line - scrollY)
        term.clearLine()
        local contents = tLines[line]
        if not contents then break end

        -- Visual Mode background
        local isVisualLine = (mode == "VISUAL" and line >= vStart and line <= vEnd)
        if isVisualLine then term.setBackgroundColor(visualColour) else term.setBackgroundColor(bgColour) end

        local pos, token, _, finish, continuation = 1
        local lex_state = tLineLexStates[line]
        if lex_state then
            token, finish, _, continuation = lex_state[1](lex_context, contents, table.unpack(lex_state, 2))
        else
            token, _, finish, _, continuation = lex_one(lex_context, contents, 1)
        end

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

        if line == y and x == #contents + 1 and mode == "INSERT" then
            writeCompletion()
            colour = term.getTextColour()
        end

        line = line + 1
        if continuation == nil then continuation = false end
        if tLineLexStates[line] ~= nil and not shallowEqual(tLineLexStates[line], continuation) then
            tLineLexStates[line] = continuation or false
            changed = true
        else
            changed = false
        end
    end
    term.setTextColor(colours.white)
    term.setBackgroundColor(bgColour)
    term.setCursorPos(x - scrollX, y - scrollY)
end

local function redrawText()
    redrawLines(scrollY + 1, scrollY + h - 1)
end

local function redrawStatusBar()
    term.setCursorPos(1, h)
    
    -- 状态栏整体的默认背景色和前景色
    local barBg = isColour and colours.grey or colours.black
    local barFg = colours.white

    -- 先用默认底色清空并铺满整行
    term.setBackgroundColor(barBg)
    term.setTextColor(barFg)
    term.clearLine()
    
    -- 根据当前模式分配【模式标签】的颜色
    local modeBg = barBg
    local modeFg = barFg

    if mode == "NORMAL" then
        modeBg = colours.blue
        modeFg = colours.black
    elseif mode == "INSERT" then
        modeBg = colours.green
        modeFg = colours.black
    elseif mode == "VISUAL" then
        modeBg = colours.purple
        modeFg = colours.black
    elseif mode == "COMMAND" then
        modeBg = colours.yellow
        modeFg = colours.black
    end

    if not isColour then
        modeBg = colours.black
        modeFg = colours.white
    end

    -- 1. 单独绘制带有彩色背景的模式文字
    term.setBackgroundColor(modeBg)
    term.setTextColor(modeFg)
    local modeText = "-- " .. mode .. " -- "
    term.write(modeText)
    
    -- 2. 恢复状态栏默认底色，绘制后续的命令或提示信息
    term.setBackgroundColor(barBg)
    term.setTextColor(barFg)
    
    local extraText = ""
    if mode == "COMMAND" then
        extraText = ":" .. cmdBuffer
    elseif mode == "NORMAL" and status_text ~= "" then
        extraText = " " .. status_text
    end
    term.write(extraText)
    
    -- 3. 绘制屏幕最右侧的文件名和光标位置信息
    -- 提取文件名展示，顺便判断一下如果文件是只读的，给个 [RO] 提示
    local displayFile = sPath
    if bReadOnly then displayFile = displayFile .. " [RO]" end 
    
    -- 拼装右侧信息，例如: "startup.lua | 12,5"
    local rightInfo = displayFile .. " | " .. y .. "," .. x
    
    -- 定位到屏幕最右边写入
    term.setCursorPos(w - #rightInfo, h)
    term.write(rightInfo)
    
    -- 4. 渲染完毕后，重置回编辑主区域的背景色，并把光标挪回文本编辑处
    term.setBackgroundColor(bgColour)
    term.setTextColor(textColour)
    term.setCursorPos(x - scrollX, y - scrollY)
end

local function setCursor(newX, newY)
    local _, oldY = x, y
    x = math.max(1, newX)
    y = math.max(1, math.min(#tLines, newY))
    
    local limit = mode == "INSERT" and (#tLines[y] + 1) or math.max(1, #tLines[y])
    x = math.min(x, limit)

    local screenX = x - scrollX
    local screenY = y - scrollY
    local bRedraw = false

    if screenX < 1 then scrollX = x - 1; screenX = 1; bRedraw = true
    elseif screenX > w then scrollX = x - w; screenX = w; bRedraw = true end

    if screenY < 1 then scrollY = y - 1; screenY = 1; bRedraw = true
    elseif screenY > h - 2 then scrollY = y - (h - 2); screenY = h - 2; bRedraw = true end

    recomplete()
    if bRedraw or mode == "VISUAL" then
        redrawText()
    elseif y ~= oldY then
        redrawLines(math.min(y, oldY), math.max(y, oldY))
    else
        redrawLines(y)
    end
    redrawStatusBar()
end

local function acceptCompletion()
    if nCompletion then
        local sCompletion = tCompletions[nCompletion]
        tLines[y] = tLines[y] .. sCompletion
        setCursor(x + #sCompletion, y)
    end
end

local function execCommand()
    if cmdBuffer == "w" then
        if save(sPath) then status_text = '"'..sPath..'" written' else status_text = 'Error saving' end
    elseif cmdBuffer == "q" then
        bRunning = false
    elseif cmdBuffer == "wq" or cmdBuffer == "x" then
        save(sPath)
        bRunning = false
    else
        status_text = "Not an editor command: " .. cmdBuffer
    end
end

-- Input Handlers
local function handleNormal(key, char)
    if char == "i" then mode = "INSERT"
    elseif char == "a" then mode = "INSERT"; setCursor(x + 1, y)
    elseif char == "A" then mode = "INSERT"; setCursor(#tLines[y] + 1, y)
    elseif char == "I" then mode = "INSERT"; setCursor(1, y)
    elseif char == "o" then
        table.insert(tLines, y + 1, "")
        table.insert(tLineLexStates, y + 1, false)
        mode = "INSERT"
        setCursor(1, y + 1)
        redrawText()
    elseif char == "O" then
        table.insert(tLines, y, "")
        table.insert(tLineLexStates, y, false)
        mode = "INSERT"
        setCursor(1, y)
        redrawText()
    elseif char == "V" or char == "v" then
        mode = "VISUAL"
        visualStartY = y
    elseif char == "h" or key == keys.left then setCursor(x - 1, y)
    elseif char == "j" or key == keys.down then setCursor(x, y + 1)
    elseif char == "k" or key == keys.up then setCursor(x, y - 1)
    elseif char == "l" or key == keys.right then setCursor(x + 1, y)
    elseif char == "0" then setCursor(1, y)
    elseif char == "$" then setCursor(#tLines[y], y)
    elseif char == "g" then
        if lastNormalChar == "g" then setCursor(x, 1); lastNormalChar = ""
        else lastNormalChar = "g"; return end
    elseif char == "G" then setCursor(x, #tLines)
    elseif char == "x" then
        if #tLines[y] > 0 then
            tLines[y] = string.sub(tLines[y], 1, x - 1) .. string.sub(tLines[y], x + 1)
            redrawLines(y)
            setCursor(x, y)
        end
    elseif char == "d" then
        if lastNormalChar == "d" then
            clipboard = {tLines[y]}
            table.remove(tLines, y)
            table.remove(tLineLexStates, y)
            if #tLines == 0 then table.insert(tLines, ""); table.insert(tLineLexStates, false) end
            setCursor(x, math.min(y, #tLines))
            redrawText()
            lastNormalChar = ""
        else lastNormalChar = "d"; return end
    elseif char == "y" then
        if lastNormalChar == "y" then
            clipboard = {tLines[y]}
            status_text = "1 line yanked"
            lastNormalChar = ""
        else lastNormalChar = "y"; return end
    elseif char == "p" then
        if #clipboard > 0 then
            for i=1, #clipboard do
                table.insert(tLines, y + i, clipboard[i])
                table.insert(tLineLexStates, y + i, false)
            end
            setCursor(x, y + #clipboard)
            redrawText()
        end
    elseif char == ":" then
        mode = "COMMAND"
        cmdBuffer = ""
    end
if char then
        if char ~= "d" and char ~= "y" and char ~= "g" then 
            lastNormalChar = "" 
        end
    else
        -- 如果是 key 事件，只有按下方向键才打断组合键
        if key == keys.left or key == keys.right or key == keys.up or key == keys.down then
            lastNormalChar = ""
        end
    end
    
    redrawStatusBar()
end

local function handleInsert(key, char)
    if key == keys.tab then
        mode = "NORMAL"
        setCursor(x - 1, y)
    elseif key == keys.leftCtrl or key == keys.rightCtrl or (key == keys.right and nCompletion) then
        if nCompletion then acceptCompletion() end
    elseif key == keys.up then
        if nCompletion then
            nCompletion = nCompletion - 1
            if nCompletion < 1 then nCompletion = #tCompletions end
            redrawLines(y)
        else setCursor(x, y - 1) end
    elseif key == keys.down then
        if nCompletion then
            nCompletion = nCompletion + 1
            if nCompletion > #tCompletions then nCompletion = 1 end
            redrawLines(y)
        else setCursor(x, y + 1) end
    elseif key == keys.left then setCursor(x - 1, y)
    elseif key == keys.right then setCursor(x + 1, y)
    elseif key == keys.backspace then
        if x > 1 then
            local sLine = tLines[y]
            local prevChar = string.sub(sLine, x - 1, x - 1)
            local currChar = string.sub(sLine, x, x)
            
            -- 判断是否是成对的括号/引号，如果是，一起删除
            local isPair = (prevChar == "(" and currChar == ")") or
                           (prevChar == "[" and currChar == "]") or
                           (prevChar == "{" and currChar == "}") or
                           (prevChar == "'" and currChar == "'") or
                           (prevChar == '"' and currChar == '"')
            
            if isPair then
                tLines[y] = string.sub(sLine, 1, x - 2) .. string.sub(sLine, x + 1)
                setCursor(x - 1, y)
            else
                tLines[y] = string.sub(sLine, 1, x - 2) .. string.sub(sLine, x)
                setCursor(x - 1, y)
            end
        elseif y > 1 then
            local prevLen = #tLines[y - 1]
            tLines[y - 1] = tLines[y - 1] .. tLines[y]
            table.remove(tLines, y)
            table.remove(tLineLexStates, y)
            setCursor(prevLen + 1, y - 1)
            redrawText()
        end
    elseif key == keys.enter or key == keys.numPadEnter then
        local sLine = tLines[y]
        local _, spaces = string.find(sLine, "^[ ]+")
        if not spaces then spaces = 0 end
        tLines[y] = string.sub(sLine, 1, x - 1)
        table.insert(tLines, y + 1, string.rep(' ', spaces) .. string.sub(sLine, x))
        table.insert(tLineLexStates, y + 1, false)
        setCursor(spaces + 1, y + 1)
        redrawText()
    elseif char then
        local pairs = { ["("] = ")", ["["] = "]", ["{"] = "}", ["'"] = "'", ['"'] = '"' }
        local closingPairs = { [")"] = true, ["]"] = true, ["}"] = true, ["'"] = true, ['"'] = true }
        local sLine = tLines[y]
        local nextChar = string.sub(sLine, x, x)

        -- 如果输入的是闭合字符，且光标后的字符刚好是这个闭合字符，则跳过（不重复插入）
        if closingPairs[char] and nextChar == char then
            setCursor(x + 1, y)
        elseif pairs[char] then
            -- 自动补全成对符号
            tLines[y] = string.sub(sLine, 1, x - 1) .. char .. pairs[char] .. string.sub(sLine, x)
            setCursor(x + 1, y)
        else
            -- 正常输入
            tLines[y] = string.sub(sLine, 1, x - 1) .. char .. string.sub(sLine, x)
            setCursor(x + 1, y)
        end
    end
end
local function handleVisual(key, char)
    if key == keys.tab then
        mode = "NORMAL"
        redrawText()
    elseif char == "h" or key == keys.left then setCursor(x - 1, y)
    elseif char == "j" or key == keys.down then setCursor(x, y + 1)
    elseif char == "k" or key == keys.up then setCursor(x, y - 1)
    elseif char == "l" or key == keys.right then setCursor(x + 1, y)
    elseif char == "y" then
        local vStart, vEnd = math.min(y, visualStartY), math.max(y, visualStartY)
        clipboard = {}
        for i = vStart, vEnd do table.insert(clipboard, tLines[i]) end
        mode = "NORMAL"
        status_text = #clipboard .. " lines yanked"
        redrawText()
    elseif char == "d" or char == "x" or key == keys.backspace then
        local vStart, vEnd = math.min(y, visualStartY), math.max(y, visualStartY)
        clipboard = {}
        for i = vStart, vEnd do
            table.insert(clipboard, tLines[i])
        end
        for i = 1, (vEnd - vStart + 1) do
            table.remove(tLines, vStart)
            table.remove(tLineLexStates, vStart)
        end
        if #tLines == 0 then table.insert(tLines, ""); table.insert(tLineLexStates, false) end
        mode = "NORMAL"
        setCursor(x, math.min(vStart, #tLines))
        redrawText()
    end
end

local function handleCommand(key, char)
    if key == keys.tab or key == keys.backspace and #cmdBuffer == 0 then
        mode = "NORMAL"
    elseif key == keys.backspace then
        cmdBuffer = string.sub(cmdBuffer, 1, -2)
    elseif key == keys.enter or key == keys.numPadEnter then
        mode = "NORMAL"
        execCommand()
    elseif char then
        cmdBuffer = cmdBuffer .. char
    end
    redrawStatusBar()
end

-- Setup
load(sPath)
term.setBackgroundColour(bgColour)
term.clear()
redrawText()
setCursor(x, y)
term.setCursorBlink(true)

-- Main Loop
while bRunning do
    local event = table.pack(os.pullEvent())
    if event[1] == "key" or event[1] == "char" then
        local key = event[1] == "key" and event[2] or nil
        local char = event[1] == "char" and event[2] or nil
        
        status_text = "" -- clear status on keystroke
        if mode == "NORMAL" then handleNormal(key, char)
        elseif mode == "INSERT" then handleInsert(key, char)
        elseif mode == "VISUAL" then handleVisual(key, char)
        elseif mode == "COMMAND" then handleCommand(key, char)
        end
    elseif event[1] == "term_resize" then
        w, h = term.getSize()
        setCursor(x, y)
        term.clear()
        redrawText()
        redrawStatusBar()
    end
end

term.clear()
term.setCursorBlink(false)
term.setCursorPos(1, 1)

