// Private WindowServer API. See docs/architecture.md, "Replacing the Dock switcher" and "Activation".

#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>

// Taking ⌘⇥ away from the Dock. Exported by CoreGraphics (re-exported from SkyLight), so it links normally.
typedef CF_ENUM(int32_t, CGSSymbolicHotKey) {
    CGSSymbolicHotKeyCommandTab = 1,
    CGSSymbolicHotKeyCommandShiftTab = 2,
};

extern CGError CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey, bool isEnabled);
extern bool CGSIsSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey);

// Making another process frontmost, the way the Dock does. Only SkyLight exports it, so it is looked up
// at run time (AppActivator). `window` 0 together with `SLPSModeNoWindows` activates an app that has no windows.
typedef CF_OPTIONS(uint32_t, SLPSMode) {
    SLPSModeAllWindows = 0x100,
    SLPSModeUserGenerated = 0x200,
    SLPSModeNoWindows = 0x400,
};

typedef CGError (*SLPSSetFrontProcessWithOptionsFunction)(ProcessSerialNumber *psn, CGWindowID window, SLPSMode mode);

// The WindowServer id of an Accessibility window. Exported by HIServices, so it links normally.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);

// GetProcessForPID is deprecated but is the only way to get the ProcessSerialNumber SkyLight expects.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline OSStatus TSGetProcessForPID(pid_t pid, ProcessSerialNumber *psn) {
    return GetProcessForPID(pid, psn);
}
#pragma clang diagnostic pop
