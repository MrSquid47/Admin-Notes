#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "MrSquid"
#define PLUGIN_VERSION "1.0.4"

#include <sourcemod>
#include <sdktools>
#include <base64>
#include <morecolors>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Admin Notes", 
	author = PLUGIN_AUTHOR, 
	description = "Make notes on problematic players.", 
	version = PLUGIN_VERSION, 
	url = ""
};

char linebreak[] = "------------------------------------------------------------";
Database db;
int notenums[MAXPLAYERS + 1];
int notemax[MAXPLAYERS + 1];
int erasenums[MAXPLAYERS + 1];
int erasetargets[MAXPLAYERS + 1];
int notetargets[MAXPLAYERS + 1];
bool notechat[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	DB_Connect();
	
	RegAdminCmd("sm_makenote", Command_makenote, ADMFLAG_BAN, "Make a note on a player");
	RegAdminCmd("sm_erasenote", Command_erasenote, ADMFLAG_BAN, "Erase a note on a player");
	RegAdminCmd("sm_notes", Command_getnote, ADMFLAG_BAN, "List player notes");
	RegAdminCmd("sm_listnotes", Command_listnotes, ADMFLAG_BAN, "List players with notes");
	
	CreateTimer(240.0, Timer_reconnect, _, TIMER_REPEAT);
}

public void OnClientPostAdminCheck(int client)
{
	for (int i = 1; i < MaxClients; i++)
	{
		if (i > 0 && i <= MaxClients && IsClientInGame(i))
		{
			if (CheckCommandAccess(i, "sm_notes", ADMFLAG_GENERIC, false))
			{
				DB_PrintNotes(i, client);
			}
		}
	}
}

void DB_Connect()
{
	SQL_TConnect(CB_DB_Connect, "admin-notes");
}

void CB_DB_Connect(Handle owner, Handle hndl, const char[] error, any data)
{
	db = view_as<Database>(hndl);
	
	if (db == INVALID_HANDLE)
	{
		LogError("Failed to connect to database: %s", error);
	}
}

void CB_checkAuth(Database rDB, DBResultSet rs, char[] error, int client)
{
	if (rDB == INVALID_HANDLE || rs == INVALID_HANDLE)
	{
		LogError("CheckAuth Failed: %s", error);
		return;
	}
	
	if (rs.FetchRow()) {
		if (erasenums[client] == 0)
		{
			erasenums[client] = 1;
		}
		
		for (int i = 1; i < erasenums[client]; i++)
		{
			if (!rs.FetchRow()) {
				PrintToChat(client, "[AN] The specified note does not exist.");
				return;
			}
		}
		
		char auth[32];
		rs.FetchString(0, auth, sizeof(auth));
		
		char sAuth[32];
		GetClientAuthId(client, AuthId_Steam3, sAuth, sizeof(sAuth));
		
		if (StrEqual(auth, sAuth)) {
			DB_EraseNote(client, erasetargets[client]);
		} else {
			PrintToChat(client, "[AN] You do not have permission to erase this note.");
		}
	}
}

void checkAuth(int client)
{
	if (db == INVALID_HANDLE) {
		LogError("CheckAuth Failed: Not connected to database!");
		PrintToChat(client, "[AN] UNABLE TO CONFIRM AUTH!");
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(erasetargets[client], AuthId_Steam3, sAuth, sizeof(sAuth));
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT b.authorid FROM notes b WHERE b.steamid = '%s' ORDER BY id;", sAuth);
	
	db.Query(CB_checkAuth, sQuery, client);
}

void CB_DB_GetNote(Database rDB, DBResultSet rs, char[] error, int client)
{
	if (rDB == INVALID_HANDLE || rs == INVALID_HANDLE)
	{
		LogError("GetNote Failed: %s", error);
		return;
	}
	
	if (rs.FetchRow()) {
		if (notenums[client] == 0)
		{
			notenums[client] = 1;
		}
		
		for (int i = 1; i < notenums[client]; i++)
		{
			if (!rs.FetchRow()) {
				PrintToChat(client, "[AN] The specified note does not exist.");
			}
		}
		
		char noteB64[256], note[256];
		rs.FetchString(0, noteB64, sizeof(noteB64));
		DecodeBase64(note, sizeof(note), noteB64);
		notemax[client] = rs.RowCount;
		
		char authorB64[128], author[64], authorid[32], ndate[32];
		rs.FetchString(1, authorB64, sizeof(authorB64));
		DecodeBase64(author, sizeof(author), authorB64);
		rs.FetchString(2, authorid, sizeof(authorid));
		rs.FetchString(3, ndate, sizeof(ndate));
		
		if (notechat[client] == true)
		{
			PrintToChat(client, "%s\nNote %i of %i:\n%s\nAuthor: %s %s\nDate: %s\n%s", linebreak, notenums[client], rs.RowCount, note, author, authorid, ndate, linebreak);
		} else {
			ShowMenu(client, note, author, authorid, ndate);
		}
	} else {
		PrintToChat(client, "[AN] There are no notes for this player.");
	}
	
	delete rs;
}

void CB_DB_MakeNote(Database rDB, DBResultSet rs, char[] error, int client)
{
	PrintToChat(client, "[AN] The note has been saved.");
	delete rs;
}

void CB_DB_PrintNotes(Database rDB, DBResultSet rs, char[] error, int data)
{
	int client = data & 0xFFFF;
	int target = (data >> 16) & 0xFFFF;
	char n[256];
	GetClientName(target, n, sizeof(n));
	if (rs.FetchRow()) {
		CPrintToChat(client, "[AN] Player '%s' has {gold}%i{white} note(s)!", n, rs.RowCount);
	}
	
	delete rs;
}

void CB_DB_EraseNote(Database rDB, DBResultSet rs, char[] error, int client)
{
	if (rDB == INVALID_HANDLE)
	{
		LogError("EraseNote Failed: %s", error);
		return;
	}
	
	if (rs.FetchRow()) {
		if (erasenums[client] == 0)
		{
			erasenums[client] = 1;
		}
		
		for (int i = 1; i < erasenums[client]; i++)
		{
			if (!rs.FetchRow()) {
				PrintToChat(client, "[AN] The specified note does not exist.");
				return;
			}
		}
		
		int id = rs.FetchInt(0);
		
		char query[256];
		FormatEx(query, sizeof(query), "DELETE from notes where id=%i;", id);
		SQL_LockDatabase(db);
		SQL_FastQuery(db, query);
		SQL_UnlockDatabase(db);
		
		PrintToChat(client, "[AN] Note erased.");
	} else {
		PrintToChat(client, "[AN] There are no notes for this player.");
	}
	
	delete rs;
}

void DB_MakeNote(int client, int target, char[] note)
{
	if (db == INVALID_HANDLE) {
		LogError("MakeNote Failed: Not connected to database!");
		PrintToChat(client, "[AN] Not connected to database!");
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(target, AuthId_Steam3, sAuth, sizeof(sAuth));
	
	char AuthName[64], AuthNameB64[128];
	GetClientName(client, AuthName, sizeof(AuthName));
	
	EncodeBase64(AuthNameB64, sizeof(AuthNameB64), AuthName);
	
	char sAuth2[32];
	GetClientAuthId(client, AuthId_Steam3, sAuth2, sizeof(sAuth2));
	
	char ndate[32];
	FormatTime(ndate, sizeof(ndate), NULL_STRING);
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO notes (steamid, note, author, authorid, ndate) VALUES ('%s', '%s', '%s', '%s', '%s');", sAuth, note, AuthNameB64, sAuth2, ndate);
	
	db.Query(CB_DB_MakeNote, sQuery, client);
}

void DB_GetNote(int client, int target)
{
	if (db == INVALID_HANDLE) {
		LogError("GetNote Failed: Not connected to database!");
		PrintToChat(client, "[AN] Not connected to database!");
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(target, AuthId_Steam3, sAuth, sizeof(sAuth));
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT b.note, b.author, b.authorid, b.ndate FROM notes b WHERE b.steamid = '%s' ORDER BY id;", sAuth);
	
	db.Query(CB_DB_GetNote, sQuery, client);
}

void DB_EraseNote(int client, int target)
{
	if (db == INVALID_HANDLE) {
		LogError("EraseNote Failed: Not connected to database!");
		PrintToChat(client, "[AN] Not connected to database!");
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(target, AuthId_Steam3, sAuth, sizeof(sAuth));
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT b.id FROM notes b WHERE b.steamid = '%s' ORDER BY id;", sAuth);
	
	db.Query(CB_DB_EraseNote, sQuery, client);
}

void DB_PrintNotes(int client, int target)
{
	if (db == INVALID_HANDLE) {
		LogError("PrintNotes Failed: Not connected to database!");
		return;
	}
	
	char sAuth[32];
	GetClientAuthId(target, AuthId_Steam3, sAuth, sizeof(sAuth));
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT b.id FROM notes b WHERE b.steamid = '%s' ORDER BY id;", sAuth);
	
	db.Query(CB_DB_PrintNotes, sQuery, client | (target << 16));
}

public Action Command_makenote(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "Usage: sm_makenote <#userid|name> [note]");
		return Plugin_Handled;
	}
	char arg1[32], notearg[128], rawnote[128];
	
	/* Get the arguments */
	GetCmdArg(1, arg1, sizeof(arg1));
	for (int i = 2; i <= args; i++)
	{
		GetCmdArg(i, notearg, sizeof(notearg));
		if (i != 2)
		{
			Format(rawnote, sizeof(rawnote), "%s %s", rawnote, notearg);
		} else {
			strcopy(rawnote, sizeof(rawnote), notearg);
		}
	}
	
	//get target
	int target = 0;
	target = FindTarget(client, arg1, true, true);
	
	if (target == -1)
	{
		//ReplyToCommand(client, "[AN] Unable to find target.");
		return Plugin_Handled;
	}
	
	
	char note[256];
	EncodeBase64(note, sizeof(note), rawnote);
	
	ReplyToCommand(client, "[AN] Making note");
	DB_MakeNote(client, target, note);
	
	// announce
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (CheckCommandAccess(i, "sm_notes", ADMFLAG_GENERIC, false))
			{
				CPrintToChat(i, "[AN] '{gold}%N{white}' made a note on player '{gold}%N{white}': {green}%s", client, target, rawnote);
			}
		}
	}
	
	return Plugin_Handled;
}

public Action Command_getnote(int client, int args)
{
	notechat[client] = true;
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_notes <#userid|name>");
		return Plugin_Handled;
	} else if (args > 2) {
		char arg3[128];
		GetCmdArg(3, arg3, sizeof(arg3));
		if (StrEqual("menu", arg3))
		{
			notechat[client] = false;
		}
	} else if (args == 1) {
		notechat[client] = false;
	}
	
	char arg1[128], arg2[128];
	
	/* Get the arguments */
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	int iarg2 = StringToInt(arg2);
	
	//get target
	int target = 0;
	target = FindTarget(client, arg1, false, true);
	
	if (target == -1)
	{
		//ReplyToCommand(client, "[AN] Unable to find target.");
		return Plugin_Handled;
	}
	
	notenums[client] = iarg2;
	notetargets[client] = target;
	if (notechat[client] == true)
		ReplyToCommand(client, "[AN] Retrieving note");
	DB_GetNote(client, target);
	
	return Plugin_Handled;
}

public Action Command_listnotes(int client, int args)
{
	ReplyToCommand(client, "[AN] Showing noted players:");
	for (int i = 1; i < MaxClients; i++)
	{
		if (i > 0 && i <= MaxClients && IsClientInGame(i))
		{
			DB_PrintNotes(client, i);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_erasenote(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "Usage: sm_erasenote <#userid|name> [note number]");
		return Plugin_Handled;
	}
	char arg1[32], arg2[32];
	
	/* Get the arguments */
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	int iarg2 = StringToInt(arg2);
	
	//get target
	int target = 0;
	target = FindTarget(client, arg1, false, true);
	
	if (target == -1)
	{
		//ReplyToCommand(client, "[AN] Unable to find target.");
		return Plugin_Handled;
	}
	
	erasenums[client] = iarg2;
	ReplyToCommand(client, "[AN] Erasing note");
	
	// CHECK PERMISSIONS
	AdminId aid = GetUserAdmin(client);
	if (GetAdminFlag(aid, Admin_Root, Access_Effective))
	{
		DB_EraseNote(client, target);
	} else {
		erasetargets[client] = target;
		checkAuth(client);
	}
	
	return Plugin_Handled;
}

void ShowMenu(int client, char[] note, char[] author, char[] authorid, char[] ndate)
{
	Menu menu = new Menu(Menu_Handler);
	menu.SetTitle("Note %i of %i", notenums[client], notemax[client]);
	menu.AddItem("note", note, 1);
	char auths[256], fdate[64];
	Format(auths, sizeof(auths), "Author: %s %s", author, authorid);
	Format(fdate, sizeof(fdate), "Date: %s", ndate);
	menu.AddItem("auth", auths, 1);
	menu.AddItem("date", fdate, 1);
	if (notenums[client] != 1)
	{
		menu.AddItem("prev", "Previous Note");
	} else {
		menu.AddItem("prev", "Previous Note", 1);
	}
	if (notenums[client] != notemax[client])
	{
		menu.AddItem("next", "Next Note");
	} else {
		menu.AddItem("next", "Next Note", 1);
	}
	menu.ExitButton = true;
	menu.Display(client, 120);
}

public int Menu_Handler(Menu MenuHandle, MenuAction action, int client, int num)
{
	if (action == MenuAction_Select)
	{
		if (num == 3)
		{
			ClientCommand(client, "sm_notes #%i %i menu", GetClientUserId(notetargets[client]), notenums[client] - 1);
		} else if (num == 4)
		{
			ClientCommand(client, "sm_notes #%i %i menu", GetClientUserId(notetargets[client]), notenums[client] + 1);
		}
	} else if (action == MenuAction_End)
		delete MenuHandle;
}

public Action Timer_reconnect(Handle timer, int index)
{
	delete db;
	DB_Connect();
} 