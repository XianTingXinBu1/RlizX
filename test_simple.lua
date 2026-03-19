#!/usr/bin/env lua
-- 简单测试工具注册

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local base_dir = get_script_dir()

print("测试工具注册...")

-- 直接加载注册表
local Registry = dofile(base_dir .. "/tools/registry.lua")

-- 注册一个测试工具
Registry.register("test_tool", {
  name = "test_tool",
  description = "测试工具"
}, function(args, context)
  return { result = "测试成功" }
end)

-- 检查工具数量
local tools = Registry.get_all_tools_definitions()
print("已注册工具数量:", #tools)

for i, tool in ipairs(tools) do
  print(string.format("  %d. %s - %s", i, tool.name, tool.description))
end

-- 测试执行
print("\n测试执行工具...")
local result = Registry.execute("test_tool", {}, {})
print("执行结果:", result.result or result.error)

-- 现在加载所有工具
print("\n加载所有工具...")
dofile(base_dir .. "/tools/loader.lua")

local all_tools = Registry.get_all_tools_definitions()
print("加载后工具数量:", #all_tools)

for i, tool in ipairs(all_tools) do
  print(string.format("  %d. %s - %s", i, tool.name, tool.description))
end

print("\n✅ 测试完成！")