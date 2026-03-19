-- RlizX Agent Loop
-- 极简的消息循环：LLM ↔ 工具执行

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

-- 加载工具
dofile(get_script_dir() .. "/../tools/loader.lua")

local Context = dofile(get_script_dir() .. "/context.lua")
local Memory = dofile(get_script_dir() .. "/memory.lua")
local Tools = dofile(get_script_dir() .. "/../tools/executor.lua")

-- 消息循环
function M.run(agent_name, user_message, config)
  -- 构建上下文
  local system_prompt = Context.build(agent_name, config)
  
  -- 加载记忆
  local conversation = Memory.get_recent(agent_name, 10)
  
  -- 添加用户消息
  conversation[#conversation + 1] = { role = "user", content = user_message }
  
  -- 调用 LLM
  local response = Tools.call_llm(system_prompt, conversation, config)
  
  if not response then
    return nil, "LLM 调用失败"
  end
  
  -- 解析工具调用
  local tool_calls = Tools.parse_tool_calls(response)
  
  if #tool_calls > 0 then
    -- 执行工具
    local tool_results = {}
    for _, call in ipairs(tool_calls) do
      local result = Tools.execute(call.name, call.arguments, config)
      tool_results[#tool_results + 1] = {
        tool_call_id = call.id,
        content = Tools.format_result(result)
      }
    end
    
    -- 将工具结果添加到对话
    conversation[#conversation + 1] = { role = "assistant", content = response }
    for _, result in ipairs(tool_results) do
      conversation[#conversation + 1] = { role = "tool", content = result.content }
    end
    
    -- 再次调用 LLM 获取最终响应
    response = Tools.call_llm(system_prompt, conversation, config)
  end
  
  -- 保存到记忆
  conversation[#conversation + 1] = { role = "assistant", content = response }
  Memory.add(agent_name, conversation)
  
  return response
end

return M