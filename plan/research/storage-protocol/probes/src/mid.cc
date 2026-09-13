#include <iostream>
#include <vector>
#include <string>
#include <algorithm>

struct Item { std::string name; int weight; };

static bool byWeight(const Item &a, const Item &b) { return a.weight < b.weight; }

int total(const std::vector<Item> &items) {
	int t = 0;
	for (auto const &i : items) t += i.weight;
	return t;
}

void report(std::vector<Item> items) {
	std::sort(items.begin(), items.end(), byWeight);
	for (auto const &i : items) std::cout << i.name << ":" << i.weight << "\n";
	std::cout << "total=" << total(items) << std::endl;
}

int main(int argc, char **argv) {
	std::vector<Item> v;
	for (int i = 1; i < argc; ++i) v.push_back(Item{std::string(argv[i]), i * 3});
	report(v);
	return 0;
}
