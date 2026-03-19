-- RlizX Skill Loader
-- 负责加载完整的技能文档和资源信息

local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/../Hub/utils.lua")

local M = {}

-- 列出目录中的文件
local function list_directory(dir_path)
    local files = {}
    local pipe = io.popen("find '" .. dir_path .. "' -maxdepth 1 -type f 2>/dev/null | sort")
    if not pipe then
        return files
    end

    for line in pipe:lines() do
        local file_path = line:match("^%s*(.-)%s*$")
        if file_path then
            local file_name = file_path:match("([^/]+)$")
            if file_name and file_name ~= "" then
                table.insert(files, file_name)
            end
        end
    end
    pipe:close()

    return files
end

-- 解析完整的 SKILL.md
local function parse_full_skill(skill_name, skill_path)
    local skill_file = skill_path .. "/SKILL.md"
    local content = U.read_file(skill_file)
    if not content then
        return nil, "SKILL.md not found"
    end

    local detail = {
        name = skill_name,
        version = "",
        author = "",
        category = "",
        description = "",
        full_content = content,
        usage = "",
        scenarios = {},
        available_resources = {
            scripts = {},
            references = {},
            assets = {}
        }
    }

    local current_section = nil
    local in_metadata = false

    for line in content:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")

        -- 检测章节标题
        if trimmed:match("^##%s+") then
            current_section = trimmed:match("^##%s+(.+)$")

            if current_section == "元数据" then
                in_metadata = true
            else
                in_metadata = false
            end
        elseif current_section == "元数据" and in_metadata then
            -- 解析元数据
            local key, value = trimmed:match("^%s*-%s*([^:]+):%s*(.+)$")
            if key and value then
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")

                if key == "Version" then
                    detail.version = value
                elseif key == "Author" then
                    detail.author = value
                elseif key == "Category" then
                    detail.category = value
                end
            end
        elseif current_section == "描述" and detail.description == "" then
            -- 提取描述
            local desc_content = content:match("## 描述\r?\n(.*)")
            if desc_content then
                local next_section = desc_content:find("\n##")
                if next_section then
                    detail.description = desc_content:sub(1, next_section - 1):match("^%s*(.-)%s*$")
                else
                    detail.description = desc_content:match("^%s*(.-)%s*$")
                end
            end
        elseif current_section == "使用方法" then
            -- 提取使用方法
            local usage_content = content:match("## 使用方法\r?\n(.*)")
            if usage_content then
                local next_section = usage_content:find("\n##")
                if next_section then
                    detail.usage = usage_content:sub(1, next_section - 1):match("^%s*(.-)%s*$")
                else
                    detail.usage = usage_content:match("^%s*(.-)%s*$")
                end
            end
        elseif current_section == "使用场景" then
            -- 提取使用场景
            local scenario = trimmed:match("^%s*-%s*(.+)$")
            if scenario then
                table.insert(detail.scenarios, scenario)
            end
        end
    end

    -- 扫描可用资源
    detail.available_resources.scripts = list_directory(skill_path .. "/scripts")
    detail.available_resources.references = list_directory(skill_path .. "/references")
    detail.available_resources.assets = list_directory(skill_path .. "/assets")

    return detail
end

-- 加载技能详细信息
function M.load_skill(skill_name, base_dir)
    local skill_path = base_dir .. "/../../skills/" .. skill_name

    -- 检查技能目录是否存在
    local check_cmd = "test -d '" .. skill_path .. "' && echo 'exists' || echo 'notfound'"
    local pipe = io.popen(check_cmd)
    if not pipe then
        return nil, "Failed to check skill directory"
    end
    local result = pipe:read("*all")
    pipe:close()

    if result:match("notfound") then
        return nil, "Skill not found: " .. skill_name
    end

    -- 解析完整技能
    local detail, err = parse_full_skill(skill_name, skill_path)
    if not detail then
        return nil, err or "Failed to parse skill"
    end

    return detail
end

-- 读取技能资源文件
function M.load_skill_resource(skill_name, resource_type, resource_name, base_dir)
    local valid_types = { scripts = true, references = true, assets = true }
    if not valid_types[resource_type] then
        return nil, "Invalid resource type: " .. tostring(resource_type)
    end

    local resource_path = base_dir .. "/../../skills/" .. skill_name .. "/" .. resource_type .. "/" .. resource_name
    local content = U.read_file(resource_path)

    if not content then
        return nil, "Resource not found: " .. resource_name
    end

    return content
end

return M