-- RlizX Tools Loader
-- 自动加载和注册所有工具

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local Registry = dofile(get_script_dir() .. "/registry.lua")
local base_dir = get_script_dir()

-- 加载文件操作工具
local FileOps = dofile(base_dir .. "/file_ops.lua")

Registry.register("read_file", {
  name = "read_file",
  description = "读取文件内容",
  inputSchema = {
    type = "object",
    properties = {
      path = { type = "string", description = "文件路径" }
    },
    required = {"path"}
  }
}, FileOps.read_file)

Registry.register("write_file", {
  name = "write_file",
  description = "写入文件内容",
  inputSchema = {
    type = "object",
    properties = {
      path = { type = "string", description = "文件路径" },
      content = { type = "string", description = "文件内容" }
    },
    required = {"path", "content"}
  }
}, FileOps.write_file)

Registry.register("list_files", {
  name = "list_files",
  description = "列出目录内容",
  inputSchema = {
    type = "object",
    properties = {
      path = { type = "string", description = "目录路径" }
    },
    required = {}
  }
}, FileOps.list_files)

-- 添加 Heartbeat 工具
local Heartbeat = dofile(base_dir .. "/../scheduler/heartbeat.lua")

Registry.register("add_heartbeat_task", {
  name = "add_heartbeat_task",
  description = "添加周期性任务",
  inputSchema = {
    type = "object",
    properties = {
      task = { type = "string", description = "任务描述" }
    },
    required = {"task"}
  }
}, function(args, context)
  local task = args and args.task
  if not task or task == "" then
    return { error = "缺少必需参数: task" }
  end
  
  if Heartbeat.add_task(task) then
    return { result = "任务已添加: " .. task }
  else
    return { error = "添加任务失败" }
  end
end)

Registry.register("list_heartbeat_tasks", {
  name = "list_heartbeat_tasks",
  description = "列出所有周期性任务",
  inputSchema = {
    type = "object",
    properties = {},
    required = {}
  }
}, function(args, context)
  local tasks = Heartbeat.read_tasks()
  
  if #tasks == 0 then
    return { result = "没有周期性任务" }
  end
  
  local lines = {"周期性任务:"}
  for _, task in ipairs(tasks) do
    local marker = task.done and "x" or " "
    lines[#lines + 1] = string.format("- [%s] %s", marker, task.text)
  end
  
  return { result = table.concat(lines, "\n") }
end)

-- 添加 Cron 工具
local Cron = dofile(base_dir .. "/../scheduler/cron.lua")

Registry.register("add_cron_job", {
  name = "add_cron_job",
  description = "添加定时任务",
  inputSchema = {
    type = "object",
    properties = {
      name = { type = "string", description = "任务名称" },
      message = { type = "string", description = "执行消息" },
      cron = { type = "string", description = "Cron 表达式" }
    },
    required = {"name", "message", "cron"}
  }
}, function(args, context)
  local name = args and args.name
  local message = args and args.message
  local cron = args and args.cron
  
  if not name or name == "" then
    return { error = "缺少必需参数: name" }
  end
  if not message or message == "" then
    return { error = "缺少必需参数: message" }
  end
  if not cron or cron == "" then
    return { error = "缺少必需参数: cron" }
  end
  
  if Cron.add_job(name, message, cron) then
    return { result = "定时任务已添加: " .. name }
  else
    return { error = "添加任务失败" }
  end
end)

Registry.register("list_cron_jobs", {
  name = "list_cron_jobs",
  description = "列出所有定时任务",
  inputSchema = {
    type = "object",
    properties = {},
    required = {}
  }
}, function(args, context)
  local jobs = Cron.list_jobs()
  
  if #jobs == 0 then
    return { result = "没有定时任务" }
  end
  
  local lines = {"定时任务:"}
  for _, job in ipairs(jobs) do
    lines[#lines + 1] = string.format("  [%s] %s - %s (%s)", job.id, job.name, job.message, job.cron)
  end
  
  return { result = table.concat(lines, "\n") }
end)

-- 加载 Shell 操作工具
local ShellOps = dofile(base_dir .. "/shell_ops.lua")

Registry.register("shell_execute", {
  name = "shell_execute",
  description = "执行 shell 命令（支持安全检查和超时控制）",
  inputSchema = {
    type = "object",
    properties = {
      command = { type = "string", description = "要执行的命令" },
      working_dir = { type = "string", description = "工作目录（可选）" },
      timeout = { type = "number", description = "超时时间（秒，默认30）" }
    },
    required = {"command"}
  }
}, ShellOps.execute)

Registry.register("shell_getenv", {
  name = "shell_getenv",
  description = "获取环境变量",
  inputSchema = {
    type = "object",
    properties = {
      name = { type = "string", description = "环境变量名（不指定则列出所有）" }
    },
    required = {}
  }
}, ShellOps.getenv)

Registry.register("shell_which", {
  name = "shell_which",
  description = "检查命令是否存在",
  inputSchema = {
    type = "object",
    properties = {
      command = { type = "string", description = "要检查的命令" }
    },
    required = {"command"}
  }
}, ShellOps.which)

Registry.register("shell_pwd", {
  name = "shell_pwd",
  description = "获取当前工作目录",
  inputSchema = {
    type = "object",
    properties = {},
    required = {}
  }
}, ShellOps.pwd)

return Registry