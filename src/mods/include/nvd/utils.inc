#if defined _nvd_utils_included
 #endinput
#endif
#define _nvd_utils_included

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <nvd/core>
#include <nvd/strings>

/* -------------------------- smlib replacements (old-syntax compat) -------------------------- */

/**
 * Gets the active weapon entity index of a client.
 */
stock int Client_GetActiveWeapon(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
}

/**
 * Gets the classname of the active weapon.
 */
stock int Client_GetActiveWeaponName(int client, char[] buffer, int size)
{
	int weapon = Client_GetActiveWeapon(client);
	if (weapon <= 0 || !IsValidEdict(weapon)) {
		buffer[0] = '\0';
		return 0;
	}
	GetEdictClassname(weapon, buffer, size);
	return weapon;
}

/**
 * Sets the active weapon of a client.
 * Silently ignores invalid weapon entities.
 */
stock void Client_SetActiveWeapon(int client, int weapon)
{
	if (weapon > 0 && IsValidEntity(weapon))
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
}

/**
 * Sets the armor value of a client.
 */
stock void Client_SetArmor(int client, int value)
{
	SetEntProp(client, Prop_Send, "m_ArmorValue", value);
}

/**
 * Gets the primary clip count of a weapon.
 */
stock int Weapon_GetPrimaryClip(int weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iClip1");
}

/**
 * Sets the primary clip count of a weapon.
 */
stock void Weapon_SetPrimaryClip(int weapon, int value)
{
	SetEntProp(weapon, Prop_Send, "m_iClip1", value);
}

/**
 * Equips a weapon to a client.
 * @param switchTo  If true, switch to this weapon after equipping.
 */
stock void Client_EquipWeapon(int client, int weapon, bool switchTo=false)
{
	EquipPlayerWeapon(client, weapon);
	if (switchTo) {
		Client_SetActiveWeapon(client, weapon);
	}
}

/**
 * Removes all weapons from a client by iterating m_hMyWeapons.
 */
stock void Client_RemoveAllWeapons(int client)
{
	int offset = FindDataMapInfo(client, "m_hMyWeapons") - 4;
	for (int i = 0; i < 48; i++) {
		offset += 4;
		int weapon = GetEntDataEnt2(client, offset);
		if (weapon > 0 && IsValidEdict(weapon)) {
			char cls[64];
			GetEdictClassname(weapon, cls, sizeof(cls));
			if (StrContains(cls, "weapon_") == 0) {
				RemovePlayerItem(client, weapon);
				AcceptEntityInput(weapon, "kill");
			}
		}
	}
}

/**
 * Gives a weapon to a client.
 * @param switchTo  If true, switch to this weapon after giving.
 * @return          Weapon entity index or -1 on failure.
 */
stock int Client_GiveWeapon(int client, const char[] className, bool switchTo=true)
{
	int weapon = GivePlayerItem(client, className);
	if (weapon != -1 && switchTo) {
		Client_SetActiveWeapon(client, weapon);
	}
	return weapon;
}

/**
 * Gets a client's weapon by slot index.
 * Wrapper around GetPlayerWeaponSlot().
 */
stock int Client_GetWeaponBySlot(int client, int slot)
{
	return GetPlayerWeaponSlot(client, slot);
}

/**
 * Finds a weapon entity index by classname on a client.
 */
stock int Client_GetWeaponByClassname(int client, const char[] className)
{
	int offset = FindDataMapInfo(client, "m_hMyWeapons") - 4;
	for (int i = 0; i < 48; i++) {
		offset += 4;
		int weapon = GetEntDataEnt2(client, offset);
		if (weapon > 0 && IsValidEdict(weapon)) {
			char weaponClass[64];
			GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
			if (StrEqual(weaponClass, className)) {
				return weapon;
			}
		}
	}
	return -1;
}

/**
 * Sets the clip ammo for a weapon by classname.
 */
stock bool Client_SetWeaponClipAmmo(int client, const char[] className, int primaryClip=-1, int secondaryClip=-1)
{
	int weapon = Client_GetWeaponByClassname(client, className);
	if (weapon == -1) return false;

	if (primaryClip != -1) {
		SetEntProp(weapon, Prop_Send, "m_iClip1", primaryClip);
	}
	if (secondaryClip != -1) {
		SetEntProp(weapon, Prop_Send, "m_iClip2", secondaryClip);
	}
	return true;
}

/**
 * Gets the player's carried ammo for a weapon by classname.
 */
stock bool Client_GetWeaponPlayerAmmo(int client, const char[] className, int &primaryAmmo=-1, int &secondaryAmmo=-1)
{
	int weapon = Client_GetWeaponByClassname(client, className);
	if (weapon == -1) return false;

	int offset_ammo = FindDataMapInfo(client, "m_iAmmo");

	if (primaryAmmo != -1) {
		int offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
		primaryAmmo = GetEntData(client, offset);
	}
	if (secondaryAmmo != -1) {
		int offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
		secondaryAmmo = GetEntData(client, offset);
	}
	return true;
}

/**
 * Sets the player's carried ammo for a weapon by classname.
 */
stock bool Client_SetWeaponPlayerAmmo(int client, const char[] className, int primaryAmmo=-1, int secondaryAmmo=-1)
{
	int weapon = Client_GetWeaponByClassname(client, className);
	if (weapon == -1) return false;

	int offset_ammo = FindDataMapInfo(client, "m_iAmmo");

	if (primaryAmmo != -1) {
		int offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
		SetEntData(client, offset, primaryAmmo, 4, true);
	}
	if (secondaryAmmo != -1) {
		int offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
		SetEntData(client, offset, secondaryAmmo, 4, true);
	}
	return true;
}

/**
 * Translates a CS:S location token (e.g., "BombsiteA") to its localized name.
 */
stock void GetLocationName(const char[] token, char[] buffer, int size)
{
	if (GetFeatureStatus(FeatureType_Native, "NVD_GetStr") == FeatureStatus_Available) {
		NVD_GetStr("nvd_bot_chat", "locations", token, buffer, size, token);
		return;
	}
	strcopy(buffer, size, token);
}
