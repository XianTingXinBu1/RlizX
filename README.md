# RlizX

一个基于纯 Lua 实现的命令行 AI 编程助手，提供轻量级的多 Agent 管理和长期记忆功能。

## 特性

- **纯 Lua 实现** - 无外部依赖，开箱即用
- **多 Agent 系统** - 每个 Agent 独立配置和记忆空间
- **交互式 REPL** - 支持自动补全、历史记录、命令系统
- **长期记忆** - 工作记忆和角色设定持久化
- **混合检索** - 智能记忆检索与上下文构建
- **TLS 支持** - 通过 C 扩展支持 HTTPS 请求
- **流式响应** - 支持 OpenAI 兼容 API 的流式输出
- **命令补全** - 智能命令和 Agent 名称补全

## 安装

### 前置要求

- Lua 5.1 或更高版本
- GCC（用于编译 TLS 模块）
- OpenSSL 开发库

### 编译 TLS 模块

```bash
cd src/TLS
make
```

### 配置

编辑 `rlizx.config.json` 配置你的 API：

```json
{
  "openai": {
    "endpoint": "https://api.openai.com/v1/chat/completions",
    "api_key": "your-api-key-here",
    "model": "gpt-4",
    "timeout": 60,
    "temperature": 1,
    "stream": true,
    "ca_file": "/path/to/cert.pem",
    "verify_tls": true
  }
}
```

## 使用

### 启动 REPL

```bash
lua rlizx.lua
```

### 基本命令

```bash
# 显示帮助
lua rlizx.lua help

# 显示版本
lua rlizx.lua version

# 运行配置检查
lua rlizx.lua check
```

### REPL 指令

REPL 启动后，可以使用以下命令：

- `/help` - 显示帮助
- `/status` - 显示当前状态
- `/version` - 显示版本
- `/clear` - 清屏
- `/exit` - 退出 REPL
- `/switch <名称>` - 切换当前 Agent
- `/agent list` - 列出所有 Agent
- `/agent add <名称>` - 新增 Agent
- `/agent delete <名称>` - 删除 Agent

### 快捷键

- `↑/↓` - 历史命令导航 / 补全项选择
- `←/→` - 光标移动
- `Backspace` - 删除字符
- `Ctrl+C` - 退出 REPL
- `/` 后继续输入 - 弹出命令补全

## 项目结构

```
rlizx/
├── agents/               # Agent 数据目录
│   └── <agent_name>/
│       └── .rlizx/
│           ├── config.json    # Agent 配置
│           ├── memory/        # 工作记忆
│           └── role.txt       # 角色设定
├── src/
│   ├── Check/           # 配置检查模块
│   ├── Gateway/         # 网关层
│   ├── Hub/             # 核心业务层
│   │   ├── hub.lua      # 主逻辑
│   │   ├── config.lua   # 配置管理
│   │   ├── http.lua     # HTTP 请求
│   │   ├── memory.lua   # 记忆管理
│   │   ├── agent.lua    # Agent 管理
│   │   └── utils.lua    # 工具函数
│   ├── REPL/            # 交互式环境
│   └── TLS/             # TLS C 扩展
├── rlizx.lua            # 入口文件
└── rlizx.config.json    # 全局配置
```

## Agent 系统

每个 Agent 拥有独立的：

- **配置文件** (`config.json`) - API 模型、参数等
- **工作记忆** (`memory/`) - 对话历史和上下文
- **角色设定** (`role.txt`) - Agent 的角色定义

创建新 Agent：

```
/switch my-agent
```

这将自动创建 `agents/my-agent/` 目录及其配置文件。

## 架构设计

### 分层架构

1. **REPL 层** - 用户交互和命令解析
2. **Gateway 层** - 输入输出路由和内存管理
3. **Hub 层** - 业务逻辑和 API 调用
4. **Check 层** - 配置验证和健康检查

### 记忆系统

- **工作记忆** - 存储最近的对话交互
- **角色设定** - 定义 Agent 的行为和风格
- **混合检索** - 根据上下文动态构建提示词

## 开发

### 添加新功能

1. 在对应模块目录添加 Lua 文件
2. 通过 `dofile()` 加载模块
3. 遵循纯 Lua 实现原则

### 测试

```bash
lua rlizx.lua check
```

## 版本历史

### v0.1.0

- 初始版本
- 实现 REPL 交互环境
- 支持 Agent 管理
- 集成长期记忆系统
- 支持 TLS 和流式响应

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 致谢

感谢所有贡献者和用户的支持。