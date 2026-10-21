import XCTest
@testable import Jailor

final class GeometryTests: XCTestCase {
    func testNormalizedRectRoundTrip() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let normalized = NormRect(x: 0.25, y: 0.1, width: 0.5, height: 0.4)
        let cocoa = ScreenGeometry.cocoaRect(from: normalized, in: visible)
        let result = ScreenGeometry.normRect(from: cocoa, in: visible)

        XCTAssertEqual(result.x, normalized.x, accuracy: 0.002)
        XCTAssertEqual(result.y, normalized.y, accuracy: 0.002)
        XCTAssertEqual(result.width, normalized.width, accuracy: 0.002)
        XCTAssertEqual(result.height, normalized.height, accuracy: 0.002)
    }

    func testCocoaRectUsesTopLeftOrigin() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let rect = ScreenGeometry.cocoaRect(
            from: NormRect(x: 0, y: 0, width: 0.5, height: 0.5),
            in: visible
        )
        XCTAssertEqual(rect.minX, 0)
        XCTAssertEqual(rect.maxY, visible.maxY)
        XCTAssertEqual(rect.width, 500)
        XCTAssertEqual(rect.height, 500)
    }

    func testAccessibilityCoordinateConversion() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = ScreenGeometry.axRect(from: cocoa, primaryHeight: 1000)
        XCTAssertEqual(ax.minX, 100)
        XCTAssertEqual(ax.minY, 400)
        XCTAssertEqual(ax.width, 300)
        XCTAssertEqual(ax.height, 400)
    }

    func testClampKeepsFrameInsideUnitSquare() {
        let clamped = NormRect(x: 0.9, y: -0.2, width: 0.5, height: 0.02)
            .clamped(minWidth: 0.1, minHeight: 0.1)
        XCTAssertEqual(clamped.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(clamped.height, 0.1, accuracy: 0.0001)
        XCTAssertEqual(clamped.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(clamped.y, 0, accuracy: 0.0001)
    }

    func testLegacySettingsWithoutWorkspaceModeStillDecode() throws {
        let json = """
        {
          "autoRestoreOnLaunch": true,
          "launchMissingApps": true,
          "tagMemory": {}
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.autoRestoreOnLaunch)
        XCTAssertTrue(settings.launchMissingApps)
        XCTAssertNil(settings.activeLayoutID)
        XCTAssertNil(settings.workspaceMode)
        XCTAssertTrue(settings.tagMemory.isEmpty)
    }

    func testWorkspaceModeRoundTrip() throws {
        var settings = AppSettings.default
        settings.workspaceMode = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.workspaceMode, false)
    }

    func testLegacyAssignmentWithoutWindowIDDecodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "layoutID": "22222222-2222-2222-2222-222222222222",
          "frameID": "33333333-3333-3333-3333-333333333333",
          "bundleID": "com.microsoft.VSCode",
          "appName": "Code",
          "windowTitle": "Project — Visual Studio Code",
          "updatedAt": "2026-10-21T02:19:12Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let assignment = try decoder.decode(WindowAssignment.self, from: Data(json.utf8))
        XCTAssertNil(assignment.windowID)
        XCTAssertEqual(
            assignment.windowKey,
            "com.microsoft.VSCode|Project — Visual Studio Code"
        )
    }

    func testWindowKeyPrefersStableWindowID() {
        let assignment = WindowAssignment(
            layoutID: UUID(),
            frameID: UUID(),
            bundleID: "com.microsoft.VSCode",
            appName: "Code",
            windowTitle: "Project — Visual Studio Code",
            tagID: nil,
            windowID: 12345
        )
        XCTAssertEqual(assignment.windowKey, "id:12345")
    }

    func testVietnameseLocalizationTableIsUsable() {
        for (key, value) in VietnameseStrings.table {
            XCTAssertFalse(key.isEmpty)
            XCTAssertFalse(value.isEmpty)
        }
        XCTAssertEqual(VietnameseStrings.table["Labels"], "Nhãn")
        XCTAssertEqual(VietnameseStrings.table["Settings"], "Cài đặt")
        XCTAssertEqual(VietnameseStrings.table["Language"], "Ngôn ngữ")
    }

    @MainActor
    func testLocalizationSwitchesLive() {
        let localization = Localization.shared
        let original = localization.language
        defer { localization.language = original }

        localization.language = .english
        XCTAssertEqual(localization.t("Labels"), "Labels")
        XCTAssertEqual(localization.t("Assigned %@ to frame %d.", "Code", 2), "Assigned Code to frame 2.")

        localization.language = .vietnamese
        XCTAssertEqual(localization.t("Labels"), "Nhãn")
        XCTAssertEqual(localization.t("Assigned %@ to frame %d.", "Code", 2), "Đã gán Code vào Khung 2.")
    }
}
