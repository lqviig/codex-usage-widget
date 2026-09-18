# Security Policy

## Reporting a vulnerability

请勿在公开 Issue 中提交令牌、账户信息、日志或漏洞细节。请通过 GitHub 私信或仓库维护者指定的私密渠道报告安全问题。

## Credential handling

本项目不应读取浏览器资料、浏览器 LocalStorage 或操作系统凭据存储。DeepSeek 数据仅使用用户显式设置的 `DEEPSEEK_USER_TOKEN` 环境变量；该值不得提交到 Git、Issue、Pull Request 或日志。

如果你意外提交了令牌，请立刻在平台撤销或轮换该令牌，并从 Git 历史中清除泄露内容。
