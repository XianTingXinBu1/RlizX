#!/usr/bin/env lua
-- RlizX AI 测试脚本

-- 添加模块路径
local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local base_dir = get_script_dir()
package.path = base_dir .. "/?.lua;" .. base_dir .. "/agent/?.lua;" .. base_dir .. "/tools/?.lua;" .. base_dir .. "/scheduler/?.lua;" .. base_dir .. "/config/?.lua;" .. base_dir .. "/providers/?.lua;" .. base_dir .. "/bus/?.lua;" .. base_dir .. "/cli/?.lua;" .. package.path

print("RlizX v2.0 - AI 测试")
print("=" .. string.rep("=", 50))

-- 测试 1: 初始化配置
print("\n测试 1: 初始化配置")
local Config = dofile(base_dir .. "/config/schema.lua")
local default = Config.get_default()
default.api_key = "sk-test-key-12345"
Config.save(default)
print("配置已保存")

-- 测试 2: 加载配置
print("\n测试 2: 加载配置")
local config = Config.get_current()
print("Provider:", config.provider)
print("Model:", config.model)
print("API Key:", string.sub(config.api_key, 1, 10) .. "...")

-- 测试 3: 工具加载
print("\n测试 3: 加载工具")
dofile(base_dir .. "/tools/loader.lua")
local Registry = dofile(base_dir .. "/tools/registry.lua")
local tools = Registry.get_all_tools_definitions()
print("已加载工具数量:", #tools)
for i, tool in ipairs(tools) do
  print(string.format("  %d. %s - %s", i, tool.name, tool.description))
end

-- 测试 4: Heartbeat 任务
print("\n测试 4: Heartbeat 任务")
local Heartbeat = dofile(base_dir .. "/scheduler/heartbeat.lua")
-- 清空旧任务
Heartbeat.write_tasks({})
-- 添加新任务
Heartbeat.add_task("检查系统状态")
Heartbeat.add_task("发送日报")
Heartbeat.add_task("更新学习笔记")
local tasks = Heartbeat.read_tasks()
print("Heartbeat 任务数量:", #tasks)
for i, task in ipairs(tasks) do
  local status = task.done and "✓" or "○"
  print(string.format("  %s %d. %s", status, i, task.text))
end

-- 测试 5: Cron 任务
print("\n测试 5: Cron 任务")
local Cron = dofile(base_dir .. "/scheduler/cron.lua")
Cron.add_job("每日报告", "生成每日工作报告", "0 9 * * *")
Cron.add_job("每周备份", "备份代码库", "0 0 * * 0")
local jobs = Cron.list_jobs()
print("Cron 任务数量:", #jobs)
for i, job in ipairs(jobs) do
  print(string.format("  %d. [%s] %s - %s (%s)", i, job.id, job.name, job.message, job.cron))
end

-- 测试 6: 模拟 AI 消息处理
print("\n测试 6: 模拟 AI 消息处理")
local Bus = dofile(base_dir .. "/bus/router.lua")
print("消息路由系统已加载")

-- 测试 7: LLM 提供商
print("\n测试 7: LLM 提供商")
local Providers = dofile(base_dir .. "/providers/registry.lua")
print("提供商注册表已加载")
local provider_names = {}
for name, _ in pairs(Providers.providers) do
  provider_names[#provider_names + 1] = name
end
print("已注册提供商:", table.concat(provider_names, ", "))

print("\n" .. string.rep("=", 52))
print("✅ 所有测试完成！")
print("\n🎉 RlizX 系统已准备就绪，可以开始使用 AI 助手了！")