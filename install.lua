-- install.lua - CC-linux-like bootstrap installer
-- Usage: wget run https://raw.githubusercontent.com/timetetng/CC-linux-like/main/install.lua
-- Dynamically discovers .lua files via GitHub API; falls back to hardcoded list on failure.

local BASE_URL = "https://raw.githubusercontent.com/timetetng/CC-linux-like/main"
local TREE_URL = "https://api.github.com/repos/timetetng/CC-linux-like/git/trees/main?recursive=1"

local INCLUDE_PREFIXES = { "bin/", "config/", "game/", "startup.lua" }
local EXCLUDE_FILES = { "install.lua" }

-- Hardcoded fallback when GitHub API is unavailable (rate-limited, offline, etc.)
local FALLBACK_FILES = {
    "startup.lua",
    "bin/boot.lua",
    "bin/cat.lua",
    "bin/crash.lua",
    "bin/git.lua",
    "bin/grep.lua",
    "bin/neofetch.lua",
    "bin/pwd.lua",
    "bin/ssh.lua",
    "bin/touch.lua",
    "bin/tree.lua",
    "bin/vim.lua",
    "bin/yazi.lua",
    "config/theme.lua",
    "game/game/#.lua",
    "game/game/falling.lua",
}

-- URL-encode special characters (# -> %23) so raw URLs aren't truncated
local function urlEncodePath(path)
    return path:gsub("#", "%%23")
end

-- Safely create a directory (and its parents)
local function mkdirSafe(path)
    if fs.exists(path) then
        if fs.isDir(path) then
            return true
        end
        print("  warning: " .. path .. " exists but is not a directory")
        return false
    end
    local parent = path:match("^(.+)/[^/]+$")
    if parent and not fs.exists(parent) then
        mkdirSafe(parent)
    end
    fs.makeDir(path)
    return true
end

-- Download a single file with AUTO-MIRROR fallback
local function downloadFile(url, dest)
    local dir = dest:match("^(.+)/[^/]+$")
    if dir then
        mkdirSafe(dir)
    end

    if fs.exists(dest) then
        return "skipped"
    end

    -- 第一次尝试：GitHub 原站
    local response, err = http.get(url)

    -- 第二次尝试：如果原站触发 rate limit 拦截，自动走 ghproxy 代理重试
    if not response then
        local mirrorUrl = "https://ghproxy.net/" .. url
        response, err = http.get(mirrorUrl)
    end

    if not response then
        return nil, err or "connection failed"
    end

    local content = response.readAll()
    response.close()

    if not content or #content == 0 then
        return nil, "empty response"
    end

    local file, err2 = fs.open(dest, "w")
    if not file then
        return nil, err2 or "cannot write file"
    end

    file.write(content)
    file.close()
    return "ok"
end

-- ==========================================================================
-- Main
-- ==========================================================================
local termW = term.getSize()
local pad = ("="):rep(math.min(termW, 50))

print(pad)
print("  CC-linux-like Installer")
print("  https://github.com/timetetng/CC-linux-like")
print(pad)
print()

-- ==========================================================================
-- 交互式配置 (Interactive Setup)
-- ==========================================================================
print("=== Initial Setup ===")

-- 1. 询问并设置用户名
write("Enter username (leave blank to skip): ")
local username = read()
if username and username ~= "" then
    settings.set("user.name", username)
    settings.save() -- 必须调用 save() 才能将更改持久化到 .settings 文件中
    print(" -> Username saved as: " .. username)
else
    print(" -> Skipped setting username.")
end

-- 2. 询问并设置设备标签
write("Enter device label (leave blank to skip): ")
local label = read()
if label and label ~= "" then
    os.setComputerLabel(label) -- 等同于执行 label set
    print(" -> Device label set to: " .. label)
else
    print(" -> Skipped setting label.")
end

print(pad)
print()
-- ==========================================================================

if not http then
    print("Error: HTTP API is not available. Enable it in CC:Tweaked config.")
    return
end

-- Step 1: try to get file list from GitHub Tree API
local toDownload = {}

if textutils and textutils.unserializeJSON then
    print("Fetching repository file tree...")
    local resp, err = http.get(TREE_URL)
    if resp then
        local raw = resp.readAll()
        resp.close()

        local ok, treeData = pcall(textutils.unserializeJSON, raw)
        if ok and treeData and treeData.tree then
            for _, entry in ipairs(treeData.tree) do
                if entry.type == "blob" and entry.path:match("%.lua$") then
                    local included = false
                    for _, prefix in ipairs(INCLUDE_PREFIXES) do
                        if entry.path == prefix or entry.path:sub(1, #prefix) == prefix then
                            included = true
                            break
                        end
                    end
                    local excluded = false
                    for _, ex in ipairs(EXCLUDE_FILES) do
                        if entry.path == ex then
                            excluded = true
                            break
                        end
                    end
                    if included and not excluded then
                        table.insert(toDownload, {
                            path = entry.path,
                            url = BASE_URL .. "/" .. urlEncodePath(entry.path),
                        })
                    end
                end
            end
        else
            local msg = ""
            if raw and #raw > 0 then
                msg = raw:match('"message"%s*:%s*"([^"]+)"') or ""
            end
            print("  API error" .. (msg ~= "" and (" (" .. msg .. ")") or "") .. " - using fallback list")
        end
    else
        print("  " .. (err or "connection failed") .. " - using fallback list")
    end
else
    print("textutils.unserializeJSON not available - using fallback list")
end

-- Step 2: if API didn't produce results, use fallback
if #toDownload == 0 then
    print("Using hardcoded file list (" .. #FALLBACK_FILES .. " files)")
    for _, path in ipairs(FALLBACK_FILES) do
        table.insert(toDownload, {
            path = path,
            url = BASE_URL .. "/" .. urlEncodePath(path),
        })
    end
end

if #toDownload == 0 then
    print("  no files to install")
    return
end

-- Step 3: create directories
local dirSet = {}
for _, f in ipairs(toDownload) do
    local dir = f.path:match("^(.+)/[^/]+$")
    if dir then
        dirSet["/" .. dir] = true
    end
end

print("Creating directories...")
for dir, _ in pairs(dirSet) do
    if not fs.exists(dir) then
        mkdirSafe(dir)
        print("  " .. dir .. " created")
    end
end
print()

-- Step 4: download files
print("Downloading " .. #toDownload .. " files...")
print()

local countOk = 0
local countSkip = 0
local countFail = 0
local errors = {}

for _, f in ipairs(toDownload) do
    write("  " .. f.path .. " ")

    local status, err = downloadFile(f.url, "/" .. f.path)
    if status == "ok" then
        print("OK")
        countOk = countOk + 1
    elseif status == "skipped" then
        print("skip (exists)")
        countSkip = countSkip + 1
    else
        print("FAIL " .. (err or "unknown error"))
        countFail = countFail + 1
        table.insert(errors, f.path .. ": " .. (err or "unknown error"))
    end

    -- 【关键修复】：每次下载后休息 0.3 秒，防止被当成爬虫踢掉
    os.sleep(0.3)
end

-- Summary
print()
print(pad)
print("  Install summary")
print(pad)
print("  installed: " .. countOk)
if countSkip > 0 then
    print("  skipped:  " .. countSkip .. " (already exist)")
end
if countFail > 0 then
    print("  failed:    " .. countFail)
    print()
    for _, e in ipairs(errors) do
        print("    FAIL " .. e)
    end
end
print(pad)
print()

if countFail == 0 then
    print("  All done! Reboot in 3 seconds...")
	os.sleep(3)
	shell.run("reboot")
else
    print("  Some files failed. Retry or check your network connection.")
end
print(pad)
