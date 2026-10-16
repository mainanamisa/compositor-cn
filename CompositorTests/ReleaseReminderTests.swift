import Testing
@testable import Compositor

@Suite struct ReleaseReminderTests {
    @Test func versionNumbersCompareNumerically() {
        #expect(ReleaseReminder.isNewer("1.5.10", than: "1.5.9"))
        #expect(ReleaseReminder.isNewer("1.6.0", than: "1.5.3"))
        #expect(ReleaseReminder.isNewer("2.0", than: "1.5.3"))
        #expect(!ReleaseReminder.isNewer("1.5.3", than: "1.5.3"))
        #expect(!ReleaseReminder.isNewer("1.5.2", than: "1.5.3"))
        #expect(!ReleaseReminder.isNewer("1.5", than: "1.5.1"))
        #expect(ReleaseReminder.isNewer("1.5.1", than: "1.5"))
    }

    @Test func releaseTagsYieldTheirVersionNumber() {
        #expect(ReleaseReminder.version(fromTag: "v1.5.3-cn") == "1.5.3")
        #expect(ReleaseReminder.version(fromTag: "v1.5.3") == "1.5.3")
        #expect(ReleaseReminder.version(fromTag: "1.5.10-cn.2") == "1.5.10")
        #expect(ReleaseReminder.version(fromTag: "release-notes") == nil)
    }
}
