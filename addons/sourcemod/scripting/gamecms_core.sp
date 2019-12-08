
#include <sourcemod>
#include <basecomm>

#define DB_PASS		0
#define USER_PASS	1

#define PUSHMENT_BAN  0 
#define PUSHMENT_MUTE 1 
#define PUSHMENT_GAG  2 
#define PUSHMENT_M_G  3 

#define BANSTEAM	1
#define BANIP		2

#define LOGSERVICES	1
#define LOGRIGHTS	2
#define LOGCONNECTS	4
#define LOGDB		8
#define LOGPW		16

#define SITEURL "https://classic-source.pp.ua/"

static const String: sLog[] = "addons/sourcemod/logs/gamecms_core.log";

new		g_iLoggin = 31,
		g_iLoadedServices,
		g_iServerId	= -1,
		g_iBanType	= 3,
String:	g_sInfoVar[32] = "_pw",
Handle:	g_hDatabase,
Handle:	g_hArrayServiceId,
Handle:	g_hArrayServiceName,
Handle:	g_hArrayServiceFlags,
Handle:	g_hArrayServiceImmunity,
Handle: hCvarForceId,
		g_iUserId[MAXPLAYERS];


public Plugin:myinfo = 
{
	name = "GameCMS: Core",
	author = "Danyas",
	description = "Services & Bans & Mutes support for GameCMS",
	version = "1.1a",
	url = "https://vk.com/id36639907"
}

public OnPluginStart()
{
	if (!SQL_CheckConfig("gamecms")) 
	{ 
		SetFailState("Секция \"gamecms\" не найдена в databases.cfg");
	}
	
	RegAdminCmd("sm_gamecms_ban",	CMD_MENU_BAN,		ADMFLAG_BAN);
	RegAdminCmd("sm_gamecms_unban",	CMD_MENU_UNBAN,		ADMFLAG_BAN);
	
	RegAdminCmd("sm_gamecms_mute",	CMD_MENU_MUTE,		ADMFLAG_BAN);
	//RegAdminCmd("sm_gamecms_unmute",	CMD_MENU_UNMUTE,	ADMFLAG_BAN);
	
	RegAdminCmd("sm_gamecms_gag",	CMD_MENU_GAG,		ADMFLAG_BAN);
	//RegAdminCmd("sm_gamecms_ungag",	CMD_MENU_UNGAG,		ADMFLAG_BAN);
	
	RegAdminCmd("sm_gamecms_silence",	CMD_MENU_SILENCE,	ADMFLAG_BAN);
	//RegAdminCmd("sm_gamecms_unsilence",	CMD_MENU_UNSILENCE,	ADMFLAG_BAN);


	hCvarForceId = CreateConVar("sm_gamecms_core_force_serverid", "-1", "Manual choose ServerId, -1 for autodetect", _, true, -1.0);

	
	new Handle: hCvar = CreateConVar(
		"sm_gamecms_core_logs",
		"31", "1 - LOG SERVICES / 2 - LOG RIGHTS / 4 - CONNECTS / 8 - LOG DB QUERIES / 16 - LOG PASSCHECKS (LOG SERVICES + LOG RIGHTS = 3)"
		, _, true, 0.0, true, 31.0);
		
																																   
	
	HookConVarChange(hCvar, UpdateCvar_log);
	
	
	hCvar = CreateConVar(
		"sm_gamecms_core_pushment_type",
		"3", "1 - SteamID / 2 - IP (SteamID + IP = 3)"
		, _, true, 0.0, true, 3.0);
		
	
	HookConVarChange(hCvar, UpdateCvar_bantype);
	
	AutoExecConfig(true, "gamecms_core");
	
									
	
	g_hArrayServiceId = CreateArray();
	g_hArrayServiceName = CreateArray(64);
	g_hArrayServiceFlags = CreateArray();
	g_hArrayServiceImmunity = CreateArray();

	SQL_TConnect(SQL_LoadServer, "gamecms");
}


public SQL_LoadServer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)  
	{
		SetFailState("Database failure: %s", error);
		return;
	}

	g_hDatabase = hndl;
	decl String:query[192]; query[0] = '\0';
	
	new iVar = GetConVarInt(hCvarForceId);
	if(iVar == -1)
	{
		new longip = GetConVarInt(FindConVar("hostip"));
		
		FormatEx(query, sizeof(query),
			"SELECT `pass_prifix`,`id` FROM `servers` WHERE `ip` = '%d.%d.%d.%d' AND `port` = '%i'",
				(longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF, GetConVarInt(FindConVar("hostport")));
				
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer: \"%s\"", query);
	}
	else
	{
		FormatEx(query, sizeof(query), "SELECT `pass_prifix` FROM `servers` WHERE `id` = '%i'", g_iServerId = iVar);
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer: \"%s\"", query);
	}
	
	SQL_TQuery(g_hDatabase, SQL_CheckServer, query);
}


public SQL_CheckServer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) LogError("SQL_CheckServer Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		SQL_FetchString(hndl, 0, g_sInfoVar, sizeof(g_sInfoVar));
		if(g_iServerId == -1) g_iServerId = SQL_FetchInt(hndl, 1);
		
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer Result: [SERVER ID: %i] [PASS INFO VAR: \"%s\"]", g_iServerId, g_sInfoVar);
		
		
		decl String:query[96]; query[0] = '\0';
		FormatEx(query, sizeof(query), "SELECT `id`, `name`, `rights`, `immunity` FROM `services` WHERE `server` = '%i'", g_iServerId);
		
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_GetServices: \"%s\"", query);
		SQL_TQuery(g_hDatabase, SQL_GetServices, query);
	}
	else
	{
		if(g_iServerId == -1)
		{
			new longip = GetConVarInt(FindConVar("hostip"));
			SetFailState("Сервер \"%d.%d.%d.%d:%i\" не найден базе сайта", (longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF, GetConVarInt(FindConVar("hostport")));
		}
		else
		{
			SetFailState("Указан неверный \"sm_gamecms_loader_force_serverid\"");
		}
	}
}

public SQL_GetServices(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) LogError("SQL_GetServices Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl))
	{
		g_iLoadedServices = 0;
		if(g_iLoggin & LOGSERVICES)  LogToFileEx(sLog, "|#    |        Флаги          | Иммунитет | Название услуги");
		while (SQL_FetchRow(hndl))
		{
			decl String:sFlags[AdminFlags_TOTAL + 1], String: sServiceName[64];
			
			PushArrayCell(g_hArrayServiceId, SQL_FetchInt(hndl, 0));
			
			SQL_FetchString(hndl, 1, sServiceName, sizeof(sServiceName));	
			SQL_FetchString(hndl, 2, sFlags, sizeof(sFlags));
			
			PushArrayString(g_hArrayServiceName, sServiceName);
			
			new AdminFlag:flag, flagbits;
			
			for (new i = 0; i < strlen(sFlags); i++)
			{
				if (!FindFlagByChar(sFlags[i], flag))
				{
					LogToFileEx(sLog, "Найден неверный флаг: %c", sFlags[i]);
				}
				else
				{
					flagbits |= FlagToBit(flag);
				}
			}
			
			PushArrayCell(g_hArrayServiceFlags, flagbits);
			PushArrayCell(g_hArrayServiceImmunity, SQL_FetchInt(hndl, 3));
			
			if(g_iLoggin & LOGSERVICES)
				LogToFileEx(sLog, "|#%4d| %21s | %9i | %s",
					g_iLoadedServices + 1, sFlags, GetArrayCell(g_hArrayServiceImmunity, g_iLoadedServices), sServiceName);
			
			g_iLoadedServices++;
		}
		
		if(g_iLoadedServices == 0) SetFailState("Не удалось получить список услуг");
		
		if(g_iLoggin & LOGSERVICES) LogToFileEx(sLog, "Загружено %i услуг из базы.", g_iLoadedServices);
		
		for (new i = 1; i <= MaxClients; ++i)
		{
			if (IsClientInGame(i)) OnClientPostAdminCheck(i);
		}
	}
}

public OnClientPostAdminCheck(client)
{
	if(IsFakeClient(client)) return;

	decl String: sAuth[21], String:query[420]; // MLG NONSCOPED H@RDCODING SKILLZ ACTIVATED
	// SELECT `reason`, `ends`, `type` FROM `gamecms_pushments` WHERE `ip` = INET_ATON("78.189.100.21") OR `authid` = 'STEAM_1:0:1400466842' AND `ends` > 1488 AND `sid` = 2
	
	if(g_iBanType & BANSTEAM)
	{
		//STEAM_1:0:1400466842
		GetClientAuthId(client, AuthId_Engine, sAuth, sizeof(sAuth));
		if(g_iBanType & BANIP)
		{
			decl String: sAuthIP[17];
			GetClientIP(client, sAuthIP, sizeof(sAuthIP));
			FormatEx(query, sizeof(query), "SELECT `type` FROM `gamecms_pushments` WHERE `authid` = '%s' OR `ip` = INET_ATON(\"%s\") AND `ends` > %i AND `sid` = %i", sAuth, sAuthIP, GetTime(), g_iServerId);
		}
		else
		{
			FormatEx(query, sizeof(query), "SELECT `type` FROM `gamecms_pushments` WHERE `authid` = '%s' AND `ends` > %i AND `sid` = %i", sAuth, GetTime(), g_iServerId);
		}
	}

	else if(g_iBanType & BANIP)
	{
		if(GetClientIP(client, sAuth, sizeof(sAuth)))
		{
			//78.189.100.21
			FormatEx(query, sizeof(query), "SELECT `type` FROM `gamecms_pushments` WHERE `ip` = INET_ATON(\"%s\") AND `ends` > %i AND `sid` = %i", sAuth, GetTime(), g_iServerId);
		}
	}
	else
	{
		CheckServices(client);
	}
	
	if(query[0])
	{
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "OnClientPostAdminCheck PushmentCheck: \"%s\"", query);
		SQL_TQuery(g_hDatabase, SQL_Callback_PushmentCheck, query, GetClientUserId(client));
	}
}

public SQL_Callback_PushmentCheck(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	if(client > 0)
	{	
		if(hndl == INVALID_HANDLE)
		{
			LogError("SQL_Callback_PushmentCheck Query falied. (error:  %s)", error);
			return;
		}
		
		if(SQL_FetchRow(hndl))
		{
			switch(SQL_FetchInt(hndl, 0))
			{
				case PUSHMENT_BAN:
				{
					KickClient(client, "[GameCMS]\nВы забанены на этом сервере.\nПодробнее: %s/banlist?server=%i", SITEURL, g_iServerId);
				}
				
				case PUSHMENT_MUTE:
				{
					PrintToChat(client, "[GameCMS] У вас отключен микрофон.\nПодробнее: %s/muts?server=%i", SITEURL, g_iServerId);
					BaseComm_SetClientMute(client, true);
					//SetClientListeningFlags(client, VOICE_MUTED);
					CheckServices(client);
				}
				
				case PUSHMENT_GAG:
				{
					PrintToChat(client, "[GameCMS] У вас отключен чат.\nПодробнее: %s/muts?server=%i", SITEURL, g_iServerId);
					BaseComm_SetClientGag(client, true);
					CheckServices(client);
				}
				
				case PUSHMENT_M_G:
				{
					PrintToChat(client, "[GameCMS] У вас отключен микрофон и чат.\nПодробнее: %s/muts?server=%i", SITEURL, g_iServerId);
					BaseComm_SetClientGag(client, true);
					CheckServices(client);
				}
			}
		}
		else
		{
			CheckServices(client);
		}
	}
}

CheckServices(client)
{
	decl String: sSteamId[21], String:query[420]; // MLG NONSCOPED H@RDCODING SKILLZ ACTIVATED
	GetClientAuthId(client, AuthId_Engine, sSteamId, sizeof(sSteamId));
	FormatEx(query, 420, "SELECT `admins__services`.`service`, `admins__services`.`rights_und`, `admins`.`pass`, `admins`.`user_id`  FROM `admins__services`, `admins` WHERE `admins`.`id`=`admins__services`.`admin_id` AND `admins`.`name`='%s' AND `admins`.`server`='%i' AND (`admins__services`.`ending_date`>CURRENT_TIMESTAMP OR `admins__services`.`ending_date`='0000-00-00 00:00:00')", sSteamId, g_iServerId);
	if(g_iLoggin & LOGCONNECTS) LogToFileEx(sLog, "Игрок %N (%s) подключен.", client, sSteamId);	
	if(g_iLoggin & LOGDB) LogToFileEx(sLog, "OnClientPostAdminCheck: \"%s\"", query);
	SQL_TQuery(g_hDatabase, SQL_Callback, query, client)	
}

public SQL_Callback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (!IsClientConnected(client))	return;
	
	if(hndl == INVALID_HANDLE) LogError("SQL_Callback Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl))
	{
		decl String:sFlags[AdminFlags_TOTAL + 1]; sFlags[0] = '\0';
		new	MaxImmunity, c;
		
		
		while (SQL_FetchRow(hndl))
		{
			decl String:tFlags[AdminFlags_TOTAL + 1]; tFlags[0] = '\0';
			decl String:sPasswordDB[32]; sPasswordDB[0] = '\0';
			
			new iService = SQL_FetchInt(hndl, 0);
			new bool: bFlagsOverride;
			new iAuthStatus;
			// -1 - invalid pass
			//  0 - no db pass
			//  1 - valid pass
			
			
			SQL_FetchString(hndl, 2, sPasswordDB, sizeof(sPasswordDB));
			
			if(sPasswordDB[0] != 0)
			{
				decl String: sPassword[32]; sPassword[0] = '\0';
				iAuthStatus = -1;
				
				if(GetClientInfo(client, g_sInfoVar, sPassword, sizeof(sPassword)) && sPassword[0] != 0 && StrEqual(sPassword, sPasswordDB))
				{
					iAuthStatus = 1;
				}
			}
			
			SQL_FetchString(hndl, 1, tFlags, sizeof(tFlags));
			
			
			if(!StrEqual(tFlags, "none"))
			{
				bFlagsOverride = true;
			}
			else tFlags[0] = '\0';
			
			for(new i; i < g_iLoadedServices; i++)
			{
				if(GetArrayCell(g_hArrayServiceId, i) == iService)
				{
					if(g_iLoggin & LOGRIGHTS)
					{
						decl String: sServiceName[64]; sServiceName[0] = '\0';
						GetArrayString(g_hArrayServiceName, i, sServiceName, sizeof(sServiceName));
						LogToFileEx(sLog, "У игрока %N обнаружена услуга: %s%s%s%s", client,  sServiceName, bFlagsOverride ? ". Обнаружено изменение флагов на ": "", tFlags,	iAuthStatus == -1 ? ", но пароль введен не верно" : (g_iLoggin & LOGPW && iAuthStatus == 1) ? ", пароль введен верно" : (g_iLoggin & LOGPW && iAuthStatus == 0) ? ", пароль не требуеться" : "");
					}
					
					if(iAuthStatus != -1)
					{
						new iServiceImmunity = GetArrayCell(g_hArrayServiceImmunity, i);
						if(MaxImmunity < iServiceImmunity) MaxImmunity = iServiceImmunity;
						
						if(bFlagsOverride)
						{
							new AdminFlag:flag;
							
							for (new a = 0; a < strlen(tFlags); a++)
							{
								if (!FindFlagByChar(tFlags[a], flag)) {LogToFileEx(sLog, "Найден неверный флаг: %c", tFlags[a]);}
								else
								{
									AddUserFlags(client, flag);
									if(g_iLoggin & LOGRIGHTS) {if(!FindFlagChar(flag, c)) c = 't'; Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);}
								}
							}
						}
						else
						{
							new AdminFlag:flags[AdminFlags_TOTAL];
							
							new num_flags = FlagBitsToArray(GetArrayCell(g_hArrayServiceFlags, i), flags, sizeof(flags));
							
							for (new x = 0; x < num_flags; x++)
							{
								AddUserFlags(client, flags[x]);
								if(g_iLoggin & LOGRIGHTS) {if(!FindFlagChar(flags[x], c)) c = 't'; Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);}
							}
						}
					}
				}
			}
			
			g_iUserId[client] = SQL_FetchInt(hndl, 3);
		}
	
		new	iImmunity, AdminId:id = GetUserAdmin(client);
		if(id == INVALID_ADMIN_ID)
		{
			id = CreateAdmin();
			SetUserAdmin(client, id, true);
		}
		else
		{
			iImmunity = GetAdminImmunityLevel(id);
		}
		
		if(iImmunity < MaxImmunity)
		{
			SetAdminImmunityLevel(id, iImmunity);
		}
		
		if(g_iLoggin & LOGCONNECTS && g_iUserId[client] != 0) LogToFileEx(sLog, "Игрок %N - %i userid на сайте (%s/profile?id=%i)", client, g_iUserId[client], SITEURL, g_iUserId[client]);	
	
		if(g_iLoggin & LOGRIGHTS && c != 0) LogToFileEx(sLog, "Игроку %N выданы флаги: \"%s\" и установлен иммунитет \"%i\"", client, sFlags, iImmunity < MaxImmunity ? MaxImmunity : iImmunity);
	}
}

public Action:CMD_MENU_BAN(client, args) 
{ 
	if (client > 0 && args < 1)
	{
		new Handle:menu = CreateMenu(Select_BanMenu);
		SetMenuTitle(menu, "[GameCMS] Выбор игрока для бана:\n "); 
		decl String:userid[15], String:name[32]; 
		for (new i = 1; i <= MaxClients; i++) 
		{ 
			if (IsClientInGame(i)) 
			{ 		  
				if(/*client == i || !CanUserTarget(client, i) || */IsFakeClient(i)) continue;
				IntToString(GetClientUserId(i), userid, 15); 
				GetClientName(i, name, 32); 
				AddMenuItem(menu, userid, name); 
			} 
		} 
		
		DisplayMenu(menu, client, 0); 
	}
	return Plugin_Handled; 
}


public Action:CMD_MENU_MUTE(client, args) 
{ 
	if (client > 0 && args < 1)
	{
		new Handle:menu;// = CreateMenu(Select_MuteMenu);
		SetMenuTitle(menu, "[GameCMS] Выбор игрока для мута:\n "); 
		decl String:userid[15], String:name[32]; 
		for (new i = 1; i <= MaxClients; i++) 
		{ 
			if (IsClientInGame(i)) 
			{ 		  
				if(/*client == i || !CanUserTarget(client, i) || */IsFakeClient(i)) continue;
				IntToString(GetClientUserId(i), userid, 15); 
				GetClientName(i, name, 32); 
				AddMenuItem(menu, userid, name); 
			} 
		} 
		
		DisplayMenu(menu, client, 0); 
	}
	return Plugin_Handled; 
}

public Action:CMD_MENU_GAG(client, args) 
{ 
	if (client > 0 && args < 1)
	{
		new Handle:menu;// = CreateMenu(Select_GagMenu);
		SetMenuTitle(menu, "[GameCMS] Выбор игрока для гага:\n "); 
		decl String:userid[15], String:name[32]; 
		for (new i = 1; i <= MaxClients; i++) 
		{ 
			if (IsClientInGame(i)) 
			{ 		  
				if(/*client == i || !CanUserTarget(client, i) || */IsFakeClient(i)) continue;
				IntToString(GetClientUserId(i), userid, 15); 
				GetClientName(i, name, 32); 
				AddMenuItem(menu, userid, name); 
			} 
		} 
		
		DisplayMenu(menu, client, 0); 
	}
	return Plugin_Handled; 
}


public Action:CMD_MENU_SILENCE(client, args) 
{ 
	if (client > 0 && args < 1)
	{
		new Handle:menu;// = CreateMenu(Select_SilenceMenu);
		SetMenuTitle(menu, "[GameCMS] Выбор игрока для мута+гага:\n "); 
		decl String:userid[15], String:name[32]; 
		for (new i = 1; i <= MaxClients; i++) 
		{ 
			if (IsClientInGame(i)) 
			{ 		  
				if(/*client == i || !CanUserTarget(client, i) || */IsFakeClient(i)) continue;
				IntToString(GetClientUserId(i), userid, 15); 
				GetClientName(i, name, 32); 
				AddMenuItem(menu, userid, name); 
			} 
		} 
		
		DisplayMenu(menu, client, 0); 
	}
	return Plugin_Handled; 
}


public Action:CMD_MENU_UNBAN(client, args) 
{ 
	if (client > 0 && args < 1)
	{
		SQL_TQuery(g_hDatabase, GetBans_Callback, "SELECT `name`, `bid`, INET_NTOA(`ip`), `unban_aid` FROM `gamecms_pushments` ORDER BY `bid` DESC", GetClientUserId(client));
	}
	return Plugin_Handled; 
} 

public GetBans_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("GetBans_Callback: Query failed! %s", error);
	}
	
	new client = GetClientOfUserId(data);
	if (client == 0)
	{
		LogError("[GetBans_Callback] Client is not valid. Reason: %s", error);
		return;
	}

	decl String: sBuff[64], String:sBanId[8], String: sIP[32] = "NO IP", String: sOut[128];
	new Handle:menu = CreateMenu(Select_UnBanMenu);
	new iCnt;
	while (SQL_FetchRow(hndl))
	{
		iCnt++;
		SQL_FetchString(hndl, 0, sBuff, sizeof(sBuff));
		new banid = SQL_FetchInt(hndl, 1);
		
		if(SQL_IsFieldNull(hndl, 2) == false)
   
				 
   
	  
		{
			SQL_FetchString(hndl, 2, sIP, sizeof(sIP));
		}

		FormatEx(sOut, sizeof(sOut), "%s (%s)", sBuff, sIP);
		IntToString(banid, sBanId, sizeof(sBanId));
		AddMenuItem(menu, sBanId, sOut, SQL_IsFieldNull(hndl, 3) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	SetMenuTitle(menu, "[GameCMS] Выбор игрока для разбана:\n  (всего %i банов)\n \n", iCnt); 
	DisplayMenu(menu, client, 0); 
}

public Select_UnBanMenu(Handle:menu, MenuAction:action, client, option) 
{
	switch(action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		
		case MenuAction_Select:
		{
			decl String:href[256], String:banid[12];
			GetMenuItem(menu, option, banid, 12);
			FormatEx(href, sizeof(href), "UPDATE `gamecms_pushments` SET `unban_aid` = %i WHERE `bid` = %i", g_iUserId[client], StringToInt(banid));
			SQL_TQuery(g_hDatabase, SQL_ErrorCheckCallBack, href, GetClientUserId(client));
		}
	}
}

public SQL_ErrorCheckCallBack(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("Query failed! %s", error);
	}
	else
	{
		new client = GetClientOfUserId(data);
		if(client)
		{
			PrintToChat(client, "[GameCMS] Игрок успешно разбанен!");
		}
	}
}

public Select_BanMenu(Handle:menu, MenuAction:action, client, option) 
{
	switch(action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		
		case MenuAction_Select:
		{
			decl String:userid[15];
			GetMenuItem(menu, option, userid, 15);
			if(GetClientOfUserId(StringToInt(userid)))
			{
				new Handle:SecMenu = CreateMenu(Select_SecMenu);
				SetMenuTitle(SecMenu, "[GameCMS] Выбор причины и длительности бана:\n ");
				AddMenuItem(SecMenu, userid, "AFK (10 м.)");
				AddMenuItem(SecMenu, userid, "Высокий пинг (30 мин.)");
				AddMenuItem(SecMenu, userid, "Некорректный никнейм (1 ч.)");
				AddMenuItem(SecMenu, userid, "Умышленное ослепление союзников (3 ч.)");
				AddMenuItem(SecMenu, userid, "Некорректный спрей (3 ч.)");
				AddMenuItem(SecMenu, userid, "Использование багов (6 ч.)");
				AddMenuItem(SecMenu, userid, "Подозрение в читерстве (1 д.)");
				DisplayMenu(SecMenu, client, 0); 
			}
		}
	}
}


public Select_SecMenu(Handle:menu, MenuAction:action, client, option) 
{
	switch(action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		
		case MenuAction_Select:
		{
			decl String:userid[15];
			GetMenuItem(menu, option, userid, 15);
			new target = GetClientOfUserId(StringToInt(userid));
			if(target)
			{
				decl String:href[1024], String:sPlayerName[32], String:sEscPlayerName[65], String: sIP[17], String: sAuth[32],  String: sReason[128];
				GetClientName(target, sPlayerName, sizeof(sPlayerName) - 1); 
				SQL_EscapeString(g_hDatabase, sPlayerName, sEscPlayerName, sizeof(sEscPlayerName) - 1);
				GetClientIP(client, sIP, sizeof(sIP));
				GetClientAuthId(client, AuthId_Engine, sAuth, sizeof(sAuth));
				
				/* ВНИМАНИЁО, КАСТЫЛЬ */	
				new iBanTime;
				
				switch(option)
				{
					case 0:
					{
						iBanTime = 600;
						strcopy(sReason, sizeof(sReason), "AFK");
					}
					case 1:
					{
						iBanTime = 1800;
						strcopy(sReason, sizeof(sReason), "Высокий пинг");
					}
					case 2:
					{
						iBanTime = 3600;
						strcopy(sReason, sizeof(sReason), "Некорректный никнейм");
					}
					case 3:
					{
						iBanTime = 10800;
						strcopy(sReason, sizeof(sReason), "Умышленное ослепление союзников");
					}
					case 4:
					{
						iBanTime = 21600;
						strcopy(sReason, sizeof(sReason), "Использование багов");
					}
					case 5:
					{
						iBanTime = 86400;
						strcopy(sReason, sizeof(sReason), "Подозрение в читерстве");
					}
				}
	
				FormatEx(href, sizeof(href), "INSERT INTO `gamecms_pushments`(`ip`, `authid`, `name`, `created`, `length`, `ends`, `reason`, `aid`, `sid`) VALUES (INET_ATON(\"%s\"), \"%s\",\"%s\", %i, %i, %i, \"%s\", %i, %i);", sIP, sAuth, sEscPlayerName, GetTime(), iBanTime, GetTime() + iBanTime, sReason, g_iUserId[client], g_iServerId);
				SQL_TQuery(g_hDatabase, SQL_InsertCheckCallBack, href, GetClientUserId(target));
				
			}
		}
	}
}

public SQL_InsertCheckCallBack(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("SQL_InsertCheckCallBack: Query failed! %s", error);
	}
	else
	{
		new target = GetClientOfUserId(data);
		KickClient(target, "[GameCMS]\nВы забанены на этом сервере.\nПодробнее: %s/banlist?server=%i", SITEURL, g_iServerId);
		PrintToChatAll("[GameCMS] Игрок %N забанен.", target);
	}
}

public OnRebuildAdminCache(AdminCachePart:part)
{
	if(part != AdminCache_Admins) return;
	
	for (new i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i)) OnClientPostAdminCheck(i);
	}
}

public UpdateCvar_bantype(Handle:c, const String:ov[], const String:nv[])	g_iBanType = StringToInt(nv);
public UpdateCvar_log(Handle:c, const String:ov[], const String:nv[])	g_iLoggin = StringToInt(nv);
