#if OPEN1000X_DEMO
// Demo builds only (`DEMO=1 ./scripts/build-app.sh`). Regular builds don't compile this file's
// contents, so masking can't be switched on by accident in a release.

/// Replaces personal device names with generic ones for screenshots and recordings.
enum DemoMode {
    /// Picks a name from the Bluetooth major device class: 0x01 computer, 0x02 phone.
    static func deviceName(for classOfDevice: UInt32) -> String {
        switch (classOfDevice >> 8) & 0x1F {
        case 0x01: "MacBook Pro"
        case 0x02: "iPhone 16"
        default: "Bluetooth Device"
        }
    }
}
#endif
