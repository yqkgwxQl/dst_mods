# API 行为记录与特效方案

> 只记录**实测过**的结论；官方没有运行时 API 文档，社区注解只有签名，没测过的一律按未知处理。
>
> 本文分两部分：**方案选择**（矩阵/决策树/探针）与**行为记录**（已验证/待验证）。

## 一、方案矩阵

| 方案 | 选择性 | 跟随旋转 | 动态强度 | 跨客户端 | 复杂度 | 典型用途 |
|---|---|---|---|---|---|---|
| `SetSymbolAddColour(sym, r,g,b,a)` | ❌ 整个符号，暗部也会被加色 | ✅ 天然跟随 | ✅ netvar 驱动 | 需客户端执行 | 低 | 整体染色/微光 |
| `SetSymbolLightOverride(sym, v)` | ❌ 整个符号自发光 | ✅ 天然跟随 | ✅ | 需客户端执行 | 低 | 整体提亮 |
| `SetSymbolBloom` + `SetBloomEffectHandle` | 🟡 只亮部，但 handle 是**实体级** | ✅ | 🟡 基本只能开关 | 需客户端执行 | 中 | 亮部泛光；可能让脸/衣服一起亮 |
| 分件符号（crack / glow 层） | ✅ 局部 | ✅ 天然跟随 | ✅ 切帧/ShowSymbol | 需 build 支持 | 中 | 裂纹、分层光 |
| 独立 FX + `Follower:FollowSymbol` | ✅ 局部形状 | ❌ **只跟位置，不跟旋转** | ✅ netvar 调 alpha | 需父节点/网络 | 高 | 径向、点状、粒子 |
| 烘焙进武器贴图 | ✅ 局部 | ✅ 天然跟随 | 🟡 只能整体调 | 无 | 低 | 静态光晕、刃口高光 |
| 自定义 shader / Bloom handle 变体 | 未知 | 未知 | 未知 | 未知 | 高 | 未验证 |

## 二、决策树

```text
需要“只有局部发光”吗？
├─ 否 → 整体微光
│    ├─ 只要夜间可见 → SetSymbolLightOverride
│    └─ 要带颜色/随理智变化 → SetSymbolAddColour + netvar
└─ 是 → 需要跟随剑的旋转吗？
     ├─ 是 → 不能用 FollowSymbol
     │    ├─ 能接受静态光晕 → 烘焙进武器贴图（最稳）
     │    └─ 需要分件/可变 → build 里加 glow/crack 符号
     └─ 否（径向/点状）→ 独立 FX + FollowSymbol + netvar alpha
```

## 三、10 分钟探针流程（做美术前必做）

1. 按决策树选 1 个候选方案
2. 用**最小测试资源**，不要用正式美术：
   - 符号方案：纯色方块 PNG
   - FX 方案：箭头/细长条 PNG（能看出旋转）
3. 进游戏，依次做：
   - 站立
   - 斜持/挥剑
   - 走动、转身
   - 卸下/重新装备
   - 第二客户端观察（如果支持多人）
4. 记录四项：
   - 是否跟随位置
   - 是否跟随旋转
   - 是否影响其他部位
   - 是否跨客户端可见
5. 把结论写回本文「已验证」，再开始正式资源

## 四、已验证 API 行为

| API | 结论 | 证据 | 日期 | 置信度 |
|---|---|---|---|---|
| `Follower:FollowSymbol` | 只同步位置，不同步旋转 | 刀形光晕在斜持/挥剑时保持竖直，与剑分离 | 2026-11-15 | 高 |
| `AnimState:SetSymbolAddColour` | 对整个符号统一加色，暗部也会被提亮 | 剑身整体发绿，无明暗区分 | 2026-11-15 | 高 |
| `AnimState:SetSymbolBloom` | 单独设置没有明显效果，需要 `SetBloomEffectHandle` | 只调 bloom 时无变化；加 handle 后才有泛光 | 2026-11-15 | 中 |
| `AnimState:SetBloomEffectHandle` | 作用范围是**实体级**，不是符号级 | 开 handle 后角色脸/衣服高光也可能泛光 | 2026-11-15 | 中 |
| 服务器调用渲染 API | 不会同步到客户端，需 netvar + 客户端执行 | 服务器 `SetSymbolAddColour` 后客户端无变化 | 2026-11-15 | 高 |
| prefab 文件环境 | 没有 `GLOBAL`，且开启严格模式 | `GLOBAL.net_float` 报 “variable 'GLOBAL' is not declared” | 2026-11-15 | 高 |
| `entity:AddFollower` 顺序 | 必须在 `AddNetwork` 之前 | 顺序反了客户端不跟随 | 2026-11-15 | 中 |
| `Follower:FollowSymbol` 偏移 | 偏移不随符号旋转 | 剑斜持时偏移方向仍按世界坐标 | 2026-11-15 | 中 |
| `cli.py` 编译 scml | 忽略 `<object x/y/scale>` | 改 scml 后 frame 不变 | 2026-11-15 | 高 |
| build 位置 | 由 frame + pivot 共同决定 | 只改 frame 不同步 pivot/顶点会偏 | 2026-11-15 | 高 |

置信度：

- **高**：多场景复现，或控制台直接读到结果
- **中**：单场景复现，可能是特例
- **低**：只观察到一次，未排除其他因素

## 五、待验证

| API / 问题 | 为什么要测 | 建议探针 |
|---|---|---|
| `FollowSymbol` 的 `followframe`、`followlayered` 参数 | 可能影响旋转/层级 | 控制台改参数，斜持截图 |
| `Follower:FollowSymbol` 偏移的坐标系 | 决定偏移量怎么给 | 斜持时改 offset，看移动方向 |
| `SetSymbolAddColour` 的 alpha 参数 | 是否按 alpha 混合 | 传 0 / 1 对比 |
| `SetSymbolLightOverride` 的亮度上限 | 是否过曝 | 0.2 / 0.5 / 1.0 对比 |
| `SetSymbolBloom` 多符号叠加 | 能否只让一个符号泛光 | 给两个符号分别设 bloom |
| 客户端 `SetMultColour` 与 netvar 时序 | 初次进场是否丢事件 | 新客户端加入观察 |
| `SetParent` 与 `Follower` 的先后 | 是否影响位置 | 两种顺序对比 |

## 六、假设清单模板

实现前先填：

```text
任务：<一句话>

假设 1：<API/行为>   置信度：低/中/高
  探针：<最小测试>
  结果：未测 / 通过 / 失败

假设 2：...
```

规则：

- 只列“会影响实现方向”的假设
- 探针必须能在 10 分钟内完成，且不依赖正式美术/完整功能
- 未验证的假设，不得写进生产代码或资源制作计划

## 七、反模式

- ❌ 因为“原版也这么用”就推断某 API 支持某种行为
- ❌ 先做贴图/对齐/打包，再进游戏验证
- ❌ 用手动改 `build.xml` 的 frame 去补锚点，不同步 pivot/顶点
- ❌ 在服务器调用渲染 API，指望客户端自动同步

## 八、签名查询

社区注解可作为**签名参考**（不含行为）：

- `b1inkie/lsp-dst`：LuaCATS 注解，覆盖 `AnimState`、`Follower` 等
- 注意：`Follower:StopFollowing`、`SetOffset` 等参数在注解里标的是 `UNKNOWN`

## 九、相关文档

- `docs/MOD测试手册.md`：L4 视觉验证、通道 7 假设驱动
- `tools/工具说明文档.md`：build 锚点与 DST Mod Tool 对齐
- `tools/官方格式说明.md`：BILD/ANIM 字段
