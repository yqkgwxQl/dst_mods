local assets =
{
    Asset("ANIM", "anim/blade_glow_fx.zip"),   
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddFollower()
    inst.entity:AddNetwork()
    --[[
        AddFollower() 给实体加一个 Follower 组件，让它能“跟着别的实体或某个符号走”。

        1.----------------------------
        inst.Follower:FollowSymbol(target.GUID, "swap_object", 0, 0, 0)
           参数      含义
        第 1 个   跟随哪个实体（GUID）
        第 2 个   跟随该实体的哪个符号，"swap_object" 就是手持物品
        x, y, z   相对该符号的偏移

        之后每帧引擎会把 FX 的 Transform 更新到目标符号的位置，剑挥到哪，光晕跟到哪。

        2.----------------------------
        注意事项
            1_ 目标消失要清理：持有者死亡/卸下/碎剑时，主动 fx:Remove()，否则 FX 会留在原地。
            2_ 偏移是相对值：0,0,0 表示和符号原点重合；对不齐就调这三个数。
            3_ Follower 不改变大小：缩放仍靠 Transform:SetScale。
            4_ AddFollower 只是加组件，不自动跟随，必须再调 FollowSymbol / FollowEntity。
        ]]
    inst.AnimState:SetBank("blade_glow_fx")
    inst.AnimState:SetBuild("blade_glow_fx")
    inst.AnimState:PlayAnimation("idle", true)
    inst.AnimState:SetMultColour(1, 1, 1, 0.5)  -- 透明度：0.5
    inst.AnimState:SetFinalOffset(2)   
    --[[
        SetFinalOffset 控制“这个 FX 整体画在角色前面还是后面”

        原理：
            DST 是 2D 渲染，所有东西按一个“排序键”从后往前画。这个键大体由：
            ~~~
                世界位置（y 坐标）
                + 实体类型/图层
                + FinalOffset
            ~~~
            组成。FinalOffset 就是给这个排序键加一个整数偏移：
                正数 → 往更前面画（盖住别人）
                负数 → 往更后面画（被别人盖住）
                0 → 默认层
            常见取值
                值	            典型用途
                -2、-1	    地面阴影、贴地特效
                0	        普通世界物件、角色
                1	        稍微靠前的 FX（火焰、光效）
                2	        明确盖在角色前面的 FX
                3、7	    更强的前景层（如 UI 附近的特效）
        ]]
    inst:AddTag("FX")

    inst._glow_alpha = net_float(inst.GUID, "blade_glow_alpha", "glowalphadirty")
    inst:ListenForEvent("glowalphadirty", function()
        inst.AnimState:SetMultColour(1, 1, 1, inst._glow_alpha:value())
    end)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    
    return inst
end


return Prefab("blade_glow_fx", fn, assets)