#pragma once
#include "CollisionProbe.hpp"
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <cstring>
namespace collision_runtime {
static nsport::Memory memory;
static uint64_t textBegin, textEnd;
bool readMemory(void *, uint64_t address, void *destination, size_t size) {
    vm_size_t copied = 0;
    return vm_read_overwrite(mach_task_self(), address, size,
        reinterpret_cast<vm_address_t>(destination), &copied) == KERN_SUCCESS && copied == size;
}
bool identify() {
    static const uint8_t expected[] = {0xaf,0x49,0x43,0x2e,0x9f,0x7f,0x3d,0x7c,0x94,0x70,0x8c,0xf9,0x0e,0x3b,0x33,0x78};
    const auto base = reinterpret_cast<uint64_t>(_dyld_get_image_header(0));
    memory = {nullptr, readMemory, base};
    mach_header_64 header{};
    if (!memory.get(base, header) || header.magic != MH_MAGIC_64 || header.filetype != MH_EXECUTE ||
        header.ncmds > 4096 || header.sizeofcmds > 1024 * 1024) return false;
    uint64_t cursor = base + sizeof header, end = cursor + header.sizeofcmds;
    bool uuidOK = false;
    for (uint32_t i = 0; i < header.ncmds; ++i) {
        load_command command{};
        if (cursor > end || end - cursor < sizeof command || !memory.get(cursor, command) ||
            command.cmdsize < sizeof command || command.cmdsize > end - cursor) return false;
        if (command.cmd == LC_UUID && command.cmdsize == sizeof(uuid_command)) {
            uuid_command uuid{};
            if (!memory.get(cursor, uuid)) return false;
            uuidOK = !std::memcmp(uuid.uuid, expected, sizeof expected);
        }
        if (command.cmd == LC_SEGMENT_64 && command.cmdsize >= sizeof(segment_command_64)) {
            segment_command_64 segment{};
            if (!memory.get(cursor, segment)) return false;
            if (!std::strncmp(segment.segname, "__TEXT", 16)) {
                if (segment.nsects > (command.cmdsize - sizeof segment) / sizeof(section_64)) return false;
                for (uint32_t s = 0; s < segment.nsects; ++s) {
                    section_64 section{};
                    if (!memory.get(cursor + sizeof segment + uint64_t(s) * sizeof section, section)) return false;
                    if (!std::strncmp(section.sectname, "__text", 16)) {
                        if (section.addr < segment.vmaddr || section.size > segment.vmsize ||
                            section.addr - segment.vmaddr > segment.vmsize - section.size) return false;
                        textBegin = section.addr - segment.vmaddr;
                        textEnd = textBegin + section.size;
                    }
                }
            }
        }
        cursor += command.cmdsize;
    }
    return uuidOK && textBegin && textEnd > textBegin;
}
}
