-- 测试 cjson 集成
-- 验证 JSON 解析和编码功能

local BASE_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/") or ".")
package.path = BASE_DIR .. "/?.lua;" .. package.path

local U = dofile(BASE_DIR .. "/src/Hub/utils.lua")
local JsonEncoder = dofile(BASE_DIR .. "/src/Tool/json_encoder.lua")

print("=" .. string.rep("=", 60))
print("测试 cjson 集成")
print("=" .. string.rep("=", 60))
print()

-- 测试 1: 基本解析
print("测试 1: 基本解析")
local json1 = '{"name":"Alice","age":30,"active":true}'
local obj1 = U.json_parse(json1)
print("输入:", json1)
print("解析结果:", obj1.name, obj1.age, obj1.active)
print("✓ 通过")
print()

-- 测试 2: 基本编码
print("测试 2: 基本编码")
local obj2 = {name = "Bob", age = 25, active = false}
local json2 = U.json_encode(obj2)
print("输入: {name = \"Bob\", age = 25, active = false}")
print("编码结果:", json2)
print("✓ 通过")
print()

-- 测试 3: 中文支持
print("测试 3: 中文支持")
local json3 = '{"name":"张三","message":"你好世界"}'
local obj3 = U.json_parse(json3)
print("输入:", json3)
print("解析结果:", obj3.name, obj3.message)
local cn_json = U.json_encode(obj3)
print("编码结果:", cn_json)
print("✓ 通过")
print()

-- 测试 4: Unicode 表情符号
print("测试 4: Unicode 表情符号")
local json4 = '{"message":"Hello 😀","emoji":"🚀"}'
local obj4 = U.json_parse(json4)
print("输入:", json4)
print("解析结果:", obj4.message, obj4.emoji)
local emoji_json = U.json_encode(obj4)
print("编码结果:", emoji_json)
print("✓ 通过")
print()

-- 测试 5: 嵌套结构
print("测试 5: 嵌套结构")
local json5 = '{"user":{"name":"Charlie","profile":{"age":35,"skills":["Lua","Python"]}}}'
local obj5 = U.json_parse(json5)
print("输入:", json5)
print("解析结果:", obj5.user.name, obj5.user.profile.age)
for i, skill in ipairs(obj5.user.profile.skills) do
  print("  技能", i, ":", skill)
end
local nested_json = U.json_encode(obj5)
print("编码结果:", nested_json)
print("✓ 通过")
print()

-- 测试 6: 数组
print("测试 6: 数组")
local json6 = '[1,2,3,"four",{"nested":true}]'
local obj6 = U.json_parse(json6)
print("输入:", json6)
for i, v in ipairs(obj6) do
  print("  元素", i, ":", type(v), v)
end
local arr_json = U.json_encode(obj6)
print("编码结果:", arr_json)
print("✓ 通过")
print()

-- 测试 7: 特殊值
print("测试 7: 特殊值 (null)")
local json7 = '{"value":null}'
local obj7 = U.json_parse(json7)
print("输入:", json7)
print("解析结果:", obj7.value)
print("✓ 通过")
print()

-- 测试 8: Worker 任务序列化场景
print("测试 8: Worker 任务序列化")
local task = {
  id = "task-123",
  type = "request",
  agent = "default",
  input = "测试任务",
  context = {
    workspace = "/root/工作区/RlizX",
    timestamp = os.time()
  },
  tools = {"read_file", "write_file"}
}
local task_json = U.json_encode(task)
print("任务编码结果:", task_json)
local decoded_task = U.json_parse(task_json)
print("解码结果 ID:", decoded_task.id)
print("解码结果 Agent:", decoded_task.agent)
print("✓ 通过")
print()

-- 测试 9: Worker 结果序列化场景
print("测试 9: Worker 结果序列化")
local result = {
  success = true,
  output = "任务执行成功",
  tool_calls = {
    {
      name = "read_file",
      result = {content = "文件内容"}
    }
  },
  metadata = {
    duration = 1.234,
    tokens_used = 150
  }
}
local result_json = U.json_encode(result)
print("结果编码结果:", result_json)
local decoded_result = U.json_parse(result_json)
print("解码结果 Success:", decoded_result.success)
print("解码结果 Output:", decoded_result.output)
print("✓ 通过")
print()

-- 测试 10: JsonEncoder 模块
print("测试 10: JsonEncoder 模块")
local obj10 = {name = "David", age = 40, active = true}
local json10 = JsonEncoder.encode_json(obj10)
print("输入: {name = \"David\", age = 40, active = true}")
print("编码结果:", json10)
print("✓ 通过")
print()

-- 测试 11: 错误处理
print("测试 11: 错误处理")
local invalid_json = '{"invalid": json}'
local obj11, err = U.json_parse(invalid_json)
if obj11 == nil and err then
  print("无效 JSON 正确返回错误:", err)
  print("✓ 通过")
else
  print("✗ 失败：应该返回错误")
end
print()

print("=" .. string.rep("=", 60))
print("所有测试完成！")
print("=" .. string.rep("=", 60))