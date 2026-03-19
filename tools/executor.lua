-- RlizX Tools Executor
-- 工具执行和 LLM 调用

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local Registry
local function get_registry()
  if not Registry then
    Registry = dofile(get_script_dir() .. "/registry.lua")
  end
  return Registry
end

-- 调用 LLM
function M.call_llm(system_prompt, messages, config)
  local http = dofile(get_script_dir() .. "/../providers/registry.lua")
  return http.request(config, system_prompt, messages)
end

-- 解析工具调用
function M.parse_tool_calls(response)
  local calls = {}
  
  -- 简单的解析：查找 <tool_name>...args...</tool_name> 格式
  for name, args in response:gmatch("<(%w+)>(.-)</(%w+)>") do
    calls[#calls + 1] = {
      id = tostring(#calls + 1),
      name = name,
      arguments = args
    }
  end
  
  return calls
end

-- 执行工具
function M.execute(name, arguments, context)
  return get_registry().execute(name, arguments, context)
end

-- 格式化结果
function M.format_result(result)
  if type(result) == "table" then
    if result.error then
      return "Error: " .. result.error
    elseif result.result then
      return tostring(result.result)
    else
      return get_registry().encode_json(result)
    end
  end
  return tostring(result)
end

return M