-- RlizX REPL terminal/input helpers (pure Lua)

local M = {}

local function printf(fmt, ...)
  io.stdout:write(string.format(fmt, ...))
end

local function get_stty_state()
  local p = io.popen("stty -g 2>/dev/null")
  if not p then return nil end
  local state = p:read("*l")
  p:close()
  return state
end

local function set_raw_mode()
  -- raw + no-echo + immediate input
  os.execute("stty -echo -icanon min 1 time 0")
end

local function restore_mode(state)
  if state and state ~= "" then
    os.execute("stty " .. state)
  else
    os.execute("stty sane")
  end
end

local function read_key()
  local c = io.stdin:read(1)
  if not c then return nil end
  if c == "\27" then
    local c2 = io.stdin:read(1)
    if c2 == "[" then
      local c3 = io.stdin:read(1)
      return "ESC[" .. (c3 or "")
    end
    return "ESC"
  end

  local b = string.byte(c)
  if b and b >= 0x80 then
    local len
    if b >= 0xF0 then
      len = 4
    elseif b >= 0xE0 then
      len = 3
    elseif b >= 0xC0 then
      len = 2
    else
      len = 1
    end
    if len > 1 then
      local rest = io.stdin:read(len - 1) or ""
      return c .. rest
    end
  end

  return c
end

local function utf8_chars(s)
  local t = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    t[#t + 1] = ch
  end
  return t
end

local function utf8_width(ch)
  local b = string.byte(ch)
  if not b or b < 0x80 then
    return 1
  end
  -- 近似宽度：把大多数多字节字符当作宽 2
  return 2
end

local function buf_width(buf, n)
  local w = 0
  for i = 1, n do
    w = w + utf8_width(buf[i])
  end
  return w
end

local function text_width(s)
  return buf_width(utf8_chars(s or ""), #(utf8_chars(s or "")))
end

local function render_line(prompt, buf, cursor, menu, selected_index, last_menu_lines)
  io.stdout:write("\r")
  io.stdout:write(prompt)
  io.stdout:write(table.concat(buf))
  io.stdout:write("\27[0K")

  for _ = 1, (last_menu_lines or 0) do
    io.stdout:write("\n\27[0K")
  end
  for _ = 1, (last_menu_lines or 0) do
    io.stdout:write("\27[1A")
  end

  local menu_lines = 0
  if menu and #menu > 0 then
    menu_lines = #menu
    for i, item in ipairs(menu) do
      local prefix = (i == selected_index) and "  > " or "    "
      io.stdout:write("\n\27[0K" .. prefix .. item.label)
    end
    for _ = 1, menu_lines do
      io.stdout:write("\27[1A")
    end
  end

  local target = text_width(prompt) + buf_width(buf, cursor)
  io.stdout:write("\r")
  if target > 0 then
    io.stdout:write(string.format("\27[%dC", target))
  end
  io.stdout:flush()
  return menu_lines
end

local function read_line(prompt, history, complete_fn)
  local buf = {}
  local cursor = 0
  local hist_index = nil
  local saved_line = ""
  local menu = {}
  local selected_index = 1
  local last_menu_lines = 0
  local suppress_menu_once = false

  local function current_text()
    return table.concat(buf)
  end

  local function set_buffer(text)
    buf = utf8_chars(text)
    cursor = #buf
  end

  local function refresh_menu()
    if suppress_menu_once then
      menu = {}
      selected_index = 1
      suppress_menu_once = false
      return
    end

    if not complete_fn then
      menu = {}
      selected_index = 1
      return
    end

    local items = complete_fn(current_text()) or {}
    menu = items
    if #menu == 0 then
      selected_index = 1
    elseif selected_index < 1 then
      selected_index = 1
    elseif selected_index > #menu then
      selected_index = #menu
    end
  end

  local function redraw()
    last_menu_lines = render_line(prompt, buf, cursor, menu, selected_index, last_menu_lines)
  end

  local function accept_completion()
    local item = menu[selected_index]
    if not item then
      return false
    end
    set_buffer(item.value)
    hist_index = nil
    suppress_menu_once = not item.keep_menu_open
    refresh_menu()
    redraw()
    return true
  end

  refresh_menu()
  redraw()

  while true do
    local k = read_key()
    if not k then return nil end

    if k == "\r" or k == "\n" then
      if #menu > 0 then
        accept_completion()
      else
        io.stdout:write("\n")
        return current_text()
      end
    elseif k == "\127" or k == "\8" then
      if cursor > 0 then
        table.remove(buf, cursor)
        cursor = cursor - 1
        hist_index = nil
      end
      refresh_menu()
    elseif k == "\3" then
      io.stdout:write("\n")
      return nil, "interrupt"
    elseif k == "ESC[A" then
      if #menu > 0 then
        if selected_index > 1 then
          selected_index = selected_index - 1
        end
      elseif #history > 0 then
        if not hist_index then
          hist_index = #history
          saved_line = current_text()
        elseif hist_index > 1 then
          hist_index = hist_index - 1
        end
        set_buffer(history[hist_index] or "")
        refresh_menu()
      end
    elseif k == "ESC[B" then
      if #menu > 0 then
        if selected_index < #menu then
          selected_index = selected_index + 1
        end
      elseif hist_index then
        if hist_index < #history then
          hist_index = hist_index + 1
          set_buffer(history[hist_index] or "")
        else
          hist_index = nil
          set_buffer(saved_line)
        end
        refresh_menu()
      end
    elseif k == "ESC[D" then
      if cursor > 0 then
        cursor = cursor - 1
      end
      refresh_menu()
    elseif k == "ESC[C" then
      if cursor < #buf then
        cursor = cursor + 1
      end
      refresh_menu()
    elseif k >= " " then
      table.insert(buf, cursor + 1, k)
      cursor = cursor + 1
      hist_index = nil
      refresh_menu()
    end

    redraw()
  end
end

M.printf = printf
M.get_stty_state = get_stty_state
M.set_raw_mode = set_raw_mode
M.restore_mode = restore_mode
M.read_line = read_line

return M