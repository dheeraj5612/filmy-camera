#import "FilmyOpticalAperture.h"
#import <math.h>

// Declarations only, NOT method implementations or private APIs. These public
// selectors are documented in Apple's iOS 27 exposure API. Declaring their
// exact Objective-C signatures lets the compiler generate correctly typed
// message sends (including CMTime and blocks) even with a pre-release SDK
// that predates the hardware announcement. No KVC, IMP casts or swizzling.
// https://developer.apple.com/documentation/avfoundation/capture-device-exposure
@interface AVCaptureDevice (FilmyPublicOpticalExposureDeclarations)
- (void)setExposureModeCustomWithLensAperture:(float)lensAperture
                                  duration:(CMTime)duration
                                       ISO:(float)ISO
                         completionHandler:(void (^ _Nullable)(CMTime))handler;
@end

@interface AVCaptureDeviceFormat (FilmyPublicOpticalExposureDeclarations)
@property(nonatomic, readonly) float minLensAperture;
@property(nonatomic, readonly) float maxLensAperture;
- (BOOL)supportsExposureModeCustomWithLensAperture:(float)lensAperture
                                       duration:(CMTime)duration
                                            ISO:(float)ISO;
@end

BOOL FilmyOpticalApertureBounds(AVCaptureDevice *device, float *minimum, float *maximum) {
    *minimum = 0;
    *maximum = 0;
    if (@available(iOS 27.0, *)) {
        AVCaptureDeviceFormat *format = device.activeFormat;
        if (![device respondsToSelector:@selector(setExposureModeCustomWithLensAperture:duration:ISO:completionHandler:)] ||
            ![format respondsToSelector:@selector(supportsExposureModeCustomWithLensAperture:duration:ISO:)] ||
            ![format respondsToSelector:@selector(minLensAperture)] ||
            ![format respondsToSelector:@selector(maxLensAperture)] ||
            ![device isExposureModeSupported:AVCaptureExposureModeCustom]) { return NO; }
        float low = format.minLensAperture;
        float high = format.maxLensAperture;
        if (!isfinite(low) || !isfinite(high) || low <= 0 || high <= low) { return NO; }
        *minimum = low;
        *maximum = high;
        return YES;
    }
    return NO;
}

BOOL FilmySupportsOpticalExposure(AVCaptureDevice *device, float aperture, CMTime duration, float iso) {
    float minimum = 0, maximum = 0;
    if (!FilmyOpticalApertureBounds(device, &minimum, &maximum) ||
        !isfinite(aperture) || aperture < minimum || aperture > maximum ||
        !isfinite(iso) || iso < device.activeFormat.minISO || iso > device.activeFormat.maxISO ||
        !CMTIME_IS_NUMERIC(duration) || CMTimeCompare(duration, device.activeFormat.minExposureDuration) < 0 ||
        CMTimeCompare(duration, device.activeFormat.maxExposureDuration) > 0) { return NO; }
    return [device.activeFormat supportsExposureModeCustomWithLensAperture:aperture duration:duration ISO:iso];
}

BOOL FilmySetOpticalExposure(AVCaptureDevice *device, float aperture, CMTime duration, float iso,
                            void (^completion)(CMTime)) {
    if (!FilmySupportsOpticalExposure(device, aperture, duration, iso)) { return NO; }
    [device setExposureModeCustomWithLensAperture:aperture duration:duration ISO:iso completionHandler:completion];
    return YES;
}
