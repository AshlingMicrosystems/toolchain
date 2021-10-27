#include <stdio.h>

void
custom_insn ()
{
  asm (".insn r 0x63, 0x2, 0x5, x3, x4, x5" ::: "memory");
  asm (".insn i 0x7b, 0x1, x3, x4, 18" ::: "memory");
  asm (".insn i 0x5b, 0x5, x7, x8, 25" ::: "memory");
  asm (".insn s 0x67, 0x5, x9, 17(x10)" ::: "memory");
  asm (".insn j 0x73, x11, 14" ::: "memory");
  asm (".insn u 0x5b, x12, 15" ::: "memory");
  asm (".insn b 0x1f, 0x5, x13, x14, 1f\n"
          "nop\n"
          "nop\n"
          "1:\n"
          "nop"  ::: "memory");

  asm (".insn cr 0x2, 0x9, x1, x2" ::: "memory");
  asm (".insn ci 0x1, 0x0, x3, 14" ::: "memory");
  asm (".insn css 0x2, 0x6, x4, 15" ::: "memory");
  asm (".insn ciw 0x0, 0x0, x8, 16" ::: "memory");
  asm (".insn cl 0x0, 0x6, x9, 6(x11)" ::: "memory");
  asm (".insn cs 0x1, 0x4, x9, 5(x10)" ::: "memory");
  asm (".insn cb 0x1, 0x6, x9, 8" ::: "memory");
  asm (".insn cj 0x1, 0x5, 92" ::: "memory");
}

int
main ()
{
  printf ("Hello World\n");
  return 0;
}
