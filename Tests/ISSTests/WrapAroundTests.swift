import XCTest
import ISS

// Unit tests for iss_wrap_target.
// Access the non-exported C function via @_silgen_name (same approach as
// SwipeProgressTests). No events are posted; no permissions required.

@_silgen_name("iss_wrap_target")
private func iss_wrap_target(_ spaceCount: UInt32, _ current: UInt32, _ direction: ISSDirection) -> Int

final class WrapAroundTests: XCTestCase {

  func testLeftAtFirstWrapsToLast() {
    XCTAssertEqual(iss_wrap_target(5, 0, ISSDirectionLeft), 4)
  }

  func testRightAtLastWrapsToFirst() {
    XCTAssertEqual(iss_wrap_target(5, 4, ISSDirectionRight), 0)
  }

  func testMiddleIndicesDoNotWrap() {
    for current in UInt32(1)...3 {
      XCTAssertEqual(iss_wrap_target(5, current, ISSDirectionLeft), -1)
      XCTAssertEqual(iss_wrap_target(5, current, ISSDirectionRight), -1)
    }
  }

  func testOppositeEdgeDoesNotWrap() {
    XCTAssertEqual(iss_wrap_target(5, 0, ISSDirectionRight), -1)
    XCTAssertEqual(iss_wrap_target(5, 4, ISSDirectionLeft), -1)
  }

  func testSingleAndZeroSpacesDoNotWrap() {
    for count in UInt32(0)...1 {
      XCTAssertEqual(iss_wrap_target(count, 0, ISSDirectionLeft), -1)
      XCTAssertEqual(iss_wrap_target(count, 0, ISSDirectionRight), -1)
    }
  }

  /// A stale prediction past the end still wraps rather than running off.
  func testIndexPastEndWrapsRight() {
    XCTAssertEqual(iss_wrap_target(5, 9, ISSDirectionRight), 0)
  }
}
