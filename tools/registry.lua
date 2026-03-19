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

-- JSON 编码（简化版）
function M.encode_json(v)
  local tv = type(v)
  if tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    return tostring(v)
  elseif tv == "string" then
    return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\\"') .. '"'
  elseif tv == "table" then
    local is_array = #v > 0
    local parts = {}
    
    if is_array then
      for i = 1, #v do
        parts[#parts + 1] = M.encode_json(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local keys = {}
      for k, _ in pairs(v) do
        keys[#keys + 1] = k
      end
      table.sort(keys)
      
      for _, k in ipairs(keys) do
        parts[#parts + 1] = '"' .. tostring(k) .. '":' .. M.encode_json(v[k])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  
  return '""'
end

-- JSON 解码（简化版）
function M.decode_json(s)
  -- 简化版，实际应该使用更完整的解析器
  -- 这里只处理简单的 JSON
  local ok, data = pcall(loadstring or load, "return " .. s)
  if ok and type(data) == "function" then
    return data()
  end
  return nil
end

return M