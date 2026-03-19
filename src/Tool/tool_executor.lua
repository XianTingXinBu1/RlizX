-- RlizX Tool Executor

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.tool_executor"]

if not M then
  M = {}

  local ToolCallParser = dofile(get_script_dir() .. "/tool_call_parser.lua")
  local MessageHandler = dofile(get_script_dir() .. "/message_handler.lua")
  local ToolLoop = dofile(get_script_dir() .. "/tool_loop.lua")

  function M.parse_tool_calls(response_body)
    return ToolCallParser.parse_tool_calls(response_body)
  end

  function M.detect_tool_calls(response_body)
    return ToolCallParser.detect_tool_calls(response_body)
  end

  function M.execute_single_tool(tool_call, on_progress, context)
    return ToolLoop.execute_single_tool(tool_call, on_progress, context)
  end

  function M.handle_tool_loop_result(initial_messages, http_request_fn, cfg, on_progress)
    return ToolLoop.handle_tool_loop_result(initial_messages, http_request_fn, cfg, on_progress)
  end

  function M.handle_tool_loop(initial_messages, http_request_fn, cfg, on_progress)
    return ToolLoop.handle_tool_loop(initial_messages, http_request_fn, cfg, on_progress)
  end

  function M.build_payload_with_tools(messages, cfg)
    return MessageHandler.build_payload_with_tools(messages, cfg)
  end

  function M.message_to_text(message)
    return MessageHandler.message_to_text(message)
  end

  package.loaded["rlizx.tool_executor"] = M
end

return M