# 开发经验 · UI 与部署（万法阁）

本文件把 2026-11-17 ~ 11-18 两天的实机打磨压缩成可复用的操作手册：**怎么部署验收、Lua 里哪些 UI 写法能用、哪些必然静默失败、出了症状先查哪一条**。每条结论都来自实证（acs_src 行号 / 游戏日志 / 实机截图），不是推断；新增结论请沿用「症状 → 根因 → 修法 → 证据」四段式追加。

配套文档：[功法配置规范](功法配置规范.md)（XML 层）、[UI 设计规范](UI设计规范.md)（设计规则与验收）、[研究-官方UI框架手册](研究-官方UI框架手册.md)（框架全貌）、[研究-社区UI实践](研究-社区UI实践.md)（社区做法）。

---

## 1. 部署与验收（固定五步，缺一步都不算完成）

```bash
# 1) 静态校验：字段/引用/语法
python C:/Users/28040/.dsh/skills/acs-mod-dev/scripts/acs_mod.py check "D:/Work/MOD_Dev/了不起的修仙模拟器/万法阁"
# → 期望「校验通过」，0 错 0 警

# 2) Lua 语法（有 luac 时）
luac -p <每个改动的 .lua>

# 3) 复制（PAYLOAD 见 tools/deploy.py）
python tools/deploy.py            # 正式；--dry 只打印

# 4) 一致性校验：逐文件 SHA-256
python tools/verify_deploy.py     # 退出码 0 = 「一致：全部文件 SHA-256 相同」

# 5) 完全退出游戏 → 重新启动
```

红线：

- **「复制成功」不等于「部署成功」**。必须跑 `verify_deploy.py`（它读 `PAYLOAD` 清单，报缺失/多余/内容不同），退出码 0 才算数。
- **不能只退到主菜单**。mod 的 `Info.json`、`Settings/*.xml`、`Scripts/**` 都在启动时加载；验证一律「完全退出进程再重开」。
- `PAYLOAD` 与仓库交付文件一一对应（当前 40 个文件：`Info.json`、`Preview.png`、`README.md`、`Settings/`、`Scripts/`、`Resources/`）。新增顶层目录要同步进 `deploy.py` 与 `verify_deploy.py` 的清单，否则会「部署了但没带过去」。
- 部署目标：`E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\Mods\万法阁`。本机只有这一份安装（Steam AppID 955900），不要按 D:/C:/F: 猜路径。

> 工具环境注记：本机 DSH 会话在 `workspace-write` 下执行任何 shell 都会被拒（`niubash: rubash: Permission denied`，failure.code=EXECUTION_RESTRICTED，连 `pwd` 都一样）。部署需要 `danger-full-access`。这是环境限制，不是脚本问题——不要浪费时间改写脚本。

---

## 2. 窗口生命周期：顺序错了整窗打不开

ACS 的 Lua 窗口走 `Wnd_Simple`，它的 `UIInfo` 在 `OnInit` 里才 `CreateInstance`。因此：

```lua
w:SetSize(600, 520)        -- 1 尺寸
w:Show()                   -- 2 必须先 Show
w:SetTitle("衍天 · 创造")   -- 3 之后才能碰 UIInfo
w:SetHtml(html)            -- 4 富文本；晚于 Show
```

- **Show 之前调用 `SetHtml`/`SetTitle`** → `NullReferenceException at Wnd_Simple.SetHtml`，窗根本不出现，且异常只在 Player.log 里，游戏内日志看不到。
- 打开流程一律用**逐步 pcall**，失败时打印步骤名：

```lua
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then WFG:Log("[create] 步骤失败 " .. name .. "：" .. tostring(err)) end
  return ok
end
-- step("show", ...) step("title", ...) step("html", ...) step("build", ...) step("layout", ...) step("reload", ...)
```

没有这层包裹时，一次 `SetTitle` 提前调用会让整窗不出现，日志里**只有一行 NRE**，很容易误判成「版本坏了」。v6 就是这样被判死的——实际是顺序问题。

---

## 3. 控件：FairyGUI 裸类型多数不可用，用官方 InGame 包

| 需求 | 结论 | 原因/写法 |
|---|---|---|
| 按钮 | **用** `ui://0xrxw6g7hdhl18`（GButton） | 裸 `GButton` 无 `title` 子件，既没文字也没外观 |
| 勾选 | `ui://0xrxw6g7hdhl1a` | 裸 GButton 的 buttonMode 不够 |
| 滑条 | `ui://0xrxw6g7hdhl1e`（UI_SliderH） | 裸 `GSlider` 无 `grip` 子件 → 拖不动 |
| 输入框 | `ui://0xrxw6g7hdhl1c`（UI_InputTextField） | 子件 1 是 `GTextInput`，取 `comp:GetChildAt(1)` |
| 列表 | 不要用 `GList:AddItemFromPool()` | 无 `defaultItem` 时返回 nil |
| 提示气泡 | `Wnd_TipPopPanel.Instance:AddBind` | `obj.tooltips` 依赖 `UIConfig.tooltipsWin`，本工程各处都没赋值 → 全失效 |
| 图形底板 | `GGraph` 在**窗口内部**可用 | 放到 `GRoot.inst` 覆盖层**不渲染**（见 §6） |

> 滑条范围不能 `min == max`：只允许 1 档时把 `max` 设为 2，并用 `touchable=false` / `grayed=true` 锁定，否则 FairyGUI 计算 `(value-min)/(max-min)` 得 0/0，`value` 变成 `-nan(ind)`。

加入方式：

```lua
local obj = w:AddObjectFromUrl("ui://0xrxw6g7hdhl18", 0, 0)  -- 自动挂监听，且不递归子件
obj:SetPosition(x, y)
obj:SetSize(wd, 34)
obj.title = "确认创造"
```

`Wnd_LuaWindowBase.AddObj` 只给**被加入的那个对象**挂监听、不递归 → 想接子件事件得自己 `AddObjectFromUrl` 拿对象，或按控件名在 `OnObjectEvent` 里分发。

---

## 4. 点击：`onClick:Add(fn)` 在 XLua 下静默失败

**症状**：按钮点下去毫无反应，日志干净。

**根因**：`FairyGUI.EventListener.Add` 有 0 参/1 参两个重载，XLua 推断不出 Lua 闭包该转成哪个委托，异常又被 `pcall` 吞掉 → 监听根本没挂上。

**可用写法（按优先级）**：

1. **按控件名分发**（推荐，和项目现有窗口一致）：

```lua
function W:OnObjectEvent(sender, evt)
  local n = sender and sender.name
  WFG:Log("[create] 点击控件：" .. tostring(n))
  if n == "btConfirm" then ... end
end
```

2. 必须显式挂委托时，写死委托类型：

```lua
b.onClick:Add(CS.FairyGUI.EventCallback0(function() ... end))
s.onChanged:Add(CS.FairyGUI.EventCallback0(function() ... end))
```

**排查技巧**：给 `OnObjectEvent` 加一行无条件日志。日志不出现 = 事件没进来（监听/命中问题）；日志出现但没执行 = 分支名写错。这一行把「UI 不响应」拆成两类，省掉大半盲猜。

---

## 5. 布局：控件坐标属于 contentPane，不是窗口虚拟画布

- `UI_WindowEmpty.m_html` 是一个**撑满内容区**的 `GRichTextField`。往内容区直接摆按钮会压字 → 取 `contentPane:GetChildAt(1)`，改它的 `y`/`height` 把正文挪成一条带子，控件放带子下方。
- 坐标基准是 `contentPane` 的本地坐标，不是设计稿里的 `WIN_W`。两者宽度不等时，按 `WIN_W` 居中会整体偏移。
- **统一双边对齐**，别让每一行各自按自身宽度居中（那样标签列永远不齐）：

```lua
local pw = pane.width
local L, R = 64, pw - 64        -- 左标签列 / 右边界内收
label:SetPosition(L, y)
arrowR:SetPosition(R - 28, y)   -- ▶ 贴右边界内侧
bar:SetSize(R - L - 120, 24)    -- 滑条自适应
```

- 曾经用 `LO = 62 + dx` 在居中偏移上再叠一层，结果左标签被推右、右侧 ▶ 直接出卡片外。**出现「越改越歪」时先怀疑坐标系，而不是继续调数字。**

---

## 6. 地图选点：用引擎的 Magic 原生点选，不要自绘光标

**三次失败**：`GGraph` 挂 `GRoot.inst` + `GlobalToLocal` 换算 + 每帧刷新，框始终不出现（占用格变色也不出现）。说明该覆盖层不参与 mod 窗口之外的绘制/命中，不要再试第四次。

**正确路径**：把神通声明成「点地」目标，引擎自己画框、自己做占位校验，然后把格 key 交给 Lua：

```xml
<!-- Settings/Practice/Magic/Magic_YanTian.xml -->
<SelectMode>Single</SelectMode>
<SelectTarget>Point|NoBuilding|NoItem|NoPlant|Walkable</SelectTarget>
```

```lua
function M_Create:MagicEnter(IDs, IsThing)
  local key = IsThing and nil or IDs[0]   -- 非选物分支里 IDs 是格 key 列表
  WFG:Log("[magic.create] 目标地块 key=" .. tostring(key))
  ...
end
```

取证：`XiaWorld/g_emMagicTarget` 是 [Flags]（含 `Point = 2`）；`XiaWorld/UILogicMode_MagicCommand.cs:392` 非选物时 `DidApply(list, isthing: false)`；`MagicBase.MagicEnter(ids, isthing)` 原样透传给 Lua。

流程因此变成：**点地图选格 → 开素材面板 → 选材料/品级/数量/储灵 → 确认落格**。界面只负责参数，落点归引擎。

- 兜底：没走点选直接打开面板时，退回 `WFG.ui.pos:Start` 手动选点，按钮文案随落点变。
- 占用格校验用 `Things:GetThingsAtGrid`；点在占用格只提示、不扣灵气。

---

## 7. 造物与储灵（两条易错链）

**造物**：`World.map:DropItems(name, stuff, count, key, true, true, ling, addq)`。`ThingMgr:CreateItem` 在 DLL 里**不存在**，`pcall` 会把它变成静默失败。`addq` 是品级增量 float（0..1）。

**储灵调不动**：`Item_Base.xml` 起底 `<LingMax>0</LingMax>`；`ItemThing.MaxLing == 0` 时 `Thing.AddLing` 直接 return，不报错。修法双保险：

1. `D.lingFallback = 100` 作为面板显示与报价的兜底上限；
2. 造物瞬间临时抬高 `def.LingMax`，写完立即还原（别把临时值留在定义里）。

**报价链**：`def.lua CreateCost(level, quality, count)` 三参。两参调用会报 `attempt to perform arithmetic on a nil value (local 'count')`。统一 `count = count or 1`，且不要在 derive 层再做第二次折扣（曾经「×count 又打 9 折」导致价格对不上）。

---

## 8. 症状 → 根因 速查表

| 症状 | 根因 | 修法 |
|---|---|---|
| 整窗不出现，日志一行 NRE at `Wnd_Simple.SetHtml` | 在 `Show()` 之前 SetHtml/SetTitle | 固定 SetSize→Show→SetTitle→SetHtml；Open 逐步 pcall |
| 按钮点了没反应 | `onClick:Add(fn)` 委托推断失败被 pcall 吞 | `OnObjectEvent` 按控件名分发，或 `EventCallback0` |
| 按钮有字没外观 / 滑条拖不动 | 裸 GButton 无 title 子件、裸 GSlider 无 grip | 用官方 InGame 包控件（§3 表） |
| 滑条数值显示 `×-nan(ind)` | `min == max` 导致 `(value-min)/(max-min)` 为 0/0 | `max` 至少给 2；只有 1 档时锁 `touchable` 并强制 `value=1` |
| 列表为空（池化卡片） | `ClearCards` 把数据源 `rows` 一起清空；`AddItemFromPool` 返回的是 `GObject` | `ClearCards` 只清控件；`SetItems` 最后赋值 `rows`；卡片先 `asButton` 再设属性 |
| 正文出现 `[color=#...]` | 把 `SetHtml` 窗口的 UBB 标记喂给 `GRichTextField` | `GRichTextField` 用 HTML：`<font color="#...">...</font>` |
| 按钮隐藏后偏右/文字被裁 | 布局按全部按钮占位，隐藏按钮仍占 x 槽；标题字号沿用默认 | 按 `visible` 重新居中；标题子件字号调小；一行超过 pane 宽时拆行 |
| 悬停没提示 | `UIConfig.tooltipsWin` 未赋值 | `Wnd_TipPopPanel.Instance:AddBind` |
| `os.time()` 报 global 'os' 为 nil | mod 沙箱没开 os 库 | 用 `CS.UnityEngine.Time.realtimeSinceStartup` |
| `ThingMgr:GetDef` 报 invalid arguments | 第一参传了 int | 传 `CS.XiaWorld.g_emThingType.Item`/`.Building`/`.Plant` |
| 物品名显示成 `SysAxe` | 用了 `ThingDef.ThingName`（空时回落内部键） | 用实例 `thing:GetName()` |
| NPC 灵气恒为 0 | 读了不存在的 `Ling` | `Thing.LingV`（只读）+ `MaxLing` |
| 参悟树整片空白 | 秘籍 `StarLevel ≥ 3` 让 `Wnd_GongSkillTree` 控制器越界 | `StarLevel` 只能 0..2 |
| 确认窗标签/箭头不齐 | 按 `WIN_W` 而不是 `contentPane.width` 居中 | 按 pane 宽度 L=64 / R=pw-64 双边对齐 |
| 神通放了没反应 | `<SelectTarget>` 缺 `Point` 或占位标志 | `Point|NoBuilding|NoItem|NoPlant|Walkable` |
| 点了地却拿不到坐标 | 把 `IDs` 当 Thing 列表用 | 非选物分支 `IDs[0]` 就是格 key |

---

## 9. 调试取证工作法（省时间的三件事）

1. **每个关键节点打一条带前缀的日志**：`[create] 点击控件：…`、`[magic.create] 目标地块 key=…`、`[confirm.quote] …`。日志前缀就是 grep 锚点，比读代码快一个数量级。
2. **反编译取证再动手**：`acs_src` 里确认方法存在、参数个数、枚举值。`ThingMgr:CreateItem` 不存在、`Ling` 不存在、`GetDef` 第一参是枚举——这三条都是「不查就写，写了就静默失败」的典型。
3. **区分「没进来」和「进来了但没执行」**：无条件日志 + 分支日志两层，能在一轮里定位，而不是改三轮。

---

## 10. 弯路复盘（下次直接跳过）

1. **自绘 UI 覆盖层**：`GGraph` 挂 `GRoot` 三轮不可见 → 优先级应为「找引擎原生能力」高于「自己画」。原生能力一旦找到，代码量和稳定性都更好。
2. **在 Show 前配置 UI**：一次顺序错误被误判为版本回归，白花一轮排查。窗口类一律套逐步 pcall。
3. **按设计稿像素居中**：坐标系错了，调数字永远调不齐。先打印 `pane.width`/`pane.x`。
4. **靠「复制 32 文件」宣称部署完成**：没有 SHA-256 比对就无法排除「旧文件没覆盖」。验收看退出码，不看打印。

---

## 11. 复用的最小骨架

```lua
local W = {}
function W:Open(npc, tile)
  local w = ...  -- 按项目现有写法创建 Wnd_Simple
  local function step(n, f)
    local ok, e = pcall(f)
    if not ok then WFG:Log("[w] 步骤失败 " .. n .. "：" .. tostring(e)) end
  end
  step("size",  function() w:SetSize(600, 520) end)
  step("show",  function() w:Show() end)
  step("title", function() w:SetTitle("标题") end)
  step("html",  function() w:SetHtml("<p align='center'>说明</p>") end)
  step("build", function() self:Build(w) end)    -- AddObjectFromUrl 摆控件
  step("layout",function() self:Layout(w) end)   -- 按 contentPane.width 双边对齐
end
function W:OnObjectEvent(sender, evt)
  local n = sender and sender.name
  WFG:Log("[w] 点击控件：" .. tostring(n))
  if n == "btOk" then ... end
end
```

---

## 12. 官方浏览器壳的顶部筛选与滑条

- **筛选按钮不要固定宽**：`UI_bnt_buildType` 原宽 154，三枚 480 会超 `RemoteStorage` 的 `gridW=439`。按 `w=floor((gridW-gap*(n-1))/n)` 分摊，按钮标题子件 1 字号 12。
- **筛选行放在 `m_Head` 下方**：不要写死 `gridY-36`，否则与页签重叠；优先取 `head.y + head.height + 4`，取不到可信高度时退回 `gridY`。网格起点改为筛选行 +34，并按底栏 `gridY+gridH-24` 反算高度，避免 footer 与网格重叠。
- **能源面板用 `UI_SliderH`**：`UIPackage.CreateObject("InGame","SliderH")` 后必须 `.asSlider`；先设 `min<max` 再设 `value`，否则 `(value-min)/(max-min)` 得 NaN。滑条宽高用 `SetSize(w,28,false)`；程序设 `value` 不触发 `onChanged`，拖拽/点击才触发；可用 `onGripTouchEnd` 在松手后重绘状态。
- **文案居中与排版**：能源正文用 `GRichTextField` 的 `align=Center`，并先设 `autoSize=AutoSizeType.None` 再 `SetSize(gw,180)`，否则写 `text` 时控件会缩成内容宽度、整段偏左；行间用 `<br/>`，不要用 UBB。XLua 未暴露 `wordWrap`，长句要手动断行。按钮按 `visible` 重排，`WFG_EMode` 标题动态显示当前模式。
- **窗口内容不要超出 contentPane**：能源面板取 `pane.width-42`、`pane.height-96`，底部按钮与提示都在面板高度内；筛选芯片宽度总和必须等于 `gridW`。

---

## 13. 按钮重叠、二级浮窗与角色门禁（m06466 实证）

- **原生按钮缩放仍会压边**：`UI_bnt_buildType` 的背景是九宫格图形，`SetSize(141,28)` 只改逻辑尺寸，图形按原设计尺寸绘制，三枚并排就互相压住。需要精确宽度的筛选/操作按钮不要用它。
- **精确尺寸用裸 GButton 自绘**：`CS.FairyGUI.GButton()` 后 `SetSize(w,h)`、`opaque=true`、`touchable=true`；`GGraph.DrawRect(w,h,1,lineColor,fillColor)` 作背景、`GRichTextField` 作 child 1，背景与标签都设 `touchable=false`。`opaque=true` 是整块可点的关键；只画背景不设 opaque 时点击区仍是默认尺寸。
- **DrawRect 的颜色顺序**：XLua 包装签名是 `DrawRect(width,height,lineSize,lineColor,fillColor)`，第 4 个是**线色**、第 5 个才是**填充色**。写成 `fill,line` 会得到深棕底 + 浅色描边，外观很像原版按钮，容易误判成回退到了 `UI_bnt_buildType`。
- **不要写 `GTextField.fontSize`**：XLua 没有暴露 camelCase 的 `fontSize`；在同一个 `pcall` 里先写它，异常会中断后面的 `text` 与 `AddChild`，表现为按钮只有底板没有文案。小写 `fontsize`、`autoSize`、`textHeight` 是暴露的；但仍建议把 `text` 放在最后单独赋值。
- **`GTextField` 默认 `autoSize=Both`**：写 `text` 会把控件缩成文字大小，`align=Center` 只在自己的文字宽度内生效。需要整宽居中时，先设 `autoSize=AutoSizeType.None`，再 `SetSize(w,h)`，最后写 `text`。
- **下拉不要循环切换**：触发器用 `B:SetDropdowns`，浮层用 `B:ShowOptionPopupAt`；浮层加在 `contentPane` 最后，坐标用父控件局部坐标相加，越界先左右夹取再向上翻，避免出框。
- **选项回调顺序**：先 `CloseDropdown()`（Dispose 浮层）再执行业务回调；不要在浮层仍存活时重建网格，否则旧行控件与旧闭包会叠在池里。
- **能源按钮按可见项重排**：显隐后必须重算 x；固定槽位会让隐藏按钮继续占位。两行按钮分别居中，96 宽、gap 8，文字用 child 1 的 `text` 改，不要改 `GButton.title`（自绘按钮没有 title 子件绑定）。
- **角色门禁放在所有显示入口**：`OpenNpc` 与 `Show` 都要检查 `isYanNpc`；拒绝时清空当前角色、关闭已开窗口，只弹提示。只在按钮点击处拦截，选中角色回调仍可绕过。
---

## 14. 下拉美化、点击外部关闭与浮窗防溢出（m06956 实证）

- **触发器留出内边距**：筛选条不要从 `gridX` 起贴住背景框；按 `inset=8` 收窄为 `gridW-16`，两行高度改为 32、行距 6，网格起点再留 8px。触发器右侧加 `▾` 子件，标签宽度收窄到 `w-24`，展开时箭头改 `▴`。
- **浮层做层次**：主面板用米色填充 + 深棕 1px 边框，右下 4px 半透明阴影，顶部一条浅金高光；选项行去掉原生按钮边框，选中行用暖金底 + 左侧竖线 + 右侧 `✓`，悬停叠浅色层。
- **点击外部关闭**：在浮层之前向 `contentPane` 加一块全屏 `GComponent`，设 `opaque=true`、`touchable=true`，`onClick` 只调 `CloseDropdown()`；浮层必须加在挡板之后。`CloseDropdown` 先 Dispose 挡板再 Dispose 浮层，并重置所有箭头。
- **浮层翻转用触发器顶边**：只传“触发器底边+6”时，空间不够会翻到错误位置；同时传 `anchorTop=触发器顶边`，翻上时用 `anchorTop-ph-10`（再扣 4px 阴影与 6px 间距），再夹在 `contentPane` 内 10px 边距。
- **能源正文固定满宽**：`status` 先 `autoSize=None`、`SetSize(gw,180)`，写完 `text` 再 SetSize 一次；`label()` 同样先固定宽高。否则 `autoSize=Both` 会把每行缩成自身宽度，视觉上整段偏左。
- **创造页不显示库存**：`C:Render` 传 `showCount=false`，卡片 child 6 隐藏；`ShowTip` 的创造分支不再拼“库存 n”行。数据中心的“共享总库已收录”保留。
- **浮窗防溢出**：`GTextField.wordWrap` 未暴露，不能靠它自动换行。工具提示固定 310px 宽，正文 282px；名称、类别、描述、提示都先用 UTF-8 安全函数按 22 字断成 `<br/>`，再用已暴露的 `textHeight` 反算浮窗高度（取不到时按字符数估算），最后把浮窗夹在 `pane` 内 8px。定位顺序是右侧→卡片下方→卡片上方，避免翻到卡片左侧遮挡卡片导致 `rollOut` 闪烁。
- **属性名**：XLua 暴露的是小写 `fontsize`、`autoSize`、`textHeight`；没有 `wordWrap`，也没有 camelCase `fontSize`。不要把它们混写。

---

## 15. UI 设计规则（2026-11-19）

本节只做入口与最低验收；完整规则见 [UI 设计规范](UI设计规范.md)，技能侧同步在 `references/11-ui-design.md`。

- **先量后画**：从 `[ui:<key>] shell pane=... grid=...` 取实际 contentPane 与网格，所有宽度/坐标据此推导；禁止整窗 SetSize/SetScale。
- **顶部筛选**：最多两行，总宽 ≤ gridW-16，单枚 ≥120px；触发器显示“字段名+当前值+箭头”；超过两项用下拉/二级浮窗，不用循环按钮。
- **文本**：整宽居中先 `autoSize=None` → `SetSize` → 最后写 `text`；字号 `fontsize`（小写），无 `wordWrap`；GRichTextField 只认 HTML。
- **浮层**：先加全屏 blocker，点外部关闭；回调先关浮层再刷新；浮层夹在 pane 内 10px。
- **工具提示**：固定 310/282，按 22 字手动断行，`textHeight` 反算高度；右侧→下方→上方，禁止遮住悬停卡片。
- **门禁**：所有显示入口都检查；拒绝时清角色、关已开窗、只弹提示。
- **验收**：luac 全量 + `acs_mod.py check` 0/0 + `deploy.py` + `verify_deploy.py` SHA-256 全同；完全重启后三窗各开一次。

