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

  local FileOps = dofile(get_script_dir() .. "/file_ops.lua")
  local JsonOps = dofile(get_script_dir() .. "/json_ops.lua")
  local GitOps = dofile(get_script_dir() .. "/git_ops.lua")
  local PathUtils = dofile(get_script_dir() .. "/path_utils.lua")
  local SearchOps = dofile(get_script_dir() .. "/search_ops.lua")
  local ScheduleOps = dofile(get_script_dir() .. "/schedule_ops.lua")
  local SkillOps = dofile(get_script_dir() .. "/skill_ops.lua")

  local function register_tool_definition(registry, name, description, properties, required, handler, category)
    registry.register_tool(name, {
      type = "function",
      ["function"] = {
        name = name,
        description = description,
        parameters = {
          type = "object",
          properties = properties or {},
          required = required or {},
        },
      },
    }, handler, { category = category })
  end

  local function register_file_tools()
    local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

    register_tool_definition(
      Registry,
      "read_file",
      "读取指定路径的文件内容",
      {
        path = {
          type = "string",
          description = "文件路径（相对于当前 agent 工作区根目录，例如 .rlizx/role/main.md；也可传该工作区内绝对路径）",
        },
      },
      { "path" },
      FileOps.read_file,
      "read"
    )

    register_tool_definition(
      Registry,
      "write_file",
      "将内容写入指定路径的文件",
      {
        path = {
          type = "string",
          description = "文件路径（相对于当前 agent 工作区根目录，例如 .rlizx/role/main.md；也可传该工作区内绝对路径）",
        },
        content = {
          type = "string",
          description = "要写入的文件内容",
        },
      },
      { "path", "content" },
      FileOps.write_file,
      "write"
    )

    register_tool_definition(
      Registry,
      "list_files",
      "列出指定目录下的文件和子目录",
      {
        path = {
          type = "string",
          description = "目录路径（相对于当前 agent 工作区根目录，例如 . 或 .rlizx/role，默认为当前目录）",
        },
      },
      {},
      FileOps.list_files,
      "read"
    )

    register_tool_definition(
      Registry,
      "search_files",
      "在工作区内按关键字或模式搜索文件内容",
      {
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
      { "query" },
      FileOps.search_files,
      "read"
    )

    register_tool_definition(
      Registry,
      "patch_file",
      "按文本片段修改文件，默认只允许唯一匹配",
      {
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
      { "path", "old_text", "new_text" },
      FileOps.patch_file,
      "write"
    )

    register_tool_definition(
      Registry,
      "read_json",
      "读取 JSON 文件，可按 key_path 获取子节点",
      {
        path = {
          type = "string",
          description = "JSON 文件路径",
        },
        key_path = {
          type = "string",
          description = "点路径，如 openai.tools.read_file",
        },
      },
      { "path" },
      JsonOps.read_json,
      "read"
    )

    register_tool_definition(
      Registry,
      "write_json_key",
      "写入 JSON 指定 key_path 的值",
      {
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
      { "path", "key_path", "value" },
      function(args, context)
        local proxy = {}
        for k, v in pairs(args or {}) do
          proxy[k] = v
        end
        proxy.value = JsonOps.parse_write_json_value(args and args.value)
        return JsonOps.write_json_key(proxy, context)
      end,
      "write"
    )

    register_tool_definition(
      Registry,
      "git_status",
      "查看当前工作区 git 状态",
      {
        short = {
          type = "boolean",
          description = "true 为精简输出（默认），false 为完整输出",
        },
      },
      {},
      GitOps.git_status,
      "git"
    )

    register_tool_definition(
      Registry,
      "git_diff",
      "查看当前工作区 git diff，可选 staged 和 path",
      {
        staged = {
          type = "boolean",
          description = "是否查看暂存区 diff",
        },
        path = {
          type = "string",
          description = "可选，限制到某个路径",
        },
      },
      {},
      GitOps.git_diff,
      "git"
    )

    register_tool_definition(
      Registry,
      "web_search",
      "使用 DuckDuckGo 进行网络搜索",
      {
        query = {
          type = "string",
          description = "搜索关键词",
        },
        num_results = {
          type = "number",
          description = "返回结果数量，默认 10，最大 30",
        },
      },
      { "query" },
      SearchOps.web_search,
      "read"
    )

    register_tool_definition(
      Registry,
      "web_fetch",
      "获取指定 URL 的网页内容",
      {
        url = {
          type = "string",
          description = "网页 URL（必须以 http:// 或 https:// 开头）",
        },
      },
      { "url" },
      SearchOps.web_fetch,
      "read"
    )

    register_tool_definition(
      Registry,
      "schedule_create_nl",
      "通过自然语言创建定时任务",
      {
        natural_language = {
          type = "string",
          description = "自然语言时间与意图描述，如 每天9点提醒我检查git状态",
        },
        prompt = {
          type = "string",
          description = "可选，任务执行时发送给 agent 的提示词",
        },
        agent = {
          type = "string",
          description = "可选，目标 agent 名称；缺省使用当前会话 agent",
        },
      },
      { "natural_language" },
      ScheduleOps.schedule_create_nl,
      "write"
    )

    register_tool_definition(
      Registry,
      "schedule_list",
      "列出当前 agent 的定时任务",
      {
        agent = {
          type = "string",
          description = "可选，目标 agent 名称；缺省使用当前会话 agent",
        },
      },
      {},
      ScheduleOps.schedule_list,
      "read"
    )

    register_tool_definition(
      Registry,
      "schedule_delete",
      "删除指定定时任务",
      {
        job_id = {
          type = "string",
          description = "任务 ID",
        },
        agent = {
          type = "string",
          description = "可选，目标 agent 名称；缺省使用当前会话 agent",
        },
      },
      { "job_id" },
      ScheduleOps.schedule_delete,
      "write"
    )

    register_tool_definition(
      Registry,
      "schedule_pause",
      "暂停指定定时任务",
      {
        job_id = {
          type = "string",
          description = "任务 ID",
        },
        agent = {
          type = "string",
          description = "可选，目标 agent 名称；缺省使用当前会话 agent",
        },
      },
      { "job_id" },
      ScheduleOps.schedule_pause,
      "write"
    )

    register_tool_definition(
      Registry,
      "schedule_resume",
      "恢复指定定时任务",
      {
        job_id = {
          type = "string",
          description = "任务 ID",
        },
        agent = {
          type = "string",
          description = "可选，目标 agent 名称；缺省使用当前会话 agent",
        },
      },
      { "job_id" },
      ScheduleOps.schedule_resume,
      "write"
    )
  end

  function M.register()
    register_file_tools()
  end

  function M.set_workspace_root(path)
    return PathUtils.set_workspace_root(path)
  end

  function M.get_workspace_root()
    return PathUtils.get_workspace_root()
  end

  package.loaded["rlizx.file_manager"] = M
end

return M