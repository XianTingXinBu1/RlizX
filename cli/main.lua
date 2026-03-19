-- RlizX CLI
-- 极简的命令行接口

local M = {}

local function print_help()
  print([[
RlizX - 极简 AI 助手

用法:
  rlizx agent                    # 进入交互模式
  rlizx agent -m "消息"          # 发送单条消息
  rlizx cron add <名称> <消息> <cron>  # 添加定时任务
  rlizx cron list                # 列出定时任务
  rlizx cron remove <id>         # 删除定时任务
  rlizx heartbeat                # 检查 Heartbeat 任务
  rlizx init                     # 初始化配置
  rlizx version                  # 显示版本
  rlizx help                     # 显示帮助
]])
end

local function print_version()
  print("RlizX v2.0.0 - 基于 nanobot 架构重构")
end

local function init_config()
  local Config = require("rlizx.config.schema")
  local default = Config.get_default()
  
  print("初始化 RlizX 配置...")
  print("请输入你的 OpenAI API Key:")
  local api_key = io.read()
  
  if api_key and api_key ~= "" then
    default.api_key = api_key
  end
  
  Config.save(default)
  print("配置已保存到 rlizx.config.json")
end

local function run_agent(message)
  local Bus = require("rlizx.bus.router")
  local Config = require("rlizx.config.schema")
  
  local config = Config.get_current()
  local agent_name = "default"
  
  local response, err = Bus.send(agent_name, message, config)
  
  if response then
    print(response)
  else
    print("错误: " .. (err or "未知错误"))
  end
end

local function run_interactive()
  local Bus = require("rlizx.bus.router")
  local Config = require("rlizx.config.schema")
  
  local config = Config.get_current()
  local agent_name = "default"
  
  print("RlizX 交互模式 (输入 'exit' 退出)")
  print("--------------------------------")
  
  while true do
    io.write("> ")
    local input = io.read()
    
    if not input or input == "exit" or input == "quit" then
      break
    end
    
    if input == "" then
      goto continue
    end
    
    local response, err = Bus.send(agent_name, input, config)
    
    if response then
      print(response)
    else
      print("错误: " .. (err or "未知错误"))
    end
    
    ::continue::
  end
end

local function cron_add(name, message, cron_expr)
  local Cron = require("rlizx.scheduler.cron")
  
  if Cron.add_job(name, message, cron_expr) then
    print("定时任务已添加: " .. name)
  else
    print("添加失败")
  end
end

local function cron_list()
  local Cron = require("rlizx.scheduler.cron")
  local jobs = Cron.list_jobs()
  
  if #jobs == 0 then
    print("没有定时任务")
    return
  end
  
  print("定时任务列表:")
  for _, job in ipairs(jobs) do
    print(string.format("  [%s] %s - %s (%s)", job.id, job.name, job.message, job.cron))
  end
end

local function cron_remove(job_id)
  local Cron = require("rlizx.scheduler.cron")
  
  if Cron.remove_job(job_id) then
    print("定时任务已删除: " .. job_id)
  else
    print("删除失败")
  end
end

local function heartbeat_check()
  local Heartbeat = require("rlizx.scheduler.heartbeat")
  local Bus = require("rlizx.bus.router")
  local Config = require("rlizx.config.schema")
  
  local tasks = Heartbeat.get_pending_tasks()
  
  if #tasks == 0 then
    print("没有待处理的 Heartbeat 任务")
    return
  end
  
  print("待处理的 Heartbeat 任务:")
  for i, task in ipairs(tasks) do
    print(string.format("  %d. %s", i, task))
  end
  
  local config = Config.get_current()
  local agent_name = "default"
  
  for _, task in ipairs(tasks) do
    print("\n执行任务: " .. task)
    local response, err = Bus.send(agent_name, task, config)
    
    if response then
      print("结果: " .. response)
      Heartbeat.mark_done(task)
    else
      print("错误: " .. (err or "未知错误"))
    end
  end
end

-- 主入口
function M.main(args)
  local cmd = args[1] or "help"
  
  if cmd == "help" or cmd == "-h" or cmd == "--help" then
    print_help()
  elseif cmd == "version" or cmd == "-v" or cmd == "--version" then
    print_version()
  elseif cmd == "init" then
    init_config()
  elseif cmd == "agent" then
    if args[2] == "-m" and args[3] then
      run_agent(args[3])
    else
      run_interactive()
    end
  elseif cmd == "cron" then
    local subcmd = args[2]
    if subcmd == "add" and args[3] and args[4] and args[5] then
      cron_add(args[3], args[4], args[5])
    elseif subcmd == "list" then
      cron_list()
    elseif subcmd == "remove" and args[3] then
      cron_remove(args[3])
    else
      print("用法: rlizx cron add|list|remove ...")
    end
  elseif cmd == "heartbeat" then
    heartbeat_check()
  else
    print("未知命令: " .. cmd)
    print("使用 'rlizx help' 查看帮助")
  end
end

return M