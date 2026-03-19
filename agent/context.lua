-- RlizX Context Builder
-- 构建系统提示词

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- 构建系统提示词
function M.build(agent_name, config)
  local parts = {}
  
  -- 1. 加载角色设定
  local role_file = string.format("agents/%s/.rlizx/role.txt", agent_name)
  local role = read_file(role_file)
  if role and role ~= "" then
    parts[#parts + 1] = role
  else
    parts[#parts + 1] = "你是一个有用的 AI 助手。"
  end
  
  -- 2. 添加工具说明
  local tools = require("rlizx.tools.registry").get_all_tools_definitions()
  if #tools > 0 then
    parts[#parts + 1] = "\n可用工具："
    for _, tool in ipairs(tools) do
      parts[#parts + 1] = string.format("- %s: %s", tool.name, tool.description)
    end
  end
  
  -- 3. 添加工作区信息
  local workspace = os.getenv("PWD") or "."
  parts[#parts + 1] = string.format("\n工作区: %s", workspace)
  
  return table.concat(parts, "\n")
end

return M