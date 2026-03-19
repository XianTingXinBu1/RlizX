-- RlizX Skill Index
-- 负责管理技能索引缓存，避免每次全扫描

local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/../Hub/utils.lua")

local M = {}

-- 获取索引文件路径
local function get_index_path(base_dir)
    return base_dir .. "/../../skills/.skills_index.json"
end

-- 加载索引文件
function M.load_index(base_dir)
    local index_path = get_index_path(base_dir)
    local content = U.read_file(index_path)

    if not content then
        return nil
    end

    local ok, parsed = pcall(U.json_parse, content)
    if not ok or type(parsed) ~= "table" then
        return nil
    end

    return parsed
end

-- 保存索引文件
function M.save_index(base_dir, index_data)
    local index_path = get_index_path(base_dir)

    -- 简单的 JSON 编码（仅支持基本类型）
    local function encode_json(data, indent)
        indent = indent or ""
        local t = type(data)

        if t == "nil" then
            return "null"
        elseif t == "boolean" then
            return data and "true" or "false"
        elseif t == "number" then
            return tostring(data)
        elseif t == "string" then
            return '"' .. U.json_escape(data) .. '"'
        elseif t == "table" then
            local is_array = true
            local i = 1
            for k, _ in pairs(data) do
                if k ~= i then
                    is_array = false
                    break
                end
                i = i + 1
            end

            local parts = {}
            if is_array then
                for _, item in ipairs(data) do
                        parts[#parts + 1] = encode_json(item, indent .. "  ")
                      end                return "[" .. (#parts > 0 and "\n" .. indent .. "  " or "") ..
                       table.concat(parts, ",\n" .. indent .. "  ") ..
                       (#parts > 0 and "\n" .. indent or "") .. "]"
            else
                local keys = {}
                for k in pairs(data) do
                    keys[#keys + 1] = k
                end
                table.sort(keys)

                for _, k in ipairs(keys) do
                    parts[#parts + 1] = indent .. "  " .. encode_json(k, indent .. "  ") .. ": " ..
                                          encode_json(data[k], indent .. "  ")
                end
                return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
            end
        end

        return "null"
    end

    local json_content = encode_json(index_data)

    return U.write_file(index_path, json_content)
end

-- 获取索引时间戳
function M.get_index_timestamp(base_dir)
    local index = M.load_index(base_dir)
    if not index or not index.timestamp then
        return 0
    end
    return tonumber(index.timestamp) or 0
end

-- 更新索引
function M.update_index(base_dir, skill_registry)
    local index_data = {
        timestamp = os.time(),
        skills = {}
    }

    -- 提取技能注册表的关键信息
    for name, skill in pairs(skill_registry) do
        index_data.skills[name] = {
            name = skill.name,
            version = skill.version,
            author = skill.author,
            category = skill.category,
            description = skill.description,
            triggers = skill.triggers or {},
            dependencies = skill.dependencies or {}
        }
    end

    return M.save_index(base_dir, index_data)
end

-- 检查索引是否需要更新
function M.needs_update(base_dir)
    local index_path = get_index_path(base_dir)

    -- 如果索引文件不存在，需要更新
    local check_cmd = "test -f '" .. index_path .. "' && echo 'exists' || echo 'notfound'"
    local pipe = io.popen(check_cmd)
    if not pipe then
        return true
    end
    local result = pipe:read("*all")
    pipe:close()

    if result:match("notfound") then
        return true
    end

    -- 检查 skills 目录的修改时间
    local skills_path = base_dir .. "/../../skills"
    local stat_cmd = "stat -c %Y '" .. skills_path .. "' 2>/dev/null || echo '0'"
    pipe = io.popen(stat_cmd)
    if not pipe then
        return true
    end
    local skills_mtime = tonumber(pipe:read("*all")) or 0
    pipe:close()

    local index_timestamp = M.get_index_timestamp(base_dir)

    return skills_mtime > index_timestamp
end

return M