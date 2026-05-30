#if defined _nvd_utils_included
 #endinput
#endif
#define _nvd_utils_included

#include <sourcemod>
#include <sdktools>
#include <cstrike>

/* -------------------------- smlib replacements (old-syntax compat) -------------------------- */

/**
 * Gets the active weapon entity index of a client.
 */
stock Client_GetActiveWeapon(client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
}

/**
 * Gets the classname of the active weapon.
 */
stock Client_GetActiveWeaponName(client, String:buffer[], size)
{
	new weapon = Client_GetActiveWeapon(client);
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
stock Client_SetActiveWeapon(client, weapon)
{
	if (weapon > 0 && IsValidEntity(weapon))
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
}

/**
 * Sets the armor value of a client.
 */
stock Client_SetArmor(client, value)
{
	SetEntProp(client, Prop_Send, "m_ArmorValue", value);
}

/**
 * Gets the primary clip count of a weapon.
 */
stock Weapon_GetPrimaryClip(weapon)
{
	return GetEntProp(weapon, Prop_Send, "m_iClip1");
}

/**
 * Sets the primary clip count of a weapon.
 */
stock Weapon_SetPrimaryClip(weapon, value)
{
	SetEntProp(weapon, Prop_Send, "m_iClip1", value);
}

/**
 * Equips a weapon to a client.
 * @param switchTo  If true, switch to this weapon after equipping.
 */
stock Client_EquipWeapon(client, weapon, bool:switchTo=false)
{
	EquipPlayerWeapon(client, weapon);
	if (switchTo) {
		Client_SetActiveWeapon(client, weapon);
	}
}

/**
 * Removes all weapons from a client by iterating m_hMyWeapons.
 */
stock Client_RemoveAllWeapons(client)
{
	new offset = FindDataMapInfo(client, "m_hMyWeapons") - 4;
	for (new i = 0; i < 48; i++) {
		offset += 4;
		new weapon = GetEntDataEnt2(client, offset);
		if (weapon > 0 && IsValidEdict(weapon)) {
			decl String:cls[64];
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
stock Client_GiveWeapon(client, const String:className[], bool:switchTo=true)
{
	new weapon = GivePlayerItem(client, className);
	if (weapon != -1 && switchTo) {
		Client_SetActiveWeapon(client, weapon);
	}
	return weapon;
}

/**
 * Gets a client's weapon by slot index.
 * Wrapper around GetPlayerWeaponSlot().
 */
stock Client_GetWeaponBySlot(client, slot)
{
	return GetPlayerWeaponSlot(client, slot);
}

/**
 * Sets the clip ammo for a weapon by classname.
 */
stock bool:Client_SetWeaponClipAmmo(client, const String:className[], primaryClip=-1, secondaryClip=-1)
{
	new weapon = Client_GetWeaponByClassname(client, className);
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
 * @param primaryAmmo   Receives primary ammo count (pass -1 to skip).
 * @param secondaryAmmo Receives secondary ammo count (pass -1 to skip).
 */
stock bool:Client_GetWeaponPlayerAmmo(client, const String:className[], &primaryAmmo=-1, &secondaryAmmo=-1)
{
	new weapon = Client_GetWeaponByClassname(client, className);
	if (weapon == -1) return false;

	new offset_ammo = FindDataMapInfo(client, "m_iAmmo");

	if (primaryAmmo != -1) {
		new offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
		primaryAmmo = GetEntData(client, offset);
	}
	if (secondaryAmmo != -1) {
		new offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
		secondaryAmmo = GetEntData(client, offset);
	}
	return true;
}

/**
 * Sets the player's carried ammo for a weapon by classname.
 * @param primaryAmmo   Primary ammo count to set (pass -1 to skip).
 * @param secondaryAmmo Secondary ammo count to set (pass -1 to skip).
 */
stock bool:Client_SetWeaponPlayerAmmo(client, const String:className[], primaryAmmo=-1, secondaryAmmo=-1)
{
	new weapon = Client_GetWeaponByClassname(client, className);
	if (weapon == -1) return false;

	new offset_ammo = FindDataMapInfo(client, "m_iAmmo");

	if (primaryAmmo != -1) {
		new offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType") * 4);
		SetEntData(client, offset, primaryAmmo, 4, true);
	}
	if (secondaryAmmo != -1) {
		new offset = offset_ammo + (GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoType") * 4);
		SetEntData(client, offset, secondaryAmmo, 4, true);
	}
	return true;
}

/**
 * Finds a weapon entity index by classname on a client.
 */
stock Client_GetWeaponByClassname(client, const String:className[])
{
	new offset = FindDataMapInfo(client, "m_hMyWeapons") - 4;
	for (new i = 0; i < 48; i++) {
		offset += 4;
		new weapon = GetEntDataEnt2(client, offset);
		if (weapon > 0 && IsValidEdict(weapon)) {
			decl String:weaponClass[64];
			GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));
			if (StrEqual(weaponClass, className)) {
				return weapon;
			}
		}
	}
	return -1;
}
