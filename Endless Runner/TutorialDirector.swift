//
//  TutorialDirector.swift
//  Endless Runner
//
//  Advances tutorial sections from song timestamps (wall-clock, started with the track).
//

import Foundation

struct TutorialFrame: Equatable {
    var section: TutorialSection
    var didEnterSection: Bool
    var elapsed: Float
    /// 0…1 coaching card opacity.
    var overlayOpacity: Float
    /// Extra portal rim pulse (0…1) during overdrive.
    var portalPulse: Float
    var shouldStopMusic: Bool
    var shouldFinish: Bool
    var showTestRunBanner: Bool
}

@MainActor
final class TutorialDirector {
    private(set) var elapsed: Float = 0
    private(set) var sectionIndex: Int = 0
    private(set) var isActive = false

    /// Seconds to hold the "TEST RUN INITIATED" banner before returning to the menu.
    private static let outroHold: Float = 2.4
    private var outroElapsed: Float = 0
    private var didRequestMusicStop = false
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
        didRequestMusicStop = false
        didRequestFinish = false
        overlayFade = 1
    }

    func stop() {
        isActive = false
        didRequestFinish = false
        didRequestMusicStop = false
    }

    func update(deltaTime: Float) -> TutorialFrame {
        guard isActive else {
            return TutorialFrame(
                section: TutorialCatalog.sections[0],
                didEnterSection: false,
                elapsed: elapsed,
                overlayOpacity: 0,
                portalPulse: 0,
                shouldStopMusic: false,
                shouldFinish: false,
                showTestRunBanner: false
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

        var shouldStopMusic = false
        if section.isOutro, !didRequestMusicStop {
            didRequestMusicStop = true
            shouldStopMusic = true
        }

        var shouldFinish = false
        var showBanner = false
        if section.isOutro {
            showBanner = true
            // On the enter frame, hold the banner before counting down.
            if !didEnter {
                outroElapsed += deltaTime
            }
            if outroElapsed >= Self.outroHold, !didRequestFinish {
                didRequestFinish = true
                shouldFinish = true
            }
        } else {
            outroElapsed = 0
        }

        let portalPulse: Float
        if section.portalOverdrive {
            // Violent pulse keyed to elapsed time.
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
            shouldStopMusic: shouldStopMusic,
            shouldFinish: shouldFinish,
            showTestRunBanner: showBanner
        )
    }
}
