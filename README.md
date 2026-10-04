# PairBack

PairBack enables the hidden Network Relay Pairing that's enabled on iOS 26.0+ by default but gated behind an Apple Internal flag on iOS 18.x. I'm not yet sure if the path it enables exists on iOS 17.0.

PairBack relies on DarkSword for sandbox escape, so it's currently supported up to 18.7.1. 

Verified on:  
| **iPhone** | **iOS** | **Watch** | **watchOS** | **Result** |
| --- | --- | --- | --- | --- |
| iPhone 16 Pro | 18.6.2 | Apple Watch Series 10 | 26.5 | SUCCESS! |
| iPhone 15 | 18.6.2 | Apple Watch SE 2nd gen | 26.5 | SUCCESS! |
| iPhone 13 Pro Max | 18.6 | Apple Watch SE 2nd gen | 26.6 | SUCCESS! |
| iPhone 11 Pro | 26.0.1 | Apple Watch Series 9 | 27.0 beta (24R5347a) | SUCCESS!

## Changes

| Setting | Value |
| --- | --- |
| NanoRegistry `networkrelay_pairing` feature flag | Enabled |
| MobileGestalt `AppleInternalInstall` cache entries | `1` |
| NanoRegistry pairing limits | `99 / 23 / 10 / 6` |

PairBack saves the original files before writing and can restore its own changes. It validates the MobileGestalt key location and file structure, preserves unrelated plist entries, and verifies the NanoRegistry plist on disk. Live NanoRegistry preferences may remain stale until reboot. `AppleInternalInstall` is device-wide while enabled. The vendored DarkSword code has launchd persistence disabled; see [vendor provenance](Vendor/Lara/README.md).

## Use

1. [Download the unsigned IPA](https://github.com/RomashkaTea/apple-pairback/releases) and sideload it.
2. Tap **Prepare Access**, **Read current values**, then **Apply all three settings**.
3. Restart the iPhone and pair the watch. If a failed attempt left an Apple Watch entry in Bluetooth settings, forget that entry before retrying.

**Restore saved values** requires Prepare Access again after a reboot. Keep the app installed until you restore or copy its `Documents/PairBackBackup`. Installing the app alone changes nothing. DarkSword has caused a kernel panic during testing, so use is experimental.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
swift test
scripts/package_unsigned_ipa.sh
```

The IPA is written to `dist/PairBack-unsigned.ipa`. Source is [AGPL-3.0](LICENSE).
