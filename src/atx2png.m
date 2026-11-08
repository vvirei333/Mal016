// atx2png.m — decode an Apple ATX file via ImageIO and write PNG
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s in.atx out.png\n", argv[0]); return 2; }
    @autoreleasepool {
        NSURL *inURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *outURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)inURL, NULL);
        if (!src) { fprintf(stderr, "cannot open\n"); return 1; }
        CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        if (!img) {
            fprintf(stderr, "decode failed (type=%s)\n",
                    CGImageSourceGetType(src) ? [(__bridge NSString*)CGImageSourceGetType(src) UTF8String] : "?");
            return 1;
        }
        fprintf(stderr, "decoded %zux%zu\n", CGImageGetWidth(img), CGImageGetHeight(img));
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)outURL,
            CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(dst, img, NULL);
        bool ok = CGImageDestinationFinalize(dst);
        fprintf(stderr, "write=%d\n", ok);
        return ok ? 0 : 1;
    }
}
