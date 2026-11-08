// prstool2.m — fetch/modify/push ATX face gallery via PosterBoardServices PRSService
// commands:
//   fetch                     fetch gallery, save /var/tmp/gallery.plist
//   dump <plist>              unarchive and describe object graph
//   push <plist>              unarchive and push as gallery update
//   additem <plist> <slug>    unarchive, duplicate a WK item with new slug, push
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void (^PRSGalleryBlock)(id config, NSDate *date, NSError *err);
typedef void (^PRSErrorBlock)(NSError *err);

static id SV = nil;
static void *dl(void) {
    static void *h;
    if (!h) {
        dlopen("/System/Library/PrivateFrameworks/AppPredictionClient.framework/AppPredictionClient", RTLD_NOW|RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/PosterKit.framework/PosterKit", RTLD_NOW|RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/PosterBoard.framework/PosterBoard", RTLD_NOW|RTLD_GLOBAL);
        h = dlopen("/System/Library/PrivateFrameworks/PosterBoardServices.framework/PosterBoardServices", RTLD_NOW|RTLD_GLOBAL);
        if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); exit(1); }
    }
    return h;
}
static id svc(void) {
    if (!SV) { dl(); Class c = NSClassFromString(@"PRSService"); SV = [[c alloc] init]; }
    return SV;
}
static int prs_wait(dispatch_semaphore_t sem, const char *w) {
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20ull*NSEC_PER_SEC)) != 0) {
        fprintf(stderr, "%s: TIMEOUT\n", w); return 0;
    }
    return 1;
}
static void describeClass(Class c, int depth) {
    unsigned int n = 0;
    objc_property_t *props = class_copyPropertyList(c, &n);
    fprintf(stderr, "%*sclass %s props:", depth*2, "", class_getName(c));
    for (unsigned i = 0; i < n; i++) fprintf(stderr, " %s", property_getName(props[i]));
    fprintf(stderr, "\n");
    if (props) free(props);
}
static void describeObject(id o, int depth) {
    if (!o || o == [NSNull null]) return;
    Class c = object_getClass(o);
    fprintf(stderr, "%*s%s <%p>\n", depth*2, "", class_getName(c), o);
    describeClass(c, depth+1);
    if ([o isKindOfClass:[NSArray class]]) {
        NSArray *a = o;
        for (NSUInteger i = 0; i < a.count && i < 40; i++) {
            fprintf(stderr, "%*s[%lu]:\n", (depth+1)*2, "", (unsigned long)i);
            describeObject(a[i], depth+2);
        }
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: %s fetch|dump|push|additem ...\n", argv[0]); return 2; }
        NSString *cmd = [NSString stringWithUTF8String:argv[1]];
        dl();

        if ([cmd isEqualToString:@"fetch"]) {
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            PRSGalleryBlock blk = ^(id config, NSDate *d, NSError *e) {
                fprintf(stderr, "fetch: %p err=%s\n", config, [[e description] UTF8String] ?: "(nil)");
                if (config) {
                    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:config requiringSecureCoding:NO error:NULL];
                    [data writeToFile:@"/var/tmp/gallery.plist" atomically:YES];
                    fprintf(stderr, "saved /var/tmp/gallery.plist (%lu bytes)\n", (unsigned long)data.length);
                }
                dispatch_semaphore_signal(sem);
            };
            ((void (*)(id, SEL, PRSGalleryBlock))objc_msgSend)(svc(), sel_registerName("fetchGallery:"), blk);
            prs_wait(sem, "fetch");
        } else if ([cmd isEqualToString:@"dump"] && argc >= 3) {
            NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
            NSError *err = nil;
            id obj = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:data error:&err];
            fprintf(stderr, "unarchived: %s err=%s\n", [[obj description] UTF8String], [[err description] UTF8String] ?: "(nil)");
            describeObject(obj, 0);
        } else if ([cmd isEqualToString:@"push"] && argc >= 3) {
            NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
            NSError *err = nil;
            id obj = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:data error:&err];
            if (!obj) { fprintf(stderr, "unarchive failed: %s\n", [[err description] UTF8String]); return 1; }
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            PRSErrorBlock blk = ^(NSError *e) {
                fprintf(stderr, "push: err=%s\n", [[e description] UTF8String] ?: "(nil)");
                dispatch_semaphore_signal(sem);
            };
            ((void (*)(id, SEL, id, PRSErrorBlock))objc_msgSend)(svc(), sel_registerName("pushPosterGalleryUpdate:completion:"), obj, blk);
            prs_wait(sem, "push");
        } else if ([cmd isEqualToString:@"additem"] && argc >= 4) {
            NSString *path = [NSString stringWithUTF8String:argv[2]];
            NSString *slug = [NSString stringWithUTF8String:argv[3]];
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSError *err = nil;
            id cfg = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:data error:&err];
            if (!cfg) { fprintf(stderr, "unarchive failed: %s\n", [[err description] UTF8String]); return 1; }
            NSArray *sections = [cfg valueForKey:@"sections"];
            fprintf(stderr, "sections=%lu\n", (unsigned long)sections.count);
            BOOL done = NO;
            NSMutableArray *newSections = [sections mutableCopy];
            for (NSUInteger si = 0; si < sections.count; si++) {
                id sec = sections[si];
                NSArray *items = [sec valueForKey:@"items"];
                for (NSUInteger ii = 0; ii < items.count; ii++) {
                    id it = items[ii];
                    NSString *ext = [it valueForKey:@"extensionBundleIdentifier"];
                    if (![ext isEqualToString:@"com.apple.WallpaperKit.CollectionsPoster"]) continue;
                    NSData *itemData = [NSKeyedArchiver archivedDataWithRootObject:it requiringSecureCoding:NO error:NULL];
                    id copy = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:itemData error:NULL];
                    NSString *newIdent = [[NSUUID UUID] UUIDString];
                    [copy setValue:newIdent forKey:@"identifier"];
                    [copy setValue:[slug stringByAppendingString:@".DYNAMIC"] forKey:@"descriptorIdentifier"];
                    NSMutableArray *newItems = [items mutableCopy];
                    [newItems addObject:copy];
                    [sec setValue:newItems forKey:@"items"];
                    [newSections replaceObjectAtIndex:si withObject:sec];
                    fprintf(stderr, "added item %s -> %s in section %lu\n", newIdent.UTF8String, slug.UTF8String, (unsigned long)si);
                    done = YES;
                    break;
                }
                if (done) break;
            }
            if (!done) { fprintf(stderr, "WK section not found\n"); return 1; }
            [cfg setValue:newSections forKey:@"sections"];
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            PRSErrorBlock blk = ^(NSError *e) {
                fprintf(stderr, "push: err=%s\n", [[e description] UTF8String] ?: "(nil)");
                dispatch_semaphore_signal(sem);
            };
            ((void (*)(id, SEL, id, PRSErrorBlock))objc_msgSend)(svc(), sel_registerName("pushPosterGalleryUpdate:completion:"), cfg, blk);
            prs_wait(sem, "push");
        } else {
            fprintf(stderr, "unknown cmd\n"); return 2;
        }
    }
    return 0;
}
