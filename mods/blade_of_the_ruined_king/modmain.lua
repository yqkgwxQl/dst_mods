--[[
    1.modmain的运行环境是独立于游戏主环境的
    游戏不是直接把 modmain 丢进全局跑，而是先建一个沙箱表 env（mods.lua:258 CreateEnvironment）————> 也就是说modmain是运行在沙箱环境env中的
        把 modmain 放进去执行（mods.lua:550 InitializeModMain）。env 里预先塞好了一批东西：
            pairs ipairs print math table type string tostring require Class	Lua 基础函数和库，沙箱预置的
            TUNING	                                                            游戏调参表（伤害、耐久、理智速度都在里面）
            LEVELCATEGORY GROUND WORLD_TILES LOCKS KEYS LEVELTYPE	            世界生成用的常量
            GLOBAL                                                              通往游戏全局的门 !!!! 
            modname MODROOT	                                                    当前 mod 名、mod 根路径
            env                                                                 沙箱自己
            
    2.GLOBAL 是指向游戏真正的全局表，是对应mod拿到游戏全局里的资源的门
        env里是：
            没有 STRINGS、TheNet、TheInput、SpawnPrefab、TECH、RECIPETABS……的
            在沙箱里，你写 STRINGS 会去 env 里找，找不到就是 nil，不会自动回退到游戏全局表。所以要拿游戏里的东西，必须显式走 GLOBAL：
                GLOBAL.STRINGS.NAMES.BLADE_OF_THE_RUINED_KING = "破败王者之刃"  赋值    往 NAMES 表里写一个key
                GLOBAL.TECH.NONE                                               取值    从 TECH表里读出 NONE这个值（读完就没了，单独写一行等于没用)
                GLOBAL.SpawnPrefab("nightmarefuel")                            函数调用  取出 SpawnPrefab这个函数，然后执行它，参数是"nightmarefuel"

        local _G = GLOBAL。_G就是游戏全局 
        local env = env     env表示沙箱自己
    3.GLOBAL.STRINGS.NAMES.BLADE_OF_THE_RUINED_KING = "破败王者之刃" 你能告诉我为什么要这样写吗？为什么不GLOBAL.STRINGS.NAMES = "破败王者之刃"？
    因为 STRINGS.NAMES 是一张表，不是字符串。它的结构是“prefab 名 → 显示名”的字典：
        STRINGS
        ├─ NAMES
        │   ├─ TWIGS                        = "树枝"
        │   ├─ FLINT                        = "燧石"
        │   └─ BLADE_OF_THE_RUINED_KING     = "破败王者之刃"
        │
        ├─ RECIPE_DESC
        │   └─ BLADE_OF_THE_RUINED_KING     = "永失吾爱，举目破败"
        │
        └─ CHARACTERS
            │
            ├─ GENERIC                      ← “所有角色的默认值”
            │   ├─ DESCRIBE
            │   │   └─ BLADE_OF_THE_RUINED_KING = "她唇角的一弯…"
            │   └─ DESCRIBE_GENERIC        = "它是什么？"     ← 谁都没写时的万能句
            │
            ├─ WILSON                       ← 注意：全大写
            │   ├─ DESCRIBE
            │   │   └─ BLADE_OF_THE_RUINED_KING = "（Wilson对于破败王者之刃的 专属台词）"
            │   └─ DESCRIBE_GENERIC        = "Well, what's this?"
            │
            ├─ WENDY
            │   └─ DESCRIBE
            │       └─ BLADE_OF_THE_RUINED_KING = "（Wendy对于破败王者之刃的 的台词）"
            │
            └─ WOLFGANG …
    游戏检视一件物品时，走的是 stringutil.lua 的 GetDescription：
        -- ① 角色自己的
        STRINGS.CHARACTERS[character].DESCRIBE[itemname]
        -- ② 没有就退到 GENERIC
        STRINGS.CHARACTERS.GENERIC.DESCRIBE[itemname]
        -- ③ 还没有就用万能句
        STRINGS.CHARACTERS.GENERIC.DESCRIBE_GENERIC
]]
-- ========================================================================================================
-- ========================================================================================================
-- ========================================================================================================

PrefabFiles = {"blade_of_the_ruined_king"}     -- 对应 scripts/prefabs/blade_of_the_ruined_king.lua
--[[
    1.why 不是ProfabFiles = {"scripts/prefabs"}呢？
        PrefabFiles 里写的是“prefab 文件名”，不是“路径”；路径是引擎自己拼的，而且 scripts/ 和 prefabs/ 这两段它都帮你加好了。
    2.为什么modmain.lua里要写PrefabFiles = {"blade_of_the_ruined_king"}?
        因为 PrefabFiles 是“要把哪些 prefab 文件注册进游戏”的清单。没有它，你的 scripts/prefabs/blade_of_the_ruined_king.lua 就只是一份没人执行的文本。

    Example:
        PrefabFiles = {"blade_of_the_ruined_king", "blade_of_the_ruined_king_2"}    
        mod.PrefabFiles实际上：下标1: blade_of_the_ruined_king
                              下标2: blade_of_the_ruined_king_2
    游戏读完modmain后，会按照PrefabFiles逐个加载
    for _, prefab_path in ipairs(mod.PrefabFiles) do
        local ret = LoadPrefabFile("prefabs/"..prefab_path, nil, MODS_ROOT..modname.."/")
        ...     
    end

    函数返回的是这个文件 return 出来的 Prefab 列表，所以下面还有一层 for _, prefab in ipairs(ret)，把每个 prefab 登记进 mod.Prefabs
    最终得到mod.Prefabs
            eg:     name                        path                                root_path
                blade_of_the_ruined_king    prefabs/blade_of_the_ruined_king    F:\zhongzhuan\dst_mods\mods\blade_of_the_ruined_king
                blade_of_the_ruined_king_2  prefabs/blade_of_the_ruined_king_2  F:\zhongzhuan\dst_mods\mods\blade_of_the_ruined_king
    3.整个流程
        PrefabFiles 里的 "blade_of_the_ruined_king"
                │ 引擎补前缀
                ▼
        "prefabs/blade_of_the_ruined_king"
                │ 走 <mod>/scripts/?.lua 的搜索路径
                ▼
        <mod>/scripts/prefabs/blade_of_the_ruined_king.lua
                │ 执行这个文件
                ▼
        文件末尾 return Prefab("blade_of_the_ruined_king", fn, assets)
                │ 这个返回值被注册进全局 Prefabs 表
                ▼
        c_spawn / 配方产出 / 掉落物 才能按名字找到它
    4.如何理解"走 <mod>/scripts/?.lua 的搜索路径"?
        1-游戏启动时（main.lua）设的是：
            package.path = "scripts\\?.lua;scriptlibs\\?.lua"
        2-mod 加载时，mods.lua:398 又把自己的 scripts 目录插到最前面：
            package.path = MODS_ROOT..modname.."\\scripts\\?.lua;"..package.path ————> 即package.path = F:\zhongzhuan\dst_mods\mods\blade_of_the_ruined_king\\scripts\\?.lua  ;  scripts\\?.lua  ;  scriptlibs\\?.lua
        3-于是当引擎执行：
            LoadPrefabFile("prefabs/blade_of_the_ruined_king", "prefabs/blade_of_the_ruined_king_2"...)
            ? 被替换成 prefabs/blade_of_the_ruined_king，依次尝试：
                <MODS_ROOT><mod名>\scripts\prefabs\blade_of_the_ruined_king.lua ← 命中
                scripts\prefabs\...（游戏本体，找不到）
                scriptlibs\...

                <MODS_ROOT><mod名>\scripts\prefabs\blade_of_the_ruined_king_2.lua ← 命中
                scripts\prefabs\...（游戏本体，找不到）
                scriptlibs\...
        ]]
-- ========================================================================================================
-- ========================================================================================================
-- ========================================================================================================
-- Assets表
--[[
    五个必须知道的点：

    1.它必须是全局变量（前面不能加 local）。游戏执行完 modmain 后，从 env.Assets 把这个表读走——源码 mods.lua:675：
            local pref = Prefab("MOD_"..modname, nil, mod.Assets, prefabnames, true)
            RegisterSinglePrefab(pref)
            TheSim:LoadPrefabs({pref.name})
        也就是说，你的 Assets 被挂到一个自动生成的 MOD_<mod名> prefab 上，然后 LoadPrefabs 一次性预加载。它不是“声明”，是“启动时预载”。
    2.ATLAS 和 IMAGE 成对：xml 是“目录”，tex 是“图”；只声明 tex 会找不到图，只声明 xml 会找不到纹理。
    3.路径相对 mod 根目录（不是相对 modmain），所以 images/selection_square.xml。
    4.和 prefab 文件里的 Assets 区别：prefab 里的在 prefab 注册时按需加载；modmain 里的是全局预载，适合 UI 图集这种“随时要用”的资源。
    5.      位置                          作用域                  加载时机                         典型内容
    prefab 里的 local assets      跟着这个 prefab         prefab 注册 / 被需要时           物品自己的动画、贴图
    modmain 里的全局 Assets       整个 mod                mod 启动时一次性预载             UI 图集、要随时用的公共资源
        modmain 的 Assets 会被挂到一个自动生成的 MOD_<mod名> prefab 上，启动时 LoadPrefabs 预载
    ]]
Assets = {
    Asset("ANIM", "anim/blade_of_the_ruined_king.zip"),   
    Asset("ANIM", "anim/swap_blade_of_the_ruined_king.zip"),   
    Asset("ATLAS", "images/inventoryimages/inventoryimg_full_64.xml"),   
}       

-- ========================================================================================================
-- ========================================================================================================
-- ========================================================================================================
-- AddRecipe2(name, ingredient, tech, config, filter)   
    -- filter 指的就是制作栏左侧那些分类页。你打开制作栏，左边一竖排图标分别是：工具、照明、科学、精炼、武器、盔甲、服装、恢复、魔法、装饰、建筑、容器、烹饪、园艺、钓鱼、航海、骑乘、冬季、夏季、雨天、活动，
-- 添加配方  AddRecipe2(    产物，原料（噩梦燃料两个，燧石1个），所需科技层级，美术资源（atlas,image），分类(武器栏) )
AddRecipe2("blade_of_the_ruined_king", { Ingredient("nightmarefuel", 2), Ingredient("goldnugget", 1), Ingredient("flint", 1) },
    GLOBAL.TECH.SCIENCE_TWO, { atlas = "images/inventoryimages/inventoryimg_full_64.xml",
      image = "inventoryimg_full_64.tex" },{ "WEAPONS" })
      --image 要的是图集里的元素名（看 xml 里的 <Element name="...">），不是文件路径

-- ========================================================================================================
-- ========================================================================================================
-- ========================================================================================================

local mine_config = {
    BASE_DAMAGE  = 54,
    USES = 100,    
    SANITY_DRAIN = -50/480, --每秒
    -- 生命偷取	命中 +1，击杀再 +3
    LIFESTEAL_HIT = 1,      
    LIFESTEAL_KILL = 3,    
    --雾之锋(真伤) : 目标当前生命 3%，单次上限 20点伤害，要求目标生命值>100
    BLADE_OF_MIST_PERCENT = 0.03,
    BLADE_OF_MIST_LIMIT = 20,
    BLADE_OF_MIST_MIN_HEALTH = 100,
    -- 抓挠之影	: 同一目标 3 层 → 减速 30%，持续 3 秒
    -- Crawling Horror 抓挠之影
    RUIN_SLOW_KEY =  "ruined_blade_slow", -- 速度倍率的key,唯一即可
    RUIN_SLOW_STACK_WINDOW = 4,           -- 4s内没有命中直接清零
    RUIN_SLOW_TIME = 3,                   -- 简述时间
    RUIN_SLOW_MULT = 0.7,                 -- 0.7 ——> 减速 30%

}
GLOBAL.TUNING.BLADE_OF_THE_RUINED_KING = mine_config

--物品名：背包/箱子里的悬停名、制作栏里的产物名、物品获得提示
-- 查找顺序：
    --  游戏拿 prefab 名大写去查，查不到就显示原始 prefab 名或报缺名。
GLOBAL.STRINGS.NAMES.BLADE_OF_THE_RUINED_KING = "破败王者之刃"
--配方描述：制作栏里点开配方后，名字下面那两行小字
-- 查找顺序：
    -- STRINGS.RECIPE_DESC[string.upper(self.recipe.description or self.recipe.product)]
GLOBAL.STRINGS.RECIPE_DESC.BLADE_OF_THE_RUINED_KING = "永失吾爱，举目破败"
--检视台词：角色打量这件物品时说的话（默认角色通用）
-- 查找顺序：
    -- 先查当前角色的 STRINGS.CHARACTERS.WILSON.DESCRIBE.xxx；
    -- 找不到再回退到 STRINGS.CHARACTERS.GENERIC.DESCRIBE.xxx（就是你写的这行） ———————> 全局的，并非角色专属
    -- 还没有就用万能句 STRINGS.CHARACTERS.GENERIC.DESCRIBE_GENERIC            ———————> 全局的，并非角色专属
GLOBAL.STRINGS.CHARACTERS.GENERIC.DESCRIBE.BLADE_OF_THE_RUINED_KING = "她唇角的一弯，笑意中的温柔... 于她双眸中，我倾见爱如永恒"



-- ======================================OTHER==================================================================
-- ========================================================================================================
-- ========================================================================================================
--[[
//这里简要了解即可，以后主要靠搜索-------------------------------------------
TUNING（一张全局表）
│
├─ 角色基础属性
│   ├─ WILSON_HEALTH       = 150
│   ├─ WILSON_HUNGER       = 150
│   ├─ WILSON_SANITY       = 200
│   ├─ WATHGRITHR_SANITY   = 120
│   └─ WX78_MAX_SANITY     = 300
│
├─ 武器（你最能参考的一块）
│   ├─ SPEAR_DAMAGE        = wilson_attack          → 34
│   ├─ SPEAR_USES          = 150
│   ├─ HAMBAT_DAMAGE       = wilson_attack*1.75     → 59.5
│   ├─ HAMBAT_USES         = 100
│   ├─ NIGHTSWORD_DAMAGE   = wilson_attack*2        → 68
│   ├─ NIGHTSWORD_USES     = 100
│   ├─ BATBAT_DAMAGE       = wilson_attack*1.25     → 42.5
│   ├─ BATBAT_DRAIN        = wilson_attack*0.2      → 6.8
│   └─ GLASSCUTTER         = { USES=75, DAMAGE=68, DAMAGE_VS_SHADOW_BONUS=1.25, SHADOW_WEAR=0.5 }
│
├─ 理智（注意单位）
│   ├─ CRAZINESS_TINY      = -100/(day_time*4)      → -5/分钟
│   ├─ CRAZINESS_SMALL     = -100/(day_time*2)      → -10/分钟
│   ├─ CRAZINESS_MED       = -100/day_time          → -20/分钟
│   └─ SANITY_DAPPERNESS   = 1                      （换算系数）
│
├─ 盔甲（值 = 耐久，_ABSORPTION = 减伤）
│   ├─ ARMOR_SCRAP_HAT             = wilson_health*2.5*…
│   ├─ ARMOR_SCRAP_HAT_ABSORPTION  = 0.85
│   ├─ ARMORDREADSTONE             = wilson_health*8*…
│   └─ ARMORDREADSTONE_ABSORPTION  = 0.9
│
├─ 生物 / BOSS（按前缀成组）
│   ├─ SPIDER_*        (82 个键)
│   ├─ ALTERGUARDIAN_* (79)
│   ├─ CRABKING_*      (73)
│   ├─ HERMITCRAB_*    (68)
│   ├─ GESTALT_*       (62)
│   └─ …
│
└─ 世界 / 系统
    ├─ DAY / DUSK / NIGHT 相关时长
    ├─ SANITY_*        （光环、光强阈值、惩罚）
    └─ …
几个特点：
    大部分是扁平键值，命名规律是 对象_属性：SPEAR_DAMAGE、SPIDER_HEALTH
    值是表达式，常用 wilson_attack（34）、wilson_health（150）、day_time（300 秒）当基准
    少量是子表，比如 GLASSCUTTER、ARMOR_WETNESS，用 TUNING.GLASSCUTTER.USES 取
    键的总数是 5,686 个唯一名，别背，靠补全/搜索
//这里简要了解即可，以后主要靠搜索-------------------------------------------
scripts/components/  (835)
│
├─ 物品与装备
│   ├─ inventoryitem   能否进背包、图标、堆叠上限
│   ├─ equippable      装备槽、装备/卸下回调、dapperness
│   ├─ weapon          伤害、攻击回调、攻击距离
│   ├─ armor           吸收、耐久
│   ├─ finiteuses      次数耐久 ← 你正在用的
│   ├─ fueled          燃料值
│   ├─ perishable      腐烂
│   ├─ edible          食物属性
│   ├─ stackable       堆叠
│   ├─ container       容器（箱子）
│   ├─ inventory       背包
│   ├─ deployable      放置成建筑
│   ├─ repairable      可被修
│   ├─ repairer        能修别人 ← 噩梦燃料要挂的
│   └─ inspectable     检视（名字、描述）
│
├─ 生存状态
│   ├─ health          血量
│   ├─ hunger          饥饿
│   ├─ sanity          理智
│   ├─ temperature     体温
│   ├─ moisture        湿度
│   ├─ heater          热源
│   └─ insulator       保温
│
├─ 移动与物理
│   ├─ locomotor       移动速度、走路/跑步
│   ├─ rider           骑乘
│   ├─ boatphysics     船体物理
│   └─ embarker        上下船
│
├─ 行为与交互
│   ├─ workable        可砍/可采
│   ├─ burnable        可燃
│   ├─ hauntable       可作祟
│   ├─ talker          会说话
│   ├─ trader          会交易
│   ├─ follower        跟随
│   ├─ leader          招募
│   ├─ periodicspawner 周期刷东西
│   └─ maprevealable   揭示地图
│
└─ 生物 / AI
    ├─ combat          战斗（目标、逃跑）
    ├─ sleeper         睡觉
    ├─ pollinator      授粉
    └─ …
]]

-- ========================================================================================================
-- 【临时】自动化测试入口（用完请删除下面这一行，以及 scripts/autotest.lua）
-- ========================================================================================================
modimport("scripts/autotest.lua")