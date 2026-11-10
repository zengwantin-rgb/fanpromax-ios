import struct
from types import SimpleNamespace
package=SimpleNamespace(MACH_MAGIC=b"\xcf\xfa\xed\xfe")
LIBRARY="@executable_path/Frameworks/FanProIntegrated.dylib"

def dependency_names(path):
    data = path.read_bytes()
    count, size = struct.unpack_from('<II', data, 16)
    cursor, end = 32, 32 + size
    names = []
    for _ in range(count):
        if cursor + 8 > end or end > len(data):
            raise ValueError('invalid load command bounds')
        command, length = struct.unpack_from('<II', data, cursor)
        if length < 8 or cursor + length > end:
            raise ValueError('invalid load command size')
        if command in (0xc, 0x80000018, 0x8000001f):
            if length < 24:
                raise ValueError('invalid dependency command')
            offset = struct.unpack_from('<I', data, cursor + 8)[0]
            if not 24 <= offset < length:
                raise ValueError('invalid dependency name')
            names.append(data[cursor + offset:cursor + length].split(b'\0')[0].decode())
        cursor += length
    if cursor != end:
        raise ValueError('inconsistent command count')
    return names


def add_dependency(path, library=LIBRARY):
    """Append a load command in existing zero padding; never move a section."""
    data = bytearray(path.read_bytes())
    if len(data) < 32 or data[:4] != package.MACH_MAGIC:
        raise ValueError('expected a thin Mach-O')
    count, size = struct.unpack_from('<II', data, 16)
    end = 32 + size
    if end > len(data):
        raise ValueError('truncated load commands')
    first_section = len(data)
    cursor = 32
    for _ in range(count):
        if cursor + 8 > end:
            raise ValueError('truncated load command')
        cmd, length = struct.unpack_from('<II', data, cursor)
        if length < 8 or length % 8 or cursor + length > end:
            raise ValueError('invalid load command')
        if cmd in (0xc, 0x80000018, 0x8000001f):
            if length < 24:
                raise ValueError('invalid dylib command')
            offset = struct.unpack_from('<I', data, cursor + 8)[0]
            if offset < 24 or offset >= length:
                raise ValueError('invalid dylib name offset')
            name = bytes(data[cursor + offset:cursor + length]).split(b'\0')[0].decode()
            if name == library:
                raise ValueError('dependency already installed')
        if cmd == 0x19:
            if length < 72:
                raise ValueError('truncated segment')
            sections = struct.unpack_from('<I', data, cursor + 64)[0]
            if 72 + 80 * sections > length:
                raise ValueError('truncated section table')
            for i in range(sections):
                section = cursor + 72 + 80 * i
                offset = struct.unpack_from('<I', data, section + 48)[0]
                amount = struct.unpack_from('<Q', data, section + 40)[0]
                if offset and amount:
                    if offset < end or offset + amount > len(data):
                        raise ValueError('invalid section file range')
                    first_section = min(first_section, offset)
        cursor += length
    if cursor != end or first_section == len(data):
        raise ValueError('missing section boundary or inconsistent commands')
    name = library.encode() + b'\0'
    length = (24 + len(name) + 7) & ~7
    command = (struct.pack('<6I', 0xc, length, 24, 0, 0, 0) + name).ljust(length, b'\0')
    if end + length > first_section or any(data[end:end + length]):
        raise ValueError('not enough unused header padding')
    data[end:end + length] = command
    struct.pack_into('<II', data, 16, count + 1, size + length)
    path.write_bytes(data)
    return {'dependency': library, 'command_offset': end, 'command_size': length,
            'section_offsets_unchanged': True}


