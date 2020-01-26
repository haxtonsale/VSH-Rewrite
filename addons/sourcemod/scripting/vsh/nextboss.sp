static ArrayList g_aNextBossMulti;
static bool g_bNextBossSpecialClass;
static TFClassType g_nNextBossSpecialClass;

void NextBoss_Init()
{
	g_aNextBoss = new ArrayList(sizeof(NextBoss));
	g_aNextBossMulti = new ArrayList();
	
	g_ConfigConvar.Create("vsh_boss_chance_saxton", "0.25", "% chance for next boss to be Saxton Hale from normal bosses pool (0.0 - 1.0)", _, true, 0.0, true, 1.0);
	g_ConfigConvar.Create("vsh_boss_chance_multi", "0.20", "% chance for next boss to be multiple bosses (0.0 - 1.0)", _, true, 0.0, true, 1.0);
	g_ConfigConvar.Create("vsh_boss_chance_modifiers", "0.15", "% chance for next boss to have random modifiers (0.0 - 1.0)", _, true, 0.0, true, 1.0);
}

int NextBoss_CreateStruct(int iClient)
{
	int iIndex = g_aNextBoss.FindValue(iClient, 1);	//assuming iClient is at 1 pos of struct
	if (iIndex >= 0)
	{
		NextBoss nextBoss;
		g_aNextBoss.GetArray(iIndex, nextBoss);
		return nextBoss.iId;
	}
	
	g_iNextBossId++;
	
	NextBoss nextBoss;
	nextBoss.iId = g_iNextBossId;
	nextBoss.iClient = iClient;
	nextBoss.sBossType = NULL_STRING;
	nextBoss.sModifierType = NULL_STRING;
	
	g_aNextBoss.PushArray(nextBoss);
	return g_iNextBossId;
}

bool NextBoss_GetStruct(int iId, NextBoss nextBoss)
{
	int iIndex = g_aNextBoss.FindValue(iId, 0);	//assuming iId is at 0 pos of struct
	if (iIndex < 0)
		return false;
	
	g_aNextBoss.GetArray(iIndex, nextBoss);
	return true;
}

void NextBoss_SetStruct(NextBoss nextBoss)
{
	int iIndex = g_aNextBoss.FindValue(nextBoss.iId, 0);	//assuming iId is at 0 pos of struct
	if (iIndex >= 0)
		g_aNextBoss.SetArray(iIndex, nextBoss);
}

void NextBoss_Delete(SaxtonHaleNextBoss nextBoss)
{
	int iIndex = g_aNextBoss.FindValue(nextBoss, 0);	//assuming iId is at 0 pos of struct
	if (iIndex >= 0)
		g_aNextBoss.Erase(iIndex);
}

void NextBoss_DeleteClient(int iClient)
{
	int iIndex = g_aNextBoss.FindValue(iClient, 1);	//assuming iClient is at 1 pos of struct
	if (iIndex >= 0)
		g_aNextBoss.Erase(iIndex);
}

void NextBoss_SetSpecialClass(TFClassType nClass)
{
	g_bNextBossSpecialClass = true;
	g_nNextBossSpecialClass = nClass;
}

void NextBoss_SetNextBoss()
{
	//Get every non-specs and randomize incase we have to pick random player
	ArrayList aClients = new ArrayList();
	for (int iClient = 1; iClient <= MaxClients; iClient++)
		if (IsClientInGame(iClient) && TF2_GetClientTeam(iClient) > TFTeam_Spectator)
			aClients.Push(iClient);
	
	aClients.Sort(Sort_Random, Sort_Integer);
	
	bool bForceSet;
	int iMainBoss;
	
	//Check if there any client bosses force set for this round
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient))
		{
			SaxtonHaleNextBoss nextBoss = SaxtonHaleNextBoss(iClient);
			if (nextBoss.bForceNext)
			{
				NextBoss_SetBoss(nextBoss, aClients);
				bForceSet = true;
			}
		}
	}
	
	//If there no force set, pick one from highest queue
	if (!bForceSet)
	{
		iMainBoss = NextBoss_GetNextClient(aClients);
		ArrayList aMultiBoss;
		
		//Roll for multi boss
		if (Preferences_Get(iMainBoss, Preferences_MultiBoss)
			&& GetRandomFloat(0.0, 1.0) <= g_ConfigConvar.LookupFloat("vsh_boss_chance_multi")
			&& (aMultiBoss = NextBoss_GetRandomMulti()))
		{
			int iRank = 1;
			int iMultiBossLength = aMultiBoss.Length;
			for (int i = 0; i < iMultiBossLength; i++)
			{
				int iClient = -1;
				while (iClient == -1)
				{
					iClient = NextBoss_GetNextClient(aClients, iRank);
					
					if (!Preferences_Get(iClient, Preferences_MultiBoss))
					{
						//Client dont want to play as multi boss, skip
						iClient = -1;
						iRank++;
					}
					else
					{
						//Set client to play as multi boss
						SaxtonHaleNextBoss nextBoss = SaxtonHaleNextBoss(iClient);
						
						char sBossType[MAX_TYPE_CHAR];
						aMultiBoss.GetString(i, sBossType, sizeof(sBossType));
						
						nextBoss.SetBoss(sBossType);
						NextBoss_SetBoss(nextBoss, aClients);
					}
				}
			}
		}
		else
		{
			//Set client to play as normal boss
			SaxtonHaleNextBoss nextBoss = SaxtonHaleNextBoss(iMainBoss);
			NextBoss_SetBoss(nextBoss, aClients);
		}
	}
	else
	{
		//Fill any boss for next round, but with missing client
		int iLength = g_aNextBoss.Length;
		for (int i = 0; i < iLength; i++)
		{
			NextBoss nextStruct;
			g_aNextBoss.GetArray(i, nextStruct);
			
			if (!nextStruct.bForceNext)
				continue;
			
			nextStruct.iClient = NextBoss_GetNextClient(aClients);
			g_aNextBoss.SetArray(i, nextStruct);
			
			SaxtonHaleNextBoss nextBoss = SaxtonHaleNextBoss(nextStruct.iClient);
			NextBoss_SetBoss(nextBoss, aClients);
		}
	}
	
	delete aClients;
	
	//Get amount of valid bosses after set
	int iBosses = 0;
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (SaxtonHale_IsValidBoss(iClient, false))
		{
			iBosses++;
			
			if (!iMainBoss)
				iMainBoss = iClient;
		}
	}
	
	if (iBosses == 0)
	{
		//Still empty after setting boss...
		PluginStop(true, "[VSH] NO BOSSES AFTER ATTEMPTED TO SET ONE!!!!");
		return;
	}
	
	//Cut down health, incase there more than 1 bosses
	float flHealthMulti = 1.0 / float(iBosses);
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		SaxtonHaleBase boss = SaxtonHaleBase(iClient);
		if (IsClientInGame(iClient) && boss.bValid && !boss.bMinion)
		{
			boss.flHealthMultiplier *= flHealthMulti;
			int iHealth = boss.CallFunction("CalculateMaxHealth");
			boss.iMaxHealth = iHealth;
			boss.iHealth = iHealth;
		}
	}
	
	if (g_bNextBossSpecialClass || g_nNextBossSpecialClass != TFClass_Unknown)
	{
		if (g_nNextBossSpecialClass == TFClass_Unknown)
			g_nNextBossSpecialClass = view_as<TFClassType>(GetRandomInt(1, sizeof(g_strClassName)-1));
		
		ClassLimit_SetSpecialRound(g_nNextBossSpecialClass);
		PrintToChatAll("%s%s SPECIAL ROUND: %N versus %s", TEXT_TAG, TEXT_COLOR, iMainBoss, g_strClassName[g_nNextBossSpecialClass]);
		
		g_bNextBossSpecialClass = false;
		g_nNextBossSpecialClass = TFClass_Unknown;
	}
	else	//If not, disable special round
	{
		ClassLimit_SetSpecialRound(TFClass_Unknown);
	}

	//Create timer to play round start sound
	int iRoundTime = tf_arena_preround_time.IntValue;
	float flPickBossTime = float(iRoundTime)-7.0;
	CreateTimer(flPickBossTime, Timer_RoundStartSound, iMainBoss);
}

int NextBoss_GetNextClient(ArrayList aClients, int iRank = 1)
{
	int iClient = Queue_GetPlayerFromRank(iRank);
	if (0 < iClient <= MaxClients && IsClientInGame(iClient))
		return iClient;
	
	if (aClients.Length > 0)
	{
		PrintToChatAll("%s%s Unable to find player in queue to become boss! %sPicking random player...", TEXT_TAG, TEXT_ERROR, TEXT_COLOR);
		return aClients.Get(0);
	}
	
	PluginStop(true, "[VSH] FAILED TO FIND CLIENT TO SET BOSS!!!!");
	return 0;
}

void NextBoss_SetBoss(SaxtonHaleNextBoss nextBoss, ArrayList aClients)
{
	//Fill random boss and not modifier if not set
	char sBossType[MAX_TYPE_CHAR], sModifierType[MAX_TYPE_CHAR];
	nextBoss.GetBoss(sBossType, sizeof(sBossType));
	nextBoss.GetModifier(sModifierType, sizeof(sModifierType));
	
	if (StrEmpty(sBossType))
		NextBoss_GetRandomNormal(sBossType, sizeof(sBossType));
	
	if (StrEmpty(sModifierType))
		NextBoss_GetRandomModifiers(sModifierType, sizeof(sModifierType));
	
	// Allow them to join the boss team
	Client_AddFlag(nextBoss.iClient, ClientFlags_BossTeam);
	TF2_ForceTeamJoin(nextBoss.iClient, TFTeam_Boss);
	
	SaxtonHaleBase boss = SaxtonHaleBase(nextBoss.iClient);
	boss.CallFunction("CreateBoss", sBossType);
	
	//Give every bosses able to scare scout by default
	CScareRage scareAbility = boss.CallFunction("FindAbility", "CScareRage");
	if (scareAbility == INVALID_ABILITY) //If boss don't have scare rage ability, give him one
		scareAbility = boss.CallFunction("CreateAbility", "CScareRage");
	
	scareAbility.nSetClass = TFClass_Scout;
	scareAbility.flRadiusClass = 800.0;
	scareAbility.iStunFlagsClass = TF_STUNFLAGS_SMALLBONK;
	
	//Select Modifiers
	if (!StrEqual(sModifierType, "CModifiersNone") && !StrEmpty(sModifierType))
		boss.CallFunction("CreateModifiers", sModifierType);
	
	TF2_RespawnPlayer(nextBoss.iClient);
	
	//Display to client what boss you are for 10 seconds
	MenuBoss_DisplayInfo(nextBoss.iClient, sBossType, 10);
	
	//Enable special round if triggered
	if (nextBoss.bSpecialClassRound)
	{
		if (nextBoss.nSpecialClassType == TFClass_Unknown && g_nNextBossSpecialClass == TFClass_Unknown)
			g_nNextBossSpecialClass = view_as<TFClassType>(GetRandomInt(1, sizeof(g_strClassName)-1));
		else if (nextBoss.nSpecialClassType != TFClass_Unknown)
			g_nNextBossSpecialClass = nextBoss.nSpecialClassType;
	}

	//Reset player queue
	Queue_ResetPlayer(nextBoss.iClient);
	int iIndex = aClients.FindValue(nextBoss.iClient);
	if (iIndex >= MaxClients)
		aClients.Erase(iIndex);
	
	//Clear next boss data
	NextBoss_Delete(nextBoss);
}

stock void NextBoss_AddMulti(ArrayList aBosses)
{
	g_aNextBossMulti.Push(aBosses);
}

stock void NextBoss_RemoveMulti(const char[] sBoss)
{
	int iLength = g_aNextBossMulti.Length;
	for (int i = 0; i < iLength; i++)
	{
		ArrayList aMultiBoss = g_aNextBossMulti.Get(i);
		
		int iMultiLength = aMultiBoss.Length;
		for (int j = iMultiLength-1; j >= 0; j--)
		{
			char sMultiBoss[MAX_TYPE_CHAR];
			aMultiBoss.GetString(j, sMultiBoss, sizeof(sMultiBoss));
			
			if (StrEqual(sMultiBoss, sBoss))
			{
				aMultiBoss.Erase(j);
				
				//Check if 1 or less bosses in list, if so delet
				if (aMultiBoss.Length <= 1)
				{
					delete aMultiBoss;
					g_aNextBossMulti.Erase(i);
				}
				
				return;
			}
		}
	}
}

stock void NextBoss_GetRandomNormal(char[] sBoss, int iLength)
{
	//Saxton Hale get higher chance to appear
	if (GetRandomFloat(0.0, 1.0) <= g_ConfigConvar.LookupFloat("vsh_boss_chance_saxton"))
	{
		Format(sBoss, iLength, "CSaxtonHale");
		return;
	}
	
	//Get list of all bosses
	ArrayList aBosses = FuncClass_GetAllType(VSHClassType_Boss);
	
	//Delet multi boss
	int iBossLength = g_aNextBossMulti.Length;
	for (int i = 0; i < iBossLength; i++)
	{
		ArrayList aMultiBoss = g_aNextBossMulti.Get(i);
		
		int iMultiLength = aMultiBoss.Length;
		for (int j = 0; j < iMultiLength; j++)
		{
			char sMultiBoss[MAX_TYPE_CHAR];
			aMultiBoss.GetString(j, sMultiBoss, sizeof(sMultiBoss));
			
			int iIndex = aBosses.FindString(sMultiBoss);
			if (iIndex >= 0)
				aBosses.Erase(iIndex);
		}
	}
	
	//Delet saxton hale
	int iIndex = aBosses.FindString("CSaxtonHale");
	if (iIndex >= 0)
		aBosses.Erase(iIndex);
	
	//Delet hidden bosses
	iBossLength = aBosses.Length;
	for (int i = iBossLength-1; i >= 0; i--)
		if (NextBoss_IsBossHidden(aBosses, i))
			aBosses.Erase(i);
	
	iBossLength = aBosses.Length;
	if (iBossLength == 0)
	{
		delete aBosses;
		PluginStop(true, "[VSH] NO BOSS IN LIST TO SELECT RANDOM!!!!");
		return;
	}
	
	aBosses.GetString(GetRandomInt(0, iBossLength-1), sBoss, iLength);
	delete aBosses;
}

stock ArrayList NextBoss_GetRandomMulti()
{
	//Count players with duo prefs
	int iPlayersDuo = 0;
	for (int iClient = 1; iClient <= MaxClients; iClient++)
		if (IsClientInGame(iClient) && TF2_GetClientTeam(iClient) > TFTeam_Spectator && Preferences_Get(iClient, Preferences_PickAsBoss) && Preferences_Get(iClient, Preferences_MultiBoss))
			iPlayersDuo++;
	
	ArrayList aClone = g_aNextBossMulti.Clone();
	aClone.Sort(Sort_Random, Sort_Integer);
	
	while (aClone.Length)
	{
		ArrayList aMultiBoss = aClone.Get(0);
		
		int iLength = aMultiBoss.Length;
		if (iPlayersDuo >= iLength)
		{
			// Check if hidden boss
			bool bHidden = false;
			for (int i = 0; i < iLength; i++)
			{
				if (NextBoss_IsBossHidden(aMultiBoss, i))
				{
					bHidden = true;
					aClone.Erase(0);
					break;
				}
			}
			
			if (!bHidden)
			{
				delete aClone;
				return aMultiBoss;
			}
		}
		else
		{
			//Not enough players for this multi
			aClone.Erase(0);
		}
	}
	
	//No valid multi-boss to pick
	delete aClone;
	return null;
}

stock bool NextBoss_IsBossHidden(ArrayList aList, int iIndex)
{
	char sBuffer[MAX_TYPE_CHAR];
	aList.GetString(iIndex, sBuffer, sizeof(sBuffer));
	
	SaxtonHaleBase boss = SaxtonHaleBase(0);
	boss.CallFunction("SetBossType", sBuffer);
	return boss.CallFunction("IsBossHidden");
}

stock int NextBoss_GetRandomModifiers(char[] sModifiers, int iLength, bool bForce = false)
{
	if (bForce || GetRandomFloat(0.0, 1.0) <= g_ConfigConvar.LookupFloat("vsh_boss_chance_modifiers"))
	{
		//Get list of every non-hidden modifiers to select random
		ArrayList aModifiers = FuncClass_GetAllType(VSHClassType_Modifier);
		int iArrayLength = aModifiers.Length;
		for (int iModifiers = iArrayLength-1; iModifiers >= 0; iModifiers--)
		{
			char sModifiersType[MAX_TYPE_CHAR];
			aModifiers.GetString(iModifiers, sModifiersType, sizeof(sModifiersType));
			
			SaxtonHaleBase boss = SaxtonHaleBase(0);
			boss.CallFunction("SetModifiersType", sModifiersType);
			if (boss.CallFunction("IsModifiersHidden"))
				aModifiers.Erase(iModifiers);
		}
		
		iArrayLength = aModifiers.Length;
		if (iArrayLength == 0)
		{
			delete aModifiers;
			PluginStop(true, "[VSH] NO MODIFIERS IN LIST TO SELECT RANDOM!!!!");
			return;
		}
		
		//Randomizer and set modifiers
		aModifiers.GetString(GetRandomInt(0, iArrayLength-1), sModifiers, iLength);
		delete aModifiers;
	}
	else
	{
		Format(sModifiers, iLength, "CModifiersNone");
	}
}