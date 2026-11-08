// atxwrite.m — encode PNG/JPEG -> Apple ATX (com.apple.atx) via ImageIO
// build: clang -target arm64-apple-ios15.0 -isysroot SDK -fobjc-arc ...
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s in.png out.atx\n", argv[0]); return 2; }
    @autoreleasepool {
        NSURL *inURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *outURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)inURL, NULL);
        if (!src) { fprintf(stderr, "cannot open input\n"); return 1; }
        CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        if (!img) { fprintf(stderr, "cannot decode image\n"); return 1; }
        fprintf(stderr, "input %zux%zu\n", CGImageGetWidth(img), CGImageGetHeight(img));

        CFMutableDictionaryRef opts = CFDictionaryCreateMutable(NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        // try a few plausible knobs
        CFDictionarySetValue(opts, CFSTR("kCGImageDestinationLossyCompressionQuality"),
                             CFSTR("1.0"));

        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)outURL, CFSTR("com.apple.atx"), 1, opts);
        if (!dst) {
            fprintf(stderr, "no atx destination\n");
            // list available types for debugging
            CFArrayRef types = CGImageDestinationCopyTypeIdentifiers();
            CFShow(types);
            return 1;
        }
        CGImageDestinationAddImage(dst, img, opts);
        bool ok = CGImageDestinationFinalize(dst);
        fprintf(stderr, "finalize=%d\n", ok);
        CFRelease(dst); CFRelease(opts); CGImageRelease(img); CFRelease(src);
        return ok ? 0 : 1;
    }
}
