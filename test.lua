#!/usr/bin/env lua
-- RlizX 测试脚本

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
package.path = base_dir .. "/?.lua;" .. package.path

print("RlizX v2.0.0 - 基于 nanobot 架构重构")
print("=" .. string.rep("=", 40))

-- 测试 1: 工具加载
print("\n测试 1: 工具加载")
local Registry = require("rlizx.tools.registry")
local tools = Registry.get_all_tools_definitions()
print(string.format("已加载 %d 个工具", #tools))
for _, tool in ipairs(tools) do
  print(string.format("  - %s: %s", tool.name, tool.description))
end

-- 测试 2: 配置加载
print("\n测试 2: 配置加载")
local Config = require("rlizx.config.schema")
local config = Config.get_current()
print(string.format("Provider: %s", config.provider or "未设置"))
print(string.format("Model: %s", config.model or "未设置"))
print(string.format("API Key: %s", config.api_key and "***" or "未设置"))

-- 测试 3: Heartbeat 系统
print("\n测试 3: Heartbeat 系统")
local Heartbeat = require("rlizx.scheduler.heartbeat")
Heartbeat.add_task("测试任务 1")
Heartbeat.add_task("测试任务 2")
local tasks = Heartbeat.read_tasks()
print(string.format("已添加 %d 个任务", #tasks))
for _, task in ipairs(tasks) do
  print(string.format("  - [%s] %s", task.done and "x" or " ", task.text))
end

-- 测试 4: Cron 系统
print("\n测试 4: Cron 系统")
local Cron = require("rlizx.scheduler.cron")
Cron.add_job("测试定时任务", "执行测试", "* * * * *")
local jobs = Cron.list_jobs()
print(string.format("已添加 %d 个定时任务", #jobs))
for _, job in ipairs(jobs) do
  print(string.format("  - [%s] %s - %s (%s)", job.id, job.name, job.message, job.cron))
end

print("\n" .. string.rep("=", 42))
print("所有测试完成！")