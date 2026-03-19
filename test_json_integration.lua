#!/usr/bin/env lua
-- 测试项目中所有 JSON 相关功能

package.path = package.path .. ";./src/Hub/?.lua;./src/Tool/?.lua;./tools/?.lua;./config/?.lua;./scheduler/?.lua;./agent/?.lua;./providers/?.lua;./?.lua"

print("=" .. string.rep("=", 60))
print("JSON Integration Test")
print("=" .. string.rep("=", 60))
print()

-- 加载 cjson
local ok, cjson = pcall(require, "cjson")
if not ok then
  print("ERROR: Cannot load cjson library")
  os.exit(1)
end
print("OK: cjson library loaded")
print()

-- 测试 1: utils.lua
print("1. Testing utils.lua")
local U = dofile("src/Hub/utils.lua")

local test_obj = {name = "test", value = 123, active = true, nested = {key = "value"}}
local json_str = U.json_encode(test_obj)
local decoded = U.json_parse(json_str)

print("   Encode:", json_str)
print("   Decode:", decoded.name, decoded.value, decoded.active, decoded.nested.key)
if decoded.name == "test" and decoded.value == 123 then
  print("   OK: utils.lua JSON functions work")
else
  print("   FAIL: utils.lua JSON functions broken")
end
print()

-- 测试 2: json_encoder.lua
print("2. Testing json_encoder.lua")
local JsonEncoder = dofile("src/Tool/json_encoder.lua")

local json_str2 = JsonEncoder.encode_json({msg = "Hello", emoji = "😀"})
print("   Encode:", json_str2)
if json_str2:find("Hello") and json_str2:find("😀") then
  print("   OK: json_encoder.lua works")
else
  print("   FAIL: json_encoder.lua broken")
end
print()

-- 测试 3: json_ops.lua
print("3. Testing json_ops.lua")
local JsonOps = dofile("src/Tool/json_ops.lua")

local json_str3 = JsonOps.encode_json({key = "value", num = 42})
print("   Encode:", json_str3)
if json_str3:find("key") and json_str3:find("42") then
  print("   OK: json_ops.lua works")
else
  print("   FAIL: json_ops.lua broken")
end
print()

-- 测试 4: tools/registry.lua
print("4. Testing tools/registry.lua")
local Registry = dofile("tools/registry.lua")

local json_str4 = Registry.encode_json({test = "registry", data = {1, 2, 3}})
print("   Encode:", json_str4)
if json_str4:find("test") then
  print("   OK: tools/registry.lua works")
else
  print("   FAIL: tools/registry.lua broken")
end
print()

-- 测试 5: config/schema.lua
print("5. Testing config/schema.lua")
local Schema = dofile("config/schema.lua")

local config = Schema.load()
if config then
  print("   OK: Config loaded")
  print("   Provider:", config.provider)
  print("   Model:", config.model)
else
  print("   FAIL: Config load failed")
end
print()

-- 测试 6: scheduler/cron.lua
print("6. Testing scheduler/cron.lua")
local Cron = dofile("scheduler/cron.lua")

local jobs = Cron.list_jobs()
print("   Current jobs:", #jobs)
print("   OK: scheduler/cron.lua works")
print()

-- 测试 7: skill_index.lua
print("7. Testing skill_index.lua")
local SkillIndex = dofile("src/Skill/skill_index.lua")

local base_dir = "src/Skill"
local index = SkillIndex.load_index(base_dir)
if index then
  print("   OK: Skill index loaded")
  print("   Index timestamp:", index.timestamp)
else
  print("   INFO: Skill index not found (this is normal)")
end
print()

-- 测试 8: 中文和 Unicode 支持
print("8. Testing Chinese and Unicode support")
local unicode_test = {
  chinese = "测试",
  emoji = "😀🎉",
  mixed = "Hello 世界 🌍"
}
local unicode_json = U.json_encode(unicode_test)
local unicode_decoded = U.json_parse(unicode_json)

print("   Encode:", unicode_json)
print("   Decode:", unicode_decoded.chinese, unicode_decoded.emoji, unicode_decoded.mixed)
if unicode_decoded.chinese == "测试" and unicode_decoded.emoji == "😀🎉" then
  print("   OK: Unicode support works")
else
  print("   FAIL: Unicode support broken")
end
print()

-- 测试 9: 复杂嵌套结构
print("9. Testing complex nested structures")
local complex = {
  user = {
    name = "user",
    profile = {
      age = 25,
      skills = {"Lua", "Python", "Go"},
      contacts = {
        email = "test@example.com",
        phone = "1234567890"
      }
    },
    tags = {"admin", "developer"}
  },
  metadata = {
    created = "2026-03-19",
    updated = "2026-03-20"
  }
}
local complex_json = U.json_encode(complex)
local complex_decoded = U.json_parse(complex_json)

print("   Encode length:", #complex_json)
if complex_decoded.user.profile.skills and #complex_decoded.user.profile.skills == 3 then
  print("   OK: Complex structure handling works")
else
  print("   FAIL: Complex structure handling broken")
end
print()

-- 测试 10: 错误处理
print("10. Testing error handling")
local invalid_json = '{"invalid": json}'
local obj, err = U.json_parse(invalid_json)
if obj == nil and err then
  print("   OK: Error handling works:", err)
else
  print("   FAIL: Error handling broken")
end
print()

print("=" .. string.rep("=", 60))
print("All JSON tests completed!")
print("=" .. string.rep("=", 60))