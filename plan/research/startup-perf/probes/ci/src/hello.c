/* C startup floor. stdio is included so libc's stdio init is on the clock,
 * which is what a real wrapper pays. */
#include <stdio.h>
int main(void) { fputs("hello\n", stdout); return 0; }
