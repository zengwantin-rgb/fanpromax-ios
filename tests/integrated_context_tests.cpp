#include "CollisionProbe.hpp"
#include "LocalController.hpp"
#include <cassert>
#include <cmath>
#include <cstring>
#include <functional>
#include <iostream>
#include <map>
#include <vector>
using namespace nsport;
namespace {
constexpr uint64_t base=0x100000000, engine=0x300000000, viewport=0x300010000,
    world=0x300020000, controller=0x300030000, pawn=0x300040000,
    movement=0x300050000, capsule=0x300060000, weakList=0x300070000,
    table=0x300080000, chunk=0x300090000, capsuleVT=0x3000a0000, movementVT=0x3000b0000;
using Stage=CollisionObservation::Stage;
std::array<uint64_t,3> encoded(uint64_t pointer) {
    return {pointer ^ 0x69651cbe75340c01ULL,0,0};
}
struct Fixture {
    std::map<uint64_t,std::vector<uint8_t>> regions;
    std::function<void(uint64_t)> beforeRead;
    uint64_t failAddress{};
    size_t reads{};
    void allocate(uint64_t address,size_t size) { regions[address].resize(size); }
    template<class T> void set(uint64_t address,T value) {
        auto it=regions.upper_bound(address); assert(it!=regions.begin()); --it;
        const auto offset=address-it->first; assert(offset+sizeof value<=it->second.size());
        std::memcpy(it->second.data()+offset,&value,sizeof value);
    }
    static bool read(void *context,uint64_t address,void *out,size_t size) {
        auto &f=*static_cast<Fixture *>(context); ++f.reads;
        if (f.beforeRead) f.beforeRead(address);
        if (f.failAddress && address==f.failAddress) return false;
        auto it=f.regions.upper_bound(address); if(it==f.regions.begin()) return false; --it;
        const auto offset=address-it->first;
        if(offset>it->second.size() || size>it->second.size()-offset) return false;
        std::memcpy(out,it->second.data()+offset,size); return true;
    }
    CollisionObservation observe() { return observeCollision({this,read,base},0x1000,0x6000000); }
    Fixture() {
        for(auto object:{engine,viewport,world,controller,pawn,movement,capsule,weakList,table,chunk,capsuleVT,movementVT}) allocate(object,0x1000);
        const uint64_t slots[]={0x8098ac8,0x809b590,0x80b74f0,0x80ad348,0x7f2c5b0,0x8095918,0x8095030};
        const uint64_t objects[]={engine,viewport,world,controller,pawn,movement,capsule};
        for(unsigned i=0;i<7;++i) {
            uint64_t klass=0x400000000+uint64_t(i)*0x1000;
            allocate(klass,0x100); allocate(base+slots[i],8); set(base+slots[i],klass); set(objects[i]+0x30,encoded(klass));
        }
        allocate(base+0x81e8ef0,8); set(base+0x81e8ef0,engine);
        allocate(base+0x8174500,0x100); set(base+0x8174520,table); set(base+0x8174538,int32_t(1));
        set(table,chunk); set(chunk+8,controller); set(chunk+20,int32_t(1));
        // Encoded weak index 0 and serial 1, independent of production encoder.
        set(weakList,std::array<uint32_t,6>{0,0,0xb9702b7d,0,0,0xb5c76da1});
        set(engine+0x960,viewport); set(viewport+0x1f8,world);
        set(world+0x230,weakList); set(world+0x238,int32_t(1)); set(world+0x23c,int32_t(1));
        set(controller+0x370,encoded(pawn)); set(controller+0x2e0,encoded(0));
        set(pawn+0x338,encoded(movement)); set(pawn+0x350,encoded(capsule)); set(pawn+0x278,capsule);
        set(pawn+0x58,uint64_t(1)<<34); set(movement+0x100,capsule); set(movement+0x118,capsule);
        // Nonzero neighbouring fields must not be treated as an encoded pointer triple.
        set(movement+0x108,uint64_t(0x12345678)); set(movement+0x110,uint64_t(0x87654321));
        set(movement+0x120,uint64_t(0x99887766)); set(movement+0x128,uint64_t(0x55667788));
        set(movement+0x188,pawn); set(movement+0x298,uint8_t(1)); set(movement+0x408,1.0f);
        set(capsule+0x2fc,uint8_t(3)); set(capsule+0x534,88.0f); set(capsule+0x538,34.0f);
        set(capsule,capsuleVT); set(movement,movementVT);
        set(capsuleVT+0x6b8,base+0x12340); set(capsuleVT+0x560,base+0x23450);
        set(capsuleVT+0x8b0,base+0x34560); set(movementVT+0x620,base+0x45670);
    }
};
void localOwnership() {
    Fixture f;Memory m{&f,Fixture::read,base};
    constexpr uint64_t player=0x3000d0000,players=0x3000e0000,contexts=0x3000f0000,
        context=0x300100000,instance=0x300110000,remote=0x300120000,otherContext=0x300130000,
        otherPlayer=0x300140000,localClass=0x400007000;
    for(auto object:{player,players,contexts,context,instance,remote,otherContext,otherPlayer}) f.allocate(object,0x1000);
    f.allocate(base+0x80a23c0,8);f.allocate(localClass,0x100);f.set(base+0x80a23c0,localClass);
    f.set(player+0x30,encoded(localClass));f.set(otherPlayer+0x30,encoded(localClass));
    f.set(engine+0x210,contexts);f.set(engine+0x218,int32_t(1));f.set(engine+0x21c,int32_t(1));
    f.set(contexts,context);f.set(context+0x250,world);f.set(context+0x70,instance);
    f.set(instance+0x60,players);f.set(instance+0x68,int32_t(1));f.set(instance+0x6c,int32_t(1));
    f.set(players,encoded(player));f.set(controller+0x358,encoded(player));
    f.set(remote+0x30,encoded(uint64_t(0x400003000)));f.set(remote+0x358,encoded(0));
    f.set(chunk+24+8,remote);f.set(chunk+24+20,int32_t(2));f.set(base+0x8174538,int32_t(2));
    f.set(weakList,std::array<uint32_t,6>{0,0,0xb9702b3d,0,0,0xb5c76c21});
    f.set(weakList+24,std::array<uint32_t,6>{0,0,0xb9702b7d,0,0,0xb5c76da1});
    f.set(world+0x238,int32_t(2));f.set(world+0x23c,int32_t(2));
    const auto before=f.regions;auto result=local::readLocalController(m);
    assert(result.verified && result.controller==controller && result.player==player && result.world==world);
    assert(result.controllers==2 && result.ownedControllers==1 && f.regions==before);
    assert(observeCollision(m,0x1000,0x6000000,nullptr,result.controller).stage==Stage::ready);
    assert(observeCollision(m,0x1000,0x6000000).stage==Stage::ambiguousController);
    f.set(remote+0x358,encoded(player));result=local::readLocalController(m);
    assert(!result.verified && !result.controller && result.ownedControllers==2);
    f.set(remote+0x358,encoded(0));f.set(controller+0x358,encoded(otherPlayer));
    assert(!local::readLocalController(m).verified); // A different typed LocalPlayer is not owned by this instance.
    f.set(controller+0x358,encoded(player));f.set(player+0x30,encoded(0));
    assert(!local::readLocalController(m).verified);f.set(player+0x30,encoded(localClass));
    f.set(context+0x250,uint64_t(0));assert(!local::readLocalController(m).verified);f.set(context+0x250,world);
    f.set(context+0x70,uint64_t(0));assert(!local::readLocalController(m).verified);f.set(context+0x70,instance);
    f.set(instance+0x68,int32_t(0));assert(!local::readLocalController(m).verified);f.set(instance+0x68,int32_t(1));
    f.set(chunk+20,int32_t(9));assert(!local::readLocalController(m).verified);f.set(chunk+20,int32_t(1));
    unsigned reads=0;
    f.beforeRead=[&](uint64_t at){if(at==controller+0x358 && ++reads==2) f.set(controller+0x358,encoded(0));};
    result=local::readLocalController(m);assert(!result.verified && !result.controller);
    f.beforeRead={};f.set(controller+0x358,encoded(player));reads=0;
    f.beforeRead=[&](uint64_t at){if(at==players && ++reads==2) f.set(players,encoded(otherPlayer));};
    result=local::readLocalController(m);assert(!result.verified && !result.controller);
    f.beforeRead={};f.set(players,encoded(player));
    f.beforeRead=[&](uint64_t at){if(at==controller+0x358) f.set(viewport+0x1f8,uint64_t(0));};
    assert(!local::readLocalController(m).verified);f.beforeRead={};f.set(viewport+0x1f8,world);
    f.set(weakList,std::array<uint32_t,6>{0,0,0xb9702b7d,0,0,0xb5c76da1});
    result=local::readLocalController(m);assert(result.verified && result.controllers==1 && result.ownedControllers==1);
    f.set(engine+0x218,int32_t(2));f.set(engine+0x21c,int32_t(2));f.set(contexts,otherContext);f.set(contexts+8,context);
    result=local::readLocalController(m);assert(result.verified); // Current world context can be non-first.
    f.set(otherContext+0x250,world);assert(!local::readLocalController(m).verified); // Two matching contexts remain ambiguous.
}
}
int main() {
    localOwnership();
    Fixture f;
    const auto before=f.regions;
    auto observation=f.observe();
    assert(observation.stage==Stage::ready && observation.movementMode==1 && observation.collisionEnabled==3);
    assert(observation.actorCollision && observation.rootIsCapsule && observation.updatedIsCapsule && observation.primitiveIsCapsule && observation.ownerIsPawn);
    assert(observation.collisionSetter==0x12340 && observation.movementSetter==0x45670);
    assert(f.regions==before && f.reads<100); // No state writes or global actor traversal.
    f.set(controller+0x370,encoded(0)); assert(f.observe().stage==Stage::pawn);
    f.set(controller+0x2e0,encoded(pawn)); assert(f.observe().stage==Stage::ready);
    f.set(controller+0x370,encoded(pawn)); f.set(controller+0x2e0,encoded(0));
    f.set(chunk+20,int32_t(2)); assert(f.observe().stage==Stage::controller); f.set(chunk+20,int32_t(1));
    f.set(world+0x238,int32_t(2)); assert(f.observe().stage==Stage::controller); // Invalid TArray bounds.
    f.set(world+0x23c,int32_t(2)); f.set(weakList+24,std::array<uint32_t,6>{0,0,0xb9702b7d,0,0,0xb5c76da1});
    assert(f.observe().stage==Stage::ambiguousController);
    Memory pinned{&f,Fixture::read,base};
    assert(observeCollision(pinned,0x1000,0x6000000,nullptr,controller).stage==Stage::ready);
    assert(observeCollision(pinned,0x1000,0x6000000,nullptr,pawn).stage==Stage::controller);
    // Distinct controllers may coexist; a verified identity must select the right one.
    constexpr uint64_t otherController=0x3000c0000;
    f.allocate(otherController,0x1000);f.set(otherController+0x30,encoded(uint64_t(0x400003000)));
    f.set(chunk+24+8,otherController);f.set(chunk+24+20,int32_t(2));
    f.set(base+0x8174538,int32_t(2));
    f.set(weakList,std::array<uint32_t,6>{0,0,0xb9702b3d,0,0,0xb5c76c21}); // index 1, serial 2
    assert(f.observe().stage==Stage::ambiguousController);
    assert(observeCollision(pinned,0x1000,0x6000000,nullptr,controller).stage==Stage::ready);
    f.set(chunk+20,int32_t(9)); // Losing the pinned controller cannot select the other one.
    assert(observeCollision(pinned,0x1000,0x6000000,nullptr,controller).stage==Stage::controller);
    f.set(chunk+20,int32_t(1));
    f.set(weakList,std::array<uint32_t,6>{0,0,0xb9702b7d,0,0,0xb5c76da1});
    f.set(world+0x238,int32_t(1));
    f.failAddress=capsule+0x534; assert(f.observe().stage==Stage::unreadable); f.failAddress=0;
    f.beforeRead=[&](uint64_t address) { if(address==capsule+0x534) f.set(controller+0x370,encoded(0)); };
    assert(f.observe().stage==Stage::changed); f.beforeRead={}; f.set(controller+0x370,encoded(pawn));
    f.set(movement+0x408,NAN); assert(f.observe().stage==Stage::invalidValues); f.set(movement+0x408,1.0f);
    f.set(movement+0x298,uint8_t(255)); assert(f.observe().stage==Stage::invalidValues); f.set(movement+0x298,uint8_t(3));
    f.set(capsule+0x538,100.0f); assert(f.observe().stage==Stage::invalidValues); f.set(capsule+0x538,34.0f);
    f.set(capsuleVT+0x6b8,base+0x7000000); f.set(movementVT+0x620,base+0x45671);
    observation=f.observe(); assert(observation.stage==Stage::ready && observation.collisionSetter==0 && observation.movementSetter==0);
    f.set(movement+0x100,uint64_t(0)); assert(!f.observe().updatedIsCapsule);
    f.set(capsule+0x30,encoded(0)); assert(f.observe().stage==Stage::components);
    Fixture generations;
    CollisionContext context;
    Memory m{&generations,Fixture::read,base};
    assert(observeCollision(m,0x1000,0x6000000,&context).stage==Stage::ready && !context.generationsValid);
    generations.set(base+0x8174538,int32_t(4));
    const uint64_t objects[]={pawn,movement,capsule};
    for(uint32_t i=0;i<3;++i) {
        const auto index=i+1;
        generations.set(objects[i]+0x20,std::array<uint32_t,3>{0,0,0xb5c76d21U^(index<<7)});
        generations.set(chunk+index*24+8,objects[i]); generations.set(chunk+index*24+20,int32_t(101+i));
    }
    assert(observeCollision(m,0x1000,0x6000000,&context).stage==Stage::ready && context.generationsValid);
    assert(context.serials[0]==101 && context.serials[1]==102 && context.serials[2]==103);
    generations.set(chunk+48+16,uint32_t(0x30000000));
    observeCollision(m,0x1000,0x6000000,&context); assert(!context.generationsValid);
    generations.set(chunk+48+16,uint32_t(0)); generations.set(chunk+48+8,uint64_t(123));
    observeCollision(m,0x1000,0x6000000,&context); assert(!context.generationsValid);
    std::cout<<"PASS: current-world local-player ownership; remote-first and duplicate controllers; ambiguous owned controllers; expired identity; ownership/array/world races; pinned sampler context; read-only live graph and component identity\n";
}
