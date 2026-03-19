#!/usr/bin/env lua
-- 测试完整的 Telegram Bot 流程

package.path = package.path .. ";./providers/?.lua;./bus/?.lua;./agent/?.lua;./tools/?.lua;./config/?.lua;./?.lua"

print("=== Telegram Bot 完整测试 ===\n")

-- 1. 测试配置加载
print("1. 测试配置加载")
local f = io.open("rlizx.config.json", "r")
if not f then
  print("   ❌ 无法打开配置文件")
  os.exit(1)
end
local config_content = f:read("*a")
f:close()

local ok, cjson = pcall(require, "cjson")
if not ok then
  print("   ❌ 无法加载 cjson")
  os.exit(1)
end

local config, err = cjson.decode(config_content)
if not config then
  print("   ❌ 无法解析配置:", err)
  os.exit(1)
end

print("   ✓ 配置加载成功")
print("   Provider:", config.provider)
print("   Model:", config.model)
print("   Bot Token:", config.telegram and config.telegram.bot_token and "已配置" or "未配置")
print()

-- 2. 测试 Telegram API 连接
print("2. 测试 Telegram API 连接")
local Telegram = dofile("providers/telegram.lua")

local bot_token = config.telegram and config.telegram.bot_token
if not bot_token or bot_token == "" then
  print("   ❌ 未配置 Bot Token")
  os.exit(1)
end

local bot_info, err = Telegram.get_me(bot_token)
if err then
  print("   ❌ 获取 Bot 信息失败:", err)
  os.exit(1)
end

print("   ✓ Bot 信息获取成功")
print("   名称:", bot_info.first_name)
print("   用户名:", "@" .. bot_info.username)
print("   ID:", bot_info.id)
print()

-- 3. 测试获取更新
print("3. 测试获取更新")
local updates, err = Telegram.get_updates(bot_token, nil, 2)
if err then
  print("   ❌ 获取更新失败:", err)
  os.exit(1)
end

print("   ✓ 获取更新成功")
print("   更新数量:", #updates)
if #updates > 0 then
  print("   最新更新 ID:", updates[#updates].update_id)
  local update = updates[#updates]
  if update.message then
    print("   最新消息:", update.message.text or "(非文本消息)")
  end
end
print()

-- 4. 测试 Router
print("4. 测试 Router 模块")
local Router = dofile("bus/router.lua")
print("   ✓ Router 模块加载成功")
print()

-- 5. 测试 Agent Loop
print("5. 测试 Agent Loop 模块")
local Loop = dofile("agent/loop.lua")
print("   ✓ Agent Loop 模块加载成功")
print()

-- 6. 总结
print("=" .. string.rep("=", 50))
print("✓ 所有测试通过！")
print("=" .. string.rep("=", 50))
print()
print("下一步:")
print("运行: lua telegram_bot.lua")
print("然后在 Telegram 中与 @" .. bot_info.username .. " 对话")