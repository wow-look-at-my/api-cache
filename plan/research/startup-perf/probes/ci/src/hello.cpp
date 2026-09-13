/* C++ with <iostream>. The iostream static initializer (std::ios_base::Init)
 * runs before main in every translation unit that includes the header, and it
 * is the classic reason a C++ tool starts slower than the C one beside it. */
#include <iostream>
int main() { std::cout << "hello\n"; return 0; }
