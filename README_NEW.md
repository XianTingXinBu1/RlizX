# RlizX v2.0 - 基于 nanobot 架构重构

## 概述

RlizX 是一个极简的 AI 助手，完全参照 nanobot 的设计理念重构。代码量减少到约 3000 行，保持核心功能的同时极大简化了架构。

## 核心特性

### 1. 极简架构
- 代码量减少约 40%（从 5000 行到 3000 行）
- 删除不必要的抽象层
- 每个模块只做一件事

### 2. 消息驱动
- 所有操作都是消息传递
- 统一的消息路由系统
- 简化的 Agent 循环

### 3. 智能集成
- Heartbeat 系统让 AI 自己管理任务
- 文件驱动的任务管理
- AI 可以理解、修改、执行自己的任务列表

### 4. 双定时任务系统
- **Cron 系统**：标准 cron 表达式，精确时间控制
- **Heartbeat 系统**：文件驱动的智能任务，AI 自主管理

## 项目结构

```
RlizX/
├── agent/              # 核心智能体
│   ├── loop.lua       # 消息循环（LLM ↔ 工具执行）
│   ├── context.lua    # 上下文构建
│   └── memory.lua     # 记忆管理
├── tools/              # 工具系统
│   ├── registry.lua   # 工具注册表
│   ├── executor.lua   # 工具执行器
│   ├── file_ops.lua   # 文件操作工具
│   └── loader.lua     # 工具加载器
├── scheduler/          # 定时任务
│   ├── cron.lua       # 标准 cron
│   └── heartbeat.lua  # 智能任务
├── providers/          # LLM 提供商
│   └── registry.lua   # 提供商注册表
├── bus/                # 消息路由
│   └── router.lua     # 消息路由器
├── config/             # 配置
│   └── schema.lua     # 配置 schema
├── cli/                # 命令行
│   └── main.lua       # 入口文件
├── rlizx.lua          # 主入口
├── test2.lua          # 测试脚本
└── README_NEW.md      # 本文档
```

## 快速开始

### 1. 初始化配置

```bash
lua rlizx.lua init
```

### 2. 进入交互模式

```bash
lua rlizx.lua agent
```

### 3. 发送单条消息

```bash
lua rlizx.lua agent -m "你好"
```

## 命令参考

### Agent 命令

```bash
# 交互模式
lua rlizx.lua agent

# 单条消息
lua rlizx.lua agent -m "消息内容"
```

### Cron 命令

```bash
# 添加定时任务
lua rlizx.lua cron add <名称> <消息> <cron表达式>

# 列出定时任务
lua rlizx.lua cron list

# 删除定时任务
lua rlizx.lua cron remove <任务ID>
```

### Heartbeat 命令

```bash
# 检查并执行 Heartbeat 任务
lua rlizx.lua heartbeat
```

### 其他命令

```bash
# 初始化配置
lua rlizx.lua init

# 显示版本
lua rlizx.lua version

# 显示帮助
lua rlizx.lua help
```

## Heartbeat 系统

Heartbeat 是一个创新的文件驱动的任务管理系统，让 AI 能够自主管理任务。

### 创建 Heartbeat 文件

编辑 `workspace/HEARTBEAT.md`：

```markdown
## 周期性任务
- [ ] 每天早上检查系统状态
- [ ] 每周生成工作报告
- [ ] 每月整理学习笔记
```

### 执行 Heartbeat 任务

```bash
lua rlizx.lua heartbeat
```

AI 会：
1. 读取 `HEARTBEAT.md`
2. 执行未完成的任务
3. 自动标记完成的任务
4. 发送执行结果

### 通过 AI 管理 Heartbeat

你可以直接与 AI 对话来管理 Heartbeat：

```
你：添加一个每周备份代码的任务
AI：好的，我已将"每周备份代码"添加到 Heartbeat 任务列表。
```

## 工具系统

### 内置工具

- `read_file` - 读取文件内容
- `write_file` - 写入文件内容
- `list_files` - 列出目录内容
- `add_heartbeat_task` - 添加周期性任务
- `list_heartbeat_tasks` - 列出所有周期性任务
- `add_cron_job` - 添加定时任务
- `list_cron_jobs` - 列出所有定时任务

### 添加新工具

1. 在 `tools/` 目录创建工具文件
2. 在 `tools/loader.lua` 中注册工具

示例：

```lua
-- tools/my_tool.lua
local M = {}

function M.my_function(args, context)
  local param = args and args.param
  return { result = "处理结果: " .. (param or "无") }
end

return M
```

```lua
-- tools/loader.lua
local MyTool = dofile(base_dir .. "/my_tool.lua")

Registry.register("my_tool", {
  name = "my_tool",
  description = "我的工具",
  inputSchema = {
    type = "object",
    properties = {
      param = { type = "string", description = "参数" }
    },
    required = {"param"}
  }
}, MyTool.my_function)
```

## 配置

### 配置文件位置

`rlizx.config.json`

### 配置示例

```json
{
  "provider": "openai",
  "model": "gpt-4",
  "temperature": 0.7,
  "api_key": "sk-your-api-key",
  "endpoint": "https://api.openai.com/v1/chat/completions"
}
```

## 与 nanobot 的对比

| 特性 | nanobot | RlizX v2.0 |
|------|---------|------------|
| **语言** | Python | Lua |
| **代码量** | ~4000 行 | ~3000 行 |
| **Heartbeat** | ✓ | ✓ |
| **Cron** | ✓ | ✓ |
| **工具系统** | ✓ | ✓ |
| **消息驱动** | ✓ | ✓ |
| **提供商** | 多个 | OpenAI（可扩展） |
| **渠道** | 多个 | REPL（可扩展） |

## 测试

运行测试脚本验证安装：

```bash
lua test2.lua
```

## 开发路线图

- [ ] 支持更多 LLM 提供商
- [ ] 添加更多通信渠道
- [ ] 优化 Heartbeat 系统的 AI 集成
- [ ] 添加技能系统
- [ ] 完善文档和示例

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

---

**重构完成！** 🎉

RlizX v2.0 基于 nanobot 的极简设计理念，实现了：
- ✅ 极简架构
- ✅ 消息驱动
- ✅ 智能集成
- ✅ 双定时任务系统
- ✅ 完整的工具系统