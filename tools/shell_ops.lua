-- RlizX Shell Operations
-- Shell 命令执行工具

local M = {}

-- 安全的 shell 参数转义
local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

-- 执行 shell 命令
function M.execute(args, context)
  local command = args and args.command
  if not command or command == "" then
    return { error = "缺少必需参数: command" }
  end
  
  -- 安全检查：禁止某些危险命令
  local dangerous_patterns = {
    "rm -rf /",
    "mkfs",
    "dd if=",
    ":(){:|:&};:",
    "format",
    "del /f /s /q"
  }
  
  local lower_cmd = command:lower()
  for _, pattern in ipairs(dangerous_patterns) do
    if lower_cmd:find(pattern, 1, true) then
      return {
        error = "拒绝执行危险命令: " .. pattern,
        suggestion = "请使用更具体的路径或参数"
      }
    end
  end
  
  -- 可选参数
  local working_dir = args.working_dir or context and context.working_dir or "."
  local timeout = args.timeout or 30
  
  -- 使用子 shell 来正确处理工作目录和超时
  -- 方法：(cd /path/to/dir && command) 或 (command) 如果没有指定目录
  local dir_cmd = working_dir ~= "." and "cd " .. shell_quote(working_dir) .. " && " or ""
  local full_command = "(" .. dir_cmd .. command .. ")"
  
  -- 使用 timeout 命令限制执行时间
  local safe_command = string.format("timeout %d bash -c %s 2>&1", timeout, shell_quote(full_command))
  
  -- 执行命令
  local pipe = io.popen(safe_command)
  if not pipe then
    return { error = "无法执行命令: " .. command }
  end
  
  -- 读取输出
  local output = pipe:read("*a")
  local exit_code = { pipe:close() }
  
  -- 获取真实的退出码
  local code = exit_code[3] or exit_code[1] or 0
  
  -- 判断是否超时
  local timed_out = code == 124
  
  return {
    success = code == 0,
    exit_code = code,
    output = output,
    timed_out = timed_out,
    command = command
  }
end

-- 获取环境变量
function M.getenv(args, context)
  local var_name = args and args.name
  if var_name then
    local value = os.getenv(var_name)
    return {
      success = true,
      name = var_name,
      value = value,
      exists = value ~= nil
    }
  else
    -- 列出所有环境变量
    local env_vars = {}
    for k, v in pairs(_G.os.getenv and _G.os.getenv() or {}) do
      env_vars[#env_vars + 1] = k .. "=" .. v
    end
    return {
      success = true,
      result = table.concat(env_vars, "\n")
    }
  end
end

-- 检查命令是否存在
function M.which(args, context)
  local command = args and args.command
  if not command or command == "" then
    return { error = "缺少必需参数: command" }
  end

  local pipe = io.popen("which " .. shell_quote(command) .. " 2>/dev/null")
  if not pipe then
    return { success = false, found = false, path = nil }
  end

  local path = pipe:read("*a"):gsub("\n$", "")
  pipe:close()

  return {
    success = true,
    found = path ~= "",
    path = path ~= "" and path or nil,
    command = command
  }
end

-- 获取当前工作目录
function M.pwd(args, context)
  local pipe = io.popen("pwd")
  if not pipe then
    return { success = false, error = "无法获取当前工作目录" }
  end

  local path = pipe:read("*a"):gsub("\n$", "")
  pipe:close()

  return {
    success = true,
    path = path
  }
end

return M