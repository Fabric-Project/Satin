import Foundation

public final class Tween {
    public let id = UUID()
    // Properties
    public private(set) var loops: Int = 0
    public private(set) var loop: Int = 0

    public private(set) var tweening: Bool = false
    public private(set) var complete: Bool = false
    public private(set) var looping: Bool = false
    public private(set) var pingPong: Bool = false
    public private(set) var pingPongState: Bool = false
    public private(set) var progress: Double = 0.0

    public private(set) var delayOnLoop: Bool = false
    public private(set) var delayOnPingPong: Bool = false

    // Easing
    public private(set) var easingFn: ((_ time: Double) -> Double) = easeLinear

    // Callbacks
    private var _onStart: (() -> ())?
    private var _onRestart: (() -> ())?
    private var _onPlay: (() -> ())?
    private var _onPause: (() -> ())?
    private var _onStop: (() -> ())?
    private var _onUpdate: ((_ progress: Double) -> ())?
    private var _onTweenStart: (() -> ())?
    private var _onTween: ((_ value: Double) -> ())?
    private var _onComplete: (() -> ())?
    private var _onLoopsComplete: (() -> ())?
    private var _onPingPongComplete: (() -> ())?

    private var firstTime: Bool = true
    private var delay: TimeInterval = 0.0
    private var duration: TimeInterval = 0.0
    /// The time progress counts from, on the timeline `update(time:)` is given. Nil until the
    /// next update anchors it at that update's time plus `startTimeOffset`.
    private var startTime: TimeInterval? {
        didSet {
            lastDeltaTime = -1.0
        }
    }

    private var startTimeOffset: TimeInterval = 0.0

    private var lastDeltaTime: TimeInterval = 0.0

    /// The tweener that updates this tween, which takes it back when it restarts after completing.
    private weak var tweener: Tweener?

    init(duration: Double, tweener: Tweener) {
        self.duration = duration
        self.tweener = tweener
    }

    public func restart() -> Tween {
        loop = 0
        _onRestart?()
        return start()
    }

    /// Starts on the next update.
    public func start() -> Tween {
        start(anchoredAt: nil)
    }

    /// Starts at `time`, or on the next update when nil.
    private func start(anchoredAt time: TimeInterval?) -> Tween {
        if complete {
            tweener?.append(self)
        }
        tweening = true
        complete = false
        let startDelay = (firstTime || delayOnLoop || (delayOnPingPong && !pingPongState)) ? delay : 0.0
        anchorStart(at: time, offset: startDelay)
        progress = -startDelay / duration
        _onStart?()
        firstTime = false
        return self
    }

    public func onRestart(_ restartFn: @escaping (() -> ())) -> Tween {
        _onRestart = restartFn
        return self
    }

    public func onStart(_ startFn: @escaping (() -> ())) -> Tween {
        _onStart = startFn
        return self
    }

    public func onPlay(_ playFn: @escaping (() -> ())) -> Tween {
        _onPlay = playFn
        return self
    }

    public func onPause(_ pauseFn: @escaping (() -> ())) -> Tween {
        _onPause = pauseFn
        return self
    }

    public func onStop(_ stopFn: @escaping (() -> ())) -> Tween {
        _onStop = stopFn
        return self
    }

    public func onUpdate(_ updateFn: @escaping ((_ progress: Double) -> ())) -> Tween {
        _onUpdate = updateFn
        return self
    }

    public func onTweenStart(_ tweenStartFn: @escaping (() -> ())) -> Tween {
        _onTweenStart = tweenStartFn
        return self
    }

    public func onTween(_ tweenFn: @escaping ((_ progress: Double) -> ())) -> Tween {
        _onTween = tweenFn
        return self
    }

    public func onEasing(_ easingFn: @escaping ((_ time: Double) -> Double)) -> Tween {
        self.easingFn = easingFn
        return self
    }

    public func onComplete(_ completeFn: @escaping (() -> ())) -> Tween {
        _onComplete = completeFn
        return self
    }

    public func onLoopsComplete(_ loopsCompleteFn: @escaping (() -> ())) -> Tween {
        _onLoopsComplete = loopsCompleteFn
        return self
    }

    public func onPingPongComplete(_ pingPongCompleteFn: @escaping (() -> ())) -> Tween {
        _onPingPongComplete = pingPongCompleteFn
        return self
    }

    public func play() -> Tween {
        if complete {
            return restart()
        }
        else {
            tweening = true
            anchorStart(at: nil, offset: -progress * duration)
        }
        _onPlay?()
        return self
    }

    /// Pauses at the progress of the last update.
    public func pause() {
        tweening = false
        _onPause?()
    }

    public func stop() {
        tweening = false
        _onStop?()
        progress = 0.0
    }

    public func remove() {
        stop()
        complete = true
    }

    public func pingPong(_ pingPong: Bool = true) -> Tween {
        self.pingPong = pingPong
        return self
    }

    public func delay(_ delay: Double, onLoop: Bool = false, onPingPing: Bool = false) -> Tween {
        self.delay = delay
        delayOnLoop = onLoop
        delayOnPingPong = onPingPing
        return self
    }

    public func loop(_ looping: Bool = true) -> Tween {
        self.looping = looping
        return self
    }

    public func duration(_ duration: Double) -> Tween {
        self.duration = duration
        return self
    }

    public func loops(_ count: Int) -> Tween {
        loops = count
        return self
    }

    public func easing(_ easing: Easing) -> Tween {
        easingFn = easing.function
        return self
    }

    func pingPong(_ progress: Double) -> Double {
        if pingPong, pingPongState {
            return 1.0 - progress
        }
        return progress
    }

    /// Anchors `startTime` `offset` seconds after `time`, or after the next update's time when nil.
    private func anchorStart(at time: TimeInterval?, offset: TimeInterval) {
        startTimeOffset = offset
        startTime = time.map { $0 + offset }
    }

    func updateProgress(time: TimeInterval) {
        guard tweening else { return }
        let startTime = self.startTime ?? time + startTimeOffset
        if self.startTime == nil {
            self.startTime = startTime
        }
        let deltaTime = time - startTime
        if deltaTime >= 0.0, lastDeltaTime < 0.0 {
            _onTweenStart?()
        }
        lastDeltaTime = deltaTime
        progress = deltaTime / duration
    }

    /// Advances to `time`, in seconds on the caller's timeline, and returns whether the tween is complete.
    func update(time: TimeInterval) -> Bool {
        updateProgress(time: time)

        guard tweening, progress >= 0.0 else { return complete }

        let _progress = pingPong(min(max(progress, 0.0), 1.0))
        let _tween = easingFn(_progress)

        _onUpdate?(_progress)
        _onTween?(_tween)

        if progress >= 1.0 {
            loop += 1

            complete = true
            tweening = false

            let finalUpdateProgress = pingPong(1.0)
            _onUpdate?(finalUpdateProgress)
            _onTween?(finalUpdateProgress)
            _onComplete?()

            var restart = false

            var loopsLeft = Int.max
            if !looping, loops > 0 {
                loopsLeft = loops - loop
                if loopsLeft == 0 {
                    _onLoopsComplete?()
                }
            }

            if pingPong, loopsLeft > 0 {
                pingPongState = !pingPongState
                if pingPongState {
                    restart = true
                }
                else {
                    _onPingPongComplete?()
                }
            }

            if looping || (loops > 0 && loopsLeft > 0) {
                restart = true
            }

            if restart {
                _ = start(anchoredAt: time)
            }
        }

        return complete
    }
}

extension Tween: Equatable {
    public static func == (lhs: Tween, rhs: Tween) -> Bool { lhs === rhs }
}
