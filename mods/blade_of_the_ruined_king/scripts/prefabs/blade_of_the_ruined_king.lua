local assets =
{
    Asset("ANIM", "anim/blade_of_the_ruined_king.zip"),
    Asset("ANIM", "anim/swap_blade_of_the_ruined_king.zip"),
}

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

    MakeInventoryFloatable(inst, "med", 0.05, {1.1, 0.5, 1.1}, true, -9)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(50)

    -------

    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(100)
    inst.components.finiteuses:SetUses(100)
    inst.components.finiteuses:SetOnFinished(inst.Remove)

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

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("blade_of_the_ruined_king", fn, assets)