#!/usr/bin/env lua
-- Shell 工具 AI 演示
-- 展示 AI 如何使用 shell 工具执行各种操作

package.path = package.path .. ";./tools/?.lua;./?.lua"

local Registry = dofile("./tools/loader.lua")

print("=== RlizX Shell 工具 AI 演示 ===\n")

-- 模拟 AI 用户的请求
local user_requests = {
  {
    request = "帮我查看当前目录下有哪些文件",
    ai_reasoning = "用户想查看当前目录的文件，我应该使用 shell_execute 执行 ls 命令",
    tool = "shell_execute",
    args = { command = "ls -la" }
  },
  {
    request = "检查一下 git 状态",
    ai_reasoning = "用户想查看 git 状态，我应该使用 shell_execute 执行 git status",
    tool = "shell_execute",
    args = { command = "git status --short" }
  },
  {
    request = "当前工作目录在哪里？",
    ai_reasoning = "用户想知道当前工作目录，我应该使用 shell_pwd 工具",
    tool = "shell_pwd",
    args = {}
  },
  {
    request = "检查一下 lua 命令是否存在",
    ai_reasoning = "用户想检查 lua 命令是否可用，我应该使用 shell_which 工具",
    tool = "shell_which",
    args = { command = "lua" }
  },
  {
    request = "查看一下 HOME 环境变量",
    ai_reasoning = "用户想查看 HOME 环境变量，我应该使用 shell_getenv 工具",
    tool = "shell_getenv",
    args = { name = "HOME" }
  },
  {
    request = "在 /tmp 目录下创建一个测试文件",
    ai_reasoning = "用户想在 /tmp 目录下创建文件，我应该使用 shell_execute 指定工作目录",
    tool = "shell_execute",
    args = {
      command = "echo 'Hello from RlizX' > test_file.txt && cat test_file.txt",
      working_dir = "/tmp"
    }
  },
  {
    request = "帮我执行一个危险命令：rm -rf /",
    ai_reasoning = "这是一个危险命令，系统应该自动阻止它",
    tool = "shell_execute",
    args = { command = "rm -rf /" }
  }
}

-- 模拟 AI 处理用户请求
for i, scenario in ipairs(user_requests) do
  print(string.format("--- 场景 %d ---", i))
  print("用户请求:", scenario.request)
  print("AI 思考:", scenario.ai_reasoning)
  
  -- AI 执行工具
  local result = Registry.execute(scenario.tool, scenario.args)
  
  -- AI 生成响应
  if result.error then
    print(string.format("AI 回复: ❌ %s", result.error))
    if result.suggestion then
      print("提示:", result.suggestion)
    end
  else
    if result.success then
      print("AI 回复: ✓ 执行成功")
    else
      print("AI 回复: ✗ 执行失败")
    end
    
    -- 格式化输出结果
    if result.output and result.output ~= "" then
      local output = result.output:gsub("\n$", "")
      if #output > 100 then
        output = output:sub(1, 97) .. "..."
      end
      print("结果:", output)
    end
    
    if result.path then
      print("路径:", result.path)
    end
    
    if result.found ~= nil then
      print("找到:", result.found and "是" or "否")
      if result.path then
        print("位置:", result.path)
      end
    end
    
    if result.value then
      print("值:", result.value)
    end
    
    if result.exit_code then
      print("退出码:", result.exit_code)
    end
  end
  
  print()
end

print("=== 演示完成 ===")
print("\nAI 可以使用以下 shell 工具：")
local tools = Registry.get_all_tools_definitions()
for i, tool in ipairs(tools) do
  if tool.name:find("shell") then
    print(string.format("  • %s - %s", tool.name, tool.description))
  end
end