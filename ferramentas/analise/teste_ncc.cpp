#include "sigfm.hpp"
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>
static std::vector<unsigned char> pgm(const std::string& p, int& w, int& h)
{
    std::ifstream f(p, std::ios::binary); std::string m; int mx; f >> m >> w >> h >> mx; f.get();
    std::vector<unsigned char> d(w * h); f.read((char*) d.data(), w * h); return d;
}
int main(int argc, char** argv)
{
    std::vector<SigfmImgInfo*> v;
    for (int i = 1; i < argc; i++) { int w, h; auto d = pgm(argv[i], w, h); v.push_back(sigfm_extract(d.data(), w, h)); }
    // ida e volta pela serialização, como acontece ao salvar a digital
    for (auto& x : v) { int n; auto* b = sigfm_serialize_binary(x, &n); auto* y = sigfm_deserialize_binary(b, n); free(b); sigfm_free_info(x); x = y; }
    for (size_t a = 0; a < v.size(); a++) { for (size_t b = 0; b < v.size(); b++) printf("%4d", a == b ? -1 : sigfm_match_score(v[a], v[b])); printf("\n"); }
}
