# PairBack

PairBack helps pair a newer Apple Watch with an older iPhone without updating iOS. It combines the three settings used to pair an Apple Watch Series 10 on watchOS 26.5 with an iPhone 16 Pro on iOS 18.6.2. That is the only pairing combination verified so far.

PairBack has no device-model or build whitelist. It checks Lara DarkSword's published iOS ranges: **17.0–18.7.1** and **26.0–26.0.1**. DarkSword does not support A19/M5 devices. Other iPhone and watch combinations may behave differently.

## Changes

| Setting | Value |
| --- | --- |
| NanoRegistry `networkrelay_pairing` feature flag | Enabled |
| MobileGestalt `AppleInternalInstall` cache entries | `1` |
| NanoRegistry pairing limits | `99 / 23 / 10 / 6` |

PairBack saves the original files before writing and can restore its own changes. It validates the MobileGestalt key location and file structure, preserves unrelated plist entries, and checks both disk and live NanoRegistry preferences. `AppleInternalInstall` is device-wide while enabled. The vendored DarkSword code has launchd persistence disabled; see [vendor provenance](Vendor/Lara/README.md).

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
