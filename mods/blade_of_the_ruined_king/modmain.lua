
PrefabFiles = {"blade_of_the_ruined_king"}     -- 对应 scripts/prefabs/blade_of_the_ruined_king.lua

Assets = {
    Asset("ANIM", "anim/blade_of_the_ruined_king.zip"),   
    Asset("ANIM", "anim/swap_blade_of_the_ruined_king.zip"),   
    Asset("ATLAS", "images/inventoryimages/inventoryimg_full_64.xml"),   
}       


-- AddRecipe2(name, ingredient, tech, config, filter)   
    -- filter 指的就是制作栏左侧那些分类页。你打开制作栏，左边一竖排图标分别是：工具、照明、科学、精炼、武器、盔甲、服装、恢复、魔法、装饰、建筑、容器、烹饪、园艺、钓鱼、航海、骑乘、冬季、夏季、雨天、活动，
-- 添加配方  AddRecipe2(    产物，原料（噩梦燃料两个，金块1个，燧石1个），所需科技层级，美术资源（atlas,image），分类(武器栏) )
AddRecipe2("blade_of_the_ruined_king", { Ingredient("nightmarefuel", 2), Ingredient("goldnugget", 1), Ingredient("flint", 1) },
    GLOBAL.TECH.SCIENCE_TWO, { atlas = "images/inventoryimages/inventoryimg_full_64.xml",
      image = "inventoryimg_full_64.tex" },{ "WEAPONS" })
      --image 要的是图集里的元素名（看 xml 里的 <Element name="...">），不是文件路径



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



