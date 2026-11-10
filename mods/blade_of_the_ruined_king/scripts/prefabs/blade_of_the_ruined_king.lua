local assets =
{
    Asset("ANIM", "anim/blade_of_the_ruined_king.zip"),
    Asset("ANIM", "anim/swap_blade_of_the_ruined_king.zip"),
    Asset("ATLAS", "images/inventoryimages/inventoryimg_full_64.xml"),
}


local function onequip(inst, owner)
    local skin_build = inst:GetSkinBuild()
    if skin_build ~= nil then
        owner:PushEvent("equipskinneditem", inst:GetSkinName())
        owner.AnimState:OverrideItemSkinSymbol("swap_object", skin_build, "swap_blade_of_the_ruined_king", inst.GUID, "swap_blade_of_the_ruined_king")
    else
        -- 符号名 = build.bin 里记录的符号名（= SCML 的 folder/entity 名），不是 PNG 文件名
        owner.AnimState:OverrideSymbol("swap_object", "swap_blade_of_the_ruined_king", "swap_blade_of_the_ruined_king")
    end
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
    local skin_build = inst:GetSkinBuild()
    if skin_build ~= nil then
        owner:PushEvent("unequipskinneditem", inst:GetSkinName())
    end
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
local function apply_slow(inst, target, target_element)
    -- locomotor 移动组件  建筑、树木、部分生物没有 locomotor（它们不移动），这时直接放弃，不报错。
    local loco = target.components.locomotor
    if loco == nil then return end
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

-- inst: 武器，即破败王者之刃 attacker: 攻击者，即人物自己 target: 你所攻击的目标
    -- 抓挠之影 : 同一目标3层→减速30% ————> 雾之锋附带的真实伤害 ————> 命中 +1，击杀再 +3
local function onattack(inst, attacker, target)

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

    -- 雾之锋附带的真实伤害
    if target_health ~= nil and not target_health:IsDead() then
        if target_health.maxhealth > TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_MIN_HEALTH then
            local damage = math.min(target_health.currenthealth * TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_PERCENT, TUNING.BLADE_OF_THE_RUINED_KING.BLADE_OF_MIST_LIMIT)
            -- false: 不是持续伤害 "blade_of_mist": 造成的伤害标签
            target_health:DoDelta(-damage, false, "blade_of_mist")
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
            apply_slow(inst, target, target_element)
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


    inst:AddComponent("weapon")
    -- inst.components.weapon:SetDamage(TUNING.BLADE_OF_THE_RUINED_KING.DAMAGE)
    inst.components.weapon:SetDamage(get_damage)
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
