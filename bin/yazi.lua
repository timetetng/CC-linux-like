-- CC-Yazi - A 3-column Vim-like file manager for CC:Tweaked

local tArgs = {...}
local currentPath = shell.resolve(tArgs[1] or "")
if not fs.isDir(currentPath) then currentPath = fs.getDir(currentPath) end

local w, h = term.getSize()
local bRunning = true

-- Layout widths (optimized for 51-char default terminal)
local w1 = math.floor(w * 0.22)
local w2 = math.floor(w * 0.38)
local w3 = w - w1 - w2

-- State
local files = {}
local cursorIdx = 1
local scrollY = 0
local lastChar = ""

-- Colors (Catppuccin Mocha Theme)
local isColour = term.isColour()

-- 如果终端支持自定义调色板，则注入真正的 Catppuccin 色值
if isColour and term.setPaletteColor then
    term.setPaletteColor(colours.black, 0x1e1e2e)     -- Base (主背景)
    term.setPaletteColor(colours.grey, 0x181825)      -- Mantle (父级/预览背景，区分层级)
    term.setPaletteColor(colours.lightGrey, 0x45475a) -- Surface1 (选中项背景)
    term.setPaletteColor(colours.white, 0xcdd6f4)     -- Text (主文本)
    term.setPaletteColor(colours.cyan, 0x89b4fa)      -- Blue (目录颜色)
    term.setPaletteColor(colours.green, 0xa6e3a1)     -- Green (可执行文件颜色)
end

local colBg = colours.black
local colParentBg = colours.grey
local colCurrentBg = colours.black
local colPreviewBg = colours.grey
local colText = colours.white
local colDir = isColour and colours.cyan or colours.white
local colExec = isColour and colours.green or colours.white
local colSelectBg = isColour and colours.lightGrey or colours.grey
local colSelectText = colours.white

-- Syntax Lexer for Preview
local tokens = require("cc.internal.syntax.parser").tokens
local lex_one = require("cc.internal.syntax.lexer").lex_one
local token_colours = {
    [tokens.STRING] = isColour and colours.red or colText,
    [tokens.COMMENT] = isColour and colours.green or colours.lightGrey,
    [tokens.NUMBER] = isColour and colours.magenta or colText,
}
local keywordColour = isColour and colours.yellow or colText
local keywords = {
    "AND", "BREAK", "DO", "ELSE", "ELSEIF", "END", "FALSE", "FOR", "FUNCTION",
    "GOTO", "IF", "IN", "LOCAL", "NIL", "NOT", "OR", "REPEAT", "RETURN", "THEN",
    "TRUE", "UNTIL", "WHILE"
}
for _, kw in ipairs(keywords) do token_colours[tokens[kw]] = keywordColour end
for _, token in pairs(tokens) do
    if not token_colours[token] then token_colours[token] = colText end
end
local lex_context = { line = function() end, report = function() end }

-- Helper: Get sorted files
local function getSortedFiles(path)
    if not fs.exists(path) or not fs.isDir(path) then return {} end
    local rawFiles = fs.list(path)
    local dirs, normalFiles = {}, {}
    for _, f in ipairs(rawFiles) do
        local full = fs.combine(path, f)
        if fs.isDir(full) then table.insert(dirs, f)
        else table.insert(normalFiles, f) end
    end
    table.sort(dirs, function(a,b) return a:lower() < b:lower() end)
    table.sort(normalFiles, function(a,b) return a:lower() < b:lower() end)
    
    local result = {}
    for _, d in ipairs(dirs) do table.insert(result, {name = d, isDir = true}) end
    for _, f in ipairs(normalFiles) do table.insert(result, {name = f, isDir = false}) end
    return result
end

-- Helper: Truncate string cleanly
local function trunc(str, len)
    if #str > len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

-- Refresh state
local function refreshState()
    files = getSortedFiles(currentPath)
    if cursorIdx > #files then cursorIdx = math.max(1, #files) end
    if cursorIdx < 1 then cursorIdx = 1 end
    
    local listHeight = h - 1
    if cursorIdx - scrollY > listHeight then scrollY = cursorIdx - listHeight end
    if cursorIdx - scrollY < 1 then scrollY = cursorIdx - 1 end
end

-- Drawing
local function drawColumn(xOffset, width, bg, items, activeIdx, startScroll)
    for i = 1, h - 1 do
        term.setCursorPos(xOffset, i)
        local idx = startScroll + i
        
        if idx <= #items and items[idx] then
            local item = items[idx]
            if activeIdx == idx then
                term.setBackgroundColor(colSelectBg)
                term.setTextColor(colSelectText)
            else
                term.setBackgroundColor(bg)
                if item.isDir then term.setTextColor(colDir)
                elseif item.name:match("%.lua$") then term.setTextColor(colExec)
                else term.setTextColor(colText) end
            end
            
            local display = item.name .. (item.isDir and "/" or "")
            term.write(trunc(display, width))
        else
            term.setBackgroundColor(bg)
            term.write(string.rep(" ", width))
        end
    end
end

local function drawPreview(xOffset, width, bg, targetItem)
    term.setBackgroundColor(bg)
    term.setTextColor(colText)
    for i = 1, h - 1 do
        term.setCursorPos(xOffset, i)
        term.write(string.rep(" ", width))
    end
    
    if not targetItem then return end
    local fullPath = fs.combine(currentPath, targetItem.name)
    
    if targetItem.isDir then
        -- Preview directory
        local subFiles = getSortedFiles(fullPath)
        for i = 1, math.min(#subFiles, h - 1) do
            term.setCursorPos(xOffset, i)
            local sub = subFiles[i]
            if sub.isDir then term.setTextColor(colDir) else term.setTextColor(colText) end
            term.write(trunc(sub.name .. (sub.isDir and "/" or ""), width))
        end
    else
        -- Preview file with syntax highlighting
        if fs.getSize(fullPath) > 50000 then
            term.setCursorPos(xOffset, 1)
            term.setTextColor(colText)
            term.write(trunc("[File too large]", width))
            return
        end
        local f = io.open(fullPath, "r")
        if f then
            local state = false
            for i = 1, h - 1 do
                local line = f:read()
                if not line then break end
                term.setCursorPos(xOffset, i)
                
                -- Prepare string for lexing (handle tabs and width)
                local renderLine = trunc(line:gsub("\t", "  "), width)
                
                local pos, token, _, finish, continuation = 1
                if state then
                    token, finish, _, continuation = state[1](lex_context, renderLine, table.unpack(state, 2))
                else
                    token, _, finish, _, continuation = lex_one(lex_context, renderLine, 1)
                end

                local currentColour = colText
                term.setTextColor(currentColour)

                while token do
                    local newColour = token_colours[token] or colText
                    if newColour ~= currentColour then
                        term.setTextColor(newColour)
                        currentColour = newColour
                    end
                    term.write(renderLine:sub(pos, finish))
                    pos = finish + 1
                    if continuation then break end
                    token, _, finish, _, continuation = lex_one(lex_context, renderLine, pos)
                end
                term.write(renderLine:sub(pos))
                if continuation == nil then continuation = false end
                state = continuation or false
            end
            f:close()
        end
    end
end

local function drawStatusBar()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colours.white)
    term.setTextColor(colours.black)
    local info = " " .. (currentPath == "" and "/" or currentPath)
    if #files > 0 then
        local target = files[cursorIdx]
        local fPath = fs.combine(currentPath, target.name)
        if not target.isDir then
            info = info .. " | " .. fs.getSize(fPath) .. "B"
        end
    end
    info = trunc(info .. string.rep(" ", w), w)
    term.write(info)
end

local function draw()
    local parentPath = fs.getDir(currentPath)
    local parentFiles = getSortedFiles(parentPath)
    local pIdx = 0
    local cName = fs.getName(currentPath)
    for i, f in ipairs(parentFiles) do
        if f.name == cName then pIdx = i; break end
    end
    if currentPath == "" then parentFiles = {}; pIdx = 0 end
    local pScroll = math.max(0, pIdx - math.floor((h-1)/2))
    
    drawColumn(1, w1, colParentBg, parentFiles, pIdx, pScroll)
    drawColumn(1 + w1, w2, colCurrentBg, files, cursorIdx, scrollY)
    
    local target = files[cursorIdx]
    drawPreview(1 + w1 + w2, w3, colPreviewBg, target)
    drawStatusBar()
end

refreshState()
term.clear()
draw()

-- Input Loop
while bRunning do
    local event, p1, p2 = os.pullEvent()
    
    if event == "term_resize" then
        w, h = term.getSize()
        w1 = math.floor(w * 0.22)
        w2 = math.floor(w * 0.38)
        w3 = w - w1 - w2
        refreshState()
        draw()
    elseif event == "char" then
        local char = p1
        if char == "q" then
            bRunning = false
        elseif char == "j" then
            cursorIdx = math.min(#files, cursorIdx + 1)
        elseif char == "k" then
            cursorIdx = math.max(1, cursorIdx - 1)
        elseif char == "h" then
            if currentPath ~= "" then
                local oldName = fs.getName(currentPath)
                currentPath = fs.getDir(currentPath)
                refreshState()
                for i, f in ipairs(files) do
                    if f.name == oldName then cursorIdx = i; break end
                end
            end
        elseif char == "l" then
            if #files > 0 then
                local target = files[cursorIdx]
                if target.isDir then
                    currentPath = fs.combine(currentPath, target.name)
                    cursorIdx = 1
                    scrollY = 0
                    refreshState()
                end
            end
        elseif char == "G" then
            cursorIdx = #files
        elseif char == "g" then
            if lastChar == "g" then
                cursorIdx = 1
                lastChar = ""
            else
                lastChar = "g"
            end
        end
        
        if char ~= "g" then lastChar = "" end
        
        local listHeight = h - 1
        if cursorIdx - scrollY > listHeight then scrollY = cursorIdx - listHeight end
        if cursorIdx - scrollY < 1 then scrollY = cursorIdx - 1 end
        
        draw()
    elseif event == "key" then
        local key = p1
        -- 按下回车键或 'e' 时，统一使用 cvim 打开文件
        if key == keys.enter or key == keys.e then
            if #files > 0 then
                local target = files[cursorIdx]
                local targetPath = fs.combine(currentPath, target.name)
                if target.isDir then
                    currentPath = targetPath
                    cursorIdx = 1
                    scrollY = 0
                    refreshState()
                    draw()
                else
                    term.setBackgroundColor(colours.black)
                    term.setTextColor(colours.white)
                    term.clear()
                    term.setCursorPos(1,1)
                    
                    -- 直接调用 vim（找不到则降级回 edit）
                    local editor = shell.resolveProgram("vim") and "vim" or "edit"
                    shell.run(editor, targetPath)
                    
                    -- 从 cvim 退出后恢复 yazi 界面
                    term.clear()
                    refreshState()
                    draw()
                end
            end
        end
    end
end

-- Cleanup
term.setBackgroundColor(colours.black)
term.setTextColor(colours.white)
term.clear()
term.setCursorPos(1, 1)
