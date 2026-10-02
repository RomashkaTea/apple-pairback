import CryptoKit
import Darwin
import Foundation

struct PairingStatus {
  let gestaltValue: Int64
  let gestaltExtra: NSNumber?
  let relayEnabled: Bool
  let registryDisk: NSDictionary
  let registryPreferences: NSDictionary
  let backupPresent: Bool

  var fullyApplied: Bool {
    gestaltValue == 1 && gestaltExtra?.intValue == 1 && relayEnabled
      && PairBackPlan.limitsMatch(registryDisk) && PairBackPlan.limitsMatch(registryPreferences)
  }

  var summary: String {
    let keys = PairBackPlan.limits.keys.sorted()
    let disk = keys.map { "\($0)=\((registryDisk[$0] as? NSNumber)?.intValue.description ?? "—")" }
      .joined(separator: ", ")
    let live = keys.map {
      "\($0)=\((registryPreferences[$0] as? NSNumber)?.intValue.description ?? "—")"
    }.joined(separator: ", ")
    return "MobileGestalt: \(gestaltValue) / \(gestaltExtra?.intValue.description ?? "—")\n"
      + "Network Relay: \(relayEnabled ? "on" : "off")\n"
      + "NanoRegistry file: \(disk)\nNanoRegistry preferences: \(live)\n"
      + "PairBack backup: \(backupPresent ? "present" : "none")"
  }
}

@MainActor
final class PairingStore: ObservableObject {
  static let shared = PairingStore()
  @Published private(set) var status: PairingStatus?
  @Published private(set) var message = "Prepare access to inspect the pairing settings."
  @Published private(set) var isBusy = false

  private let access = AccessController.shared
  private let fm = FileManager.default
  private let flags = "/Library/Preferences/FeatureFlags/Domain/NanoRegistry.plist"
  private let gestalt =
    "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
  private let registry = "/var/mobile/Library/Preferences/com.apple.NanoRegistry.plist"
  private let preferenceDomain = "com.apple.NanoRegistry" as CFString
  private let preferenceUser = "mobile" as CFString
  private var backup: URL {
    fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "PairBackBackup", isDirectory: true)
  }
  private var domainDirectory: URL { URL(fileURLWithPath: flags).deletingLastPathComponent() }
  private var featureDirectory: URL { domainDirectory.deletingLastPathComponent() }
  private var preferencesDirectory: URL { featureDirectory.deletingLastPathComponent() }

  private init() {}

  private func fileExists(_ path: String) throws -> Bool {
    var info = stat()
    if path.withCString({ lstat($0, &info) }) == 0 {
      guard info.st_mode & 0o170000 == 0o100000 else {
        throw PairBackError("Expected a regular file at \(path)")
      }
      return true
    }
    if errno == ENOENT { return false }
    throw PairBackError("Cannot inspect \(path): errno \(errno)")
  }

  private func directoryExists(_ path: String) throws -> Bool {
    var info = stat()
    if path.withCString({ stat($0, &info) }) == 0 {
      guard info.st_mode & 0o170000 == 0o040000 else {
        throw PairBackError("Expected a directory at \(path)")
      }
      return true
    }
    if errno == ENOENT { return false }
    throw PairBackError("Cannot inspect \(path): errno \(errno)")
  }

  private func readFile(_ path: String) throws -> Data? {
    guard try fileExists(path) else { return nil }
    return try Data(contentsOf: URL(fileURLWithPath: path))
  }

  private func registryPreferences() -> NSDictionary {
    let value = CFPreferencesCopyMultiple(
      nil, preferenceDomain, preferenceUser,
      kCFPreferencesAnyHost)
    return value as NSDictionary
  }

  private func readStatus() throws -> PairingStatus {
    guard let gestaltData = try readFile(gestalt) else {
      throw PairBackError("MobileGestalt cache is missing")
    }
    let offset = Int(pb_mobilegestalt_offset(PairBackPlan.gestaltKey))
    let (value, extra) = try PairBackPlan.gestaltValues(gestaltData, offset: offset)
    let flag = try PairBackPlan.flagEnabled(readFile(flags))
    let diskData = try readFile(registry)
    let disk = try diskData.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
    try PairBackPlan.validateLimitTypes(disk)
    let live = registryPreferences()
    try PairBackPlan.validateLimitTypes(live)
    return PairingStatus(
      gestaltValue: value, gestaltExtra: extra, relayEnabled: flag,
      registryDisk: disk, registryPreferences: live,
      backupPresent: fm.fileExists(atPath: backup.path))
  }

  func refresh() {
    guard access.isReady else {
      message = "Prepare Access first."
      return
    }
    do {
      status = try readStatus()
      message =
        status?.fullyApplied == true
        ? "All three settings are enabled. No change is needed."
        : "Review the values, then Apply if needed."
    } catch {
      message = "Read failed: \(error.localizedDescription)"
    }
  }

  private func requireReady() throws {
    guard access.isReady else {
      throw PairBackError("Prepare Access first")
    }
    guard !hasOwnerReceipts else {
      throw PairBackError("Repair the saved file ownership receipt before another write")
    }
  }

  private var receiptPaths: [String: String] {
    [
      "preferences.owner.plist": preferencesDirectory.path,
      "feature.owner.plist": featureDirectory.path,
      "domain.owner.plist": domainDirectory.path,
      "flag.owner.plist": flags,
      "gestalt.owner.plist": gestalt,
    ]
  }

  var backupAvailable: Bool { fm.fileExists(atPath: backup.path) }

  var hasOwnerReceipts: Bool {
    receiptPaths.keys.contains { fm.fileExists(atPath: backup.appendingPathComponent($0).path) }
  }

  private func withTemporaryOwner<T>(
    of path: String, receipt name: String,
    _ work: () throws -> T
  ) throws -> T {
    guard receiptPaths[name] == path else { throw PairBackError("Unapproved ownership target") }
    if path == flags || path == gestalt {
      guard try fileExists(path) else {
        throw PairBackError("Ownership target disappeared: \(path)")
      }
    } else {
      guard try directoryExists(path) else {
        throw PairBackError("Ownership directory disappeared: \(path)")
      }
    }
    var info = stat()
    guard path.withCString({ stat($0, &info) }) == 0 else {
      throw PairBackError("Cannot stat \(path): errno \(errno)")
    }
    var volume = statfs()
    guard path.withCString({ statfs($0, &volume) }) == 0,
      volume.f_flags & UInt32(MNT_RDONLY) == 0
    else {
      throw PairBackError("Ownership target is on a read-only volume: \(path)")
    }
    if info.st_uid == getuid() { return try work() }
    guard access.isReady else { throw PairBackError("Kernel access is not ready") }
    let receipt = backup.appendingPathComponent(name)
    let values: [String: NSNumber] = [
      "uid": NSNumber(value: info.st_uid),
      "gid": NSNumber(value: info.st_gid),
    ]
    try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
      .write(to: receipt, options: .atomic)
    guard path.withCString({ apfs_own($0, getuid(), info.st_gid) == 0 }) else {
      var check = stat()
      if path.withCString({ stat($0, &check) }) == 0,
        check.st_uid == info.st_uid, check.st_gid == info.st_gid
      {
        try? fm.removeItem(at: receipt)
      }
      throw PairBackError("Could not temporarily change owner of \(path)")
    }
    var result: Result<T, Error>
    do { result = .success(try work()) } catch { result = .failure(error) }
    guard path.withCString({ apfs_own($0, info.st_uid, info.st_gid) == 0 }) else {
      throw PairBackError("Could not restore owner of \(path); receipt retained")
    }
    var restored = stat()
    guard path.withCString({ stat($0, &restored) }) == 0,
      restored.st_uid == info.st_uid, restored.st_gid == info.st_gid
    else {
      throw PairBackError("Ownership readback differs at \(path); receipt retained")
    }
    try fm.removeItem(at: receipt)
    return try result.get()
  }

  func repairOwnership() {
    guard access.isReady else {
      message = "Prepare Access first."
      return
    }
    var failures: [String] = []
    for (name, path) in receiptPaths.sorted(by: { $0.key < $1.key }) {
      let receipt = backup.appendingPathComponent(name)
      guard fm.fileExists(atPath: receipt.path) else { continue }
      do {
        if path == flags || path == gestalt {
          guard try fileExists(path) else {
            throw PairBackError("Ownership target disappeared: \(path)")
          }
        } else {
          guard try directoryExists(path) else {
            throw PairBackError("Ownership directory disappeared: \(path)")
          }
        }
        let data = try Data(contentsOf: receipt)
        guard
          let values = try PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: NSNumber],
          let uid = values["uid"]?.uint32Value,
          let gid = values["gid"]?.uint32Value
        else {
          throw PairBackError("Invalid ownership receipt \(name)")
        }
        guard path.withCString({ apfs_own($0, uid, gid) == 0 }) else {
          throw PairBackError("Could not restore owner at \(path)")
        }
        var check = stat()
        guard path.withCString({ stat($0, &check) }) == 0,
          check.st_uid == uid, check.st_gid == gid
        else {
          throw PairBackError("Ownership readback differs at \(path)")
        }
        try fm.removeItem(at: receipt)
      } catch { failures.append("\(name): \(error.localizedDescription)") }
    }
    message = failures.isEmpty ? "Ownership restored." : failures.joined(separator: "; ")
  }

  private func ensureFlagDirectories() throws {
    if try !directoryExists(featureDirectory.path) {
      try withTemporaryOwner(of: preferencesDirectory.path, receipt: "preferences.owner.plist") {
        try fm.createDirectory(at: featureDirectory, withIntermediateDirectories: false)
      }
    }
    if try !directoryExists(domainDirectory.path) {
      try withTemporaryOwner(of: featureDirectory.path, receipt: "feature.owner.plist") {
        try fm.createDirectory(at: domainDirectory, withIntermediateDirectories: false)
      }
    }
  }

  private func writeFile(_ data: Data, at path: String) throws {
    let exists = try fileExists(path)
    if path == flags && !exists {
      try withTemporaryOwner(of: domainDirectory.path, receipt: "domain.owner.plist") {
        try access.overwrite(data, at: path)
      }
    } else if path == flags && exists {
      try withTemporaryOwner(of: path, receipt: "flag.owner.plist") {
        try access.overwrite(data, at: path)
      }
    } else if path == gestalt {
      try withTemporaryOwner(of: path, receipt: "gestalt.owner.plist") {
        try access.overwrite(data, at: path)
      }
    } else {
      throw PairBackError("Unapproved file write target")
    }
  }

  private func removeFlagFile() throws {
    guard try fileExists(flags) else { return }
    try withTemporaryOwner(of: domainDirectory.path, receipt: "domain.owner.plist") {
      try fm.removeItem(atPath: flags)
    }
  }

  private func removeNewDirectoryIfEmpty(_ directory: URL, receipt: String) throws {
    guard try directoryExists(directory.path) else { return }
    guard try fm.contentsOfDirectory(atPath: directory.path).isEmpty else { return }
    try withTemporaryOwner(of: directory.deletingLastPathComponent().path, receipt: receipt) {
      try fm.removeItem(at: directory)
    }
  }

  private func writeBackup(
    gestaltData: Data, flagsData: Data?, registryData: Data?,
    featureExisted: Bool, domainExisted: Bool
  ) throws {
    guard !fm.fileExists(atPath: backup.path) else {
      throw PairBackError("A PairBack backup already exists; Restore before applying again")
    }
    try fm.createDirectory(
      at: backup, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    let manifest: [String: Any] = [
      "formatVersion": NSNumber(value: 1),
      "flagsExisted": NSNumber(value: flagsData != nil),
      "registryExisted": NSNumber(value: registryData != nil),
      "featureExisted": NSNumber(value: featureExisted),
      "domainExisted": NSNumber(value: domainExisted),
      "gestaltSHA256": Data(SHA256.hash(data: gestaltData)),
      "flagsSHA256": Data(SHA256.hash(data: flagsData ?? Data())),
      "registrySHA256": Data(SHA256.hash(data: registryData ?? Data())),
    ]
    try gestaltData.write(to: backup.appendingPathComponent("gestalt.original"), options: .atomic)
    try (flagsData ?? Data()).write(
      to: backup.appendingPathComponent("flags.original"), options: .atomic)
    try (registryData ?? Data()).write(
      to: backup.appendingPathComponent("registry.original"), options: .atomic)
    try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0)
      .write(to: backup.appendingPathComponent("manifest.plist"), options: .atomic)
    guard try Data(contentsOf: backup.appendingPathComponent("gestalt.original")) == gestaltData,
      try Data(contentsOf: backup.appendingPathComponent("flags.original"))
        == (flagsData ?? Data()),
      try Data(contentsOf: backup.appendingPathComponent("registry.original"))
        == (registryData ?? Data())
    else {
      throw PairBackError("Backup readback differs")
    }
  }

  private func setRegistryTargets(from source: NSDictionary) throws {
    try PairBackPlan.validateLimitTypes(source)
    for key in PairBackPlan.limits.keys {
      CFPreferencesSetValue(
        key as CFString, source[key] as? NSNumber,
        preferenceDomain, preferenceUser, kCFPreferencesAnyHost)
    }
    guard CFPreferencesSynchronize(preferenceDomain, preferenceUser, kCFPreferencesAnyHost) else {
      throw PairBackError("NanoRegistry preference sync failed")
    }
    let after = registryPreferences()
    for key in PairBackPlan.limits.keys {
      guard (after[key] as? NSNumber) == (source[key] as? NSNumber) else {
        throw PairBackError("NanoRegistry preference readback differs for \(key)")
      }
    }
  }

  private func verifyRegistryAfterWrite(expected: NSDictionary, before: NSDictionary) throws {
    let currentData = try readFile(registry)
    let current = try currentData.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
    for key in PairBackPlan.limits.keys {
      guard (current[key] as? NSNumber) == (expected[key] as? NSNumber) else {
        throw PairBackError("NanoRegistry file readback differs for \(key)")
      }
    }
    guard PairBackPlan.unrelatedRegistryEntriesPreserved(before: before, after: current) else {
      throw PairBackError("An unrelated NanoRegistry preference changed during sync")
    }
  }

  func apply() {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    var backupComplete = false
    var touchedGestalt = false
    var touchedFlag = false
    var touchedPreferences = false
    var originalGestalt = Data()
    var originalFlag: Data?
    var originalRegistry: Data?
    var featureExisted = true
    var domainExisted = true
    do {
      try requireReady()
      let before = try readStatus()
      if before.fullyApplied {
        status = before
        message =
          "All three settings are already enabled. No files changed and no backup was created."
        return
      }
      guard let savedGestalt = try readFile(gestalt) else {
        throw PairBackError("MobileGestalt cache disappeared before Apply")
      }
      originalGestalt = savedGestalt
      originalFlag = try readFile(flags)
      originalRegistry = try readFile(registry)
      let disk = try originalRegistry.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
      let preferences = registryPreferences()
      guard disk.isEqual(preferences) else {
        throw PairBackError(
          "NanoRegistry file and preference cache disagree. Restart the iPhone before applying.")
      }
      featureExisted = try directoryExists(featureDirectory.path)
      domainExisted = try directoryExists(domainDirectory.path)
      let offset = Int(pb_mobilegestalt_offset(PairBackPlan.gestaltKey))
      let stagedGestalt = try PairBackPlan.enableGestalt(originalGestalt, offset: offset)
      let stagedFlag = try PairBackPlan.enableFlag(originalFlag)
      let stagedRegistry = disk.mutableCopy() as? NSMutableDictionary ?? NSMutableDictionary()
      for (key, value) in PairBackPlan.limits { stagedRegistry[key] = NSNumber(value: value) }
      try writeBackup(
        gestaltData: originalGestalt, flagsData: originalFlag,
        registryData: originalRegistry, featureExisted: featureExisted,
        domainExisted: domainExisted)
      backupComplete = true

      if before.gestaltValue != 1 || before.gestaltExtra?.intValue != 1 {
        touchedGestalt = true
        try writeFile(stagedGestalt, at: gestalt)
      }
      if !before.relayEnabled {
        try ensureFlagDirectories()
        touchedFlag = true
        try writeFile(stagedFlag, at: flags)
      }
      if !PairBackPlan.limitsMatch(disk) || !PairBackPlan.limitsMatch(preferences) {
        touchedPreferences = true
        try setRegistryTargets(from: stagedRegistry)
        try verifyRegistryAfterWrite(expected: stagedRegistry, before: disk)
      }
      let after = try readStatus()
      guard after.fullyApplied else {
        throw PairBackError("Final readback did not match all three settings")
      }
      status = after
      message =
        "Applied and verified. Restart the iPhone before pairing so Bridge and NanoRegistry reload their cached values."
    } catch {
      var rollbackProblems: [String] = []
      if touchedPreferences {
        do {
          let disk = try originalRegistry.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
          try setRegistryTargets(from: disk)
        } catch { rollbackProblems.append("NanoRegistry: \(error.localizedDescription)") }
      }
      if touchedFlag {
        do {
          let current = try readFile(flags)
          let restored =
            (try? PairBackPlan.restoreFlag(current: current, original: originalFlag))
            ?? originalFlag
          if let restored { try writeFile(restored, at: flags) } else { try removeFlagFile() }
        } catch { rollbackProblems.append("Feature flag: \(error.localizedDescription)") }
      }
      if touchedGestalt {
        do {
          guard let current = try readFile(gestalt) else {
            throw PairBackError("MobileGestalt cache disappeared during rollback")
          }
          let offset = Int(pb_mobilegestalt_offset(PairBackPlan.gestaltKey))
          let restored =
            (try? PairBackPlan.restoreGestalt(
              current: current, original: originalGestalt, offset: offset))
            ?? originalGestalt
          try writeFile(restored, at: gestalt)
        } catch { rollbackProblems.append("MobileGestalt: \(error.localizedDescription)") }
      }
      if !backupComplete && fm.fileExists(atPath: backup.path) {
        try? fm.removeItem(at: backup)
      }
      if backupComplete && rollbackProblems.isEmpty {
        do {
          let restored = try readStatus()
          let offset = Int(pb_mobilegestalt_offset(PairBackPlan.gestaltKey))
          let originalMG = try PairBackPlan.gestaltValues(originalGestalt, offset: offset)
          let originalDisk =
            try originalRegistry.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
          guard restored.gestaltValue == originalMG.0,
            restored.gestaltExtra == originalMG.1,
            restored.relayEnabled == (try PairBackPlan.flagEnabled(originalFlag)),
            PairBackPlan.limits.keys.allSatisfy({ key in
              (restored.registryDisk[key] as? NSNumber) == (originalDisk[key] as? NSNumber)
                && (restored.registryPreferences[key] as? NSNumber)
                  == (originalDisk[key] as? NSNumber)
            })
          else {
            throw PairBackError("Rollback readback differs")
          }
        } catch { rollbackProblems.append(error.localizedDescription) }
      }
      if backupComplete && rollbackProblems.isEmpty && !hasOwnerReceipts {
        if !domainExisted {
          try? removeNewDirectoryIfEmpty(domainDirectory, receipt: "feature.owner.plist")
        }
        if !featureExisted {
          try? removeNewDirectoryIfEmpty(featureDirectory, receipt: "preferences.owner.plist")
        }
        try? fm.removeItem(at: backup)
      }
      status = try? readStatus()
      let outcome: String
      if !touchedGestalt && !touchedFlag && !touchedPreferences {
        outcome = "No pairing settings changed."
      } else if rollbackProblems.isEmpty {
        outcome = "Prior values restored."
      } else {
        outcome =
          "Rollback needs repair: \(rollbackProblems.joined(separator: "; ")). Backup retained."
      }
      message =
        "Apply failed: \(error.localizedDescription). " + outcome
    }
  }

  func restore() {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      try requireReady()
      let manifestData = try Data(contentsOf: backup.appendingPathComponent("manifest.plist"))
      guard
        let manifest = try PropertyListSerialization.propertyList(from: manifestData, format: nil)
          as? [String: Any],
        (manifest["formatVersion"] as? NSNumber)?.intValue == 1,
        let flagExisted = (manifest["flagsExisted"] as? NSNumber)?.boolValue,
        let registryExisted = (manifest["registryExisted"] as? NSNumber)?.boolValue,
        let featureExisted = (manifest["featureExisted"] as? NSNumber)?.boolValue,
        let domainExisted = (manifest["domainExisted"] as? NSNumber)?.boolValue
      else {
        throw PairBackError("Backup manifest is incomplete")
      }
      let originalGestalt = try Data(contentsOf: backup.appendingPathComponent("gestalt.original"))
      let flagBytes = try Data(contentsOf: backup.appendingPathComponent("flags.original"))
      let registryBytes = try Data(contentsOf: backup.appendingPathComponent("registry.original"))
      guard (manifest["gestaltSHA256"] as? Data) == Data(SHA256.hash(data: originalGestalt)),
        (manifest["flagsSHA256"] as? Data) == Data(SHA256.hash(data: flagBytes)),
        (manifest["registrySHA256"] as? Data) == Data(SHA256.hash(data: registryBytes))
      else {
        throw PairBackError("Backup integrity check failed; no restore writes attempted")
      }
      let originalFlag: Data? = flagExisted ? flagBytes : nil
      let originalRegistry: Data? = registryExisted ? registryBytes : nil
      let originalDisk = try originalRegistry.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
      try PairBackPlan.validateLimitTypes(originalDisk)
      guard let currentGestalt = try readFile(gestalt) else {
        throw PairBackError("MobileGestalt cache is missing")
      }
      let currentFlag = try readFile(flags)
      let currentRegistry = try readFile(registry)
      let currentDisk = try currentRegistry.map(PairBackPlan.dictionary) ?? NSMutableDictionary()
      guard currentDisk.isEqual(registryPreferences()) else {
        throw PairBackError(
          "NanoRegistry file and preference cache disagree. Restart before restoring.")
      }
      let offset = Int(pb_mobilegestalt_offset(PairBackPlan.gestaltKey))
      let restoredGestalt = try PairBackPlan.restoreGestalt(
        current: currentGestalt, original: originalGestalt, offset: offset)
      let restoredFlag = try PairBackPlan.restoreFlag(current: currentFlag, original: originalFlag)
      // Refuse to replace a target value another tool changed since PairBack applied it.
      let mgNow = try PairBackPlan.gestaltValues(currentGestalt, offset: offset)
      let mgBefore = try PairBackPlan.gestaltValues(originalGestalt, offset: offset)
      guard mgNow.0 == 1 || mgNow.0 == mgBefore.0,
        mgNow.1?.intValue == 1 || mgNow.1 == mgBefore.1
      else {
        throw PairBackError("MobileGestalt target changed after Apply; backup retained")
      }
      guard
        try PairBackPlan.flagEnabled(currentFlag)
          || PairBackPlan.flagEnabled(originalFlag) == PairBackPlan.flagEnabled(currentFlag)
      else {
        throw PairBackError("Feature flag changed after Apply; backup retained")
      }
      for key in PairBackPlan.limits.keys {
        let current = currentDisk[key] as? NSNumber
        let original = originalDisk[key] as? NSNumber
        guard current?.intValue == PairBackPlan.limits[key] || current == original else {
          throw PairBackError("NanoRegistry target changed after Apply: \(key)")
        }
      }

      var touchedPreferences = false
      var touchedGestalt = false
      var touchedFlag = false
      var verifiedStatus: PairingStatus?
      do {
        touchedPreferences = true
        try setRegistryTargets(from: originalDisk)
        try verifyRegistryAfterWrite(expected: originalDisk, before: currentDisk)
        if restoredGestalt != currentGestalt {
          touchedGestalt = true
          try writeFile(restoredGestalt, at: gestalt)
        }
        if restoredFlag != currentFlag {
          touchedFlag = true
          if let restoredFlag {
            try writeFile(restoredFlag, at: flags)
          } else {
            try removeFlagFile()
          }
        }
        if !domainExisted {
          try? removeNewDirectoryIfEmpty(domainDirectory, receipt: "feature.owner.plist")
        }
        if !featureExisted {
          try? removeNewDirectoryIfEmpty(featureDirectory, receipt: "preferences.owner.plist")
        }
        guard !hasOwnerReceipts else { throw PairBackError("Ownership recovery receipt remains") }
        let verified = try readStatus()
        guard verified.gestaltValue == mgBefore.0,
          verified.gestaltExtra == mgBefore.1,
          verified.relayEnabled == (try PairBackPlan.flagEnabled(originalFlag)),
          PairBackPlan.limits.keys.allSatisfy({ key in
            (verified.registryDisk[key] as? NSNumber) == (originalDisk[key] as? NSNumber)
              && (verified.registryPreferences[key] as? NSNumber)
                == (originalDisk[key] as? NSNumber)
          })
        else {
          throw PairBackError("Restore readback differs")
        }
        verifiedStatus = verified
      } catch {
        var rollbackProblems: [String] = []
        if touchedFlag {
          do {
            if let currentFlag {
              try writeFile(currentFlag, at: flags)
            } else {
              try removeFlagFile()
            }
          } catch { rollbackProblems.append("Feature flag: \(error.localizedDescription)") }
        }
        if touchedGestalt {
          do { try writeFile(currentGestalt, at: gestalt) } catch {
            rollbackProblems.append("MobileGestalt: \(error.localizedDescription)")
          }
        }
        if touchedPreferences {
          do { try setRegistryTargets(from: currentDisk) } catch {
            rollbackProblems.append("NanoRegistry: \(error.localizedDescription)")
          }
        }
        throw PairBackError(
          "Restore failed: \(error.localizedDescription). "
            + (rollbackProblems.isEmpty
              ? "Applied values retained."
              : "Rollback needs repair: \(rollbackProblems.joined(separator: "; "))."))
      }
      let backupRemoved = (try? fm.removeItem(at: backup)) != nil
      status = verifiedStatus
      message =
        backupRemoved
        ? "Saved values restored. Restart the iPhone to reload system caches."
        : "Saved values restored, but the backup could not be removed; it remains available in Files. Restart the iPhone."
    } catch {
      status = try? readStatus()
      message = error.localizedDescription
    }
  }
}
