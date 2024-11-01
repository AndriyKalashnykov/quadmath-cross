#include <stdio.h>
#include <stdlib.h>
#include <quadmath.h>
// gcc ./quadmath.c  -o quadmath -lquadmath
// gcc quadmath.c -o quadmath -Wl,-Bstatic -lquadmath

//int main ()
//{
//  __float128 r;
//  char buf[128];
//
//  r = strtoflt128("1.2345678", NULL);	// undefined reference to `strtoflt128'
//  r = 123.456;	// OK
////  quadmath_snprintf (buf, sizeof buf, "%Qa", r);
//  quadmath_snprintf (buf, sizeof buf, "%Qf\n", r);
//  printf(buf);
//  getchar();
//  return 0;
//}

int main ()
{
  __float128 a, b, r;
  char buf[128];

  printf("enter first 128-bit float ");
  scanf("%s", buf);
  a = strtoflt128 (buf, NULL);
  printf("enter second 128-bit float ");
  scanf("%s", buf);
  b = strtoflt128 (buf, NULL);
  r=a+b;
  quadmath_snprintf (buf, sizeof buf, "%+-#46.*Qe", r);
  return 0;
}