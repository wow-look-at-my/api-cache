/* Minimal C process: the floor for "a program that starts and exits". */
#include <unistd.h>
int main(void) { write(1, "hello\n", 6); return 0; }
