# 踩坑记录

开发、部署和日常排障中实际遇到过的坑，以及验证过的解决办法。按主题分组，供后续维护者参考。

## 一、DeepSeek 用量取数

### 1.1 接口失败也返回 HTTP 200

用量端点鉴权失败时**不是** 401，而是 HTTP 200 加一个业务错误体：

```json
{"code": 40003, "msg": "Authorization Failed (invalid token)", "data": null}
```

**只判断状态码会把无效令牌当成成功。** 必须解析响应体，`code == 0` 才算拿到数据。`fetch_deepseek.py` 的 `token_accepted()` 就是为此存在的：它先打一次轻量请求验证令牌，再拉真实数据。

### 1.2 `cost` 和 `amount` 的返回结构不一致

两个端点的月份参数相同，但 `data.biz_data` 的外层形状不同：

- `/api/v0/usage/cost` → `biz_data` 是**数组**，需要取其中含 `days` 字段的元素
- `/api/v0/usage/amount` → `biz_data` 是**对象**

共用一套解析逻辑会在其中一边静默失败。`pick_block()` 统一做了归一化。

### 1.3 Token 口径要按计费类型求和

DeepSeek 把输入 token 拆成缓存命中与未命中两类，直接加 `PROMPT_TOKEN` 会得到 0：

```
今日 Token = PROMPT_CACHE_HIT_TOKEN + PROMPT_CACHE_MISS_TOKEN + RESPONSE_TOKEN
```

早期模型只上报扁平的 `PROMPT_TOKEN`，因此需要回退：当上面三项全为 0 时改用 `PROMPT_TOKEN`。请求次数在 `REQUEST` 项。

### 1.4 日期必须按北京时间比对

接口返回的 `days[].date` 是北京时间（UTC+8）的日期。用机器本地时区（或 UTC）取"今天"会在跨日、跨时区环境下拿错行——表现为"今日消费"显示 0 或者取了昨天。脚本内部固定用 `timezone(timedelta(hours=8))`。

### 1.5 令牌配置后必须重启悬浮窗

进程的环境变量是**启动时快照**的。用 `[Environment]::SetEnvironmentVariable(..., 'User')` 写入用户环境变量后，**已经在运行的悬浮窗不会看到它**，界面继续显示"请设置 DEEPSEEK_USER_TOKEN"。

必须重启悬浮窗。若由脚本代劳，还要注意两点：

```powershell
# 1) 同时设置当前进程，否则马上启动的子进程继承的仍是旧环境块
$env:DEEPSEEK_USER_TOKEN = $token
# 2) 启动子进程时显式注入，最稳妥
$info = New-Object Diagnostics.ProcessStartInfo
$info.EnvironmentVariables['DEEPSEEK_USER_TOKEN'] = $token
```

另外，让脚本自己从文件读取令牌值，**不要经命令行参数传递**——命令行会出现在进程列表里。

### 1.6 令牌过期的表现与恢复

浏览器退出登录或平台会话过期后，令牌失效，界面对应区域显示「DeepSeek 登录令牌无效或已过期」，Codex 区域不受影响。

恢复：重新从平台取得令牌 → 更新 `DEEPSEEK_USER_TOKEN` → 重启悬浮窗（见 1.5）。

## 二、PowerShell 与 WPF 界面

### 2.1 `.ps1` 必须带 UTF-8 BOM

PowerShell 5.1 在中文（GBK）代码页的控制台下，读取**无 BOM** 的 UTF-8 脚本会把中文界面文字变成乱码——而且是静默的，脚本照常运行，只是文本全错。

用编辑器保存为 "UTF-8 with BOM"，或写入后补上：

```python
path.write_bytes(b'\xef\xbb\xbf' + path.read_bytes())
```

改完文件后要复查 BOM 是否还在（有些工具改写时会丢掉）。

### 2.2 窗口高度不要硬编码

硬编码 `Height` 的结果是要么底部一大片空白，要么文字被下边缘裁掉——而且随字体缩放、DPI 变化继续漂移。

用 `SizeToContent="Height"` 让内容决定高度，折叠时只需把正文面板设为 `Collapsed`，窗口会自动收窄。位置校正放到布局完成后：

```powershell
[Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
  [Windows.Threading.DispatcherPriority]::Background, [Action]{ ... })
```

否则贴屏幕底边展开时，窗口会长到屏幕外。

### 2.3 标题和右侧按钮必须分列，否则按钮会"消失"

标题文本和右上角按钮放在同一个 Grid 单元格里、按钮用 `HorizontalAlignment="Right"` 时，长标题（例如折叠态的 `◉ 5h 100% · 周 46% · ¥0.99`）会把 Grid 撑宽，把按钮挤出可视区域。现象：折叠态只看到 ↻ 和 ×，+ 不见了。

正确做法是分列，并允许标题截断：

```xml
<Grid>
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="*"/>
    <ColumnDefinition Width="Auto"/>
  </Grid.ColumnDefinitions>
  <TextBlock Grid.Column="0" TextTrimming="CharacterEllipsis"/>
  <StackPanel Grid.Column="1" Orientation="Horizontal"/>
</Grid>
```

### 2.4 折叠成细条要同时收内边距

只隐藏正文面板，外层 `Border` 的 `Padding` 和标题行的 `Margin` 还在，细条会显得很厚。折叠时把两者一起收小（例如展开 `18,14` / 折叠 `18,8`），才能得到真正的一条。

### 2.5 单实例保护

用命名 Mutex（如 `Local\CodexUsageWidget`）防止重复启动。副作用：**旧实例还活着时新实例会静默退出**，表现为"双击没反应"。排障时先确认是不是已有实例占着锁。

### 2.6 用渲染截图自检界面

不用盯着屏幕猜：WPF 可以把窗口直接渲染成 PNG（`RenderTargetBitmap`），配合一个 `-PreviewPath` 参数输出预览图，再人工或自动核对排版——裁切、重叠、多余留白这类问题在图上比在代码里好发现得多。

## 三、脚本与运维

### 3.1 用命令行匹配杀进程时，会杀掉命令自己

```powershell
# 危险：执行这条命令的进程，其命令行里也含 'UsageWidget'
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'UsageWidget' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

结果是命令自己把自己杀了：输出中断、留下一个非零退出码，后续步骤全部没执行。

两个防线：`-and $_.ProcessId -ne $PID` 排除自身；需要匹配的关键字也可以拆开拼接，让本进程的命令行不含该字面量。

### 3.2 启动 GUI 子进程会让管道命令挂住

`[Diagnostics.Process]::Start` 或 `Start-Process` 启动的窗口进程会继承父进程的标准输出句柄。如果父命令的输出正被 shell 管道接管（例如 `| tr -d '\r'`），管道会一直等这个句柄关闭——命令挂到超时，看起来像"脚本卡死了"，其实脚本早跑完了。

在终端里跑这类脚本时，避免让输出进管道，或者改用不继承句柄的方式启动。

### 3.3 MSYS 路径不被原生程序识别

在 Git Bash 里调用 `git`、`python` 等原生程序时，`/c/Users/...` 不会被转换，报 `cannot change to`／`can't open file 'C:\c\Users\...'`。统一用 `C:/Users/...` 形式。

### 3.4 git 报 dubious ownership

如果仓库是在其它身份下创建的（例如 Codex 沙箱用户），当前用户执行 git 命令会被拒绝：

```
fatal: detected dubious ownership in repository at '...'
```

按提示加例外即可（也可只在单条命令上用 `-c` 临时指定，不写进全局配置）：

```bash
git config --global --add safe.directory "C:/path/to/repo"
# 或
git -c safe.directory="C:/path/to/repo" -C "C:/path/to/repo" status
```

## 四、设计取舍记录

**令牌来源。** 最初版本直接从浏览器 LocalStorage 自动读取平台会话令牌，做到零配置。出于凭据处理原则（见 [SECURITY.md](SECURITY.md)），改为由用户显式提供 `DEEPSEEK_USER_TOKEN`：脚本不再接触浏览器资料、本地存储或系统凭据管理器。代价是首次配置和令牌过期后都需要手动更新一次（见 1.5、1.6）。

**数据可用性。** DeepSeek 的用量端点并非面向开发者公开的稳定 API，字段或访问方式变化时该区域会不可用；这是已知风险，界面上以提示和"保留上次数据"来兜底，不影响 Codex 区域。
