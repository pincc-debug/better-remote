import XCTest
import RemoteFitCore
@testable import RemoteFit

final class FeedbackCopyTests: XCTestCase {
    func testFeedbackCopyMatchesTheAboutPage() {
        XCTAssertEqual(FeedbackCopy.page, "关于")
        XCTAssertEqual(FeedbackCopy.slogan, "手机远程 Mac，画面刚好铺满。")
        XCTAssertEqual(FeedbackCopy.checkUpdate, "检查更新")
        XCTAssertEqual(FeedbackCopy.section, "意见反馈")
        XCTAssertEqual(FeedbackCopy.help, "帮助中心")
        XCTAssertEqual(FeedbackCopy.coffee, "请作者喝咖啡")
        XCTAssertEqual(BetterRemoteSite.rewardQR, URL(string: "https://betterremote.pincc.dev/qr/reward.png")!)
        XCTAssertEqual(BetterRemoteSite.help, URL(string: "https://betterremote.pincc.dev/help")!)
        XCTAssertEqual(FeedbackCopy.placeholder, "遇到什么问题，或想提什么建议")
        XCTAssertEqual(FeedbackCopy.attach, "上传日志")
        XCTAssertEqual(FeedbackCopy.note, "方便查问题，不含隐私内容。")
        XCTAssertEqual(FeedbackCopy.send, "发送")
        XCTAssertEqual(FeedbackCopy.copy, "复制编号")
        XCTAssertEqual(FeedbackCopy.failed, "没能发送，检查网络后重试")
        XCTAssertEqual(FeedbackCopy.sent("br-abc12345"), "已发送，编号 br-abc12345")
    }
}
