# 更新日志

## v2.1.2（2026-11-23）

### 修复
- **跨地图后全部加成永久失效**：引擎在换图（出征历练、门派战斗地图、RPG 地图）打包前调用 `ClearNoSyncModifier`（`FightMapMgr.cs:3070-3078` → `NpcPropertyMgr.cs:810-821`），把 `def.Sync == 0` 的修正器从角色身上移除且不写入 `SL_NpcPack`；`ModifierDef._Base` 的默认 `Sync` 就是 0。本模组 34 条 Modifier 此前均未声明 `<Sync>`，因此衍天珠的佩戴心境 +100 / 伤势恢复、服用得到的根本灵气、衍天诀各境界加成，都会在来回一次地图后消失。现全部补上 `<Sync>1</Sync>`，随打包往返保留。
- **衍天佩增幅换图后同样丢失**，且 `pei.lua` 只信内存缓存 `st.mods`，Effect 被引擎外部清掉后永不补挂。现在每次同步都先 `FindModifier` + `IsVaild` 实测存活，缺失即补。
- **衍天珠多颗同戴、卸下一颗**会连带清除仍在佩戴的那颗的全部效果：引擎按名字 `RemoveModifier` 是 `FindAll` 全杀。`module.lua` 改为每秒对账，佩戴中但效果缺失即自动补挂，最多 1 秒恢复；多颗同戴仍然只生效一份。

### 新增
- 开局经历「万法阁·衍天遗泽」除灵石 ×300 外，额外赠送 **衍天珠 ×4、衍天佩 ×4**，经历描述同步说明。

## v2.1.1（2026-11-20）

### 美术
- 三柄本命飞剑换上专属外观：灵析剑 / 灵源剑 / 灵道剑各有 128×128 背包图标（`wfg_item_<k>_jian.png`）与法宝图（`wfg_fabao_<k>_jian.png`），`Item_YanTian.xml` 的 `TexPath` / `FabaoTexPath` 不再复用原版 `object_PTjian01` / `object_MBjian01`。
- 衍天能源中心换成独立外观 `wfg_building_halleng.png`（553×980，与灵玉峰同尺寸基准），不再与灵玉峰共用一张贴图。

### 修复
- 本命飞剑落在地面上显示过大（约 4.2 个世界单位）：实测 `<TexScale>` 对物品不生效（`RenderPool.cs:616` 的 `Sprite.Create` 固定 100 PPU，`ItemView.cs:23` 虽乘 `def.TexScale`，实际仍按 `Item_Base` 的 0.8 渲染）。改为把法宝图裁到内容包围盒、内容高统一 100 px（39×104 / 20×104 / 51×104），并移除三处无效的 `<TexScale>`，现与原版法宝同量级。

### 说明
- 高清原图留在本机 `_art/fabao_hi_*.png`；`_art/` 是本机素材工作区，已加入 `.gitignore`，不进仓库。

## v2.1.0（2026-11-20）

### 新增
- 专属秘宝「灵道剑」（`WFG_Item_LingDaoJian`）：本命法宝·总纲解锁第三柄本命飞剑配方，材料 **衍天珠 ×1 + 灵石 ×49**，走官方法宝炼制（Level 20 必成）。
- 道行存取：佩带并认主后，衍天诀角色指令栏出现「灵道剑」，可把自身道行存入剑内或取回；存道上限为当前道行，取回上限为剑内存储。
- 威力成长：每 1 点存道 +1% 法宝威力，**无上限**；加成通过角色级 `NpcFight_FabaoPowerAddP` 生效，因此作用于佩者全部法宝。
- 存道归属修士（存档字段 `ld`），换剑、卸下或转修他法都不会丢失；未佩剑或转修时加成失效，但随时可取回。

### 说明
- 引擎限制：XLua 未导出 `FabaoData`，法宝特殊能力枚举也不可扩展，偷天七绝针的 `AgeAddPowerUp` 无法照搬为物品级能力，改用动态修正器实现同等效果。
- 灵道剑与灵析剑/灵源剑共用剑形贴图（`object_PTjian01` / `object_MBjian01`）。
- 旧档补发：秘籍的 `<Fabaos>` 只在学会瞬间写入角色，已学过总纲的老存档由 `module.lua` 的 `EnsureFabaoFormula` 每秒检查参悟树节点（`IsLearnedTreeUnit("WFG_Tree_YanTian_D0")`）并调用 `LearnFabaoFormulas`（幂等）补学灵道剑配方；新增物品与配方定义仍需完全重启游戏才会加载。
- 判定键坑：`IsLearnedEsoterica` / `CheckIsLearnEsotericaDisplayName` 都以「秘籍实例 ID」为键（`NpcPractice.cs:1149`、`:1817-1838`、`:751-767`），传 XML 定义名恒为 false，因此不能用定义名判定是否学过总纲。
- 按钮事件挂载失败修正：灵道剑窗里调用了仓库中并不存在的全局 `cb0`，异常被挂载函数的 pcall 吞掉，导致按钮全部「看得见、点不动」。该文件内补上 `local function cb0`，并让挂载失败写 `WFG:Error` 与提示框，不再静默。
- 灵道剑界面只用已在灵析剑/灵源剑界面中实机验证过的 FairyGUI 原语（`browser` 壳、`MakeFlatButton`、`GRichTextField`、`AddClick`），不使用仓库内未经上机验证的 `Scripts/WFG/ui/kit.lua`；数量调节改为 ±1/±10/±100/±1000/一半/全部/清零按钮，不用滑块。

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
