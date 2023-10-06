#pragma semicolon 1
#include <sourcemod>
#include <string>
#include <sdktools>
#include <timers>
#define PLUGIN_VERSION "1.1.1"


/******
* TODO
*******
* - Расширьте рюкзак, чтобы включить слот 0 и слот 1 (основной и дополнительный)
* - Добавить ограничения по весу/количеству
* - Добавлено замедление нагрузки
* - Добавлены невосстановимые предметы после смерти
* - Добавлены cvars для управления плагином
* - Улучшена логика пополнения запасов предметов
* - Улучшить логику использования таблеток
* - Улучшить логику использования гранат
* - Добавить команду Drop
* - Добавить команду просмотра администратора
* - Добавить админ дать команду
* - Сделать L4D1 совместимым
******************
* Version History
******************
* 1.0
*  - Первый выпуск
* 1.1
*  - Добавлены команды быстрого выбора.
*/

//Инициализировать переменные

/* Идентификатор игрока — используется для переноса пакетов между картами в кооперативе. */

new Handle:hGame_Mode = INVALID_HANDLE;
new pack_store[MAXPLAYERS+1][9];
new iGame_Mode;

/* Содержимое рюкзака — хранит количество каждого предмета в своем рюкзаке. */
new pack_mols[MAXPLAYERS+1];							//Molotovs
new pack_pipes[MAXPLAYERS+1];							//Pipebombs
new pack_biles[MAXPLAYERS+1];							//Bile Bombs
new pack_kits[MAXPLAYERS+1];							//First Aid Kits
new pack_defibs[MAXPLAYERS+1];							//Defibrillator
new pack_firepacks[MAXPLAYERS+1];						//Incendiary Ammo Packs
new pack_explodepacks[MAXPLAYERS+1];					//Explosive Ammo Packs
new pack_pills[MAXPLAYERS+1];							//Pain Pills
new pack_adrens[MAXPLAYERS+1];							//Adrenaline

/* Solt Selections — сохраняет текущий выбор предмета для каждого слота. */
new pack_slot2[MAXPLAYERS+1];							//Grenade Selection
new pack_slot3[MAXPLAYERS+1];							//Kit Selection
new pack_slot4[MAXPLAYERS+1];							//Pills Selection

/* Разное Исправления — используется для исправления различных проблем/проблем с событиями. */
new bool:item_pickup[MAXPLAYERS+1];						//Set in Event_ItemPickup to skip Event_PlayerUse
new item_drop[MAXPLAYERS+1];							//Set in Event_WeaponDrop to prevent items getting "reused"
new bool:pills_used[MAXPLAYERS+1];						//Set in Event_PillsUsed to skip Event_WeaponDrop
new pills_owner[MAXPLAYERS+1];							//Set in Event_WeaponDrop to handle passing pills/adren
new Handle:nadetimer[MAXPLAYERS+1] = INVALID_HANDLE;	//Timer to resupply players after they use grenades
new bool:roundFailed = false;

public Plugin:myinfo = {
	name = "Backpack",
	author = "Web2Root",
	description = "Allows you to carry extra items in your backpack.",
	version = PLUGIN_VERSION,
	url = ""
}

public OnPluginStart() {
	decl String:game[12];
	new Handle:pack_version = INVALID_HANDLE;
	decl String:sGame_Mode[32];
	
	GetGameFolderName(game, sizeof(game));
	if (StrContains(game, "left4dead") == -1) SetFailState("Backpack will only work with Left 4 Dead!");
	
	/* Game Mode Hook */
	hGame_Mode = FindConVar("mp_gamemode");
	HookConVarChange(hGame_Mode, ConVarChange_GameMode);
	
	GetConVarString(hGame_Mode, sGame_Mode, sizeof(sGame_Mode));
	
	if(StrContains(sGame_Mode, "coop") != -1) {
		iGame_Mode = 1;
	}
	if(StrContains(sGame_Mode, "realism") != -1) {
		iGame_Mode = 2;
	}
	if(StrContains(sGame_Mode, "versus") != -1) {
		iGame_Mode = 3;
	}
	if(StrContains(sGame_Mode, "scavenge") != -1) {
		iGame_Mode = 4;
	}
	if(StrContains(sGame_Mode, "teamversus") != -1) {
		iGame_Mode = 5;
	}
	if(StrContains(sGame_Mode, "teamscavenge") != -1) {
		iGame_Mode = 6;
	}
	if(StrContains(sGame_Mode, "survival") != -1) {
		iGame_Mode = 7;
	}
	
	
	RegConsoleCmd("pack", PackMenu);
	RegAdminCmd("pack_view", AdminViewMenu, ADMFLAG_GENERIC, "Allows admins to view player backpacks");
	
	/* Перехватчики событий */
	HookEvent("round_start", Event_RoundStart); 		//Используется для сброса всех рюкзаков в начале раунда.
	HookEvent("item_pickup", Event_ItemPickup);			//Используется для захвата предметов
	HookEvent("player_use", Event_PlayerUse); 			//Используется для сбора дополнительных предметов
	HookEvent("weapon_drop", Event_WeaponDrop);			//Используется для ловли предметов
	HookEvent("player_death", Event_PlayerDeath); 		//Используется для выпадения предметов игрока после смерти
	HookEvent("round_freeze_end", Event_RoundEnd);
	HookEvent("mission_lost", Event_MissionLost);
	HookEvent("finale_win", Event_FinaleWin);
	
	/* События использования предметов */
	HookEvent("heal_success", Event_KitUsed); 			//Используется, чтобы поймать, когда кто-то использует комплект
	HookEvent("defibrillator_used", Event_KitUsed); 	//Используется, чтобы поймать, когда кто-то использует defib
	HookEvent("upgrade_pack_used",Event_KitUsed); 		//Используется, чтобы поймать, когда кто-то использует ammo pack
	HookEvent("pills_used", Event_PillsUsed); 			//Используется, чтобы поймать, когда кто-то использует pills
	HookEvent("adrenaline_used", Event_PillsUsed); 		//Используется, чтобы поймать, когда кто-то использует adrenaline
	
	/* Смена рюкзака */
	HookEvent("bot_player_replace", Event_BotToPlayer); //Используется для передачи пакета уходящего бота присоединяющемуся игроку.
	HookEvent("player_bot_replace", Event_PlayerToBot); //Используется для передачи набора уходящего игрока присоединившемуся боту.
	
	pack_version = CreateConVar("l4d_backpack_version", PLUGIN_VERSION, "Backpack plugin version.", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	CreateConVar("l4d_backpack_start_mols", "0", "Starting Molotovs", _, true, 0.0);
	CreateConVar("l4d_backpack_start_pipes", "0", "Starting Pipe Bombs", _, true, 0.0);
	CreateConVar("l4d_backpack_start_biles", "0", "Starting Bile Jars", _, true, 0.0);
	CreateConVar("l4d_backpack_start_kits", "0", "Starting Medkits", _, true, 0.0);
	CreateConVar("l4d_backpack_start_defibs", "0", "Starting Defibs", _, true, 0.0);
	CreateConVar("l4d_backpack_start_firepacks", "0", "Starting Fire Ammo Packs", _, true, 0.0);
	CreateConVar("l4d_backpack_start_explodepacks", "0", "Starting Explode Ammo Packs", _, true, 0.0);
	CreateConVar("l4d_backpack_start_pills", "0", "Starting Pills", _, true, 0.0);
	CreateConVar("l4d_backpack_start_adrens", "0", "Starting Adrenalines", _, true, 0.0);
	CreateConVar("l4d_backpack_help_mode", "1", "Controls how joining help message is displayed.");
	
	AutoExecConfig(true, "l4d_backpack");
	
	SetConVarString(pack_version, PLUGIN_VERSION);
	
	ResetBackpack(0, 1);
	
}

public OnClientPutInServer(client) {
	if(GetConVarInt(FindConVar("l4d_backpack_help_mode")) != 0) {
		CreateTimer(60.0, Timer_WelcomeMessage, client);
	}
}

public Action:Timer_WelcomeMessage(Handle:timer, any:client) {
	new String:help[] = "\x01[SM] Выжившие могут носить в рюкзаке дополнительные предметы..\n\x01[SM] Чтобы открыть рюкзак, введите \x04!pack\x01 в чат.\n\x01[SM] You can quick-select items by typing \x04!pack <1-9>\x01 in chat.";
	if (IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client)) {
		switch (GetConVarInt(FindConVar("l4d_backpack_help_mode"))) {
			case 1: {
				PrintToChat(client, help);
			}
			case 2: {
				PrintHintText(client, help);
			}
			case 3: {
				PrintCenterText(client, help);
			}
			default: {
				PrintToChat(client, help);
			}
		}
	}
}

public ConVarChange_GameMode(Handle:cvar, const String:oldVal[], const String:newVal[]) {
	decl String:sGame_Mode[32];
	
	GetConVarString(hGame_Mode, sGame_Mode, sizeof(sGame_Mode));
	
	if(StrContains(sGame_Mode, "coop") != -1) {
		iGame_Mode = 1;
	}
	if(StrContains(sGame_Mode, "realism") != -1) {
		iGame_Mode = 2;
	}
	if(StrContains(sGame_Mode, "versus") != -1) {
		iGame_Mode = 3;
	}
	if(StrContains(sGame_Mode, "scavenge") != -1) {
		iGame_Mode = 4;
	}
	if(StrContains(sGame_Mode, "teamversus") != -1) {
		iGame_Mode = 5;
	}
	if(StrContains(sGame_Mode, "teamscavenge") != -1) {
		iGame_Mode = 6;
	}
	if(StrContains(sGame_Mode, "survival") != -1) {
		iGame_Mode = 7;
	}
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	new i;
	
	if(iGame_Mode == 1 || iGame_Mode == 2) {
		if(roundFailed == true) {
			for(i = 1; i <= MAXPLAYERS; i++) {
				pack_mols[i] = pack_store[i][0];
				pack_pipes[i] = pack_store[i][1];
				pack_biles[i] = pack_store[i][2];
				pack_kits[i] = pack_store[i][3];
				pack_defibs[i] = pack_store[i][4];
				pack_firepacks[i] = pack_store[i][5];
				pack_explodepacks[i] = pack_store[i][6];
				pack_pills[i] = pack_store[i][7];
				pack_adrens[i] = pack_store[i][8];
			}
		}
		roundFailed = false;
		
		return Plugin_Continue;
	}
	ResetBackpack(0, 1);
	return Plugin_Continue;
}

public Action:Event_ItemPickup(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	decl String:item[64];
	GetEventString(event, "item", item, sizeof(item));
	item_drop[client] = 0;
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called ItemPickup. Item = %s", client, item);
	#endif
	if(StrContains(item, "molotov", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			KillTimer(nadetimer[client]);
			nadetimer[client] = INVALID_HANDLE;
			GrenadeRemove(client);
		}
		pack_slot2[client] = 1;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot2 to %d", client, pack_slot2[client]);
		#endif
	}
	if(StrContains(item, "pipe_bomb", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			KillTimer(nadetimer[client]);
			nadetimer[client] = INVALID_HANDLE;
			GrenadeRemove(client);
		}
		pack_slot2[client] = 2;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot2 to %d", client, pack_slot2[client]);
		#endif
	}
	if(StrContains(item, "vomitjar", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			KillTimer(nadetimer[client]);
			nadetimer[client] = INVALID_HANDLE;
			GrenadeRemove(client);
		}
		pack_slot2[client] = 3;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot2 to %d", client, pack_slot2[client]);
		#endif
	}
	if(StrContains(item, "first_aid_kit", false) != -1) {
		pack_slot3[client] = 1;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot3 to %d", client, pack_slot3[client]);
		#endif
	}
	if(StrContains(item, "defibrillator", false) != -1) {
		pack_slot3[client] = 2;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot3 to %d", client, pack_slot3[client]);
		#endif
	}
	if(StrContains(item, "upgradepack_incendiary", false) != -1) {
		pack_slot3[client] = 3;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot3 to %d", client, pack_slot3[client]);
		#endif
	}
	if(StrContains(item, "upgradepack_explosive", false) != -1) {
		pack_slot3[client] = 4;
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot3 to %d", client, pack_slot3[client]);
		#endif
	}
	if(StrContains(item, "pain_pills", false) != -1) {
		pack_slot4[client] = 1;
		if(pills_owner[client] != 0) {
			CreateTimer(1.0, GivePills, pills_owner[client]);
			pills_owner[client] = 0;
		}
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot4 to %d", client, pack_slot4[client]);
		#endif
	}
	if(StrContains(item, "adrenaline", false) != -1) {
		pack_slot4[client] = 2;
		if(pills_owner[client] != 0) {
			CreateTimer(1.0, GivePills, pills_owner[client]);
			pills_owner[client] = 0;
		}
		#if defined DEBUG
		PrintToChatAll("[DEBUG] %d changed slot4 to %d", client, pack_slot4[client]);
		#endif
	}
	item_pickup[client] = true;
	return Plugin_Continue;
}

public Action:Event_PlayerUse(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	decl String:item[64];
	new targetid;
	if(item_pickup[client]) {
		item_pickup[client] = false;
		return Plugin_Continue;
	}
	targetid = GetEventInt(event, "targetid");
	GetEdictClassname(targetid, item, sizeof(item));
	if(StrContains(item, "molotov", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_mols[client] += 1;
	}
	if(StrContains(item, "pipe_bomb", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_pipes[client] += 1;
	}
	if(StrContains(item, "vomitjar", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_biles[client] += 1;
	}
	if(StrContains(item, "first_aid_kit", false) != -1) {
		pack_slot3[client] = 1; //Ловит заранее заданные комплекты
		AcceptEntityInput(targetid, "Kill");
		pack_kits[client] += 1;
	}
	if(StrContains(item, "defibrillator", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_defibs[client] += 1;
	}
	if(StrContains(item, "upgradepack_incendiary", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_firepacks[client] += 1;
	}
	if(StrContains(item, "upgradepack_explosive", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_explodepacks[client] += 1;
	}
	if(StrContains(item, "pain_pills", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_pills[client] += 1;
	}
	if(StrContains(item, "adrenaline", false) != -1) {
		AcceptEntityInput(targetid, "Kill");
		pack_adrens[client] += 1;
	}
	
	return Plugin_Continue;
}

public Action:Event_WeaponDrop(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	new weapon = GetEventInt(event, "propid");
	decl String:item[64];
	GetEventString(event, "item", item, sizeof(item));
	
	if(client <= 0) {
		return Plugin_Continue;
	}
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d dropped %d - %s", client, weapon, item);
	#endif
	if(StrContains(item, "molotov", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			TriggerTimer(nadetimer[client]);
		}
		nadetimer[client] = CreateTimer(0.5, GiveGrenade, client);
	}
	if(StrContains(item, "pipe_bomb", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			TriggerTimer(nadetimer[client]);
		}
		nadetimer[client] = CreateTimer(0.5, GiveGrenade, client);
	}
	if(StrContains(item, "vomitjar", false) != -1) {
		if(nadetimer[client] != INVALID_HANDLE) {
			TriggerTimer(nadetimer[client]);
		}
		nadetimer[client] = CreateTimer(0.5, GiveGrenade, client);
	}
	if(StrContains(item, "first_aid_kit", false) != -1) {
		AcceptEntityInput(weapon, "Kill");
		pack_kits[client] += 1;
		item_drop[client] = 4;
	}
	if(StrContains(item, "defibrillator", false) != -1) {
		AcceptEntityInput(weapon, "Kill");
		pack_defibs[client] += 1;
		item_drop[client] = 5;
	}
	if(StrContains(item, "upgradepack_incendiary", false) != -1) {
		AcceptEntityInput(weapon, "Kill");
		pack_firepacks[client] += 1;
		item_drop[client] = 6;
	}
	if(StrContains(item, "upgradepack_explosive", false) != -1) {
		AcceptEntityInput(weapon, "Kill");
		pack_explodepacks[client] += 1;
		item_drop[client] = 7;
	}
	if(pills_used[client]) {
		pills_used[client] = false;
		return Plugin_Continue;
	}	
	if(StrContains(item, "pain_pills", false) != -1) {
		new target = GetClientAimTarget(client);
		if(target < 0) {
			AcceptEntityInput(weapon, "Kill");
			pack_pills[client] += 1;
			item_drop[client] = 8;
			//CreateTimer(0.5, GivePills, client);
			return Plugin_Continue;
		}
		pills_owner[target] = client;
	}
	if(StrContains(item, "adrenaline", false) != -1) {
		new target = GetClientAimTarget(client);
		if(target < 0) {
			AcceptEntityInput(weapon, "Kill");
			pack_adrens[client] += 1;
			item_drop[client] = 9;
			//CreateTimer(0.5, GivePills, client);
			return Plugin_Continue;
		}
		pills_owner[target] = client;
	}
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	new Float:victim[3];
	victim[0] = GetEventFloat(event, "victim_x");
	victim[1] = GetEventFloat(event, "victim_y");
	victim[2] = GetEventFloat(event, "victim_z");
	if(client <= 0) {
		return Plugin_Continue;
	}
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called PlayerDeath.", client);
	#endif
	if(GetClientTeam(client) == 2) {
		SpawnItem(victim, "weapon_molotov", pack_mols[client]);
		SpawnItem(victim, "weapon_pipe_bomb", pack_pipes[client]);
		SpawnItem(victim, "weapon_vomitjar", pack_biles[client]);
		SpawnItem(victim, "weapon_first_aid_kit", pack_kits[client]);
		SpawnItem(victim, "weapon_defibrillator", pack_defibs[client]);
		SpawnItem(victim, "weapon_upgradepack_incendiary", pack_firepacks[client]);
		SpawnItem(victim, "weapon_upgradepack_explosive", pack_explodepacks[client]);
		SpawnItem(victim, "weapon_pain_pills", pack_pills[client]);
		SpawnItem(victim, "weapon_adrenaline", pack_adrens[client]);
	}
	ResetBackpack(client, 0);
	
	return Plugin_Continue;
}

public SpawnItem(const Float:origin[3], const String:item[], const amount) {
	new i;
	new entity;
	for(i = 1; i <= amount; i++) {
		entity = CreateEntityByName(item);
		if(entity == -1) {
			#if defined DEBUG
			PrintToChatAll("[DEBUG] Во время события PlayerDeath не удалось создать объект %s.", item);
			#endif
			break;
		}
		if(!DispatchSpawn(entity)) {
			#if defined DEBUG
			PrintToChatAll("[DEBUG] During event PlayerDeath, Entity %s failed to spawn.", item);
			#endif
			continue;
		}
		TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
		#if defined DEBUG
		PrintToChatAll("[DEBUG] During event PlayerDeath, Entity %s was successfully spawned at (%.2f, %.2f, %.2f).", item, origin[0], origin[1], origin[2]);
		#endif
	}
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	new i;
	
	if((iGame_Mode == 1 || iGame_Mode == 2) && roundFailed == false) {
		for(i = 1; i <= MAXPLAYERS; i++) {
			pack_store[i][0] = pack_mols[i];
			pack_store[i][1] = pack_pipes[i];
			pack_store[i][2] = pack_biles[i];
			pack_store[i][3] = pack_kits[i];
			pack_store[i][4] = pack_defibs[i];
			pack_store[i][5] = pack_firepacks[i];
			pack_store[i][6] = pack_explodepacks[i];
			pack_store[i][7] = pack_pills[i];
			pack_store[i][8] = pack_adrens[i];
		}
	}
	return Plugin_Continue;
}

public Action:Event_FinaleWin(Handle:event, const String:name[], bool:dontBroadcast) {
	new i;
	
	if(iGame_Mode == 1 || iGame_Mode == 2) {
		ResetBackpack(0, 1);
		for(i = 1; i <= MAXPLAYERS; i++) {
			pack_store[i][0] = pack_mols[i];
			pack_store[i][1] = pack_pipes[i];
			pack_store[i][2] = pack_biles[i];
			pack_store[i][3] = pack_kits[i];
			pack_store[i][4] = pack_defibs[i];
			pack_store[i][5] = pack_firepacks[i];
			pack_store[i][6] = pack_explodepacks[i];
			pack_store[i][7] = pack_pills[i];
			pack_store[i][8] = pack_adrens[i];
		}
	}
	
	roundFailed = false;
	
	return Plugin_Continue;
}

public Action:Event_MissionLost(Handle:event, const String:name[], bool:dontBroadcast) {
	if(iGame_Mode == 1 || iGame_Mode == 2) {
		roundFailed = true;
	}
	return Plugin_Continue;
}

public GrenadeRemove(any:client) {
	new Float:position[3]; //Текущее положение объекта
	decl String:grenade[128]; //Название сброшенной гранаты
	new Float:eyepos[3]; //Положение глаз клиента
	new entity = -1; //Сохраняет ближайшую гранату / указ
	new Float:distance = 10000.0; //Сохраняет векторное расстояние до ближайшей гранаты
	new Float:dist; //Сохраняет векторное расстояние текущей гранаты
	new slot2 = pack_slot2[client];
	
	GetClientAbsOrigin(client, eyepos);
	switch (slot2) {
		case 1: {
			strcopy(grenade, sizeof(grenade), "weapon_molotov");
		}
		case 2: {
			strcopy(grenade, sizeof(grenade), "weapon_pipe_bomb");
		}
		case 3: {
			strcopy(grenade, sizeof(grenade), "weapon_vomitjar");
		}
		default: {
			#if defined DEBUG
			PrintToChatAll("[DEBUG] Exited RemoveGrenade because %d's slot2 = %d", client, slot2);
			#endif
			/*
			* Если это всплывает, значит что-то вероятно
			* пошло не так или кто-то сделал какую ту ухню, чего не должен был делать.
			* Здесь нечего делать, кроме входа и возврата.
			*/
			return;
		}
	}
	for(new i = 0; i <= GetEntityCount(); i++) {
		if(IsValidEntity(i)) {
			decl String:EdictName[128];
			GetEdictClassname(i, EdictName, sizeof(EdictName));
			if(StrContains(EdictName, grenade) != -1) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] Found %d - %s while looking for last grenade.", i, EdictName);
				#endif
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", position);
				#if defined DEBUG
				PrintToChatAll("[DEBUG] Grenade position (%.2f, %.2f, %.2f) Eye position (%.2f, %.2f, %.2f)", position[0], position[1], position[2], eyepos[0], eyepos[1], eyepos[2]);
				#endif
				dist = FloatAbs(GetVectorDistance(eyepos, position));
				#if defined DEBUG
				PrintToChatAll("[DEBUG] Distance = %f. Shortest Distance = %f", dist, distance);
				#endif
				if((dist < distance) && (dist != 50.0)) { //Граната найденная на расстоянии в 50 единицах от вас — это та которую вы держите.
					distance = dist;
					entity = i;
				}
			}
		}
	}
	if(distance == 10000.0 || entity <= 0) {
		//Последняя граната почему-то не найдена
		#if defined DEBUG
		PrintToChatAll("[DEBUG] Couldn't find grenade %s for %d", grenade, client);
		#endif
		return;
	}
	#if defined DEBUG
	PrintToChatAll("[DEBUG] Removing Grenade %s at %f distance from %d", grenade, distance, client);
	#endif
	AcceptEntityInput(entity, "Kill");
	switch (slot2) {
		case 1: {
			pack_mols[client] += 1;
		}
		case 2: {
			pack_pipes[client] += 1;
		}
		case 3: {
			pack_biles[client] += 1;
		}
	}
	return;
}

public Action:GiveGrenade(Handle:timer, any:client) {
	if(client <= 0 || !IsClientInGame(client)) {
		return;
	}
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called GiveGrenade.", client);
	#endif
	nadetimer[client] = INVALID_HANDLE;
	new flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	new entity;
	entity = GetPlayerWeaponSlot(client, 2);
	if(entity <= -1) {
		switch (pack_slot2[client]) {
			case 1: {
				if(pack_mols[client] > 0) {
					FakeClientCommand(client, "give molotov");
					pack_mols[client] -= 1;
				} else {
					pack_slot2[client] = 0;
				}
			}
			case 2: {
				if(pack_pipes[client] > 0) {
					FakeClientCommand(client, "give pipe_bomb");
					pack_pipes[client] -= 1;
				} else {
					pack_slot2[client] = 0;
				}
			}
			case 3: {
				if(pack_biles[client] > 0) {
					FakeClientCommand(client, "give vomitjar");
					pack_biles[client] -= 1;
				} else {
					pack_slot2[client] = 0;
				}
			}
		}
	}
	SetCommandFlags("give", flags|FCVAR_CHEAT);
}

public Action:Event_KitUsed(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	new flags = GetCommandFlags("give");
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called KitUsed.", client);
	#endif
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	new entity;
	entity = GetPlayerWeaponSlot(client, 3);
	if(entity <= -1) {
		switch (pack_slot3[client]) {
			case 1: {
				if(item_drop[client] == 4) {
					pack_kits[client] -= 1;
				}
				if(pack_kits[client] > 0) {
					FakeClientCommand(client, "give first_aid_kit");
					pack_kits[client] -= 1;
				} else {
					pack_slot3[client] = 0;
				}
			}
			case 2: {
				if(item_drop[client] == 5) {
					pack_defibs[client] -= 1;
				}
				if(pack_defibs[client] > 0) {
					FakeClientCommand(client, "give defibrillator");
					pack_defibs[client] -= 1;
				} else {
					pack_slot3[client] = 0;
				}
			}
			case 3: {
				if(item_drop[client] == 6) {
					pack_firepacks[client] -= 1;
				}
				if(pack_firepacks[client] > 0) {
					FakeClientCommand(client, "give upgradepack_incendiary");
					pack_firepacks[client] -= 1;
				} else {
					pack_slot3[client] = 0;
				}
			}
			case 4: {
				if(item_drop[client] == 7) {
					pack_explodepacks[client] -= 1;
				}
				if(pack_explodepacks[client] > 0) {
					FakeClientCommand(client, "give upgradepack_explosive");
					pack_explodepacks[client] -= 1;
				} else {
					pack_slot3[client] = 0;
				}
			}
		}
		item_drop[client] = 0;
	}
	SetCommandFlags("give", flags|FCVAR_CHEAT);
	return Plugin_Continue;
}

public Action:Event_PillsUsed(Handle:event, const String:name[], bool:dontBroadcast) {
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);
	CreateTimer(1.0, GivePills, client);
	pills_used[client] = true;
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called PillsUsed.", client);
	#endif
	return Plugin_Continue;
}

public Action:GivePills(Handle:timer, any:client) {
	if(client <= 0 || !IsClientInGame(client)) {
		return;
	}
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d called GivePills.", client);
	#endif
	new flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	new entity;
	entity = GetPlayerWeaponSlot(client, 4);
	if(entity <= -1) {
		switch (pack_slot4[client]) {
			case 1: {
				if(item_drop[client] == 8) {
					pack_pills[client] -= 1;
				}
				if(pack_pills[client] > 0) {
					FakeClientCommand(client, "give pain_pills");
					pack_pills[client] -= 1;
				} else {
					pack_slot4[client] = 0;
				}
			}
			case 2: {
				if(item_drop[client] == 9) {
					pack_adrens[client] -= 1;
				}
				if(pack_adrens[client] > 0) {
					FakeClientCommand(client, "give adrenaline");
					pack_adrens[client] -= 1;
				} else {
					pack_slot4[client] = 0;
				}
			}
		}
	}
	SetCommandFlags("give", flags|FCVAR_CHEAT);
}

public Action:Event_BotToPlayer(Handle:event, const String:name[], bool:dontBroadcast) {
	new bot = GetEventInt(event, "bot");
	new client = GetClientOfUserId(bot);
	new player = GetEventInt(event, "player");
	new client2 = GetClientOfUserId(player);
	
	#if defined DEBUG
	PrintToChatAll("[DEBUG] Bot %d handed control to %d.", client, client2);
	#endif
	
	/* Переключение */
	pack_mols[client2] += pack_mols[client];
	pack_pipes[client2] += pack_pipes[client];
	pack_biles[client2] += pack_biles[client];
	pack_kits[client2] += pack_kits[client];
	pack_defibs[client2] += pack_defibs[client];
	pack_firepacks[client2] += pack_firepacks[client];
	pack_explodepacks[client2] += pack_explodepacks[client];
	pack_pills[client2] += pack_pills[client];
	pack_adrens[client2] += pack_adrens[client];
	pack_slot2[client2] = pack_slot2[client];
	pack_slot3[client2] = pack_slot3[client];
	pack_slot4[client2] = pack_slot4[client];
	item_drop[client2] = 0;
	pills_owner[client2] = 0;
	pills_used[client2] = false;
	item_pickup[client2] = false;
	
	/* Удалить старый */
	ResetBackpack(client, 0);
	
	if(iGame_Mode == 1 || iGame_Mode == 2) {
		pack_store[client2][0] += pack_store[client][0];
		pack_store[client2][1] += pack_store[client][1];
		pack_store[client2][2] += pack_store[client][2];
		pack_store[client2][3] += pack_store[client][3];
		pack_store[client2][4] += pack_store[client][4];
		pack_store[client2][5] += pack_store[client][5];
		pack_store[client2][6] += pack_store[client][6];
		pack_store[client2][7] += pack_store[client][7];
		pack_store[client2][8] += pack_store[client][8];
		
		pack_store[client][0] = 0;
		pack_store[client][1] = 0;
		pack_store[client][2] = 0;
		pack_store[client][3] = 0;
		pack_store[client][4] = 0;
		pack_store[client][5] = 0;
		pack_store[client][6] = 0;
		pack_store[client][7] = 0;
		pack_store[client][8] = 0;
		
	}
	
	return Plugin_Continue;
}


public Action:Event_PlayerToBot(Handle:event, const String:name[], bool:dontBroadcast) {
	new bot = GetEventInt(event, "bot");
	new client2 = GetClientOfUserId(bot);
	new player = GetEventInt(event, "player");
	new client = GetClientOfUserId(player);
	
	#if defined DEBUG
	PrintToChatAll("[DEBUG] %d handed control to Bot %d.", client, client2);
	#endif
	
	/* Переключение */
	pack_mols[client2] += pack_mols[client];
	pack_pipes[client2] += pack_pipes[client];
	pack_biles[client2] += pack_biles[client];
	pack_kits[client2] += pack_kits[client];
	pack_defibs[client2] += pack_defibs[client];
	pack_firepacks[client2] += pack_firepacks[client];
	pack_explodepacks[client2] += pack_explodepacks[client];
	pack_pills[client2] += pack_pills[client];
	pack_adrens[client2] += pack_adrens[client];
	pack_slot2[client2] = pack_slot2[client];
	pack_slot3[client2] = 1;
	pack_slot4[client2] = pack_slot4[client];
	item_drop[client2] = 0;
	pills_owner[client2] = pills_owner[client];
	pills_used[client2] = false;
	item_pickup[client2] = false;
	
	/* Remove Old */
	ResetBackpack(client, 0);
	
	if(iGame_Mode == 1 || iGame_Mode == 2) {
		pack_store[client2][0] += pack_store[client][0];
		pack_store[client2][1] += pack_store[client][1];
		pack_store[client2][2] += pack_store[client][2];
		pack_store[client2][3] += pack_store[client][3];
		pack_store[client2][4] += pack_store[client][4];
		pack_store[client2][5] += pack_store[client][5];
		pack_store[client2][6] += pack_store[client][6];
		pack_store[client2][7] += pack_store[client][7];
		pack_store[client2][8] += pack_store[client][8];
		
		pack_store[client][0] = 0;
		pack_store[client][1] = 0;
		pack_store[client][2] = 0;
		pack_store[client][3] = 0;
		pack_store[client][4] = 0;
		pack_store[client][5] = 0;
		pack_store[client][6] = 0;
		pack_store[client][7] = 0;
		pack_store[client][8] = 0;
	}
	
	return Plugin_Continue;
}

ResetBackpack(client = 0, reset = 1) {
	/*
	* Ценности клиента (Client)
	* Номер клиента для игрока которого вы хотите сбросить
	* 0 означает сброс всех
	*
	* Сбросить значения (Reset)
	* 0 означает опустошить пакет обратно в 0
	* 1 означает, что в пакете установлено начальное количество
	*/
	new mols;
	new pipes;
	new biles;
	new kits;
	new defibs;
	new firepacks;
	new explodepacks;
	new pills;
	new adrens;
	new i;
	
	if(reset == 1) {
		mols = GetConVarInt(FindConVar("l4d_backpack_start_mols"));
		pipes = GetConVarInt(FindConVar("l4d_backpack_start_pipes"));
		biles = GetConVarInt(FindConVar("l4d_backpack_start_biles"));
		kits = GetConVarInt(FindConVar("l4d_backpack_start_kits"));
		defibs = GetConVarInt(FindConVar("l4d_backpack_start_defibs"));
		firepacks = GetConVarInt(FindConVar("l4d_backpack_start_firepacks"));
		explodepacks = GetConVarInt(FindConVar("l4d_backpack_start_explodepacks"));
		pills = GetConVarInt(FindConVar("l4d_backpack_start_pills"));
		adrens = GetConVarInt(FindConVar("l4d_backpack_start_adrens"));
	}
	
	if(client != 0) {
		pack_mols[client] = mols;
		pack_pipes[client] = pipes;
		pack_biles[client] = biles;
		pack_kits[client] = kits;
		pack_defibs[client] = defibs;
		pack_firepacks[client] = firepacks;
		pack_explodepacks[client] = explodepacks;
		pack_pills[client] = pills;
		pack_adrens[client] = adrens;
		pack_slot2[client] = 0;
		pack_slot3[client] = 0;
		pack_slot4[client] = 0;
		item_drop[client] = 0;
		pills_owner[client] = 0;
		pills_used[client] = false;
		item_pickup[client] = false;
		nadetimer[client] = INVALID_HANDLE;
		
		return;
	}
	
	for(i = 0; i <= MAXPLAYERS; i++) {
		pack_mols[i] = mols;
		pack_pipes[i] = pipes;
		pack_biles[i] = biles;
		pack_kits[i] = kits;
		pack_defibs[i] = defibs;
		pack_firepacks[i] = firepacks;
		pack_explodepacks[i] = explodepacks;
		pack_pills[i] = pills;
		pack_adrens[i] = adrens;
		pack_slot2[i] = 0;
		pack_slot3[i] = 0;
		pack_slot4[i] = 0;
		item_drop[i] = 0;
		pills_owner[i] = 0;
		pills_used[i] = false;
		item_pickup[i] = false;
		nadetimer[i] = INVALID_HANDLE;
	}
	
	return;
}

/* Функции HUD */
public Action:PackMenu(client, arg) {
	decl String:sSlot[128];
	new iSlot;
	new entity;
	decl String:EdictName[128];
	new flags = GetCommandFlags("give");
	
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	
	if(IsClientInGame(client) && !IsFakeClient(client)) {
		if(GetClientTeam(client) == 2) {
			if(IsPlayerAlive(client)) {
				GetCmdArg(1, sSlot, sizeof(sSlot));
				iSlot = StringToInt(sSlot);
				switch(iSlot) {
					case 1, 2, 3: {
						entity = GetPlayerWeaponSlot(client, 2);
						if(entity > -1) {
							GetEdictClassname(entity, EdictName, sizeof(EdictName));
							if(StrContains(EdictName, "molotov", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_mols[client] += 1;
							}
							if(StrContains(EdictName, "pipe_bomb", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_pipes[client] += 1;
							}
							if(StrContains(EdictName, "vomitjar", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_biles[client] += 1;
							}
						}
						pack_slot2[client] = iSlot;
						switch (iSlot) {
							case 1: {
								if(pack_mols[client] > 0) {
									FakeClientCommand(client, "give molotov");
									pack_mols[client] -= 1;
								} else {
									pack_slot2[client] = 0;
								}
							}
							case 2: {
								if(pack_pipes[client] > 0) {
									FakeClientCommand(client, "give pipe_bomb");
									pack_pipes[client] -= 1;
								} else {
									pack_slot2[client] = 0;
								}
							}
							case 3: {
								if(pack_biles[client] > 0) {
									FakeClientCommand(client, "give vomitjar");
									pack_biles[client] -= 1;
								} else {
									pack_slot2[client] = 0;
								}
							}
						}
					}
					case 4, 5, 6, 7: {
						entity = GetPlayerWeaponSlot(client, 3);
						if(entity > -1) {
							GetEdictClassname(entity, EdictName, sizeof(EdictName));
							if(StrContains(EdictName, "first_aid_kit", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_kits[client] += 1;
							}
							if(StrContains(EdictName, "defibrillator", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_defibs[client] += 1;
							}
							if(StrContains(EdictName, "upgradepack_incendiary", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_firepacks[client] += 1;
							}
							if(StrContains(EdictName, "upgradepack_explosive", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_explodepacks[client] += 1;
							}
						}
						pack_slot2[client] = iSlot - 3;
						switch (iSlot - 3) {
							case 1: {
								if(pack_kits[client] > 0) {
									FakeClientCommand(client, "give first_aid_kit");
									pack_kits[client] -= 1;
								} else {
									pack_slot3[client] = 0;
								}
							}
							case 2: {
								if(pack_defibs[client] > 0) {
									FakeClientCommand(client, "give defibrillator");
									pack_defibs[client] -= 1;
								} else {
									pack_slot3[client] = 0;
								}
							}
							case 3: {
								if(pack_firepacks[client] > 0) {
									FakeClientCommand(client, "give upgradepack_incendiary");
									pack_firepacks[client] -= 1;
								} else {
									pack_slot3[client] = 0;
								}
							}
							case 4: {
								if(pack_explodepacks[client] > 0) {
									FakeClientCommand(client, "give upgradepack_explosive");
									pack_explodepacks[client] -= 1;
								} else {
									pack_slot3[client] = 0;
								}
							}
						}
					}
					case 8, 9: {
						entity = GetPlayerWeaponSlot(client, 4);
						if(entity > -1) {
							GetEdictClassname(entity, EdictName, sizeof(EdictName));
							if(StrContains(EdictName, "pain_pills", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_pills[client] += 1;
							}
							if(StrContains(EdictName, "adrenaline", false) != -1) {
								RemovePlayerItem(client, entity);
								pack_adrens[client] += 1;
							}
						}
						pack_slot4[client] = iSlot - 7;
						switch (iSlot - 7) {
							case 1: {
								if(pack_pills[client] > 0) {
									FakeClientCommand(client, "give pain_pills");
									pack_pills[client] -= 1;
								} else {
									pack_slot4[client] = 0;
								}
							}
							case 2: {
								if(pack_adrens[client] > 0) {
									FakeClientCommand(client, "give adrenaline");
									pack_adrens[client] -= 1;
								} else {
									pack_slot4[client] = 0;
								}
							}
						}
					}
					default: {
						showpackHUD(client);
					}
				}
			} else {
				PrintToChat(client, "Вы не можете получить доступ к своему рюкзаку, будучи мертвым.");
			}
		} else {
			PrintToChat(client, "Вы не можете получить доступ к своему рюкзаку, когда он заражен.");
		}
	}
	
	SetCommandFlags("give", flags|FCVAR_CHEAT);
	
	return Plugin_Handled;
}


public showpackHUD(client) {
	decl String:line[100];
	new Handle:panel = CreatePanel();
	SetPanelTitle(panel, "Рюкзак:");
	DrawPanelText(panel, "---------------------");
	Format(line, sizeof(line), "Молотов: %d", pack_mols[client]);
	if(pack_slot2[client] == 1) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Самодельная бомба: %d", pack_pipes[client]);
	if(pack_slot2[client] == 2) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Банка рвоты: %d", pack_biles[client]);
	if(pack_slot2[client] == 3) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Аптечка: %d", pack_kits[client]);
	if(pack_slot3[client] == 1) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Дефибрилятор: %d", pack_defibs[client]);
	if(pack_slot3[client] == 2) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Зажигательные патроны: %d", pack_firepacks[client]);
	if(pack_slot3[client] == 3) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Взрывные патроны: %d", pack_explodepacks[client]);
	if(pack_slot3[client] == 4) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Таблетки: %d", pack_pills[client]);
	if(pack_slot4[client] == 1) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Адреналин: %d", pack_adrens[client]);
	if(pack_slot4[client] == 2) StrCat(line, sizeof(line), " (Selected)");
	DrawPanelItem(panel, line);
	DrawPanelItem(panel, "Выход");
	SendPanelToClient(panel, client, Panel_Backpack, 60);
	CloseHandle(panel);
	return;
}


public Panel_Backpack(Handle:menu, MenuAction:action, param1, param2) {
	new entity;
	decl String:EdictName[128];
	new flags = GetCommandFlags("give");
	
	if (!(action == MenuAction_Select)) {
		return;
	}
	
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	switch (param2) {
		case 1, 2, 3: {
			entity = GetPlayerWeaponSlot(param1, 2);
			if(entity > -1) {
				GetEdictClassname(entity, EdictName, sizeof(EdictName));
				if(StrContains(EdictName, "molotov", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_mols[param1] += 1;
				}
				if(StrContains(EdictName, "pipe_bomb", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_pipes[param1] += 1;
				}
				if(StrContains(EdictName, "vomitjar", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_biles[param1] += 1;
				}
			}
			pack_slot2[param1] = param2;
			switch (param2) {
				case 1: {
					if(pack_mols[param1] > 0) {
						FakeClientCommand(param1, "give molotov");
						pack_mols[param1] -= 1;
					} else {
						pack_slot2[param1] = 0;
					}
				}
				case 2: {
					if(pack_pipes[param1] > 0) {
						FakeClientCommand(param1, "give pipe_bomb");
						pack_pipes[param1] -= 1;
					} else {
						pack_slot2[param1] = 0;
					}
				}
				case 3: {
					if(pack_biles[param1] > 0) {
						FakeClientCommand(param1, "give vomitjar");
						pack_biles[param1] -= 1;
					} else {
						pack_slot2[param1] = 0;
					}
				}
			}
		}
		case 4, 5, 6, 7: {
			entity = GetPlayerWeaponSlot(param1, 3);
			if(entity > -1) {
				GetEdictClassname(entity, EdictName, sizeof(EdictName));
				if(StrContains(EdictName, "first_aid_kit", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_kits[param1] += 1;
				}
				if(StrContains(EdictName, "defibrillator", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_defibs[param1] += 1;
				}
				if(StrContains(EdictName, "upgradepack_incendiary", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_firepacks[param1] += 1;
				}
				if(StrContains(EdictName, "upgradepack_explosive", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_explodepacks[param1] += 1;
				}
			}
			pack_slot2[param1] = param2 - 3;
			switch (param2 - 3) {
				case 1: {
					if(pack_kits[param1] > 0) {
						FakeClientCommand(param1, "give first_aid_kit");
						pack_kits[param1] -= 1;
					} else {
						pack_slot3[param1] = 0;
					}
				}
				case 2: {
					if(pack_defibs[param1] > 0) {
						FakeClientCommand(param1, "give defibrillator");
						pack_defibs[param1] -= 1;
					} else {
						pack_slot3[param1] = 0;
					}
				}
				case 3: {
					if(pack_firepacks[param1] > 0) {
						FakeClientCommand(param1, "give upgradepack_incendiary");
						pack_firepacks[param1] -= 1;
					} else {
						pack_slot3[param1] = 0;
					}
				}
				case 4: {
					if(pack_explodepacks[param1] > 0) {
						FakeClientCommand(param1, "give upgradepack_explosive");
						pack_explodepacks[param1] -= 1;
					} else {
						pack_slot3[param1] = 0;
					}
				}
			}
		}
		case 8, 9: {
			entity = GetPlayerWeaponSlot(param1, 4);
			if(entity > -1) {
				GetEdictClassname(entity, EdictName, sizeof(EdictName));
				if(StrContains(EdictName, "pain_pills", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_pills[param1] += 1;
				}
				if(StrContains(EdictName, "adrenaline", false) != -1) {
					RemovePlayerItem(param1, entity);
					pack_adrens[param1] += 1;
				}
			}
			pack_slot4[param1] = param2 - 7;
			switch (param2 - 7) {
				case 1: {
					if(pack_pills[param1] > 0) {
						FakeClientCommand(param1, "give pain_pills");
						pack_pills[param1] -= 1;
					} else {
						pack_slot4[param1] = 0;
					}
				}
				case 2: {
					if(pack_adrens[param1] > 0) {
						FakeClientCommand(param1, "give adrenaline");
						pack_adrens[param1] -= 1;
					} else {
						pack_slot4[param1] = 0;
					}
				}
			}
		}
	}
	SetCommandFlags("give", flags|FCVAR_CHEAT);
	return;
}


public Action:AdminViewMenu(client, args) {
	decl String:line[100];
	new Handle:panel = CreatePanel();
	SetPanelTitle(panel, "Админ Pack View:");
	DrawPanelText(panel, "---------------------");
	
	Format(line, sizeof(line), "Игроки: %3d %3d %3d %3d %3d %3d %3d %3d", 1, 2, 3, 4, 5, 6, 7, 8);
	DrawPanelText(panel, line);
	Format(line, sizeof(line), "Молотов: %3d %3d %3d %3d %3d %3d %3d %3d", pack_mols[1], pack_mols[2], pack_mols[3], pack_mols[4], pack_mols[5], pack_mols[6], pack_mols[7], pack_mols[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Самодельная бомба: %3d %3d %3d %3d %3d %3d %3d %3d", pack_pipes[1], pack_pipes[2], pack_pipes[3], pack_pipes[4], pack_pipes[5], pack_pipes[6], pack_pipes[7], pack_pipes[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Банка рвоты: %3d %3d %3d %3d %3d %3d %3d %3d", pack_biles[1], pack_biles[2], pack_biles[3], pack_biles[4], pack_biles[5], pack_biles[6], pack_biles[7], pack_biles[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Аптечка: %3d %3d %3d %3d %3d %3d %3d %3d", pack_kits[1], pack_kits[2], pack_kits[3], pack_kits[4], pack_kits[5], pack_kits[6], pack_kits[7], pack_kits[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Дефибрилято: %3d %3d %3d %3d %3d %3d %3d %3d", pack_defibs[1], pack_defibs[2], pack_defibs[3], pack_defibs[4], pack_defibs[5], pack_defibs[6], pack_defibs[7], pack_defibs[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Зажигательные патроны: %3d %3d %3d %3d %3d %3d %3d %3d", pack_firepacks[1], pack_firepacks[2], pack_firepacks[3], pack_firepacks[4], pack_firepacks[5], pack_firepacks[6], pack_firepacks[7], pack_firepacks[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Взрывные патроны: %3d %3d %3d %3d %3d %3d %3d %3d", pack_explodepacks[1], pack_explodepacks[2], pack_explodepacks[3], pack_explodepacks[4], pack_explodepacks[5], pack_explodepacks[6], pack_explodepacks[7], pack_explodepacks[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Таблетки: %3d %3d %3d %3d %3d %3d %3d %3d", pack_pills[1], pack_pills[2], pack_pills[3], pack_pills[4], pack_pills[5], pack_pills[6], pack_pills[7], pack_pills[8]);
	DrawPanelItem(panel, line);
	Format(line, sizeof(line), "Адреналин: %3d %3d %3d %3d %3d %3d %3d %3d", pack_adrens[1], pack_adrens[2], pack_adrens[3], pack_adrens[4], pack_adrens[5], pack_adrens[6], pack_adrens[7], pack_adrens[8]);
	DrawPanelItem(panel, line);
	DrawPanelItem(panel, "Выход");
	SendPanelToClient(panel, client, Panel_Nothing, 60);
	CloseHandle(panel);
	
	return Plugin_Handled;
}


public Panel_Nothing(Handle:menu, MenuAction:action, param1, param2) {
	return;
}