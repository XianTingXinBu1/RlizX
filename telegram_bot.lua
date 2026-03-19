#!/usr/bin/env lua
-- RlizX Telegram Bot 启动脚本

package.path = package.path .. ";./providers/?.lua;./bus/?.lua;./agent/?.lua;./tools/?.lua;./config/?.lua;./?.lua"

-- 加载模块
local Telegram = dofile("providers/telegram.lua")
local Router = dofile("bus/router.lua")

-- 读取配置文件（使用 cjson 解析）
local function load_config()
  local f = io.open("rlizx.config.json", "r")
  if not f then
    return nil
  end

  local content = f:read("*a")
  f:close()

  -- 使用 cjson 解析 JSON
  local ok, cjson = pcall(require, "cjson")
  if not ok then
    print("❌ 错误: 无法加载 cjson 库")
    print("请安装: apt-get install lua-cjson")
    return nil
  end

  local config, err = cjson.decode(content)
  if not config then
    print("❌ 错误: 无法解析配置文件:", err)
    return nil
  end

  -- 确保 telegram 字段存在
  if not config.telegram then
    config.telegram = {}
  end

  -- 设置默认值
  config.endpoint = config.endpoint or "https://api.openai.com/v1/chat/completions"
  config.model = config.model or "gpt-4"
  config.provider = config.provider or "openai"

  return config
end

local config = load_config()

-- 检查 Telegram Bot Token
local bot_token = config and config.telegram and config.telegram.bot_token

if not bot_token or bot_token == "" then
  print("❌ 错误: 未配置 Telegram Bot Token")
  print("\n请在 rlizx.config.json 中添加以下配置:")
  print([[
{
  "telegram": {
    "bot_token": "YOUR_BOT_TOKEN_HERE"
  }
}
]])
  print("\n获取 Bot Token 的步骤:")
  print("1. 在 Telegram 中找到 @BotFather")
  print("2. 发送 /newbot 创建新机器人")
  print("3. 按照提示设置机器人名称和用户名")
  print("4. 复制返回的 Bot Token")
  os.exit(1)
end

print("=== RlizX Telegram Bot ===")
print("配置加载成功")
print(string.format("Provider: %s", config and config.provider or "openai"))
print(string.format("Model: %s", config and config.model or "gpt-4"))
print()

-- 启动 Telegram Bot
local ok, err = pcall(function()
  return Telegram.start(bot_token, config, Router)
end)

if not ok then
  print("\n❌ Bot 启动失败:", err)
  os.exit(1)
end