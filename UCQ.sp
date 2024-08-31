
#define DEBUG 0

#define PLUGIN_NAME           "Ullapool Caber QoL Plugin"
#define PLUGIN_AUTHOR         "Niko Oneshot Real"
#define PLUGIN_DESCRIPTION    "Some QoL things for the Ullapool Caber"
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#pragma semicolon 1


public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
};

ConVar cvar_rate;
ConVar cvar_ammosmall;
ConVar cvar_ammomedium;
ConVar cvar_ammolarge;
ConVar cvar_hitpenalty;
float regen_time = 20.0;
char caber_cname[] = "tf_weapon_stickbomb";
int caber_id = 307;
KeyValues cabers;
Handle HudTextSync;

public void OnPluginStart()
{
    cabers = new KeyValues("cabers");
    cvar_rate = CreateConVar("sm_caber_regenrate", "1.0", "The rate at which the Caber regenerates.");
    cvar_ammosmall = CreateConVar("sm_caber_ammo_small", "0.25", "The amount small ammo packs refill of the regen bar.");
    cvar_ammomedium = CreateConVar("sm_caber_ammo_medium", "0.5", "The amount medium ammo packs refill of the regen bar.");
    cvar_ammolarge = CreateConVar("sm_caber_ammo_large", "1.0", "The amount large ammo packs refill of the regen bar.");
    cvar_hitpenalty = CreateConVar("sm_caber_hit_penalty", "0.1", "The amount of charge a broken caber loses when hitting someone.");
    AutoExecConfig(true, "plugin_ucq");

    float rate = GetConVarFloat(cvar_rate);
    if (rate != 0.0) {
        PrintToServer("[UCQ] Regen time is %.2fs", regen_time / GetConVarFloat(cvar_rate));
    } else {
        PrintToServer("[UCQ] Auto-regen is disabled.");
    }
    HudTextSync = CreateHudSynchronizer();

    HookEvent("item_pickup", Event_item_pickup);
    HookEvent("player_hurt", Event_player_hurt);

    RegAdminCmd("sm_caber_give", Command_Givecaber, ADMFLAG_SLAY);
    RegAdminCmd("sm_caber_check", Command_Checkcaber, ADMFLAG_SLAY);
    RegAdminCmd("sm_caber_fix", Command_Uncaber, ADMFLAG_SLAY);
    PrintToServer("[UCQ] Ullapool Caber QoL Plugin has loaded.");
}


public void OnMapStart() {
    CreateTimer(1.0, CaberTimer, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    HookEntityOutput("item_ammopack_large", "OnCacheInteraction", Caber_Refill);
    HookEntityOutput("item_ammopack_medium", "OnCacheInteraction", Caber_Refill);
    HookEntityOutput("item_ammopack_small", "OnCacheInteraction", Caber_Refill);
}

// i HATED this part. remind me to never mess with ammo packs again.
public void Caber_Refill(const char[] output, int caller, int client, float delay) {
    if(!isUsingCaber(client)) {
        return;
    }
    if(!isCaberBroken(client)) {
        return;
    }
    char cName[32];
    GetEntityClassname(caller, cName, sizeof(cName));
    #if DEBUG == 1
    PrintToChat(client, "%d | %s | %s | %.2f", client, output, cName, delay);
    #endif

    if(strcmp(cName,"item_ammopack_large") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammolarge));
        }
    }
    if(strcmp(cName,"item_ammopack_medium") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammomedium));
        }
    }
    if(strcmp(cName,"item_ammopack_small") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammosmall));
        }
    }


    float position[3];
    GetEntPropVector(caller, Prop_Send, "m_vecOrigin", position);
    DataPack dp = CreateDataPack();
    char cId[8];
    IntToString(caller, cId, sizeof(cId));
    WritePackString(dp, cId);
    WritePackFloat(dp, position[0]);
    WritePackFloat(dp, position[1]);
    WritePackFloat(dp, position[2]);
    WritePackString(dp, cName);
    CreateTimer(10.0, RespawnPack, dp, TIMER_FLAG_NO_MAPCHANGE);
    position[1] = 0.0;
    TeleportEntity(caller, position);
}

Action RespawnPack(Handle timer, DataPack dp) {
    #if DEBUG == 1
    PrintHintTextToAll("Respawning pack...");
    #endif
    ResetPack(dp);
    char cId[8];
    ReadPackString(dp, cId, sizeof(cId));
    int caller = StringToInt(cId);
    float X = ReadPackFloat(dp);
    float Y = ReadPackFloat(dp);
    float Z = ReadPackFloat(dp);
    char cName[32];
    ReadPackString(dp, cName, sizeof(cName));
    
    float pos[3];
    pos[0] = X;
    pos[1] = Y;
    pos[2] = Z;

    TeleportEntity(caller, pos);
    CloseHandle(dp);
    return Plugin_Handled;
}

Action CaberTimer(Handle timer) {
    for(int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) {
            if(isUsingCaber(client)) {
                if (isCaberBroken(client) != 0) {
                    addCaberCharge(client, GetConVarFloat(cvar_rate) / regen_time);
                } else {
                    setCaberCharge(client, 0.0, false);
                }
            }
        }
    }  
    return Plugin_Continue;
}

public Action Event_player_hurt(Event event, const char[] name, bool dontBroadcast) {
    int attacker = event.GetInt("attacker");
    if (attacker == 0 || attacker == event.GetInt("userid")) {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(attacker);

    if (isUsingCaber(client) && isCaberBroken(client) && getCaberCharge(client) != -87.71) {
        addCaberCharge(client, GetConVarFloat(cvar_hitpenalty) * -1.0);
    }
    return Plugin_Continue;
}


public void Event_item_pickup(Event event, const char[] name, bool dontBroadcast) {
    char i[32];
    event.GetString("item", i, sizeof(i));
    
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    #if DEBUG == 1
    PrintHintText(client, "Picked up %s!", i);
    #endif

    if(strcmp(i,"ammopack_large") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammolarge));
        }
    }

    if(strcmp(i,"ammopack_medium") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammomedium));
        }
    }

    if(strcmp(i,"ammopack_small") == 0) {
        if (isUsingCaber(client)) {
            addCaberCharge(client, GetConVarFloat(cvar_ammosmall));
        }
    }

}

// does not validate caber usage!
public float getCaberCharge(int client) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    char caberid[32];
    IntToString(caberitem, caberid, sizeof(caberid));
    return cabers.GetFloat(caberid, -87.71);
}

// does not validate caber usage!
public void addCaberCharge(int client, float amount) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    char caberid[32];
    IntToString(caberitem, caberid, sizeof(caberid));
    cabers.SetFloat(caberid, getCaberCharge(client) + amount);

    SetHudTextParams(-1.0, 0.7, 5.0, 255, 255, 255, 255);
    if(getCaberCharge(client) >= 1.0) {
        fixCaber(client);
        cabers.DeleteKey(caberid); // i'd rather not leak my memory, thank you.
        ShowSyncHudText(client, HudTextSync, "Caber is repaired!");
        return;
    } else if(getCaberCharge(client) < 0.0) {
        cabers.SetFloat(caberid, 0.0);
    }
    ShowSyncHudText(client, HudTextSync, "Caber is at %.0f% charge.", getCaberCharge(client) * 100);
}

public void setCaberCharge(int client, float amount, bool showHudTextOnRepair) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    char caberid[32];
    IntToString(caberitem, caberid, sizeof(caberid));
    cabers.SetFloat(caberid, amount);
    if(getCaberCharge(client) >= 1.0) {
        fixCaber(client);
        cabers.DeleteKey(caberid); // i'd rather not leak my memory, thank you.
        if (showHudTextOnRepair == true) {
            SetHudTextParams(-1.0, 0.7, 5.0, 255, 255, 255, 255);
            ShowSyncHudText(client, HudTextSync, "Caber is repaired!");
        }
        return;
    } else if (getCaberCharge(client) == 0.0) {
        cabers.DeleteKey(caberid);
    }
}

public bool isUsingCaber(int client) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    if(!IsValidEntity(caberitem)) {
        char caberid[32];
        IntToString(caberitem, caberid, sizeof(caberid));
        if(cabers.GetFloat(caberid, -87.71) != -87.71) {
            cabers.DeleteKey(caberid); // nuking broken or invalid caber IDs
        }
        return false;
    }
    char entclass[64];
    GetEntityNetClass(caberitem, entclass, sizeof(entclass));	
    int weap_id = GetEntData(caberitem, FindSendPropInfo(entclass, "m_iItemDefinitionIndex"));
    if(weap_id == caber_id) {
        return true;
    }
    return false;
}

// returns 0 if its ok. anything else means its broken.
public int isCaberBroken(int client) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    return GetEntProp(caberitem, Prop_Send, "m_iDetonated");
}

public Action Command_Checkcaber(int client, int args) {
    if(isUsingCaber(client)) {
        if (isCaberBroken(client) == 0) {
            PrintToChat(client, "Yup, that caber is fine.");
        } else {
            PrintToChat(client, "Yup, that caber is totally wrecked.");
        }
        return Plugin_Handled;
    }
    PrintToChat(client, "That is not a caber.");
    return Plugin_Handled;
}

// NOTE: Assumes client has a caber. Do checks before calling this function!
public void fixCaber(int client) {
    int caberitem = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
    SetEntProp(caberitem, Prop_Send, "m_bBroken", 0);
    SetEntProp(caberitem, Prop_Send, "m_iDetonated", 0);
}

public Action Command_Uncaber(int client, int args) {
    if(isUsingCaber(client)) {
        setCaberCharge(client, 1.0, true);
        return Plugin_Handled;
    }
    PrintToChat(client, "That is not a caber.");
    return Plugin_Handled;
}

public void GiveCaber(int client) {
    int caberitem = CreateEntityByName(caber_cname);

    // from the gimme plugin: https://forums.alliedmods.net/showthread.php?t=335644
    char entclass[64];
    GetEntityNetClass(caberitem, entclass, sizeof(entclass));	
    SetEntData(caberitem, FindSendPropInfo(entclass, "m_iItemDefinitionIndex"), caber_id);
    SetEntData(caberitem, FindSendPropInfo(entclass, "m_bInitialized"), 1);
    SetEntData(caberitem, FindSendPropInfo(entclass, "m_iEntityLevel"), 1);
    SetEntData(caberitem, FindSendPropInfo(entclass, "m_iEntityQuality"), 0);
    SetEntProp(caberitem, Prop_Send, "m_bValidatedAttachedEntity", 1);
    
    SetEntProp(caberitem, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
    SetEntPropEnt(caberitem, Prop_Send, "m_hOwnerEntity", client);
    SetEntData(caberitem, FindSendPropInfo(entclass, "m_iEntityLevel"), 1);

    DispatchSpawn(caberitem);
    TF2_RemoveWeaponSlot(client, 2);
    EquipPlayerWeapon(client,caberitem);
}

public Action Command_Givecaber(int client, int args)
{
    GiveCaber(client);
    return Plugin_Handled;
}
