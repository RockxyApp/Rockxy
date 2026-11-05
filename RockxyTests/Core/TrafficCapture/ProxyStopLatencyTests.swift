import Foundation
@testable import Rockxy
import Testing

// Regression tests for the Stop-latency work in the system proxy layer: concurrent read-only
// `networksetup` batches, the bounded helper probes, and a Stop overtaking an enable. Every
// command runs through an injected runner; none of these reaches the real `networksetup`.

// MARK: - ProxyStopLatencyTests

struct ProxyStopLatencyTests {
    // MARK: Internal

    // MARK: Concurrent reads

    @Test("Independent reads run at the same time, not one after another")
    func readsOverlap() {
        // Each runner blocks until all four have arrived. A serial implementation can never
        // satisfy that, so passing is proof of overlap rather than a timing guess.
        let rendezvous = Rendezvous(parties: 4)
        let commands = (0 ..< 4).map { ["-getwebproxy", "Service \($0)"] }

        let results = ProxyReadFanout.run(commands, maxConcurrent: 8) { _ in
            guard rendezvous.arriveAndWait(timeout: 5) else {
                throw FakeFailure.noOverlap
            }
            return "ok"
        }

        #expect(results.allSatisfy { (try? $0.get()) == "ok" })
    }

    @Test("Live children never exceed the cap")
    func widthIsCapped() {
        let gauge = Gauge()
        let commands = (0 ..< 12).map { ["-getwebproxy", "Service \($0)"] }

        _ = ProxyReadFanout.run(commands, maxConcurrent: 3) { _ in
            gauge.enter()
            Thread.sleep(forTimeInterval: 0.03)
            gauge.leave()
            return ""
        }

        #expect(gauge.peak <= 3)
        #expect(gauge.peak >= 2)
    }

    @Test("A width of one is serial")
    func widthOneIsSerial() {
        let gauge = Gauge()
        let commands = (0 ..< 5).map { ["-getwebproxy", "Service \($0)"] }

        _ = ProxyReadFanout.run(commands, maxConcurrent: 1) { _ in
            gauge.enter()
            Thread.sleep(forTimeInterval: 0.005)
            gauge.leave()
            return ""
        }

        #expect(gauge.peak == 1)
    }

    @Test("Results keep command order and one failure stays in its own slot")
    func orderAndFailureIsolation() {
        let commands = (0 ..< 6).map { ["-get", "\($0)"] }

        let results = ProxyReadFanout.run(commands, maxConcurrent: 4) { command in
            // Later commands finish first, so order is not an accident of completion.
            Thread.sleep(forTimeInterval: Double(6 - (Int(command[1]) ?? 0)) * 0.005)
            if command[1] == "2" {
                throw FakeFailure.commandFailed
            }
            return command[1]
        }

        #expect(results.count == 6)
        for (index, result) in results.enumerated() {
            if index == 2 {
                #expect((try? result.get()) == nil)
            } else {
                #expect((try? result.get()) == String(index))
            }
        }
    }

    @Test("An empty batch spawns nothing")
    func emptyBatch() {
        let results = ProxyReadFanout.run([], maxConcurrent: 8) { _ in
            Issue.record("no command should run")
            return ""
        }
        #expect(results.isEmpty)
    }

    // MARK: Batched state reads

    @Test("Restoration states are assembled per service from one flat concurrent batch")
    func restorationStatesAcrossServices() throws {
        // The reads of both services are flattened into one batch, so they overlap each other
        // as well as the six fields of a single service.
        let gauge = Gauge()
        let services = ["Wi-Fi", "Ethernet"]

        let states = SystemProxyManager.readRestorationStates(
            services: services,
            maxConcurrent: 8
        ) { command in
            gauge.enter()
            Thread.sleep(forTimeInterval: 0.02)
            gauge.leave()
            return Self.output(for: command)
        }

        #expect(gauge.peak > 1)
        #expect(states.count == 2)
        let wifi = try #require(states["Wi-Fi"])
        #expect(wifi.http == ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 8_888))
        #expect(wifi.https == ProxyEndpointState(enabled: true, host: "127.0.0.1", port: 8_888))
        #expect(!wifi.socks.enabled)
        #expect(wifi.pacEnabled == false)
        #expect(!wifi.autoDiscoveryEnabled)
        #expect(wifi.bypassDomains == ["*.local", "169.254/16"])
        #expect(states["Ethernet"]?.service == "Ethernet")
    }

    @Test("One unreadable field makes that whole service absent, never a half-read state")
    func unreadableFieldDropsService() {
        let states = SystemProxyManager.readRestorationStates(
            services: ["Wi-Fi", "Ethernet"],
            maxConcurrent: 8
        ) { command in
            if command.first == "-getproxybypassdomains", command.last == "Ethernet" {
                throw FakeFailure.commandFailed
            }
            return Self.output(for: command)
        }

        #expect(states["Wi-Fi"] != nil)
        #expect(states["Ethernet"] == nil)
    }

    @Test("Snapshot batch reads five fields per service and drops a service on any failure")
    func snapshotBatch() {
        let seen = Recorder()
        let snapshots = SystemProxyManager.readProxySnapshots(
            services: ["Wi-Fi", "Ethernet"],
            maxConcurrent: 8
        ) { command in
            seen.add(command)
            if command.first == "-getsocksfirewallproxy", command.last == "Ethernet" {
                throw FakeFailure.commandFailed
            }
            return Self.output(for: command)
        }

        #expect(snapshots["Wi-Fi"]?.httpPort == 8_888)
        #expect(snapshots["Ethernet"] == nil)
        // The snapshot never asks for the bypass list; that read belongs to the fuller state.
        #expect(!seen.commands.contains { $0.first == "-getproxybypassdomains" })
        #expect(seen.commands.count == 10)
    }

    @Test("No service means no commands")
    func noServicesNoCommands() {
        let states = SystemProxyManager.readRestorationStates(services: []) { _ in
            Issue.record("no command should run")
            return ""
        }
        #expect(states.isEmpty)
    }

    // MARK: Helper probe bounds

    @Test("Helper probes on the Stop path are bounded well under the general 10 second window")
    func helperProbeBounds() {
        let generalWindow: Duration = .seconds(10)
        #expect(SystemProxyManager.helperOwnerProbeTimeout == .seconds(2))
        #expect(SystemProxyManager.helperRestoreConfirmationProbeTimeout == .seconds(3))
        #expect(SystemProxyManager.helperOwnerProbeTimeout < generalWindow)
        #expect(SystemProxyManager.helperRestoreConfirmationProbeTimeout < generalWindow)
    }

    // MARK: Stop during enable

    @Test("A Stop requested after an enable was requested supersedes it")
    func stopSupersedesEarlierEnable() {
        let supersession = ProxyEnableSupersession()
        let enable = supersession.mark()
        #expect(!supersession.isSuperseded(since: enable))

        supersession.noteStopRequested()

        #expect(supersession.isSuperseded(since: enable))
    }

    @Test("A Stop that finished before an enable was requested does not cancel it")
    func earlierStopDoesNotSupersedeLaterEnable() {
        let supersession = ProxyEnableSupersession()
        supersession.noteStopRequested()

        let enable = supersession.mark()

        #expect(!supersession.isSuperseded(since: enable))
    }

    @Test("Every enable requested before a Stop is superseded, whether queued or running")
    func stopSupersedesQueuedAndRunningEnables() {
        let supersession = ProxyEnableSupersession()
        let running = supersession.mark()
        let queued = supersession.mark()

        supersession.noteStopRequested()
        let restartedAfterStop = supersession.mark()

        #expect(supersession.isSuperseded(since: running))
        #expect(supersession.isSuperseded(since: queued))
        #expect(!supersession.isSuperseded(since: restartedAfterStop))
    }

    @Test("An enable that checks between services stops at the next boundary and leaves later ones untouched")
    func enableLoopGivesWayBetweenServices() {
        // The same check the manager runs before each service's first command, driven by a
        // Stop that lands while the second service is being written.
        let supersession = ProxyEnableSupersession()
        let enable = supersession.mark()
        var written: [String] = []
        var outcome: Result<Void, any Error> = .success(())

        for service in ["Wi-Fi", "Ethernet", "Thunderbolt Bridge", "iPhone USB"] {
            if supersession.isSuperseded(since: enable) {
                outcome = .failure(SystemProxyError.enableSupersededByStop)
                break
            }
            written.append(service)
            if service == "Ethernet" {
                supersession.noteStopRequested()
            }
        }

        #expect(written == ["Wi-Fi", "Ethernet"])
        if case let .failure(error) = outcome, case SystemProxyError.enableSupersededByStop = error {
            #expect(!error.localizedDescription.isEmpty)
        } else {
            Issue.record("the enable should have given way with enableSupersededByStop")
        }
    }

    // MARK: Primed first read

    @Test("A primed read serves the named subject once and then steps aside")
    func primedReadServesOnce() {
        let clock = ManualClock()
        let primed = ProxyPrimedRead(subject: "Wi-Fi", value: 7, now: { clock.now })

        #expect(primed.take(for: "Wi-Fi") == 7)
        #expect(primed.take(for: "Wi-Fi") == nil)
    }

    @Test("A primed read never answers for a different subject, and a miss does not spend it")
    func primedReadIsPerSubject() {
        let clock = ManualClock()
        let primed = ProxyPrimedRead(subject: "Wi-Fi", value: 7, now: { clock.now })

        #expect(primed.take(for: "Ethernet") == nil)
        #expect(primed.take(for: "Wi-Fi") == 7)
    }

    @Test("A primed read older than its bound is refused, so a stall falls back to a live read")
    func primedReadExpires() {
        let clock = ManualClock()
        let primed = ProxyPrimedRead(subject: "Wi-Fi", value: 7, maxAge: .seconds(1), now: { clock.now })

        clock.advance(.milliseconds(1_500))

        #expect(primed.take(for: "Wi-Fi") == nil)
        // Spent even though it was refused: it must not become servable again later.
        clock.advance(.seconds(-1))
        #expect(primed.take(for: "Wi-Fi") == nil)
    }

    @Test("Priming the first service removes exactly one live read and none of the later ones")
    func primingSavesOnlyTheFirstServicePreRead() {
        let withoutPriming = liveReadsPerService(primeFirst: false)
        let withPriming = liveReadsPerService(primeFirst: true)

        // Pre-read plus post-commit revalidation for each service.
        #expect(withoutPriming == ["Wi-Fi": 2, "Ethernet": 2])
        // The first service's pre-read is served from the plan; its revalidation, and both of
        // the second service's reads, are still live.
        #expect(withPriming == ["Wi-Fi": 1, "Ethernet": 2])
    }

    // MARK: Phase timer

    @Test("Phases are measured between marks and reported in order")
    func phaseTimerSplitsBetweenMarks() {
        let clock = ManualClock()
        var timer = ProxyPhaseTimer(now: { clock.now })

        clock.advance(.milliseconds(250))
        timer.mark("read")
        clock.advance(.seconds(2))
        timer.mark("loop")

        #expect(timer.phases.map(\.name) == ["read", "loop"])
        #expect(abs(timer.phases[0].seconds - 0.25) < 0.001)
        #expect(abs(timer.phases[1].seconds - 2) < 0.001)
        #expect(timer.summary.hasPrefix("read "))
        #expect(timer.summary.contains(", loop "))
    }

    // MARK: Private

    private enum FakeFailure: Error {
        case noOverlap
        case commandFailed
    }

    private static func output(for command: [String]) -> String {
        switch command.first {
        case "-getwebproxy",
             "-getsecurewebproxy":
            "Enabled: Yes\nServer: 127.0.0.1\nPort: 8888\nAuthenticated Proxy Enabled: 0\n"
        case "-getsocksfirewallproxy":
            "Enabled: No\nServer: \nPort: 0\nAuthenticated Proxy Enabled: 0\n"
        case "-getautoproxyurl":
            "URL: (null)\nEnabled: No\n"
        case "-getproxyautodiscovery":
            "Auto Proxy Discovery: Off\n"
        case "-getproxybypassdomains":
            "*.local\n169.254/16\n"
        default:
            ""
        }
    }

    /// Runs the real recovery loop over two services with a counting live reader, and returns how
    /// many live reads each service cost.
    private func overridden(_ service: String) -> ProxyServiceRestorationState {
        ProxyRecoveryJournalFixtures.renamed(ProxyRecoveryJournalFixtures.rockxyOverride, to: service)
    }

    private func liveReadsPerService(primeFirst: Bool) -> [String: Int] {
        let services = ["Wi-Fi", "Ethernet"]
        let live = Dictionary(uniqueKeysWithValues: services.map { ($0, overridden($0)) })
        let entries = services.map { name in
            ProxyServiceRecoveryJournalEntry(
                service: name,
                stage: .pending,
                expectedPreStepState: overridden(name),
                target: ProxyRecoveryJournalFixtures.renamed(ProxyRecoveryJournalFixtures.capturedSettings, to: name)
            )
        }
        let backup = DirectProxyBackup(
            services: services.map { name in
                let captured = ProxyRecoveryJournalFixtures.renamed(
                    ProxyRecoveryJournalFixtures.capturedSettings,
                    to: name
                )
                return DirectServiceBackup(
                    service: name,
                    httpEnabled: captured.http.enabled,
                    httpHost: captured.http.host,
                    httpPort: captured.http.port,
                    httpsEnabled: captured.https.enabled,
                    httpsHost: captured.https.host,
                    httpsPort: captured.https.port,
                    socksEnabled: captured.socks.enabled,
                    socksHost: captured.socks.host,
                    socksPort: captured.socks.port,
                    pacEnabled: captured.pacEnabled,
                    pacURL: captured.pacURL,
                    autoDiscoveryEnabled: captured.autoDiscoveryEnabled,
                    bypassDomains: captured.bypassDomains
                )
            },
            timestamp: Date(timeIntervalSince1970: 0),
            rockxyPort: ProxyRecoveryJournalFixtures.rockxyPort,
            recoveryPending: true,
            journal: entries
        )
        let counter = ReadCounter()
        let primed = primeFirst ? ProxyPrimedRead(subject: "Wi-Fi", value: overridden("Wi-Fi")) : nil

        let result = DirectProxyRecoveryRunner.run(
            entriesToRestore: entries,
            backup: backup,
            journal: entries,
            retention: ProxyBackupRetention(authorized: services, preserved: []),
            deferredServices: [],
            effects: DirectProxyRecoveryEffects(
                readState: { service in
                    if let value = primed?.take(for: service) {
                        return value
                    }
                    counter.record(service)
                    return live[service]
                },
                publishBackup: { _ in },
                restoreProxyState: { _ in },
                restoreBypassDomains: { _ in },
                log: { _ in }
            )
        )
        #expect(result.allSucceeded)
        #expect(result.attemptedServices == services)
        return counter.counts
    }
}

// MARK: - Rendezvous

/// Releases every party only once all of them have arrived.
private final class Rendezvous: @unchecked Sendable {
    // MARK: Lifecycle

    init(parties: Int) {
        self.parties = parties
    }

    // MARK: Internal

    func arriveAndWait(timeout: TimeInterval) -> Bool {
        lock.lock()
        arrived += 1
        if arrived == parties {
            for _ in 0 ..< parties {
                gate.signal()
            }
        }
        lock.unlock()
        return gate.wait(timeout: .now() + timeout) == .success
    }

    // MARK: Private

    private let parties: Int
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var arrived = 0
}

// MARK: - Gauge

private final class Gauge: @unchecked Sendable {
    // MARK: Internal

    var peak: Int {
        lock.withLock { highWater }
    }

    func enter() {
        lock.withLock {
            current += 1
            highWater = max(highWater, current)
        }
    }

    func leave() {
        lock.withLock { current -= 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var current = 0
    private var highWater = 0
}

// MARK: - Recorder

private final class Recorder: @unchecked Sendable {
    // MARK: Internal

    var commands: [[String]] {
        lock.withLock { stored }
    }

    func add(_ command: [String]) {
        lock.withLock { stored.append(command) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: [[String]] = []
}

// MARK: - ManualClock

private final class ManualClock: @unchecked Sendable {
    // MARK: Internal

    var now: ContinuousClock.Instant {
        lock.withLock { base.advanced(by: offset) }
    }

    func advance(_ amount: Duration) {
        lock.withLock { offset += amount }
    }

    // MARK: Private

    private let lock = NSLock()
    private let base = ContinuousClock.now
    private var offset: Duration = .zero
}

// MARK: - ReadCounter

private final class ReadCounter: @unchecked Sendable {
    // MARK: Internal

    var counts: [String: Int] {
        lock.withLock { stored }
    }

    func record(_ service: String) {
        lock.withLock { stored[service, default: 0] += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var stored: [String: Int] = [:]
}
