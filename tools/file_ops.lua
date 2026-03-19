-- RlizX File Operations
-- 基础文件操作工具

local M = {}

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

-- 读取文件
function M.read_file(args, context)
  local path = args and args.path
  if not path or path == "" then
    return { error = "缺少必需参数: path" }
  end
  
  local f = io.open(path, "r")
  if not f then
    return { error = "文件不存在: " .. path }
  end
  
  local content = f:read("*a")
  f:close()
  
  return { result = content }
end

-- 写入文件
function M.write_file(args, context)
  local path = args and args.path
  local content = args and args.content
  
  if not path or path == "" then
    return { error = "缺少必需参数: path" }
  end
  if content == nil then
    return { error = "缺少必需参数: content" }
  end
  
  local dir = path:match("^(.*)/")
  if dir then
    os.execute("mkdir -p " .. shell_quote(dir))
  end
  
  local f = io.open(path, "w")
  if not f then
    return { error = "无法写入文件: " .. path }
  end
  
  f:write(content)
  f:close()
  
  return { result = "文件写入成功" }
end

-- 列出文件
function M.list_files(args, context)
  local path = args and args.path or "."
  
  local p = io.popen("ls -1 " .. shell_quote(path) .. " 2>/dev/null")
  if not p then
    return { error = "无法列出目录: " .. path }
  end
  
  local files = {}
  for file in p:lines() do
    files[#files + 1] = file
  end
  p:close()
  
  return { result = table.concat(files, "\n") }
end

return M