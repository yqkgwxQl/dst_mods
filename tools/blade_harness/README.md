# blade_harness —— 破败王者之刃的战斗逻辑测试

一个临时测试 mod（`server_only_mod`），在专用服务器启动后自动跑一遍战斗回调，把结果打到 `server_log.txt`。

## 测什么

| 项目 | 期望 |
|---|---|
| 6 个 FX prefab 能否生成 | 全部非 nil |
| 雾之锋真伤（1000 血，3% 封顶 20） | 20 |
| 雾之锋低血量（1000 上限 / 当前 100） | 3 |
| 大/小目标命中特效 | 各生成 1 个 |
| 三击减速 | 0.700，3 秒后 1.000 |
| 击杀吸血（+1 命中、+3 击杀） | +4 |
| 击杀魂火 | 生成 1 个 |
| 破碎掉落 + 黑雾 | 燃料 +2，前后 puff 各 1 |

## 怎么跑

1. 把本目录 junction 到游戏 mods：

```powershell
New-Item -ItemType Junction `
  -Path "<游戏目录>\mods\blade_harness" `
  -Target "<仓库>\tools\blade_harness"
```

2. 建一个测试集群，`modoverrides.lua` 同时启用：

```lua
return {
    blade_of_the_ruined_king = { enabled = true },
    blade_harness = { enabled = true },
}
```

3. 启动专用服务器（`-persistent_storage_root` 指向测试集群）
4. 等日志出现 `[HARNESS] DONE`

## 说明

- 不依赖玩家操作，直接调用 `weapon.components.weapon:OnAttack(attacker, target)`
- 用 `GLOBAL.SpawnPrefab` / `GLOBAL.Ents`，因为 mod 环境没有这些全局
- 测完删掉 junction 和测试集群即可，不影响正式存档
