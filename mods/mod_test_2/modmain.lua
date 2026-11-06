--[[
0. 先搞懂它跑在哪个环境里（这是理解 GLOBAL 的前提）
    游戏不是直接把 modmain 丢进全局跑，而是先建一个沙箱表 env（mods.lua:258 CreateEnvironment），
        把 modmain 放进去执行（mods.lua:550 InitializeModMain）。env 里预先塞好了一批东西：
            pairs, ipairs, print, math, table, type, string, tostring, require, Class,
            TUNING,
            LEVELCATEGORY, GROUND, WORLD_TILES, LOCKS, KEYS, LEVELTYPE,   -- 世界生成用
            GLOBAL = _G,        -- ← 真正的游戏全局表
            modname, MODROOT,   -- 当前 mod 名 / 路径
            env = env,
            modimport = ...,

    外加 modutil 注入的 AddComponentPostInit、AddPrefabPostInit、AddClassPostConstruct、GetModConfigData、modassert 等。 
    注意里面没有 TheNet、TheInput、SpawnPrefab、STRINGS、PLAYERCOLOURS……这些都在游戏全局里，所以必须通过 GLOBAL 拿。
    ]]

--此处的_G 不是游戏全局，而是那个沙箱表自己（源码 env.env = env）
local _G = GLOBAL

PrefabFiles = {"my_weapon"}     -- 对应 scripts/prefabs/my_weapon.lua
--[[
    why 不是ProfabFiles = {"scripts/prefabs"}呢？
        PrefabFiles 里写的是“prefab 文件名”，不是“路径”；路径是引擎自己拼的，而且 scripts/ 和 prefabs/ 这两段它都帮你加好了。

    链路：
        PrefabFiles = {"my_weapon"}
                │ 引擎加前缀 "prefabs/"
                ▼
        "prefabs/my_weapon"
                │ 走 package.path 里的 <mod>\scripts\?.lua
                ▼
        <mod>\scripts\prefabs\my_weapon.lua
    ]]
-- Assets表
--[[
    三个必须知道的点：

    1.它必须是全局变量（前面不能加 local）。游戏执行完 modmain 后，从 env.Assets 把这个表读走——源码 mods.lua:675：
            local pref = Prefab("MOD_"..modname, nil, mod.Assets, prefabnames, true)
            RegisterSinglePrefab(pref)
            TheSim:LoadPrefabs({pref.name})
        也就是说，你的 Assets 被挂到一个自动生成的 MOD_<mod名> prefab 上，然后 LoadPrefabs 一次性预加载。它不是“声明”，是“启动时预载”。
    2.ATLAS 和 IMAGE 成对：xml 是“目录”，tex 是“图”；只声明 tex 会找不到图，只声明 xml 会找不到纹理。
    3.路径相对 mod 根目录（不是相对 modmain），所以 images/selection_square.xml。
    4.和 prefab 文件里的 Assets 区别：prefab 里的在 prefab 注册时按需加载；modmain 里的是全局预载，适合 UI 图集这种“随时要用”的资源。
    ]]
Assets = {
    Asset("ANIM", "anim/my_weapon.zip"),   
    Asset("ANIM", "anim/swap_my_weapon.zip"),   
    Asset("ATLAS", "images/inventoryimages/inventoryimg_full_64.xml"),   
    Asset("IMAGE", "images/inventoryimages/inventoryimg_full_64.tex"),   
    Asset("ATLAS", "images/mod_cover_icon_full_128.xml"),   
    Asset("IMAGE", "images/mod_cover_icon_full_128.tex"),   
}

-- 添加配方  AddRecipe2(    产物，原料（树枝两个，燧石1个），所需科技层级，美术资源（atlas,image），分类(武器栏) )
AddRecipe2("my_weapon", { Ingredient("twigs", 2), Ingredient("flint", 1) },
    GLOBAL.TECH.NONE, { atlas = "images/inventoryimages/inventoryimg_full_64.xml",
      image = "inventoryimg_full_64.tex" },{ "WEAPONS" })
      --image 要的是图集里的元素名（看 xml 里的 <Element name="...">），不是文件路径

GLOBAL.STRINGS.NAMES.MY_WEAPON = "破败王者之刃"
GLOBAL.STRINGS.RECIPE_DESC.MY_WEAPON = "永失吾爱，举目破败"
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.MY_WEAPON = "她唇角的一弯，笑意中的温柔... 于她双眸中，我倾见爱如永恒"