#include "EventLoopLookup.hpp"
#include <cassert>
#include <algorithm>
#include <cstring>
#include <iostream>
#include <map>
#include <vector>
using namespace fanport;
struct Fixture {
    std::map<uintptr_t,std::vector<uint8_t>> regions;bool imageMatches=true;size_t largestRead{};
    void put(uintptr_t address,const void *value,size_t bytes) {regions[address]=std::vector<uint8_t>((const uint8_t *)value,(const uint8_t *)value+bytes);}
    static bool read(void *ctx,uintptr_t address,void *value,size_t bytes) {
        auto &f=*(Fixture *)ctx;f.largestRead=std::max(f.largestRead,bytes);
        for(const auto &r:f.regions)if(address>=r.first && address-r.first<=r.second.size() && bytes<=r.second.size()-(address-r.first)) {
            std::memcpy(value,r.second.data()+address-r.first,bytes);return true;
        }return false;
    }
    static bool image(void *ctx,uintptr_t,uintptr_t) {return ((Fixture *)ctx)->imageMatches;}
};
int main() {
    constexpr uintptr_t run=0x100000,target=0x102000,second=0xff000;
    std::array<uint32_t,0x140> code{};uint32_t entry=0xb4000040;
    auto add=[&](size_t n,uintptr_t destination) {
        code[n]=0xaa0003e2;code[n+1]=0xaa1403e0;
        code[n+2]=0x94000000U|(uint32_t((int64_t(destination)-int64_t(run+(n+2)*4))/4)&0x03ffffffU);
    };
    Fixture f;add(4,target);f.put(run,code.data(),sizeof(code));f.put(target,&entry,4);
    auto result=findEventLoopInstaller(run,Fixture::read,Fixture::image,&f);assert(result.target==target && result.candidates==1);
    add(9,target);f.put(run,code.data(),sizeof(code));result=findEventLoopInstaller(run,Fixture::read,Fixture::image,&f);assert(result.target==target && result.candidates==2);
    add(16,second);f.put(run,code.data(),sizeof(code));f.put(second,&entry,4);
    result=findEventLoopInstaller(run,Fixture::read,Fixture::image,&f);assert(!result.target && !std::strcmp(result.reason,"pattern_ambiguous"));
    code={};add(12,second);f.put(run,code.data(),sizeof(code));assert(findEventLoopInstaller(run,Fixture::read,Fixture::image,&f).target==second);
    f.imageMatches=false;assert(!findEventLoopInstaller(run,Fixture::read,Fixture::image,&f).target);f.imageMatches=true;
    uint32_t wrong=0xb5000040;f.put(second,&wrong,4);assert(!findEventLoopInstaller(run,Fixture::read,Fixture::image,&f).target);
    f.put(second,&entry,4);code[13]=0xaa1403e1;f.put(run,code.data(),sizeof(code));assert(!findEventLoopInstaller(run,Fixture::read,Fixture::image,&f).target);
    f.put(run,code.data(),16);result=findEventLoopInstaller(run,Fixture::read,Fixture::image,&f);assert(!result.target && !std::strcmp(result.reason,"run_unreadable"));
    assert(!findEventLoopInstaller(run+1,Fixture::read,Fixture::image,&f).target && f.largestRead==0x500);
    std::cout<<"PASS: bounded UIKit event-loop call lookup; positive/negative branches; duplicate same targets; ambiguous/different-image/unreadable/wrong-entry/wrong-register rejection\n";
}
