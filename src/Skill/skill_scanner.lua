-- RlizX Skill Scanner
-- 负责扫描 skills 目录，解析 SKILL.md 元数据，构建技能注册表

local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/../Hub/utils.lua")

local M = {}

-- 解析 SKILL.md 文件的元数据部分
local function parse_skill_metadata(skill_name, skill_path)
    local skill_file = skill_path .. "/SKILL.md"
    local content = U.read_file(skill_file)
    if not content then
        return nil, "SKILL.md not found"
    end

    local metadata = {
        name = skill_name,
        version = "",
        author = "",
        category = "",
        description = "",
        triggers = {},
        dependencies = {
            scripts = false,
            references = false,
            assets = false
        }
    }

    -- 解析元数据字段
    local in_metadata = false
    for line in content:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed == "## 元数据" then

                in_metadata = true

              elseif in_metadata then

                if trimmed:sub(1, 2) == "##" then

                  -- 退出元数据部分

                  in_metadata = false

                  -- 检查是否是描述部分

                  if trimmed:match("^##%s*描述") then

                    -- 提取描述（第一段）

                    local desc_pattern = "## 描述%s*\n(.-)%s*\n##"

                    local desc_match = content:match(desc_pattern)

                    if desc_match then

                      metadata.description = desc_match:match("^%s*(.-)%s*$") or ""

                    else

                      -- 尝试另一种模式

                      local desc_start = content:find(trimmed, 1, true) + #trimmed

                      local next_section = content:find("\n##", desc_start)

                      if next_section then

                        metadata.description = content:sub(desc_start, next_section - 1):match("^%s*(.-)%s*$") or ""

                      else

                        metadata.description = content:sub(desc_start):match("^%s*(.-)%s*$") or ""

                      end

                    end

                    break

                  end

                else

                  -- 解析元数据

                  local key, value = trimmed:match("^%s*-%s*([^:]+):%s*(.+)$")

                  if key and value then

                    key = key:match("^%s*(.-)%s*$")

                    value = value:match("^%s*(.-)%s*$")

                    if key == "Version" then

                      metadata.version = value

                    elseif key == "Author" then

                      metadata.author = value

                    elseif key == "Category" then

                      metadata.category = value

                    elseif key == "Triggers" then

                      -- 解析触发关键词列表

                      for trigger in value:gmatch("[^,]+") do

                        local t = trigger:match("^%s*(.-)%s*$")

                        if t ~= "" then

                          table.insert(metadata.triggers, t)

                        end

                      end

                    end

                  end

                end

              elseif trimmed:match("^##%s*描述") then

                -- 提取描述（第一段）

                local desc_pattern = "## 描述%s*\n(.-)%s*\n##"

                local desc_match = content:match(desc_pattern)

                if desc_match then

                  metadata.description = desc_match:match("^%s*(.-)%s*$") or ""

                else

                  -- 尝试另一种模式

                  local desc_start = content:find(trimmed, 1, true) + #trimmed

                  local next_section = content:find("\n##", desc_start)

                  if next_section then

                    metadata.description = content:sub(desc_start, next_section - 1):match("^%s*(.-)%s*$") or ""

                  else

                    metadata.description = content:sub(desc_start):match("^%s*(.-)%s*$") or ""

                  end

                end

                break

              end    end

    -- 检查依赖资源目录
    local deps = metadata.dependencies
    local check_cmd = "test -d '" .. skill_path .. "/scripts' && echo 'exists' || echo 'notfound'"
    local pipe = io.popen(check_cmd)
    if pipe then
      local result = pipe:read("*all")
      pipe:close()
      deps.scripts = result:match("exists") ~= nil
    end

    check_cmd = "test -d '" .. skill_path .. "/references' && echo 'exists' || echo 'notfound'"
    pipe = io.popen(check_cmd)
    if pipe then
      local result = pipe:read("*all")
      pipe:close()
      deps.references = result:match("exists") ~= nil
    end

    check_cmd = "test -d '" .. skill_path .. "/assets' && echo 'exists' || echo 'notfound'"
    pipe = io.popen(check_cmd)
    if pipe then
      local result = pipe:read("*all")
      pipe:close()
      deps.assets = result:match("exists") ~= nil
    end

    return metadata
end

-- 扫描 skills 目录，构建技能注册表
function M.scan_skills(base_dir)
    local skills_path = base_dir .. "/../../skills"
    local registry = {}

    -- 检查 skills 目录是否存在
    local skills_check = io.popen("ls -d '" .. skills_path .. "' 2>/dev/null")
    if not skills_check then
        return registry
    end
    local result = skills_check:read("*all")
    skills_check:close()
    if result == "" then
        return registry
    end

    -- 列出技能目录
    local list_cmd = "find '" .. skills_path .. "' -mindepth 1 -maxdepth 1 -type d"
    local pipe = io.popen(list_cmd)
    if not pipe then
        return registry
    end

    for line in pipe:lines() do
        local skill_path = line:match("^%s*(.-)%s*$")
        if skill_path then
            local skill_name = skill_path:match("/([^/]+)$")
            if skill_name and skill_name ~= "" then
                local metadata = parse_skill_metadata(skill_name, skill_path)
                if metadata then
                    registry[skill_name] = metadata
                end
            end
        end
    end
    pipe:close()

    return registry
end

return M