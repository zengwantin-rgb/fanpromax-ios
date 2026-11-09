#pragma once
#include "PortCore.hpp"

namespace nsport {
// This interface intentionally has no write callback and never calls a game function.
struct CollisionObservation {
    enum class Stage { engine, viewport, world, controller, ambiguousController,
        pawn, components, unreadable, changed, invalidValues, ready };
    Stage stage{Stage::engine};
    uint8_t movementMode{}, customMode{}, collisionEnabled{};
    bool actorCollision{}, rootIsCapsule{}, updatedIsCapsule{}, primitiveIsCapsule{}, ownerIsPawn{};
    float gravity{}, halfHeight{}, radius{};
    // Only executable RVAs are returned. Zero means unknown/outside __text.
    uint64_t collisionSetter{}, collisionGetter{}, responseSetter{}, movementSetter{};
};
// Ephemeral handles, used only inside a game-thread task. Never written to logs.
struct CollisionContext {
    uint64_t world{}, controller{}, pawn{}, movement{}, capsule{};
    std::array<uint64_t,3> items{};
    std::array<int32_t,3> serials{};
    bool generationsValid{};
};
CollisionObservation observeCollision(const Memory &, uint64_t textBeginRVA, uint64_t textEndRVA,
                                      CollisionContext *context = nullptr, uint64_t expectedController = 0);
const char *collisionStageName(CollisionObservation::Stage);
} // namespace nsport
