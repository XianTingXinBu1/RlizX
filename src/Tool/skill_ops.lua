-- RlizX Skill Operations
-- 技能系统相关工具

local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/../Hub/utils.lua")

-- 加载技能管理器
local function get_skill_manager()
    local base_dir = U.script_dir()
    return dofile(base_dir .. "/../Skill/skill_manager.lua")
end

-- 工具定义
local function get_tool_definitions()
    return {
        {
            name = "scan_available_skills",
            description = "扫描并列出所有可用的技能及其元数据",
            inputSchema = {
                type = "object",
                properties = {},
                required = {}
            }
        },
        {
            name = "load_skill_info",
            description = "加载指定技能的完整详细信息，包括使用方法、场景和可用资源",
            inputSchema = {
                type = "object",
                properties = {
                    skill_name = {
                        type = "string",
                        description = "技能名称"
                    }
                },
                required = {"skill_name"}
            }
        },
        {
            name = "read_skill_resource",
            description = "读取指定技能的资源文件内容（脚本、参考文档或资源文件）",
            inputSchema = {
                type = "object",
                properties = {
                    skill_name = {
                        type = "string",
                        description = "技能名称"
                    },
                    resource_type = {
                        type = "string",
                        description = "资源类型：scripts、references 或 assets",
                        enum = {"scripts", "references", "assets"}
                    },
                    resource_name = {
                        type = "string",
                        description = "资源文件名"
                    }
                },
                required = {"skill_name", "resource_type", "resource_name"}
            }
        },
        {
            name = "search_skills",
            description = "根据关键词搜索技能，支持按名称、描述或触发词搜索",
            inputSchema = {
                type = "object",
                properties = {
                    query = {
                        type = "string",
                        description = "搜索关键词"
                    }
                },
                required = {"query"}
            }
        },
        {
            name = "refresh_skills",
            description = "刷新技能注册表，重新扫描技能目录",
            inputSchema = {
                type = "object",
                properties = {},
                required = {}
            }
        }
    }
end

-- 工具处理器
local function handle_scan_available_skills(_args, _context)
    local SkillManager = get_skill_manager()
    local base_dir = U.script_dir()

    local registry = SkillManager.get_skill_registry(base_dir)

    if not registry or next(registry) == nil then
        return {
            result = "没有找到可用的技能"
        }
    end

    local lines = {"可用技能列表："}
    for name, skill in pairs(registry) do
        local meta = {}
        table.insert(meta, "版本: " .. (skill.version or "未知"))
        table.insert(meta, "作者: " .. (skill.author or "未知"))
        table.insert(meta, "分类: " .. (skill.category or "未分类"))

        if skill.description and skill.description ~= "" then
            table.insert(meta, "描述: " .. skill.description)
        end

        if skill.triggers and #skill.triggers > 0 then
            table.insert(meta, "触发词: " .. table.concat(skill.triggers, ", "))
        end

        table.insert(lines, "")
        table.insert(lines, "技能名称: " .. name)
        for _, m in ipairs(meta) do
            table.insert(lines, "  " .. m)
        end
    end

    return {
        result = table.concat(lines, "\n")
    }
end

local function handle_load_skill_info(args, _context)
    local skill_name = args.skill_name
    if not skill_name or skill_name == "" then
        return {
            error = "缺少必需参数: skill_name"
        }
    end

    local SkillManager = get_skill_manager()
    local base_dir = U.script_dir()

    local detail, err = SkillManager.get_skill_detail(skill_name, base_dir)
    if not detail then
        return {
            error = "加载技能失败: " .. (err or "未知错误")
        }
    end

    local lines = {"技能详细信息："}
    table.insert(lines, "")
    table.insert(lines, "技能名称: " .. detail.name)
    table.insert(lines, "版本: " .. detail.version)
    table.insert(lines, "作者: " .. detail.author)
    table.insert(lines, "分类: " .. detail.category)
    table.insert(lines, "")
    table.insert(lines, "描述:")
    table.insert(lines, detail.description)
    table.insert(lines, "")

    if detail.usage and detail.usage ~= "" then
        table.insert(lines, "使用方法:")
        table.insert(lines, detail.usage)
        table.insert(lines, "")
    end

    if detail.scenarios and #detail.scenarios > 0 then
        table.insert(lines, "使用场景:")
        for _, scenario in ipairs(detail.scenarios) do
            table.insert(lines, "  - " .. scenario)
        end
        table.insert(lines, "")
    end

    table.insert(lines, "可用资源:")
    local resources = detail.available_resources
    if resources.scripts and #resources.scripts > 0 then
        table.insert(lines, "  脚本:")
        for _, script in ipairs(resources.scripts) do
            table.insert(lines, "    - " .. script)
        end
    end
    if resources.references and #resources.references > 0 then
        table.insert(lines, "  参考文档:")
        for _, ref in ipairs(resources.references) do
            table.insert(lines, "    - " .. ref)
        end
    end
    if resources.assets and #resources.assets > 0 then
        table.insert(lines, "  资源文件:")
        for _, asset in ipairs(resources.assets) do
            table.insert(lines, "    - " .. asset)
        end
    end

    return {
        result = table.concat(lines, "\n")
    }
end

local function handle_read_skill_resource(args, _context)
    local skill_name = args.skill_name
    local resource_type = args.resource_type
    local resource_name = args.resource_name

    if not skill_name or skill_name == "" then
        return {
            error = "缺少必需参数: skill_name"
        }
    end
    if not resource_type or resource_type == "" then
        return {
            error = "缺少必需参数: resource_type"
        }
    end
    if not resource_name or resource_name == "" then
        return {
            error = "缺少必需参数: resource_name"
        }
    end

    local SkillManager = get_skill_manager()
    local base_dir = U.script_dir()

    local content, err = SkillManager.get_skill_resource(skill_name, resource_type, resource_name, base_dir)
    if not content then
        return {
            error = "读取资源失败: " .. (err or "未知错误")
        }
    end

    return {
        result = "资源内容:\n\n" .. content
    }
end

local function handle_search_skills(args, _context)
    local query = args.query
    if not query or query == "" then
        return {
            error = "缺少必需参数: query"
        }
    end

    local SkillManager = get_skill_manager()
    local base_dir = U.script_dir()

    local results = SkillManager.search_skills(query, base_dir)

    if not results or next(results) == nil then
        return {
            result = "没有找到匹配的技能: " .. query
        }
    end

    local lines = {"搜索结果 (" .. query .. "):"}
    for name, skill in pairs(results) do
        table.insert(lines, "")
        table.insert(lines, "技能名称: " .. name)
        table.insert(lines, "  描述: " .. (skill.description or "无"))
        if skill.triggers and #skill.triggers > 0 then
            table.insert(lines, "  触发词: " .. table.concat(skill.triggers, ", "))
        end
    end

    return {
        result = table.concat(lines, "\n")
    }
end

local function handle_refresh_skills(_args, _context)
    local SkillManager = get_skill_manager()
    local base_dir = U.script_dir()

    local registry = SkillManager.refresh_registry(base_dir)

    local count = 0
    for _ in pairs(registry) do
        count = count + 1
    end

    return {
        result = "技能注册表已刷新，共找到 " .. count .. " 个技能"
    }
end

-- 注册工具
local function register()
    local Registry = dofile(U.script_dir() .. "/tool_registry.lua")

    local definitions = get_tool_definitions()

    Registry.register_tool(
        "scan_available_skills",
        definitions[1],
        handle_scan_available_skills,
        { category = "read" }
    )

    Registry.register_tool(
        "load_skill_info",
        definitions[2],
        handle_load_skill_info,
        { category = "read" }
    )

    Registry.register_tool(
        "read_skill_resource",
        definitions[3],
        handle_read_skill_resource,
        { category = "read" }
    )

    Registry.register_tool(
        "search_skills",
        definitions[4],
        handle_search_skills,
        { category = "read" }
    )

    Registry.register_tool(
        "refresh_skills",
        definitions[5],
        handle_refresh_skills,
        { category = "read" }
    )
end

register()