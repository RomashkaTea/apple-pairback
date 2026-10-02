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

  func testRejectsWrongGestaltOffsetAndUnexpectedValue() throws {
    var cache = Data(repeating: 0, count: 320)
    cache.replaceSubrange(248..<256, with: Data(repeating: 3, count: 8))
    let input = try plist(["CacheData": cache, "CacheExtra": [:]])
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: 256))
    XCTAssertThrowsError(try PairBackPlan.enableGestalt(input, offset: 248))
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
}
