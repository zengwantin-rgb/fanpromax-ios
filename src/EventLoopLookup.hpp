#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
namespace fanport {
using CodeRead=bool (*)(void *,uintptr_t,void *,size_t);
using SameImage=bool (*)(void *,uintptr_t,uintptr_t);
struct EventLoopLookup {uintptr_t target{};unsigned candidates{};const char *reason{"pattern_missing"};};
// Read only our process's UIKit _run implementation. Never patch instructions.
inline EventLoopLookup findEventLoopInstaller(uintptr_t run,CodeRead read,SameImage sameImage,void *context) {
    EventLoopLookup result;std::array<uint32_t,0x140> code{};
    if(!run || (run&3) || !read || !sameImage || run>std::numeric_limits<uintptr_t>::max()-sizeof(code) ||
        !read(context,run,code.data(),sizeof(code))) {result.reason="run_unreadable";return result;}
    uintptr_t unique{};bool ambiguous=false;
    for(size_t i=0;i+2<code.size();++i) {
        // mov x2,x0; mov x0,xN; bl ... (the reference's run-loop call shape).
        if(code[i]!=0xaa0003e2U || (code[i+1]&0xffe0ffffU)!=0xaa0003e0U || (code[i+2]&0xfc000000U)!=0x94000000U)continue;
        int64_t immediate=code[i+2]&0x03ffffffU;if(immediate&0x02000000)immediate-=0x04000000;
        const int64_t delta=immediate*4;const uintptr_t pc=run+(i+2)*4;
        if((delta<0 && pc<uint64_t(-delta)) || (delta>=0 && pc>std::numeric_limits<uintptr_t>::max()-uintptr_t(delta)))continue;
        const uintptr_t target=delta<0 ? pc-uintptr_t(-delta) : pc+uintptr_t(delta);
        if(!sameImage(context,run,target))continue;
        uint32_t first{};
        if(!read(context,target,&first,sizeof(first)) || (first&0xff00001fU)!=0xb4000000U)continue; // cbz x0,...
        ++result.candidates;if(unique && unique!=target)ambiguous=true;else unique=target;
    }
    if(ambiguous) {result.reason="pattern_ambiguous";return result;}
    if(unique) {result.target=unique;result.reason="system_pattern";}
    return result;
}
}
