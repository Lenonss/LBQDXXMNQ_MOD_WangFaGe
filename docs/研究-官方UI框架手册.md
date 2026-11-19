# 官方 UI 框架使用手册（FairyGUI · ACS v0.995）

> 面向 Lua mod 作者，回答一个问题：**在 ACS 里能做到多富的界面？**
> 结论先给：能。勾选框、滑条、网格、图标、悬停提示、富文本链接、双击，全都能做，但每一件的"能"都附带前提，且**不是**走 `SetHtml + AddButton` 这一条路。

---

## 证据约定

| 记号 | 含义 |
| --- | --- |
| `G\...` | 游戏安装目录 `E:\Program Files (x86)\Steam\steamapps\common\AmazingCultivationSimulator\` |
| `S\...` | 反编译源码 `C:\Users\28040\AppData\Local\Temp\acs_src`（Assembly-CSharp.dll） |
| `F\...` | FairyGUI 本体反编译 `C:\Users\28040\AppData\Local\Temp\fairy`（Assembly-CSharp-firstpass.dll） |
| `[反编译]` | 直接读 IL 还原的代码，可信度最高 |
| `[官方示例]` | `Mods\Example` 或官方 Lua 脚本里的现成用法 |
| `[本项目实测]` | 万法阁实机跑过 |
| `[待实测]` | 代码结构支持，但没在游戏里点过；用前自己验一次 |

FairyGUI 类型本体**不在** Assembly-CSharp.dll，而在 `G\Amazing Cultivation Simulator_Data\Managed\Assembly-CSharp-firstpass.dll`（186 个 `FairyGUI.*` 类型）。Assembly-CSharp.dll 里只有 `FairyGUI.TreeViewRes` 和 `FairyGUI.Utils.HtmlNpcInfo` 两个补丁类。

复现命令（rep 用）：

```bash
ILSPY="C:/Users/28040/.dotnet/tools/ilspycmd.exe"
M="E:/Program Files (x86)/Steam/steamapps/common/AmazingCultivationSimulator/Amazing Cultivation Simulator_Data/Managed"
"$ILSPY" -t FairyGUI.GButton "$M/Assembly-CSharp-firstpass.dll"      # FairyGUI 本体
"$ILSPY" -t XiaWorld.UI.InGame.UI_Checkbox "$M/Assembly-CSharp.dll"  # 官方组件生成类
```

---

## 0. 结论摘要：能做什么 / 不能做什么

| 能力 | 结论 | 依据 |
| --- | --- | --- |
| 富文本正文（颜色/图片/链接/按钮） | ✅ 有，`SimpleWindow:SetHtml` 整窗一张 `GRichTextField` | `S\Wnd_Simple.cs:40-52`；`S\XiaWorld.UI.InGame\UI_WindowEmpty.cs:19-24` |
| 普通按钮 | ✅ 三种来源都行：`.fui` 组件、内置包 URL、纯 Lua 自绘 | `S\Wnd_LuaWindowBase.cs:45-50`；`G\Scripts\Window\simplewindowbase.lua:40-45` |
| 勾选框 | ✅ 能，但**没有现成的"裸控件"**：要么用内置 `InGame/Checkbox`（URL `ui://0xrxw6g7hdhl1a`），要么自己拿 `GGraph+GButton` 画 | `F\GButton.cs:474-491`；`uiin\UI_Checkbox.cs` |
| 滑条 | ⚠️ **`new GSlider` 拖不动**。拖动逻辑绑在包里名为 `grip` 的子件上，裸 new 没有 grip 就只是"能赋值读值的数值容器" | `F\GSlider.cs:244-274` |
| 下拉框 | ✅ 用内置 `InGame/ComboBox`；裸 `new GComboBox` 无弹窗子件 | `uiin\UI_ComboBox.cs`；`F\GComboBox.cs` |
| 网格列表 | ✅ 能，但用**普通 `GComponent` + 手排坐标**；`GList` 的虚拟列表在纯 Lua 下不可用 | 见 §6.3 证据 |
| 列表项点击 / 双击 | ✅ `onClickItem`、`onRightClickItem`，双击自己记时间戳 | `F\GList.cs:986-996` |
| 悬停 tooltip（`obj.tooltips = "..."`） | ❌ **默认不可用**：`UIConfig.tooltipsWin` 全工程无赋值，只会打一条 warning | `F\GRoot.cs:484-506`；`F\UIConfig.cs:106` |
| 物品提示窗（真正能用的那个） | ✅ 用官方 `Wnd_TipPopPanel.Instance:AddBind(obj, thing, npc)` | `S\Wnd_TipPopPanel.cs:930` |
| 自己画 tooltip | ✅ `onRollOver` + 自建图元，完全可控（推荐） | `F\GObject.cs:187-189` |
| 物品图标 | ✅ `thing://2,Item_Xxx`、`Spr/...`、`tex://...`、`thingid://<id>`、`http(s)://` | `S\GMyLoader.cs:12-34` |
| 文本输入框 | ⚠️ `GTextInput` 构造是 public，但内嵌 Unity InputField，需实机验证 | `F\GTextInput.cs:146` `[待实测]` |
| 程序内新建 `.fui` 包 | ❌ 不行。`.fui.bytes` 必须用 FairyGUI Editor 导出，运行时只能"加载/创建" | `F\UIPackage.cs:256-293` |
| 虚拟列表 / 循环列表 | ❌ 纯 Lua 下不可用（要求 scrollPane + 默认 item 资源） | `F\GList.cs:1338-1367` |

一句话路线建议：

- **要好看、要复用官方皮肤** → 自己打包 `.fui.bytes`，`UIPackage.CreateObject` 取出组件再绑事件（§2）。
- **要快、要能热改、不想碰编辑器** → 纯 Lua 自绘（§3）。本 mod 的 `Scripts/WFG/ui/kit.lua` 走的是这条。
- **只要文字按钮** → `SimpleWindow` + `SetHtml` 富文本链接（最省事，但交互上限低）。

---

## 1. 三条建窗路径

### 1.1 路径 A：`Windows:CreateWindow`（纯 Lua 首选）

```lua
local Windows = GameMain:GetMod("Windows")
local tbWindow = Windows:CreateWindow("MyWindow")

function tbWindow:OnInit()
    -- 注意：此刻 contentPane 还是 nil，必须自己设，否则是空窗
    self.window.contentPane = UIPackage.CreateObject("MyPkg", "MainPanel")
    self.window.closeButton = self:GetChild("frame"):GetChild("n5")
end

function tbWindow:OnUpdate(dt) end
function tbWindow:OnShown() end
function tbWindow:OnShowUpdate() end
function tbWindow:OnHide() end

-- Show / Hide / SetSize / GetChild / AddObjectFromUrl 基类已经提供，直接调
-- tbWindow:Show()  tbWindow:Hide()  tbWindow:SetSize(800,600)
```

**C# 侧真实行为** `[反编译]`

- `G\Scripts\Window\windows.lua:40-48`：`Windows:CreateWindow(name)` → `CS.Wnd_LuaWindowBase.CreateWindow(name)`，结果塞进 `Windows.tbWindow`。
- `G\Scripts\Window\windows.lua:3-5`：`tbWindowClass` / `tbWindow` / `enter` 三个表。
- `G\Scripts\Window\windows.lua:21-29`：`NewClass` 用 `Lib:NewClass(self.WindowBase)` 造 Lua 表。
- `S\Wnd_LuaWindowBase.cs:17-22`：`public static LuaTable CreateWindow(string name)`，new 之后立刻 `Init()`。
- `S\Wnd_LuaWindowBase.cs:57-67`：`Init()` 里 `GameMain:GetMod('Windows'):NewClass('{name}')` 拿到 Lua 表，`LuaBase.Set("window", this)`。
- `S\Wnd_LuaWindowBase.cs:24-34`：`OnInit` **只调 Lua 的 `Init()`，不设 contentPane** —— 这是最容易踩的空窗坑。
- `S\Wnd_LuaWindowBase.cs:45-50`：`AddObj(GObject obj, int x, int y)` = `contentPane.AddChild(obj)` + `SetXY` + 挂 4 个事件。
- `S\Wnd_LuaWindowBase.cs:15`：Listeners = `onClick` / `onKeyDown` / `onClickLink` / `onRightClick`。
- `S\Wnd_LuaWindowBase.cs:52-55`：事件统一转发到 Lua 的 `OnEventListener`。
- `S\Wnd_LuaWindowBase.cs:79-107`：`OnShown` / `OnShowUpdate` 转发 Lua。
- `S\Wnd_LuaWindowBase.cs:109-123`：`OnUpdate(float dt)` 转发 Lua，dt 是 `Time.deltaTime`。
- `S\Wnd_LuaWindowBase.cs:140-155`：`Dispose` 里调 `LuaBase.Destory()`。
- `G\Scripts\Window\windows.lua:11-18`：`OnLeave` 时遍历 `Windows.tbWindow` 逐个 `v.window:Dispose()`。

窗口基类便捷方法（`G\Scripts\Window\windowbase.lua`）：

| Lua 方法 | 实现 | 行 |
| --- | --- | --- |
| `Show()` / `Hide()` | `window:Show()` / `window:Hide()` | `:9-15` |
| `SetSize(w,h)` | `window:SetSize` | `:22-24` |
| `AddObjectFromUrl(url,x,y)` | `UIPackage.CreateObjectFromURL(url)` + `window:AddObj` | `:27-31` |
| `GetChild(name)` | `window.contentPane:GetChild(name)` | `:33-38` |

**限制**：不自带标题栏、不自带关闭按钮、不是 modal、不自动居中。`OnInit` 里必须自己设 `contentPane`，否则窗口打开是空的。

### 1.2 路径 B：`SimpleWindow:CreateWindow`（内置窗框 + HTML 正文）

```lua
local SimpleWindow = GameMain:GetMod("SimpleWindow")
local tbWindow = SimpleWindow:CreateWindow("MyHtmlWindow")

function tbWindow:OnInit()
    self:SetTitle("我的窗口")
    self:SetSize(600, 420)
    self:SetHtml([[<font size='20' color='#8B5A2B'>标题</font>
<a href='cmd:do1'>点我做一件事</a>
<input type='button' value='按钮' name='Bnt1'/>
<img src='Spr/Building/building_test.png'/>]])
end

function tbWindow:OnObjectEvent(t, obj, context)
    if t == "onClickLink" then
        print("link:", context.data)          -- context.data 就是 href 里冒号后面那段
    elseif t == "onClick" and obj.name == "Bnt1" then
        print("按钮")
    end
end
```

**C# 侧** `[反编译]`

- `G\Scripts\simplewindow.lua:41-49`：`SimpleWindow:CreateWindow` → `CS.Wnd_Simple.CreateWindow`。
- `S\Wnd_Simple.cs:24-33`：`OnInit` 里 `UIInfo = UI_WindowEmpty.CreateInstance()`、`contentPane = UIInfo`、`opaque=false`、`UIInfo.m_html.onClickLink.Add(OnEventListener)`、`closeButton = UIInfo.m_frame.m_n5`、`modal = true`。
- `S\Wnd_Simple.cs:35-38`：`SetTitle` → `UIInfo.m_frame.title`。
- `S\Wnd_Simple.cs:40-52`：`SetHtml` 写 `UIInfo.m_html.text`，并给所有 HtmlButton 子对象挂事件。
- `S\Wnd_Simple.cs:63-68`：`AddObj` 同路径 A。
- `S\Wnd_Simple.cs:75-85`：`Init` 走 `GameMain:GetMod('SimpleWindow'):NewClass(...)`。
- `S\Wnd_Simple.cs:111-116`：`Dispose` **没有 try/catch**，LuaBase 为 nil 时直接 NRE。
- `G\Scripts\Window\simplewindowbase.lua:40-45`：`AddButton` 用硬编码 `ui://0xrxw6g7hdhl18`（= `InGame/Button`）；`:46-51` `AddLable` 用 `ui://0xrxw6g7nd594l`。

**限制与已知问题**：

- `modal = true`：窗口一开，底层 GRoot 的 modal 遮罩就上，世界点击被吞（这通常是好事，但叠窗要注意）。
- 正文只有一张 html，版式全靠 HTML/CSS **子集**（FairyGUI 的富文本，不是浏览器）。
- `[本项目实测]` `SimpleWindow:AddButton` 在万法阁的创造窗里**显示正常但点击不触发**（见 `handoff/` 账本 2026-11-17 19:22）。可靠的通路是 `onClickLink` + `context.data`；`onClick` 只在 `SetHtml` 的 `<input type='button'>` 上稳定。
- `Dispose` 空引用风险：窗口创建失败（如 Lua 侧 OnInit 报错）后仍被 `OnLeave` 批量 Dispose 会炸。

### 1.3 路径 C：直接 `new FairyGUI.Window`，或者更干脆 `GRoot.inst:AddChild`

```lua
local FG = CS.FairyGUI

local win = FG.Window()
win.contentPane = myGComponent      -- 关键：不设就是空窗
win.closeButton = myGComponent:GetChild("close")
win.modal = true
win:Show()
-- 或者不走 Window，直接把组件挂到根：
FG.GRoot.inst:AddChild(myGComponent)
```

**C# 侧** `[反编译]`

- `F\Window.cs:38-77`：`contentPane` setter 会 `AddChild`、`SetSize(contentPane.width,height)`、加 Size 关系、并**自动**尝试 `_frame = contentPane.GetChild("frame")`，若存在则自动取 `closeButton` / `dragArea` / `contentArea`。
- `F\Window.cs:81-99`：`closeButton` setter 自动 `onClick.Add(closeEventHandler)`。
- `F\Window.cs:170-173`：构造里 `displayObject.onTouchBegin.AddCapture(__touchBegin)`、`SetHome(GRoot.inst)`。
- `F\Window.cs:180-186`：`Show()` → `GRoot.inst.ShowWindow(this)` + `OnShowUpdate` + 触发 `g_emGlobleEventType.OpenWindow` / `WindowEvent(1)`。
- `F\Window.cs:219-231`：`Hide()` 走动画；`HideImmediately()` 走 `root.HideWindowImmediately`。
- `F\GRoot.cs:145-149`：`ShowWindow(win)` = `AddChild(win)` + `AdjustModalLayer()`。
- `F\GRoot.cs:161-172`：`HideWindowImmediately(win, dispose)` 才会真删/真 Dispose。
- `F\GRoot.cs:285-295`：modal 遮罩是一个 `GGraph`，`DrawRect` + `UIConfig.modalLayerColor`（默认黑 40%）。

**这条路的价值**：`GRoot.inst:AddChild(comp)` 让你**完全绕开 Window 语义**（不需要 closeButton、不需要 modal），适合做 HUD 式常驻层。代价是没有 `OnShowUpdate`、没有自动关窗、`GlobleEvent.OpenWindow` 也不会触发。

### 1.4 三条路对比

| | `Windows:CreateWindow` | `SimpleWindow:CreateWindow` | 裸 `Window` / `GRoot:AddChild` |
| --- | --- | --- | --- |
| 默认 contentPane | ❌ 无，自己设 | ✅ `UI_WindowEmpty` | ❌ 无 |
| 标题栏 / 关闭钮 | ❌ | ✅ 自带 | 取决于组件里有没有 `frame` |
| modal | ❌ | ✅ true | 自己设 |
| HTML 正文 | ❌（要自己造 GRichTextField） | ✅ | 自己造 |
| 与 mod 生命周期绑定 | ✅ `OnLeave` 自动 Dispose | ✅ | ❌ 自己管 |
| 适合 | 自绘面板、`.fui` 主窗 | 文本/表单类窗 | HUD、实验性 UI |

---

## 2. mod 自带 `.fui.bytes` 的完整流程

### 2.1 目录与命名

```
MyMod\
  Info.json                      # "UIPackage":"UI/Sample"
  UI\Sample_fui.bytes            # ← 文件名 = <UIPackage 值>_fui.bytes
  Scripts\Window\XxxWindow.lua
  Resources\Spr\...              # 仅当你要用 Spr/ 图标
```

- `G\Mods\Example\Info.json:5`：`"UIPackage":"UI/Sample"`；`:6` 官方注释「载入UI模块，多个包用逗号隔开，没有就删掉UIPackage」。
- `G\Mods\Example\UI\Sample_fui.bytes` 实际存在（1953 B）。
- `S\ModsMgr.cs:674`：`string text2 = path + "/" + text + "_fui.bytes";` —— 所以 `UIPackage` 的值是**带目录的相对路径**，且文件名前缀必须与之完全一致。
- `S\ModsMgr.cs:675-682`：文件不存在时只打一条 `KLog.Dbg("Mod: ... UI file is null ...")`，**不报错、不中断**。包没加载成功时你只会看到后面的 `CreateObject` 返回 nil。

> `Settings\UI\*.xml`（如 `G\Mods\Example\Settings\UI\MainList\test.xml`、`Settings\UI\Help\Help.xml`）是**数据驱动 UI**（建造菜单项、帮助条目），和 `.fui` 包毫无关系。别把 fui 放进 `Settings\UI\`。

### 2.2 加载链路（逐行）

`S\ModsMgr.cs:660-685` → `LoadUIPackage()`：

```
foreach mod in Mods:
    if !active or UIPackage empty: continue
    for text in UIPackage.Split(','):
        text2 = mod.Path + "/" + text + "_fui.bytes"
        if File.Exists(text2): LoadUIPackage(text, mod.Path)
```

`S\ModsMgr.cs:1262-1302` → `LoadUIPackage(string path, string modpath)`：

- `:1264`：`UIPackage.AddPackage(path, delegate(string name, string extension, Type type, out DestroyMethod destroyMethod){...})`
- `:1266`：`destroyMethod = DestroyMethod.Destroy`
- `:1269`：`name = "File://" + modpath + "/" + name + extension;`
- `:1270-1273`：`new WWW(name)` + 忙等 `while(!wWW.isDone){}`（**同步阻塞主线程**）
- `:1278-1280`：`TextAsset` → 返回 `wWW.bytes`（fui 描述文件）
- `:1282-1288`：`Texture` / `Texture2D` → `wWW.texture`（图集）
- `:1290-1292`：`AudioClip`
- `:1301`：`KLog.Dbg("Mod {0} load UIPackage {1}", modpath, path)`

`F\UIPackage.cs:256-293` → `AddPackage(assetPath, loadFunc)`：

- `:258-261`：按 `assetPath` 去重（重复调用返回同一个包）
- `:263`：`loadFunc(assetPath + "_fui", ".bytes", typeof(TextAsset), out destroyMethod)`
- `:265-272`：拿不到数据时 **playing 状态下直接 `throw new Exception("FairyGUI: Cannot load ui package in '...'")"`**
- `:288-290`：按 `id`、内部 `name`、`assetPath` 三个键注册

**结论**：`UIPackage.CreateObject("Sample", "SampleWindow")` 里的 `"Sample"` 是 **fui 文件内部记录的包名**（FairyGUI Editor 里导出的 Package Name），不是 `Info.json` 里那个 `UI/Sample` 全路径。FairyGUI 导出时包名默认取工程名，请显式核对。

图集资源路径也是按 `modpath + name + extension` 拼的（`ModsMgr.cs:1269`），所以 fui 里引用的图片必须在 mod 根目录下按相对路径存在。

### 2.3 在 Lua 里用

```lua
local Windows = GameMain:GetMod("Windows")
local tbWindow = Windows:CreateWindow("SampleWindow")

function tbWindow:OnInit()
    -- 1) 整窗替换成自己包里的组件
    self.window.contentPane = UIPackage.CreateObject("Sample", "SampleWindow")
    if self.window.contentPane == nil then
        print("[UI] 包没加载成功：检查 Info.json 的 UIPackage 与 fui 内包名")
        return
    end

    -- 2) 关窗：组件里若有 frame 子件，Window 会自动接 frame.closeButton；
    --    否则手动指定任意 GObject
    self.window.closeButton = self:GetChild("frame"):GetChild("n5")

    -- 3) 取子件绑事件
    local btn = self:GetChild("bnt_1")
    btn.title = "确定"
    btn.onClick:Add(function(ctx) print("clicked", ctx.sender.name) end)

    -- 4) 图标：两种 URL 都行
    btn.icon  = "Spr/Object/object_test.png"
    local ld  = self:GetChild("loader")
    ld.url    = "Spr/Building/building_test.png"

    -- 5) 列表
    local list = self:GetChild("list")
    for i = 1, 20 do
        local item = list:AddItemFromPool()
        item.icon = "thing://2,Item_SmallBell,Item_IronBlock"
        item.title = "物品" .. i
    end
    list.onClickItem:Add(function(ctx)
        local idx = ctx.sender:GetChildIndex(ctx.data)   -- ctx.data 是 item 本体
        print("选中", idx, ctx.data.name)
    end)
end
```

以上对应 `G\Mods\Example\Scripts\Window\SampleWindow.lua:2-31`（`:4` CreateObject、`:5` closeButton、`:6-13` 按钮、`:15-16` loader、`:18-19` label、`:21-28` list、`:30` progressbar）与 `:56-62` 的 `OnUpdate`（`self.progressbar.value = v`）。

### 2.4 事件绑定一览

| 事件 | 挂在 | 回调签名 | 证据 |
| --- | --- | --- | --- |
| `onClick` | 任意 `GObject` | `function(ctx) ctx.sender` | `F\GObject.cs:177` |
| `onRightClick` | 任意 `GObject` | 同上 | `F\GObject.cs:179` |
| `onTouchBegin/End` | 任意 `GObject` | 同上 | `F\GObject.cs:181,185` |
| `onRollOver/Out` | 任意 `GObject` | 同上 | `F\GObject.cs:187,189` |
| `onClickLink` | `GRichTextField` | `ctx.data` = href 冒号后内容 | `F\GObject.cs:197`；示例 `TestWindow.lua:32-44` |
| `onClickItem` | `GList` | `ctx.data` = 被点的 item | `F\GList.cs:986-996` |
| `onRightClickItem` | `GList` | 同上 | 同上 |
| `onChanged` | `GSlider` / `GComboBox` 等 | — | `F\GSlider.cs` |

`self:GetChild("xxx")` 走的是 `window.contentPane:GetChild(name)`（`windowbase.lua:33-38`），**只按 name 查，不递归**；fui 里没命名的子件叫 `n1`、`n5`、`n12` 这种。

---

### 2.5 官方教程原文（Editor → mod 的七步）

游戏自带的「自定义UI相关(UI DIY)」压缩包里有一份 `UI制作教程.docx`（11 段）与一个 **FairyGUI 工程 `mod.fairy`**，已解包在：

```
docs\_uidiy\自定义UI相关(UI DIY)\自定义UI相关\ModUI\
  UI制作教程.docx
  mod.fairy
  assets\GSQ(内置不用导出或加载)\   ← 30 个内置控件的源工程（Button/Checkbox/ComboBox/
                                       Input/List/Menu/ProgressBar/Slider/Window + images）
```

教程原文（`docs\_uidiy_tutorial.txt:3-14`，逐条照录）：

1. 工具/教程/SDK：http://fairygui.com/
2. 打开 `modui` 工程
3. 新建包
4. 在自己的包里创建 UI
5. 如果要用别的图素，就自己弄到自己的包里
6. **GSQ 的图素和控件已经内置，不用导出和加载**
7. 将主要控件设置为「导出」
8. 发布自己的包
9. 将导出的所有文件复制到 MOD 文件夹
10. 包加载方法：在 MOD 的 `Info.json` 里加 `"UIPackage":"包路径"`（例如 `UI/Sample`）
11. 使用方法见 `Example\Scripts\Window\SampleWindow.lua`

第 6 条是关键：**内置包（`InGame` / `GSQ`）里的控件与图素不需要你导出**，只要 URL 对（§4.1）就能直接 Create。第 7 条「设为导出」是必须的 —— 没导出的组件不在 `_fui.bytes` 里，`CreateObject` 会返回 nil。

`assets\GSQ(...)\` 下每个控件都有一份 XML 源（`extention="Button"` / `"Slider"` 这种），想抄外观或确认子件名就直接看，例：

- `...\Checkbox\Checkbox.xml:2-20`：`<component size="27,19" extention="Button">`、`<controller name="button" pages="0,up,1,down,2,over,3,selectedOver"/>`、文字子件 **`name="title"`**、勾选图 `name="n7"` 只在 page 1/3 显示、`<Button mode="Check"/>`。
- `...\Slider\SliderH.xml:2-17`：`extention="Slider"`、`controller name="Mode"`、子件 **`n1`(底) / `bar`(填充) / `grip`(Button_iconOnly)**、`<Slider/>`。

> 版本差异提醒：这份 GSQ 工程是 2019–2020 年的，字段命名（如 Checkbox 的第 2 个子件）与现在出货的 `InGame` 包不完全一致。**结构以反编译的 `uiin\UI_*.cs` 为准，外观参考 XML**。

---

## 3. 不依赖 `.fui` 包：纯 Lua 造控件

### 3.1 可行性矩阵

| 类 | 构造 public | 反编译行 | 裸 new 后能用吗 | 说明 |
| --- | --- | --- | --- | --- |
| `GComponent` | ✅ | `F\GComponent.cs:238` | ✅ 完整可用 | 容器；`AddChild` / `GetChild` / `RemoveChildren` 全在 |
| `GGraph` | ✅ | 默认构造 | ✅ 完整可用 | `DrawRect(w,h,lineSize,lineColor,fillColor)` 可画底板/分割线（`F\GGraph.cs:116`） |
| `GTextField` | ✅ | `F\GTextField.cs:229` | ✅ 可用 | 用 `UIConfig.defaultFont`，游戏启动时已设（`S\GameWatch.cs:885-894`） |
| `GLoader` | ✅ | `F\GLoader.cs:338` | ✅ 可用 | `url` 走 `GMyLoader` 的五种前缀（§5） |
| `GImage` | ✅ | — | ⚠️ 需 `texture`/`url` | 一般用 `GLoader` 代替更省心 |
| `GButton` | ✅ | `F\GButton.cs:297` | ⚠️ **可点，无视觉** | `title/icon` 只在 `ConstructExtension` 里绑子件（`:474-492`）；裸 new 时 `_titleObject/_iconObject` 为 null |
| `GSlider` | ✅ | `F\GSlider.cs:139` | ⚠️ **能赋值，拖不动** | 拖动绑在名为 `grip` 的子件上（`:244-274`），裸 new 没有 |
| `GList` | ✅ | `F\GList.cs:423` | ✅ 可当容器用 | 虚拟列表不可用（§6.3） |
| `GProgressBar` | ✅ | `F\GProgressBar.cs:116` | ⚠️ 需 `bar` 子件 | 自己画进度条反而更快 |
| `GComboBox` | ✅ | `F\GComboBox.cs:309` | ❌ 无弹窗子件 | 用内置 `InGame/ComboBox` |
| `GTextInput` | ✅ | `F\GTextInput.cs:146` | ⚠️ | 内嵌 Unity InputField，`[待实测]` |
| `Window` | ✅ | `F\Window.cs:38` | ✅（需 contentPane） | §1.3 |

**总判定：可行。** FairyGUI 的类型在 `S\ExampleGenConfig.cs:12-96` 的 `[LuaCallCSharp(GenFlag.No)]` 名单里被显式暴露给 Lua（EventContext / GObject / GComponent / GList / GButton / GSlider / GComboBox / GProgressBar / GLoader / GGraph / GRoot / UIPackage / Window / UIObjectFactory …），`GenFlag.No` 意味着不生成静态 wrapper、走反射 translator —— 也就是说 **Lua 里 `CS.FairyGUI.GComponent()` 直接就能 new**。

`S\ExampleGenConfig.cs:98-124` 的 `CSharpCallLua` 名单里还有 `EventCallback0` / `EventCallback1` / `ListItemRenderer` / `ListItemProvider`，所以 `btn.onClick:Add(function(ctx) ... end)` 和 `list.itemRenderer = f` 这类"把 Lua 函数塞进 C#"的用法是被官方允许的。

另有一条捷径：`UIObjectFactory.NewObject(ObjectType)` 是纯 switch、不碰包（`F\UIObjectFactory.cs:90-136`），可以从 Lua 造控件再自定性：

```lua
local obj = CS.FairyGUI.UIObjectFactory.NewObject(CS.FairyGUI.ObjectType.Button)
```

### 3.1.1 `flua.lua` 已经把类挂成 Lua 全局

这是最直接的证据：`G\Scripts\flua.lua`（全文 41 行）就是一张"Lua 全局名 → FairyGUI 类型"的映射表，加载后你可以直接 `GComponent()`、`GTextField()`、`GGraph()`：

| 行 | 全局名 | 行 | 全局名 |
| --- | --- | --- | --- |
| 1 | `EventContext` | 20 | `GComponent` |
| 2 | `EventListener` | 21 | `GList` |
| 3 | `EventDispatcher` | 22 | `GRoot` |
| 4 | `InputEvent` | 23 | `GLabel` |
| 6 | `Container` | 24 | `GButton` |
| 8 | `Stage` | 25 | `GComboBox` |
| 9 | `Controller` | 26 | `GProgressBar` |
| 10 | `GObject` | 27 | `GSlider` |
| 11 | `GGraph` | 28 | `PopupMenu` |
| 13 | `GImage` | 29 | `ScrollPane` |
| 14 | `GLoader` | 30 | `Transition` |
| 15 | `GMovieClip` | 31 | `UIPackage` |
| 16 | `TextFormat` | 32 | `Window` |
| 17 | `GTextField` | 33 | `GObjectPool` |
| 18 | `GRichTextField` | 36 | `UIPanel` |
| 19 | `GTextInput` | 38 | `TypingEffect` |

**没挂全局的**（需要 `CS.FairyGUI.` 前缀）：`UIConfig`、`UIObjectFactory`、`GTween` 之外的 tween 工具类、以及各 `UI_*` 生成类（用 URL 取，别直接 new）。

所以下面两行等价，全局写法更短：

```lua
local c1 = CS.FairyGUI.GComponent()
local c2 = GComponent()
```

### 3.2 自绘控件骨架（可直接抄）

```lua
local FG   = CS.FairyGUI
local Unity = CS.UnityEngine

local function color(hex, a)
    hex = tostring(hex or "#000000"):gsub("^#", "")
    return Unity.Color(tonumber(hex:sub(1,2),16)/255,
                       tonumber(hex:sub(3,4),16)/255,
                       tonumber(hex:sub(5,6),16)/255, a or 1)
end

-- 底板：DrawRect 内部已经 SetSize（F\GGraph.cs:118），不用再设一遍
local function rect(w, h, fill, line)
    local g = FG.GGraph()
    g:DrawRect(w, h, 1, color(line or "#8A6A3A"), color(fill or "#F3E6C8"))
    return g
end

-- 文本：字号要走 TextFormat 对象（getter 代理到 Unity 侧 textFormat，别指望改字段能生效）
local function label(text, size, hex, x, y)
    local t = FG.GTextField()
    local tf = FG.TextFormat()
    tf.size = size or 14
    tf.color = color(hex or "#2B1B0E")
    t.textFormat = tf
    t.text = text
    t:SetXY(x or 0, y or 0)
    return t
end

-- 按钮：底板 + 文字 + 点击
local function button(text, w, h)
    local root = FG.GComponent()
    root:SetSize(w, h, true)
    local bg = rect(w, h, "#EBDCB8", "#8A6A3A"); bg.name = "bg"
    local lb = label(text, 14, "#2B1B0E", 0, 0); lb.name = "lb"
    root:AddChild(bg); root:AddChild(lb)
    root.onClick:Add(function(ctx) print("click", text) end)
    return root
end

-- 勾选框（纯自绘：方框 + 内部实心块）
local checked
local function checkbox(x, y, onToggle)
    local box = FG.GComponent()
    box:SetSize(120, 24, true)
    local frame = rect(16, 16, "#FFFFFF", "#8A6A3A"); frame:SetXY(x, y)
    local dot   = rect(10, 10, "#8A6A3A", "#8A6A3A"); dot:SetXY(x + 3, y + 3)
    local lb    = label("勾选项", 14, "#2B1B0E", x + 22, y - 2)
    box:AddChild(frame); box:AddChild(dot); box:AddChild(lb)
    dot.visible = false
    box.touchable = true
    box.onClick:Add(function()
        checked = not checked
        dot.visible = checked
        if onToggle then onToggle(checked) end
    end)
    return box
end

-- 滑条（纯自绘 + onTouchBegin 手搓拖动，不要用裸 GSlider）
local function slider(w, h, minv, maxv, value, onChange)
    local root = FG.GComponent()
    root:SetSize(w, h, true)
    local track = rect(w, 6, "#D9C8A6", "#8A6A3A"); track:SetXY(0, (h - 6) / 2)
    local fill  = rect(w * value, 6, "#8A6A3A", "#8A6A3A"); fill:SetXY(0, (h - 6) / 2)
    root:AddChild(track); root:AddChild(fill)
    root.touchable = true
    root.onTouchBegin:Add(function(ctx)
        local lp = root:GlobalToLocal(ctx.inputEvent.position)   -- position 是舞台坐标
        local r = math.max(0, math.min(1, lp.x / w))
        fill:SetSize(w * r, 6)
        if onChange then onChange(minv + (maxv - minv) * r) end
        ctx:StopPropagation()     -- 别让父级/GRoot 继续派发（官方 GSlider.cs:321 同款）
    end)
    return root
end
```

> 这套就是本 mod 的 `Scripts/WFG/ui/kit.lua` 的雏形（那边还多做了 `Icon` / `Tip` / 分页网格）。开门见山一句：**自绘时"控件"不是控件，是"组件 + 你自己维护的状态"**——勾选态要自己存，滑条位置要自己写，没有 `selected` / `value` 帮你兜。

### 3.3 裸 `GButton` 为什么点了没反应/没字

`F\GButton.cs:474-492`（`ConstructExtension`，只在"从包里构建"时被调）：

```csharp
_buttonController = GetController("button");
if (_buttonController != null) ...
_titleObject = GetChild("title");
_iconObject  = GetChild("icon");
```

所以裸 `new GButton()`：
- `onClick` 仍然正常（事件挂在 displayObject 上，`F\GButton.cs:297` 之后 base 处理）；
- `title` 只是存进字段，**不渲染**（`_titleObject == null`）；
- `icon` 同理（`GObject.icon` 是空实现，`F\GObject.cs:821-830`）。

要么自己 `AddChild` 一个 `GTextField` 当标题并手动同步，要么直接用内置 `InGame/Button`。

同理 `GObject.text` 也是虚方法空实现（`F\GObject.cs:799-808`），别对 `GComponent` 直接 `.text = "x"`。

---

## 4. 官方现成控件清单（内置 `InGame` 包）

内置包 id 是 `0xrxw6g7`，包名 `InGame`，随游戏资源加载：`S\TestMainMenu.cs:19-20` 里 `UIPackage.AddPackage("UIData/InGame")` / `("UIData/GSQ")`。游戏目录里**没有**散落的 `.bytes`（这些包在 Unity 资源里），所以 mod 不需要自带任何东西就能用下面的 URL。

### 4.1 控件 URL 表

| 控件 | URL | 组件名 / 基类 | 子件（生成类字段） | 证据 |
| --- | --- | --- | --- | --- |
| 按钮 | `ui://0xrxw6g7hdhl18` | `Button` / `GButton` | — | `uiin\UI_Button.cs`；`simplewindowbase.lua:41` |
| 纯图标按钮 | `ui://0xrxw6g7q3f724` | `Button_iconOnly` | — | `uiin\UI_Button_iconOnly.cs` |
| 放置按钮 | `ui://0xrxw6g7nd594g` | `BntPlace` | — | `S\Wnd_World.cs:109` |
| 标签 | `ui://0xrxw6g7nd594l` | Label | — | `simplewindowbase.lua:47` |
| **勾选框** | `ui://0xrxw6g7hdhl1a` | `Checkbox` / `GButton` | `m_button`(Controller)、`m_n1`、`m_n6`(GLoader)、`m_n3`、`m_title` | `uiin\UI_Checkbox.cs:6-33` |
| **滑条(横)** | `ui://0xrxw6g7hdhl1e` | `SliderH` / `GSlider` | `m_Mode`(Controller)、`m_n1`、`m_bar`、`m_grip` | `uiin\UI_SliderH.cs:6-31` |
| 滑条(竖) | `ui://0xrxw6g7hdhl1g` | `SliderV` / `GSlider` | 同上 | `uiin\UI_SliderV.cs` |
| 区间滑条 | `ui://0xrxw6g7l0f4hy` | `SliderHRange` | — | `uiin\UI_SliderHRange.cs` |
| **下拉框** | `ui://0xrxw6g7hdhl1i` | `ComboBox` / `GComboBox` | — | `uiin\UI_ComboBox.cs`；弹窗 `ui://0xrxw6g7hdhl7` |
| 滚动条(横/竖) | `ui://0xrxw6g7hdhl1m` / `...1n` | `ScrollBarH` / `ScrollBarV` | — | `uiin\UI_ScrollBarH.cs` |
| 窗口框 | `ui://0xrxw6g7hdhl1j` | `WindowFrame` | `title`、`n5`(关)、`contentArea`、`dragArea` | `uiin\UI_WindowFrame.cs` |
| 空窗（SimpleWindow 用） | `ui://0xrxw6g7doa6ki` | `WindowEmpty` | `m_frame`、`m_html` | `S\XiaWorld.UI.InGame\UI_WindowEmpty.cs:12-24` |
| 物品格 | `ui://0xrxw6g7ps9u2ovw5` | `Item` | — | `uiin\UI_Item.cs` |
| 物品选择格 | `ui://0xrxw6g7pjluljryqe` | `ItemSelectCommon` | — | `uiin\UI_ItemSelectCommon.cs` |
| 选中按钮 | `ui://0xrxw6g7lqzs52ow23` | `SelectBnt` | — | `uiin\UI_SelectBnt.cs` |
| 提示窗体 | `ui://0xrxw6g7oip24a` | `Tip_PopPanel` | — | `uiin\UI_Tip_PopPanel.cs` |
| 文本项 | `ui://0xrxw6g7gebq2l` | `ItemTextOnly` | — | `uiin\UI_ItemTextOnly.cs` |

完整清单：Assembly-CSharp.dll 里有 **692 个** `XiaWorld.UI.InGame.UI_*` 生成类，每个都带 `public const string URL` 与 `CreateInstance()`。要什么就去反编译那个类：

```bash
grep "UI_" /tmp/acstypes.txt | head -80
"$ILSPY" -t XiaWorld.UI.InGame.UI_Checkbox "$M/Assembly-CSharp.dll"
```

### 4.2 从 Lua 取内置控件

```lua
-- 方式一：URL（推荐，最稳）
local cb = UIPackage.CreateObjectFromURL("ui://0xrxw6g7hdhl1a")   -- InGame/Checkbox
if cb == nil then return end
cb = cb.asButton

-- Checkbox 在 GSQ 源工程里是 <Button mode="Check"/>：点一下就自动翻 selected，
-- 外观由 controller "button" 的 0/1/2/3 页切换，你不用手管
cb.title    = "启用"          -- 走 GetChild("title")，该组件文字子件就叫 title
cb.selected = false
cb.onClick:Add(function(ctx)
    print("checked:", ctx.sender.selected)   -- 点完读 selected 即可
end)
```

> 若 `cb.title` 没反应（某些版本文字子件被改名），退一步直接改子件：
> ```lua
> cb:GetChildAt(3).text = "启用"   -- uiin\UI_Checkbox.cs 里 m_title = GetChildAt(3) GTextField
> ```

```lua
-- 方式二：包名 + 组件名（语义比 URL 常量清楚）
local cbox = UIPackage.CreateObject("InGame", "ComboBox").asComboBox
cbox.items = CS.System.String[3]{"甲", "乙", "丙"}   -- 数组要显式构造（F\GComboBox.cs:131）
cbox.values = CS.System.String[3]{"a", "b", "c"}     -- :192，配合 value 用
cbox.selectedIndex = 0                                -- :227
cbox.onChanged:Add(function(ctx) print("选:", cbox.selectedIndex) end)

-- 滑条
local sl = UIPackage.CreateObjectFromURL("ui://0xrxw6g7hdhl1e").asSlider
sl.min, sl.max, sl.value = 0, 100, 30
sl.wholeNumbers = true
sl.onChanged:Add(function(ctx) print("值:", sl.value) end)
```

对照：`F\GButton.cs:205-248`（`selected` 会 `SetCurrentState()` 并走 `_buttonController`）、`F\GSlider.cs:75-123`（`min`/`max`/`value`/`wholeNumbers`）、`F\GComboBox.cs:45`（`icon` override）与 `items`/`selectedIndex`。

**注意** `UIPackage.CreateObjectFromURL` 找不到时**静默返回 null**（`F\UIPackage.cs:362-366`，`?.` 短路，无日志），你对着 nil 调 `.asButton` 会得到 `attempt to index a nil value`。拿包里的组件一律先判空。

### 4.3 Tooltip：三条路，一条是死的

**(a) `obj.tooltips = "文本"` —— 在 ACS 里不可用** `[反编译]`

- `F\GObject.cs:650-673`：setter 里非空就给 `onRollOver/onRollOut` 挂内部回调。
- `F\GObject.cs:1160-1179`：`__rollOver` → `root.ShowTooltips(...)`。
- `F\GRoot.cs:484-506`：`ShowTooltips` 需要 `UIConfig.tooltipsWin` 非空，否则 `Debug.LogWarning("FairyGUI: UIConfig.tooltipsWin not defined")` 直接 return。
- `F\UIConfig.cs:106`：`public static string tooltipsWin;` 默认 null；**整个 acs_src 里没有任何一处给它赋值**（`grep -rn "tooltipsWin"` 只命中 FairyGUI 本体）。

所以 `SampleWindow.lua:26` 那句 `item.tooltips = "物品" .. i` 在现代版本里大概率只是往日志里写 warning。想用必须先在 Lua 里补一行：

```lua
CS.FairyGUI.UIConfig.tooltipsWin = "ui://0xrxw6g7oip24a"   -- 指到任意能当提示框的组件
```

但那样提示框里显示的是 `ShowTooltipsWin` 里的默认逻辑（设 `tooltipWin.text`），能不能显示成你想要的样子取决于目标组件结构 —— 不推荐。

**(b) 官方物品提示窗（要显示物品信息时唯一正解）**

```lua
local tip = CS.XiaWorld.Wnd_TipPopPanel.Instance
tip:AddBind(bnt, thing, npc)          -- 鼠标悬停 bnt 时显示 thing 的提示
-- 解绑
tip:RemoveBind(bnt)
```

- `S\Wnd_TipPopPanel.cs:34`：`public static Wnd_TipPopPanel Instance => UILogicMgr.GetWindow<Wnd_TipPopPanel>()`
- `S\Wnd_TipPopPanel.cs:930`：`public void AddBind(GObject ct, Thing t, Npc owner = null, bool cantuse = false)`
- `S\Wnd_TipPopPanel.cs:942`：`public void RemoveBind(GObject ct)`
- `S\Wnd_TipPopPanel.cs:36-43`：内部 `UIInfo = UI_Tip_PopPanel.CreateInstance()`、`visible=false`、`opaque=false`、`touchable=false`
- 用法实例：`S\SearchMainPanel.cs:452` `AddBind(bnt.m_n172.m_icon, thing)`；`S\Panel_Equpt.cs:174-182` `RemoveBind` / `AddBind`。

**(c) 自己画 tooltip（要自定义内容/富文本时）**

```lua
local tip = myLabel -- 预先造好、visible=false、放在高层
obj.onRollOver:Add(function(ctx)
    tip.text = "自定义提示"
    local p = CS.FairyGUI.GRoot.inst:GlobalToLocal(CS.UnityEngine.Vector2(
        CS.FairyGUI.Stage.inst.touchPosition.x,
        CS.FairyGUI.Stage.inst.touchPosition.y))
    tip:SetXY(p.x + 12, p.y + 18)
    tip.visible = true
end)
obj.onRollOut:Add(function() tip.visible = false end)
```

`GRoot.inst` 是 public static（`F\GRoot.cs:32`），`F\GRoot.cs:507-540` 官方就是这么定位提示窗的（`touchPosition + (10, 20)`，延迟 0.1s）。

---

## 5. 物品图标怎么加载

ACS 把 FairyGUI 的 `GLoader` 换成了自写的 `GMyLoader`（`S\GMyLoader.cs:6`），按 URL 前缀分流（`:12-34`）：

| 前缀 | 处理 | 示例 | 用途 |
| --- | --- | --- | --- |
| `thing://` | `LoadThing` | `thing://2,Item_SmallBell,Item_IronBlock` | **按 ThingDef 取图**，推荐 |
| `thingid://` | `LoadThingID` | `thingid://12345` | 按运行时 Thing 实例 id 取图（含法宝/材质色） |
| `tex://` | `LoadSinglePath`（去掉 6 字符后 `Resources.Load<Sprite>`） | `tex://Sprs/ui/icon_x` | 直接 Resources 路径 |
| `http(s)://` `file://` | `LoadWWW` | — | 网络/本地图 |
| 其它（无前缀） | `LoadPath` → `NewGetSprite.Instance.GetSprite(path)` | `Spr/Object/object_test.png` | 走 Spr 图集/Resources |

### 5.1 `thing://` 的三段式

`thing://<int ThingType>,<ThingDefName>[,<StuffDefName>]`（`S\GMyLoader.cs:134-276`）：

- 第 1 段是 `g_emThingType` 的整数值：`2` = Item、`4` = Building/地面等（`S\Wnd_GameMain.cs:1587` 用 `thing://4,FillShallowWater`）。
- 第 2 段是 Def 名。
- 第 3 段是**材料** Def 名，影响贴图和染色；不给就传 `nil` 或空串。
- 内部：`ThingMgr.Instance.GetDef(type, name)` → 取不到就 `onExternalLoadFailed()`（**静默**，图标空着）→ `def.GetTexPath(0)` → 建筑还要找 `_alp` 遮罩、地板/屋顶用 `"Item_Wood"` 代替材料（`S\ProduceMainPanel.cs:145`）。

```lua
btn.icon = "thing://2,Item_SmallBell,Item_IronBlock"   -- 物品 + 指定材质
btn.icon = "thing://2,Item_SmallBell"                  -- 只有两段也行
btn.icon = string.format("thing://%d,%s,%s", def.Type, def.Name, "Item_Wood"
```

### 5.2 `Spr/...` 是什么

`S\GMyLoader.cs:71-105` 的 `LoadPath` 走 `NewGetSprite.Instance.GetSprite(path)` —— 这是游戏的 Sprite 缓存（`Resources\Spr\...` 与打包图集），**不是** FairyGUI 包内资源。

- 写 `"Spr/Object/object_test.png"` 有 `.png` 后缀（`SampleWindow.lua:13`、`:16`）；
- 也见过不带后缀的写法（`S\Panel_BuildingProduceList.cs:76` 用 `"res/Sprs/ui/icon_anything"`、`:71` 用 `def.GetTexPath(0)`）—— 取决于图源怎么注册的。**跟字符串来源抄，别自己拼。**

两者区别一句话：`Spr/...` 是"一张图"，`thing://` 是"一个物品的图（含材料染色 + 朝向 + 遮罩）"。

### 5.3 注意

- 加载是**同步**的（`GMyLoader.LoadPath` 直接 `GetSprite`），所以别在逐帧 `OnUpdate` 里反复改 `icon`。
- 失败静默：图标不出现时先确认 Def 名拼写与 `g_emThingType` 数值。
- `GLoader` 还有 `align`、`fill` 等属性（`F\GLoader.cs:70`），九宫格拉伸靠 `fill`。

---

## 6. 列表（`GList`）与背包式格子

### 6.1 基本用法

```lua
local list = self:GetChild("list")     -- .fui 里的 GList
-- 或者纯 Lua：local list = CS.FairyGUI.GList(); comp:AddChild(list)

for i = 1, 20 do
    local item = list:AddItemFromPool()          -- 需要一个"默认 item 资源"
    item.icon  = "thing://2,Item_SmallBell"
    item.title = "物品" .. i
end

list.onClickItem:Add(function(ctx)
    -- ctx.sender = list, ctx.data = 被点的 GObject
    print("clicked", ctx.data.name, ctx.sender:GetChildIndex(ctx.data))
end)
list.onRightClickItem:Add(function(ctx) print("right", ctx.data.name) end)
```

- `F\GList.cs:468-478`：`AddItemFromPool()` → `GetFromPool(null)` → 用 `defaultItem` → `AddChild`。
- `F\GList.cs:449-461`：`GetFromPool(url)` 走 `_pool.GetObject(url)`，**url 为空且 defaultItem 为空时返回 null** → `AddChild(null)` 抛异常。
- `F\GList.cs:480-492`：`AddChildAt` 会给每个 item 挂 `onClick`/`onRightClick` 内部委托（所以 `onClickItem` 才有东西可派发）。
- `F\GList.cs:986-996`：`DispatchItemEvent` 里 `DispatchEvent("onClickItem", item)`，`context.data` 就是 item 本体。
- `F\GList.cs:27,29,31`：`selectionMode`、`itemRenderer`、`itemProvider`。

**纯 Lua 造 `GList` 时没有 `defaultItem`，`AddItemFromPool()` 直接返回 nil。** 原因链条（`[反编译]`）：

- `F\GList.cs:449-478`：`AddItemFromPool()` → `GetFromPool(null)` → `url = defaultItem`（默认 null）→ `_pool.GetObject(url)` → `AddChild(结果)`。
- `F\GObjectPool.cs:38-55`：`GetObject(url)` 先 `UIPackage.NormalizeURL(url)`，**url 为空直接 `return null`**；否则池里有就复用，没有就 `UIPackage.CreateObjectFromURL(url)`（`:49`）现造一个。

所以两种解法：

```lua
-- A) 给 defaultItem 一个真实的组件 URL，池子就能自己造/复用 item
list.defaultItem = "ui://0xrxw6g7ps9u2ovw5"   -- = InGame/Item（§4.1）
local item = list:AddItemFromPool()           -- 不再是 nil
item.icon  = "thing://2,Item_SmallBell"
item.title = "铃铛"

-- B) 干脆不用 pool，自己 AddChild（纯 Lua 组件场景）
list:AddChild(myOwnItemComponent())           -- GList 会自动挂 onClick/onRightClick
```

> `defaultItem` 是 `public string`（`F\GList.cs:21`），存的是 **URL**，不是组件对象。写成组件实例不会报错但也不生效。

### 6.2 背包式「网格 + 悬停 + 双击」完整示例

```lua
-- 依赖 §3.2 的 rect() / label()；FG = CS.FairyGUI，tip 是预先造好的 GTextField
-- 12 格 4x3 网格，每格 64x64
local CELL, GAP = 64, 8
local grid = FG.GComponent()
grid:SetSize(4 * CELL + 3 * GAP, 3 * CELL + 2 * GAP, true)

local lastClickTime, lastIndex = 0, -1

for i = 1, 12 do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local cell = FG.GComponent()
    cell:SetSize(CELL, CELL, true)
    cell:SetXY(col * (CELL + GAP), row * (CELL + GAP))
    cell.name = "cell_" .. i

    local bg = rect(CELL, CELL, "#F3E6C8", "#8A6A3A"); bg.name = "bg"
    local icon = FG.GLoader()
    icon:SetSize(CELL - 8, CELL - 8)
    icon:SetXY(4, 4)
    icon.url = "thing://2,Item_SmallBell"      -- 换素材时直接改
    icon.touchable = false                     -- 让点击落到 cell 上
    cell:AddChild(bg); cell:AddChild(icon)

    cell.onClick:Add(function()
        local now = CS.UnityEngine.Time.unscaledTime
        if lastIndex == i and now - lastClickTime < 0.4 then
            print("双击第", i, "格")
            lastClickTime, lastIndex = 0, -1
        else
            lastClickTime, lastIndex = now, i
            print("单击第", i, "格")
        end
    end)

    -- 悬停提示：用自己画的 tip，不走 tooltips
    cell.onRollOver:Add(function()
        tip.text = "第 " .. i .. " 格"
        tip.visible = true
        local p = CS.FairyGUI.GRoot.inst:GlobalToLocal(
            CS.UnityEngine.Vector2(CS.FairyGUI.Stage.inst.touchPosition.x,
                                   CS.FairyGUI.Stage.inst.touchPosition.y))
        tip:SetXY(p.x + 12, p.y + 18)
    end)
    cell.onRollOut:Add(function() tip.visible = false end)

    grid:AddChild(cell)
end
```

要点：

- **格子自己算坐标**，别指望 `GList` 的 `layout` 在没有 `Setup_*` 的情况下生效（`layout`/`lineGap`/`columnGap` 都是属性，能设；但 `GList` 的布局重算挂在 `Setup_AfterAdd` 与 `AddChildAt` 之后，纯 Lua 场景以手排最稳）。
- 悬停提示用 `onRollOver/onRollOut`；**不要**用 `touchable = true` 的覆盖层压住格子。
- 双击靠时间戳；`Time.unscaledTime` 不受游戏暂停影响（暂停时 `Time.timeScale = 0`）。
- 图标子件设 `touchable = false`，否则点击落在 icon 上、`cell.onClick` 收不到。

### 6.3 虚拟列表为什么不能用（`[反编译]`+`[待实测]`）

```csharp
// F\GList.cs:1338-1347
private void SetVirtual(bool loop) {
    if (base.scrollPane == null)
        Debug.LogError("FairyGUI: Virtual list must be scrollable!");   // 只报错，不 return
    ...
// F\GList.cs:1360-1367
if (_itemSize.x == 0f || _itemSize.y == 0f) {
    GObject fromPool = GetFromPool(null);
    if (fromPool == null) {
        Debug.LogError("FairyGUI: Virtual List must have a default list item resource.");
        _itemSize = new Vector2(100f, 100f);
```

- `scrollPane` 只在 `Setup_BeforeAdd` 里创建（包内组件才有），纯 Lua 的 `GList` 没有 → 报错后仍继续 `_virtual = true`，后续 `RefreshVirtualList` 走 `scrollPane` 直接空引用。
- 没有 `defaultItem` 时 `_itemSize` 落到 100×100 兜底。

结论：**别在 mod 里用 `SetVirtual()` / `numItems` 虚拟列表**。数据量大时自己做分页（本 mod 的创造窗口就是 4×4 分页），或用 `GList` 的普通模式 `AddChild` 手动增删。

---

## 7. 常见坑

### 7.1 `CreateObject` 静默返回 nil

`F\UIPackage.cs:352-366`：

```csharp
public static GObject CreateObject(string pkgName, string resName)
    => GetByName(pkgName)?.CreateObject(resName);      // 包没了 → null，无日志
public static GObject CreateObjectFromURL(string url)
    => GetItemByURL(url)?.owner.CreateObject(itemByURL, null);   // 资源没了 → null，无日志
```

只有 **async** 版本会 `Debug.LogError("FairyGUI: package not found - " + pkgName)`（`:383`）和 `("FairyGUI: resource not found - " + url)`（`:396`）。

防御写法：

```lua
local comp = UIPackage.CreateObject("MyPkg", "MainPanel")
if comp == nil then
    print("[UI] CreateObject 返回 nil：Info.json 的 UIPackage 路径错 / fui 内包名不是 MyPkg / 加载抛异常")
    return
end
self.window.contentPane = comp
```

### 7.2 包名冲突

`F\UIPackage.cs:505-508`：

```csharp
if (_packageInstById.TryGetValue(id, out var value) && name != value.name)
    Debug.LogWarning("FairyGUI: Package conflicts, '" + name + "' and '" + value.name + "'");
```

同一个包 id 被两个不同名字注册时会互踩（后加载的按 name 注册，但 id 仍指旧的）。mod 间共用同一个 FairyGUI 工程导出的包、或从别人包里复制 fui 时最容易踩。规避：**每个 mod 用自己独立的包名与包 id**（FairyGUI Editor 里改 Package ID）。

### 7.3 窗口 Dispose 与 LuaBase 空引用

- `G\Scripts\Window\windows.lua:11-18`：`OnLeave` 遍历所有窗口 `Dispose()`。
- `S\Wnd_LuaWindowBase.cs:140-155`：`Dispose` 里调 `LuaBase.Destory()`。
- `S\Wnd_Simple.cs:111-116`：**没有 try/catch**，LuaBase 为 nil 时 NRE。

所以：窗口创建后在 `OnInit` 里**不要**抛异常（Lua 侧报错会让 LuaBase 半初始化），否则退出游戏/切存档时批量 Dispose 会炸一片。给 `OnInit` 整体套 `pcall`：

```lua
function tbWindow:OnInit()
    local ok, err = pcall(function() ... end)
    if not ok then print("[UI] OnInit 失败:", err) end
end
```

### 7.4 暂停、输入、modal

- 暂停世界：`CS.XiaWorld.MainManager.Instance:Pause()`（`S-main\mm.cs:855`，即 `MainManager.cs:855`）；恢复 `Play(speed, sys)`（`MainManager.cs:892`）。
  本 mod 的解析确认窗就是这么冻结时间的。
- `SimpleWindow` 自带 `modal = true`（`S\Wnd_Simple.cs:33`），会 `AdjustModalLayer` 上遮罩，底层点击被吞。
- 自己的窗口想挡点击：`win.modal = true`，或手动 `FG.GRoot.inst:AddChild(FG.GGraph():DrawRect(...))` 当遮罩。
- `GRoot.LockBringTop`（`F\GRoot.cs:20`）为 true 时 `BringToFront` 直接 return（`:176-179`）——如果窗口"点不上去/被压住"，先怀疑这个。
- `GRoot.IgnoreModal`（`:22`）能让窗口无视 modal 区，官方内部用来做 HUD。

### 7.5 GRoot 层级与排序

- 窗口顺序 = `GRoot` 子节点顺序；`ShowWindow` 只是 `AddChild`（`F\GRoot.cs:147`），所以后 Show 的在上面。
- `BringToFront(win)` 会停在"modal 遮罩之下"（`F\GRoot.cs:174-198`），除非 `win.modal` 或 `IgnoreModal`。
- 单个对象层面还有 `sortingOrder`（`F\GObject.cs:612`），同层内可调。
- `GRoot` 尺寸 = 屏幕 / `UIContentScaler.scaleFactor`（`F\GRoot.cs:139-143`），所以 `SetXY` 用的是"设计分辨率坐标"，不是像素。

### 7.6 其他小坑

| 现象 | 原因 | 证据 |
| --- | --- | --- |
| 窗口打开是白的/空的 | `OnInit` 没设 `contentPane`（`Wnd_LuaWindowBase` 不代设） | `S\Wnd_LuaWindowBase.cs:24-34` |
| `SetHtml` 里的按钮点了没反应 | 本项目实测 `AddButton` 不触发；用 `onClickLink` | 账本 2026-11-17 |
| 勾选符号显示成方块 | 字体缺字（`☑`/`☐` 不一定有；`■`/`□` 有） | 本项目实测 |
| 给 `GComponent` 设 `.text/.icon` 无效 | 两者在 `GObject` 是空虚方法 | `F\GObject.cs:799-830` |
| `btn.title = "x"` 设了不显示 | `GButton` 只认**名字叫 `title` 的子件**（`GetChild("title")`）；自己拼组件时文字对象改名就失效 | `F\GButton.cs:474-492` |
| `btn.icon` 设了不显示 | 同理只认 `GetChild("icon")`；Checkbox/SliderH 这类没有 icon 子件的组件设 icon 无效 | 同上 |
| 裸 `GSlider` 拖不动 | grip 子件缺失 | `F\GSlider.cs:244-274` |
| `tooltips` 只出 warning | `UIConfig.tooltipsWin` 未赋值 | `F\GRoot.cs:484-506` |
| `AddItemFromPool` 返回 nil / 抛异常 | 无 `defaultItem` 资源 | `F\GList.cs:449-478` |
| `OnUpdate` 里每帧改 `icon` 卡顿 | 图像同步加载 | `S\GMyLoader.cs:71-105` |
| 窗口关不掉 | `closeButton` 没设，或 `noclose = true` | `F\Window.cs:81-99`、`F\Window.cs:34` |
| 新建窗口尺寸不对 | `contentPane` setter 会用 contentPane 的尺寸覆盖 Window 尺寸 | `F\Window.cs:60` |

---

## 8. 给本 mod 的结论

1. **不要**再走 `SimpleWindow + AddButton` 做交互 —— 按钮不通，且没有勾选/滑条（本项目实测）。
2. 想要富交互，两条可行主线：
   - **纯 Lua 自绘**（`Scripts/WFG/ui/kit.lua`）：上手快、热改快、不需要 FairyGUI Editor；代价是控件全自己维护状态，文字/图标要靠 `GTextField` + `GLoader` 自己拼。
   - **`.fui.bytes` + `UIPackage.CreateObject`**：能直接拿官方皮肤和现成控件（`InGame` 包里 Checkbox/SliderH/ComboBox 都在），代价是要用 FairyGUI Editor 导出、包名/图集路径要严格对齐。
3. **混合**是最省力的：外壳用纯 Lua 造（`Windows:CreateWindow` + 自绘底板），里面的"重控件"从内置包 Create：
   ```lua
   local cb = UIPackage.CreateObjectFromURL("ui://0xrxw6g7hdhl1a").asButton
   local sl = UIPackage.CreateObjectFromURL("ui://0xrxw6g7hdhl1e").asSlider
   self:AddObjectFromUrl("ui://0xrxw6g7hdhl1a", 20, 20)   -- 走 Windows 基类，事件自动接 OnEventListener
   ```
   这条路不依赖 mod 自带包（`InGame` 是游戏内置），又拿到了真正的勾选/滑条视觉与交互。
4. **物品图标**统一用 `thing://`，最省事也最不容易错。
5. **物品提示**用 `Wnd_TipPopPanel.Instance:AddBind`（官方原生），自定义提示用 `onRollOver` 自绘。

---

## 附：本文所有证据文件速查

| 主题 | 文件 | 关键行 |
| --- | --- | --- |
| 窗口注册表 | `G\Scripts\Window\windows.lua` | 3-5, 11-18, 21-29, 40-48 |
| Lua 窗口基类 | `G\Scripts\Window\windowbase.lua` | 22-24, 27-31, 33-38 |
| SimpleWindow 基类 | `G\Scripts\Window\simplewindowbase.lua` | 26-28, 36-38, 40-45, 46-51 |
| 简单窗口创建 | `G\Scripts\simplewindow.lua` | 12-19, 41-49 |
| `Wnd_LuaWindowBase` | `S\Wnd_LuaWindowBase.cs` | 15, 17-22, 24-34, 45-50, 52-55, 57-67, 79-107, 109-123, 140-155 |
| `Wnd_Simple` | `S\Wnd_Simple.cs` | 24-33, 35-38, 40-52, 63-68, 75-85, 111-116 |
| fui 加载 | `S\ModsMgr.cs` | 660-685, 674, 1262-1302, 1269 |
| 包创建/冲突 | `F\UIPackage.cs` | 256-293, 288-290, 352-366, 383, 396, 505-508 |
| Window | `F\Window.cs` | 34, 38-77, 81-99, 170-186, 219-231, 255 |
| GRoot | `F\GRoot.cs` | 20-22, 32, 145-149, 161-198, 285-295, 484-540 |
| 控件构造 | `F\GButton.cs` / `F\GSlider.cs` / `F\GList.cs` / `F\GComponent.cs` | 297/139/423/238；GButton 474-492；GSlider 244-274；GList 449-478, 986-996 |
| GObject 事件/属性 | `F\GObject.cs` | 177-201, 612, 650-673, 799-830, 1160-1179 |
| UIConfig | `F\UIConfig.cs` | 71, 76-78, 106 |
| Lua 类型暴露 | `S\ExampleGenConfig.cs` | 12-96, 98-124 |
| 控件 URL | `uiin\UI_*.cs`、`S\XiaWorld.UI.InGame\UI_WindowEmpty.cs` | 各文件 `const string URL` |
| Tooltip | `S\Wnd_TipPopPanel.cs` | 34, 36-43, 930, 942 |
| 图标 URL | `S\GMyLoader.cs` | 12-34, 71-105, 107-131, 134-276 |
| 官方示例窗 | `G\Mods\Example\Scripts\Window\SampleWindow.lua` | 2-31, 56-62 |
| 官方示例窗（HTML） | `G\Mods\Example\Scripts\Window\TestWindow.lua` | 2-13, 32-44 |
