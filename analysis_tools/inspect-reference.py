"""Read-only, pinned IPA analysis of character/vehicle movement relationships.

Run only on GitHub-hosted macOS. Resolve actual Mach-O chained rebases and
report bounded control-flow contexts; a nearby name is not an API identity.
"""
import bisect
from collections import defaultdict, deque
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import zipfile


EXPECTED = 'cf59f3663bba56b035024e71d814ffceecf86d5d99bd90873c2fd82372e3a0c7'
# Follow-ups from the first pinned report: the rider property's type factory,
# two observed native-table registration starts, and calibrated movement slots.
FOCUS_ENTRIES = (
    0x359be28, 0x35a9ab0, 0x3a0c86c, 0x504ec70, 0x1c857c0,
    # Factory code arguments seen in the preceding hosted report. Their roles
    # remain visible in the factory disassembly, rather than inferred by name.
    0x35f9850, 0x35fe718, 0x35fe724, 0x3a0cdf4, 0x3a0ce00,
    0x35aa400, 0x35aa40c, 0x359c088, 0x359c094, 0x3603270,
    0x35173fc, 0x5977738, 0x33ee21c, 0x3419074,
    0x504f4dc, 0x32a34f8,
)
# These tables are stored into the primary object pointer by constructor
# contexts reached from the named class factories in the preceding report.
DISPATCH_FOCUS = (
    ('character_seat_validate', 0x71ef2d0, 0x918),
    ('character_seat_implementation', 0x71ef2d0, 0x920),
    ('character_based_movement_update', 0x71ef2d0, 0x7e8),
    ('wheeled_vehicle_base_update', 0x745e460, 0x8f0),
    ('vehicle_sync_base_move_validate', 0x74571b8, 0x4e0),
    ('vehicle_sync_base_move_implementation', 0x74571b8, 0x4e8),
)
EXACT_NAMES = (
    'GetVehiclePawn', 'ServerMoveToVehicleSeat', 'MoveVehicleSeat',
    'OnRep_WheeledVehicleBaseMovement', 'WheeledVehicleBaseMovement',
    'HasServerBaseComp', 'BaseComp', 'RelativePos', 'VehicleMovementRef',
    'VehicleMovement', 'WheeledVehicleMovementComponent',
    'OnRep_AttachmentReplication', 'OnRep_ReplicatedBasedMovement',
    'GetMovementBase', 'SetBase', 'GetImpartedMovementBaseVelocity',
    'UpdateBasedMovement', 'SaveBaseLocation', 'SetBaseFromFloor',
    'BasedMovement', 'ReplicatedBasedMovement', 'MovementBase',
    'bIgnoreBaseRotation', 'bImpartBaseVelocityX', 'bImpartBaseVelocityY',
    'bImpartBaseVelocityZ', 'bImpartBaseAngularVelocity',
    'bServerHasBaseComponent', 'bRelativePosition', 'bBaseRelativePosition',
    'AttachParent', 'VehicleRiderComponent', 'VehicleSeatComponent',
    'GetVehicleRiderComponent', 'GetDriver', 'GetSeatIndex', 'SeatIndex',
    'CharacterMovement', 'MaxWalkSpeed', 'GetMaxSpeed',
)


def main(*, exact_names=EXACT_NAMES, focus_entries=FOCUS_ENTRIES,
         dispatch_focus=DISPATCH_FOCUS, output='out/vehicle-character-link',
         discovery_pattern=None, priority_names=None, metadata_focus_rvas=(), metadata_windows=(),
         context_limit=360, context_extent=0x1000, context_extents=None):
    if (sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'):
        raise SystemExit('IPA inspection requires GitHub-hosted macOS.')
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
    import warning_dispatch_patch as macho

    with zipfile.ZipFile(sys.argv[1]) as archive:
        data = archive.read('Payload/ExtremeGame.app/ExtremeGame')
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXPECTED:
        raise ValueError('Unexpected original executable SHA-256')
    command_end, segments, sections = macho.layout(data)
    base = next(s['vmaddr'] for s in segments if s['name'] == '__TEXT')
    code = next(s for s in sections if s['name'] == '__text')
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)

    def file_offset(va, size=1):
        segment = next((s for s in segments
                        if s['vmaddr'] <= va and va + size <= s['vmaddr'] + s['size']), None)
        if segment is None:
            raise ValueError(f'Address not file backed: {va:#x}+{size:#x}')
        return segment['offset'] + va - segment['vmaddr']

    def address(at):
        segment = next(s for s in segments if s['offset'] <= at < s['offset'] + s['size'])
        return segment['vmaddr'] + at - segment['offset']

    def read(va, size):
        at = file_offset(va, size)
        return data[at:at + size]

    def in_code(va):
        return code['address'] <= va < code['address'] + code['size'] and va % 4 == 0

    def rva(va):
        return hex(va - base)

    def cstring(va):
        try:
            at = file_offset(va)
        except ValueError:
            return None
        stop = data.find(b'\0', at, at + 128)
        if stop < 0:
            return None
        value = data[at:stop]
        if value and all(32 <= c < 127 for c in value):
            return value.decode('ascii')
        return None

    def wide_string(va):
        try:
            at = file_offset(va)
        except ValueError:
            return None
        for size in range(0, 384, 2):
            if data[at + size:at + size + 2] != b'\0\0':
                continue
            try:
                value = data[at:at + size].decode('utf-16le')
            except UnicodeDecodeError:
                return None
            return value if len(value) > 1 and all(32 <= ord(c) < 127 for c in value) else None
        return None

    cursor = 32
    fixups = None
    starts = []
    while cursor < command_end:
        kind, length = struct.unpack_from('<II', data, cursor)
        if kind == 0x80000034:
            fixups = struct.unpack_from('<I', data, cursor + 8)[0]
        if kind == 0x26:
            at, size = struct.unpack_from('<II', data, cursor + 8)
            va, value, shift = base, 0, 0
            for byte in data[at:at + size]:
                value |= (byte & 127) << shift
                if byte & 128:
                    shift += 7
                    continue
                if not value:
                    break
                va += value
                starts.append(va)
                value = shift = 0
        cursor += length
    if fixups is None:
        raise ValueError('Missing chained fixups')
    header = struct.unpack_from('<7I', data, fixups)
    begin = fixups + header[1]
    if struct.unpack_from('<I', data, begin)[0] != len(segments):
        raise ValueError('Unexpected chained-fixup segment count')
    rebases, formats = {}, set()
    for index, segment in enumerate(segments):
        relative = struct.unpack_from('<I', data, begin + 4 + index * 4)[0]
        if not relative:
            continue
        at = begin + relative
        size, page_size, fmt, segment_offset, _, pages = struct.unpack_from('<IHHQIH', data, at)
        if fmt not in (2, 6) or segment['vmaddr'] - base != segment_offset:
            raise ValueError('Unsupported pointer format or segment offset')
        formats.add(fmt)
        for page in range(pages):
            start = struct.unpack_from('<H', data, at + 22 + page * 2)[0]
            if start == 0xffff:
                continue
            positions = []
            if start & 0x8000:
                overflow = start & 0x7fff
                while True:
                    if 22 + overflow * 2 + 2 > size:
                        raise ValueError('Overflow starts outside fixup command')
                    value = struct.unpack_from('<H', data, at + 22 + overflow * 2)[0]
                    positions.append(value & 0x7fff)
                    overflow += 1
                    if value & 0x8000:
                        break
            else:
                positions.append(start)
            for position in positions:
                seen = set()
                while True:
                    if position in seen or position + 8 > page_size:
                        raise ValueError('Invalid chained fixup progression')
                    seen.add(position)
                    loc = segment['offset'] + page * page_size + position
                    raw = struct.unpack_from('<Q', data, loc)[0]
                    if not raw >> 63:
                        target = raw & ((1 << 36) - 1)
                        if fmt == 6:
                            target += base
                        target |= ((raw >> 36) & 255) << 56
                        rebases[address(loc)] = target
                    step = ((raw >> 51) & 0xfff) * 4
                    if not step:
                        break
                    position += step

    # Existing exact registered thunk, plus a known speed property, calibrate
    # pointer decoding. The code following a name may also be a UFunction
    # constructor, so all other pairs remain candidates until inspected.
    assert cstring(rebases[base + 0x75eff20]) == 'GetVehiclePawn'
    assert rebases[base + 0x75eff28] == base + 0x35f6fdc

    discovered = set()
    pattern = re.compile(discovery_pattern or r'(Vehicle.*(?:Rider|Seat|Ride|Attach|Driver|Base|Movement)|'
                         r'(?:Rider|Seat).*(?:Vehicle|Move|Attach)|'
                         r'(?:Get|Set|OnRep|Server|Client).*(?:MovementBase|BasedMovement))')
    for section in sections:
        if section['name'] != '__cstring' or section['zero_fill']:
            continue
        for raw in data[section['offset']:section['offset'] + section['size']].split(b'\0'):
            if len(raw) > 96 or not re.fullmatch(rb'[A-Za-z_][A-Za-z0-9_]{3,95}', raw):
                continue
            name = raw.decode('ascii')
            if pattern.search(name):
                discovered.add(name)
    names = list(dict.fromkeys(exact_names + tuple(sorted(discovered))))
    string_addresses = {}
    for name in names:
        needle, at, hits = name.encode() + b'\0', 0, []
        while True:
            at = data.find(needle, at)
            if at < 0:
                break
            try:
                hits.append(address(at))
            except StopIteration:
                pass
            at += len(needle)
        string_addresses[name] = set(hits)
    name_at = defaultdict(list)
    for name, addresses in string_addresses.items():
        for va in addresses:
            name_at[va].append(name)

    references, pairs = [], []
    for loc, target in rebases.items():
        if target not in name_at:
            continue
        words = []
        for offset in range(-16, 72, 8):
            try:
                raw = struct.unpack('<Q', read(loc + offset, 8))[0]
            except ValueError:
                continue
            pointer = rebases.get(loc + offset)
            words.append({'relative': offset, 'raw': hex(raw),
                          'rebase_rva': rva(pointer) if pointer is not None else None,
                          'string': cstring(pointer) if pointer is not None and not in_code(pointer) else None,
                          'code': pointer is not None and in_code(pointer)})
        for name in name_at[target]:
            record = {'name': name, 'string_rva': rva(target), 'reference_rva': rva(loc), 'words': words}
            references.append(record)
            candidate = rebases.get(loc + 8)
            if candidate is not None and in_code(candidate):
                pairs.append({'name': name, 'record_rva': rva(loc), 'code_rva': rva(candidate)})

    def named_row(loc):
        name_pointer, function_pointer = rebases.get(loc), rebases.get(loc + 8)
        if name_pointer is None or function_pointer is None or not in_code(function_pointer):
            return None
        name = cstring(name_pointer)
        # This game's reflected names include hashes starting with a digit.
        if name is not None and re.fullmatch(r'[A-Za-z0-9_]{1,96}', name):
            return {'name': name, 'record_rva': rva(loc), 'code_rva': rva(function_pointer)}
        return None

    table_candidates = {}
    for pair in pairs:
        location = base + int(pair['record_rva'], 16)
        first = location
        for _ in range(2048):
            if named_row(first - 16) is None:
                break
            first -= 16
        if first in table_candidates:
            continue
        rows, location = [], first
        for _ in range(2048):
            row = named_row(location)
            if row is None:
                break
            rows.append(row)
            location += 16
        table_candidates[first] = {'start_rva': rva(first), 'rows': rows,
                                   'limit_reached': len(rows) == 2048}

    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.skipdata = True

    def context(entry):
        extent=(context_extents or {}).get(entry-base,context_extent)
        if not 0x100<=extent<=0x10000 or extent%4:
            raise ValueError('Context extent must be aligned and bounded to 65536 bytes')
        stop = min(entry + extent, code['address'] + code['size'])
        if starts:
            index = bisect.bisect_right(starts, entry)
            if index < len(starts):
                stop = min(stop, starts[index])
        instructions = {pc: (mnemonic, operands) for pc, _, mnemonic, operands
                        in md.disasm_lite(read(entry, stop - entry), entry)}
        todo, visited, calls, exits = [entry], set(), set(), set()
        outside_edges=[]
        while todo:
            pc = todo.pop()
            if pc in visited or pc not in instructions:
                continue
            visited.add(pc)
            mnemonic, operands = instructions[pc]
            match = re.search(r'#(0x[0-9a-f]+)\s*$', operands)
            target = int(match.group(1), 16) if match else None
            if mnemonic in ('ret', 'br', 'braa', 'brab', '.byte'):
                exits.add(pc)
                continue
            if mnemonic in ('b', 'bl') and target is not None and in_code(target):
                if mnemonic == 'bl' or not entry <= target < stop:
                    calls.add(target)
                if mnemonic == 'b':
                    if entry <= target < stop:
                        todo.append(target)
                    else:
                        outside_edges.append({'source_rva':rva(pc),'target_rva':rva(target),'kind':'branch'})
                        exits.add(pc)
                    continue
            if mnemonic.startswith('b.') or mnemonic in ('cbz', 'cbnz', 'tbz', 'tbnz'):
                if target is not None:
                    if entry <= target < stop:
                        todo.append(target)
                    else:
                        outside_edges.append({'source_rva':rva(pc),'target_rva':rva(target),'kind':'conditional_branch'})
                        exits.add(pc)
            todo.append(pc + 4)
        filename = f'{entry - base:08x}.asm'
        (out / filename).write_text(''.join(
            f'{pc - base:09x} {instructions[pc][0]:9} {instructions[pc][1]}\n' for pc in sorted(visited)))
        constants, constant_functions, arrays = [], set(), []
        for pc in sorted(visited):
            mnemonic, operands = instructions[pc]
            page = re.fullmatch(r'(x\d+), #(0x[0-9a-f]+)', operands) if mnemonic == 'adrp' else None
            following = instructions.get(pc + 4) if pc + 4 in visited else None
            if page is None or following is None or following[0] != 'add':
                continue
            addition = re.fullmatch(r'(x\d+), (x\d+), #(0x[0-9a-f]+|\d+)', following[1])
            if addition is None or addition.group(2) != page.group(1):
                continue
            pointer = int(page.group(2), 16) + int(addition.group(3), 0)
            constant = {'rva': rva(pc), 'register': addition.group(1), 'target_rva': rva(pointer),
                        'string': cstring(pointer) if not in_code(pointer) else None,
                        'wide_string': wide_string(pointer) if not in_code(pointer) else None,
                        'code': in_code(pointer)}
            constants.append(constant)
            if addition.group(1) == 'x3' and in_code(pointer):
                constant_functions.add(pointer)
            if not all(in_code(rebases.get(pointer + offset, 0)) for offset in (0, 8, 16)):
                continue
            slots = {}
            for slot in (0, 8, 16, 0x6c0, 0x6c8, 0x6d8, 0x7e8, 0x8f0, 0x918, 0x920):
                target = rebases.get(pointer + slot)
                slots[hex(slot)] = rva(target) if target is not None and in_code(target) else None
                if slot >= 0x6c0 and target is not None and in_code(target):
                    constant_functions.add(target)
            arrays.append({'address_rva': rva(pointer), 'reference_rva': rva(pc),
                           'kind': 'constant_code_pointer_array_candidate', 'slots': slots})
        if base + 0x3d2406c in calls:
            constant_functions.update(base + int(c['target_rva'], 16)
                                      for c in constants if c['code'])
        return {'entry_rva': rva(entry), 'range_end_rva': rva(stop),
                'boundary_kind': 'function_starts' if starts else 'bounded_reachable_context_only',
                'instruction_count': len(visited), 'direct_targets': [rva(c) for c in sorted(calls)],
                'terminal_instruction_rvas': [rva(pc) for pc in sorted(exits)],
                'truncated_at_range_end': stop - 4 in visited and stop - 4 not in exits,
                'outside_range_edges':outside_edges,
                'constant_addresses': constants, 'code_pointer_array_candidates': arrays,
                'constant_code_followups': [rva(c) for c in sorted(constant_functions)],
                'file': filename}, calls | constant_functions

    # Prioritize vehicle/seat association over generic actor constructors.
    priority = priority_names or ('GetVehiclePawn', 'ServerMoveToVehicleSeat', 'MoveVehicleSeat',
                'OnRep_WheeledVehicleBaseMovement', 'OnRep_ReplicatedBasedMovement',
                'GetMovementBase', 'SetBase', 'OnRep_AttachmentReplication')
    ordered_pairs = sorted(pairs, key=lambda p: (priority.index(p['name'])
                           if p['name'] in priority else len(priority), p['name'], p['code_rva']))
    dispatch = []
    for label, table, slot in dispatch_focus:
        target = rebases.get(base + table + slot)
        if target is None or not in_code(target):
            raise ValueError(f'Expected code target for constructor table {table:#x}+{slot:#x}')
        dispatch.append({'path': label, 'table_rva': hex(table), 'slot': hex(slot),
                         'target_rva': rva(target)})
    initial = [base + int(item['target_rva'], 16) for item in dispatch]
    initial += [base + va for va in focus_entries]
    initial += list(dict.fromkeys(base + int(p['code_rva'], 16) for p in ordered_pairs))[:100]
    # Exact thunk call target from the previous pinned report. Identity is
    # checked from the thunk's actual call edge below, not assigned by address.
    initial += [base + 0x35f6fdc, base + 0x22d23e4]
    assert rebases[base + 0x7127e10 + 0x6d8] == base + 0x1c857c0
    assert rebases[base + 0x7b21e88 + 0x6d8] == base + 0x504ec70
    queue = deque((target, 0) for target in dict.fromkeys(initial))
    contexts, done = [], set()
    if not 1<=context_limit<=2000:
        raise ValueError('Context count must be bounded to 2000')
    while queue and len(done) < context_limit:
        target, depth = queue.popleft()
        if target in done or not in_code(target):
            continue
        done.add(target)
        result, calls = context(target)
        result['discovery_depth'] = depth
        contexts.append(result)
        if depth < 2:
            for callee in sorted(calls):
                if callee not in done:
                    queue.append((callee, depth + 1))
    thunk = next(c for c in contexts if c['entry_rva'] == '0x35f6fdc')
    assert '0x22d23e4' in thunk['direct_targets']

    target_set = set(initial)
    target_set.update(base + int(t, 16) for c in contexts if c['discovery_depth'] == 0
                      for t in c['direct_targets'])
    call_refs = defaultdict(list)
    call_counts = defaultdict(int)
    table_targets = set(table_candidates)
    table_targets.update(base + int(p['record_rva'], 16) for p in pairs)
    metadata_pages = {(base + va) & ~0xfff for va in metadata_focus_rvas}
    table_targets.update(base + va for va in metadata_focus_rvas)
    table_pages = {va & ~0xfff for va in table_targets}
    address_refs = []
    movement_slot_refs = []
    block = read(code['address'], code['size'] - code['size'] % 4)
    for index, (word,) in enumerate(struct.iter_unpack('<I', block)):
        pc = code['address'] + index * 4
        movement_range = (base + 0x504d000 <= pc < base + 0x5091000
                          or base + 0x1c60000 <= pc < base + 0x1c90000)
        if (movement_range and word & 0xffc00000 == 0xf9400000
                and ((word >> 10) & 0xfff) * 8 == 0x6d8):
            start = max(code['address'], pc - 48)
            movement_slot_refs.append({'rva': rva(pc), 'slot': '0x6d8',
                                       'kind': 'bounded_movement_slot_load_candidate',
                                       'context': [f'{at - base:09x} {mnemonic} {operands}'
                                                   for at, _, mnemonic, operands in md.disasm_lite(
                                                       read(start, 112), start)]})
        if word & 0x7c000000 == 0x14000000:
            imm = word & 0x3ffffff
            if imm & 0x2000000:
                imm -= 1 << 26
            target = pc + imm * 4
            if target in target_set:
                call_counts[target] += 1
                if len(call_refs[target]) < 96:
                    start = max(code['address'], pc - 32)
                    lines = [f'{at - base:09x} {mnemonic} {operands}' for at, _, mnemonic, operands
                             in md.disasm_lite(read(start, 48), start)]
                    call_refs[target].append({'rva': rva(pc), 'link': bool(word & 0x80000000),
                                              'context': lines})
        if word & 0x9f000000 == 0x90000000:
            imm = ((word >> 5) & 0x7ffff) * 4 + ((word >> 29) & 3)
            if imm & (1 << 20):
                imm -= 1 << 21
            page = (pc & ~0xfff) + (imm << 12)
            if page in table_pages:
                source = word & 31
                for delta in range(4, 20, 4):
                    next_word = struct.unpack_from('<I', block, index * 4 + delta)[0] if index * 4 + delta + 4 <= len(block) else 0
                    if next_word & 0xff800000 != 0x91000000 or (next_word >> 5) & 31 != source:
                        continue
                    target = page + ((next_word >> 10) & 0xfff) * (4096 if next_word & (1 << 22) else 1)
                    if target in table_targets or target & ~0xfff in metadata_pages:
                        context_start = max(code['address'], pc - 32)
                        context_size = min(128, code['address'] + code['size'] - context_start)
                        address_refs.append({'rva': rva(pc), 'target_rva': rva(target),
                                             'kind': 'adrp_add_candidate' if target in table_targets else 'same_metadata_page_candidate',
                                             'add_rva': rva(pc + delta),
                                             'context': [f'{at - base:09x} {mnemonic} {operands}'
                                                         for at, _, mnemonic, operands in md.disasm_lite(
                                                             read(context_start, context_size), context_start)]})

    vector_storage = {}
    for va in (0x81484e0, 0x8148520):
        pointer = base + va
        try:
            values = list(struct.unpack('<3f', read(pointer, 12)))
            vector_storage[hex(va)] = {'file_backed': True, 'file_values': values,
                                       'runtime_value_verified': False}
        except ValueError:
            section = next((s for s in sections
                            if s['address'] <= pointer and pointer + 12 <= s['address'] + s['size']), None)
            vector_storage[hex(va)] = {'file_backed': False,
                                       'section': section['name'] if section else None,
                                       'zero_fill': section['zero_fill'] if section else None,
                                       'runtime_value_verified': False}
    pending = {target for target, _ in queue if target not in done}
    windows=[]
    for at,size in metadata_windows:
        if at%8 or size%8 or not 0<size<=4096:
            raise ValueError('Metadata windows must be aligned and bounded to 4096 bytes')
        words=[]
        for offset in range(0,size,8):
            address=base+at+offset;pointer=rebases.get(address)
            words.append({'rva':rva(address),'raw':hex(struct.unpack('<Q',read(address,8))[0]),
                'rebase_rva':rva(pointer) if pointer is not None else None,
                'code':pointer is not None and in_code(pointer),
                'string':cstring(pointer) if pointer is not None and not in_code(pointer) else None,
                'wide_string':wide_string(pointer) if pointer is not None and not in_code(pointer) else None})
        windows.append({'rva':hex(at),'bytes':size,'kind':'bounded_metadata_words','words':words})
    report = {
        'input_sha256': digest, 'pointer_formats': sorted(formats), 'rebase_count': len(rebases),
        'function_start_count': len(starts), 'names': {k: [rva(a) for a in sorted(v)] for k, v in string_addresses.items()},
        'metadata_references': references, 'adjacent_code_pointer_candidates': pairs,
        'contiguous_named_table_candidates': list(table_candidates.values()),
        'bounded_contexts': contexts,
        'constructor_table_dispatch': dispatch,
        'direct_call_counts': {rva(k): v for k, v in sorted(call_counts.items())},
        'direct_call_references': {rva(k): v for k, v in sorted(call_refs.items())},
        'metadata_address_references': address_refs,
        'metadata_windows':windows,
        'movement_slot_references': movement_slot_refs,
        'vector_storage': vector_storage,
        'remaining_context_candidates': len(pending),
        'limits': [
            'Read-only static analysis of the pinned client, not a running device or server.',
            'A name followed by a code pointer may be an exec thunk or a reflection constructor.',
            'Without LC_FUNCTION_STARTS, reachable contexts have explicit byte bounds, not established full function extents.',
            f'At most 100 named candidates plus explicit focus entries, {context_limit} contexts, two follow-up levels.',
            'Constant code-pointer arrays are candidates, not confirmed vtables until their construction use is inspected.',
            'Selected array slots, x3 code arguments, and code constants in the calibrated class-factory shape are followed.',
            'Other indirect calls remain unresolved; slot-load searches are explicitly bounded to movement code ranges.',
            'At most 96 example call sites per target; full direct-call counts are recorded.',
            'Client Server-prefixed entries do not establish deployed server code or acceptance.',
            'No gameplay behavior, network packets, movement state, or IPA bytes are modified.',
        ],
    }
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'names': len(names), 'metadata_references': len(references),
                      'code_pointer_candidates': len(pairs), 'contexts': len(contexts),
                      'function_starts': len(starts), 'read_only': True}))


if __name__ == '__main__':
    main()
