#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

// Public AVFoundation iOS 27 API compatibility. Every entry point checks actual
// selector availability; older SDKs and early iOS 27 betas remain usable.
FOUNDATION_EXPORT BOOL FilmyOpticalApertureBounds(AVCaptureDevice * _Nullable device,
                                                float *minimum, float *maximum);
FOUNDATION_EXPORT BOOL FilmySupportsOpticalExposure(AVCaptureDevice * _Nullable device,
                                                   float aperture, CMTime duration, float iso);
// Caller must hold device.lockForConfiguration(), as for the native setter.
FOUNDATION_EXPORT BOOL FilmySetOpticalExposure(AVCaptureDevice * _Nullable device,
                                              float aperture, CMTime duration, float iso,
                                              void (^ _Nullable completion)(CMTime));

NS_ASSUME_NONNULL_END
