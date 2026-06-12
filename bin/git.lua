local args = { ... }
local cmd = args[1]
local config_file = ".gitconfig"

local current_config_path = shell.resolve(config_file)

-- ==========================================
-- URL/路径 智能解析器 (修复增强版)
-- ==========================================
local function parse_repo(input)
    if not input then return nil, nil, nil end

    -- 1. 暴力净化：去掉常见的 URL 协议和域名前缀
    input = input:gsub("^https?://", "")
    input = input:gsub("^raw%.githubusercontent%.com/", "")
    input = input:gsub("^github%.com/", "")

    -- 去掉尾部的斜杠和 .git 后缀
    if input:sub(-1) == "/" then input = input:sub(1, -2) end
    if input:sub(-4) == ".git" then input = input:sub(1, -5) end

    -- 2. 解析出 user, repo 和 subpath
    local user, repo, subpath = input:match("^([^/]+)/([^/]+)/?(.*)$")

    if user and repo then
        if subpath == "" then subpath = nil end

        if subpath then
            -- 3. 智能去除从浏览器直接复制的 URL 带来的 tree/main 或 blob/main 等分支目录
            local prefix, branch, real_path = subpath:match("^(tree)/([^/]+)/(.*)$")
            if not prefix then
                prefix, branch, real_path = subpath:match("^(blob)/([^/]+)/(.*)$")
            end

            if prefix and real_path then
                subpath = real_path
            else
                -- 4. 容错：如果用户手写了如 "user/repo/main/src..."
                -- GitHub API 的文件树中并不包含 main/，所以需要安全剥离
                local b, p = subpath:match("^(main)/(.*)$")
                if not b then b, p = subpath:match("^(master)/(.*)$") end
                if b and p then
                    subpath = p
                end
            end
        end
        return user, repo, subpath
    end

    return nil, nil, nil
end

-- ==========================================
-- 核心配置读写
-- ==========================================
local function load_config(path)
    path = path or current_config_path
    local default_cfg = { user = "", repo = "", branch = "main", token = "", subpath = "" }
    if not fs.exists(path) then return default_cfg end
    
    local f = fs.open(path, "r")
    local data = textutils.unserialise(f.readAll())
    f.close()
    
    if not data then return default_cfg end
    data.token = data.token or ""
    data.subpath = data.subpath or ""
    data.branch = data.branch or "main"
    return data
end

local function save_config(cfg, path)
    path = path or current_config_path
    local f = fs.open(path, "w")
    f.write(textutils.serialise(cfg))
    f.close()
end

-- ==========================================
-- 核心：智能拉取函数 (支持单文件与子目录)
-- ==========================================
local function do_pull(user, repo, branch, dest_dir, token, subpath)
    local tree_url = string.format(
        "https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1",
        user, repo, branch
    )

    print("Fetching repository structure from GitHub...")
    
    local headers = {
        ["User-Agent"] = "ComputerCraft-Git-Client/2.1"
    }
    if token and token ~= "" then
        headers["Authorization"] = "token " .. token
    end

    local response, err_msg, err_res = http.get(tree_url, headers)
    
    if not response then
        printError("Error: Failed to fetch directory tree!")
        printError("HTTP Error: " .. tostring(err_msg))
        if err_res then
            local error_body = err_res.readAll()
            err_res.close()
            local ok, err_data = pcall(textutils.unserialiseJSON, error_body)
            if ok and err_data and err_data.message then
                printError("GitHub API Says: " .. err_data.message)
            end
        end
        return false
    end

    local raw_json = response.readAll()
    response.close()
    
    local data = textutils.unserialiseJSON(raw_json)
    if not data or not data.tree then
        printError("Error: Failed to parse GitHub data or repository is empty.")
        return false
    end

    -- 分析目标是文件还是目录
    local target_is_file = false
    local prefix = subpath or ""
    
    if prefix ~= "" then
        for _, item in ipairs(data.tree) do
            if item.path == prefix then
                if item.type == "blob" then
                    target_is_file = true
                end
                break
            end
        end
        if not target_is_file and prefix:sub(-1) ~= "/" then
            prefix = prefix .. "/"
        end
    end

    print(string.format("Target mode: %s", target_is_file and "Single File" or "Directory"))
    print("Starting synchronization...")
    
    local success_count = 0
    local fail_count = 0

    for _, item in ipairs(data.tree) do
        local should_download = false
        local rel_path = ""

        if target_is_file then
            if item.path == subpath then
                should_download = true
                rel_path = fs.getName(item.path)
            end
        else
            if (prefix == "" or item.path:sub(1, #prefix) == prefix) 
               and not item.path:match("^%.git") then
                should_download = true
                rel_path = prefix == "" and item.path or item.path:sub(#prefix + 1)
            end
        end

        if should_download and rel_path ~= "" then
            local local_path = fs.combine(dest_dir, rel_path)
            
            if item.type == "tree" then
                if not fs.exists(local_path) then
                    fs.makeDir(local_path)
                end
            elseif item.type == "blob" then
                -- 转义 URL 路径应对含有空格等特殊字符的文件名
                local safe_item_path = textutils.urlEncode(item.path):gsub("%%2F", "/")
                local raw_url = string.format(
                    "https://raw.githubusercontent.com/%s/%s/%s/%s",
                    user, repo, branch, safe_item_path
                )
                
                write("-> " .. rel_path .. " ... ")
                local file_res = http.get(raw_url, headers)
                
                if file_res then
                    local parent_dir = fs.getDir(local_path)
                    if not fs.exists(parent_dir) then fs.makeDir(parent_dir) end

                    local content = file_res.readAll()
                    file_res.close()
                    local f = fs.open(local_path, "w")
                    f.write(content)
                    f.close()
                    print("OK")
                    success_count = success_count + 1
                else
                    print("FAILED")
                    fail_count = fail_count + 1
                end
            end
        end
    end
    print("---------------------------------")
    print(string.format("Sync complete! %d success, %d failed.", success_count, fail_count))
    return fail_count == 0
end

-- ==========================================
-- 帮助菜单
-- ==========================================
if not cmd or cmd == "help" then
    print("=== CC:T Git Terminal ===")
    print("git clone <url/path> [dir] : Clone repo/dir/file")
    print("git checkout <branch>      : Switch branch")
    print("git auth <token>           : Save GitHub PAT")
    print("git status                 : View repo status")
    print("git pull                   : Sync updates")
    return
end

-- ==========================================
-- 命令分发
-- ==========================================

if cmd == "auth" then
    local token = args[2]
    if not token then
        printError("Usage: git auth <your_github_token>")
        return
    end

    local cfg = load_config()
    if token == "clear" then
        cfg.token = ""
        print("Auth Token cleared.")
    else
        cfg.token = token
        print("Auth Token saved securely!")
    end
    save_config(cfg)

elseif cmd == "clone" then
    local repo_input = args[2]
    if not repo_input then
        printError("Usage: git clone <URL or user/repo[/subpath]> [target dir]")
        return
    end

    local user, repo, subpath = parse_repo(repo_input)
    if not (user and repo) then
        printError("Error: Cannot parse repository address.")
        return
    end

    local folder_name = args[3]
    if not folder_name then
        folder_name = subpath and fs.getName(subpath) or repo
    end
    
    local dest_dir = shell.resolve(folder_name)

    if not fs.exists(dest_dir) then
        fs.makeDir(dest_dir)
    elseif not fs.isDir(dest_dir) then
        printError("Error: Target path exists and is not a folder!")
        return
    end

    local current_cfg = load_config()
    local token = current_cfg.token

    local target_config = fs.combine(dest_dir, config_file)
    local cfg = { user = user, repo = repo, branch = "main", token = token, subpath = subpath or "" }
    save_config(cfg, target_config)

    print(string.format("Repo : %s/%s", user, repo))
    print(string.format("Path : %s", subpath or "ROOT"))
    print(string.format("Local: %s", dest_dir))
    
    do_pull(user, repo, cfg.branch, dest_dir, token, cfg.subpath)

elseif cmd == "checkout" and args[2] then
    local cfg = load_config()
    cfg.branch = args[2]
    save_config(cfg)
    print("Switched tracking branch to: " .. cfg.branch)

elseif cmd == "status" then
    local cfg = load_config()
    if cfg.user == "" then
        print("Current directory is not a git repository.")
    else
        print("Repo  : " .. cfg.user .. "/" .. cfg.repo)
        print("Path  : " .. (cfg.subpath == "" and "ROOT" or cfg.subpath))
        print("Branch: " .. cfg.branch)
        print("Auth  : " .. (cfg.token ~= "" and "Installed" or "None"))
    end

elseif cmd == "pull" then
    local cfg = load_config()
    if cfg.user == "" then
        printError("Error: Current directory is not bound.")
        return
    end
    do_pull(cfg.user, cfg.repo, cfg.branch, shell.dir(), cfg.token, cfg.subpath)

else
    printError("Unknown git command. Type 'git' for help.")
end
