# 更新日志

## v2.0.1（2026-11-19）

### 修复
- 衍天珠「服用后提高根本灵气」无效：服用标记 `MaxStack=0` 使引擎根本不登记该 Modifier（`FindModifier` 恒空），Lua 侧又对原始 `Npc` 调用了不存在的 `GetModifierStack`，两处叠加导致每秒结算读不到层数。现改为 `MaxStack=99` 并经 `NpcLuaHelper:GetModifierStack` 读取，服用回灵与永久根本灵气层数恢复正常。

### 新增
- 衍天珠服用后增加筑基值：尚未入门的智慧生灵服用 +10000 筑基值（筑基需 25000，约 40%）；为此移除原 `DiscipleOnly` 限制。
- 衍天珠佩带效果：除心境 +100 外，新增伤势自然恢复 +50%（引擎 `RecoveryPower`），并每秒回复 0.3% 最大气血与 1% 最大灵气。
- 数值与文案同步到物品描述、凝练窗提示、README 与设计文档。

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
