#include "osm.h"

#define OSM_FREQ_REG	0x110		/* LUT : une ligne tous les 32 octets */
#define OSM_ROW		32
#define OSM_ROWS	40
#define OSM_DESIRED(n)	(0x920 + 4 * (n))	/* palier demandé, par cœur */
#define OSM_INIT_MHZ	300		/* src == 0 : palier fixe 300 MHz */

static inline uint32_t rd32(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline void wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

static uint32_t row_mhz(uint32_t d)
{
	return (d >> 30) ? (d & 0xff) * 192 / 10 : OSM_INIT_MHZ;	/* lval * 19,2 MHz */
}

int osm_top(uintptr_t base, uint32_t *mhz)
{
	int top = 0;
	uint32_t prev = 0;
	for (int i = 0; i < OSM_ROWS; i++) {
		uint32_t f = row_mhz(rd32(base + OSM_FREQ_REG + i * OSM_ROW));
		if (i && f == prev)	/* comme Linux : la table se termine en se répétant */
			break;
		top = i;
		prev = f;
	}
	*mhz = prev;
	return top;
}

void osm_boost(void)
{
	uint32_t mhz;
	int s = osm_top(OSM_SILVER, &mhz), g = osm_top(OSM_GOLD, &mhz), l = osm_top(OSM_L3, &mhz);
	for (int n = 0; n < 6; n++)
		wr32(OSM_SILVER + OSM_DESIRED(n), s);
	for (int n = 0; n < 2; n++)
		wr32(OSM_GOLD + OSM_DESIRED(n), g);
	wr32(OSM_L3 + OSM_DESIRED(0), l);
	__asm__ volatile("dsb sy" ::: "memory");
}
