#!/usr/bin/env lua
-- RlizX AI 助手演示

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

print("🤖 RlizX v2.0 - AI 助手演示")
print("=" .. string.rep("=", 60))

-- 加载必要的模块
local Config = dofile(base_dir .. "/config/schema.lua")
local Registry = dofile(base_dir .. "/tools/registry.lua")
local Heartbeat = dofile(base_dir .. "/scheduler/heartbeat.lua")
local Bus = dofile(base_dir .. "/bus/router.lua")

-- 加载工具
dofile(base_dir .. "/tools/loader.lua")

-- 注册文件操作工具
local FileOps = dofile(base_dir .. "/tools/file_ops.lua")

print("\n📝 演示场景：AI 助手帮助管理任务")
print("-" .. string.rep("-", 60))

-- 场景 1: 用户要求 AI 添加一个任务
print("\n场景 1: 用户添加任务")
print("用户: 帮我添加一个每天早上8点检查邮件的任务")

-- 模拟 AI 处理
print("AI: 好的，我来帮你添加这个任务...")
Heartbeat.add_task("每天早上8点检查邮件")
print("✓ AI 已添加任务到 Heartbeat")

-- 场景 2: 用户要求 AI 列出所有任务
print("\n场景 2: 用户查看任务列表")
print("用户: 显示我的所有任务")

local tasks = Heartbeat.read_tasks()
print("AI: 你的任务列表如下：")
for i, task in ipairs(tasks) do
  local status = task.done and "✓" or "○"
  local text = task.text or "（空任务）"
  print("  ", status, (i) .. ".", text)
end

-- 场景 3: 用户要求 AI 创建一个工作计划文件
print("\n场景 3: 用户创建工作计划")
print("用户: 帮我创建一个工作计划文件")

print("AI: 好的，我来创建工作计划...")
FileOps.write_file({
  path = base_dir .. "/workspace/工作计划.md",
  content = [[# 工作计划

## 今日任务
- [ ] 检查邮件
- [ ] 回复重要消息
- [ ] 完成项目文档
- [ ] 代码审查

## 本周目标
- [ ] 完成功能开发
- [ ] 修复已知 bug
- [ ] 优化性能

## 长期规划
- [ ] 学习新技术
- [ ] 参与开源项目
]]
}, {})
print("✓ AI 已创建工作计划文件")

-- 场景 4: 用户要求 AI 读取文件内容
print("\n场景 4: 用户查看文件内容")
print("用户: 显示工作计划的内容")

local plan_content = FileOps.read_file({
  path = base_dir .. "/workspace/工作计划.md"
}, {})
if plan_content.result then
  print("AI: 工作计划内容如下：")
  print("---")
  print(plan_content.result)
  print("---")
else
  print("AI: 读取文件失败:", plan_content.error)
end

-- 场景 5: 用户要求 AI 添加定时任务
print("\n场景 5: 用户添加定时任务")
print("用户: 添加一个每周五下午5点的提醒")

print("AI: 好的，我来添加定时任务...")
local Cron = dofile(base_dir .. "/scheduler/cron.lua")
Cron.add_job("friday_reminder", "周五下午5点提醒", "0 17 * * 5")
print("✓ AI 已添加定时任务")

-- 场景 6: 用户要求 AI 查看定时任务
print("\n场景 6: 用户查看定时任务")
print("用户: 显示所有定时任务")

local jobs = Cron.list_jobs()
print("AI: 你的定时任务如下：")
if #jobs == 0 then
  print("  （暂无定时任务）")
else
  for i, job in ipairs(jobs) do
    print("  ", (i) .. ".", "[" .. job.id .. "]", job.name, "-", job.message, "(" .. job.cron .. ")")
  end
end

-- 场景 7: AI 总结
print("\n场景 7: AI 总结")
print("用户: 总结一下刚才的操作")

print("AI: 好的，我来总结一下：")
print("  1. ✓ 添加了 Heartbeat 任务：每天早上8点检查邮件")
print("  2. ✓ 查看了所有任务列表")
print("  3. ✓ 创建了工作计划文件")
print("  4. ✓ 读取了工作计划内容")
print("  5. ✓ 添加了定时任务：每周五下午5点提醒")
print("  6. ✓ 查看了所有定时任务")
print("\n所有操作都已完成！")

print("\n" .. string.rep("=", 62))
print("🎉 演示完成！")
print("\n💡 RlizX AI 助手特点：")
print("  • 文件驱动的任务管理（Heartbeat）")
print("  • 强大的文件操作能力")
print("  • 灵活的定时任务系统")
print("  • 消息驱动的架构")
print("  • 极简而强大的设计")
print("\n🚀 你的 AI 助手已准备就绪！")