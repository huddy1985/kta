
//#define PRINT_MAIN

#ifdef PRINT_MAIN
#include <stdio.h>
#endif

int k;
int v = 7000;
int v2 = 8000;
char str[] = "\xf0Hello my name is David.";

int foo(int x){
  int i;
  int k;
  while(str[i] != 0){
    str[i] = str[i] + x;
    i++;
  }
  return &str;
}

/*
// Tests: lw, sw
int foo(int x, int y){
  v = -10000 + v;
  return &v;
}
*/

/*
// Tests: slt,bne,sll,jr,mul,addiu
int foo(int x, int y){
  int z = x * y;
  if(x > y)
    return x;
  else
    return z;
}
*/

/*
// Tests: blez, subu, sll, addiu, bne
int foo(int x){
  int i;
  int r = 23;
  for(i=0; i < x; i++){
    r += (i+100) * 7;
  }  
  return r;
}
*/


/*
// mult, mfhi, teq, div (reminder part)
int foo(int x){
  int i;
  int r = 23;
  for(i=0; i < x; i++){
    r += (i+100) % 7;
  }  
  return r;
}
*/


/*
// mult mflo
int foo(int x, int y){
  int z = x * y;
  if(x == y)
    return x;
  else
    return z;
}
*/

/*
 0000 0000 1000 0101   0001 0000 0000 1010

 */

int main()
{
  #ifdef PRINT_MAIN
  int x = foo(5);
  printf("Result: 0x%x  %d\n", x, x);
  #endif
  return 0;
}
