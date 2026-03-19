-- RlizX Cron
-- 简化的定时任务管理

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

local function get_cron_file()
  local base = get_script_dir()
  base = base:gsub("/scheduler$", "")
  return base .. "/.rlizx/cron.json"
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

-- 读取 cron 任务
function M.read_jobs()
  local file = get_cron_file()
  local f = io.open(file, "r")
  if not f then return {} end
  
  local content = f:read("*a")
  f:close()
  
  local reg = get_registry()
  local ok, data = pcall(reg.decode_json, content)
  if not ok or not data then return {} end
  
  return data.jobs or {}
end

-- 写入 cron 任务
function M.write_jobs(jobs)
  local file = get_cron_file()
  os.execute("mkdir -p " .. shell_quote(file:match("^(.*)/")))
  
  local f = io.open(file, "w")
  if not f then return false end
  
  local reg = get_registry()
  f:write(reg.encode_json({ jobs = jobs }))
  f:close()
  
  return true
end

-- 添加任务
function M.add_job(name, message, cron_expr)
  local jobs = M.read_jobs()
  jobs[#jobs + 1] = {
    id = tostring(os.time()),
    name = name,
    message = message,
    cron = cron_expr
  }
  return M.write_jobs(jobs)
end

-- 删除任务
function M.remove_job(job_id)
  local jobs = M.read_jobs()
  local new_jobs = {}
  
  for _, job in ipairs(jobs) do
    if job.id ~= job_id then
      new_jobs[#new_jobs + 1] = job
    end
  end
  
  return M.write_jobs(new_jobs)
end

-- 列出任务
function M.list_jobs()
  return M.read_jobs()
end

-- 检查到期任务（简化版，实际应该解析 cron 表达式）
function M.check_due_jobs()
  local jobs = M.read_jobs()
  local due = {}
  
  -- 这里简化处理，实际应该实现完整的 cron 解析
  -- 现在只检查每分钟的任务
  local current_min = os.date("%M")
  
  for _, job in ipairs(jobs) do
    if job.cron == "*" .. current_min .. " * * *" then
      due[#due + 1] = job
    end
  end
  
  return due
end

return M