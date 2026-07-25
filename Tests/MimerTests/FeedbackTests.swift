import XCTest
@testable import Mimer

final class FeedbackTests: XCTestCase {
    func testBugReportURLTargetsTheBugForm() {
        let comps = URLComponents(url: Feedback.bugReportURL, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.host, "github.com")
        XCTAssertEqual(comps.path, "/hasanjafri/Mimer/issues/new")
        let query = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["template"], "bug_report.yml")
    }

    func testBugReportURLPrefillsEnvironment() {
        let comps = URLComponents(url: Feedback.bugReportURL, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        // The form's field IDs — these must stay in sync with bug_report.yml so
        // GitHub actually applies the prefill instead of silently dropping it.
        XCTAssertEqual(query["mimer-version"], Feedback.appVersion)
        XCTAssertEqual(query["macos-version"], Feedback.osDescription)
        XCTAssertFalse(Feedback.osDescription.isEmpty)
    }

    func testDiscussionsURL() {
        XCTAssertEqual(Feedback.discussionsURL.absoluteString,
                       "https://github.com/hasanjafri/Mimer/discussions")
    }
}
