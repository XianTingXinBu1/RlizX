-- RlizX Heartbeat
-- 文件驱动的智能任务管理

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local Registry
local function get_registry()
  if not Registry then
    local base = get_script_dir()
    base = base:gsub("/scheduler$", "")
    Registry = dofile(base .. "/tools/registry.lua")
  end
  return Registry
end

local function get_workspace()
  local base = get_script_dir()
  base = base:gsub("/scheduler$", "")
  return base .. "/workspace"
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

-- 获取 Heartbeat 文件路径
function M.get_heartbeat_file()
  local workspace = get_workspace()
  os.execute("mkdir -p " .. shell_quote(workspace))
  return workspace .. "/HEARTBEAT.md"
end

-- 读取任务
function M.read_tasks()
  local file = M.get_heartbeat_file()
  local f = io.open(file, "r")
  if not f then return {} end
  
  local content = f:read("*a")
  f:close()
  
  local tasks = {}
  for line in content:gmatch("[^\r\n]+") do
    local task, done = line:match("^%s*-%s*%[(.)%]%s*(.+)")
    if task then
      tasks[#tasks + 1] = {
        text = task,
        done = (done == "x" or done == "X")
      }
    end
  end
  
  return tasks
end

-- 写入任务
function M.write_tasks(tasks)
  local file = M.get_heartbeat_file()
  local f = io.open(file, "w")
  if not f then return false end
  
  f:write("## 周期性任务\n\n")
  for _, task in ipairs(tasks) do
    local marker = task.done and "x" or " "
    f:write(string.format("- [%s] %s\n", marker, task.text))
  end
  
  f:close()
  return true
end

-- 获取未完成的任务
function M.get_pending_tasks()
  local tasks = M.read_tasks()
  local pending = {}
  
  for _, task in ipairs(tasks) do
    if not task.done then
      pending[#pending + 1] = task.text
    end
  end
  
  return pending
end

-- 标记任务为完成
function M.mark_done(task_text)
  local tasks = M.read_tasks()
  
  for _, task in ipairs(tasks) do
    if task.text == task_text and not task.done then
      task.done = true
      break
    end
  end
  
  return M.write_tasks(tasks)
end

-- 添加新任务
function M.add_task(task_text)
  local tasks = M.read_tasks()
  tasks[#tasks + 1] = { text = task_text, done = false }
  return M.write_tasks(tasks)
end

return M