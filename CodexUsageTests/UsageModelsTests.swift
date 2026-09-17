import XCTest
@testable import CodexUsage

final class UpdateCheckServiceTests: XCTestCase {
    func testFindsNewerGitHubRelease() throws {
        let data = Data(
            #"{"tag_name":"v1.0.19","html_url":"https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.19"}"#.utf8
        )

        let update = UpdateCheckService.availableUpdate(from: data, currentVersion: "1.0.18")

        XCTAssertEqual(update?.version, "1.0.19")
        XCTAssertEqual(
            update?.releaseURL.absoluteString,
            "https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.19"
        )
    }

    func testIgnoresCurrentOrOlderRelease() throws {
        let current = Data(
            #"{"tag_name":"v1.0.18","html_url":"https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.18"}"#.utf8
        )
        let older = Data(
            #"{"tag_name":"v1.0.17","html_url":"https://github.com/asetho/ChatGPT-Usage/releases/tag/v1.0.17"}"#.utf8
        )

        XCTAssertNil(UpdateCheckService.availableUpdate(from: current, currentVersion: "1.0.18"))
        XCTAssertNil(UpdateCheckService.availableUpdate(from: older, currentVersion: "1.0.18"))
    }

    func testRejectsUnexpectedReleaseHost() throws {
        let data = Data(
            #"{"tag_name":"v1.0.19","html_url":"https://example.com/download"}"#.utf8
        )

        XCTAssertNil(UpdateCheckService.availableUpdate(from: data, currentVersion: "1.0.18"))
    }
}

final class UsageModelsTests: XCTestCase {
    func testRemainingPercentageIsClamped() {
        XCTAssertEqual(RateLimitWindow(usedPercent: 27, windowDurationMins: 300, resetsAt: nil).remainingPercent, 73)
        XCTAssertEqual(RateLimitWindow(usedPercent: -5, windowDurationMins: 300, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(RateLimitWindow(usedPercent: 110, windowDurationMins: 300, resetsAt: nil).remainingPercent, 0)
    }

    func testSelectsFiveHourAndWeeklyWindowsByDuration() {
        let fiveHour = RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: nil)
        let weekly = RateLimitWindow(usedPercent: 40, windowDurationMins: 10_080, resetsAt: nil)
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: weekly,
            secondary: fiveHour,
            credits: nil,
            individualLimit: nil,
            planType: "pro",
            rateLimitReachedType: nil
        )

        XCTAssertEqual(snapshot.fiveHourWindow, fiveHour)
        XCTAssertEqual(snapshot.weeklyWindow, weekly)
    }

    func testDoesNotMislabelWeeklyOnlyWindowAsFiveHour() {
        let weekly = RateLimitWindow(usedPercent: 77, windowDurationMins: 10_080, resetsAt: nil)
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: weekly,
            secondary: nil,
            credits: nil,
            individualLimit: nil,
            planType: "pro",
            rateLimitReachedType: nil
        )

        XCTAssertNil(snapshot.fiveHourWindow)
        XCTAssertEqual(snapshot.weeklyWindow, weekly)
    }

    func testLunaReserveDisplayNameUsesLimitNameOrDictionaryKey() {
        let named = RateLimitSnapshot(
            limitId: nil,
            limitName: "gpt-reserve",
            primary: nil,
            secondary: nil,
            credits: nil,
            individualLimit: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        XCTAssertTrue(named.isLunaReserve)
        XCTAssertEqual(named.displayName, "Luna Reserve")

        let unnamed = RateLimitSnapshot(
            limitId: nil,
            limitName: nil,
            primary: nil,
            secondary: nil,
            credits: nil,
            individualLimit: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let keyed = unnamed.usingLimitIdIfMissing("gpt-reserve")
        XCTAssertEqual(keyed.limitId, "gpt-reserve")
        XCTAssertTrue(keyed.isLunaReserve)
        XCTAssertEqual(keyed.displayName, "Luna Reserve")
    }

    func testDecodesCurrentRateLimitsPayload() throws {
        let json = #"""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": {"usedPercent": 77, "windowDurationMins": 10080, "resetsAt": 1789808353},
            "secondary": null,
            "credits": {"hasCredits": false, "unlimited": false, "balance": "0"},
            "individualLimit": null,
            "planType": "pro",
            "rateLimitReachedType": null
          },
          "rateLimitsByLimitId": null,
          "rateLimitResetCredits": {
            "availableCount": 1,
            "credits": [
              {"expiresAt": 1791173941, "status": "available", "title": "Full reset"}
            ]
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)

        XCTAssertNil(response.rateLimits.fiveHourWindow)
        XCTAssertEqual(response.rateLimits.weeklyWindow?.remainingPercent, 23)
        XCTAssertEqual(response.rateLimits.credits?.balance, "0")
        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 1)
        XCTAssertEqual(response.rateLimitResetCredits?.nextExpiration, 1_791_173_941)
    }

    func testTokenFormattingUsesCompactUnits() {
        XCTAssertEqual(UsageFormatters.tokenCount(950), "950")
        XCTAssertEqual(UsageFormatters.tokenCount(1_500), "1.5K")
        XCTAssertEqual(UsageFormatters.tokenCount(2_000_000), "2M")
        XCTAssertEqual(UsageFormatters.tokenCount(10_200_000_000), "10.2B")
    }

    func testNearTermResetUsesTimeEvenAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 23))!
        let reset = calendar.date(byAdding: .hour, value: 2, to: now)!

        XCTAssertEqual(
            UsageFormatters.resetLabel(Int64(reset.timeIntervalSince1970), now: now),
            UsageFormatters.shortTime.string(from: reset)
        )
    }

    func testFullResetLabelIncludesDateAndTime() {
        let timestamp: Int64 = 1_789_808_353
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))

        XCTAssertEqual(
            UsageFormatters.fullResetLabel(timestamp),
            UsageFormatters.fullDateTime.string(from: date)
        )
    }

}

final class CodexUsageServiceTests: XCTestCase {
    private let validRateLimits = #"{"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":null},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":null},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"planType":"pro","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":2}}}"#
    private let validUsage = #"{"id":4,"result":{"summary":{"currentStreakDays":3,"lifetimeTokens":1234},"dailyUsageBuckets":[]}}"#

    func testFetchesSnapshotFromAppServer() async throws {
        let executable = try makeServer(
            rateLimitsResponse: validRateLimits,
            usageResponse: validUsage
        )

        let snapshot = try await CodexUsageService.fetch(
            timeout: 2,
            executablePath: executable.path
        )

        XCTAssertEqual(snapshot.codexRateLimits.fiveHourWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.codexRateLimits.weeklyWindow?.remainingPercent, 60)
        XCTAssertEqual(snapshot.rateLimitResetCredits?.availableCount, 2)
        XCTAssertEqual(snapshot.accountUsage?.summary.lifetimeTokens, 1_234)
    }

    func testTreatsUsageEndpointFailureAsOptional() async throws {
        let executable = try makeServer(
            rateLimitsResponse: validRateLimits,
            usageResponse: #"{"id":4,"error":{"message":"usage unavailable"}}"#
        )

        let snapshot = try await CodexUsageService.fetch(
            timeout: 2,
            executablePath: executable.path
        )

        XCTAssertNil(snapshot.accountUsage)
        XCTAssertEqual(snapshot.codexRateLimits.fiveHourWindow?.remainingPercent, 75)
    }

    func testRejectsMalformedRateLimitsResponse() async throws {
        let executable = try makeServer(
            rateLimitsResponse: #"{"id":3,"result":{"unexpected":true}}"#,
            usageResponse: validUsage
        )

        do {
            _ = try await CodexUsageService.fetch(
                timeout: 2,
                executablePath: executable.path
            )
            XCTFail("Expected an invalid response error")
        } catch CodexUsageError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReportsProcessExitStatus() async throws {
        let executable = try makeExecutable(
            script: "#!/bin/sh\nprintf 'probe failed\\n' >&2\nexit 7\n"
        )

        do {
            _ = try await CodexUsageService.fetch(
                timeout: 2,
                executablePath: executable.path
            )
            XCTFail("Expected a process exit error")
        } catch CodexUsageError.processExited(let status, _) {
            XCTAssertEqual(status, 7)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTimesOutWhenServerDoesNotRespond() async throws {
        let executable = try makeExecutable(
            script: "#!/bin/sh\ntrap 'exit 0' TERM\nwhile IFS= read -r _; do :; done\n"
        )

        do {
            _ = try await CodexUsageService.fetch(
                timeout: 0.05,
                executablePath: executable.path
            )
            XCTFail("Expected a timeout error")
        } catch CodexUsageError.timedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeServer(
        rateLimitsResponse: String,
        usageResponse: String
    ) throws -> URL {
        try makeExecutable(
            script: """
            #!/bin/sh
            printf '%s\\n' '{"id":1,"result":{}}'
            printf '%s\\n' '\(rateLimitsResponse)'
            printf '%s\\n' '\(usageResponse)'
            while IFS= read -r _; do :; done
            """
        )
    }

    private func makeExecutable(script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let executable = directory.appendingPathComponent("fake-codex")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        return executable
    }
}
