// Mal0.m — jailbreak utility for PosterBoard/MobileGestalt on iOS 16.x
// No exploits: requires root (Dopamine). Public APIs + posix_spawn for unzip.
// Log: Documents/mal0.log, RECON header on every run.

#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/sysctl.h>
extern char **environ;

#define MG_PATH @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
#define PB_BASE @"/var/mobile/Containers/Data/Application"
#define LOG_NAME @"Mal0.log"

static NSString *gLogPath = nil;
static void L(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void L(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(stderr, "%s\n", line.UTF8String);
    if (gLogPath) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (!fh) { [[line dataUsingEncoding:NSUTF8StringEncoding] writeToFile:gLogPath atomically:YES]; }
        else { [fh seekToEndOfFile]; [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    }
}

static NSString *sysctlStr(NSString *name) {
    char buf[256]; size_t len = sizeof(buf);
    if (sysctlbyname(name.UTF8String, buf, &len, NULL, 0) == 0)
        return [NSString stringWithUTF8String:buf];
    return @"(absent)";
}

static void recon(void) {
    L(@"=== TendieTool RECON ===");
    L(@"  hw.machine      = %@", sysctlStr(@"hw.machine"));
    L(@"  kern.osrelease  = %@", sysctlStr(@"kern.osrelease"));
    L(@"  kern.osversion  = %@", sysctlStr(@"kern.osversion"));
    L(@"  uid             = %d", getuid());
    L(@"  mg plist        = %@ (exists=%d)", MG_PATH,
      (int)[[NSFileManager defaultManager] fileExistsAtPath:MG_PATH]);
}

// ---------- gestalt ----------
static NSDictionary *mgLoad(NSError **err) {
    NSData *d = [NSData dataWithContentsOfFile:MG_PATH];
    if (!d) { *err = [NSError errorWithDomain:@"Mal0" code:1 userInfo:@{NSLocalizedDescriptionKey: @"cannot read MG plist (root?)"}]; return nil; }
    NSError *e = nil;
    id p = [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListMutableContainersAndLeaves format:NULL error:&e];
    if (!p) { if (e) { *err = e; } else { *err = [NSError errorWithDomain:@"Mal0" code:4 userInfo:@{NSLocalizedDescriptionKey: @"plist parse error"}]; } return nil; }
    return p;
}
static BOOL mgSave(id plist, NSError **err) {
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!d) { *err = [NSError errorWithDomain:@"Mal0" code:2 userInfo:@{NSLocalizedDescriptionKey: @"plist serialize failed"}]; return NO; }
    // atomic: write temp, copy metadata-preserving
    NSString *tmp = [MG_PATH stringByAppendingString:@".tt_tmp"];
    if (![d writeToFile:tmp atomically:YES]) { *err = [NSError errorWithDomain:@"Mal0" code:3 userInfo:@{NSLocalizedDescriptionKey: @"write tmp failed"}]; return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm removeItemAtPath:MG_PATH error:nil] ||
        ![fm moveItemAtPath:tmp toPath:MG_PATH error:err]) {
        return NO;
    }
    return YES;
}
static int cmdGestalt(NSArray *args) {
    NSString *sub = args.count ? args[0] : @"dump";
    __autoreleasing NSError *err = nil;
    if ([sub isEqualToString:@"backup"]) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dst = [MG_PATH stringByAppendingString:@".tt_backup"];
        if (![fm fileExistsAtPath:MG_PATH]) { L(@"[X] no MG plist"); return 1; }
        [fm removeItemAtPath:dst error:nil];
        if (![fm copyItemAtPath:MG_PATH toPath:dst error:&err]) { L(@"[X] backup: %@", err); return 1; }
        L(@"[+] backup -> %@", dst); return 0;
    }
    if ([sub isEqualToString:@"restore"]) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *src = [MG_PATH stringByAppendingString:@".tt_backup"];
        if (![fm fileExistsAtPath:src]) { L(@"[X] no backup at %@", src); return 1; }
        [fm removeItemAtPath:MG_PATH error:nil];
        if (![fm copyItemAtPath:src toPath:MG_PATH error:&err]) { L(@"[X] restore: %@", err); return 1; }
        L(@"[+] restored from backup"); return 0;
    }
    NSMutableDictionary *p = [mgLoad(&err) mutableCopy];
    if (!p) { L(@"[X] %@", err.localizedDescription); return 1; }
    NSMutableDictionary *extra = p[@"CacheExtra"];
    if (![sub isEqualToString:@"dump"] && !extra) {
        extra = [NSMutableDictionary dictionary]; p[@"CacheExtra"] = extra;
    }
    if ([sub isEqualToString:@"dump"]) {
        L(@"CacheVersion=%@ CacheUUID=%@ keys=%lu", p[@"CacheVersion"], p[@"CacheUUID"],
          (unsigned long)[(NSDictionary *)p[@"CacheExtra"] count]);
        for (NSString *k in [(NSDictionary *)p[@"CacheExtra"] allKeys])
            L(@"  %@ = %@", k, p[@"CacheExtra"][k]);
        return 0;
    }
    if ([sub isEqualToString:@"get"] && args.count >= 2) {
        L(@"%@ = %@", args[1], extra[args[1]] ?: @"<absent>"); return 0;
    }
    if ([sub isEqualToString:@"set"] && args.count >= 3) {
        // value parsing: int, bool true/false, else string
        NSString *v = args[2];
        id obj = nil;
        if ([v isEqualToString:@"true"] || [v isEqualToString:@"false"])
            obj = @([v isEqualToString:@"true"]);
        else if ([v integerValue] && [v rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound)
            obj = @(v.integerValue);
        else obj = v;
        extra[args[1]] = obj;
        if (!mgSave(p, &err)) { L(@"[X] %@", err); return 1; }
        L(@"[+] %@ = %@", args[1], obj); return 0;
    }
    if ([sub isEqualToString:@"rm"] && args.count >= 2) {
        if (!extra[args[1]]) { L(@"[=] %@ absent", args[1]); return 0; }
        [extra removeObjectForKey:args[1]];
        if (!mgSave(p, &err)) { L(@"[X] %@", err); return 1; }
        L(@"[-] removed %@", args[1]); return 0;
    }
    L(@"usage: gestalt dump|get K|set K V|rm K|backup|restore"); return 2;
}

// ---------- posterboard ----------
static NSString *findPBContainer(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *apps = [fm contentsOfDirectoryAtPath:PB_BASE error:nil];
    for (NSString *uuid in apps) {
        NSString *p = [PB_BASE stringByAppendingPathComponent:uuid];
        NSString *probe = [p stringByAppendingPathComponent:@"Library/Application Support/PRBPosterExtensionDataStore"];
        if ([fm fileExistsAtPath:probe]) return p;
    }
    return nil;
}
static int runUnzip(NSString *zip, NSString *dst) {
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    pid_t pid; int st;
    const char *argv[] = {"/usr/bin/unzip", "-o", zip.UTF8String, "-d", dst.UTF8String, NULL};
    if (posix_spawn(&pid, argv[0], &fa, NULL, (char *const *)argv, environ) != 0) {
        L(@"[X] unzip spawn failed (is unzip installed? bootstrap: apt install unzip)"); return 1;
    }
    waitpid(pid, &st, 0);
    return WEXITSTATUS(st);
}
static int cmdTendie(NSArray *args) {
    NSString *sub = args.count ? args[0] : @"inspect";
    __autoreleasing NSError *err = nil;
    if ([sub isEqualToString:@"inspect"] && args.count >= 2) {
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tt_inspect"];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        if (runUnzip(args[1], tmp)) return 1;
        L(@"=== contents of %@ ===", args[1]);
        NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtPath:tmp];
        NSString *f; NSUInteger n = 0;
        while ((f = [e nextObject])) { if (n < 200) L(@"  %@", f); n++; }
        L(@"  total entries: %lu", (unsigned long)n);
        return 0;
    }
    if ([sub isEqualToString:@"import"] && args.count >= 2) {
        NSString *pb = findPBContainer();
        if (!pb) { L(@"[X] PosterBoard container not found"); return 1; }
        L(@"[i] PB container: %@", pb);
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tt_import"];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        if (runUnzip(args[1], tmp)) return 1;
        // copy every *.plist under Descriptors dirs into the matching Extensions path
        NSString *extBase = [pb stringByAppendingPathComponent:@"Library/Application Support/PRBPosterExtensionDataStore"];
        NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtPath:tmp];
        NSString *f; NSFileManager *fm = [NSFileManager defaultManager]; int copied = 0;
        while ((f = [e nextObject])) {
            if (![f.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
            NSString *src = [tmp stringByAppendingPathComponent:f];
            // target: keep relative layout after the bundle-id directory
            NSArray *parts = [f pathComponents];
            NSString *rel = [parts componentsJoinedByString:@"/"];
            NSString *dst = [extBase stringByAppendingPathComponent:rel];
            [fm createDirectoryAtPath:[dst stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            if ([fm copyItemAtPath:src toPath:dst error:&err]) { copied++; L(@"[+] %@", rel); }
            else L(@"[-] %@ (%@)", rel, err.localizedDescription);
        }
        L(@"=== imported %d descriptor files; respring to apply ===", copied);
        L(@"[!] 16.x may reject unknown descriptor fields — check PosterBoard after respring");
        return copied ? 0 : 1;
    }
    L(@"usage: tendie inspect X.tendies | import X.tendies"); return 2;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray *args = [NSProcessInfo processInfo].arguments;
        if (args.count < 2) {
            fprintf(stderr, "TendieTool v0.1 — jailbreak PosterBoard/MG CLI (iOS 16.x)\n"
                    "usage: Mal0 <recon|gestalt|tendie> [args]\n"); return 2;
        }
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        gLogPath = [docs stringByAppendingPathComponent:LOG_NAME];
        recon();
        NSString *cmd = args[1];
        NSArray *rest = [args subarrayWithRange:NSMakeRange(2, args.count - 2)];
        if ([cmd isEqualToString:@"recon"]) return 0;
        if ([cmd isEqualToString:@"gestalt"]) return cmdGestalt(rest);
        if ([cmd isEqualToString:@"tendie"]) return cmdTendie(rest);
        L(@"unknown command: %@", cmd); return 2;
    }
}
