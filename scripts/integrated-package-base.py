"""GitHub-hosted macOS only: sign two user-supplied IPA comparison packages.

Never execute input binaries. Preserve application resources and __text sections.
The baseline retains the input entitlements; the second adds get-task-allow only.
"""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import uuid
import zipfile

EXPECTED_SHA256 = '50460045f0389ebbffbdbb56119fe9f0a7fda18ea0d19ba8d43592ec9c5df9ab'
EXPECTED_UUID = 'af49432e-9f7f-3d7c-9470-8cf90e3b3378'
APP = Path('Payload/ExtremeGame.app')
MACH_MAGIC = b'\xcf\xfa\xed\xfe'
FAT_MAGICS = {b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def archive_entries(archive):
    entries = archive.infolist()
    if not entries or len(entries) > 10000 or sum(i.file_size for i in entries) > 3 * 1024**3:
        raise ValueError('unexpected archive size or entry count')
    names = set()
    for item in entries:
        name = item.filename
        path = PurePosixPath(name)
        parts = name.rstrip('/').split('/')
        if (path.is_absolute() or '\\' in name or any(p in ('', '.', '..') for p in parts)
                or parts[0] != 'Payload' or (len(parts) > 1 and parts[1] != 'ExtremeGame.app')):
            raise ValueError('unexpected or unsafe archive path')
        canonical = str(path)
        if canonical in names:
            raise ValueError('duplicate archive path')
        names.add(canonical)
        mode = item.external_attr >> 16
        if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError('links and special files are not accepted')
        if item.flag_bits & 1:
            raise ValueError('encrypted ZIP entries are not accepted')
    return entries


def extract(source, destination):
    with zipfile.ZipFile(source) as archive:
        entries = archive_entries(archive)
        for item in entries:
            target = destination / item.filename
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as src, target.open('wb') as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)
                target.chmod(0o755 if (item.external_attr >> 16) & 0o111 else 0o644)


def macho_info(path):
    data = path.read_bytes()
    if len(data) < 32 or data[:4] != MACH_MAGIC:
        raise ValueError('expected thin 64-bit Mach-O')
    _, cpu, _, kind, count, command_size, _, _ = struct.unpack_from('<8I', data)
    if cpu != 0x100000c or kind not in (2, 6, 8) or 32 + command_size > len(data):
        raise ValueError('unexpected architecture, file type or command size')
    cursor = 32
    info = {'uuid': None, 'text_sha256': None, 'crypt': []}
    for _ in range(count):
        if cursor + 8 > 32 + command_size:
            raise ValueError('truncated load command')
        cmd, size = struct.unpack_from('<II', data, cursor)
        if size < 8 or cursor + size > 32 + command_size:
            raise ValueError('invalid load command size')
        if cmd == 0x1b:
            if size != 24:
                raise ValueError('invalid UUID command')
            info['uuid'] = str(uuid.UUID(bytes=data[cursor + 8:cursor + 24]))
        elif cmd in (0x21, 0x2c):
            if size < 20:
                raise ValueError('truncated encryption command')
            offset, length, cryptid = struct.unpack_from('<III', data, cursor + 8)
            if cryptid != 0 or offset + length > len(data):
                raise ValueError('encrypted or invalid Mach-O input')
            info['crypt'].append({'offset': offset, 'size': length, 'cryptid': cryptid})
        elif cmd == 0x19:
            if size < 72:
                raise ValueError('truncated segment command')
            sections = struct.unpack_from('<I', data, cursor + 64)[0]
            if 72 + sections * 80 > size:
                raise ValueError('truncated section table')
            for n in range(sections):
                section = cursor + 72 + n * 80
                name = data[section:section + 16].rstrip(b'\0')
                segment = data[section + 16:section + 32].rstrip(b'\0')
                if name == b'__text' and segment == b'__TEXT':
                    length = struct.unpack_from('<Q', data, section + 40)[0]
                    offset = struct.unpack_from('<I', data, section + 48)[0]
                    if not length or offset + length > len(data) or info['text_sha256'] is not None:
                        raise ValueError('invalid text section')
                    info['text_sha256'] = hashlib.sha256(data[offset:offset + length]).hexdigest()
        cursor += size
    if cursor != 32 + command_size or not info['uuid'] or not info['text_sha256']:
        raise ValueError('missing identity or text section')
    return info


def entitlements(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)],
                            capture_output=True, check=True)
    return plistlib.loads(result.stdout) if result.stdout.strip() else {}


def sign(path, permissions, temporary):
    temporary.write_bytes(plistlib.dumps(permissions))
    subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--pagesize', '4096',
                    '--generate-entitlement-der', '--entitlements', str(temporary), str(path)], check=True)
    if entitlements(path) != permissions:
        raise ValueError('signed entitlements differ from intended permissions')


def resource_digests(root, binaries):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*'))
            if p.is_file() and p not in binaries and '_CodeSignature' not in p.parts}


def package(root, output):
    # Input assets are already compressed. Stored ZIP keeps packaging bounded and fast.
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
        for path in sorted((root / 'Payload').rglob('*')):
            archive.write(path, path.relative_to(root).as_posix())
    if output.stat().st_size >= 2 * 1024**3:
        raise ValueError('output exceeds release asset size limit')
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('packaged ZIP failed CRC verification')


def main():
    if (sys.platform != 'darwin' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'):
        raise SystemExit('Signing and validation require a GitHub-hosted macOS runner.')
    source = Path(sys.argv[1])
    if digest(source) != EXPECTED_SHA256:
        raise ValueError('input does not match the user-supplied package')
    root = Path('build/game-signing')
    root.mkdir(parents=True, exist_ok=False)
    output = Path('out/game-signing')
    output.mkdir(parents=True, exist_ok=False)
    extract(source, root)
    app = root / APP
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'),
            info.get('CFBundleVersion'), info.get('CFBundleExecutable')) != (
            'com.pubg.newstate', '0.9.98', '804', 'ExtremeGame'):
        raise ValueError('unexpected game version or executable')
    binaries = {}
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if magic in FAT_MAGICS:
            raise ValueError('unexpected universal binary')
        if magic == MACH_MAGIC:
            binaries[path] = macho_info(path)
            path.chmod(0o755)
    executable = app / 'ExtremeGame'
    if executable not in binaries or binaries[executable]['uuid'] != EXPECTED_UUID:
        raise ValueError('main executable UUID mismatch')
    original_permissions = entitlements(app)
    if original_permissions.get('get-task-allow'):
        raise ValueError('baseline already permits debugging')
    resources = resource_digests(root, binaries)
    frameworks = sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True)
    accounted = {executable}
    for framework in frameworks:
        framework_info = plistlib.loads((framework / 'Info.plist').read_bytes())
        binary = framework / framework_info['CFBundleExecutable']
        if binary not in binaries:
            raise ValueError('framework executable missing')
        accounted.add(binary)
    if accounted != set(binaries):
        raise ValueError('unhandled nested executable; do not sign it implicitly')
    for framework in frameworks:
        sign(framework, entitlements(framework), Path('build/framework-entitlements.plist'))
    reports = {}
    for variant in ('baseline', 'debuggable'):
        permissions = dict(original_permissions)
        if variant == 'debuggable':
            permissions['get-task-allow'] = True
        sign(app, permissions, Path('build/game-entitlements.plist'))
        subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
        for path, before in binaries.items():
            if macho_info(path) != before:
                raise ValueError('Mach-O text, UUID or encryption metadata changed')
        if resource_digests(root, binaries) != resources:
            raise ValueError('application resources changed')
        ipa = output / f'NEW_STATE-0.9.98-804-{variant}.ipa'
        package(root, ipa)
        reports[variant] = {'file': ipa.name, 'sha256': digest(ipa), 'bytes': ipa.stat().st_size,
                            'entitlements': permissions, 'signature_verified': True,
                            'resources_unchanged': True, 'text_sections_unchanged': True,
                            'device_launch_verified': False, 'game_write_verified': False}
        print(f'PASS: {variant} signature, entitlements, text preservation, resources and ZIP CRC', flush=True)
    report = {'input_sha256': EXPECTED_SHA256, 'commit': os.environ['GITHUB_SHA'],
              'binaries': {str(p.relative_to(root)): v for p, v in binaries.items()}, 'variants': reports,
              'collision_changes': False, 'anti_detection_changes': False}
    (output / 'signing-report.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / 'SHA256SUMS').write_text(''.join(f"{r['sha256']}  {r['file']}\n" for r in reports.values()))


if __name__ == '__main__':
    main()
