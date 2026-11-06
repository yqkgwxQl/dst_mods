# 饥荒联机版 MOD 测试手册

> 这份文档是给**执行测试的那个 AI（也就是我）**看的工作规范，不是教程。
> 目的：任何一次"我做了个 mod，帮我验一下"的请求，都能按这里的层级、通道、清单和判定协议走，而不是每次临时发挥。

- **被测环境**：DST 762113（Windows x64），Steam 库 `<Steam 库>`
- **测试集群**：`Cluster_1`（`cluster_name = test`），已有基线备份 `Cluster_1.backup-20261106`
- **游戏数据目录**：`C:\Users\<用户名>\Documents\Klei\DoNotStarveTogether`
- **文档维护**：每当发现新的可验证通道或新的典型故障，回来补一节，并在末尾"变更记录"记一行

---

## 零、事实基础（已核实，不要再凭印象）

以下每一条都是我在这台机器上实测确认过的，写测试脚本时必须以此为准。

| 事实 | 证据 |
|---|---|
| 游戏脚本可读 | `data\databundles\scripts.zip` 是标准 zip（54 MB），4109 个条目，可解压查询任何 `TheSim:`/`AnimState:` 方法 |
| 专用服务器不渲染 | 可执行文件是 `dontstarve_dedicated_server_nullrenderer_x64.exe`，`nullrenderer` |
| 游戏内有截图 API | `scripts/util/screenshotter.lua`：`TheScreenshotter:RequestScreenshot(cb)` → `TheSim:RequestScreenshot()`；`main.lua:384` 每次都创建 `TheScreenshotter` |
| 截图回调拿到的是内存纹理 | `OnScreenshotReady(texture, texture_string)`，官方用于反馈上传，**未验证可落盘** |
| 控制台有 120 个 `c_*` 命令 | `scripts/consolecommands.lua` |
| 模组注入点齐全 | `modutil.lua`：`AddPrefabPostInit` / `AddPrefabPostInitAny` / `AddComponentPostInit` / `AddClassPostConstruct` / `AddPlayerPostInit` / `AddGamePostInit` / `AddSimPostInit` / `AddStategraphPostInit` / `AddBrainPostInit` / `AddReplicableComponent` / `AddModCharacter` / `AddModRPCHandler` / `SendModRPCToServer` / `GetModRPC` |
| 日志按启动轮转 25 份 | `Master\backup\server_log\server_log_<时间戳>.txt` |
| anim 包格式 | zip 内 `build.bin` + `atlas-0.tex` +（物品自身还需 `anim.bin`，swap 包**不能**有） |
| build.bin 标志位位置 | 不固定！在 `atlas-0.tex` 字符串起点 **+23** 处，uint32 值应为 `8`（写死偏移 65 会误判） |

> **铁律**：涉及游戏 API 名称、参数、行为时，先去 `scripts.zip` 查，不许靠记忆。

### 0.1 源码位置

| 用途 | 路径 |
|---|---|
| 游戏安装根目录 | `<游戏安装目录>`（Steam 库里 `steamapps\common\Don't Starve Together`） |
| **Lua 源码包（权威依据）** | `<游戏安装目录>\data\databundles\scripts.zip` |
| 版本标识 | 安装根目录下 `version.txt`（当前 `762113`） |

> 本机的绝对路径不写在这里——见同目录的 `本机环境.local.md`（被 `*.local.md` 排除，不会上传）。

- `scripts.zip` 是**标准 zip**（首 4 字节 `50 4B 03 04`，即 `PK\x03\x04`），约 54 MB、4100 个条目，脚本在包内 `scripts/` 下。
- **反面例子**：不是所有叫 `.zip` 的都是标准 zip，有的打开会报 `End of Central Directory record could not be found`。处理任何资源包前先验首 4 字节，别假定。
- 重建工作副本用仓库里的脚本，不要手工解压：

```powershell
.\tools\prepare_refs.ps1
```

- 游戏更新后（`version.txt` 变化）必须重新解压，否则查到的是旧版本 API。
---

## 一、测试金字塔

按成本从低到高。**每次测试从 L0 开始，能停在低层就不要上高层。**

| 层 | 名称 | 是否需要启动游戏 | 耗时 | 覆盖什么 |
|---|---|---|---|---|
| **L0** | 静态检查 | 否 | < 1 s | 文件结构、命名一致性、资源引用、语法、modinfo 完整性 |
| **L1** | 加载检查 | 只起服务器 | 30–60 s | mod 能否加载、Lua 报错、prefab 注册、组件挂载 |
| **L2** | 运行时断言 | 起服务器 + 自动脚本 | 60–90 s | 实体生成、组件参数、事件、坐标、状态机 |
| **L3** | 交互流程 | 起服务器 + 强制调用 | 90 s+ | 装备、使用、传送、战斗、死亡复活 |
| **L4** | 视觉验证 | 起服务器 + 客户端 | 2 min+ | 握点、朝向、特效外观 |

真实判据：**L0 能抓到约七成"改完就坏"的问题**，L1 再抓两成，剩下不到一成才需要 L4。所以永远先跑 L0。

---

## 二、五条观测通道

### 通道 1：静态解析（L0）

不启动游戏，直接读文件。已验证可读的东西：

- **mod 源码**：`modinfo.lua`、`modmain.lua`、`scripts/prefabs/*.lua`
- **anim 包**：解 zip 取 `build.bin` / `anim.bin` / `atlas-0.tex`
  - 用 ASCII 串提取 build 名、符号名、动画名（长度 ≥ 3 的连续可打印串）
  - 标志位按 `IndexOf('atlas-0.tex') + 23` 定位，读 uint32
- **图集 xml**：`<Element name="xxx.tex">` 的元素名列表
- **游戏源码**：查任意 API 是否存在、参数顺序

### 通道 2：日志（L1/L2）

| 文件 | 内容 |
|---|---|
| `master_server_log.txt` / `caves_server_log.txt` | 两个分片"本次"日志 |
| `Master\server_log.txt` | 分片自己的日志副本 |
| `client_log.txt` | 客户端日志（Lua 报错、加载、连接） |
| `Master\backup\server_log\` | 历史启动日志（对比基线用） |

**关键观测点**（顺序固定）：

```
Loading mod: <name>            → mod 开始加载
  Loading modmain.lua          → 执行 modmain
  Registering prefabs          → 注册 prefab
LOAD BE … LOAD BE: done        → 全量资源预载
Begin Session / Loading world  → 世界加载
Sim unpaused                   → 可操作
```

Lua 报错形如 `attempt to index a nil value` / `stack traceback:` 并带文件行号，**行号直接定位到 mod 文件**。

### 通道 3：控制台命令（L2/L3）

服务器以 `-console` 启动时可接受 `c_*` 命令。已确认存在且常用的：

| 用途 | 命令 |
|---|---|
| 生成/给予 | `c_spawn("prefab", n)`、`c_give("prefab", n)` |
| 选中/操作 | `c_sel()`、`c_findnext("prefab")`、`c_equip()`、`c_remove()` |
| 位置 | `c_pos()`、`c_printpos()`、`c_teleport()`、`c_goto()` |
| 世界状态 | `c_countprefabs("x")`、`c_counttagged("tag")`、`c_listtag()`、`c_dumpworldstate()` |
| 存/退 | `c_save()`、`c_shutdown()` |

> **待验证**：能否用管道把命令喂进服务器 stdin 并捕获 stdout（决定 L2 能否全自动）。首次做 L2 前先花 2 分钟验证这条通道；不行就退回"写进测试 mod 的 `AddSimPostInit` 里自动跑"。

### 通道 4：测试 mod（L2/L3 的主力）

不让测试代码污染被测 mod。做法：一个独立的 `harness` mod，只在测试集群启用，靠注入点观察被测 mod：

```lua
-- harness/modmain.lua 骨架
local function T(name, ok, detail)
    print(string.format("[TEST] %s %s %s", name, ok and "PASS" or "FAIL", detail or ""))
end

AddPrefabPostInit("my_weapon", function(inst)
    T("prefab_exists", inst ~= nil)
    T("has_weapon_comp", inst.components.weapon ~= nil)
    if inst.components.weapon then
        T("damage", inst.components.weapon.damage == 50,
          "expect 50 got " .. tostring(inst.components.weapon.damage))
    end
end)

AddSimPostInit(function()
    local total, pass, fail = 0, 0, 0   -- 汇总后打印 [TEST-SUMMARY]
end)
```

### 通道 5：截图（L4）

- **OS 层**：PowerShell 抓游戏窗口区域存 PNG，我直接读图判断。**确定可行**。
- **游戏内**：`TheScreenshotter:RequestScreenshot(cb)`，回调拿内存纹理，落盘能力未验证。

---

## 三、按 mod 类型的检查清单

测试时先判断类型，再从对应表里挑检查项，加上这次改动特有的项。

### 3.1 武器 / 工具

| 检查项 | 层 | 判据 |
|---|---|---|
| swap 包无 `anim.bin`，有 `build.bin` + `atlas-0.tex` | L0 | 条目名 |
| 物品包有 `anim.bin` | L0 | 条目名 |
| `build.bin` 标志位 = 8 | L0 | `atlas-0.tex` 起点 +23，uint32 |
| build 名 == `SetBuild(...)` 参数 | L0 | build.bin 串 vs Lua |
| 符号名 == `OverrideSymbol` 第 3 参数 | L0 | 同上 |
| `PlayAnimation("x")` 的 x 存在于 build | L0 | build.bin 串里有 |
| 图集元素名 == `imagename` / recipe `image` | L0 | xml vs Lua |
| `Assets` 里每条路径真实存在 | L0 | 文件系统 |
| `PrefabFiles` 不带路径不带 `.lua` | L0 | 字符串形态 |
| `STRINGS.NAMES.<PREFAB>` 的 key 是大写 | L0 | Lua |
| prefab 注册成功 | L1 | 日志 `Registering prefabs` 下有该名 |
| `weapon` / `equippable` / `inventoryitem` / `finiteuses` 组件存在 | L2 | `inst.components.x ~= nil` |
| 伤害值、使用次数符合预期 | L2 | 读组件字段 |
| 装备后 `owner.AnimState:GetBuild()` 为 swap build | L2 | 运行时读 |
| 装备后 `ARM_carry` 显示、`ARM_normal` 隐藏 | L2 | `IsShowing()` |
| 掉落/漂浮参数 | L2 | `Transform` 坐标、`MakeInventoryFloatable` 参数 |
| 握点视觉位置 | L4 | 截图人眼/我读图 |

### 3.2 人物 mod

| 检查项 | 层 | 判据 |
|---|---|---|
| `AddModCharacter("x", "FEMALE"/"MALE", ...)` 参数完整 | L0 | Lua |
| `STRINGS.CHARACTER_NAMES/TITLES/DESCRIPTIONS/QUOTES` 有该 key | L0 | Lua |
| `STRINGS.CHARACTERS.<NAME>` 说话表存在 | L0 | Lua |
| 头像/立绘图集存在且元素名对得上 | L0 | 文件 + xml |
| `MakePlayerCharacter` 的 `common_postinit` / `master_postinit` 都定义了 | L0 | Lua |
| 初始物品 `start_inv` 里的 prefab 都存在 | L0 | 交叉查 |
| 角色出现在选人界面 | L2 | `CHARACTERLIST` 含该 key |
| 出生后属性（血量/饥饿/理智/速度）符合设定 | L2 | 读组件 |
| 初始物品真的进了背包 | L2 | `inventory:Has(...)` |
| 说话不报错（访问 `STRINGS.CHARACTERS.X` 各处） | L2 | 日志无 `nil` 报错 |
| 死亡/复活流程 | L3 | 强制 `inst.components.health:SetPercent(0)` |
| 皮肤/身体贴图外观 | L4 | 截图 |

### 3.3 功能 mod（传送、命令、UI 扩展）

| 检查项 | 层 | 判据 |
|---|---|---|
| `AddModRPCHandler(modname, name, fn)` 注册名与 `GetModRPC` 一致 | L0 | Lua 交叉 |
| 服务端/客户端职责分清（`TheWorld.ismastersim` 分支） | L0 | Lua |
| 客户端不在 `modmain` 里调用服务端专属 API | L0 | Lua 审阅 |
| `AddAction` / `STRINGS.ACTIONS.<X>` / `AddStategraphActionHandler` 三件套齐全 | L0 | 缺一个动作就不出现 |
| 权限判断（非管理员不能传别人） | L0/L2 | Lua + 运行时 |
| 动作能否被触发（`inst:PushEvent` 或强制 `SendModRPCToServer`） | L3 | 日志/坐标变化 |
| 传送后坐标是否真的变了 | L3 | `c_pos()` 前后对比 |
| 多人同步 | L3 | **单人测不了**，只能验证服务端路径不报错 |

### 3.4 客户端 UI mod

只有 L4 有意义，L0 只能查 `AddClassPostConstruct` 的类名是否存在（去 `scripts.zip` 里查那个 Widget 类）。

---

## 四、统一测试协议

### 输出格式（强制）

```lua
print("[TEST] <case_id> PASS <detail>")
print("[TEST] <case_id> FAIL <detail>")
print("[TEST-SUMMARY] total=N pass=X fail=Y")
```

`case_id` 用 `类型.对象.检查项`，例如 `weapon.my_weapon.damage`、`char.wzk.start_inv`。

### 证据链

每条 PASS/FAIL 必须能追到一个可复核的来源：日志行、文件字节偏移、或运行时打印的字段值。**不允许出现"看起来没问题"这种判定。**

### 报告

每次测试写一份，存到：
```
<笔记库>\饥荒\测试报告\YYYYMMDD-HHMM-<mod名>.md
```
报告结构：结论一句话 → 通过的项 → 失败的项（带证据）→ 未验证的项（说明为什么）→ 建议的下一步。

### 工具落位

```
<工作区>\_dst_test\
├─ check_mod.ps1      # L0，通用，一次写好长期复用
├─ run_harness.ps1    # L1/L2，起服 + 喂命令 + 收日志
├─ capture.ps1        # L4，截游戏窗口
├─ reports\           # 原始日志副本
└─ baseline\          # 基线快照（见第六节）
```

---

## 五、常见故障对照表

拿症状直接定位，不用从头猜。

| 症状 | 首查 | 层 |
|---|---|---|
| 模组根本没加载 | `modinfo.lua` 字段、`modoverrides.lua` 里 `enabled=true`、日志 `Loading mod:` | L1 |
| `attempt to index a nil value` | 日志里的文件和行号 | L1 |
| 手上什么都没有 | `OverrideSymbol` 第 3 参数 vs build.bin 里的符号名 | L0 |
| 手上是一张白图/错图 | 同上 + atlas 里有没有那个符号 | L0 |
| 物品栏图标空白 | `atlasname` + `imagename` vs 图集 xml 元素名 | L0 |
| 地上看不见物品 | `SetBuild` 名、`PlayAnimation` 的动画名 | L0 |
| 放地上是透明框 | 物品包缺 `anim.bin`，或 build.bin 标志位不是 8 | L0 |
| 装备没反应 | `equippable:SetOnEquip` 是否设了、`equippable` 组件是否加 | L1/L2 |
| 伤害不对 | `weapon:SetDamage`、是否被别的 mod 改了乘法器 | L2 |
| 动作选项不出现 | `AddAction` + `STRINGS.ACTIONS` + `AddStategraphActionHandler` 缺一 | L0 |
| 传送没效果 | RPC 注册名不一致、客户端没发、服务端没在 `ismastersim` 分支里 | L2/L3 |
| 客户端崩、服务器正常 | `client_log.txt` 的 traceback | L1 |
| 只有洞穴报错 | 看 `caves_server_log.txt`，两份 `modoverrides` 不一致 | L1 |

---

## 六、比逐次手写脚本更好的做法

### 6.1 分层复用

`check_mod.ps1`（L0）与 mod 类型无关，写一次，以后所有 mod 都能跑。只有 L2 的断言需要按 mod 类型生成。**不要让每次测试都从零写脚本。**

### 6.2 基线快照 + diff（回归测试）

L2 跑完，把关键数值 dump 成一份 JSON/Lua 表存进 `baseline\`：

```lua
-- 例：weapon 基线
{ damage = 50, uses = 100, tags = {"sharp","pointy","weapon"}, float_scale = {1.1,0.5,1.1} }
```

下次跑完自动 diff，输出"本次 vs 基线"的差异。这是唯一能抓到**"改了 A，弄坏了 B"**的手段，比单次 PASS/FAIL 有价值得多。

### 6.3 一个入口

最终形态是 `test.ps1 <mod名>`：L0 → 起服 → L1 → L2 → diff 基线 → 写报告 → 关服。改完代码双击一次，后台跑 60 秒，期间可以继续写。

### 6.4 测试环境隔离

- 只用 `Cluster_1` 测，不碰平时玩的世界
- 测试前确认 `modoverrides.lua` 只留被测 mod + harness
- 改动任何集群配置前先整包备份
- 测试世界允许被搞乱，需要干净世界时用 `c_regenerateworld()` 而不是手动删存档

---

## 七、每次测试的标准流程（SOP）

1. **读代码**：`modinfo.lua` + `modmain.lua` + `scripts/prefabs/*.lua`，判断 mod 类型
2. **列清单**：按第三节挑对应表，加上这次改动的特有项，先给用户看一眼要测什么
3. **跑 L0**：静态检查，出 PASS/FAIL 表
4. **L0 有 FAIL 就停**，先修再往上层走（省一次 60 秒重启）
5. **跑 L1**：起服务器，只读日志，确认加载无报错
6. **跑 L2/L3**：harness mod 自动断言，收集 `[TEST]` 行
7. **需要视觉确认才跑 L4**，并且截图必须配一句"我在看什么"的说明
8. **写报告**：结论、证据、未验证项
9. **更新基线**：确认这次是对的，才把新数值写进 `baseline\`
10. **清理**：测试服关掉，`modoverrides.lua` 恢复原状或记录改动

---

## 八、边界（做不到的事，别许诺）

| 做不到 | 原因 | 替代 |
|---|---|---|
| 无头验证画面 | `nullrenderer` 不渲染 | 必须有客户端在场 |
| 自动操作角色（走、攻击、点 UI） | 无法注入鼠标键盘 | 用 `c_*` 命令直接改状态，绕过操作 |
| 验证"好不好看" | 主观 | 我读截图 + 描述，你拍板 |
| 双人/多人同步 | 需要第二个账号和客户端 | 只验服务端路径不报错，联机部分标"未验证" |
| 验证 Steam 创意工坊上传效果 | 涉及真实账号操作 | 只做本地包结构检查 |

---

## 九、待验证清单

下次有机会先花几分钟把这几条钉死，写进第零节：

1. `-console` 起服时能否用管道喂 stdin 命令、并捕获 stdout
2. `TheScreenshotter:RequestScreenshot` 的回调纹理能否落盘成 PNG
3. `c_regenerateworld()` 后 prefab 是否重新注册（影响测试复用）
4. 只起 Master 不起 Caves 时，`shard_enabled = true` 的集群能否正常运行（影响 L1 时长）

---

## 十、禁止事项

- ❌ 把测试代码留在正式 mod 里（要留就包在 `if TEST_MODE then ... end` 里）
- ❌ 直接改用户正在玩的存档
- ❌ 未经备份就改 `cluster.ini` / `modoverrides.lua`
- ❌ 用"应该没问题"替代日志证据
- ❌ 一次改多个变量后测出问题——分不清是谁的锅

---

## 十一、工具清单（`tools/`）

### 11.1 目录分工

```
tools\
├─ app\    日常 GUI。需要人工点界面，我不调用
├─ cli\    可脚本化。我的检查器和自动化会调用这里
├─ gui\    独立小 GUI，按需人工使用
└─ docs\   工具笔记（README 中英双份）
```

**归属原则**：能被命令行调用、需要进自动化脚本的 → `cli\`；必须点界面的 → `app\` / `gui\`。

### 11.2 `app\` —— 日常 GUI（我不调用）

| 工具 | 大小 | 功能 |
|---|---|---|
| `DST Mod Tool.exe` | 58 MB | tauri 应用 v1.2.0。编辑 scml / Spriter json / 二进制 bin 与 zip、查看 tex、批量打包 png。**日常主力** |
| `dst-mod-tool.exe` | 24 MB | 同类工具 v0.2.4，与上面不是同一个文件（哈希不同），功能相近 |
| `Asset Archive.exe` | 54 MB | `dont-starve-asset-archive`，资源包归档/解包 |
| `Spriter.exe - 快捷方式.lnk` | — | 指向已安装的 Spriter Pro：`<Spriter 安装目录>\Spriter.exe` |

### 11.3 `cli\` —— 可脚本化（自动化会调用）

| 工具 | 命令 | 功能 | 我什么时候用 |
|---|---|---|---|
| `ktools\krane.exe` | `krane <动画目录> <输出目录>`<br>`krane --mark-atlases build.bin <输出目录>`<br>`krane --check-animation-fidelity` | anim.bin + build.bin + atlas-0.tex → scml；生成边缘标记图；检查 Spriter 不支持的变换 | L0 需要还原资源结构、核对动画时 |
| `ktools\ktech.exe` | `ktech a.png`（tex→png）<br>`ktech b.png`（png→tex）<br>`ktech -i atlas-0.tex`（打印信息）<br>`ktech icon.png --atlas modicon.xml` | tex ↔ png、查元信息、连 atlas xml 一起生成 | 查 tex 尺寸/格式 |
| `ktools\BuildRenamer.exe` | 图形/命令行 | 改 build 名，并**删去 build.bin 尾部符号表** | 换皮肤、改 build 名 |
| `stex\stex.exe` | `stex pack -i <输入目录> -o <输出目录>`<br>`stex unpack -i x.xml -o <输出目录>` | 多图打包成 atlas.tex + key.xml（MaxRects）；反向拆包 | **打包贴图首选**，见下方限制 |
| `animbuilder\animc.exe` | `animc /anim a.xml /build b.xml /out <目录>` | xml → bin | 没有 Steam Mod Tools 时编译动画 |
| `animbuilder\animd.exe` | `animd /in <目录> /out <目录>` | bin → xml（结果缺 image 属性） | 反编译核对 |
| `pyscripts\cli.py` | `python cli.py <文件或目录> [参数]` | 全流程：zip→scml、build.json 处理、图片→atlas、重命名、裁剪等 | 批量处理、自动化拼装 |
| `steam\steam2md.py` | `python steam2md.py` | Steam 格式 ↔ markdown | 写创意工坊说明 |
| `fsb-extractor\FMOD FSB Extractor.exe` | 命令行 | `.fsb` → `.wav` | 处理音效 |

**三条必须记住的限制**：

1. **打包带透明通道的贴图只能用 `stex`。** 工具集原作者原话：*"stex 是唯一一个正确处理透明图片的程序，因此建议不要使用 ktech 或者 ztools"*。
2. **`krane` / `ktech` 是 32 位程序**，处理超大图集时受 2 GB 地址空间限制。
3. **`pyscripts` 靠相对路径找工具**：`ktech.py` 搜 `../../ktools`，`stex.py` 搜 `../../stex`。所以 `pyscripts`、`ktools`、`stex` **必须留在 `cli\` 下的同级位置**，移动任何一个都要同步检查这两个搜索路径。

> `BuildRenamer` 会删掉 `build.bin` 尾部的符号表，导致字节布局变化——这正是「标志位不能写死偏移 65，必须按 `atlas-0.tex` 起点 +23 定位」的原因（见零节）。

### 11.4 `gui\` —— 按需人工

| 工具 | 功能 | 状态 |
|---|---|---|
| `bmfont\bmfont64.exe` | 字体制作（BMFont **1.14a**） | 可用。注意 Klei 官方用的是 **1.12a**，版本差异可能产生格式差异 |
| `fsbextractor\FsbExtractor.exe` | `.fsb` 音频提取（图形版） | 可用 |
| `speech-editor\SpeechFileUpdater.exe` | 说话文件编辑/对比（人物 mod 用） | **当前不可用**：x86 程序，本机只有 x64 的 .NET，`C:\Program Files (x86)\dotnet` 不存在。修法：`winget install Microsoft.DotNet.DesktopRuntime.8 --architecture x86` |

### 11.5 工具与测试层的对应

| 测试层 | 会用到的工具 |
|---|---|
| **L0 静态检查** | `pyscripts`（解析 zip/build）、`krane`（反编译核对）、`ktech -i`（tex 元信息）、`stex unpack`（拆图集看元素名） |
| **L1 / L2** | 不需要工具，只看日志 |
| **L4 视觉验证** | `app\DST Mod Tool`（播动画）、Spriter Pro（看姿态）、`bmfont`（字体） |

---

## 十二、参考资料清单（`refs/`）

### 12.1 结构

```
refs\
├─ mod_reference\
│   └─ mod_test_2\
│       ├─ assets\   8 个：参考图、中间产物
│       └─ codes\    3 个：参考代码
└─ other_reference\
    ├─ scripts\      4109 个：游戏 Lua 源码（从 scripts.zip 解出）
    ├─ Wilson_sample\  74 个：官方威尔逊 scml 工程
    ├─ notes\        1 个：API 速查笔记
    └─ modtemplate\  4 个：mod 骨架
```

### 12.2 各项用途

**`mod_reference\mod_test_2\assets\`（8 个）** —— 本 mod 的原始素材与中间产物：

| 文件 | 用途 |
|---|---|
| `original.png` (904 KB) | 原图 |
| `ruined_blade.png` (428 KB) | 处理后的贴图 |
| `ruined_blade_planted.png` (347 KB) | 插地形态的图 |
| `ruined_blade_icon_full_64.png` | 图标 |
| `my_weapon.zip` / `swap_my_weapon.zip` | 导出的动画包副本 |
| `swap_my_weapon.scml` | Spriter 源工程 |
| `mod_cover_icon_full_128.jpg` | 封面图 |

**`mod_reference\mod_test_2\codes\`（3 个）** —— 写代码时对照的原版实现：

| 文件 | 用途 |
|---|---|
| `spear.lua` (20 KB) | **原版长矛**。做武器 mod 时最好的对照物：组件、标签、漂浮参数、配方都能照抄 |
| `modmain_reference.lua` / `modinfo_reference.lua` | 参考 mod 的写法 |

**`other_reference\scripts\`（4109 个）** —— 游戏 Lua 源码，从 `data/databundles/scripts.zip` 解出。主要子目录：

| 子目录 | 文件数 | 查什么 |
|---|---|---|
| `prefabs\` | 1621 | 任何物品/生物/建筑的完整实现 |
| `components\` | 835 | 组件行为（weapon、health、inventoryitem…） |
| `stategraphs\` | 264 | 动作状态机（SGwilson 等） |
| `brains\` | 199 | AI |
| `widgets\` | 185 | UI 控件 |
| `screens\` | 63 | 界面 |
| `map\` | 44 | 世界生成 |

**这是零节「查 API 先查源码」那条铁律的落点。** 任何 `TheSim:` / `AnimState:` 方法存不存在、参数顺序，来这里查，不要凭记忆。

**`other_reference\Wilson_sample\`（74 个）** —— 官方威尔逊的 scml 工程：`build.scml` + 12 个部位目录（`arm_lower` `arm_upper` `cheeks` `face` `foot` `hair` `hair_hat` `hand` `headbase` `headbase_hat` `leg` `torso`）。

做**人物 mod** 时这是分层结构的范本：角色由哪些符号组成、每个部位多少张图、`build.scml` 怎么写。

**`other_reference\notes\字典.lua`（51 KB）** —— 「う丶青木」的 API 速查笔记（`GLOBAL.TheWorld`、`unpack`、`components` 等）。比翻源码快，但**可能过期**，冲突时以源码为准。

**`other_reference\modtemplate\`（4 个）** —— mod 骨架：`modinfo.lua`、`modmain.lua`、`modicon.tex`、`modicon.xml`。新建 mod 时直接复制改名。

### 12.3 维护规则

1. **`refs\` 不进 git**：游戏源码与第三方素材，约 270 MB，且涉及版权，已在 `.gitignore` 排除。
2. **换机器要重建**：跑 `tools\prepare_refs.ps1`：

   ```
   powershell -ExecutionPolicy Bypass -File .\tools\prepare_refs.ps1
   powershell -ExecutionPolicy Bypass -File .\tools\prepare_refs.ps1 -Force      # 覆盖已有
   powershell -ExecutionPolicy Bypass -File .\tools\prepare_refs.ps1 -GameDir "D:\Games\Don't Starve Together"
   ```

   脚本会：校验 zip 首 4 字节是不是 `PK\x03\x04`（不是所有 `.zip` 都是标准 zip）、只取 `scripts/` 前缀、解到 `refs\other_reference\scripts`、输出文件数与游戏版本号。实测 4109 个文件、约 32 秒。**它只重建 scripts 这一项**，`mod_reference` / `Wilson_sample` / `notes` / `modtemplate` 是人工整理的，不重建。
3. **会过期**：游戏更新后 `refs\scripts` 就是旧版本，查 API 前先确认 `version.txt` 与解压时一致（脚本每次都会打印版本号）。
4. **按 mod 分组**：以后每做一个新 mod，在 `mod_reference\` 下开一个新目录，不要往 `other_reference\` 里堆。

---

## 十三、起服实操（L1 的前提）

### 13.1 三种起服方式，本机只有一种能走通

| 方式 | 状态 | 说明 |
|---|---|---|
| **客户端点「开始游戏」** | ✅ **可用** | 客户端负责带 token、设工作目录、传 `-monitor_parent_process` / `-sigprefix` 等参数 |
| 手工命令行起专用服务器 | ❌ 本机失败 | 见 13.2，两次都崩 |
| 只起 Master、不起 Caves | 未验证 | 得先解决 13.2 |

**结论：要做 L1（读日志验加载），只能走客户端。** 这也是为什么「起服」这件事一直要用户操作，我没法代劳。

### 13.2 失败记录（2026-11-06 实测，三次尝试）

| # | 参数 | 现象 |
|---|---|---|
| 1 | 少 `-ownerdir` | `PersistRootStorage` 落到 `...\DoNotStarveTogether\Cluster_1\`（缺账号目录 `<账号目录>`），读错配置并**误建目录** |
| 2 | 补 `-ownerdir <账号目录>` | 目录对了，但 `Token file not found`，随后 `DoLuaFile Could not load lua file scripts/main.lua` |
| 3 | 再加 `-WorkingDirectory <游戏根>` | 仍失败，日志特征见下 |

第 3 次失败的关键日志：

```
[00:00:00]: Mounting file system databundles/klump.zip skipped.
[00:00:00]: Mounting file system databundles/scripts.zip skipped.
...
[00:00:01]: DoLuaFile Could not load lua file scripts/main.lua
[00:00:01]: Error loading main.lua
[00:00:01]: Failed mSimulation->Reset()
[00:00:01]: Error during game initialization!
```

而客户端拉起时的正常日志是：

```
[00:00:01]: Mounting file system databundles/klump.zip successful.
```

**判断**：所有数据包被 `skipped` → 找不到 `scripts/main.lua` → 初始化直接崩，进程 2 秒退出。**与 mod 无关。**

**两个可能原因，都未证实，不要当结论用**：

- 缺 `cluster_token.txt`（离线模式 `offline_cluster = true` 也没解决）
- 外置启动缺少客户端传的某些参数（`-monitor_parent_process`、`-sigprefix`、`-secondary_log_prefix`）

### 13.3 下次要再试，用这条命令

参数抄自客户端日志，补上 token 后可以复现环境：

```
bin64\dontstarve_dedicated_server_nullrenderer_x64.exe ^
  -persistent_storage_root APP:Klei/ -conf_dir DoNotStarveTogether ^
  -cluster Cluster_1 -shard Master ^
  -ownernetid <你的 SteamID> -ownerdir <账号目录> -clouddir <账号目录> ^
  -ugc_directory <创意工坊目录>
```

前提：先把 `cluster_token.txt` 放进 `Cluster_1\`（`accounts.klei.com` 生成）。另外用 `Start-Process` 启动时**必须设 `-WorkingDirectory` 为游戏根目录**，否则同样会 `skipped`。

### 13.4 一条诊断捷径

**只要日志里出现 `Mounting file system ... skipped`，问题一定在启动环境，不在 mod。**

别去改 mod 代码、别去动 `modoverrides.lua`——先去查启动参数和工作目录。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-06 | 初版。基于武器 mod 的实际排查（`mod_test_2`）与 `scripts.zip` 源码核实建立 |
| 2026-11-06 | 补充「0.1 本机源码位置」：绝对路径、版本号、解压复现步骤、zip 真伪判别（修补初版只写相对路径的疏漏） |
| 2026-11-06 | 新增「十一、工具清单」与「十二、参考资料清单」：`tools/` 四类工具的功能与调用方式、与 L0–L4 的对应关系；`refs/` 各项内容与用途 |
| 2026-11-06 | 新增「十三、起服实操」：三种起服方式的实测结论、三次失败记录与日志特征、可复现的命令行；`prepare_refs.ps1` 写入 12.3 并实测通过（4109 文件 / 32 秒） |
