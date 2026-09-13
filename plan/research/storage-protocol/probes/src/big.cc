#include <iostream>
#include <vector>
#include <map>
#include <string>
#include <algorithm>
#include <sstream>
#include <memory>
#include <functional>
#include <unordered_map>
#include <regex>

namespace demo {
template <typename T>
struct Node {
	T value;
	std::vector<std::shared_ptr<Node<T>>> kids;
	explicit Node(T v) : value(std::move(v)) {}
	void add(std::shared_ptr<Node<T>> k) { kids.push_back(std::move(k)); }
	std::size_t count() const {
		std::size_t n = 1;
		for (auto const &k : kids) n += k->count();
		return n;
	}
};

template <typename K, typename V>
class Registry {
public:
	void put(K k, V v) { items_[std::move(k)] = std::move(v); }
	const V *get(const K &k) const {
		auto it = items_.find(k);
		return it == items_.end() ? nullptr : &it->second;
	}
	std::string describe() const {
		std::ostringstream os;
		for (auto const &kv : items_) os << kv.first << "=" << kv.second << ";";
		return os.str();
	}
private:
	std::map<K, V> items_;
};

struct Stats {
	double mean = 0, var = 0;
	std::size_t n = 0;
	void push(double x) {
		++n;
		double d = x - mean;
		mean += d / static_cast<double>(n);
		var += d * (x - mean);
	}
};

std::vector<std::string> tokenize(const std::string &s) {
	std::regex re("[^ \t,]+");
	std::vector<std::string> out;
	for (auto it = std::sregex_iterator(s.begin(), s.end(), re); it != std::sregex_iterator(); ++it)
		out.push_back(it->str());
	return out;
}

int run(const std::string &input) {
	Registry<std::string, int> reg;
	auto toks = tokenize(input);
	Stats st;
	for (std::size_t i = 0; i < toks.size(); ++i) {
		reg.put(toks[i], static_cast<int>(i));
		st.push(static_cast<double>(toks[i].size()));
	}
	auto root = std::make_shared<Node<std::string>>("root");
	for (auto const &t : toks) root->add(std::make_shared<Node<std::string>>(t));
	std::unordered_map<std::string, std::function<int(int)>> ops;
	ops["double"] = [](int x) { return x * 2; };
	ops["square"] = [](int x) { return x * x; };
	int acc = 0;
	for (auto const &kv : ops) acc += kv.second(static_cast<int>(root->count()));
	std::sort(toks.begin(), toks.end());
	std::cout << reg.describe() << " mean=" << st.mean << " acc=" << acc << "\n";
	return acc;
}
}  // namespace demo

int main(int argc, char **argv) {
	std::string in;
	for (int i = 1; i < argc; ++i) in += std::string(argv[i]) + " ";
	return demo::run(in) & 0xff;
}
