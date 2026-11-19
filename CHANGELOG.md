# 更新日志

## v2.0.0（2026-11-19）

首个 GitHub 版本，与游戏内 `Info.json Version=200` 对应。

### 新增
- 衍天佩：手工台「1 衍天珠 + 10 任意木料」制作，佩戴后按已学 14 项衍天诀技能逐项解锁增幅，主动神通「衍天·炼石（佩）」。
- 手机端适配基础设施：`tools/check_compat.py` 双端静态体检、`tools/package_release.py` 打包、`tools/bump_version.py` 版本号、`.github/workflows/release.yml` 自动发版。
- 诊断探针 `tools/probe_mod`：一次进游戏即可判明移动端是否加载 Lua、内置依赖是否存在、逻辑分辨率与触摸支持。
- `docs/手机端适配.md`：安卓安装路径、日志抓取、症状对照与已知限制。

### 已知限制
- 部分窗口仍依赖内置 `SimpleWindow`；落点选择与悬停提示未做触屏改造（待真机验证后处理）。
- 窗口为固定像素尺寸，小屏设备可能溢出。
