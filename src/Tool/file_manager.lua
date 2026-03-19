-- RlizX File Manager Tools

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.file_manager"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")

  local function get_cwd()
    local p = io.popen("pwd 2>/dev/null")
    if not p then
      return "."
    end
    local line = p:read("*l")
    p:close()
    if not line or line == "" then
      return "."
    end
    return line
  end

  local function collapse_path(path)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

    local parts = {}
    for seg in p:gmatch("[^/]+") do
      if seg == "." or seg == "" then
        -- ignore
      elseif seg == ".." then
        if #parts > 0 then
          table.remove(parts)
        end
      else
        parts[#parts + 1] = seg
      end
    end

    return "/" .. table.concat(parts, "/")
  end

  local function to_absolute(path)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

    if p:sub(1, 1) == "/" then
      return collapse_path(p)
    end

    return collapse_path(get_cwd() .. "/" .. p)
  end

  local function default_project_root()
    local here = to_absolute(get_script_dir())
    return collapse_path(here .. "/../..")
  end

  local active_root = default_project_root()

  function M.set_workspace_root(path)
    if type(path) ~= "string" or path == "" then
      active_root = default_project_root()
      return false, "invalid workspace root"
    end

    active_root = collapse_path(path)
    return true
  end

  function M.get_workspace_root()
    return active_root
  end

  local function get_project_root()
    return active_root or default_project_root()
  end

  local function normalize_path(path)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

    if p:sub(1, 1) == "/" then
      return collapse_path(p)
    end

    return collapse_path(get_project_root() .. "/" .. p)
  end

  local function is_path_safe(path)
    if type(path) ~= "string" then
      return false, "路径必须是字符串"
    end
    if path:find("\0", 1, true) then
      return false, "路径包含非法字符"
    end

    local root = get_project_root()
    local resolved = normalize_path(path)

    if resolved == root then
      return true, resolved
    end

    if resolved:sub(1, #root + 1) == (root .. "/") then
      return true, resolved
    end

    return false, "路径超出项目根目录"
  end

  local function shell_quote(s)
    return string.format("%q", tostring(s or ""))
  end

  local function path_is_dir(path)
    local check = os.execute("test -d " .. shell_quote(path) .. " >/dev/null 2>&1")
    return check == true or check == 0
  end

  local function list_dir_entries(path)
    local p = io.popen("ls -1A " .. shell_quote(path) .. " 2>/dev/null")
    if not p then
      return nil
    end

    local items = {}
    for line in p:lines() do
      if line ~= "." and line ~= ".." and line ~= "" then
        items[#items + 1] = line
      end
    end
    p:close()
    table.sort(items)
    return items
  end

  local function to_relative(abs_path)
    local root = get_project_root()
    if abs_path == root then
      return "."
    end
    if abs_path:sub(1, #root + 1) == (root .. "/") then
      return abs_path:sub(#root + 2)
    end
    return abs_path
  end

  local function run_capture(cmd)
    local p = io.popen(cmd .. " 2>&1")
    if not p then
      return nil, "命令执行失败"
    end
    local out = p:read("*a") or ""
    p:close()
    return out
  end

  local function encode_json(v)
    local tv = type(v)
    if tv == "nil" then
      return "null"
    elseif tv == "boolean" then
      return v and "true" or "false"
    elseif tv == "number" then
      return tostring(v)
    elseif tv == "string" then
      return '"' .. U.json_escape(v) .. '"'
    elseif tv == "table" then
      local is_array = true
      local max = 0
      local count = 0
      for k, _ in pairs(v) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
          is_array = false
          break
        end
        if k > max then
          max = k
        end
        count = count + 1
      end
      if is_array and max == count then
        local parts = {}
        for i = 1, #v do
          parts[#parts + 1] = encode_json(v[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
      end

      local keys = {}
      for k, _ in pairs(v) do
        keys[#keys + 1] = tostring(k)
      end
      table.sort(keys)

      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format('"%s":%s', U.json_escape(k), encode_json(v[k]))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end

    return '""'
  end

  local function parse_key_path(key_path)
    if type(key_path) ~= "string" or key_path == "" then
      return nil
    end
    local keys = {}
    for part in key_path:gmatch("[^%.]+") do
      if part ~= "" then
        keys[#keys + 1] = part
      end
    end
    if #keys == 0 then
      return nil
    end
    return keys
  end

  local function count_occurrences(text, needle)
    local count = 0
    local from = 1
    while true do
      local s = text:find(needle, from, true)
      if not s then
        break
      end
      count = count + 1
      from = s + #needle
    end
    return count
  end

  local function replace_first_plain(text, old_text, new_text)
    local s, e = text:find(old_text, 1, true)
    if not s then
      return text, 0
    end
    return text:sub(1, s - 1) .. new_text .. text:sub(e + 1), 1
  end

  local function replace_all_plain(text, old_text, new_text)
    local out = {}
    local from = 1
    local count = 0

    while true do
      local s, e = text:find(old_text, from, true)
      if not s then
        out[#out + 1] = text:sub(from)
        break
      end
      out[#out + 1] = text:sub(from, s - 1)
      out[#out + 1] = new_text
      from = e + 1
      count = count + 1
    end

    return table.concat(out), count
  end

  function M.read_file(args)
    local path = args and args.path
    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local f = io.open(resolved, "r")
    if not f then
      return { error = "文件不存在或不可读: " .. tostring(path) .. " (resolved: " .. resolved .. ")" }
    end

    local content = f:read("*a")
    f:close()

    return { result = content or "" }
  end

  function M.write_file(args)
    local path = args and args.path
    local content = args and args.content

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end
    if content == nil then
      return { error = "缺少必需参数: content" }
    end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local dir = resolved:match("^(.*)/")
    if dir and dir ~= "" then
      os.execute("mkdir -p " .. shell_quote(dir))
    end

    local ok = U.write_file(resolved, tostring(content))
    if not ok then
      return { error = "无法写入文件: " .. tostring(path) }
    end

    return { result = "文件写入成功" }
  end

  function M.list_files(args)
    local path = (args and args.path) or "."

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local check = os.execute("test -d " .. shell_quote(resolved) .. " >/dev/null 2>&1")
    if not (check == true or check == 0) then
      return { error = "目录不存在或不可访问: " .. tostring(path) .. " (resolved: " .. resolved .. ")" }
    end

    local items = list_dir_entries(resolved)
    if not items then
      return { error = "无法列出目录: " .. tostring(path) .. " (resolved: " .. resolved .. ")" }
    end

    return { result = table.concat(items, "\n") }
  end

  function M.search_files(args)
    local query = args and args.query
    local path = (args and args.path) or "."
    local is_regex = args and args.is_regex == true
    local case_sensitive = args and args.case_sensitive == true
    local max_results = tonumber(args and args.max_results) or 50

    if type(query) ~= "string" or query == "" then
      return { error = "缺少必需参数: query" }
    end

    if max_results < 1 then max_results = 1 end
    if max_results > 200 then max_results = 200 end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local root_is_dir = path_is_dir(resolved)
    local files = {}

    local function walk(dir)
      if #files > 5000 then
        return
      end

      local entries = list_dir_entries(dir)
      if not entries then
        return
      end

      for _, name in ipairs(entries) do
        local full = dir .. "/" .. name
        if path_is_dir(full) then
          walk(full)
        else
          files[#files + 1] = full
        end
      end
    end

    if root_is_dir then
      walk(resolved)
    else
      files[1] = resolved
    end

    local q = query
    if not case_sensitive then
      q = q:lower()
    end

    local matches = {}
    for _, file in ipairs(files) do
      local content = U.read_file(file)
      if content and content ~= "" then
        local line_no = 0
        for line in content:gmatch("([^\n]*)\n?") do
          if line == "" and line_no > 0 and #line == 0 then
            -- keep behavior stable on trailing newline
          end
          line_no = line_no + 1

          local target = line
          if not case_sensitive then
            target = target:lower()
          end

          local hit = false
          if is_regex then
            hit = target:find(q) ~= nil
          else
            hit = target:find(q, 1, true) ~= nil
          end

          if hit then
            matches[#matches + 1] = {
              path = to_relative(file),
              line = line_no,
              text = line,
            }
            if #matches >= max_results then
              return { result = matches }
            end
          end

          if line_no > 20000 then
            break
          end
        end
      end
    end

    return { result = matches }
  end

  function M.patch_file(args)
    local path = args and args.path
    local old_text = args and args.old_text
    local new_text = args and args.new_text
    local replace_all = args and args.replace_all == true

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end
    if type(old_text) ~= "string" then
      return { error = "缺少必需参数: old_text" }
    end
    if type(new_text) ~= "string" then
      return { error = "缺少必需参数: new_text" }
    end
    if old_text == "" then
      return { error = "old_text 不能为空" }
    end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local content = U.read_file(resolved)
    if content == nil then
      return { error = "文件不存在或不可读: " .. tostring(path) }
    end

    local total = count_occurrences(content, old_text)
    if total == 0 then
      return { error = "未找到匹配文本" }
    end

    local replaced
    local count

    if replace_all then
      replaced, count = replace_all_plain(content, old_text, new_text)
    else
      if total > 1 then
        return { error = "匹配到多处文本，请使用 replace_all=true 或提供更精确 old_text" }
      end
      replaced, count = replace_first_plain(content, old_text, new_text)
    end

    local ok = U.write_file(resolved, replaced)
    if not ok then
      return { error = "写入失败: " .. tostring(path) }
    end

    return { result = { replacements = count } }
  end

  function M.read_json(args)
    local path = args and args.path
    local key_path = args and args.key_path

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local raw = U.read_file(resolved)
    if raw == nil then
      return { error = "文件不存在或不可读: " .. tostring(path) }
    end

    local ok, obj = pcall(U.json_parse, raw)
    if not ok or type(obj) ~= "table" then
      return { error = "JSON 解析失败" }
    end

    if not key_path or key_path == "" then
      return { result = obj }
    end

    local keys = parse_key_path(key_path)
    if not keys then
      return { error = "key_path 非法" }
    end

    local cur = obj
    for _, k in ipairs(keys) do
      if type(cur) ~= "table" then
        return { error = "key_path 不存在: " .. tostring(key_path) }
      end
      cur = cur[k]
      if cur == nil then
        return { error = "key_path 不存在: " .. tostring(key_path) }
      end
    end

    return { result = cur }
  end

  function M.write_json_key(args)
    local path = args and args.path
    local key_path = args and args.key_path
    local value = args and args.value
    local create_missing = args and args.create_missing == true

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end
    if not key_path or key_path == "" then
      return { error = "缺少必需参数: key_path" }
    end

    local safe, resolved = is_path_safe(path)
    if not safe then
      return { error = resolved }
    end

    local raw = U.read_file(resolved)
    if raw == nil then
      return { error = "文件不存在或不可读: " .. tostring(path) }
    end

    local ok, obj = pcall(U.json_parse, raw)
    if not ok or type(obj) ~= "table" then
      return { error = "JSON 解析失败" }
    end

    local keys = parse_key_path(key_path)
    if not keys then
      return { error = "key_path 非法" }
    end

    local cur = obj
    for i = 1, #keys - 1 do
      local k = keys[i]
      if cur[k] == nil then
        if create_missing then
          cur[k] = {}
        else
          return { error = "key_path 不存在: " .. tostring(key_path) }
        end
      end
      if type(cur[k]) ~= "table" then
        return { error = "key_path 中间节点不是对象: " .. tostring(k) }
      end
      cur = cur[k]
    end

    cur[keys[#keys]] = value

    local encoded = encode_json(obj)
    local write_ok = U.write_file(resolved, encoded)
    if not write_ok then
      return { error = "写入失败: " .. tostring(path) }
    end

    return { result = { updated = true } }
  end

  function M.git_status(args)
    local short = not (args and args.short == false)
    local root = get_project_root()
    local cmd

    if short then
      cmd = "cd " .. shell_quote(root) .. " && git status --porcelain"
    else
      cmd = "cd " .. shell_quote(root) .. " && git status"
    end

    local out, err = run_capture(cmd)
    if not out then
      return { error = err or "git status 执行失败" }
    end

    return { result = out }
  end

  function M.git_diff(args)
    local staged = args and args.staged == true
    local path = args and args.path
    local root = get_project_root()

    local cmd = "cd " .. shell_quote(root) .. " && git diff"
    if staged then
      cmd = cmd .. " --staged"
    end

    if path and path ~= "" then
      local safe, resolved = is_path_safe(path)
      if not safe then
        return { error = resolved }
      end
      local rel = to_relative(resolved)
      if rel ~= "." then
        cmd = cmd .. " -- " .. shell_quote(rel)
      end
    end

    local out, err = run_capture(cmd)
    if not out then
      return { error = err or "git diff 执行失败" }
    end

    return { result = out }
  end

  package.loaded["rlizx.file_manager"] = M
end

local function register_file_tools()
  local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

  Registry.register_tool("read_file", {
    type = "function",
    ["function"] = {
      name = "read_file",
      description = "读取指定路径的文件内容",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "文件路径（相对于当前 agent 工作区根目录，例如 .rlizx/role/main.md；也可传该工作区内绝对路径）",
          },
        },
        required = { "path" },
      },
    },
  }, M.read_file)

  Registry.register_tool("write_file", {
    type = "function",
    ["function"] = {
      name = "write_file",
      description = "将内容写入指定路径的文件",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "文件路径（相对于当前 agent 工作区根目录，例如 .rlizx/role/main.md；也可传该工作区内绝对路径）",
          },
          content = {
            type = "string",
            description = "要写入的文件内容",
          },
        },
        required = { "path", "content" },
      },
    },
  }, M.write_file)

  Registry.register_tool("list_files", {
    type = "function",
    ["function"] = {
      name = "list_files",
      description = "列出指定目录下的文件和子目录",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "目录路径（相对于当前 agent 工作区根目录，例如 . 或 .rlizx/role，默认为当前目录）",
          },
        },
        required = {},
      },
    },
  }, M.list_files)

  Registry.register_tool("search_files", {
    type = "function",
    ["function"] = {
      name = "search_files",
      description = "在工作区内按关键字或模式搜索文件内容",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "搜索关键词或模式",
          },
          path = {
            type = "string",
            description = "搜索起始路径，默认为当前工作区根目录",
          },
          is_regex = {
            type = "boolean",
            description = "是否按 Lua 模式匹配，默认 false",
          },
          case_sensitive = {
            type = "boolean",
            description = "是否区分大小写，默认 false",
          },
          max_results = {
            type = "number",
            description = "最大返回条目数，默认 50，最大 200",
          },
        },
        required = { "query" },
      },
    },
  }, M.search_files)

  Registry.register_tool("patch_file", {
    type = "function",
    ["function"] = {
      name = "patch_file",
      description = "按文本片段修改文件，默认只允许唯一匹配",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "目标文件路径",
          },
          old_text = {
            type = "string",
            description = "待替换文本",
          },
          new_text = {
            type = "string",
            description = "替换后的文本",
          },
          replace_all = {
            type = "boolean",
            description = "是否替换全部匹配，默认 false",
          },
        },
        required = { "path", "old_text", "new_text" },
      },
    },
  }, M.patch_file)

  Registry.register_tool("read_json", {
    type = "function",
    ["function"] = {
      name = "read_json",
      description = "读取 JSON 文件，可按 key_path 获取子节点",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "JSON 文件路径",
          },
          key_path = {
            type = "string",
            description = "点路径，如 openai.tools.read_file",
          },
        },
        required = { "path" },
      },
    },
  }, M.read_json)

  Registry.register_tool("write_json_key", {
    type = "function",
    ["function"] = {
      name = "write_json_key",
      description = "写入 JSON 指定 key_path 的值",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "JSON 文件路径",
          },
          key_path = {
            type = "string",
            description = "点路径，如 openai.tools.search_files",
          },
          value = {
            type = "string",
            description = "要写入的值（对象/数组可传 JSON 字符串）",
          },
          create_missing = {
            type = "boolean",
            description = "路径不存在时是否自动创建中间对象",
          },
        },
        required = { "path", "key_path", "value" },
      },
    },
  }, function(args)
    local Utils = dofile(get_script_dir() .. "/../Hub/utils.lua")

    local value = args and args.value
    local parsed = value

    if type(value) == "string" then
      local s = value
      local ok, obj = pcall(Utils.json_parse, s)
      if ok and obj ~= nil then
        parsed = obj
      elseif s == "true" then
        parsed = true
      elseif s == "false" then
        parsed = false
      elseif s == "null" then
        parsed = nil
      else
        local n = tonumber(s)
        if n ~= nil then
          parsed = n
        end
      end
    end

    local proxy = {}
    for k, v in pairs(args or {}) do
      proxy[k] = v
    end
    proxy.value = parsed
    return M.write_json_key(proxy)
  end)

  Registry.register_tool("git_status", {
    type = "function",
    ["function"] = {
      name = "git_status",
      description = "查看当前工作区 git 状态",
      parameters = {
        type = "object",
        properties = {
          short = {
            type = "boolean",
            description = "true 为精简输出（默认），false 为完整输出",
          },
        },
        required = {},
      },
    },
  }, M.git_status)

  Registry.register_tool("git_diff", {
    type = "function",
    ["function"] = {
      name = "git_diff",
      description = "查看当前工作区 git diff，可选 staged 和 path",
      parameters = {
        type = "object",
        properties = {
          staged = {
            type = "boolean",
            description = "是否查看暂存区 diff",
          },
          path = {
            type = "string",
            description = "可选，限制到某个路径",
          },
        },
        required = {},
      },
    },
  }, M.git_diff)
end

return {

  register = register_file_tools,

  set_workspace_root = function(path)

    return M.set_workspace_root(path)

  end,

  get_workspace_root = function()

    return M.get_workspace_root()

  end,

}