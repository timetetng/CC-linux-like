-- /config/theme.lua
local theme = {}

function theme.apply()
    -- 判断终端是否支持彩色[cite: 1]
    if term.isColor() and term.setPaletteColor then
        term.setPaletteColor(colors.black, 0x1e1e2e)     -- Base (默认背景)
        term.setPaletteColor(colors.gray, 0x313244)      -- Surface0
        term.setPaletteColor(colors.lightGray, 0x585b70) -- Surface2
        term.setPaletteColor(colors.white, 0xcdd6f4)     -- Text (默认文本)
        term.setPaletteColor(colors.red, 0xf38ba8)       -- Red
        term.setPaletteColor(colors.orange, 0xfab387)    -- Peach
        term.setPaletteColor(colors.yellow, 0xf9e2af)    -- Yellow
        term.setPaletteColor(colors.lime, 0xa6e3a1)      -- Green
        term.setPaletteColor(colors.green, 0x94e2d5)     -- Teal
        term.setPaletteColor(colors.cyan, 0x89dceb)      -- Sky
        term.setPaletteColor(colors.lightBlue, 0x89b4fa) -- Blue
        term.setPaletteColor(colors.blue, 0xb4befe)      -- Lavender
        term.setPaletteColor(colors.purple, 0xcba6f7)    -- Mauve
        term.setPaletteColor(colors.magenta, 0xf5c2e7)   -- Pink
        term.setPaletteColor(colors.pink, 0xf2cdcd)      -- Flamingo
        term.setPaletteColor(colors.brown, 0xeba0ac)     -- Maroon
    end
end

return theme
