-- RlizX File Operations

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.file_ops"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")
  local PathUtils = dofile(get_script_dir() .. "/path_utils.lua")

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

  function M.read_file(args, context)
    local path = args and args.path
    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end

    local safe, resolved = PathUtils.is_path_safe(path, context)
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

  function M.write_file(args, context)
    local path = args and args.path
    local content = args and args.content

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end
    if content == nil then
      return { error = "缺少必需参数: content" }
    end

    local safe, resolved = PathUtils.is_path_safe(path, context)
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

  function M.list_files(args, context)
    local path = (args and args.path) or "."

    local safe, resolved = PathUtils.is_path_safe(path, context)
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

  function M.search_files(args, context)
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

    local safe, resolved = PathUtils.is_path_safe(path, context)
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
          line_no = line_no + 1

          local target = line
          if not case_sensitive then
            target = target:lower()
          end

          local hit
          if is_regex then
            hit = target:find(q) ~= nil
          else
            hit = target:find(q, 1, true) ~= nil
          end

          if hit then
            matches[#matches + 1] = {
              path = PathUtils.to_relative(file, context),
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

  function M.patch_file(args, context)
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

    local safe, resolved = PathUtils.is_path_safe(path, context)
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

  package.loaded["rlizx.file_ops"] = M
end

return M