# 研究：社区大型 Mod 的高级 UI 实践与选型建议

> 对象：《了不起的修仙模拟器》ACS v0.995（appid 955900）
> 目的：判断「自研（官方 FairyGUI + 自己封装）」还是「借用现成第三方 mod UI 框架/库」
> 日期：2026-11-17
> 调研者：workshop-ui（子代理），证据全部来自本机磁盘 + 可引用的公开网页

---

## 0. 结论速览（先看这段）

1. **社区里不存在一个可被别的 mod 直接 `require` 的 UI 框架**。43 个本地 mod 中，**0 个**自带独立 UI 库文件；所谓「封装」全部是各 mod 内部复制粘贴的同名函数（`AddInput/AddLable/AddButton/AddCheckBox`），散落在几十个窗口文件里。
2. 社区大型 mod 实际走的是**两条半**路线：
   - **A 派（官方正典）**：用 FairyGUI 编辑器做包 → `UIPackage:CreateObject` → 控件上 `.onClick:Add`。官方 `Mods/Example` 与 4 个工坊 mod 走这条。
   - **B 派（内置控件拼装）**：不打包，直接 `AddObjectFromUrl("ui://0xrxw6g7...")` 取游戏内置控件，坐标手算，点击统一走 `OnObjectEvent(t,obj,context)` 按 `obj.name` 分发。**UI 体量最大的 MOD版修改器（27 个窗口 / 27371 行）走这条**。
   - **C 派（纯 Lua 自绘）**：不碰 `UIPackage`，直接 `FG.GComponent()` + `GGraph:DrawRect` + `AddChild`。社区样本里没有，**这是我们万法阁 `kit.lua` 独有的第三条路**。
3. **最重要的一条工程发现**：官方两个窗口基类都把 C# 事件统一转成 `OnEventListener(context)` → `OnObjectEvent(context.type, context.sender, context)`（`Scripts/Window/windowbase.lua:17-20`、`Scripts/Window/simplewindowbase.lua:17-20`）。这个钩子默认是空函数，**实现它就能拿到窗口内所有控件的点击**，包括用 `AddObjectFromUrl` 加上去的控件。这解释了 `SimpleWindow:AddButton` 为什么「显示正常但点击不触发」——不是按钮坏了，是我们没接 `OnObjectEvent`。
4. **推荐路线：自研，不借第三方库。**具体是「官方 FairyGUI 能力 + 我们自己的 `kit.lua` 封装」，并把事件通路统一改成 `OnObjectEvent` 分发。理由与风险见 §8。

---

## 1. 调研方法与证据等级

| 步骤 | 做法 | 产物 |
|---|---|---|
| 遍历 | 扫 `workshop/content/955900/*`（37 个）+ 游戏 `Mods/*`（6 个），读 `Info.json`、探测 `*.fui.bytes` / `Scripts/Window/*.lua` / UI 库特征文件 / 许可文件 | `docs/_scan_workshop.py`、`docs/_scan_result.json`（43 行） |
| 抽样读码 | 8 个带 FUI 包的全部窗口脚本 + 最大 mod 的 27 个窗口 + 官方 `Example`、官方 `Scripts/Window/*`、`Scripts/simplewindow.lua` | 本文件 §4、§5 |
| 官方资料 | 解包 `Mods/自定义UI相关(UI DIY).rar`（bsdtar 可直接解），拿到 FairyGUI 工程 + 官方控件源 + 官方教程 | `docs/_uidiy/`、§3 |
| 联网 | 工坊框架类 mod、社区教程 | §7（仅收录可引用链接，未取到正文的明确标注） |

证据等级约定：

- **【盘证】** 本机文件读到的，行号可复查。
- **【网页】** 公开页面，附链接。
- **【推断】** 由盘证+网页推出来的，未实机验证，标出来避免误导。

---

## 2. Mod 清单（43 个，全量）

扫描口径：`.fui.bytes` = `UI/` 下任何 `*fui.bytes`；`Window` 列 = `Scripts/Window/*.lua` 数量；`UI库` = 存在疑似独立 UI 库文件（UILib / FGUIHelper / SimpleWindow 封装等）。

| # | 来源 | ID | DisplayName | 作者 | 版本 | .fui.bytes | Window | UI库 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 本体 | Example | 演示模组 | GSQ | 1 | ✓ Sample | 2 | — | 官方正典示范 |
| 2 | 工坊 | 1858385768 | 金丹助手 | AKS(Akira) | 1.25 | ✓ MakeDanAssistant | 1 | — | FUI + 转场动画 + 每帧刷新 |
| 3 | 工坊 | 1917318204 | 十度香炉（更好的空调MOD） | 挑剑拂雪 | 2.6 | ✓ C20 | 1 | — | **最小可读 FUI 模板（47 行）** |
| 4 | 工坊 | 1819060504 | 喜结良缘【匹配新修仙聊天群】 | TEFEINK | 1.7 | ✓ Orphanage | 0 | — | 窗口在 `Scripts/` 根，非 Window 目录 |
| 5 | 工坊 | 1866576765 | 批量操作 | 枫轩 | 4.1 | ✓ MultiOperationHelper | 0 | — | **全 `.luac` 编译，源码不可读** |
| 6 | 工坊 | 1873789439 | 自动搬运弥留/尸体 | 枫轩 | 4.0 | ✓ AutoOperationHelper | 0 | — | **无任何 lua**，纯 C#/dll 驱动 |
| 7 | 工坊 | 2112209838 | 自定义乾坤界 | 枫轩 | 2.02 | ✓ CustomRomoteStorage | 0 | — | 窗口 `.luac` |
| 8 | 工坊 | 1997170546 | 轻量模组加载库 ModloaderLite | 巨弩级灵压 | 5.1 | ✓ ModLoaderLite | 0 | — | **不是 UI 库**，是 DLL 加载器 |
| 9 | 工坊 | 1969434487 | **MOD版修改器** | 清风无道 | 2.1706 | — | **27** | — | **全库最大 UI 体量（27371 行）**，纯内置控件拼装 |
| 10 | 工坊 | 2594369748 | 体修淬体助手 | 清风无道 | 0.11 | — | 0 | — | **最好读的控件封装范本**（`BPRefreshWindow.lua`） |
| 11 | 工坊 | 2550287524 | 显示功法匹配度 | 无 | 1.0 | — | 0 | — | 不改窗口，**钩原版面板 `CharUI`** |
| 12 | 工坊 | 2033247609 | 智能代理人 | 大海 | 1.6 | — | 0 | — | |
| 13 | 工坊 | 2820877178 | 更多的极端天气体修吐纳 | 焰诗 | 1.14 | — | 0 | — | |
| 14 | 工坊 | 3827219717 | 3D化mod（测试版） | 淮屿鱼 | 1.5 | — | 0 | — | |
| 15 | 工坊 | 1819063341 | 修仙发廊 | TEFEINK | 1.0 | — | 0 | — | |
| 16 | 工坊 | 1820526118 | 同福客栈【可招募妖族轮回者】 | TEFEINK | 2.1 | — | 0 | — | |
| 17 | 工坊 | 1821877697 | 快速建造 | TEFEINK | 1.0 | — | 0 | — | |
| 18 | 工坊 | 1821879063 | 快速画符100% | TEFEINK | 1.0 | — | 0 | — | |
| 19 | 工坊 | 1877971681 | 显示格子更多的信息 | akira | 1.5 | — | 0 | — | |
| 20 | 工坊 | 1947524957 | 上元居1等建筑蓝图 | 陨星 | 1.0 | — | 0 | — | |
| 21 | 工坊 | 1948641743 | 掌门阁 | Are You Ok ? | 1.0 | — | 0 | — | |
| 22 | 工坊 | 1950285193 | 初期外门大吉一件套 | 夜归晨 | 0.0 | — | 0 | — | |
| 23 | 工坊 | 1952702700 | 五行交感聚灵阵建筑蓝图 | 183747902 | 1.0 | — | 0 | — | |
| 24 | 工坊 | 1966606538 | 藏经阁一键录入 | LinZhy | 2.9 | — | 0 | — | |
| 25 | 工坊 | 1970806197 | 锁灵法座 | 苏氏十三 | 4.6 | — | 0 | — | |
| 26 | 工坊 | 1972279483 | 炼器炼丹大吉小房 | 慕言帆 | 1.0 | — | 0 | — | |
| 27 | 工坊 | 1990693419 | 聚灵阵（五行控温） | 数万个基佬 | 0.0 | — | 0 | — | |
| 28 | 工坊 | 1996299754 | 内门五行宿舍大吉 | 开局一只穿山甲… | 1.0 | — | 0 | — | |
| 29 | 工坊 | 1999915554 | 真仙难度全天气大吉套餐（上） | lodo | 0.0 | — | 0 | — | |
| 30 | 工坊 | 2006475973 | 真仙难度全天气大吉套餐（下） | lodo | 1.0 | — | 0 | — | |
| 31 | 工坊 | 2178261623 | 灵●五行聚灵大阵 | 六道众生 | 0.0 | — | 0 | — | |
| 32 | 工坊 | 2267680512 | 落魄山成员 | 剑气长城二掌柜 | 1.0 | — | 0 | — | |
| 33 | 工坊 | 2524799831 | 升级功法互存 | JZ | 0.1 | — | 0 | — | |
| 34 | 工坊 | 2776432368 | 倍速结丹 | 凡夫阿牛 | 1.3 | — | 0 | — | |
| 35 | 工坊 | 2812078088 | 体修吐纳房 | Let's Quit | 1.0 | — | 0 | — | |
| 36 | 工坊 | 2825387986 | 女性立绘大修+模型小修 | archway | 1.1 | — | 0 | — | |
| 37 | 工坊 | 2847702973 | 自动画符 | JKstring | 1.3 | — | 0 | — | |
| 38 | 工坊 | 3631455466 | 归元丹等物品 | blank | 0.0 | — | 0 | — | |
| 39 | 本体 | 3D模型导入教学 | — | — | — | — | 0 | — | 教学包 |
| 40 | 本体 | JianLaiGongFa | 剑来功法 | Z | 1.2 | — | 0 | — | |
| 41 | 本体 | 万法阁 | 万法阁 | — | 1 | — | 0* | ✓ kit.lua | **本项目**（窗口在 `Scripts/WFG/ui/`） |
| 42 | 本体 | 测试 | 测试 | 天堂小灰狼 | 1.1 | — | 0 | — | |
| 43 | 本体 | 诸天万法 | 诸天万法 | — | 1 | — | 0 | — | |

\* 我们的窗口放在 `Scripts/WFG/ui/` 而非 `Scripts/Window/`，这是自定义目录，**不影响功能**（`Scripts/` 下 .lua 由 boot 链加载）。

### 2.1 统计结论

- **只有 8/43 个 mod 带 `.fui.bytes`**，其中 3 个（枫轩系）源码编译成 `.luac`、1 个（ModloaderLite）根本不是 UI、1 个（自动搬运）连 lua 都没有 → **真正可读的 FUI 窗口样本只有 3 份**：`Example`、`十度香炉`、`喜结良缘`、`金丹助手`。
- **UI 体量最大的 mod 恰恰不用 FUI 包**：MOD版修改器 27 个窗口、27371 行，全部用游戏内置 `ui://` 控件手工拼。
- **0 个 mod 声明依赖字段**：见 §6.1，`Info.json` 里根本没有 `Depends/Requires` 这种键。

---

## 3. 官方 UI 工具链（本次新挖到的关键物料）

`Mods/自定义UI相关(UI DIY).rar` 是官方随包发的 UI 制作资料，**不需要装 7-Zip，Windows 自带 `tar`（bsdtar）就能解**：

```bash
tar -xf "E:/.../Mods/自定义UI相关(UI DIY).rar" -C docs/_uidiy
```

解出来三样东西：

### 3.1 `ModUI/mod.fairy` + `ModUI/settings/`

一个 **FairyGUI 编辑器工程文件**（配 `Publish.json` / `Common.json`）。也就是说官方给的是一条「打开工程 → 新建自己的包 → 发布」的编辑器工作流，不是代码工作流。

### 3.2 `ModUI/UI制作教程.docx`（全文 11 段，官方原文）

1. 工具教程 SDK：http://fairygui.com/
2. 打开 modui 工程
3. 新建包
4. 在自己的包里创建 UI
5. 如果要用别的图素，就自己弄到自己的包里就行
6. **GSQ 的图素和控件已经内置，不用导出和加载**
7. 将主要控件设置为**导出**
8. 发布自己的包
9. 将导出的所有文件复制到 MOD 文件夹
10. 包加载方法：在 MOD 对应的 `Info.json` 里加入 `"UIPackage":"包路径"`（例如 `UI/Sample`）
11. 使用方法见 `Example\Scripts\Window\SampleWindow.lua`

对应到 `Mods/Example/Info.json` 的原生注释：

```json
"UIPackage": "UI/Sample",
"UIPackage说明": "载入UI模块，多个包用逗号隔开，没有就删掉UIPackage"
```

### 3.3 `ModUI/assets/GSQ(内置不用导出或加载)/` —— 游戏内置控件库清单

这是**官方内置控件的编辑器源文件**，`30` 个 XML。它告诉我们游戏自带哪些现成控件（**不用自己做、不用打进包、直接用 `ui://` 引用**）：

| 类别 | 控件 |
|---|---|
| Button（8） | `Button`、`Button2`、`AutoSizeButton`、`Button_iconOnly`、`IconButton`、`IconTextButton`、`FlatIconButton`、`LinkButton` |
| Checkbox（2） | `Checkbox`、`Checkbox2` |
| ComboBox（4） | `ComboBox`、`ComboBoxItem`、`ComboBoxPopup`、`DropdownButton` |
| Input（3） | `TextInput`、`TextArea`、`NumericInput` |
| List（3） | `ListItem`、`IconListItem`、`CheckIconListItem` |
| Menu（3） | `MenuBarItem`、`PopupMenu`、`PopupMenuItem` |
| ProgressBar（1） | `ProgressBar` |
| Slider（1） | `SliderH` |
| Window（2） | `WindowFrame`、`WindowCloseButton` |

> **这是本次调研最实用的一条**：输入框、下拉框、单选框、滑块、进度条、弹出菜单、带勾选的列表项，**官方全都有现成的**，用 `ui://` 直接实例化即可，不需要 FairyGUI 编辑器、不需要自己画。

---

## 4. 社区实际采用的路线（分类 + 代码）

### 4.1 A 派：FairyGUI 包 + `contentPane`（官方正典）

```lua
-- Mods/Example/Scripts/Window/SampleWindow.lua:1-13
local Windows = GameMain:GetMod("Windows");--先注册一个新的MOD模块
local tbWindow = Windows:CreateWindow("SampleWindow");
function tbWindow:OnInit()
    self.window.contentPane =  UIPackage.CreateObject("Sample", "SampleWindow");--载入UI包里的窗口
    self.window.closeButton = self:GetChild("frame"):GetChild("n5");
    local bnt1 = self:GetChild("bnt_1");
    bnt1.title = "RPG测试";
    bnt1.onClick:Add(OnClickRPG);
```

同一套写法的社区最小版（47 行整窗，最好抄）：

```lua
-- workshop/1917318204/Scripts/Window/Cg20Window.lua:1-12
local Windows = GameMain:GetMod("Windows");--先注册一个新的MOD模块
local tbWindow = Windows:CreateWindow("C20Window");
function tbWindow:OnInit()
    self.window.contentPane =  UIPackage.CreateObject("C20UI", "C20Window");--载入UI包里的窗口
    self.window.closeButton = self:GetChild("C20frame"):GetChild("n5");
    self.window:Center();
    self.bnt1 = self:GetChild("C20bnt_1");
    self.bnt1.onClick:Add(OnClick1);
    self.bnt1.data = self;

    self.InputText_1 = self:GetChild("C20n19");   -- 输入框：读 .text，tonumber 转数
end
```

点击回调靠 `sender.data` 回指窗口：

```lua
-- workshop/1917318204/Scripts/Window/Cg20Window.lua:38-46（节选）
function OnClick1(context)
    local self = context.sender.data;
    ...
end
```

**要点**：这套里 `.onClick:Add` 是**可靠**的（控件来自 `UIPackage.CreateObject` 的包内预置组件）。

列表 + 文本 + tooltip 的标准动作（`workshop/1819060504/Scripts/OrphanageWindow.lua:4-9, 38-42, 51-55`）：

```lua
self.window.contentPane = UIPackage.CreateObject("Orphanage", "OrphanageWindow");
self.window.closeButton = self:GetChild("frame"):GetChild("n5");
OrphanageWindow.List = OrphanageWindow:GetChild("n2");
OrphanageWindow.List.onClickItem:Add(OrphanageWindow.onClickItem);
...
OrphanageWindow.List:RemoveChildrenToPool();
local item = OrphanageWindow.List:AddItemFromPool();
item:GetChild("From").text = AdopterList[i].From;
item.tooltips = ...
```

转场动画 / 外部贴图（`workshop/1858385768/Scripts/Window/MakeDanAssistantWindow.lua:9-15`）：

```lua
local texPath = PhoneLib.GetModInfos("MakeDanAssistant").ResPath .. "..."
self:GetChild("bootLogo").texture = PhoneLib.LoadTextureByIO(texPath)
self.window:SetSize(275, 490)
self.window.contentPane:GetTransition("bootLogoAni"):Play()
```

### 4.2 B 派：内置控件 + `AddObjectFromUrl` + `OnObjectEvent`（老牌大 mod）

**这是全库 UI 体量最大的路线**（MOD版修改器 27371 行），也是最「抗 UI 包丢失」的路线：完全不依赖任何 `.fui.bytes`，直接引用游戏内置包里的控件。

窗口创建（绕过 `SimpleWindow` 模块，直接拿 C# 类）：

```lua
-- workshop/1969434487/Scripts/Window/QFWDModifierMainUI.lua:1-2
QFWDModifierMainUI = CS.Wnd_Simple.CreateWindow("QFWDModifierMainUI");
ModifierMain:AddWindow("QFWDModifierMainUI",QFWDModifierMainUI);
```

手工造控件 + 设置内置子件（注意 `m_title` / `m_n12` 这些**内置组件内部子件名**）：

```lua
-- workshop/1969434487/Scripts/Window/QFWDModifierMainUI.lua:674-693（AddButton4）
local obj = objs:AddObjectFromUrl("ui://0xrxw6g7lsb652ow3n",x,y);
if w==nil or h==nil then w=60; h=25; end
obj:SetSize(w, h);
obj.m_title.singleLine=true;
obj.m_title.textFormat.bold=true;
obj.m_title.textFormat.size=18;
obj.m_title.textFormat.align=CS.FairyGUI.AlignType.Center;
obj.m_title.y=0;
obj.m_title.text = value;
obj.name = name;            -- ★ 名字就是点击分发的 key
obj.m_n12.visible=false;    -- 关掉内置的装饰子件
obj.tooltips=...
return obj;
```

**点击统一走窗口级事件总线**（不挂 `.onClick`）：

```lua
-- workshop/1969434487/Scripts/Window/QFWDModifierMainUI.lua:427-431
function QFWDModifierMainUI:OnObjectEvent(t,obj,context)
    --print(t,obj,obj.name)
    if t == "onClick" then
        if obj.name == "bntShowHelp" then
```

同一 mod 里甚至把 `.onClick` 注释掉了（`AddChildToList3` 内 `--obj.onClick:Add(MapSet.ListChildOnClick);`）——这是「程序化添加的控件拿不到 `.onClick`」的直接证据。

清风无道的控件封装（**全库最干净的范本，可直接抄**）：

```lua
-- workshop/2594369748/Scripts/BPRefreshWindow.lua:291-303（AddInput）
function BPRefresh_MainWidow:AddInput(objs,name,value,x,y,w,h,topText)
    local obj = objs:AddObjectFromUrl("ui://0xrxw6g7hdhl1c",x,y);
    obj.m_title.text = value;
    obj.m_title.singleLine = true;
    obj.name = name;
    obj:SetSize(w,h);
    obj.tooltips = topText;
```

```lua
-- 同文件:338-355（AddButton）
function BPRefresh_MainWidow:AddButton(objs,name,value,x,y,w,h,topText)
    local obj = objs:AddObjectFromUrl("ui://0xrxw6g7hdhl18",x,y);
    obj:SetSize(w,h);
    obj.m_title.singleLine = true;
    obj.m_title.textFormat.bold = false;
    obj.m_title.textFormat.size = 11;
    obj.m_title.autoSize = CS.FairyGUI.AutoSizeType.Both;
    obj.m_title.text = value;
    ...
```

```lua
-- 同文件:78-80, 92-99（事件分发）
function BPRefresh_MainWidow:OnObjectEvent(t,obj,context)
    print(t,obj,obj.name)
    if t == "onClick" then
        if obj.name == "bnt6_1" then ...
        if obj.name == "BPBox61" then
            if BPRefresh_MainWidow.CheckBox61.selected then   -- ★ 勾选态读 .selected
                QFForeInte.SetValue(101,1);
```

### 4.3 C 派：纯 Lua 自绘（社区无样本，我们独有）

`D:\...\万法阁\Scripts\WFG\ui\kit.lua:101-137`：

```lua
function K.Button(text, x, y, w, h, onClick, opts)
    opts = opts or {}
    local b = FG.GComponent()
    b:SetSize(w, h, true)
    pcall(function() b.opaque = true end)
    pcall(function() b.touchable = true end)

    local bg = K.Rect(w, h, normal, opts.line or "#8A6A3A", 2)   -- GGraph:DrawRect
    bg.name = "bg"
    b:AddChild(bg)
    local lbl = K.LabelCenter(text, opts.size or 14, opts.color or "#221A10", 0, 0, w, h)
    lbl.name = "label"
    b:AddChild(lbl)

    pcall(function() b.onRollOver:Add(function() paint(opts.hover or "#F7EDD8") end) end)
    pcall(function() b.onRollOut:Add(function() paint(normal) end) end)
    if onClick ~= nil then pcall(function() b.onClick:Add(onClick) end) end
    ...
end
```

能力上它比 A/B 两派都强（**能画、能悬停、能自定配色**，A/B 只能拼现成控件），但点击通路尚未验证——见 §8.4 的待验证项。

### 4.4 旁路：不改窗口，钩原版面板

`workshop/2550287524/Scripts/CharUI.lua` 直接接管原版人物面板的现成控件，连窗口都不建：

```lua
Mod.CharUI
CharUI:PerkClicked(context)   -- 读 context.data.data / context.data.selected
self.NPCSelector.selectedIndex
```

这条路**成本最低、视觉一致性最好**，但只能「增强原版已有面板」，做不了新界面。

---

## 5. 官方窗口基类（所有路线的共同地基）

### 5.1 事件总线（本次最重要的发现）

```lua
-- E:/.../AmazingCultivationSimulator/Scripts/Window/simplewindowbase.lua:17-20
function tbBase:OnEventListener(context)
    local t = context.type;
    self:OnObjectEvent(t,context.sender,context);
end
```

```lua
-- 同文件:61-63 —— 默认空实现
function tbBase:OnObjectEvent(t,obj,context)
end
```

`windowbase.lua:17-20` 与 `windowbase.lua:48-50` 完全同构。所以：

- **`OnObjectEvent` 是窗口级事件总线**，`sender` 就是被点的那个 `GObject`（`obj.name` / `obj.data` 都可用）。
- 默认空函数 → **不实现就什么都收不到**。
- 这是**官方唯一承诺的通路**，A 派只是恰好在包内预置组件上还能用对象级 `.onClick`。

### 5.2 内置控件快捷方法

```lua
-- Scripts/Window/simplewindowbase.lua:30-34
function tbBase:AddObjectFromUrl(url,x,y)
    local obj = UIPackage.CreateObjectFromURL(url)
    self.window:AddObj(obj,x,y);
    return obj;
end

-- 同文件:40-52
function tbBase:AddButton(name,text,x,y)
    local bnt = self:AddObjectFromUrl("ui://0xrxw6g7hdhl18",x,y).asButton;
    bnt.title = text; bnt.name = name;
    return bnt;
end
function tbBase:AddLable(name,text,x,y,w,h)
    local bnt = self:AddObjectFromUrl("ui://0xrxw6g7nd594l",x,y);
    bnt:SetSize(w,h,false); bnt.title = text; bnt.name = name;
    return bnt;
end
```

**注意**：官方这个 `AddButton` **不挂任何事件**，只设 `title` / `name`——名字就是留给 `OnObjectEvent` 分发用的。这反证了「`AddButton` 点击不触发」是设计如此，不是 bug。

### 5.3 富文本窗口（`SetHtml`）

`Mods/Example/Scripts/Window/TestWindow.lua:9-13, 32, 41-43`：

```lua
self:SetHtml([=[<a href='xxx'>link text</a><br>
<input type='button' value='标题' name='BntHtml'/><br>
<p align='center'><img src='Spr/Building/building_test.png'/></p>]=])
-- 事件类型注释： "onClick","onKeyDown","onClickLink","onRightClick"
if t == "onClickLink" then world:ShowMsgBox(context.data.." Clicked",...) end
```

这条路我们已在用（`create_window.lua` 整窗一张 `<a href>`），优点是排版/换行/超链接零成本，缺点是**没有悬停、没有控件状态、不能放真控件**。

---

## 6. 可复用性评估

### 6.1 跨 mod 依赖：机制上就不支持

`Info.json` 全部键（42 个 mod 全扫）：`Name`、`DisplayName`、`GameVersion`、`Version`、`Desc`、`Author`、`IncreasedDesc`、`UIPackage`、`ID`、`Flag`、`Tags`、`IsInsideCreat`、`Previews`、`ParentModInfo`、`Sort`。

- **没有 `Depends` / `Requires` / `Dependencies` 之类字段**。
- 唯一的加载顺序控制是 `Sort`（数字越小越先？），而 42 个 mod 里**只有 4 个**填了它。
- 所以「跨 mod 依赖 UI 库」在 ACS 里只能靠 `GameMain:GetMod("库名")` + nil 判断 + 求玩家手动排序，**没有框架级保证**。
- 反面证据：`ModLoaderLite` 这种明摆着要当前置的 mod，也只能靠 `CS.ModsMgr.Instance:FindMod("ModLoaderLite",nil,true)` 自己去找、自己 `Assembly.LoadFrom`。

**结论：跨 mod 依赖 = 把 mod 的可用性押在玩家的排序上。对商业级交付不可接受。**

### 6.2 复制进自己 mod：法律与工程两面

| 对象 | 能复制吗 | 依据 |
|---|---|---|
| 内置 `ui://` 控件 ID | **能，但不是「复制」而是「引用」** | `ui://0xrxw6g7*` 属于游戏本体内置包，任何 mod 都能 `AddObjectFromUrl`；官方教程明说「GSQ 的图素和控件已经内置，不用导出和加载」【盘证】 |
| 社区控件封装函数（`AddInput/AddLable/AddButton`） | **能，但价值有限** | 都是 15 行左右的直白代码，无算法；且**每个 mod 自己复制一份**（MOD版修改器 27 个窗口里重复 27 次），本身就没有「库」的概念【盘证】 |
| 枫轩系的 UI 代码 | **不能** | 全是 `.luac` 编译产物，无源码、无文档【盘证】 |
| 清风无道的 `QFLib.dll` / `ModifierMain.luac` | **不能（法律+技术）** | 闭源 DLL；且其 UI 逻辑强依赖同 mod 的编译核心（`ModifierMain:AddLable3/AddButton2/AddInput2` 都在 `.luac` 里），抽不出来【盘证】 |
| 许可声明 | **无一份** | 43 个 mod 里没有任何 `LICENSE` / MIT / 作者授权文字；只有 `1819060504/Readme.txt`、`1969434487` 各目录的 `ReadMe.txt`（内容只是「该文件夹下放的需要的数据以及一些函数库之类的。」）【盘证】 |

**结论：社区没有「库」可借，只有「范式」可学。**真正值得抄的是三个范式：
1. `contentPane` + 包内控件（A 派）
2. `AddObjectFromUrl` + `OnObjectEvent` 名字分发（B 派）
3. `m_title` / `m_n12` / `selected` / `.tooltips` 这些**内置组件的内部成员名**（§5.2、§4.2 已给）

### 6.3 可用的内置控件 `ui://` 清单（实锤引用过的）

来自 MOD版修改器 / 体修淬助手的实际调用点，按使用次数排：

| ui:// | 用途推断 | 引用处 |
|---|---|---|
| `ui://0xrxw6g7m8j0ovnz` | 标签（39 次） | `QFWDModifierMainUI.lua` 等 |
| `ui://0xrxw6g7hdhl1a` | 复选框 Checkbox（29 次） | 同 |
| `ui://0xrxw6g7hdhl1c` | 输入框 TextInput（26 次） | `BPRefreshWindow.lua:292` |
| `ui://0xrxw6g7xrwaf` | 标签/容器（25 次） | QFWD |
| `ui://0xrxw6g7hdhl18` | 按钮 Button（3 次） | `simplewindowbase.lua:41`、`BPRefreshWindow.lua:339` |
| `ui://0xrxw6g7nd594l` | 标签 Label | `simplewindowbase.lua:47` |
| `ui://0xrxw6g7gtsug9` | 标签（`.m_title`） | `BPRefreshWindow.lua:305` |
| `ui://0xrxw6g7snk12s` | 带图标的行（隐藏 `m_icon` 当纯文本用） | `BPRefreshWindow.lua:320` |
| `ui://0xrxw6g7lsb652ow3n` | 大号标题按钮（18px 居中） | `QFWDModifierMainUI.lua:674` |
| `ui://0xrxw6g7fevgbb`、`zc5cnr`、`hdhl0`、`hdhl7`、`qah58x`、`snk12s`、`ua9y2ovth`、`iqu5ovob`、`iqu5ovoa` | 其它内置件（待命名） | QFWD |

> ⚠️ **风险**：这些 ID 是**游戏内置包**的资源短 ID，**跨版本可能变**。社区 mod 直接硬编码，等于把「游戏大版本更新」当成自己会炸的日子。若要采用，必须在 `pcall` 里包一层并在失败时降级到 `kit.lua` 自绘。

---

## 7. 联网补充（只记可引用事实）

| 事实 | 来源 |
|---|---|
| 官方模组体系说明：GSQ 为 mod 作者「开放了所有接口、提供了完整 API 文档、开发教程、开发工具、**界面的编辑范例**」，并有面向美术作者的视频教学（B站 `space.bilibili.com/449602628`） | [一点浩然气，千里快哉风 — 模组系统介绍（3楼猫）](https://game.3loumao.org/88758) |
| 工坊存在名为 **【大鬼】UI框架 / UIFramework** 的「前置框架」类 mod，描述为「提供更方便的 UI 制作接口。此MOD单独安装无功能，仅为其他MOD提供UI框架接口。」它出现在多个 ACS 合集里 | [快乐修仙，关爱你的肝（合集，含该 mod 描述）](https://steamcommunity.com/sharedfiles/filedetails?id=2835201849)、[Skymods 收录页](https://catalogue.smods.ru/archives/125671) |
| 该框架在玩家排序贴里被标为「选装」，且「似乎和 Fatury 有冲突；大鬼洞天和工具盒 bug 有点多」 | [自用模组推荐（Skymods 转载）](https://catalogue.smods.ru/archives/424834) |
| **Fatury（F框架）** 是美术/音频替换框架：「动态静态立绘替换、器灵立绘、奇遇图过场图贴图替换、**UI替换**、音频替换、视频双修」，与官方编辑器配合，**不是 UI 构建 API** | [Fatury（F框架）下载页](https://mod.3dmgame.com/mod/223236)、[修仙MOD全集（基于 Fatury）](https://steamcommunity.com/sharedfiles/filedetails/?id=2948061813) |
| FairyGUI 官方窗口约定：内容组件里放名为 `frame` 的组件，`closeButton` / `dragArea` / `contentArea` 是约定名；窗口 = 内容组件 + 窗口管理 API | [FairyGUI 窗口系统文档](https://www.fairygui.com/docs/editor/window/) |
| FairyGUI 包加载：`UIPackage.AddPackage("demo")`；发布产物 `demo_fui.bytes` 是定义文件、`demo_atlas0.png` 等是资源 | [FairyGUI 显示 UI 面板文档](https://www.fairygui.com/docs/unity/) |

**未取到正文的（诚实标注）**：
- 【大鬼】UI框架 的 **ACS 版本工坊页正文没抓到**（Steam 页面抓取被拦）。目前只能说「工坊合集里出现过同名同描述的框架」。该系列作者「八荒大鬼」在《鬼谷八荒》有同名框架（[ali213 页面](https://patch.ali213.net/showpatch/278873.html)，描述同为「为玩家提供更方便的UI制作接口」）。**是否为 ACS 原生版本、其 API 形态如何、是否开源，均未证实。**
- 没有任何社区教程详细讲 ACS 里 `OnObjectEvent` 的用法——这条是本次从官方基类源码读出来的。

---

## 8. 推荐路线

### 8.1 结论

**自研。以官方 FairyGUI 能力为地基，把 `kit.lua` 补成完整的控件层，事件统一走 `OnObjectEvent`；不引入任何第三方 mod UI 框架，也不做跨 mod 依赖。**

三条腿并行，按场景选：

| 场景 | 用哪条 | 理由 |
|---|---|---|
| 排版复杂、以文字/链接为主（创造窗、确认窗、帮助） | **`SetHtml` 富文本**（现状） | 零控件成本、换行自动、超链接天然可用 |
| 需要真控件、需要悬停/状态/滑条/网格（主面板、配置） | **`kit.lua` 自绘** | 完全可控、不依赖游戏内置 ID、能悬停 |
| 想省事又要原生观感（可选） | **内置 `ui://` + `OnObjectEvent`**（B 派） | 一次调用出控件，但 ID 有版本风险 → 包 `pcall` 降级 |

### 8.2 自研：三条理由

1. **社区没有可借之物，唯一「框架」闭源且本体是另一款游戏的移植。** 43 个 mod 零 UI 库、零许可声明；枫轩系全编译；清风无道的库绑死在自家 `.luac` 核心上。所谓「借用」在工程上等于「抄 15 行函数」，收益为零。
2. **ACS 的 mod 依赖机制根本不存在**（`Info.json` 无依赖字段，只有 4/42 填了 `Sort`）。任何跨 mod 依赖都会退化成「求玩家手动排序」，一个前置没装好就整窗白屏——对万法阁这种要上工坊的整合 mod 是不可接受的支持成本。
3. **我们已有的东西比社区任何一份都好。** `kit.lua` 能画矩形、能自定义配色、能悬停改色——A/B 两派都做不到；`SetHtml` 那条已经跑通并部署。自研是在**已有资产上加一层**，而借库是**推倒重来 + 引入外部风险**。

### 8.3 自研：三条风险

1. **`.onClick` 在自绘控件上是否可靠，尚未验证。** `kit.lua:129` 用 `pcall(function() b.onClick:Add(onClick) end)` 挂事件，`pcall` 会吞掉失败——如果 `FG.GComponent()` 造出来的对象不派发 `onClick`，表现就是「按钮画出来了但点不动」，和当年 `AddButton` 一模一样。**必须先做 §8.4 的验证再铺开用。**
2. **自绘等于自建控件库，工作量在我们身上。** 输入框、下拉框、滚动列表、多选、键盘输入，每个都要自己实现（富文本 `<input>` 能救一部分）。内置库那 30 个控件白送的东西，自研要重做。
3. **视觉与官方不一致的风险。** 自绘配色/字号/间距是手调的，容易和原版界面「两张皮」；社区 mod 之所以拼命用 `ui://` 内置件，很大原因就是「看起来像原版」。

### 8.4 借第三方库：三条理由与风险（作为对照，不推荐）

**若借（理由）**：① 省掉控件自研工作量；② 可能自带主题，观感贴近原版；③ 别人踩过的坑（输入法、缩放、多分辨率）可能已修。

**若借（风险）**：
1. **可用性不可控**：`Info.json` 无依赖声明，框架 mod 未装 / 排序错 / 玩家关掉 → 我方窗口直接崩，且崩在别人代码里，日志都指不到我们。
2. **供应链不透明**：【大鬼】UI框架 无源码可得、许可未知、玩家反馈有冲突与 bug；把核心交互押在一个闭源、作者随时可弃更的前置上，等于把 mod 的寿命交给别人。
3. **没有真收益**：它提供的多半就是「几个 `Add*` 包装函数」——我们已经有一份更好的；而它带来的**版本耦合与支持成本**是实打实的。

---

## 9. 给万法阁的落地清单（可执行）

1. **【必须先做】验证事件通路**（半天，一次实机）：
   在 `main_window.lua` 里实现
   ```lua
   function tbWindow:OnObjectEvent(t, obj, context)
       WFG.log("[ui] event", t, obj and obj.name)
       if t == "onClick" then ... dispatch by obj.name ... end
   end
   ```
   然后分别点 ①`SetHtml` 里的 `<a href>`（应走 `onClickLink`）、②`kit.lua` 造的按钮、③`AddObjectFromUrl` 造的内置按钮。
   三种各记一行日志 → **一次性确定哪条通路可用**。这一步做完，UI 技术路线就彻底封板。
2. **`kit.lua` 补 `OnClick` 兜底**：`K.Button` 里除了 `b.onClick:Add`，再加一条「`opts.name` 已有 → 注册到窗口的 `_kits` 表，由 `OnObjectEvent` 按 name 派发」，双保险。
3. **`kit.lua` 补三个控件**：`K.Input`（包 `ui://0xrxw6g7hdhl1c` 或富文本 `<input>`）、`K.Dropdown`（包 `ui://...z` 或自绘弹层）、`K.List`（滚动列表，最费工，先用分页顶）。
4. **内置 ID 一律走适配层**：新增 `Scripts/WFG/ui/native.lua`，集中放 `ui://` 常量 + `M.Try(url)`（`pcall` 包裹，失败返回 nil 并记日志），禁止业务代码直接写 `ui://`。
5. **不引入任何前置依赖**，`Info.json` 保持零依赖（现状已如此）。
6. 若后续真的要 GUI 精修：用官方 `ModUI` 工程（`docs/_uidiy/`）做包 → 发布 → `Info.json` 加 `"UIPackage":"UI/xxx"`。**这是唯一被官方文档背书的重度 UI 路线**，也是「和原版一模一样」的唯一办法。

---

## 10. 附录：证据清单

| 类型 | 路径 | 说明 |
|---|---|---|
| 扫描脚本 | `docs/_scan_workshop.py` | 遍历 43 个 mod，输出 `_scan_result.json` |
| 扫描结果 | `docs/_scan_result.json` | 每 mod：display/author/version/fui/window_lua/ui_lib_lua/legal |
| 键名统计 | `docs/_infokeys.txt` | 42 个 Info.json 的键并集（证明无依赖字段） |
| 官方 UI 包 | `docs/_uidiy/` | 解包 `自定义UI相关(UI DIY).rar` 的全部内容 |
| 官方教程 | `docs/_uidiy_tutorial.txt` | `UI制作教程.docx` 的纯文本（11 段） |
| 官方基类 | `E:\...\Scripts\Window\windowbase.lua`(62 行) / `simplewindowbase.lua`(75 行) | 事件总线与内置控件快捷方法 |
| 官方示范 | `E:\...\Mods\Example\Scripts\Window\{SampleWindow,TestWindow}.lua` | A 派正典 + 富文本 |
| 社区模板 | `workshop/1917318204/Scripts/Window/Cg20Window.lua` | 47 行最小 FUI 窗口 |
| 社区封装范本 | `workshop/2594369748/Scripts/BPRefreshWindow.lua` | AddInput/AddLable/AddButton/AddCheckBox + OnObjectEvent |
| 社区最大样本 | `workshop/1969434487/Scripts/Window/QFWDModifierMainUI.lua` | B 派 + 名字分发 |

### 未验证项（不要当结论用）

- 【推断】内置 `ui://` 短 ID 与 `GSQ` 源码里 30 个控件的**一一对应关系**——只按用法推了用途，没有做「包内资源表 → 短 ID」的解包对照（内置包在 `resources.assets` 里，未提取）。
- 【推断】`FG.GComponent()` 自绘控件上 `.onClick` 是否真的会被派发（见 §8.4 步骤 1）。
- 【网页未证实】存在【大鬼】UI框架的 **ACS 原生版本**及其 API/许可。
