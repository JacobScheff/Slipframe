//
//  TutorialDirector.swift
//  Endless Runner
//
//  Advances tutorial sections from song timestamps (wall-clock, started with the track).
//

import Foundation

struct TutorialSuccessBanner: Equatable {
    var text: String
    /// 0…1 entrance (scale / fade in).
    var appear: Float
    /// Soft breathing pulse while held (0…1).
    var pulse: Float
    /// 0…1 exit (fade / lift away). 0 = fully present.
    var exit: Float

    var opacity: Float {
        let enter = appear
        let leave = 1 - exit
        return max(0, min(1, enter * leave))
    }

    var scale: Float {
        let enter = 0.72 + 0.28 * appear
        let leave = 1 + 0.12 * exit
        return enter * leave
    }
}

struct TutorialFrame: Equatable {
    var section: TutorialSection
    var didEnterSection: Bool
    var elapsed: Float
    /// 0…1 coaching card opacity.
    var overlayOpacity: Float
    /// Extra portal rim pulse (0…1) during overdrive.
    var portalPulse: Float
    var shouldFinish: Bool
    var successBanner: TutorialSuccessBanner?
}

@MainActor
final class TutorialDirector {
    private(set) var elapsed: Float = 0
    private(set) var sectionIndex: Int = 0
    private(set) var isActive = false

    /// Appear + hold + exit for "TEST RUN SUCCEEDED".
    private static let outroAppear: Float = 0.85
    private static let outroHold: Float = 3.6
    private static let outroExit: Float = 0.9
    private static var outroTotal: Float { outroAppear + outroHold + outroExit }

    private var outroElapsed: Float = 0
    private var didRequestFinish = false
    private var overlayFade: Float = 1

    var currentSection: TutorialSection {
        TutorialCatalog.sections[sectionIndex]
    }

    func begin() {
        isActive = true
        elapsed = 0
        sectionIndex = 0
        outroElapsed = 0
        didRequestFinish = false
        overlayFade = 1
    }

    func stop() {
        isActive = false
        didRequestFinish = false
    }

    func update(deltaTime: Float) -> TutorialFrame {
        guard isActive else {
            return TutorialFrame(
                section: TutorialCatalog.sections[0],
                didEnterSection: false,
                elapsed: elapsed,
                overlayOpacity: 0,
                portalPulse: 0,
                shouldFinish: false,
                successBanner: nil
            )
        }

        elapsed += deltaTime
        let targetIndex = TutorialCatalog.sectionIndex(at: elapsed)
        let didEnter = targetIndex != sectionIndex
        if didEnter {
            sectionIndex = targetIndex
            outroElapsed = 0
        }
        let section = TutorialCatalog.sections[sectionIndex]

        // Smooth overlay fade for overdrive / outro.
        let overlayTarget: Float = section.hidesOverlay || section.isOutro ? 0 : 1
        let fadeSpeed: Float = 2.8
        if overlayFade < overlayTarget {
            overlayFade = min(overlayTarget, overlayFade + deltaTime * fadeSpeed)
        } else if overlayFade > overlayTarget {
            overlayFade = max(overlayTarget, overlayFade - deltaTime * fadeSpeed)
        }

        var shouldFinish = false
        var banner: TutorialSuccessBanner?
        if section.isOutro {
            if !didEnter {
                outroElapsed += deltaTime
            }
            banner = Self.makeSuccessBanner(text: section.title, time: outroElapsed)
            if outroElapsed >= Self.outroTotal, !didRequestFinish {
                didRequestFinish = true
                shouldFinish = true
            }
        } else {
            outroElapsed = 0
        }

        let portalPulse: Float
        if section.portalOverdrive {
            portalPulse = 0.55 + 0.45 * Float(sin(Double(elapsed) * 9.0))
        } else if didEnter {
            portalPulse = 1
        } else {
            portalPulse = 0
        }

        return TutorialFrame(
            section: section,
            didEnterSection: didEnter,
            elapsed: elapsed,
            overlayOpacity: overlayFade,
            portalPulse: portalPulse,
            shouldFinish: shouldFinish,
            successBanner: banner
        )
    }

    private static func makeSuccessBanner(text: String, time: Float) -> TutorialSuccessBanner {
        let appear: Float
        if time <= 0 {
            appear = 0
        } else if time < outroAppear {
            // Ease-out cubic for a confident pop-in.
            let u = time / outroAppear
            appear = 1 - pow(1 - u, 3)
        } else {
            appear = 1
        }

        let holdStart = outroAppear
        let exitStart = outroAppear + outroHold
        let pulse: Float
        if time >= holdStart, time < exitStart {
            let holdT = time - holdStart
            pulse = 0.5 + 0.5 * Float(sin(Double(holdT) * 3.2))
        } else if time < holdStart {
            pulse = appear
        } else {
            pulse = 0
        }

        let exit: Float
        if time < exitStart {
            exit = 0
        } else if time >= outroTotal {
            exit = 1
        } else {
            let u = (time - exitStart) / outroExit
            // Ease-in so it hangs, then lifts away.
            exit = u * u
        }

        return TutorialSuccessBanner(text: text, appear: appear, pulse: pulse, exit: exit)
    }
}
