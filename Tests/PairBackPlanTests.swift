import XCTest

@testable import PairBackPlan

final class PairBackPlanTests: XCTestCase {
  private func plist(_ dictionary: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
  }

  func testMobileGestaltOnlyChangesTheTargetAndRestoresItsOriginalPresence() throws {
    var cache = Data(repeating: 0x7a, count: 320)
    cache.replaceSubrange(248..<256, with: Data(repeating: 0, count: 8))
    let original = try plist(["CacheData": cache, "CacheExtra": ["unrelated": 7], "other": "keep"])
    let applied = try PairBackPlan.enableGestalt(original, offset: 248)
    let originalDictionary = try PairBackPlan.dictionary(original)
    let appliedDictionary = try PairBackPlan.dictionary(applied)
    XCTAssertEqual((appliedDictionary["CacheExtra"] as? NSDictionary)?["unrelated"] as? Int, 7)
    XCTAssertEqual(appliedDictionary["other"] as? String, "keep")
    let before = originalDictionary["CacheData"] as! Data
    let after = appliedDictionary["CacheData"] as! Data
    XCTAssertEqual(before.prefix(248), after.prefix(248))
    XCTAssertEqual(before.suffix(from: 256), after.suffix(from: 256))
    XCTAssertEqual(try PairBackPlan.gestaltValues(applied, offset: 248).0, 1)
    (appliedDictionary["CacheExtra"] as! NSMutableDictionary)["new"] = 9
    let later = try PairBackPlan.data(appliedDictionary)
    let restored = try PairBackPlan.restoreGestalt(current: later, original: original, offset: 248)
    XCTAssertEqual(try PairBackPlan.gestaltValues(restored, offset: 248).0, 0)
    XCTAssertNil(try PairBackPlan.gestaltValues(restored, offset: 248).1)
    XCTAssertEqual(
      (try PairBackPlan.dictionary(restored)["CacheExtra"] as? NSDictionary)?["new"] as? Int, 9)
  }

  func testFlagRestorePreservesEntriesAddedLater() throws {
    let applied = try PairBackPlan.enableFlag(nil)
    XCTAssertTrue(try PairBackPlan.flagEnabled(applied))
    XCTAssertNil(try PairBackPlan.restoreFlag(current: applied, original: nil))
    let dictionary = try PairBackPlan.dictionary(applied)
    dictionary["another_feature"] = ["Enabled": true]
    let later = try PairBackPlan.data(dictionary)
    let restored = try XCTUnwrap(PairBackPlan.restoreFlag(current: later, original: nil))
    let result = try PairBackPlan.dictionary(restored)
    XCTAssertNil(result[PairBackPlan.featureKey])
    XCTAssertNotNil(result["another_feature"])
  }

  func testMobileGestaltAcceptsResolvedOffsetsAndRejectsInvalidOnes() throws {
    var cache = Data(repeating: 0, count: 320)
    cache.replaceSubrange(248..<256, with: Data(repeating: 3, count: 8))
    let input = try plist(["CacheData": cache, "CacheExtra": [:]])
    let applied = try PairBackPlan.enableGestalt(input, offset: 256)
    XCTAssertEqual(try PairBackPlan.gestaltValues(applied, offset: 256).0, 1)
    let appliedCache = try XCTUnwrap(PairBackPlan.dictionary(applied)["CacheData"] as? Data)
    XCTAssertEqual(appliedCache.subdata(in: 248..<256), cache.subdata(in: 248..<256))
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: -1))
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: 249))
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: 320))
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: 248))
  }

  func testDarkSwordVersionBoundaries() {
    func supported(_ major: Int, _ minor: Int, _ patch: Int) -> Bool {
      PairBackPlan.supportsDarkSword(
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
    }
    XCTAssertFalse(supported(16, 7, 0))
    XCTAssertTrue(supported(17, 0, 0))
    XCTAssertTrue(supported(18, 7, 1))
    XCTAssertFalse(supported(18, 7, 2))
    XCTAssertFalse(supported(19, 0, 0))
    XCTAssertTrue(supported(26, 0, 1))
    XCTAssertFalse(supported(26, 0, 2))
    XCTAssertFalse(supported(26, 1, 0))
  }

  func testRegistryCheckProtectsUnrelatedEntries() throws {
    let before: NSDictionary = [
      "maxPairingCompatibilityVersion": 24,
      "unrelated": ["name": "keep"],
    ]
    let after: NSDictionary = [
      "maxPairingCompatibilityVersion": 99,
      "unrelated": ["name": "keep"],
    ]
    XCTAssertTrue(PairBackPlan.unrelatedRegistryEntriesPreserved(before: before, after: after))
    let damaged: NSDictionary = ["maxPairingCompatibilityVersion": 99]
    XCTAssertFalse(PairBackPlan.unrelatedRegistryEntriesPreserved(before: before, after: damaged))
  }

  func testRegistryRestorePreservesLaterEntries() throws {
    let original = try plist(["minPairingCompatibilityVersion": 24, "original": "keep"])
    let current = try plist([
      "maxPairingCompatibilityVersion": 99,
      "minPairingCompatibilityVersion": 23,
      "minPairingCompatibilityVersionWithChipID": 10,
      "minQuickSwitchCompatibilityVersion": 6,
      "original": "keep",
      "addedLater": "keep too",
    ])
    let restored = try XCTUnwrap(
      PairBackPlan.restoreRegistry(current: current, original: original))
    let values = try PairBackPlan.dictionary(restored)
    XCTAssertNil(values["maxPairingCompatibilityVersion"])
    XCTAssertEqual(values["minPairingCompatibilityVersion"] as? Int, 24)
    XCTAssertNil(values["minPairingCompatibilityVersionWithChipID"])
    XCTAssertNil(values["minQuickSwitchCompatibilityVersion"])
    XCTAssertEqual(values["original"] as? String, "keep")
    XCTAssertEqual(values["addedLater"] as? String, "keep too")

    let noOriginal = try PairBackPlan.restoreRegistry(current: current, original: nil)
    let remaining = try PairBackPlan.dictionary(XCTUnwrap(noOriginal))
    XCTAssertEqual(remaining["addedLater"] as? String, "keep too")
    XCTAssertNil(remaining["maxPairingCompatibilityVersion"])
    XCTAssertNil(try PairBackPlan.restoreRegistry(current: plist([:]), original: nil))
  }
}
