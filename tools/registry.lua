-- RlizX Tools Registry
-- 简化的工具注册表

local M = {}

M.tools = {}

-- 注册工具
function M.register(name, definition, handler)
  M.tools[name] = {
    name = name,
    definition = definition,
    handler = handler
  }
end

-- 获取所有工具定义
function M.get_all_tools_definitions()
  local defs = {}
  for _, tool in pairs(M.tools) do
    defs[#defs + 1] = tool.definition
  end
  table.sort(defs, function(a, b) return a.name < b.name end)
  return defs
end

-- 执行工具
function M.execute(name, arguments, context)
  local tool = M.tools[name]
  if not tool then
    return { error = "Tool not found: " .. name }
  end
  
  local ok, result = pcall(tool.handler, arguments or {}, context or {})
  if not ok then
    return { error = "Tool execution failed: " .. tostring(result) }
  end
  
  return result
end

-- JSON 编码（使用 cjson）
function M.encode_json(v)
  local U = dofile("src/Hub/utils.lua")
  return U.json_encode(v)
end

-- JSON 解码（使用 cjson）
function M.decode_json(s)
  local U = dofile("src/Hub/utils.lua")
  return U.json_parse(s)
end

return M