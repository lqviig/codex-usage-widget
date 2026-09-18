# Codex Usage Widget

一个常驻在 Windows 桌面的轻量悬浮窗，用于查看 Codex 的 5 小时及每周剩余额度、官方 Token 统计，以及可选的 DeepSeek 当日消费、Token 和请求次数。
<img width="360" height="410" alt="image" src="https://github.com/user-attachments/assets/876427f2-2e6c-4c08-929e-3d55f194339f" />

## 功能

- Codex：5 小时 / 每周剩余额度与重置时间
- Codex：官方账户的今日 Token；若服务端不提供日统计则显示累计 Token
- DeepSeek：可选的当日消费、Token、请求次数
- DeepSeek：绿色“空闲时段”与红色“高峰时段”状态
- 窗口拖动、位置与折叠状态记忆、手动刷新、失败时保留上次数据
- Codex 每 60 秒刷新，DeepSeek 每 5 分钟刷新

## 系统要求

- Windows 10 或 Windows 11
- 已登录的 Codex 桌面端或 Codex CLI
- Codex 附带的 Python 运行时；脚本默认使用 `%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`

## 安装与启动

1. 下载或克隆此仓库。
2. 双击 [`启动用量条.cmd`](outputs/usage-pet/启动用量条.cmd) 启动。
3. 如需自动启动，在 Windows“启动”文件夹中创建 `启动用量条.cmd` 的快捷方式。

右上角 `−` 折叠，`↻` 手动刷新，`×` 关闭。拖动窗口可改变位置。

## 数据来源

Codex 数据通过本机 [Codex App Server](https://learn.chatgpt.com/docs/app-server) 的 `account/rateLimits/read` 与 `account/usage/read` 获取，复用现有 Codex 登录，不读取或保存 Codex 账号凭据。

DeepSeek 数据通过平台网页使用的用量端点读取，需要用户明确提供自己的 `DEEPSEEK_USER_TOKEN`。在 PowerShell 中设置当前会话变量：

```powershell
$env:DEEPSEEK_USER_TOKEN = '你的 DeepSeek 平台令牌'
```

为长期使用，请在 Windows 的用户环境变量中创建同名变量后重新登录。令牌不会被写进仓库；不要把令牌贴进 Issue、截图或提交记录。未配置令牌时，DeepSeek 区域会显示相应提示，Codex 区域仍可正常工作。

DeepSeek 令牌由使用者自行从自己的 DeepSeek 平台账户取得。本项目不会读取浏览器资料、浏览器缓存或凭据管理器，也不会自动保存令牌。

## DeepSeek 时段规则

官方定价规则为：北京时间周一至周五 09:00–12:00、14:00–18:00 属于高峰时段；其他时间为空闲时段。高峰显示红色，空闲显示绿色。该标记反映定价时段，并不代表实时服务器负载。规则来源：[DeepSeek 模型与价格](https://api-docs.deepseek.com/quick_start/pricing/)。

## 项目结构

| 文件 | 用途 |
| --- | --- |
| `outputs/usage-pet/UsageWidget.ps1` | WPF 悬浮窗与刷新调度 |
| `outputs/usage-pet/fetch_usage.py` | Codex 额度和 Token 读取 |
| `outputs/usage-pet/fetch_deepseek.py` | DeepSeek 今日用量读取 |
| `outputs/usage-pet/DeepSeekPeriod.ps1` | 高峰 / 空闲时段判断 |
| `outputs/usage-pet/启动用量条.cmd` | 手动启动入口 |
| `outputs/usage-pet/WatchChatGPT.ps1` | 可选：检测 ChatGPT 启动后打开悬浮窗 |

## 安全说明

- 不提交账户令牌、缓存数据或本地状态文件。
- DeepSeek 脚本不扫描浏览器配置文件、不读取浏览器 LocalStorage，也不自动提取凭据。
- DeepSeek 的用量端点并非面向开发者公开的稳定 API，字段或访问方式改变时，该区域可能不可用。

## 踩坑记录

开发与排障过程中实际踩到的坑及解决办法，按主题分组（DeepSeek 取数、PowerShell/WPF 界面、脚本与运维、设计取舍），见 [PITFALLS.md](PITFALLS.md)。

## 许可证

本项目使用 [MIT License](LICENSE)。
