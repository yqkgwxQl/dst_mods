local SpawnPrefab = GLOBAL.SpawnPrefab
local Ents = GLOBAL.Ents

local function log(fmt, ...)
    print("[HARNESS] " .. string.format(fmt, ...))
end

local function count(prefab)
    local n = 0
    for _, v in pairs(Ents) do
        if v.prefab == prefab and v:IsValid() then
            n = n + 1
        end
    end
    return n
end

local function spawn(prefab)
    local e = SpawnPrefab(prefab)
    if e == nil then
        log("spawn failed: %s", prefab)
    end
    return e
end

local function run()
    log("START")

    -- 0) FX prefab 是否都能生成
    local fx_names = {
        "wanda_attack_shadowweapon_normal_fx",
        "shadow_puff",
        "shadowstrike_slash2_fx",
        "wortox_soul_spawn_fx",
        "shadow_puff_large_front",
        "shadow_puff_large_back",
    }
    for _, name in ipairs(fx_names) do
        local e = SpawnPrefab(name)
        log("FX %s %s", name, e ~= nil and "PASS" or "FAIL")
        if e ~= nil then
            e:Remove()
        end
    end

    local attacker = spawn("pigman")
    attacker.components.health:SetMaxHealth(1000)
    attacker.components.health:SetVal(500)
    local weapon = spawn("blade_of_the_ruined_king")
    if attacker == nil or weapon == nil then
        log("FATAL: attacker/weapon spawn failed")
        return
    end

    -- 1) 雾之锋真伤：beefalo 1000 血，3% = 30，封顶 20
    local big = spawn("beefalo")
    big.components.health:SetMaxHealth(1000)
    big.components.health:SetVal(1000)
    local before = big.components.health.currenthealth
    weapon.components.weapon:OnAttack(attacker, big)
    local delta = before - big.components.health.currenthealth
    log("mist delta=%.2f expect=20 %s", delta, math.abs(delta - 20) < 0.01 and "PASS" or "FAIL")
    local bigfx = count("wanda_attack_shadowweapon_normal_fx")
    log("hit fx big=%d %s", bigfx, bigfx > 0 and "PASS" or "FAIL")

    -- 2) 小型目标命中：rabbit
    local small = spawn("rabbit")
    small.components.health:SetVal(small.components.health.maxhealth)
    local before_fx = count("wanda_attack_shadowweapon_normal_fx")
    weapon.components.weapon:OnAttack(attacker, small)
    local after_fx = count("wanda_attack_shadowweapon_normal_fx")
    local smallfx = after_fx - before_fx
    log("hit fx small=%d %s", smallfx, smallfx > 0 and "PASS" or "FAIL")

    -- 2.5) 伤害数值：理智加成
    local wdmg = spawn("blade_of_the_ruined_king")
    local dtarget = spawn("pigman")
    local function fake_attacker(s)
        return { components = { sanity = { GetPercent = function() return s end } } }
    end
    local d1 = wdmg.components.weapon:GetDamage(fake_attacker(1.0), dtarget)
    local d2 = wdmg.components.weapon:GetDamage(fake_attacker(0.5), dtarget)
    local d3 = wdmg.components.weapon:GetDamage(fake_attacker(0.0), dtarget)
    log("dmg sanity 1.0=%.2f expect=54.00 %s", d1, math.abs(d1 - 54) < 0.01 and "PASS" or "FAIL")
    log("dmg sanity 0.5=%.2f expect=60.75 %s", d2, math.abs(d2 - 60.75) < 0.01 and "PASS" or "FAIL")
    log("dmg sanity 0.0=%.2f expect=67.50 %s", d3, math.abs(d3 - 67.5) < 0.01 and "PASS" or "FAIL")

    -- 2.6) 雾之锋：低血量目标按 3% 计算
    local mist = spawn("beefalo")
    mist.components.health:SetMaxHealth(1000)
    mist.components.health:SetVal(100)
    local m0 = mist.components.health.currenthealth
    wdmg.components.weapon:OnAttack(attacker, mist)
    local mdelta = m0 - mist.components.health.currenthealth
    log("mist lowhp delta=%.2f expect=3 %s", mdelta, math.abs(mdelta - 3) < 0.01 and "PASS" or "FAIL")

    -- 3) 三击减速
    local dummy = spawn("pigman")
    dummy.components.health:SetMaxHealth(10000)
    dummy.components.health:SetVal(10000)
    local w2 = spawn("blade_of_the_ruined_king")
    for _ = 1, 3 do
        w2.components.weapon:OnAttack(attacker, dummy)
    end
    local mult = dummy.components.locomotor:ExternalSpeedMultiplier()
    log("slow mult=%.3f expect=0.700 %s", mult, math.abs(mult - 0.7) < 0.01 and "PASS" or "FAIL")
    dummy:DoTaskInTime(3.5, function()
        if dummy:IsValid() then
            local m = dummy.components.locomotor:ExternalSpeedMultiplier()
            log("slow expired=%.3f expect=1.000 %s", m, math.abs(m - 1.0) < 0.01 and "PASS" or "FAIL")
        end
    end)

    -- 4) 击杀魂火 + 吸血 (+1 命中, +3 击杀)
    local rabbit = spawn("rabbit")
    rabbit.components.health:Kill()
    local hp0 = attacker.components.health.currenthealth
    w2.components.weapon:OnAttack(attacker, rabbit)
    local dh = attacker.components.health.currenthealth - hp0
    log("lifesteal kill=%.2f expect=4 %s", dh, math.abs(dh - 4) < 0.01 and "PASS" or "FAIL")
    local soul = count("wortox_soul_spawn_fx")
    log("soul fx=%d %s", soul, soul > 0 and "PASS" or "FAIL")

    -- 5) 破碎：耐久 1，用 1 次
    local fuel0 = count("nightmarefuel")
    local w3 = spawn("blade_of_the_ruined_king")
    w3.components.finiteuses:SetUses(1)
    w3.components.finiteuses:Use(1)
    local fuel1 = count("nightmarefuel")
    log("break fuel +%d expect=2 %s", fuel1 - fuel0, (fuel1 - fuel0) == 2 and "PASS" or "FAIL")
    local puffs = count("shadow_puff_large_front") + count("shadow_puff_large_back")
    log("break puffs=%d %s", puffs, puffs >= 2 and "PASS" or "FAIL")

    log("DONE")
end

print("[HARNESS] modmain loaded")

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end
    inst:DoTaskInTime(5, function()
        local ok, err = GLOBAL.pcall(run)
        if not ok then
            log("ERROR %s", tostring(err))
        end
    end)
end)
