"""Inspect release module loading metadata on hosted macOS; never load or execute modules."""
import hashlib,json,os,struct,subprocess,sys
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
repo=os.environ['GITHUB_REPOSITORY'];out=Path('out/loader-audit');out.mkdir(parents=True)
def command(*args):return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT)
def inspect(label,tag):
 root=Path('input')/label;root.mkdir(parents=True)
 subprocess.run(['gh','release','download',tag,'--repo',repo,'--pattern','FanProIntegrated.dylib','--dir',str(root)],check=True)
 path=root/'FanProIntegrated.dylib';data=path.read_bytes()
 assert struct.unpack_from('<I',data)[0]==0xfeedfacf
 _,cpu,subtype,kind,count,size,flags,_=struct.unpack_from('<8I',data)
 cursor=32;dependencies=[];identity=None;versions=[];initializers=[];sections=[]
 for _ in range(count):
  cmd,length=struct.unpack_from('<II',data,cursor)
  assert length>=8 and cursor+length<=32+size
  if cmd in (0xc,0xd,0x80000018,0x8000001f):
   name_at=struct.unpack_from('<I',data,cursor+8)[0];name=data[cursor+name_at:cursor+length].split(b'\0')[0].decode()
   if cmd==0xd:identity=name
   else:dependencies.append(name)
  if cmd==0x32:
   platform,minimum,sdk,tools=struct.unpack_from('<4I',data,cursor+8);versions.append({'platform':platform,'minimum_hex':hex(minimum),'sdk_hex':hex(sdk),'tools':tools})
  if cmd==0x25:
   minimum,sdk=struct.unpack_from('<II',data,cursor+8);versions.append({'minimum_hex':hex(minimum),'sdk_hex':hex(sdk)})
  if cmd==0x19:
   nsects=struct.unpack_from('<I',data,cursor+64)[0]
   for index in range(nsects):
    at=cursor+72+index*80;name=data[at:at+16].split(b'\0')[0].decode();segment=data[at+16:at+32].split(b'\0')[0].decode()
    address,extent,offset=struct.unpack_from('<QQI',data,at+32)
    sections.append({'name':name,'segment':segment,'address_hex':hex(address),'size':extent,'offset':offset})
    if name in ('__mod_init_func','__init_offsets'):initializers.append(sections[-1])
  cursor+=length
 assert cursor==32+size
 release=json.loads(command('gh','api',f'repos/{repo}/releases/tags/{tag}'))
 asset=next(a for a in release['assets'] if a['name']=='FanProIntegrated.dylib')
 digest=hashlib.sha256(data).hexdigest();assert asset['digest']=='sha256:'+digest
 sig=command('codesign','--verify','--strict',str(path));(out/f'{label}-signature.txt').write_text(sig)
 imports=command('xcrun','nm','-u',str(path));(out/f'{label}-imports.txt').write_text(imports)
 headers=command('xcrun','otool','-L',str(path))+'\n'+command('xcrun','otool','-l',str(path));(out/f'{label}-load-commands.txt').write_text(headers)
 disassembly=command('xcrun','llvm-objdump','--macho','--disassemble','--demangle',str(path))
 lines=disassembly.splitlines();selected=[]
 for n,line in enumerate(lines):
  if line.endswith(':') and any(word in line for word in ('FanProEntry','FanProStart','GLOBAL__sub_I','cxx_global_var_init')):selected.extend(lines[n:n+120])
 (out/f'{label}-startup-context.txt').write_text('\n'.join(selected)+'\n')
 return {'tag':tag,'sha256':digest,'cpu':hex(cpu),'subtype':hex(subtype),'filetype':kind,'flags':hex(flags),
  'identity':identity,'dependencies':dependencies,'versions':versions,'initializer_sections':initializers,'imports':sorted(line.strip() for line in imports.splitlines() if line.strip()),'signature_verified':True,'release_digest_verified':True}
i1=inspect('i1','integrated-9ac6158aaa63');i2=inspect('i2','integrated-c1f92ca3f01d')
report={'i1':i1,'i2':i2,'new_imports':sorted(set(i2['imports'])-set(i1['imports'])),
 'removed_imports':sorted(set(i1['imports'])-set(i2['imports'])),
 'dependencies_equal':i1['dependencies']==i2['dependencies'],'versions_equal':i1['versions']==i2['versions'],
 'scope':'Static inspection of original published modules only; does not validate the injected/resigned copy or reproduce on-device launch'}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
