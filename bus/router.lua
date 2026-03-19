-- RlizX Message Router
-- 简化的消息路由系统

local M = {}

local message_queue = {}

-- 发送消息
function M.send(agent_name, message, config)
  local Loop = require("rlizx.agent.loop")
  
  local response, err = Loop.run(agent_name, message, config)
  
  if not response then
    return nil, err
  end
  
  return response
end

-- 接收消息（用于渠道）
function M.receive(callback)
  message_queue[#message_queue + 1] = callback
end

-- 处理队列中的消息
function M.process_queue(config)
  local responses = {}
  
  for i, callback in ipairs(message_queue) do
    local ok, response = pcall(callback, config)
    if ok then
      responses[#responses + 1] = response
    end
  end
  
  message_queue = {}
  return responses
end

return M