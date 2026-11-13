#pragma once
#include <stdint.h>

/* Contrôleur de fréquence Qualcomm OSM (SM7125 atoll), registres d'après le
 * pilote clk-cpu-osm du noyau Samsung SM7125 (GPL). */
#define OSM_L3		0x18321000UL
#define OSM_SILVER	0x18323000UL	/* cœurs 0-5, Cortex-A55 */
#define OSM_GOLD	0x18325800UL	/* cœurs 6-7, Cortex-A76 */

/* Dernier palier distinct de la LUT ; *mhz reçoit sa fréquence. */
int osm_top(uintptr_t base, uint32_t *mhz);
/* Demande le palier max aux 8 cœurs et au L3 (le firmware gère la tension). */
void osm_boost(void);
