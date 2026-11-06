/* MoleDPI addition: conservative QUIC v1/v2 Initial gate. SPDX-License-Identifier: GPL-3.0-only */
#include <stddef.h>
#include <stdint.h>
static int moledpi_varint(const unsigned char *b, size_t n, size_t *at, uint64_t *value) {
    if (*at >= n) return 0;
    size_t width = (size_t)1 << (b[*at] >> 6);
    if (width > n-*at) return 0;
    *value = b[(*at)++] & 63;
    for (size_t i=1; i<width; ++i) *value = (*value<<8) | b[(*at)++];
    return 1;
}
static int moledpi_quic_initial(const unsigned char *b, size_t n) {
    if (n < 1200 || n > 65535 || (b[0] & 0xc0) != 0xc0) return 0;
    unsigned v = ((unsigned)b[1]<<24)|((unsigned)b[2]<<16)|((unsigned)b[3]<<8)|b[4];
    if (!((v == 1 && (b[0] & 0x30) == 0) || (v == 0x6b3343cf && (b[0] & 0x30) == 0x10))) return 0;
    size_t at=5;
    if (b[at]<8 || b[at]>20 || at+1+b[at]>=n) return 0;
    at+=1+b[at];
    if (b[at]>20 || at+1+b[at]>=n) return 0;
    at+=1+b[at];
    uint64_t token, packet;
    if (!moledpi_varint(b,n,&at,&token) || token>n-at) return 0;
    at+=(size_t)token;
    if (!moledpi_varint(b,n,&at,&packet) || packet<17 || packet>n-at) return 0;
    return 1;
}
