-- neofetch.lua

-- 1. 基础系统信息
local label = os.getComputerLabel() or "computer"
local id = os.getComputerID()
local os_ver = os.version()
local host = (function()
	if _HOST then
		w1, w2 = _HOST:match("(%S+)%s+(%S+)")
	end
	return string.format("%s %s", w1, w2)
end)()

local minecraft_version = (function(s)
	local last = s:match("(%S+)$")
	return last and last:sub(1, -2) or ""
end)(_HOST)

local w, h = term.getSize()
local is_color = term.isColor()
local editor = (function()
	if shell.resolveProgram("vim") then
		return "vim"
	else
		return "CraftOS-edit"
	end
end)()
local shell = "crash"

-- 2. 磁盘信息计算
local function formatSize(bytes)
	if bytes >= 1048576 then
		return string.format("%.2fMB", bytes / 1048576)
	elseif bytes >= 1024 then
		return string.format("%.1fKB", bytes / 1024)
	else
		return bytes .. "B"
	end
end

local capacity = fs.getCapacity("/")
local free = fs.getFreeSpace("/")
local disk_str = "Unknown"

if free == "unlimited" then
	disk_str = "Unlimited"
elseif type(capacity) == "number" and type(free) == "number" then
	local used = capacity - free
	local percent = 0
	if capacity > 0 then
		percent = math.floor((used / capacity) * 100)
	end
	disk_str = formatSize(used) .. " / " .. formatSize(capacity) .. " (" .. percent .. "%)"
end

-- 开机时间计算
local function formatuptime()
	local time = os.clock()
	if time < 60 then
		return string.format("%dsecs", math.floor(time))
	elseif time < 3600 then
		local min = math.floor(time / 60)
		local sec = math.floor(time % 60)
		return string.format("%dmins, %dsecs", min, sec)
	elseif time < 3600 * 24 then
		local hour = math.floor(time / 3600)
		local min = math.floor((time % 3600) / 60)
		local sec = math.floor((time % 3600) % 60)
		return string.format("%dhours, %dmins, %dsecs", hour, min, sec)
	else
		local day = math.floor(time / (3600 * 24))
		local daytime = time - day * 3600 * 24
		local hour = math.floor(daytime / 3600)
		local min = math.floor((daytime % 3600) / 60)
		local sec = math.floor((daytime % 3600) % 60)
		return string.format("%ddays, %dhours, %dmins, %dsecs", day, hour, min, sec)
	end
end

local uptime = formatuptime()

-- 3. 颜色配置
local c_logo = is_color and colors.yellow or colors.white
local c_title = is_color and colors.lightBlue or colors.white
local c_key = is_color and colors.cyan or colors.white
local c_reset = colors.white

-- 4. ASCII Logo
local logo = {
	"                ",
	"                ",
	"    .------.    ",
	"    | >_   |    ",
	"    |      |    ",
	"    '------'    ",
	"     [====]     ",
}

-- 5. 信息排版表
local info = {
	{ text = label .. "@" .. "xingjian", color = c_title },
	{ text = string.rep("-", #(label .. "@xingjian")), color = colors.gray },
	{ key = "OS", val = os_ver },
	{ key = "Host", val = host },
	{ key = "Version", val = minecraft_version },
	{ key = "ID", val = id },
	{ key = "Shell", val = shell },
	{ key = "Editor", val = editor },
	{ key = "Uptime", val = uptime },
	{ key = "Res", val = w .. "x" .. h },
	{ key = "Disk", val = disk_str },
	{ key = "Color", val = tostring(is_color) },
}

local max_lines = math.max(#logo, #info)

-- 6. 渲染输出
print()
for i = 1, max_lines do
	-- 左侧 Logo
	local logo_line = logo[i] or string.rep(" ", 16)
	term.setTextColor(c_logo)
	write(logo_line .. "  ")

	-- 右侧系统信息
	local info_data = info[i]
	if info_data then
		if info_data.key then
			term.setTextColor(c_key)
			write(info_data.key .. ": ")
			term.setTextColor(c_reset)
			print(info_data.val)
		else
			term.setTextColor(info_data.color or c_reset)
			print(info_data.text)
		end
	else
		print()
	end
end

term.setTextColor(c_reset)
print()

-- 7. 打印底部 8 种核心色块并带有间距
if is_color then
	-- 对应你截图中的 8 种颜色：灰、白(文本)、青、粉、蓝、黄、绿、红
	local color_row = {
		colors.gray,
		colors.white,
		colors.green,
		colors.magenta,
		colors.lightBlue,
		colors.yellow,
		colors.lime,
		colors.red,
	}

	-- 缩进 18 个空格，使其对齐到右侧文本区域
	write(string.rep(" ", 18))

	for _, c in ipairs(color_row) do
		term.setBackgroundColor(c)
		write("  ") -- 绘制宽度为 2 的色块

		term.setBackgroundColor(colors.black)
		write(" ") -- 绘制宽度为 1 的黑色背景空格作为间距
	end

	print()
	print()
end
