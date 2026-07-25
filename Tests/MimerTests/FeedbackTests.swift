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
        XCTAssertEqual(query["mimer-version"], Feedback.appVersion)
        XCTAssertEqual(query["macos-version"], Feedback.osDescription)
        XCTAssertFalse(Feedback.osDescription.isEmpty)
    }

    /// The prefill only works if our query-param names match the issue form's
    /// field IDs. Assert against the real bug_report.yml so renaming a field
    /// there (or the template file) fails CI instead of silently dropping the
    /// prefill in production. Reads the template via #filePath so it tracks the
    /// checked-out repo, not a bundled copy.
    func testPrefillKeysMatchTheActualIssueForm() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)      // …/Tests/MimerTests/FeedbackTests.swift
            .deletingLastPathComponent()                    // …/Tests/MimerTests
            .deletingLastPathComponent()                    // …/Tests
            .deletingLastPathComponent()                    // repo root
        let comps = URLComponents(url: Feedback.bugReportURL, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let templateName = query["template"]!
        let template = repoRoot
            .appendingPathComponent(".github/ISSUE_TEMPLATE")
            .appendingPathComponent(templateName)

        let yaml = try String(contentsOf: template, encoding: .utf8)
        // Every prefilled key (besides `template` itself) must be a field id in the form.
        for key in query.keys where key != "template" {
            XCTAssertTrue(yaml.contains("id: \(key)"),
                          "bug_report.yml has no field id '\(key)' — the prefill would be dropped.")
        }
    }

    func testDiscussionsURL() {
        XCTAssertEqual(Feedback.discussionsURL.absoluteString,
                       "https://github.com/hasanjafri/Mimer/discussions")
    }
}
