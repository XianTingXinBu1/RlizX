-- RlizX CLI (entry)
local VERSION = "0.1.0"

local function printf(fmt, ...)
  io.stdout:write(string.format(fmt, ...))
end

local function print_help()
  io.stdout:write([[
RlizX - 命令行 AI 编程助手（纯 Lua）

用法:
  lua rlizx.lua                 直接进入 REPL
  lua rlizx.lua [command] [options]

命令:
  help              显示帮助
  version           显示版本
  repl              进入交互模式
  check             运行非交互式检查

选项:
  -h, --help        显示帮助
  -v, --version     显示版本

REPL 特性:
  - 显示当前 agent 的动态提示符
  - 支持 /status 查看当前状态
  - 支持 /switch 与 /agent 子命令管理 agent

说明:
  当前版本已提供基础 CLI、REPL、配置检查、agent 管理与模型调用链路。
]])
end

local function print_version()
  printf("RlizX v%s\n", VERSION)
end

local function script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function run_repl()
  local base = script_dir()
  local repl = dofile(base .. "/src/REPL/repl.lua")
  repl.start({ version = VERSION, prompt = "> " })
end

local function run_check()
  local base = script_dir()
  local check = dofile(base .. "/src/Check/check.lua")
  local ok = check.run_all()
  if not ok then
    os.exit(1)
  end
end

local function main(argv)
  if #argv == 0 then
    run_repl()
    return
  end

  local cmd = argv[1]
  if cmd == "help" or cmd == "-h" or cmd == "--help" then
    print_help()
  elseif cmd == "version" or cmd == "-v" or cmd == "--version" then
    print_version()
  elseif cmd == "repl" then
    run_repl()
  elseif cmd == "check" then
    run_check()
  else
    io.stderr:write("未知命令: " .. cmd .. "\n")
    print_help()
  end
end

main(arg)
