#!/usr/bin/env lua
-- RlizX 简化测试脚本

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

print("RlizX v2.0.0 - 基于 nanobot 架构重构")
print("=" .. string.rep("=", 40))

-- 测试 1: 工具加载
print("\n测试 1: 工具加载")
local Registry = dofile(base_dir .. "/tools/registry.lua")
local tools = Registry.get_all_tools_definitions()
print(string.format("已加载 %d 个工具", #tools))
for _, tool in ipairs(tools) do
  print(string.format("  - %s: %s", tool.name, tool.description))
end

-- 测试 2: 配置加载
print("\n测试 2: 配置加载")
local Config = dofile(base_dir .. "/config/schema.lua")
local config = Config.get_current()
print(string.format("Provider: %s", config.provider or "未设置"))
print(string.format("Model: %s", config.model or "未设置"))
print(string.format("API Key: %s", config.api_key and "***" or "未设置"))

-- 测试 3: Heartbeat 系统
print("\n测试 3: Heartbeat 系统")
local Heartbeat = dofile(base_dir .. "/scheduler/heartbeat.lua")
Heartbeat.add_task("测试任务 1")
Heartbeat.add_task("测试任务 2")
local tasks = Heartbeat.read_tasks()
print(string.format("已添加 %d 个任务", #tasks))
for _, task in ipairs(tasks) do
  print(string.format("  - [%s] %s", task.done and "x" or " ", task.text))
end

-- 测试 4: Cron 系统
print("\n测试 4: Cron 系统")
local Cron = dofile(base_dir .. "/scheduler/cron.lua")
Cron.add_job("测试定时任务", "执行测试", "* * * * *")
local jobs = Cron.list_jobs()
print(string.format("已添加 %d 个定时任务", #jobs))
for _, job in ipairs(jobs) do
  print(string.format("  - [%s] %s - %s (%s)", job.id, job.name, job.message, job.cron))
end

print("\n" .. string.rep("=", 42))
print("所有测试完成！")