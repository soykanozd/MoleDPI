// SPDX-License-Identifier: GPL-3.0-only
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "../vendor/byedpi/moledpi_quic.h"
int main(void) {
 unsigned char b[1300]={0}; b[0]=0xc0;b[4]=1;b[5]=8;b[16]=0x44;b[17]=0x9e;
 assert(moledpi_quic_initial(b,1200));assert(!moledpi_quic_initial(b,1199));
 b[0]=0xd0;b[1]=0x6b;b[2]=0x33;b[3]=0x43;b[4]=0xcf;assert(moledpi_quic_initial(b,1200));
 b[5]=21;assert(!moledpi_quic_initial(b,1200));b[5]=8;b[15]=0xff;assert(!moledpi_quic_initial(b,1200));
 unsigned state=71;
 for (int k=0;k<10000;k++) { for(size_t i=0;i<sizeof b;i++){state=state*1664525+1013904223;b[i]=(unsigned char)(state>>24);} (void)moledpi_quic_initial(b,(size_t)k%1300); }
 puts("PASS QUIC gate: v1/v2, bounds, malformed tokens and fuzzed input");
}
