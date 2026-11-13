/* Banc d'essai hôte du pilote Synaptics TCM : une fausse puce rejoue le protocole. */
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#define TOUCH_MAX 10u
#define SPEN_SLOT (TOUCH_MAX - 1u)
#define TOUCH_GPIO_IO(n) ((n) * 0x1000u + 4u)
static struct { unsigned long gpio; } st;
static unsigned touch_rd(unsigned long b, unsigned o){(void)b;(void)o;return 0;}
static int hid_id=-1, hid_down=-1, hid_x, hid_y;
static void sweet_hid_touch(int f,int d,int x,int y){hid_id=f;hid_down=d;hid_x=x;hid_y=y;}
static uint8_t dev[1024]; static unsigned dev_len, dev_pos; static int dev_has;
static uint8_t q[8][300]; static unsigned ql[8], qn, qh; /* file de messages : code + charge */
static uint8_t qc[8];
static void push(uint8_t code, const uint8_t *p, unsigned n){ qc[qn]=code; memcpy(q[qn],p,n); ql[qn++]=n; }
static unsigned last_cmd;
static int reported_mask; static int rx[10], ry[10];
static void touch_wait(unsigned ms){(void)ms;}
static void touch_report(uint32_t m, const int *x, const int *y){ reported_mask=m; for(int i=0;i<10;i++){rx[i]=x[i];ry[i]=y[i];} }
/* fausse puce : une lecture d'en-tête sert le prochain message, les lectures continuées sa charge */
static unsigned cur, cur_len, cur_off; static int in_msg;
static int touch_msg(uint8_t addr, const uint8_t *tx, unsigned nt, uint8_t *rxb, unsigned nr, bool stretch){
	(void)addr;(void)stretch;
	if (nt > 3 || nr > 90) return EIO;
	if (nt){ last_cmd = tx[0]; return 0; }
	if (!in_msg){
		if (qh>=qn){ memset(rxb,0,nr); return 0; }  /* rien : pas de marqueur */
		cur=qh++; cur_len=ql[cur]; cur_off=0; in_msg = cur_len>0;
		rxb[0]=0xa5; rxb[1]=qc[cur]; rxb[2]=cur_len&0xff; rxb[3]=cur_len>>8; return 0;
	}
	rxb[0]=0xa5; rxb[1]=0x03;
	for (unsigned i=0;i<nr-2;i++){ rxb[2+i] = cur_off<cur_len ? q[cur][cur_off] : 0x5a; cur_off++; }
	if (cur_off >= cur_len+1) in_msg=0;
	return 0;
}
#include "syna_block.c" /* extrait de bsd/dev/sweet_touch.c après le patch 0078 : tests/run.sh */
static void putbits(uint8_t *b, unsigned *off, unsigned v, unsigned bits){ for(unsigned i=0;i<bits;i++,(*off)++) if((v>>i)&1) b[*off/8] |= 1<<(*off%8); }
int main(void){
	uint8_t id[] = {0x02, 0x01, 0, 0};                      /* identify : mode application */
	uint8_t app[200] = {0};                                 /* > 88 octets : force 3 lectures continuées */
	app[32]=0x9f; app[33]=0x04;  /* max_x 1183 */  app[34]=0xcf; app[35]=0x07; /* max_y 1999 */ app[36]=10;
	uint8_t cfg[] = {24,8, 1, 6,4, 7,4, 8,12, 9,12, 3, 0};  /* NUM_ACTIVE ; pour chaque actif : index, classe, x, y */
	push(0x10,id,sizeof id); push(0x01,app,sizeof app); push(0x01,cfg,sizeof cfg);
	bool ok = syna_start();
	printf("start=%d max=%ux%u objets=%u cfg=%u\n", ok, syna.max_x, syna.max_y, syna.max_objects, syna.cfg_len);
	uint8_t rep[16]={0}; unsigned off=0;
	putbits(rep,&off,2,8);                      /* 2 contacts */
	putbits(rep,&off,0,4); putbits(rep,&off,1,4); putbits(rep,&off,100,12); putbits(rep,&off,200,12);
	putbits(rep,&off,3,4); putbits(rep,&off,1,4); putbits(rep,&off,1183,12); putbits(rep,&off,1999,12);
	push(0x11,rep,(off+7)/8);
	int e = touch_synaptics();
	printf("rapport err=%d masque=%#x  doigt0=(%d,%d)  doigt3=(%d,%d)\n", e, reported_mask, rx[0],ry[0], rx[3],ry[3]);
	uint8_t lift[2]={0}; push(0x11,lift,1);
	e = touch_synaptics(); printf("lever err=%d masque=%#x\n", e, reported_mask);
	e = touch_synaptics(); printf("rien en attente err=%d masque=%#x\n", e, reported_mask);
	/* S Pen : digitaliseur 0..max, Y inversé puis X/Y échangés (DT <0 1 1>) */
	struct spen_info in = {15000, 9000, 4095, false, true, true};
	uint8_t pk[17] = {0x91, 0, 0, 0, 0, 0x08, 0x00};      /* coordonnées, à portée, pointe appuyée */
	int x, y; unsigned p;
	int d = spen_decode(pk, &in, &x, &y, &p);          /* x=0,y=0 -> y inversé = 9000 -> échange */
	printf("spen coin: down=%d x=%d y=%d pression=%u\n", d, x, y, p);
	pk[1]=0x3a; pk[2]=0x98; pk[3]=0x23; pk[4]=0x28;        /* x=15000 y=9000 */
	pk[0]=0x81;                                            /* à portée, pointe levée */
	d = spen_decode(pk, &in, &x, &y, &p);
	printf("spen autre coin: down=%d x=%d y=%d\n", d, x, y);
	pk[0]=0x0d; printf("spen non-coordonnées: %d\n", spen_decode(pk, &in, &x, &y, &p));
	return !(ok && reported_mask==0);
}
