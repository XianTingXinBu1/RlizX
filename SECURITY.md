# 安全说明

## 敏感信息保护

本项目已采取措施保护敏感信息，请遵循以下安全最佳实践：

### 1. 配置文件

**重要**: `rlizx.config.json` 包含敏感信息（API Keys、Bot Tokens），**绝不应提交到版本控制系统**。

#### 设置配置文件

1. 复制配置模板：
   ```bash
   cp rlizx.config.example.json rlizx.config.json
   ```

2. 编辑 `rlizx.config.json`，填入你自己的凭证：
   ```json
   {
     "api_key": "your-openai-api-key-here",
     "telegram": {
       "bot_token": "your-telegram-bot-token-here"
     }
   }
   ```

3. 确保 `rlizx.config.json` 被 `.gitignore` 忽略（已配置）

### 2. 环境变量（推荐）

更安全的做法是使用环境变量：

```bash
export OPENAI_API_KEY="your-api-key"
export TELEGRAM_BOT_TOKEN="your-bot-token"
```

### 3. 被忽略的文件

以下文件类型会被 `.gitignore` 自动忽略：

- `*.config.json` - 配置文件
- `*.log` - 日志文件
- `test_*.lua` - 临时测试文件
- `demo_*.lua` - 演示文件
- `/agents/**/.rlizx/` - Agent 本地数据
- `.env` - 环境变量文件

### 4. 日志文件

日志文件可能包含敏感信息，已被配置为自动忽略：

- `telegram_bot.log` - Bot 运行日志

### 5. 清理历史

如果意外提交了敏感信息，可以使用以下方法清理：

```bash
# 从 Git 历史中移除敏感文件
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/sensitive/file" \
  --prune-empty --tag-name-filter cat -- --all

# 强制推送（慎用！）
git push origin --force --all
```

### 6. 权限设置

确保配置文件的权限正确：

```bash
chmod 600 rlizx.config.json
```

### 7. 测试凭证

测试文件中使用的凭证：
- API Key: `sk-test-key-12345`（测试值，非真实）
- Bot Token: 需要从环境变量或配置文件读取

## 安全最佳实践

1. **永远不要**将真实的 API Keys 或 Tokens 提交到版本控制系统
2. 使用环境变量存储敏感信息
3. 定期轮换 API Keys 和 Bot Tokens
4. 使用不同的凭证用于开发和生产环境
5. 限制 API Key 的权限和范围
6. 启用 Bot 的两步验证（如果支持）
7. 定期审计访问日志

## 泄露检测

如果怀疑凭证泄露，立即：
1. 撤销或轮换所有相关的 API Keys 和 Tokens
2. 检查使用情况日志
3. 通知服务提供商
4. 审查访问控制

## 联系方式

发现安全问题，请通过以下方式联系：
- 提交 Issue（不包含敏感信息）
- 私信项目维护者

---

**最后更新**: 2026-03-20