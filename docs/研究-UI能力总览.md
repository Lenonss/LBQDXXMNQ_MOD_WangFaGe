# ACS UI 能力总览（本机实测 + 反编译）

> 版本：v0.995。证据文件：`Assembly-CSharp-firstpass.dll`（`FairyGUI.*`）、`Assembly-CSharp.dll`（`Wnd_*` / `UI_*`）、`Scripts/flua.lua`、`Scripts/Window/*.lua`、`Mods/Example`。

## 1. 结论先说

| 需求 | 能不能做 | 走哪条路 |
|---|---|---|
| 纯文字面板（说明、日志） | 能 | `SimpleWindow:SetHtml` |
| 少量固定按钮 + 文字 | 能，但**不可靠** | `SimpleWindow:AddButton`（本 mod 实测点击不触发，仅显示） |
| 富文本可点击条目 | 能 | `SetHtml` 里的 `<a href>` → `onClickLink` + `context.data`（官方 `TestWindow.lua:41` 验证） |
| 勾选框 / 滑条 / 网格 / 悬停提示 / 图标 | **能** | 自建 FairyGUI 原语（见 §2），本 mod 已封装 `Scripts/WFG/ui/kit.lua` |
| 完全自定义外观（美术级） | 能 | 自带 `.fui` 包（需 FairyGUI 编辑器导出），`Info.json` 的 `UIPackage` |

**结论**：不需要第三方 UI 框架。游戏把完整 FairyGUI 暴露给了 Lua（`Scripts/flua.lua` 逐类型挂全局），控件都能 `new` 出来，缺的只是「怎么用」的说明书——本文件与 `研究-官方UI框架手册.md` 就是这份说明书。

> 界面设计规则（token、两行筛选、下拉浮层、工具提示、门禁）见 [UI 设计规范](UI设计规范.md)；本文只回答“能不能做、怎么做”。

## 2. 为什么可以直接 new 控件

反编译 `Assembly-CSharp-firstpass.dll`，以下类型全部有 **public 无参构造函数**：

```
FairyGUI.GComponent()      FairyGUI.GButton()      FairyGUI.GSlider()
FairyGUI.GList()           FairyGUI.GLoader()      FairyGUI.GTextField()
FairyGUI.GGraph()          FairyGUI.GProgressBar() FairyGUI.GTextInput()
```

`GObject` 暴露的事件与属性（`FairyGUI/GObject.cs`）：

```
onClick  onRightClick  onTouchBegin  onTouchEnd  onRollOver  onRollOut
onClickLink  onRollOverLink  onRollOutLink
tooltips（字符串，自动走 GRoot 的 tooltip 机制）
touchable  opaque  visible  alpha  x / y / width / height / scale / grayed
```

`GComponent` 的容器 API（`FairyGUI/GComponent.cs`）：

```
AddChild(GObject)   GetChild(string)   GetChildAt(int)   RemoveChildren()   SetSize(w,h,ignorePivot)
```

`GGraph` 可以画纯色方块（`FairyGUI/GGraph.cs:116`）：

```lua
g:DrawRect(w, h, lineSize, lineColor, fillColor)   -- lineColor/fillColor 为 UnityEngine.Color
```

`GTextField` 的 XLua 暴露属性（`ObjectTranslator.cs:9176-9204`）：`text / fontsize / color / autoSize / singleLine / align / verticalAlign / textHeight / textWidth / textFormat / stroke`。没有 camelCase 的 `fontSize`，也没有 `wordWrap`；需要换行时按字符手工插入 `<br/>`。

## 3. 本项目的封装：`Scripts/WFG/ui/kit.lua`

| 函数 | 作用 |
|---|---|
| `kit.Panel(w,h,fill,line)` | 带底板的 `GComponent` 容器 |
| `kit.Rect(w,h,fill,line,lineSize)` | 纯色块（`GGraph`） |
| `kit.Label(text,size,hex,x,y,w)` | 单行文字 |
| `kit.LabelCenter(text,size,hex,x,y,w,h)` | 水平+垂直居中文字 |
| `kit.Button(text,x,y,w,h,onClick,opts)` | 自绘按钮：底板 + 文字 + 悬停换色 + `onClick` |
| `kit.Check(text,x,y,checked,onChange)` | 勾选项，返回组件与取值函数 |
| `kit.Slider(x,y,w,min,max,value,onChange)` | 自绘滑条（轨道 + 手柄 + 点击定位） |
| `kit.Icon(url,x,y,w,h)` | `GLoader` 贴图（`Spr/...`、`ui://...`、`thing://...`） |
| `kit.Tip(obj,text)` | 悬停提示（`obj.tooltips = text`） |

颜色统一用 `kit.Color("#RRGGBB", alpha)`。

挂到窗口：

```lua
local root = kit.Panel(820, 700)
root:AddChild(kit.Label("衍天 · 创造", 18, "#6B4A16", 8, 10))
local b = kit.Button("关闭", 700, 640, 96, 32, function(ctx) ... end)
window.window:AddObj(root, 22, 22)   -- 左上留边距，避开 SimpleWindow 的边框
```

## 4. 三条窗口路线的取舍

| 路线 | 优点 | 缺点 | 适用 |
|---|---|---|---|
| `SimpleWindow` + 自建 FairyGUI 子层 | 无需资源包、无需美术、立刻可用 | 外层仍是游戏默认木框；内层坐标需自己排 | **当前选择** |
| `Windows:CreateWindow` + 自带 `.fui` 包 | 外观完全自定义 | 需 FairyGUI 编辑器 + 打包 `.fui.bytes` + `Info.json` 声明 `UIPackage` | 后期美术化 |
| 直接用游戏现成窗口（`Wnd_*`） | 风格统一 | 参数与生命周期绑定游戏逻辑，改装易被更新打断 | 不建议 |

## 5. 已知坑

1. `Wnd_Simple:SetHtml` 必须在 `Show()` 之后调用，否则 `UIInfo` 未创建 → `NullReferenceException`。
2. `SimpleWindow` 的正文是 `UI_WindowEmpty.m_html`（`GRichTextField`，`contentPane:GetChildAt(1)`），默认铺满内容区，任何叠在上面的控件都会压字；要用 `WFG.ui:FitHtml` 挪开或直接 `SetHtml("")`。
3. `ThingMgr:GetDef` 在 XLua 下必须传 `CS.XiaWorld.g_emThingType` 枚举，传 int 报 `invalid arguments`。
4. 枚举型属性（`autoSize`/`align`）优先传 `CS.FairyGUI.AutoSizeType.Both` 之类；传数字多数情况可转，但用 `pcall` 兜底更稳。
5. 窗口打开期间要 `MainManager.Instance:Pause()`，关闭时 `Play(gamespeed)` 恢复；本项目用引用计数封装在 `WFG.ui:Pause()/Resume()`。
6. `window:Center()` 来自 FairyGUI 基类 `Window`，`Wnd_Simple` 自身不导出。
7. 事件回调一律 `obj.onClick:Add(function(ctx) ... end)`，`ctx.sender` 是控件；`ctx.data` 仅在富文本链接里是 href。

## 6. 点击为什么「看得到、点不动」——事件总线的真相

`Wnd_LuaWindowBase.cs`（`C:\Users\28040\AppData\Local\Temp\acs_src\Wnd_LuaWindowBase.cs`）里：

```csharp
private static string[] Listeners = { "onClick", "onKeyDown", "onClickLink", "onRightClick" };

public void AddObj(GObject obj, float x, float y)
{
    base.contentPane.AddChild(obj);
    obj.SetXY(x, y);
    AddEventListener(obj);          // 只挂到「这一个」对象上
}

private void OnEventListener(EventContext context)
{
    LuaBase.CallFunctionNoRs("OnEventListener", context);   // → Lua 的 OnObjectEvent
}
```

结论：
1. **只有经过 `window:AddObj(obj, x, y)` 的对象**才被挂监听；`SimpleWindow:AddButton` 内部走的就是 `AddObjectFromUrl` → `AddObj`，所以它本该能点——但 `wincu` 之外的游戏内实测里，它在本 mod 的窗口上不触发，原因是**我们没在 `OnObjectEvent` 里按 `obj.name` 分发**（`simplewindowbase.lua` 的 `OnObjectEvent` 默认空函数），点了等于没接。
2. `AddObj` **不递归**：用 kit 自建的子控件不会被自动挂监听。所以 `kit.Attach(obj, "onClick", fn)` 必须对每个可点控件单独调用（`kit.lua` 已内置，且失败会写 `[kit] 事件挂载失败`）。
3. 自绘控件要能点，还必须满足两条：容器 `opaque = true` + `touchable = true`，底板 `GGraph.touchable = false`（否则命中的是底板，事件不冒泡到容器）。

## 7. 官方内置控件包（来自 `Mods/自定义UI相关(UI DIY).rar`）

解包后是官方 FairyGUI 工程 `ModUI/mod.fairy`、11 段教程与 30 个内置控件源文件。教程原文：「GSQ 的图素和控件已经内置，不用导出和加载」。覆盖范围：Button、Checkbox、ComboBox、TextInput/TextArea/NumericInput、List/IconList/CheckIconList、PopupMenu、ProgressBar、SliderH、WindowFrame/CloseButton。

⇒ 输入框、下拉、勾选、滑条、进度条、右键菜单都有官方件可用，走 `ui://<内置短ID>` + `AddObjectFromUrl`。风险是短 ID 跨版本会变，加载失败要能降级（本项目 `kit.lua` 即降级路径）。
