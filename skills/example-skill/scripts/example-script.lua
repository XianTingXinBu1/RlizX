-- 示例脚本
-- 这是一个示例的 Lua 脚本，演示如何在技能中使用脚本资源

local function example_function(input)
    return "Example function called with: " .. tostring(input)
end

-- 导出函数
return {
    example_function = example_function
}