#include "CollisionProbe.hpp"
#include <cmath>

namespace nsport {
namespace {
bool type(const Memory &m, uint64_t object, uint64_t singleton) {
    return object && isA(m, m.encodedPointer(object + 0x30), m.pointer(m.base + singleton));
}
struct Array { uint64_t data; int32_t count, capacity; };
bool generation(const Memory &m, uint64_t object, uint64_t &itemAddress, int32_t &serial) {
    struct Item { uint64_t reserved, object; uint32_t flags; int32_t serial; };
    std::array<uint32_t,3> words{}; int32_t count{};
    if (!m.get(object + 0x20, words) || !m.get(m.base + 0x8174538, count) || count <= 0 || count > 2000000) return false;
    const auto index = decodeSerial(words); // Native UObject internal index encoding, XOR/ROR7.
    if (index >= uint32_t(count)) return false;
    const auto table = m.pointer(m.base + 0x8174520);
    const auto chunk = table ? m.pointer(table + uint64_t(index >> 16) * 8) : 0;
    if (!chunk) return false;
    itemAddress = chunk + uint64_t(index & 0xffff) * sizeof(Item);
    Item item{};
    if (!m.get(itemAddress, item) || item.object != object || !item.serial || (item.flags & 0x30000000)) return false;
    serial = item.serial;
    return true;
}
uint64_t code(const Memory &m, uint64_t object, uint64_t slot, uint64_t begin, uint64_t end) {
    const auto vtable = m.pointer(object);
    const auto target = vtable ? m.pointer(vtable + slot) : 0;
    if (target < m.base || target - m.base < begin || target - m.base >= end || target % 4) return 0;
    return target - m.base;
}
}
CollisionObservation observeCollision(const Memory &m, uint64_t begin, uint64_t end, CollisionContext *context,
                                      uint64_t expectedController) {
    using Stage = CollisionObservation::Stage;
    CollisionObservation out;
    if (context) *context = {};
    if (!m.base || !begin || begin >= end) return out;
    const auto engine = m.pointer(m.base + 0x81e8ef0);
    if (!type(m, engine, 0x8098ac8)) return out;
    out.stage = Stage::viewport;
    const auto viewport = m.pointer(engine + 0x960);
    if (!type(m, viewport, 0x809b590)) return out;
    out.stage = Stage::world;
    const auto world = m.pointer(viewport + 0x1f8);
    if (!type(m, world, 0x80b74f0)) return out;
    out.stage = Stage::controller;
    Array controllers{};
    if (!m.get(world + 0x230, controllers) || !controllers.data || controllers.count < 1 ||
        controllers.count > 16 || controllers.capacity < controllers.count || controllers.capacity > 4096) return out;
    uint64_t controller = 0, weakAddress = 0;
    for (int32_t i = 0; i < controllers.count; ++i) {
        const auto at = controllers.data + uint64_t(i) * 24;
        const auto candidate = resolveWeak(m, at);
        if (!type(m, candidate, 0x80ad348)) continue;
        // A caller with independent local-player identity may pin its controller.
        // It must still be a live weak entry in this world; never fall back to another.
        if (expectedController && candidate != expectedController) continue;
        if (expectedController && controller == candidate) continue;
        if (controller) { out.stage = Stage::ambiguousController; return out; }
        controller = candidate; weakAddress = at;
    }
    if (!controller) return out;
    out.stage = Stage::pawn;
    uint64_t pawnField = 0x370;
    auto pawn = m.encodedPointer(controller + pawnField);
    if (!pawn) { pawnField = 0x2e0; pawn = m.encodedPointer(controller + pawnField); }
    if (!type(m, pawn, 0x7f2c5b0)) return out;
    out.stage = Stage::components;
    const auto movement = m.encodedPointer(pawn + 0x338);
    const auto capsule = m.encodedPointer(pawn + 0x350);
    if (!type(m, movement, 0x8095918) || !type(m, capsule, 0x8095030)) return out;
    out.stage = Stage::unreadable;
    uint64_t flags{};
    if (!m.get(pawn + 0x58, flags) || !m.get(movement + 0x298, out.movementMode) ||
        !m.get(movement + 0x670, out.customMode) || !m.get(movement + 0x408, out.gravity) ||
        !m.get(capsule + 0x2fc, out.collisionEnabled) || !m.get(capsule + 0x534, out.halfHeight) ||
        !m.get(capsule + 0x538, out.radius)) return out;
    out.actorCollision = (flags & (uint64_t(1) << 34)) != 0;
    out.rootIsCapsule = m.pointer(pawn + 0x278) == capsule;
    // Native loads at 0x504e5a8 / 0x504e708 directly dereference these fields.
    // Their reflected ObjectProperty descriptors do not imply pointer encoding.
    out.updatedIsCapsule = m.pointer(movement + 0x100) == capsule;
    out.primitiveIsCapsule = m.pointer(movement + 0x118) == capsule;
    out.ownerIsPawn = m.pointer(movement + 0x188) == pawn;
    out.collisionSetter = code(m, capsule, 0x6b8, begin, end);
    out.collisionGetter = code(m, capsule, 0x560, begin, end);
    out.responseSetter = code(m, capsule, 0x8b0, begin, end);
    out.movementSetter = code(m, movement, 0x620, begin, end);
    // The observer runs off-thread: discard a sample if travel/possession changed
    // any link while reading. No cached UObject pointers survive this call.
    out.stage = Stage::changed;
    if (m.pointer(m.base + 0x81e8ef0) != engine || m.pointer(engine + 0x960) != viewport ||
        m.pointer(viewport + 0x1f8) != world || resolveWeak(m, weakAddress) != controller ||
        m.encodedPointer(controller + pawnField) != pawn || m.encodedPointer(pawn + 0x338) != movement ||
        m.encodedPointer(pawn + 0x350) != capsule) return out;
    out.stage = Stage::invalidValues;
    if (out.movementMode > 7 || out.collisionEnabled > 3 || !std::isfinite(out.gravity) ||
        out.gravity < -20 || out.gravity > 20 || !std::isfinite(out.radius) ||
        !std::isfinite(out.halfHeight) || out.radius <= 0 || out.radius > 1000 ||
        out.halfHeight < out.radius || out.halfHeight > 1000) return out;
    out.stage = Stage::ready;
    if (context) {
        context->world = world; context->controller = controller; context->pawn = pawn;
        context->movement = movement; context->capsule = capsule;
        context->generationsValid = generation(m, pawn, context->items[0], context->serials[0]) &&
            generation(m, movement, context->items[1], context->serials[1]) &&
            generation(m, capsule, context->items[2], context->serials[2]);
    }
    return out;
}
const char *collisionStageName(CollisionObservation::Stage stage) {
    switch (stage) {
        case CollisionObservation::Stage::engine: return "waiting_engine";
        case CollisionObservation::Stage::viewport: return "waiting_viewport";
        case CollisionObservation::Stage::world: return "waiting_world";
        case CollisionObservation::Stage::controller: return "waiting_controller";
        case CollisionObservation::Stage::ambiguousController: return "multiple_controllers";
        case CollisionObservation::Stage::pawn: return "waiting_character";
        case CollisionObservation::Stage::components: return "waiting_components";
        case CollisionObservation::Stage::unreadable: return "read_failed";
        case CollisionObservation::Stage::changed: return "changed_during_read";
        case CollisionObservation::Stage::invalidValues: return "invalid_values";
        case CollisionObservation::Stage::ready: return "ready";
    }
    return "unknown";
}
} // namespace nsport
