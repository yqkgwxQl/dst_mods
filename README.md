# 饥荒联机版模组 / Don't Starve Together Mods

个人制作的《饥荒联机版》(Don't Starve Together) 模组仓库，持续更新中。

A work-in-progress collection of Don't Starve Together mods.

> 目前仍在开发阶段，模组尚未发布到创意工坊。以下是已完成的内容。

---

## 包含的模组

### 破败王者之刃 · Ruined King's Blade

`mods/mod_test_2`

一把来自暗影岛的王者之刃。剑身残破，锋芒犹在。

| 项目 | 数值 |
|---|---|
| 类型 | 武器（WEAPONS 栏） |
| 伤害 | 50 |
| 耐久 | 100 次 |
| 配方 | 树枝 ×2 + 燧石 ×1 |
| 科技要求 | 无 |
| 特性 | 可漂浮、可作祟 |

游戏内描述：

> 永失吾爱，举目破败

**状态**：开发中。贴图与手持动画已可用，配方与数值仍在调整。

---

## 安装

**方式一：手动安装**

1. 把 `mods/` 下的模组文件夹整个复制到游戏的 mods 目录：
   - Windows：`<Steam 安装目录>\steamapps\common\Don't Starve Together\mods\`
2. 启动游戏 → 主菜单「模组」→ 找到对应模组 → 勾选启用
3. 新建或进入世界时，在「模组」选项卡里确认已启用

> 装到已有存档里可能影响平衡，建议先用新世界测试。

**方式二：创意工坊订阅**

尚未发布。

---

## 开发说明

本仓库同时是一套模组开发与测试环境，包含测试方法论和工具链。

```
.
├─ mods/     各个模组的源码（进仓库）
├─ docs/     测试手册、工具笔记（进仓库）
├─ refs/     游戏 Lua 源码与参考资料（不进仓库，可重建）
└─ tools/    开发工具（只提交 .ps1 脚本，其余为本地工具）
```

- **测试手册**：[docs/MOD测试手册.md](docs/MOD测试手册.md) —— 分层的测试方法与故障排查
- **重建参考资料**：`refs/` 未入库，clone 后执行

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\tools\prepare_refs.ps1
  # 游戏装在非默认位置时：
  # .\tools\prepare_refs.ps1 -GameDir "D:\Games\Don't Starve Together"
  ```

  脚本从本机游戏的 `data/databundles/scripts.zip` 解压出约 4100 个 Lua 文件，供查 API 与参考原版实现使用。

- **让游戏读取仓库里的模组**（改完立即生效，无需复制）：

  ```
  mklink /J "<游戏目录>\mods\<模组名>" "<本仓库路径>\mods\<模组名>"
  ```

  删除联接用 `rmdir`，不要用 `Remove-Item -Recurse`——后者会顺着链接删掉仓库里的真实文件。

---

## 说明

- 本仓库**不包含**《饥荒联机版》的游戏本体、美术素材或 Lua 源码。`refs/` 由使用者从自己的游戏安装中生成，不随仓库分发。
- 游戏本体与相关素材版权归 Klei Entertainment 所有。
- 模组代码与自制美术素材由本仓库作者制作。

## 许可

- **代码**（Lua 脚本、PowerShell 脚本、文档）：[MIT](LICENSE)
- **美术素材**（各模组 `anim/` 与 `images/` 下的贴图、动画、图标）：保留所有权利，未经许可请勿转载或商用

---

*使用中遇到问题，欢迎提 Issue。*
