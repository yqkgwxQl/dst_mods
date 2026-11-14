# 破败王者之刃 · 机制设计

> 配套文档：[setting_description.md](setting_description.md)（世界观与视觉语言）
> 状态：**P0 / P1 已完成，P2 战斗特效已完成（2026-11-13），v1.0.4 换用三护手分件贴图（2026-11-14）**；P3 待做。
> 数值以 `modmain.lua` 的 `TUNING.BLADE_OF_THE_RUINED_KING` 为准；实现见 `scripts/prefabs/blade_of_the_ruined_king.lua`。

---

## 0. 设计目标

**一句话**：一把打起来「越来越危险」的诅咒之剑——伤害不是来自面板，而是来自雾、印记和理智的交换。

三条原则：

1. **不靠面板**：单次伤害只比长矛高一点，强度来自附伤与印记；
2. **每次变强都有代价**：掉理智、低耐久、破碎风险；
3. **特效必须能看懂**：玩家不看数字也要知道「这一下触发了什么」。

---

## 1. 定位与获取

| 项 | 方案 | 状态 |
|---|---|---|
| 阶段 | 中期（不是第一天就能做） | ✅ |
| 科技 | 炼金引擎 `TECH.SCIENCE_TWO` | ✅ |
| 配方 | 噩梦燃料 ×2 + 金块 ×1 + 燧石 ×1 | ✅ |
| 分类 | 武器（`WEAPONS`）+ 模组 | ✅ |

> 理由：噩梦燃料要打暗影生物或下遗迹，天然把武器推到“见过世面”之后。

---

## 2. 数值总表

| 字段 | 值 | 对比 / 说明 |
|---|---|---|
| 伤害 | **54** | 长矛 34 / 火腿棒 59.5 / 暗影剑 68 |
| 耐久 | **100** | 长矛 150 / 暗影剑 100 / 玻璃刀 75 |
| 理智（装备时） | **-50/天** | 换算成每秒 `-50/480`；暗影剑 -160/天 |
| 生命偷取 | 命中 **+1**，击杀再 **+3** | — |
| 雾之锋（真伤） | 目标**当前生命 3%**，单次上限 **20** | 要求目标 `maxhealth > 100` |
| 抓挠之影 | 同一目标 **3 层** → 减速 **30%**，持续 **3 秒** | 叠层窗口 4 秒 |
| 低理智增伤 | `mult = 1 + (1 - sanity%) × 0.25`，**满理智 +0%，0 理智 +25%** | 连续加成，不是阈值 |

> 百分比伤害在 DST 里很危险：BOSS 动辄上万血，3% 当前生命就是 300。**必须加上限**（20），并且目标血量低于 100 的小怪不触发，否则几刀就能磨死远古、顺手秒掉小鸡。

---

## 3. 玩家视角的核心循环

1. 平 A 叠「破败印记」→ 第 3 下触发爪痕，减速窗口继续追打；
2. 血量靠吸血慢慢回，不需要带太多药；
3. 理智一路掉，**越低越强**——但低理智会引来影怪，风险自负；
4. 耐久是倒计时，碎了掉 2 个噩梦燃料，用燃料还能修回来（见 4.5）。

---

## 4. 机制细节

### 4.1 雾之锋（命中附伤）

- **触发**：`weapon:SetOnAttack(fn)`，伤害结算之后调用；
- **条件**：目标有 `health`、未死亡、`maxhealth > 100`；
- **伤害**：`min(currenthealth × 0.03, 20)`；
- **落点**：`target_health:DoDelta(-dmg, false, "blade_mist")`，**不走** `combat:GetAttacked`，否则会二次触发 `onattack` 形成递归；
- **不排除玩家**：PvP 关闭时本来就打不到玩家；开启 PvP 时会生效（已接受这个表现）；
- **按“挨打后”的血量计算**：因为 `onattack` 在伤害结算之后，目标血量已经掉过一截，所以实际收益略低于理论上限。

### 4.2 抓挠之影（三击减速）

- **数据结构**：每把武器一张表

  ```lua
  inst._target_vector[target] = { level_count = 0, time = 0, slow_task = nil }
  ```

  以实体为 key，目标被移除时通过 `onremove` 监听删除记录，避免引用堆积；
- **叠层**：4 秒窗口内命中同一目标 +1 层，超时或换目标不影响其他目标的记录；
- **第 3 层触发**：
  - `loco:SetExternalSpeedMultiplier(inst, "ruined_blade_slow", 0.7)`
  - 3 秒后 `RemoveExternalSpeedMultiplier(inst, "ruined_blade_slow")`
  - 重复触发时先 `slow_task:Cancel()`，再排新任务
- **交错**：不同武器（source 不同）会叠乘，两把剑同时砍 = 0.7 × 0.7 ≈ 0.49。

### 4.3 生命偷取

- 命中：`attacker.components.health:DoDelta(1)`；
- 击杀：同一回调里判断 `target_health:IsDead()`，再 `+3`；
- 顺序：雾之锋 → 命中回血 → 击杀判定，保证“被雾之锋打死”也算击杀；
- 不加“吸血动画”，用剑身闪光代替（见第 8 节）。

### 4.4 破败之咒（代价）

- `equippable.dapperness = -50/480`（每秒），即 **-50/天**；
- 低理智增伤写在 `get_damage` 里：`1 + (1 - sanity:GetPercent()) × 0.25`；
- 无理智组件的持有者按满理智处理（不加成）；
- 可选彩蛋：理智 < 25% 时偶尔播放一句低语音效（不影响数值，未实现）。

### 4.5 耐久、破碎与修复

- 100 次，`finiteuses`；
- **已实现（破碎掉落）**：`SetOnFinished(onfinished)`，耐久归零时在剑的位置刷 **2 个噩梦燃料**（带随机偏移），再 `inst:Remove()`；黑雾爆散特效留到 P2；
- **已实现（修理）**：剑挂 `repairable`，`repairmaterial = MATERIALS.NIGHTMARE`（`"nightmare"`）。噩梦燃料**原版自带** `repairer`（材料 `MATERIALS.NIGHTMARE`，`finiteusesrepairvalue = TUNING.NIGHTMAREFUEL_FINITEUSESREPAIRVALUE` = **50**），所以**不需要** `AddPrefabPostInit`；
- `finiteusesrepairable` 标签由 `finiteuses` 自动维护（耐久 < 上限时加，满了摘），不用手写；
- 右键噩梦燃料修一次 **+50 耐久**，消耗 1 个燃料；满耐久时右键不消耗；
- **坑**：材料名必须是 `"nightmare"`。`MATERIALS` 表里没有 `"nightmarefuel"`，写错会导致右键永远不出现“修理”；
- 副作用：所有带 `repairable_nightmare` 标签的物品都能被噩梦燃料修（目前只有这把剑，原版生命护身符也用它）。

---

## 5. 实现落点（API 速查）

| 机制 | 落点 |
|---|---|
| 基础伤害 | `inst.components.weapon:SetDamage(get_damage)`（函数形式，每次命中现算） |
| 命中回调 | `inst.components.weapon:SetOnAttack(onattack)` |
| 理智 | `inst.components.equippable.dapperness = TUNING.…SANITY_DRAIN` |
| 耐久 | `inst.components.finiteuses`（`SetOnFinished(onfinished)` 换成自定义掉落函数） |
| 修理 | 剑挂 `repairable`（`repairmaterial = MATERIALS.NIGHTMARE`）；燃料的 `repairer` 原版自带 |
| 破碎掉落 | `onfinished` 里 `SpawnPrefab("nightmarefuel")` ×2 + `inst:Remove()` |
| 减速 | `target.components.locomotor:SetExternalSpeedMultiplier(inst, key, 0.7)` |
| 回血 | `attacker.components.health:DoDelta(n)` |
| 真伤 | `target.components.health:DoDelta(-dmg, false, "blade_mist")` |
| 命中特效 | `SpawnPrefab("...")` + `Transform:SetPosition/Rotation` |
| 跟随特效 | `fx.Follower:FollowSymbol(owner.GUID, "swap_object", 0, 0, 0)` |
| 剑身发光 | `owner.AnimState:SetSymbolLightOverride("swap_object", 0.4)` |

> `Weapon:GetDamage` 内部走 `FunctionOrValue`，所以 `self.damage` 可以是函数：
> `SetDamage(function(weapon, attacker, target) ... return dmg end)`，用来做低理智增伤。

---

## 6. 分阶段计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0 数值** | 伤害 54、耐久 100、噩梦燃料配方、炼金引擎、理智 -50/天 | ✅ 完成 |
| **P1 机制** | 雾之锋 + 三击减速 + 命中/击杀回血 + 低理智增伤 | ✅ 完成 |
| **P1 修复** | 噩梦燃料修复（原版 50 耐久/个） | ✅ 完成（2026-11-10） |
| **P1 破碎** | 破碎掉 2 个噩梦燃料 | ✅ 完成（2026-11-10） |
| **P2 特效** | 命中、第三击、击杀、破碎（黑雾爆散）四个特效 | ✅ 完成（2026-11-13） |
| **P3 打磨** | 常驻雾、低耐久裂纹、夜晚发光、配置项 | ⬜ 未开始 |

---

## 7. 已定事项与待定

**已定（2026-11-10）：**

1. 科技层级：炼金引擎（`TECH.SCIENCE_TWO`）✅
2. 百分比伤害：3% 当前生命 + 上限 20 ✅
3. 低理智：**连续加成**（0 理智 +25%），不用阈值 ✅
4. 基础伤害：54 ✅
5. 雾之锋不额外排除玩家 ✅
6. 英文名：`Blade of the Ruined King`（暂定）
7. 修复：用**原版噩梦燃料**（材料 `"nightmare"`），每次 +50 耐久，1 个燃料修一次 ✅
8. 破碎：掉 **2 个噩梦燃料** ✅

**还没定：**

- 抓挠之影触发时要不要顺带一个小硬直/击退？（会明显变强）
- 修一次 50 点会不会太慷慨？（原版值，改成 25 需要动全局 TUNING，会影响生命护身符）
- 特效是先做“能看懂”的极简版，还是直接上美术资源？

---

## 8. 特效路线图（VFX）

> 原则：**每个特效都要对应一条机制**，不做纯装饰；先做“能看懂”，再做好看。

### 8.1 命中 · 雾之锋

- **触发**：每次命中（`onattack` 里）；
- **表现**：青绿斩痕一闪 + 黑雾从伤口散开，0.2 秒内消失；
- **实现**：`SpawnPrefab("ruined_blade_hit_fx")` 放在 target 位置，按攻击方向设旋转；FX 用 `abigail_attack_fx.lua` 那套模板（`AddAnimState` → `PlayAnimation` → `animover` 移除，`persists = false`）。
- **实际（2026-11-13）**：复用原版 `wanda_attack_shadowweapon_normal_fx`；目标血量上限 >100 用默认大小，≤100 用 0.6 缩放；位置 target + 0.2 高度，按攻击方向旋转。

### 8.2 第三击 · 抓挠之影

- **触发**：印记叠满 3 层；
- **表现**：三道黑雾爪痕从目标身上划过 + 一圈地面冲击环 + 低频“撕”声；
- **实现**：同上的 FX prefab，动画 4–6 帧；减速的 3 秒里让目标身上挂一个淡黑色粒子。
- **实际（2026-11-13）**：`shadowstrike_slash2_fx`，只在目标带 `locomotor` 时生成，位置 target + 0.3 高度；未做目标身上的持续粒子。

### 8.3 击杀 · 夺魂

- **触发**：目标死亡；
- **表现**：一缕青绿魂火从尸体飘向剑，剑身闪一下；
- **实现**：`SpawnPrefab` 一个带 `Follower` 的 FX，`FollowSymbol(owner.GUID, "swap_object")`，1.5 秒后消失；同时 `SetSymbolLightOverride` 短暂拉高亮度。
- **实际（2026-11-13）**：`wortox_soul_spawn_fx`（自带音效），位置 target + 0.5 高度；未做 Follower 和剑身闪光。

### 8.4 装备常驻 · 剑身黑雾

**状态**：⬜ 未实现（P3）

- **表现**：剑身缓慢渗出黑雾，低理智时更浓；
- **实现（省事版）**：直接把雾做进 swap 的 `idle` 动画里，零代码；
- **实现（进阶版）**：每 0.5–1 秒生成一个小 FX 跟随 `swap_object`，按理智值调频率。别每帧生成。

### 8.5 低耐久 · 裂纹发光

**状态**：⬜ 未实现（P3）

- **表现**：耐久 < 30% 时，剑脊裂纹开始透出红光/青光，越低越亮；
- **实现**：swap build 里加一个 `crack` 符号，用 `AnimState:ShowSymbol/HideSymbol("crack")` 按耐久切换；或 `SetSymbolLightOverride` 渐变。

### 8.6 夜晚 / 洞穴 · 自发光

**状态**：⬜ 未实现（P3）

- **表现**：黑暗环境里剑身有微弱青光（不照明，只是好看）；
- **实现**：`SetSymbolLightOverride("swap_object", 0.3~0.5)`，或挂一个极小的 `Light`（注意性能，别每把剑都开）。

### 8.7 破碎 · 黑雾爆散

- **表现**：剑碎成黑雾四散 + 2 个噩梦燃料飞出；
- **实现**：`finiteuses` 的 `SetOnFinished` 里 `SpawnPrefab` 爆散 FX + `SpawnPrefab("nightmarefuel")` ×2（带一点随机抛射）。
- **实际（2026-11-13）**：`shadow_puff_large_back` + `shadow_puff_large_front`（自带 `deathpoof` 音效）+ 2 个噩梦燃料（随机偏移）；未做抛射动画。

### 8.8 素材与性能

- **素材**：黑雾可从 `RuinedKing_KeyArt.jpg` 里抠、重绘；青绿刀光建议按 **2–3 倍分辨率**手绘 3–5 帧（现在武器贴图为 320 高、三护手分件版，放大做特效会糊）。
- **音效**：先用游戏内现成的暗影系音效占位，正式版再换。
- **性能**：所有 FX `persists = false`；命中特效每次攻击 1 个可接受；常驻粒子必须限频；同一时间剑身跟随特效不要超过 1 个。
