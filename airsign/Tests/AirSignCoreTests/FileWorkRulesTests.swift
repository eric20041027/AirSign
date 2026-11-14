import Foundation
import Testing
@testable import AirSignCore

@Test func whileFilesAreProcessedOnlyOpeningAndQuittingAreAccepted() {
    for action in AppAction.allCases {
        #expect(BusyPolicy.allows(action, whileBusy: false))
        #expect(BusyPolicy.allows(action, whileBusy: true) == (action == .openRequest || action == .quit))
    }
}

@Test func openRequestsWaitInOrderBehindARunningOperation() {
    let a = [URL(fileURLWithPath: "/tmp/a.airsign")], b = [URL(fileURLWithPath: "/tmp/b.txt")], c = [URL(fileURLWithPath: "/tmp/c.airsign")]
    var queue = OpenQueue()
    #expect(queue.receive(a) == a && queue.waitingCount == 0)        // idle: handled now
    queue.operationBegan()
    #expect(queue.receive(b) == nil && queue.receive(c) == nil)      // busy: they wait
    #expect(queue.waitingCount == 2 && queue.next() == nil)          // nothing is handed out while busy
    queue.operationEnded()
    #expect(queue.next() == b)
    queue.operationBegan()                                           // handling b started a lock
    #expect(queue.next() == nil && queue.waitingCount == 1)
    queue.operationEnded()
    #expect(queue.next() == c && queue.next() == nil && queue.waitingCount == 0)
}

@Test func aRequestThatArrivesWhileOthersWaitGoesBehindThem() {
    let a = [URL(fileURLWithPath: "/tmp/a.txt")], b = [URL(fileURLWithPath: "/tmp/b.txt")]
    var queue = OpenQueue()
    queue.operationBegan(); _ = queue.receive(a); queue.operationEnded()
    #expect(queue.receive(b) == nil)          // a is still waiting, so b may not jump ahead
    #expect(queue.next() == a && queue.next() == b)
}
