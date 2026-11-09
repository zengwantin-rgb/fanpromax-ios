"""Read-only layout parser; no patching routines included."""
import struct

def layout(data):
    if len(data) < 32 or struct.unpack_from('<II', data) != (0xfeedfacf, 0x100000c):
        raise ValueError('Expected thin ARM64 Mach-O')
    count, size = struct.unpack_from('<II', data, 16)
    end = 32 + size
    if end > len(data):
        raise ValueError('Truncated load commands')
    segments, sections = [], []
    cursor = 32
    for _ in range(count):
        if cursor + 8 > end:
            raise ValueError('Truncated command')
        command, length = struct.unpack_from('<II', data, cursor)
        if length < 8 or length % 8 or cursor + length > end:
            raise ValueError('Invalid command size')
        if command == 0x19:
            if length < 72:
                raise ValueError('Truncated segment')
            name = data[cursor + 8:cursor + 24].rstrip(b'\0').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<4Q', data, cursor + 24)
            maxprot, initprot, nsects = struct.unpack_from('<3I', data, cursor + 56)
            if 72 + 80 * nsects != length or fileoff + filesize > len(data):
                raise ValueError('Invalid segment bounds')
            segments.append({'name': name, 'vmaddr': vmaddr, 'vmsize': vmsize,
                             'offset': fileoff, 'size': filesize, 'initprot': initprot})
            for i in range(nsects):
                at = cursor + 72 + 80 * i
                sectname = data[at:at + 16].rstrip(b'\0').decode()
                segname = data[at + 16:at + 32].rstrip(b'\0').decode()
                address, amount = struct.unpack_from('<QQ', data, at + 32)
                offset, _, reloff, nreloc, flags = struct.unpack_from('<5I', data, at + 48)
                zero_fill = flags & 0xff in (1, 0xc, 0x12)
                if not zero_fill and amount and (offset < end or offset + amount > len(data)):
                    raise ValueError('Invalid section bounds')
                sections.append({'name': sectname, 'segment': segname, 'address': address,
                    'size': amount, 'offset': offset, 'nreloc': nreloc, 'zero_fill': zero_fill})
        cursor += length
    if cursor != end:
        raise ValueError('Command count mismatch')
    return end, segments, sections


