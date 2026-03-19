#!/usr/bin/env lua
-- 测试 Telegram Bot API 连接

package.path = package.path .. ";./providers/?.lua;./?.lua"

local Telegram = dofile("providers/telegram.lua")

print("=== Telegram Bot API 测试 ===\n")

-- 检查是否提供了 bot_token
local bot_token = arg[1]

if not bot_token or bot_token == "" then
  print("❌ 错误: 未提供 Bot Token")
  print("\n用法: lua test_telegram.lua <YOUR_BOT_TOKEN>")
  print("\n或设置环境变量:")
  print("export TELEGRAM_BOT_TOKEN='your_bot_token'")
  print("lua test_telegram.lua")
  os.exit(1)
end

print("Bot Token:", bot_token:sub(1, 10) .. "...")
print()

-- 测试 1: 获取 Bot 信息
print("1. 测试 getMe")
local bot_info, err = Telegram.get_me(bot_token)
if err then
  print("   ❌ 失败:", err)
  os.exit(1)
end

print("   ✓ 成功")
print("   Bot 名称:", bot_info.first_name)
print("   Bot 用户名:", "@" .. bot_info.username)
print("   Bot ID:", bot_info.id)
print()

-- 测试 2: 获取更新（无阻塞，短超时）
print("2. 测试 getUpdates (短超时)")
local updates, err = Telegram.get_updates(bot_token, nil, 2)
if err then
  print("   ❌ 失败:", err)
else
  print("   ✓ 成功")
  print("   获取到", #updates, "条更新")
  if #updates > 0 then
    print("   最新更新 ID:", updates[#updates].update_id)
  end
end
print()

-- 测试 3: 发送消息（需要提供 chat_id）
if arg[2] then
  local chat_id = arg[2]
  print("3. 测试 sendMessage")
  print("   Chat ID:", chat_id)

  local result, err = Telegram.send_message(bot_token, chat_id,
    "*RlizX Telegram Bot 测试* 🤖\n\n" ..
    "✅ Bot 已成功连接到 Telegram API\n" ..
    "📡 长轮询功能正常\n" ..
    "🎉 准备就绪！")

  if err then
    print("   ❌ 失败:", err)
  else
    print("   ✓ 成功")
    print("   消息 ID:", result.message_id)
  end
  print()
else
  print("3. 跳过 sendMessage 测试（未提供 chat_id）")
  print("   提示: 可以向你的 Bot 发送任意消息获取 chat_id")
  print("   用法: lua test_telegram.lua <TOKEN> <CHAT_ID>")
  print()
end

print("=== 测试完成 ===")
print("\n下一步:")
print("1. 在 rlizx.config.json 中配置 telegram.bot_token")
print("2. 运行: lua telegram_bot.lua")
print("3. 在 Telegram 中与你的 Bot 对话")