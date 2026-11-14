--[==[
================================================================================
  破败王者之刃 · blade_of_the_ruined_king.lua 注释存档
================================================================================
用途：完整保留注释与代码，供翻阅、检索、讲解。
注意：本文件不参与游戏加载；实际代码以 blade_of_the_ruined_king.lua 为准，请勿在此修改。
同步：改完精简版后，运行 tools\scripts\sync_annotated.ps1 重新生成本文件。
版本：v1.0.5
================================================================================
]==]

local assets =
{
    Asset("ANIM", "anim/blade_of_the_ruined_king.zip"),
    Asset("ANIM", "anim/swap_blade_of_the_ruined_king.zip"),
    Asset("ATLAS", "images/inventoryimages/inventoryimg_full_64.xml"),
}


local function UpdateGlow(inst)
    if not inst:IsValid() then return end
    local owner = inst._glow_owner
    if owner == nil or not owner:IsValid() then return end
    inst._flash = math.max(0, (inst._flash or 0) - 0.1)    -- 每0.1s -0.1
    local sanity = owner.components.sanity
    local s = sanity ~= nil and sanity:GetPercent() or 1  -- 没有 sanity 组件的生物默认 1（不加强）
    local uses = inst.components.finiteuses
    local dur = uses ~= nil and uses:GetPercent() or 1  -- 没有finiteuses 默认耐久1，不进行光效减弱
    local k = 0.25 + (1 - s) * 0.55 + inst._flash 
    if dur < 0.3 then   -- sin ——> 正弦，范围：-1 ~ 1
        k = k * (0.75 + 0.25 * math.sin(GetTime() * 12))
        if math.random() < 0.06 then k = k + 0.15 end
    end
    k = math.min(k, 0.85)
    if owner._blade_glow ~= nil then
        owner._blade_glow:set(k)
    end
end
local function onequip(inst, owner)
    local skin_build = inst:GetSkinBuild()
    if skin_build ~= nil then
        owner:PushEvent("equipskinneditem", inst:GetSkinName())
        owner.AnimState:OverrideItemSkinSymbol("swap_object", skin_build, "swap_blade_of_the_ruined_king", inst.GUID, "swap_blade_of_the_ruined_king")
    else
        -- 第 3 个参数是「符号名」，取的是编译产物 build.bin 里记录的符号，
        -- 不是 PNG 的文件名。你这个导出流程用 SCML 的 folder/entity 名当符号名，
        -- 你想写的符号名 = SCML 的 folder/entity 名，PNG 文件名随意（它只影响图片本身）
        -- 符号名 = build.bin 里记录的符号名（= SCML 的 folder/entity 名），不是 PNG 文件名
        owner.AnimState:OverrideSymbol("swap_object", "swap_blade_of_the_ruined_king", "swap_blade_of_the_ruined_king")
        --[[     DST Tool的************duration****************
        地面物品是静态绘制，只画第 0 帧，duration 不参与，所以地面一直正常；
        手持是 OverrideSymbol 到角色的 swap_object，引擎按时间取样播放这个符号。duration = 1 时这一帧几乎瞬间过期，引擎取不到可画的帧 → 什么都不画；
            ]]
    end
            --[[
        1.-------------------------------------------------------------------------------
        owner.AnimState:SetSymbolBloom("swap_object"): 把角色身上的 swap_object 这个符号标记为“参与泛光渲染”。
            此时 swap_object 已经被 OverrideSymbol 映射成了你的武器贴图，所以这句相当于：“角色手上这把剑，请给它加泛光。”


        2.-------------------------------------------------------------------------------
            API                     作用                           是否受画质设置影响
        SetSymbolBloom          亮部产生光晕（后处理）              是，低画质可能关闭 bloom
        SetSymbolLightOverride  让符号在黑暗中“自发光”              否
        SetSymbolAddColour      直接叠加颜色                        否
        三者一般配合使用：
        ~~~
            owner.AnimState:SetSymbolBloom("swap_object")                 -- 光晕
            owner.AnimState:SetSymbolLightOverride("swap_object", 0.35)   -- 暗处可见
            owner.AnimState:SetSymbolAddColour("swap_object", 0.05,0.3,0.2,0) -- 呼吸色
        ~~~


        3.-------------------------------------------------------------------------------
        我想知道SetSymbolBloom() 怎么知道贴图哪里应该发光呢？
            SetSymbolBloom 只负责“开/关”，光晕强弱由贴图亮度和画质决定 ————> 只有贴图里本来就亮的区域（剑刃核心）才会亮。

        Bloom 的基本流程
        ~~~
            1. 角色和武器正常渲染
            2. 引擎把画面里“足够亮”的像素挑出来
            3. 对这些像素做模糊（Gaussian / downsample）
            4. 把模糊后的光晕叠加回原画面
        ~~~
        所以“哪里发光”= 哪里在最终画面里足够亮，不是贴图里画了一条“发光通道”。

        therefore不能“指定某一块发光”
            不能直接用 SetSymbolBloom 指定区域，但可以间接控制：
        eg:
            想要的效果	    做法
            只有刃口发光	贴图里把刃口画到接近白，其他压暗
            只有裂纹发光	把裂纹画成独立的高亮层，或单独做一个 FX
            整体更亮	SetSymbolAddColour 提高亮度（会连带影响泛光）
            整体更暗	SetSymbolMultColour 压暗（泛光会减弱）
            低理智更亮	脉冲式提高 AddColour，亮度上去，泛光自然变强
            ]]
    inst._glow_owner = owner;
    UpdateGlow(inst)          -- 立刻刷一次
    inst._glow_task = owner:DoPeriodicTask(0.1, function()
        UpdateGlow(inst)
    end)
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
    if inst._glow_task ~= nil then
        -- 把任务从注册表中删除
        inst._glow_task:Cancel()
        inst._glow_task = nil
    end
    if owner ~= nil and owner:IsValid() then
        -- 对SetSymbolBloom("swap_object") 的标记进行删除
        if owner._blade_glow ~= nil then
            owner._blade_glow:set(0)
            owner.AnimState:ClearSymbolBloom("swap_object") 
        end
        inst._glow_owner = nil





        inst._flash = 0
        owner.AnimState:Hide("ARM_carry")
        owner.AnimState:Show("ARM_normal")  
        local skin_build = inst:GetSkinBuild()
        if skin_build ~= nil then
            owner:PushEvent("unequipskinneditem", inst:GetSkinName())
        end
    end
end
local function spawn_fx(fx_name, x, y, z, angle, scale)
    local fx = SpawnPrefab(fx_name)
    if fx == nil then return end
    fx.Transform:SetPosition(x, y, z)
    if angle ~= nil then
        fx.Transform:SetRotation(angle)
    end
    if scale ~= nil then
        fx.Transform:SetScale(scale, scale, scale)
    end
    return fx
end

local function get_target_element(inst, target)
    if inst._target_vector == nil then
        inst._target_vector = {}
    end

    local _target_vector = inst._target_vector
    local target_element = _target_vector[target]
    if target_element == nil then
        target_element = {level_count = 0, time = 0, slow_task = nil}
        _target_vector[target] = target_element
         -- 目标被移除时自动清理，避免实体引用堆积
            -- 参数：监听事件，回调函数，来源
         inst:ListenForEvent("onremove", function(t)
            local target_element = inst._target_vector and inst._target_vector[t]
            if target_element ~= nil then
                if target_element.slow_task ~= nil then
                    if t:IsValid() and t.components.locomotor ~= nil then 
                        t.components.locomotor:RemoveExternalSpeedMultiplier(inst, TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_KEY)
                    end
                end
                inst._target_vector[t] = nil 
            end
         end, target)
    end
    return target_element
end

-- 抓挠之影 : 同一目标3层→减速30%
    -- locomotor 移动组件  建筑、树木、部分生物没有 locomotor（它们不移动），这时直接放弃，不报错。
local function apply_slow(inst, target, attacker, target_element)
    if target == nil then return end
    local loco = target.components.locomotor
    if loco == nil then return end
    --[[
    1.函数作用：
        挂减速。
    2.函数参数：
        参数         值                     作用
        source       inst（剑）             谁施加的。组件会监听这个实体的 onremove，实体没了自动清掉这一来源
        key          "ruined_blade_slow"    同一 source 下可以有多个 key，互不覆盖
        multiplier   0.7                    速度乘数，0.7 = 只剩 70% 速度 = 减速 30%
        内部实现是“按 source 分组存倍率”，最后把该 source 下所有 key 的倍率相乘。所以：
    3.注意：
        同一个 key 重复设置 → 覆盖
        不同 source 同时存在 → 叠乘（两把剑 0.7 × 0.7）
    4.thinking:
        loco:SetExternalSpeedMultiplier(source, key, multiplier)       √√√
        loco.SetExternalSpeedMultiplier(self, source, key, multiplier) √√√
        loco.SetExternalSpeedMultiplier(source, key, multiplier)       ×××
        ]]
    local tx, ty, tz  = target.Transform:GetWorldPosition()
    local angle = attacker ~= nil and attacker:GetAngleToPoint(tx, ty, tz) or nil
    spawn_fx("shadowstrike_slash2_fx", tx, ty + 0.3, tz, angle, nil)
    loco:SetExternalSpeedMultiplier(inst, TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_KEY, TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_MULT)
    -- 这里武器被移除时会进行广播  ————>  locomotor 的 onremove 监听会自动摘掉倍率

    -- 重复触发时，先取消旧的计时 ; 
    if target_element.slow_task ~= nil then
        target_element.slow_task:Cancel()   -- 删除旧的任务
        target_element.slow_task = nil 
    end

    target_element.slow_task = target:DoTaskInTime(TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_TIME, function(t)
        -- 时间到了，触发这个函数。首先把inst._ruin_slow_task置空
        target_element.slow_task = nil
        -- 移除这把武器对应标签的减速效果
        if t:IsValid() and t.components.locomotor ~= nil then 
            t.components.locomotor:RemoveExternalSpeedMultiplier(inst, TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_KEY)
        end
    end)
end
--[[ 细节：
        多把剑会叠加
            source 不同（每把剑一个实体），所以两个玩家同时砍同一个目标，减速会叠乘（0.7 × 0.7 ≈ 0.49）。
    ]]

-- inst: 武器，即破败王者之刃 attacker: 攻击者，即人物自己 target: 你所攻击的目标
    -- 抓挠之影 : 同一目标3层→减速30% ————> 雾之锋附带的真实伤害 ————> 命中 +1，击杀再 +3
local function onattack(inst, attacker, target)

    if attacker == nil then return end
    local now = GetTime()

        -- 没有目标直接返回
    if target == nil then return end

    local n = 0
    for _ in pairs(inst._target_vector) do n = n + 1 end
    if n > 32 then
        for t, e in pairs(inst._target_vector) do
            if (now - e.time) > TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_STACK_WINDOW and e.slow_task == nil then
                inst._target_vector[t] = nil
            end
        end
    end
    
    

    local mine_health = attacker ~= nil and attacker.components.health or nil
    local target_health = target ~= nil and target.components.health or nil

    -- 设定光效 flash
    inst._flash = 0.35

    -- 雾之锋附带的真实伤害
    --[[
        1.DST 是 3D 世界：
            y 是高度（上下）
            x、z 是地面（前后左右）
        2.  target.Transform:GetPosition()        -- 本地坐标
            target.Transform:GetWorldPosition()   -- 世界坐标
        一般物体两者相同；但如果目标站在船、平台、被父节点挂载的东西上，GetPosition 是相对父节点的，直接拿来 SetPosition 会偏。
        ]]
    if target_health ~= nil and not target_health:IsDead() then
        local tx, ty, tz  = target.Transform:GetWorldPosition()
        local angle = attacker ~= nil and attacker:GetAngleToPoint(tx, ty, tz) or nil
        if target_health.maxhealth > TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_MIN_HEALTH then
            local damage = math.min(target_health.currenthealth * TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_PERCENT, TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_LIMIT)
            -- false: 不是持续伤害 "blade_of_mist": 造成的伤害标签
            target_health:DoDelta(-damage, false, "blade_of_mist")
            spawn_fx("wanda_attack_shadowweapon_normal_fx", tx, ty + 0.2, tz, angle, nil)
        else 
            spawn_fx("wanda_attack_shadowweapon_normal_fx", tx, ty + 0.2, tz, nil, 0.6)
        end
    end
        -- 如果我死了，直接返回
    if mine_health == nil or mine_health:IsDead() then return end

    -- 命中 +1，击杀再 +3
    if target_health ~= nil then
        mine_health:DoDelta(TUNING.BLADE_OF_THE_RUINED_KING.LIFESTEAL_HIT)
    end
    
    if target_health ~= nil and target_health:IsDead() then
        mine_health:DoDelta(TUNING.BLADE_OF_THE_RUINED_KING.LIFESTEAL_KILL)
        local tx, ty, tz  = target.Transform:GetWorldPosition()
        local angle = attacker ~= nil and attacker:GetAngleToPoint(tx, ty, tz) or nil
        spawn_fx("wortox_soul_spawn_fx", tx, ty + 0.5, tz, angle, nil)
        -- local fx = SpawnPrefab("wortox_soul_spawn_fx")        -- 由此看出特效其实也是prefab
        -- if fx ~= nil then
        --     local tx, ty, tz = target.Transform:GetWorldPosition()
        --     -- 设置特效初始位置
        --     fx.Transform:SetPosition(tx, ty, tz)
        --     local ax, ay, az = attacker:GetWorldPosition()
        --     --attacker:GetAngleToPoint(x, y, z) ——————> “攻击者要朝向 (x, y, z) 这个点，rotation 应该是多少度？
        --     if ax ~= tx or az ~= tz then
        --         fx.Transform:SetRotation(attacker:GetAngleToPoint(tx, ty, tz))
        --     end
        -- end
        inst._flash = 0.8
    elseif target_health ~= nil then 

        -- 抓挠之影 : 同一目标3层→减速30%
        local target_element = get_target_element(inst, target)
        -- if 攻击目标不是上一次的攻击目标 or 攻击时间超过了自定义的窗口时间 ， 直接换攻击目标 | 重置攻击事件 | 重置攻击层数
        if (now - target_element.time) > TUNING.BLADE_OF_THE_RUINED_KING.RUIN_SLOW_STACK_WINDOW then
            target_element.level_count = 0 
        end

        target_element.time = now
        target_element.level_count = target_element.level_count + 1
        if target_element.level_count >= 3 then
            target_element.level_count = 0
            apply_slow(inst, target, attacker, target_element)
        end
    end
end

local function get_damage(weapon_inst, attacker, target)
    local damage = TUNING.BLADE_OF_THE_RUINED_KING.BASE_DAMAGE
    local sanity = attacker ~= nil and attacker.components.sanity or nil
    local sanity_percent = 1
    if sanity ~= nil then sanity_percent = sanity:GetPercent() end
    local mult = 1 + (1 - sanity_percent) * 0.25   -- 满理智 +0%，0 理智 +25%
    damage = damage * mult
    return damage
end

local function onfinished(inst)
    local pos = inst:GetPosition()
    -- 做惰性清理
    for i = 1, 2 do
        local fuel = SpawnPrefab("nightmarefuel")
        if fuel ~= nil then
            -- 随机偏差，避免两个燃料完全重叠
            local ox = (math.random() - 0.5) * 1.2
            local oz = (math.random() - 0.5) * 1.2
            fuel.Transform:SetPosition(pos.x + ox, pos.y, pos.z + oz)
        end
    end
    -- 想加音效/黑雾特效？？？？
    local tx, ty, tz  = inst.Transform:GetWorldPosition()
    spawn_fx("shadow_puff_large_back", tx, ty, tz, nil, nil)
    spawn_fx("shadow_puff_large_front", tx, ty, tz, nil, nil)
    if inst._glow_task ~= nil then
        inst._glow_task:Cancel()
        inst._glow_task = nil
    end
    local owner = inst._glow_owner
    if owner ~= nil and owner:IsValid() and owner._blade_glow ~= nil then
        owner._blade_glow:set(0)
        owner.AnimState:ClearSymbolBloom("swap_object") 
    end
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("blade_of_the_ruined_king")
    inst.AnimState:SetBuild("blade_of_the_ruined_king")
    inst.AnimState:PlayAnimation("idle")        
    --[[   原来的mod是my_weapon和swap_my_weapon
    1.bank,build,anim..........................................................
    Spriter 里	            编译后成为	    Lua 里写在哪

    entity 的名字	    bank（动画库）	    SetBank("...")
    folder 的名字	    build（贴图集）	    SetBuild("...")
    animation 的名字	anim（某一个动作）	PlayAnimation("...")
        eg：
            swap_my_weapon.scml：
            
                <folder id="0" name="swap_my_weapon">          ← build  = "swap_my_weapon"
                <entity id="0" name="swap_my_weapon">          ← bank   = "swap_my_weapon"
                <animation id="0" name="build" ...>          ← anim   = "build"
                    <timeline id="0" name="ruined_blade">
                    <file id="0" name="swap_my_weapon/ruined_blade.png" .../>   ← symbol = "ruined_blade"

    2.my_weapon和swap_my_weapon...........................................................
    两个完全不同的使用场景：
                            地面 / 背包里的物品	                         拿在角色手上
    谁在画	        物品自己的 AnimState（inst.AnimState）	            角色的 AnimState（owner.AnimState）
    用哪个 zip	    anim/my_weapon.zip	                                anim/swap_my_weapon.zip
    怎么用	        SetBank / SetBuild / PlayAnimation	                OverrideSymbol 换掉角色手上的一个符号
    用到几个名字	三个（bank、build、anim）	                        两个（build、symbol）
    ..............................
    装备时，物品自己的模型是被隐藏的，游戏画的是角色；角色手里原本有一个空手符号 swap_object，我们要做的就是“把这个符号的贴图换成你的剑”。
    OverrideSymbol 干的就是这件事，它相当于“给角色手上的那个位置换一个 build” && swap_my_weapon.scml（手持形态）不会出现在这三行里，而是在装备回调中使用:
    ~~~
        owner.AnimState:OverrideSymbol(
            "swap_object",      -- ① 换角色身上哪个符号（固定写 "swap_object"，别改）
            "swap_my_weapon",   -- ② 用哪个 build  ← 对应 folder 名
            "swap_my_weapon"    -- ③ 用这个 build 里的哪个图片 ← 对应文件名
        )
    ~~~ 
    所以 swap 那一套的 bank 和 anim 全程没人读——因为没有任何代码去“播放 swap 的动画”，角色播放的是自己的攻击/待机动画，我们只借了它的一张图
    ..............................
    一个类比
        一个 .zip 就是一本画册：bank 是画册名，build 是里面的一页图集，anim 是翻页动作。
        物品自己看：翻开自己那本（SetBank/SetBuild/PlayAnimation）。
        拿在手上：物品不翻自己的书，而是从另一本书里撕下一页，贴到角色手上（OverrideSymbol）。
        所以 my_weapon.zip 是“物品自己那本”，swap_my_weapon.zip 是“给角色手用的贴图页”。
    ..............................
    对你这两个文件，完整对照
                             my_weapon.scml	                     swap_my_weapon.scml
        entity（bank）	         my_weapon	                        swap_my_weapon
        folder（build）	         my_weapon	                        swap_my_weapon
        animation（anim）	     idle	                            build（名字无所谓，没人播）          
        图片（symbol）	         ruined_blade_planted	        ruined_blade ❌ 应改成 swap_my_weapon <----|   
        代码里怎么用	SetBank("my_weapon")<br>SetBuild("my_weapon")<br>PlayAnimation("idle")	            |
                                                OverrideSymbol("swap_object", "swap_my_weapon", "swap_my_weapon") 
                                                                    替换的object  使用哪个贴图集    使用这个贴图集的哪个图片
    ..............................
    一句话记住：
        物品自己显示 → bank + build + anim 三件套；拿在手上 → 只借 build + symbol 两件套（通过 OverrideSymbol 贴到角色的 swap_object 上）。
    ]]
    inst:AddTag("sharp")
    inst:AddTag("pointy")

    --weapon (from weapon component) added to pristine state for optimization
    inst:AddTag("weapon")

    local floater_swap_data = {sym_build = "swap_blade_of_the_ruined_king"}
    MakeInventoryFloatable(inst, "med", 0.05, {1.1, 0.5, 1.1}, true, -9, floater_swap_data)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end
    -- mine_parameter
    --[[       被攻击者数组 _target_vector 里有 target_element
        inst._ruin = {
            [targetA] = { level_count = 2, time = 123.4, slow_task = nil },
            [targetB] = { level_count = 1, time = 125.0, slow_task = TaskB },
        }
    ]]
    inst._target_vector = {}


    inst._glow_owner = nil
    inst._glow_task = nil
    inst._flash = 0   -- flash 是攻击里设置的光效参数，是 onattack 里设的瞬时值：命中：0.35 击杀：0.8
    inst:AddComponent("weapon")
    -- inst.components.weapon:SetDamage(TUNING.BLADE_OF_THE_RUINED_KING.DAMAGE)
    inst.components.weapon:SetDamage(get_damage)
    -- 如果我把雾之峰的伤害调到武器的基础伤害里，就会走和base_damage一样走减伤逻辑(会被目标护甲，闪避等等影响) 
        -- 此处并不这样做，直接在onattack回调里附加伤害 ——————  真实伤害，因此数值偏低
    --[[
    inst.components.weapon:SetDamage(function(weapon_inst, attacker, target)
        local base = 48
        local hp = target and target.components.health
        if hp ~= nil and not target:HasTag("player") and hp.maxhealth >= 100 then
            local mist = math.min(hp.currenthealth * 0.03, 20)
            return base + mist
        end
        return base
    end)
        ]]
    inst.components.weapon:SetOnAttack(onattack)
    -------

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(TUNING.BLADE_OF_THE_RUINED_KING.USES)
    inst.components.finiteuses:SetUses(TUNING.BLADE_OF_THE_RUINED_KING.USES)
    inst.components.finiteuses:SetOnFinished(onfinished)

    -- 可修理：配合噩梦燃料的 repairer，右键使用一次修 50 耐久
    inst:AddComponent("repairable")
    inst.components.repairable.repairmaterial = MATERIALS.NIGHTMARE

    inst:AddComponent("inspectable")
    --知道要去这个地方找图片
    --[[
    物品栏没图标：日志原话
    ~~~
        WARNING! Could not find region 'my_weapon.tex' from atlas 'images/inventoryimages4.xml'.
    ~~~
    意思是：物品栏默认拿 prefab 名（my_weapon）去游戏自带的 inventoryimages4.xml 图集里找图标——你的图标在自己做的图集里，它当然找不到。

    修法：在 prefab 里 AddComponent("inventoryitem") 之后补两行，告诉它去哪找：
    ]]
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/inventoryimg_full_64.xml"
    inst.components.inventoryitem.imagename = "inventoryimg_full_64"        -- !!!!!!!!!!!

    inst:AddComponent("equippable")
    inst.components.equippable:SetOnEquip(onequip)
    inst.components.equippable:SetOnUnequip(onunequip)
    
    inst.components.equippable.dapperness = TUNING.BLADE_OF_THE_RUINED_KING.SANITY_DRAIN -- 理智（装备时）	-50/天
    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("blade_of_the_ruined_king", fn, assets)
--[[
    Lua 的 and / or 核心可以概括成四句话：
    只有 false 和 nil 是假，0、""、{} 都是真。
    a and b：a 假就返回 a；a 真就返回 b。
    a or b：a 真就返回 a；a 假就返回 b。
    它们返回的是操作数本身，不一定是 true / false。
    ]]
