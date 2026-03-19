-- RlizX Skill Manager
-- 统一的技能管理接口，整合扫描、加载、索引功能

local SkillScanner = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/skill_scanner.lua")
local SkillLoader = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/skill_loader.lua")
local SkillIndex = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/skill_index.lua")

local M = {}

-- 内存缓存
local registry_cache = nil
local registry_cache_time = 0
local detail_cache = {}
local CACHE_TTL = 300 -- 5分钟

-- 获取技能注册表（带缓存）
function M.get_skill_registry(base_dir)
    local current_time = os.time()

    -- 检查缓存是否有效
    if registry_cache and (current_time - registry_cache_time) < CACHE_TTL then
        return registry_cache
    end

    -- 检查是否需要重新扫描
    if SkillIndex.needs_update(base_dir) then
        -- 全量扫描
        registry_cache = SkillScanner.scan_skills(base_dir)
        SkillIndex.update_index(base_dir, registry_cache)
    else
        -- 从索引加载
        local index = SkillIndex.load_index(base_dir)
        if index and index.skills then
            registry_cache = index.skills
        else
            -- 索引无效，重新扫描
            registry_cache = SkillScanner.scan_skills(base_dir)
            SkillIndex.update_index(base_dir, registry_cache)
        end
    end

    registry_cache_time = current_time
    return registry_cache
end

-- 获取技能详细信息（带缓存）
function M.get_skill_detail(skill_name, base_dir)
    -- 检查缓存
    if detail_cache[skill_name] then
        local cached = detail_cache[skill_name]
        if (os.time() - cached.time) < CACHE_TTL then
            return cached.data
        end
    end

    -- 加载技能详情
    local detail, err = SkillLoader.load_skill(skill_name, base_dir)
    if not detail then
        return nil, err
    end

    -- 更新缓存
    detail_cache[skill_name] = {
        data = detail,
        time = os.time()
    }

    return detail
end

-- 读取技能资源
function M.get_skill_resource(skill_name, resource_type, resource_name, base_dir)
    return SkillLoader.load_skill_resource(skill_name, resource_type, resource_name, base_dir)
end

-- 刷新技能注册表
function M.refresh_registry(base_dir)
    registry_cache = nil
    registry_cache_time = 0
    detail_cache = {}
    return M.get_skill_registry(base_dir)
end

-- 列出所有技能名称
function M.list_skills(base_dir)
    local registry = M.get_skill_registry(base_dir)
    local names = {}
    for name, _ in pairs(registry) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- 搜索技能（按名称、描述或触发词）
function M.search_skills(query, base_dir)
    local registry = M.get_skill_registry(base_dir)
    local results = {}

    query = query:lower()

    for name, skill in pairs(registry) do
        local match = false

        -- 检查名称
        if name:lower():find(query, 1, true) then
            match = true
        end

        -- 检查描述
        if not match and skill.description and skill.description:lower():find(query, 1, true) then
            match = true
        end

        -- 检查触发词
        if not match and skill.triggers then
            for _, trigger in ipairs(skill.triggers) do
                if trigger:lower():find(query, 1, true) then
                    match = true
                    break
                end
            end
        end

        if match then
            results[name] = skill
        end
    end

    return results
end

-- 检查技能是否存在
function M.skill_exists(skill_name, base_dir)
    local registry = M.get_skill_registry(base_dir)
    return registry[skill_name] ~= nil
end

-- 获取技能简要信息
function M.get_skill_summary(skill_name, base_dir)
    local registry = M.get_skill_registry(base_dir)
    return registry[skill_name]
end

return M