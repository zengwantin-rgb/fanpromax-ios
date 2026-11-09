// Manual capability measurement. Writes only eight bytes in our own scratch allocation.
// Game handling requests/releases a task port; no game address is supplied to vm_write.
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <poll.h>
#include <spawn.h>
#include <unistd.h>
#include <dlfcn.h>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <fcntl.h>
#include <signal.h>
#include <initializer_list>

extern char **environ;
static NSString *const Folder=@"/var/mobile/Library/Application Support/io.github.zengwantin.fanpromax";
static constexpr uint64_t Original=0x4e53505343524131ULL,Replacement=0x4e53505343524132ULL;
struct Handshake {uint64_t magic,address;int32_t pid;uint32_t reserved;};
static void save(NSDictionary *report) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path=[Folder stringByAppendingPathComponent:@"memory-check.json"];
    if ([data writeToFile:path atomically:YES])
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:nil];
}
static NSDictionary *permissions() {
    using Create=CFTypeRef (*)(CFAllocatorRef);
    using Copy=CFTypeRef (*)(CFTypeRef,CFStringRef,CFErrorRef *);
    auto create=reinterpret_cast<Create>(dlsym(RTLD_DEFAULT,"SecTaskCreateFromSelf"));
    auto copy=reinterpret_cast<Copy>(dlsym(RTLD_DEFAULT,"SecTaskCopyValueForEntitlement"));
    CFTypeRef task=create ? create(kCFAllocatorDefault) : nullptr;
    NSMutableDictionary *out=[@{@"query_available":@(task && copy)} mutableCopy];
    if (task && copy) for (NSString *key in @[@"platform-application",@"task_for_pid-allow",@"get-task-allow",
        @"com.apple.system-task-ports.control",@"com.apple.system-task-ports.read",
        @"com.apple.private.security.no-container",@"com.apple.private.security.no-sandbox"]) {
        CFTypeRef value=copy(task,(__bridge CFStringRef)key,nullptr);
        if (value) out[key]=CFBridgingRelease(value);
    }
    if (task) CFRelease(task);return out;
}
static NSDictionary *signingStatus(pid_t pid) {
    // Read-only CS_OPS_STATUS. Constants from XNU xnu-10002.1.13
    // bsd/sys/codesign.h and osfmk/kern/cs_blobs.h; no flag mutation.
    using CSOps=int (*)(pid_t,unsigned int,void *,size_t);
    auto query=reinterpret_cast<CSOps>(dlsym(RTLD_DEFAULT,"csops"));
    if (!query) return @{@"api_available":@NO,@"status_known":@NO};
    uint32_t flags=0;errno=0;
    int rc=query(pid,0,&flags,sizeof flags);int saved=errno;
    NSMutableDictionary *out=[@{@"api_available":@YES,@"status_known":@(rc==0),
        @"return":@(rc),@"errno":@(saved)} mutableCopy];
    if (rc==0) {
        out[@"flags_hex"]=[NSString stringWithFormat:@"0x%08x",flags];
        out[@"valid"]=@((flags&0x00000001U)!=0);
        out[@"get_task_allow"]=@((flags&0x00000004U)!=0);
        out[@"entitlements_validated"]=@((flags&0x00004000U)!=0);
        out[@"platform_binary"]=@((flags&0x04000000U)!=0);
        out[@"debugged"]=@((flags&0x10000000U)!=0);
    }
    return out;
}
static NSDictionary *requestControl(pid_t pid,mach_port_t &port) {
    port=MACH_PORT_NULL;errno=0;
    kern_return_t rc=task_for_pid(mach_task_self(),pid,&port);int saved=errno;
    return @{@"target_pid":@(pid),@"task_for_pid_return":@(rc),@"errno":@(saved),
        @"mach_error":@(mach_error_string(rc)),
        @"port_valid":@(MACH_PORT_VALID(port)),@"port_acquired":@(rc==KERN_SUCCESS && MACH_PORT_VALID(port))};
}
static NSDictionary *requestRead(pid_t pid,mach_port_t &port) {
    port=MACH_PORT_NULL;
    using ReadPort=int (*)(mach_port_name_t,int,mach_port_name_t *);
    auto read=reinterpret_cast<ReadPort>(dlsym(RTLD_DEFAULT,"task_read_for_pid"));
    if (!read) return @{@"api_available":@NO,@"port_acquired":@NO};
    errno=0;kern_return_t rc=read(mach_task_self(),pid,&port);int saved=errno;
    return @{@"api_available":@YES,@"target_pid":@(pid),@"task_read_for_pid_return":@(rc),
        @"mach_error":@(mach_error_string(rc)),@"errno":@(saved),
        @"port_valid":@(MACH_PORT_VALID(port)),@"port_acquired":@(rc==KERN_SUCCESS && MACH_PORT_VALID(port))};
}
static bool exactRead(int fd,void *out,size_t length,int timeout=2000) {
    auto *p=static_cast<uint8_t *>(out);
    while (length) {
        struct pollfd ready{fd,POLLIN,0};int rc;
        do {rc=poll(&ready,1,timeout);} while (rc<0 && errno==EINTR);
        if (rc<=0) return false;
        ssize_t copied=read(fd,p,length);
        if (copied<0 && errno==EINTR) continue;
        if (copied<=0) return false;
        p+=copied;length-=static_cast<size_t>(copied);
    }
    return true;
}
static int scratchChild() {
    void *page=mmap(nullptr,static_cast<size_t>(getpagesize()),PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
    if (page==MAP_FAILED) return 70;
    *static_cast<volatile uint64_t *>(page)=Original;
    Handshake hello{Original,reinterpret_cast<uint64_t>(page),getpid(),0};
    if (write(STDOUT_FILENO,&hello,sizeof hello)!=static_cast<ssize_t>(sizeof hello)) return 71;
    char command=0;
    bool received=exactRead(STDIN_FILENO,&command,1,10000);
    uint64_t value=*static_cast<volatile uint64_t *>(page);
    munmap(page,static_cast<size_t>(getpagesize()));
    return received && command=='Q' && value==Original ? 0 : 72;
}
static NSDictionary *scratchTransaction(mach_port_t ownedTask,uint64_t ownedAddress) {
    // Called only with this process's page or a page received on our newly spawned child's pipe.
    uint64_t before=0,after=0,restored=0;vm_size_t copied=0;
    kern_return_t readRC=vm_read_overwrite(ownedTask,ownedAddress,sizeof before,reinterpret_cast<vm_address_t>(&before),&copied);
    NSMutableDictionary *out=[@{@"read_return":@(readRC),@"read_bytes":@(copied),
        @"initial_matches":@(readRC==KERN_SUCCESS && copied==8 && before==Original),@"write_attempted":@NO} mutableCopy];
    if (readRC!=KERN_SUCCESS || copied!=8 || before!=Original) return out;
    uint64_t replacement=Replacement;
    kern_return_t writeRC=vm_write(ownedTask,ownedAddress,reinterpret_cast<vm_offset_t>(&replacement),sizeof replacement);
    out[@"write_attempted"]=@YES;out[@"write_return"]=@(writeRC);
    copied=0;kern_return_t checkRC=vm_read_overwrite(ownedTask,ownedAddress,sizeof after,reinterpret_cast<vm_address_t>(&after),&copied);
    out[@"readback_return"]=@(checkRC);out[@"write_confirmed"]=@(checkRC==KERN_SUCCESS && copied==8 && after==Replacement);
    // Restore even after a failed write/readback; it is still only our private scratch page.
    uint64_t original=Original;
    kern_return_t restoreRC=vm_write(ownedTask,ownedAddress,reinterpret_cast<vm_offset_t>(&original),sizeof original);
    copied=0;kern_return_t finalRC=vm_read_overwrite(ownedTask,ownedAddress,sizeof restored,reinterpret_cast<vm_address_t>(&restored),&copied);
    out[@"restore_return"]=@(restoreRC);out[@"restored"]=@(finalRC==KERN_SUCCESS && copied==8 && restored==Original);
    return out;
}
static NSDictionary *testSelf() {
    // Separate direct self-memory access from task_for_pid's policy checks.
    mach_port_t port=MACH_PORT_NULL;
    NSMutableDictionary *out=[@{@"control":requestControl(getpid(),port)} mutableCopy];
    if (MACH_PORT_VALID(port)) mach_port_deallocate(mach_task_self(),port);
    void *page=mmap(nullptr,static_cast<size_t>(getpagesize()),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    if (page==MAP_FAILED) {out[@"allocation_errno"]=@(errno);return out;}
    *static_cast<uint64_t *>(page)=Original;
    out[@"direct_self_memory"]=scratchTransaction(mach_task_self(),reinterpret_cast<uint64_t>(page));
    munmap(page,static_cast<size_t>(getpagesize()));
    return out;
}
static NSDictionary *testOwnChild() {
    int input[2],output[2];
    if (pipe(input)) return @{@"stage":@"pipe_input",@"errno":@(errno)};
    if (pipe(output)) {int error=errno;close(input[0]);close(input[1]);return @{@"stage":@"pipe_output",@"errno":@(error)};}
    // Pipes are inherited only through the explicit stdin/stdout dup actions.
    for (int fd:{input[0],input[1],output[0],output[1]}) fcntl(fd,F_SETFD,FD_CLOEXEC);
    char path[4096];uint32_t capacity=sizeof path;
    int rc=_NSGetExecutablePath(path,&capacity);
    posix_spawn_file_actions_t actions;int actionsRC=posix_spawn_file_actions_init(&actions);
    if (!rc) rc=actionsRC;
    if (!rc) rc=posix_spawn_file_actions_adddup2(&actions,input[0],STDIN_FILENO);
    if (!rc) rc=posix_spawn_file_actions_adddup2(&actions,output[1],STDOUT_FILENO);
    const char *args[]={path,"--scratch",nullptr};pid_t child=0;
    if (!rc) rc=posix_spawn(&child,path,&actions,nullptr,const_cast<char **>(args),environ);
    if (!actionsRC) posix_spawn_file_actions_destroy(&actions);
    close(input[0]);close(output[1]);
    NSMutableDictionary *out=[@{@"spawn_return":@(rc),@"child_pid":@(child),@"write_attempted":@NO} mutableCopy];
    if (!rc) {
        Handshake hello{};
        bool valid=exactRead(output[0],&hello,sizeof hello) && hello.magic==Original && hello.pid==child &&
            hello.address>=0x10000 && hello.address<0x0000fffffffffff8ULL && !(hello.address&7);
        out[@"handshake_valid"]=@(valid);
        if (valid) {
            out[@"signing_before_control"]=signingStatus(child);
            mach_port_t readPort=MACH_PORT_NULL;
            NSMutableDictionary *read=[requestRead(child,readPort) mutableCopy];
            if ([read[@"port_acquired"] boolValue]) {
                uint64_t value=0;vm_size_t copied=0;
                kern_return_t rc=vm_read_overwrite(readPort,hello.address,sizeof value,reinterpret_cast<vm_address_t>(&value),&copied);
                read[@"read_return"]=@(rc);read[@"read_bytes"]=@(copied);
                read[@"read_confirmed"]=@(rc==KERN_SUCCESS && copied==sizeof value && value==Original);
            }
            if (MACH_PORT_VALID(readPort)) mach_port_deallocate(mach_task_self(),readPort);
            out[@"read"]=read;
            mach_port_t port=MACH_PORT_NULL;NSDictionary *control=requestControl(child,port);out[@"control"]=control;
            if ([control[@"port_acquired"] boolValue]) [out addEntriesFromDictionary:scratchTransaction(port,hello.address)];
            if (MACH_PORT_VALID(port)) mach_port_deallocate(mach_task_self(),port);
        }
        char quit='Q';(void)write(input[1],&quit,1);
        int status=0;pid_t waited=0;
        for (unsigned i=0;i<50 && !waited;++i) {
            waited=waitpid(child,&status,WNOHANG);
            if (waited<0 && errno==EINTR) waited=0;
            if (!waited) usleep(100000);
        }
        if (!waited) {
            out[@"child_timeout"]=@YES;kill(child,SIGKILL); // Only our posix_spawn child.
            do {waited=waitpid(child,&status,0);} while (waited<0 && errno==EINTR);
        }
        if (waited==child) {
            if (WIFEXITED(status)) out[@"child_exit"]=@(WEXITSTATUS(status));
            if (WIFSIGNALED(status)) out[@"child_signal"]=@(WTERMSIG(status));
        }
    }
    close(input[1]);close(output[0]);return out;
}
static NSDictionary *testGameControl() {
    using List=int (*)(void *,int);using Path=int (*)(int,void *,uint32_t);
    auto list=reinterpret_cast<List>(dlsym(RTLD_DEFAULT,"proc_listallpids"));
    auto path=reinterpret_cast<Path>(dlsym(RTLD_DEFAULT,"proc_pidpath"));
    if (!list || !path) return @{@"status":@"process_api_unavailable",@"write_attempted":@NO};
    int pids[8192];int count=list(pids,sizeof pids);if (count>8192) count=8192;
    for (int i=0;i<count;++i) {
        char filename[4096]{};if (pids[i]<=0 || path(pids[i],filename,sizeof filename)<=0) continue;
        filename[sizeof filename-1]=0;const char *leaf=strrchr(filename,'/');
        if (!leaf || strcmp(leaf+1,"ExtremeGame")) continue;
        NSString *app=[[NSString stringWithUTF8String:filename] stringByDeletingLastPathComponent];
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Info.plist"]];
        if (![info[@"CFBundleIdentifier"] isEqualToString:@"com.pubg.newstate"]) continue;
        if (![info[@"CFBundleShortVersionString"] isEqualToString:@"0.9.98"] || ![info[@"CFBundleVersion"] isEqualToString:@"804"])
            return @{@"status":@"version_mismatch",@"write_attempted":@NO};
        // Observe the target's signing policy before requesting a control port.
        // CS_OPS_STATUS only reads flags; it does not enable debugging or alter the game.
        NSDictionary *signing=signingStatus(pids[i]);
        mach_port_t readPort=MACH_PORT_NULL;
        NSDictionary *read=requestRead(pids[i],readPort);
        if (MACH_PORT_VALID(readPort)) mach_port_deallocate(mach_task_self(),readPort);
        mach_port_t gamePort=MACH_PORT_NULL;
        NSMutableDictionary *out=[requestControl(pids[i],gamePort) mutableCopy];
        out[@"read"]=read;
        out[@"signing_before_control"]=signing;
        out[@"status"]=@"control_request_completed";out[@"write_attempted"]=@NO;
        if (MACH_PORT_VALID(gamePort)) mach_port_deallocate(mach_task_self(),gamePort);
        return out; // This branch never passes gamePort to scratchTransaction or vm_write.
    }
    return @{@"status":@"game_not_running",@"write_attempted":@NO};
}
static int selfTest() {
    if (strcmp(getenv("GITHUB_ACTIONS")?:"","true") || strcmp(getenv("RUNNER_ENVIRONMENT")?:"","github-hosted")) return 64;
    void *page=mmap(nullptr,static_cast<size_t>(getpagesize()),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    if (page==MAP_FAILED) return 1;
    *static_cast<uint64_t *>(page)=Original;
    NSDictionary *result=scratchTransaction(mach_task_self(),reinterpret_cast<uint64_t>(page));
    bool ok=[result[@"write_confirmed"] boolValue] && [result[@"restored"] boolValue] && *static_cast<uint64_t *>(page)==Original;
    *static_cast<uint64_t *>(page)=123;
    NSDictionary *mismatch=scratchTransaction(mach_task_self(),reinterpret_cast<uint64_t>(page));
    ok=ok && ![mismatch[@"write_attempted"] boolValue] && *static_cast<uint64_t *>(page)==123;
    munmap(page,static_cast<size_t>(getpagesize()));
    NSDictionary *baseline=testSelf();
    ok=ok && [baseline[@"direct_self_memory"][@"write_confirmed"] boolValue] &&
        [baseline[@"direct_self_memory"][@"restored"] boolValue];
    NSData *json=[NSJSONSerialization dataWithJSONObject:baseline options:0 error:nil];
    ok=ok && json!=nil && baseline[@"control"][@"mach_error"]!=nil;
    NSDictionary *signing=signingStatus(getpid());
    ok=ok && [signing[@"status_known"] boolValue] && signing[@"flags_hex"]!=nil &&
        [NSJSONSerialization dataWithJSONObject:signing options:0 error:nil]!=nil;
    if (ok) puts("PASS: actual vm_write/readback/restore in own private allocation; mismatched initial value prevents writing; self csops status and JSON export; no game involved");
    return ok ? 0 : 1;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        signal(SIGPIPE,SIG_IGN);
        if (argc==2 && !strcmp(argv[1],"--scratch")) return scratchChild();
        if (argc==2 && !strcmp(argv[1],"--self-test")) return selfTest();
        if (argc!=2 || strcmp(argv[1],"--run")) return 64;
        NSMutableDictionary *report=[@{@"version":@"0.1.0",@"schema_version":@4,@"pid":@(getpid()),@"uid":@(getuid()),@"euid":@(geteuid()),
            @"time":@(NSDate.date.timeIntervalSince1970),@"os":NSProcessInfo.processInfo.operatingSystemVersionString,
            @"runtime_entitlements":permissions(),@"self_signing_before_control":signingStatus(getpid()),
            @"developer_mode_state":@"not_measured",@"stage":@"started",@"game_memory_written":@NO,@"developer_mode_changed":@NO} mutableCopy];
        save(report);
        if (geteuid()!=0) {report[@"stage"]=@"not_root";save(report);return 65;}
        report[@"self_baseline"]=testSelf();report[@"stage"]=@"self_baseline_completed";save(report);
        report[@"own_scratch"]=testOwnChild();report[@"stage"]=@"own_scratch_completed";save(report);
        report[@"game_control"]=testGameControl();report[@"stage"]=@"completed";save(report);return 0;
    }
}
