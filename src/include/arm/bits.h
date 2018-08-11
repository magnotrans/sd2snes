/* A few simple macros for bit-handling on a Cortex M3 */
/* Written in 2010 by Ingo Korb                        */
#ifndef _ARM_BITS_H
#define _ARM_BITS_H

/* The classic macro */
#define BV(x) (1<<(x))

/* CM3 bit-band access macro - no error checks! */
#define BITBAND(addr,bit) \
  (*((volatile unsigned long *)( \
     ((unsigned long)&(addr) & 0x01ffffff)*32 + \
     (bit)*4 + 0x02000000 + ((unsigned long)&(addr) & 0xfe000000)       \
  )))

#endif
