-- RlizX Telegram Bot Provider
-- 支持长轮询模式

local M = {}

-- 使用当前工作目录作为项目根目录
local base_dir = "."

-- 加载 utils 模块（包含 cjson）
local U = dofile(base_dir .. "/src/Hub/utils.lua")

-- Telegram Bot API 端点
local API_BASE = "https://api.telegram.org/bot%s/%s"

-- 获取 API URL
local function api_url(bot_token, method)
  return string.format(API_BASE, bot_token, method)
end

-- 发送 HTTP POST 请求（使用 curl）
local function http_post(url, body)
  local cmd = string.format('curl -s -X POST "%s" -H "Content-Type: application/json"', url)

  if body then
    cmd = cmd .. string.format(' -d \'%s\'', body)
  end

  local p = io.popen(cmd)
  if not p then
    return nil, "无法执行 curl 命令"
  end

  local response_body = p:read("*a")
  local success = { p:close() }

  -- 获取退出码
  local exit_code = success[3] or success[1] or 0

  if exit_code ~= 0 then
    return nil, "HTTP 请求失败，退出码: " .. exit_code
  end

  return {
    code = 200,
    body = response_body
  }
end

-- 发送 Telegram API 请求
local function api_request(bot_token, method, data)
  local url = api_url(bot_token, method)
  local body = data and U.json_encode(data) or nil

  local response, err = http_post(url, body)
  if err then
    return nil, "API 请求失败: " .. err
  end

  if not response or response.code ~= 200 then
    return nil, "API 错误: " .. (response.body or "未知错误")
  end

  -- 使用 cjson 解析响应
  local result, err = U.json_parse(response.body)
  if err then
    return nil, "JSON 解析失败: " .. err
  end

  -- 检查 API 是否返回错误
  if not result.ok then
    return nil, "Telegram API 错误: " .. (result.description or "未知错误")
  end

  -- 返回 result 字段
  return result.result
end

-- 获取 Bot 信息
function M.get_me(bot_token)
  return api_request(bot_token, "getMe", nil)
end

-- 获取更新（长轮询）
function M.get_updates(bot_token, offset, timeout, allowed_updates)
  local data = {
    timeout = timeout or 30,
    allowed_updates = allowed_updates or {"message"}
  }

  if offset then
    data.offset = offset
  end

  return api_request(bot_token, "getUpdates", data)
end

-- 发送消息
function M.send_message(bot_token, chat_id, text, options)
  local data = {
    chat_id = chat_id,
    text = text,
    parse_mode = "Markdown"
  }

  -- 合并选项
  if options then
    for k, v in pairs(options) do
      data[k] = v
    end
  end

  return api_request(bot_token, "sendMessage", data)
end

-- 发送聊天动作
function M.send_chat_action(bot_token, chat_id, action)
  local data = {
    chat_id = chat_id,
    action = action -- typing, upload_photo, record_video, etc.
  }

  return api_request(bot_token, "sendChatAction", data)
end

-- 回复消息
function M.reply_message(bot_token, chat_id, message_id, text, options)
  local data = {
    chat_id = chat_id,
    text = text,
    parse_mode = "Markdown",
    reply_to_message_id = message_id
  }

  if options then
    for k, v in pairs(options) do
      data[k] = v
    end
  end

  return api_request(bot_token, "sendMessage", data)
end

-- 处理 Telegram 消息
function M.process_message(update)
  if not update.message then
    return nil
  end

  local message = update.message
  local chat_id = message.chat.id
  local user_id = message.from.id
  local text = message.text
  local username = message.from.username or message.from.first_name or "Unknown"

  return {
    chat_id = chat_id,
    user_id = user_id,
    username = username,
    text = text,
    message_id = message.message_id,
    update_id = update.update_id,
    raw = update
  }
end

-- 长轮询循环
function M.start_polling(bot_token, message_handler, options)
  options = options or {}

  local offset = 0
  local timeout = options.timeout or 30
  local poll_interval = options.poll_interval or 1
  local running = true

  -- 获取 Bot 信息
  local bot_info = M.get_me(bot_token)
  if not bot_info then
    return false, "无法获取 Bot 信息，请检查 token"
  end

  print(string.format("✓ Telegram Bot 已启动: @%s", bot_info.username))
  print("开始长轮询，按 Ctrl+C 停止...\n")

  -- 长轮询主循环
  while running do
    local updates = M.get_updates(bot_token, offset, timeout)

    if updates and #updates > 0 then
      for _, update in ipairs(updates) do
        -- 更新 offset
        offset = update.update_id + 1

        -- 处理消息
        local message = M.process_message(update)
        if message and message.text then
          print(string.format("[@%s] %s: %s",
            bot_info.username,
            message.username,
            message.text))

          -- 调用消息处理器
          local ok, response = pcall(message_handler, message)
          if not ok then
            print("❌ 消息处理错误:", response)
          end
        end
      end
    end

    -- 短暂休眠避免频繁请求
    os.execute("sleep " .. poll_interval)
  end

  return true
end

-- 简化的启动函数
function M.start(bot_token, config, router)
  if not bot_token or bot_token == "" then
    return false, "缺少 bot_token"
  end

  -- 消息处理器
  local function handle_message(message)
    -- 发送正在输入提示
    M.send_chat_action(bot_token, message.chat_id, "typing")

    -- 提取用户 ID 作为 agent 名称
    local agent_name = "telegram_user_" .. message.user_id

    -- 通过路由系统发送消息
    local response, err = router.send(agent_name, message.text, config)

    if err then
      M.reply_message(bot_token, message.chat_id, message.message_id,
        "❌ 处理失败: " .. err)
      return
    end

    -- 发送响应
    if response then
      -- 如果响应太长，分段发送
      local max_length = 4096
      local chunks = {}

      for i = 1, #response, max_length do
        chunks[#chunks + 1] = response:sub(i, i + max_length - 1)
      end

      for i, chunk in ipairs(chunks) do
        M.reply_message(bot_token, message.chat_id, message.message_id, chunk)
      end
    end
  end

  -- 启动长轮询
  return M.start_polling(bot_token, handle_message, {
    timeout = 30,
    poll_interval = 1
  })
end

return M