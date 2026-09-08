local fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall = fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall
local MOD_TITLE   = "Support Hunter Simple Tweaks"
local config      = { enabled = true, multiplier = 1.0, multiplierInMulti = 1.0, chooseableEventPartner = false, equalChanceToJoinQuest = false }
local oldConfig
local NetworkManager
local UserInfoManager
local MissionManager

local function arrayIsEqual(a, b)
    if (type(a) ~= "table") or (type(b) ~= "table") then return false end
    if #a ~= #b                                     then return false end
    for key, value in pairs(a) do
        if type(value) == "table" then 
            if not arrayIsEqual(value, b[key]) then return false end
        elseif b[key]  ~= value                then return false end
    end
    for key in pairs(b) do 
        if a[key] == nil then return false end
    end
    return true
end

local function arrayDeepCopy(from)
    local ary = {}
    if not from              then return ary  end
    if type(from) ~= "table" then return from end
    for key, value in pairs(from) do 
        ary[key] = (type(value) == "table") and arrayDeepCopy(value) or value
    end
    return ary
end

local CONFIG_FILE = "Support_Hunter_Simple_Tweaks.json"
local function saveConfig(force)
    if (not force) and ((not oldConfig) or arrayIsEqual(config, oldConfig)) then return end
    json.dump_file(CONFIG_FILE, config)
    oldConfig = arrayDeepCopy(config)
end

local function loadConfig()
    if oldConfig then return end
    local loaded = json.load_file(CONFIG_FILE)
    if not loaded then return saveConfig(true) end

    if type(loaded.enabled)                ~= "boolean" then loaded.enabled                = true  end
    if type(loaded.multiplier)             ~= "number"  then loaded.multiplier             = 1.0   end
    if type(loaded.multiplierInMulti)      ~= "number"  then loaded.multiplierInMulti      = 1.0   end
    if type(loaded.chooseableEventPartner) ~= "boolean" then loaded.chooseableEventPartner = false end
    if type(loaded.equalChanceToJoinQuest) ~= "boolean" then loaded.equalChanceToJoinQuest = false end

    config    = arrayDeepCopy(loaded)
    oldConfig = arrayDeepCopy(loaded)
end

local function notifyMsg(msg)
    local ChatManager = sdk.get_managed_singleton("app.ChatManager")
    ChatManager:addSystemLog(msg)
end

local NPC_ONLY = sdk.find_type_definition("app.net_quest_session.cCreateQuestSessionInfo.MULTIPLAY_SETTING"):get_field("NPC_ONLY"):get_data()
local function isOnlySupportHunters()
    local cQuestDirector = MissionManager:get_QuestDirector()
    return (cQuestDirector:get_MultiPlaySetting() == NPC_ONLY)
end

local SESSION_TYPE_QUEST = sdk.find_type_definition("app.net_session_manager.SESSION_TYPE"):get_field("QUEST"):get_data()
local function isHostInQuest()
    if isOnlySupportHunters() then return true end
    local hostInfo = UserInfoManager:getHostUserInfo(SESSION_TYPE_QUEST)
    return hostInfo and hostInfo:get_IsSelf()
end

local function onCallOriginal(args)
    return sdk.PreHookResult.CALL_ORIGINAL
end

local function onPreSetup(args)
    local storage = thread.get_hook_storage()
    storage.cNpcPartnerStatus = (config.enabled and isHostInQuest() and (config.multiplier ~= 1.0)) and args[2] or nil
    return sdk.PreHookResult.CALL_ORIGINAL 
end

local function onPostSetup(retval)
    local storage = thread.get_hook_storage()
    local this    = sdk.to_managed_object(storage.cNpcPartnerStatus)
    if this then 
        local multiplier = not isOnlySupportHunters() and config.multiplierInMulti or config.multiplier
        this:set_Attack(math.floor(this:get_Attack() * multiplier))
        notifyMsg("Adjust Support Hunter Attack: x" .. multiplier)
    end
    return retval
end

local function onPostIsEnableEventPartner(retval)
    return (config.enabled and config.chooseableEventPartner) and sdk.to_ptr(true) or retval
end

local function onPreNpcPartnerLotteryInfoCtor(args)
    local storage = thread.get_hook_storage()
    if not config.enabled or not config.equalChanceToJoinQuest then storage.cNpcPartnerLotteryInfo = nil 
    else                                                            storage.cNpcPartnerLotteryInfo = args[2] end
    return sdk.PreHookResult.CALL_ORIGINAL
end

local PRIORITY_EVENT   = sdk.find_type_definition("app.cNpcPartnerLotteryInfo.PRIORITY"):get_field("EVENT"):get_data()
local PRIORITY_DEFAULT = sdk.find_type_definition("app.cNpcPartnerLotteryInfo.PRIORITY"):get_field("DEFAULT"):get_data()
local function onPostNpcPartnerLotteryInfoCtor()
    local storage = thread.get_hook_storage()
    local this    = sdk.to_managed_object(storage.cNpcPartnerLotteryInfo)
    if not this then return end
    if this:get_Priority() == PRIORITY_EVENT then this:set_Priority(PRIORITY_DEFAULT) end
end

sdk.hook(sdk.find_type_definition("app.cNpcPartnerStatus"):get_method("setup(app.NpcPartnerDef.RANK_TYPE, app.WeaponDef.TYPE, app.cNpcPartnerStatusData, System.Single, System.Single)"), onPreSetup, onPostSetup)
sdk.hook(sdk.find_type_definition("app.NpcPartnerUtil"):get_method("isEnableEventPartner(app.NpcDef.ID_Fixed)"), onCallOriginal, onPostIsEnableEventPartner)
sdk.hook(sdk.find_type_definition("app.cNpcPartnerLotteryInfo"):get_method(".ctor(app.NpcDef.ID, app.cNpcPartnerLotteryInfo.PRIORITY, app.user_data.NpcPartnerLotteryTable.cData)"), onPreNpcPartnerLotteryInfoCtor, onPostNpcPartnerLotteryInfoCtor)

local updateMod
local function initialize()
    loadConfig()

    if not NetworkManager then NetworkManager = sdk.get_managed_singleton("app.NetworkManager")
        if not NetworkManager then return end 
    end
    
    if not UserInfoManager then UserInfoManager = NetworkManager:get_UserInfoManager()
        if not UserInfoManager then return end
    end

    if not MissionManager then MissionManager = sdk.get_managed_singleton("app.MissionManager")
        if not MissionManager then return end
    end

    updateMod = function() end
end updateMod = initialize

re.on_frame(function() updateMod() end)
re.on_config_save(saveConfig)
re.on_draw_ui(function() if not imgui.tree_node(MOD_TITLE) then return end
    local changed, value

    changed, config.enabled = imgui.checkbox("Enable", config.enabled)
    imgui.spacing()

    imgui.begin_disabled(not config.enabled)
    imgui.text("Multiplayer(SOS) Settings:")
    imgui.text("  - Only Support Hunters")
    imgui.push_item_width(220)
    changed, value = imgui.slider_float("##SOLO", config.multiplier, 0.1, 10, "x%.1f")
    if changed then config.multiplier = math.floor((value + 0.05) * 10) / 10 end
    imgui.spacing()

    imgui.text("  - Players & Support Hunters")
    changed, value = imgui.slider_float("##MULTI", config.multiplierInMulti, 0.1, 10, "x%.1f")
    if changed then config.multiplierInMulti = math.floor((value + 0.05) * 10) / 10 end
    imgui.spacing()
    imgui.pop_item_width()
    
    changed, config.chooseableEventPartner = imgui.checkbox("Chooseable Fabius and Nadia", config.chooseableEventPartner)
    imgui.spacing()

    changed, config.equalChanceToJoinQuest = imgui.checkbox("An equal chance to join the quest", config.equalChanceToJoinQuest)  
    imgui.end_disabled()
    imgui.new_line()
imgui.tree_pop() end)