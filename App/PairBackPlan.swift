import Foundation

struct PairBackError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

enum PairBackPlan {
  static let gestaltKey = "EqrsVvjcYDdxHBiQmGhAWw"
  static let featureKey = "networkrelay_pairing"
  static let limits: [String: Int] = [
    "maxPairingCompatibilityVersion": 99,
    "minPairingCompatibilityVersion": 23,
    "minPairingCompatibilityVersionWithChipID": 10,
    "minQuickSwitchCompatibilityVersion": 6,
  ]

  static func supportsDarkSword(_ version: OperatingSystemVersion) -> Bool {
    switch version.majorVersion {
    case 17:
      return true
    case 18:
      return version.minorVersion < 7
        || (version.minorVersion == 7 && version.patchVersion <= 1)
    case 26:
      return version.minorVersion == 0 && version.patchVersion <= 1
    default:
      return false
    }
  }

  static func dictionary(_ data: Data) throws -> NSMutableDictionary {
    var format = PropertyListSerialization.PropertyListFormat.binary
    guard
      let dictionary = try PropertyListSerialization.propertyList(
        from: data, options: [.mutableContainersAndLeaves], format: &format
      ) as? NSMutableDictionary
    else {
      throw PairBackError("Expected a dictionary property list")
    }
    return dictionary
  }

  static func data(_ dictionary: NSMutableDictionary) throws -> Data {
    guard PropertyListSerialization.propertyList(dictionary, isValidFor: .binary) else {
      throw PairBackError("Invalid property list")
    }
    return try PropertyListSerialization.data(
      fromPropertyList: dictionary, format: .binary, options: 0)
  }

  static func gestaltValues(_ data: Data, offset: Int) throws -> (Int64, NSNumber?) {
    let dictionary = try dictionary(data)
    guard let cache = dictionary["CacheData"] as? NSData,
      let extra = dictionary["CacheExtra"] as? NSDictionary,
      offset >= 0, offset.isMultiple(of: MemoryLayout<Int64>.size),
      cache.length >= MemoryLayout<Int64>.size,
      offset <= cache.length - MemoryLayout<Int64>.size
    else {
      throw PairBackError("Invalid MobileGestalt cache structure or key offset")
    }
    var value: Int64 = 0
    cache.getBytes(&value, range: NSRange(location: offset, length: MemoryLayout<Int64>.size))
    guard value == 0 || value == 1 else {
      throw PairBackError("Unexpected AppleInternalInstall CacheData value \(value)")
    }
    let extraValue = extra[gestaltKey]
    guard extraValue == nil || extraValue is NSNumber else {
      throw PairBackError("Unexpected AppleInternalInstall CacheExtra type")
    }
    return (value, extraValue as? NSNumber)
  }

  static func enableGestalt(_ current: Data, offset: Int) throws -> Data {
    _ = try gestaltValues(current, offset: offset)
    let dictionary = try dictionary(current)
    guard let cache = dictionary["CacheData"] as? NSMutableData,
      let extra = dictionary["CacheExtra"] as? NSMutableDictionary
    else {
      throw PairBackError("MobileGestalt cache is not mutable")
    }
    var enabled: Int64 = 1
    cache.replaceBytes(
      in: NSRange(location: offset, length: MemoryLayout<Int64>.size), withBytes: &enabled)
    extra[gestaltKey] = NSNumber(value: 1)
    return try data(dictionary)
  }

  static func restoreGestalt(current: Data, original: Data, offset: Int) throws -> Data {
    let (originalValue, originalExtra) = try gestaltValues(original, offset: offset)
    _ = try gestaltValues(current, offset: offset)
    let dictionary = try dictionary(current)
    guard let cache = dictionary["CacheData"] as? NSMutableData,
      let extra = dictionary["CacheExtra"] as? NSMutableDictionary
    else {
      throw PairBackError("MobileGestalt cache is not mutable")
    }
    var restored = originalValue
    cache.replaceBytes(
      in: NSRange(location: offset, length: MemoryLayout<Int64>.size), withBytes: &restored)
    if let originalExtra {
      extra[gestaltKey] = originalExtra
    } else {
      extra.removeObject(forKey: gestaltKey)
    }
    return try data(dictionary)
  }

  static func flagEnabled(_ current: Data?) throws -> Bool {
    guard let current else { return false }
    let dictionary = try dictionary(current)
    return ((dictionary[featureKey] as? NSDictionary)?["Enabled"] as? NSNumber)?.boolValue == true
  }

  static func enableFlag(_ current: Data?) throws -> Data {
    let dictionary = try current.map(dictionary) ?? NSMutableDictionary()
    let value =
      (dictionary[featureKey] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary
      ?? NSMutableDictionary()
    value["Enabled"] = NSNumber(value: true)
    dictionary[featureKey] = value
    return try data(dictionary)
  }

  static func restoreFlag(current: Data?, original: Data?) throws -> Data? {
    let originalDictionary = try original.map(dictionary) ?? NSMutableDictionary()
    let dictionary =
      try current.map(dictionary)
      ?? (originalDictionary.mutableCopy() as? NSMutableDictionary ?? NSMutableDictionary())
    if let originalEntry = originalDictionary[featureKey] {
      dictionary[featureKey] = originalEntry
    } else {
      dictionary.removeObject(forKey: featureKey)
    }
    if dictionary.count == 0 && original == nil { return nil }
    return try data(dictionary)
  }

  static func limitsMatch(_ dictionary: NSDictionary) -> Bool {
    limits.allSatisfy { key, value in (dictionary[key] as? NSNumber)?.intValue == value }
  }

  static func validateLimitTypes(_ dictionary: NSDictionary) throws {
    for key in limits.keys where dictionary[key] != nil {
      guard dictionary[key] is NSNumber else {
        throw PairBackError("Unexpected NanoRegistry value type for \(key)")
      }
    }
  }

  static func unrelatedRegistryEntriesPreserved(before: NSDictionary, after: NSDictionary) -> Bool {
    for key in before.allKeys.compactMap({ $0 as? String }) where limits[key] == nil {
      guard let original = before[key] as? NSObject,
        let updated = after[key] as? NSObject,
        original.isEqual(updated)
      else { return false }
    }
    return true
  }
}
