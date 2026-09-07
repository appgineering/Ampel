import AppKit
import Observation

/// Drives the menu bar image. Runs a timer only while the aggregate is
/// `.attention`; every other state is a single static image and zero timers,
/// which is what keeps the idle app at ~0% CPU. See SPEC §5.
@MainActor
@Observable
final class StatusIconModel {
    private(set) var image: NSImage = StatusIcon.image(for: .off)

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var frame = 0
    @ObservationIgnored private var state: AggregateState = .off

    func update(_ state: AggregateState) {
        guard state != self.state else { return }
        self.state = state

        timer?.invalidate()
        timer = nil

        guard state == .attention else {
            image = StatusIcon.image(for: state)
            return
        }

        frame = 0
        image = StatusIcon.pulseFrames[0]
        let timer = Timer(timeInterval: StatusIcon.pulseInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frame = (self.frame + 1) % StatusIcon.pulseFrames.count
                self.image = StatusIcon.pulseFrames[self.frame]
            }
        }
        // .common so the pulse keeps running while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
