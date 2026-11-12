import SwiftUI
import RealityKit
import UIKit
import simd

enum TutorialSection: String, CaseIterable, Identifiable {
    case basics = "Start here", biomes = "Biomes", reference = "Rifts & modes"
    var id: Self { self }
    var lessons: [TutorialLesson] { TutorialLesson.allCases.filter { $0.section == self } }
}

struct TutorialStep {
    let title: String
    let instruction: String
    let detail: String
}

/// Stable identities drive both the lesson and its choreography. Editing copy
/// cannot accidentally select a different animation or break an interaction.
enum TutorialLesson: String, CaseIterable, Identifiable {
    case space, dodge, tokens, pause, rifts, ready
    case emberRun, lowCrawl, summitStep, ghostGlass, stormPass, crystalCave, vectorFoundry, orbitGate
    case difficulty, modifiers, modes

    var id: Self { self }
    var section: TutorialSection {
        switch self {
        case .space, .dodge, .tokens, .pause, .rifts, .ready: return .basics
        case .difficulty, .modifiers, .modes: return .reference
        default: return .biomes
        }
    }
    var biome: EnvironmentID? {
        switch self {
        case .emberRun: return .emberRun
        case .lowCrawl: return .lowCrawl
        case .summitStep: return .summitStep
        case .ghostGlass: return .ghostGlass
        case .stormPass: return .stormPass
        case .crystalCave: return .crystalCave
        case .vectorFoundry: return .vectorFoundry
        case .orbitGate: return .orbitGate
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .space: return "Meet your track"
        case .dodge: return "Find the clear lane"
        case .tokens: return "Reach for tokens"
        case .pause: return "Take a breather"
        case .rifts: return "Choose your next world"
        case .ready: return "You're ready to run"
        case .difficulty: return "Read a rift"
        case .modifiers: return "A bonus for the visit"
        case .modes: return "Find your run"
        default: return biome?.displayName ?? ""
        }
    }
    var subtitle: String {
        switch self {
        case .space: return "Your room is the play space."
        case .dodge, .emberRun: return "Move your body into the opening."
        case .tokens: return "Touch gold. Build your bonus."
        case .pause: return "The track waits when you step away."
        case .rifts: return "Your lane chooses the destination."
        case .ready: return "Start simple. Discover the rest as you go."
        case .lowCrawl: return "Get below the hanging barrier."
        case .summitStep: return "A small rise clears a low hurdle."
        case .ghostGlass: return "Follow the edges of the glass."
        case .stormPass: return "Read the opening after the gust."
        case .crystalCave: return "Two different halves. One reward."
        case .vectorFoundry: return "Aim, hold, then guide."
        case .orbitGate: return "Put your head through the opening."
        case .difficulty: return "Destination, difficulty, then modifier."
        case .modifiers: return "Your HUD explains the active effect."
        case .modes: return "Four ways to follow the track."
        }
    }
    var steps: [TutorialStep] {
        switch self {
        case .space:
            return [
                .init(title: "Start at the marker", instruction: "Stand at the start marker and face the portal. The track has three lanes.", detail: "Keep enough clear space to lean, reach, and move a little to either side."),
                .init(title: "Let the track come to you", instruction: "Walls and tokens move toward you. You stay near the start of the track.", detail: "The pale figure in this miniature represents you. You can watch every example without moving.")
            ]
        case .dodge, .emberRun:
            return [
                .init(title: "Look for the opening", instruction: "This wall blocks the middle lane. Either side is clear.", detail: "In the next step, watch the figure lean into the left lane before the wall arrives."),
                .init(title: "Lean or step sideways", instruction: "Move your head into a clear lane. Keep your hands clear of the wall too.", detail: "Small, deliberate movements are enough. You don't steer with a controller."),
                .init(title: "Let the wall pass", instruction: "Hold the opening until the whole wall is past you, then look ahead for the next one.", detail: "A hit to your head or hands ends the run, unless a shield absorbs it.")
            ]
        case .tokens:
            return [
                .init(title: "Reach into the gold", instruction: "Touch a gold token with either hand to collect it. You don't need to pinch.", detail: "The example hand reaches sideways while the head stays in the clear lane."),
                .init(title: "Watch the two rewards", instruction: "Collecting a token raises your token count and builds your score bonus.", detail: "Score grows with distance. Tokens have their own counter and rankings."),
                .init(title: "Keep the bonus going", instruction: "Tokens and close slips build a bonus of up to +100%. It gradually drains between rewards.", detail: "Close slips also award points. Focus on finding clear openings while you learn.")
            ]
        case .pause:
            return [
                .init(title: "Step outside the track", instruction: "When you leave the play area, obstacles and music slow to a stop.", detail: "The HUD asks you to return to the start area."),
                .init(title: "Return when you're ready", instruction: "Step back into the start area to resume the run.", detail: "Watch the miniature leave the lanes, wait, and return.")
            ]
        case .rifts:
            return [
                .init(title: "Three gates, three worlds", instruction: "Normal starts in Ember Run. At a junction, three destinations approach during a recovery break.", detail: "Look inside each portal to see the world it leads to."),
                .init(title: "Line up with your choice", instruction: "Move into the left, middle, or right lane of the world you want.", detail: "Choose a lane below to preview the decision. In a run, your head position makes the choice."),
                .init(title: "Stay with your gate", instruction: "Hold that lane as the gates arrive. Your chosen world becomes the next part of the run.", detail: "Open Rifts & modes whenever you want to learn about difficulty and modifiers.")
            ]
        case .ready:
            return [
                .init(title: "Your first run", instruction: "Find the clear lane. Reach for gold. Pick a world when the gates arrive.", detail: "That's enough to begin. The biome guides are here whenever you want to learn another mechanic."),
                .init(title: "Go at your own pace", instruction: "Start Normal, or return to setup to choose a different mode.", detail: "Replay any lesson from How to play. Your room decorations and floor track can be adjusted in Settings.")
            ]
        case .lowCrawl:
            return [
                .init(title: "Notice the hanging barrier", instruction: "Low Crawl adds barriers with a clear opening underneath.", detail: "Read the bottom edge as the barrier comes toward you."),
                .init(title: "Lower your head", instruction: "Duck beneath the barrier and keep your head low until it passes.", detail: "Side walls still need a sideways dodge. Watch for both kinds of opening.")
            ]
        case .summitStep:
            return [
                .init(title: "Notice the low hurdle", instruction: "Summit Step adds low barriers across the track.", detail: "The game measures your standing height between runs."),
                .init(title: "Rise as it reaches you", instruction: "A small rise or hop lifts your head above the calibrated height and clears the hurdle.", detail: "You only need a little height. Continue to dodge ordinary side walls.")
            ]
        case .ghostGlass:
            return [
                .init(title: "Find the faint outline", instruction: "Some walls are almost transparent. Their edges still show where the opening is.", detail: "Glass walls can hit your head and hands, just like solid walls."),
                .init(title: "Move into clear space", instruction: "Follow the edges and shift into the open lane before the glass reaches you.", detail: "The miniature highlights the wall outline so you can see the route.")
            ]
        case .stormPass:
            return [
                .init(title: "Watch for a gust", instruction: "A wind cue warns you that an approaching obstacle is about to shift sideways.", detail: "The gust moves the obstacle. Watch its new position."),
                .init(title: "Read the new opening", instruction: "Adjust your lane after the shift, then let the obstacle pass.", detail: "Don't assume an opening will stay where it first appeared.")
            ]
        case .crystalCave:
            return [
                .init(title: "Grab a half in each hand", instruction: "Close a fist around a crystal half to hold it. Take a different type in the other hand.", detail: "Blue and coral halves combine. Two of the same type do not."),
                .init(title: "Bring your hands together", instruction: "Bring the two different halves together to merge them into a token reward.", detail: "A normal pair gives 5 tokens. Open a hand to drop a half."),
                .init(title: "Look for charged halves", instruction: "Charged halves glow more brightly and make a bigger reward when merged.", detail: "One charged half gives 50 tokens; two give 10,000, before any modifier.")
            ]
        case .vectorFoundry:
            return [
                .init(title: "Aim through your hand", instruction: "Raise a hand toward a floating shape. Hold your aim briefly to lock onto it.", detail: "Each hand can guide its own shape. You don't need to pinch."),
                .init(title: "Guide it to the matching slot", instruction: "Move your hand to move the shape into the opening with the same outline.", detail: "Once locked, movement guides the shape; turning your wrist doesn't release it."),
                .init(title: "Fill every slot", instruction: "Fit all the shapes into their matching slots to open the approaching door.", detail: "Watch both shapes settle before the two door panels slide apart.")
            ]
        case .orbitGate:
            return [
                .init(title: "Find the center opening", instruction: "Guide your head through the inside of the approaching hoop.", detail: "The opening can shift or tilt. Follow the space inside the rim."),
                .init(title: "Watch the rotating gap", instruction: "Some gates have a rotating shutter. Move your head into its open section as it arrives.", detail: "The miniature shows the opening lining up with the pale head marker.")
            ]
        case .difficulty:
            return [
                .init(title: "Look inside first", instruction: "The world inside the portal identifies the destination. The diamonds show its difficulty.", detail: "Each of the three gates gets its own difficulty and optional modifier."),
                .init(title: "Count the diamonds", instruction: "One is Stable: ×1 distance score. Two are Charged: ×1.5. Three are Unstable: ×2.", detail: "Higher difficulty brings denser patterns and more opportunities for rewards."),
                .init(title: "Check the modifier", instruction: "The lower emblem identifies a bonus for that visit. A gate can also have no modifier.", detail: "The HUD names and explains the active effect, so you don't need to memorize symbols.")
            ]
        case .modifiers:
            return [
                .init(title: "Token Surge", instruction: "Each token counts twice, and more token chains appear.", detail: "Watch one pickup add two tokens in the example below."),
                .init(title: "Aegis", instruction: "A shield absorbs one collision. That hit halves your current bonus, and the shield is spent.", detail: "Watch Shield ready change to Shield spent. A new visit can give you a new shield."),
                .init(title: "Overdrive", instruction: "Distance points increase by 25%. Tokens and close slips also build bonus faster.", detail: "The comparison below shows the same distance with and without Overdrive."),
                .init(title: "Magnet", instruction: "Collect tokens and crystal halves from farther away.", detail: "Watch the token curve toward the example hand. Your head can stay in its lane."),
                .init(title: "Close Call", instruction: "A wider close-slip window gives double points and bonus gain for each close slip.", detail: "Keep clear of the wall. This modifier rewards a close pass; it does not protect you from a hit."),
                .init(title: "Bonus Bank", instruction: "Your score bonus drains half as fast.", detail: "Watch both meters start at the same value. Bonus Bank preserves more of the bonus between rewards.")
            ]
        case .modes:
            return [
                .init(title: "Normal", instruction: "Start in Ember Run and choose a new world at each junction.", detail: "Three gates approach. Move into a lane and stay with your destination."),
                .init(title: "Loop", instruction: "Choose one biome and stay in it for the whole run.", detail: "Each Loop biome has its own score and token rankings. It is a useful way to learn one mechanic."),
                .init(title: "Playlist", instruction: "Select one or more biomes, choose the first world or start at random, and let the route shuffle within your selection.", detail: "Playlist runs are unranked. At least one biome must be selected to start."),
                .init(title: "Daily", instruction: "Everyone gets the same seeded biome route and obstacle patterns for the day.", detail: "Daily resets at midnight Eastern Time. Setup shows the date, countdown, and your bests for today.")
            ]
        }
    }
}

struct TutorialTracking {
    var head: SIMD3<Float>?
    var forward = SIMD3<Float>(0, 0, -1)
}

@MainActor
final class SpatialTutorial: ObservableObject {
    @Published private(set) var lesson = TutorialLesson.space
    @Published private(set) var stepIndex = 0
    @Published var paused = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var selectedLane = 0
    @Published private(set) var completedLessons: Set<TutorialLesson> = []
    let root = Entity()
    let controls = Entity()
    let theater = TutorialTheater()
    var reduceMotion = false {
        didSet { if oldValue != reduceMotion { render(Float(progress)) } }
    }
    private var active = false
    private var elapsed: Double = 0
    private var lastProgress = -1
    private let duration: Double = 5.5
    private var rememberedSteps: [TutorialLesson: Int] = [:]
    private var rememberedLessons: [TutorialSection: TutorialLesson] = [:]
    var step: TutorialStep { lesson.steps[stepIndex] }
    var index: Int { TutorialLesson.allCases.firstIndex(of: lesson) ?? 0 }
    var isLastStep: Bool { stepIndex == lesson.steps.count - 1 }
    var lessonNumber: Int { (lesson.section.lessons.firstIndex(of: lesson) ?? 0) + 1 }
    var isFinished: Bool { progress >= 1 }
    var modifier: RiftModifier? {
        guard lesson == .modifiers else { return nil }
        let modifiers: [RiftModifier] = [.tokenSurge, .aegis, .overdrive, .magnet, .closeCall, .bonusBank]
        return modifiers[stepIndex]
    }
    var playheadSeconds: Double { elapsed }

    func mount(in parent: Entity, panel: Entity?) {
        if controls.parent !== parent { parent.addChild(controls) }
        if root.parent !== controls { controls.addChild(root); root.addChild(theater.root) }
        guard let panel else { return }
        if panel.parent !== controls { controls.addChild(panel) }
        // Derive the miniature's placement from the real attachment dimensions,
        // keeping it in the left-hand viewport at every attachment pixel density.
        let bounds = panel.visualBounds(relativeTo: controls)
        guard bounds.extents.x > 0 else { return }
        root.position = bounds.center + [-bounds.extents.x * 0.19, bounds.extents.y * 0.12, bounds.extents.x * 0.22]
        root.scale = SIMD3(repeating: bounds.extents.x * 0.35)
        root.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
    }

    func begin(tracking: TutorialTracking, lesson: TutorialLesson = .space) {
        let position = tracking.head ?? SIMD3<Float>(0, 1.5, 0)
        let horizontal = SIMD3(tracking.forward.x, 0, tracking.forward.z)
        let forward = length(horizontal) > 0.01 ? normalize(horizontal) : SIMD3(0, 0, -1)
        // Enlarge the shared parent so text, controls, and the miniature retain
        // their alignment while occupying substantially more of the user's view.
        controls.scale = SIMD3(repeating: 1.6)
        controls.position = position + forward * 1.15 + [0, -0.10, 0]
        controls.orientation = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0])
        active = true
        select(lesson)
    }

    func selectSection(_ section: TutorialSection) {
        guard section != lesson.section else { return }
        select(rememberedLessons[section] ?? section.lessons[0], resume: true)
    }

    func select(_ lesson: TutorialLesson, resume: Bool = false) {
        rememberedSteps[self.lesson] = stepIndex
        rememberedLessons[self.lesson.section] = self.lesson
        self.lesson = lesson
        stepIndex = resume ? min(rememberedSteps[lesson] ?? 0, lesson.steps.count - 1) : 0
        selectedLane = lesson == .rifts ? 2 : 0
        theater.build(lesson)
        replay()
    }

    func selectStep(_ index: Int) {
        stepIndex = min(max(0, index), lesson.steps.count - 1)
        replay()
    }

    func replay() {
        elapsed = 0
        progress = 0
        lastProgress = -1
        paused = false
        render(0)
    }

    func chooseLane(_ lane: Int) {
        selectedLane = min(2, max(0, lane))
        replay()
    }

    func scrub(_ value: Double) {
        guard value.isFinite else { return }
        paused = true
        progress = min(1, max(0, value))
        elapsed = progress * duration
        lastProgress = Int(progress * 60)
        render(Float(progress))
    }

    func previous() {
        if stepIndex > 0 { selectStep(stepIndex - 1) }
        else if lessonNumber > 1 {
            let previous = lesson.section.lessons[lessonNumber - 2]
            select(previous)
            selectStep(previous.steps.count - 1)
        }
    }

    func next() {
        if !isLastStep { selectStep(stepIndex + 1) }
        else {
            completedLessons.insert(lesson)
            if lessonNumber < lesson.section.lessons.count { select(lesson.section.lessons[lessonNumber]) }
        }
    }

    func completeBasics() {
        completedLessons.formUnion(TutorialSection.basics.lessons)
        UserDefaults.standard.set(true, forKey: "tutorial.completed.v3")
    }
    func stop() { active = false; paused = true }
    func remove() { stop(); root.removeFromParent(); controls.removeFromParent() }

    func tick(_ delta: Double) {
        guard active, !paused, !isFinished, delta.isFinite, delta > 0 else { return }
        elapsed = min(duration, elapsed + min(delta, 0.1))
        let p = elapsed / duration
        let quantized = Int(p * 60)
        if quantized != lastProgress {
            progress = p
            lastProgress = quantized
        }
        // A held final pose never jumps to another mechanic or loops under text
        // the player is still reading. Step changes happen only on user input.
        render(Float(p))
    }

    private func render(_ p: Float) {
        theater.animate(lesson: lesson, step: stepIndex, progress: p,
                        reduced: reduceMotion, selectedLane: selectedLane, modifier: modifier)
    }

    var demoStatus: String {
        let resolved = progress >= 0.72
        switch lesson {
        case .space: return stepIndex == 0 ? "Three lanes · You start here" : "The track moves toward you"
        case .dodge, .emberRun, .ghostGlass: return stepIndex == 0 ? "Middle lane blocked · Both sides open" : resolved ? "Clear of the wall" : "Head and hands move together"
        case .tokens:
            if stepIndex == 2 { return "Bonus +\(60 - Int(progress * 10))% · Gradually drains between rewards" }
            return resolved ? "Collected · +1 token · Bonus increased" : "Touch with either hand · No pinch"
        case .pause: return stepIndex == 0 ? (resolved ? "Outside the track · Paused" : "Stepping out · Slowing down") : (resolved ? "Back in the start area · Moving" : "Returning to the start area")
        case .rifts: return ["Left: Ghost Glass", "Middle: Crystal Cave", "Right: Storm Pass"][selectedLane] + (stepIndex == 2 && resolved ? " · Chosen" : "")
        case .crystalCave: return stepIndex == 0 ? "Blue + coral · Different types" : resolved ? (stepIndex == 2 ? "One charged half · 50 tokens" : "Merged · 5 tokens") : "Bring the different halves together"
        case .vectorFoundry: return stepIndex == 0 ? (resolved ? "Shape locked" : "Aim and hold briefly") : stepIndex == 1 ? (resolved ? "Cube fitted · One slot remains" : "Move your hand toward the square slot") : resolved ? "Every slot filled · Door open" : "Fit the remaining sphere"
        case .lowCrawl: return stepIndex == 0 ? "Opening below the barrier" : "Head stays below until the barrier passes"
        case .summitStep: return stepIndex == 0 ? "Low hurdle approaching" : "Small rise as the hurdle passes"
        case .stormPass: return stepIndex == 0 ? "Wind shifts the obstacle right" : "New opening on the left"
        case .orbitGate: return stepIndex == 0 ? "Head inside the hoop" : "Head inside the rotating gap"
        case .difficulty: return stepIndex == 2 ? "Left: Token Surge · Middle: Aegis · Right: None" : "Left: Stable · Middle: Charged · Right: Unstable"
        case .modifiers:
            switch modifier {
            case .aegis: return resolved ? "Shield spent · Your run continues" : "Shield ready · One collision protected"
            case .tokenSurge: return resolved ? "One pickup · Two tokens" : "Token Surge · Double token value"
            case .overdrive: return "The same distance · 25% more points"
            case .magnet: return "Wider reach · Your head stays in its lane"
            case .closeCall: return resolved ? "Close slip · Double points and bonus gain" : "Keep your head and hands clear of the wall"
            case .bonusBank: return "Same starting bonus · Half the drain"
            case nil: return ""
            }
        case .modes: return ["Choose one of three destinations", "Crystal Cave · The same biome throughout", "Your selection · A shuffled route", "The same seeded route for every player"][stepIndex]
        case .ready: return "Clear lane. Gold tokens. Your next world."
        }
    }
}

struct TutorialControls: View {
    @ObservedObject var tutorial: SpatialTutorial
    let close: () -> Void
    let returnToSetup: () -> Void
    let startNormal: () -> Void

    private var lesson: TutorialLesson { tutorial.lesson }
    private var section: TutorialSection { lesson.section }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                HStack(spacing: 10) {
                    SlipframeMark().frame(width: 27, height: 30)
                    Text("How to play").font(.system(size: 21, weight: .semibold))
                }
                Spacer()
                ForEach(TutorialSection.allCases) { item in
                    Button(item.rawValue) { tutorial.selectSection(item) }
                        .buttonStyle(ConsoleButtonStyle(selected: section == item))
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 20) }
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Close How to play")
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Rectangle().fill(SlipframeStyle.line).frame(height: 1)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ConsoleCaption(title: "Miniature demonstration")
                        Spacer()
                        Text(tutorial.reduceMotion ? "Still poses" : tutorial.isFinished ? "Final pose" : tutorial.paused ? "Paused" : "Playing")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SlipframeStyle.muted)
                    }
                    // The RealityKit miniature is placed in front of this region.
                    // No duplicate RealityView, invisible gesture targets, or
                    // physical reaching into an attachment is needed.
                    Color.clear.frame(height: 224)
                        .accessibilityLabel("Miniature example: " + tutorial.demoStatus)
                    Slider(value: Binding(get: { tutorial.progress }, set: { tutorial.scrub($0) }), in: 0...1)
                        .tint(SlipframeStyle.ice)
                        .frame(height: 20)
                        .accessibilityLabel("Demonstration timeline")
                        .accessibilityValue("\(Int(tutorial.progress * 100)) percent")
                    demonstrationReadout
                        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
                        .accessibilityLabel(tutorial.demoStatus)
                    HStack(spacing: 8) {
                        Button { tutorial.replay() } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                        Button {
                            if tutorial.isFinished { tutorial.replay() }
                            else { tutorial.paused.toggle() }
                        } label: {
                            Label(tutorial.paused || tutorial.isFinished ? "Play" : "Pause",
                                  systemImage: tutorial.paused || tutorial.isFinished ? "play.fill" : "pause.fill")
                        }
                        Spacer()
                        if lesson == .rifts, tutorial.stepIndex > 0 {
                            ForEach(0..<3) { lane in
                                Button(["Left", "Middle", "Right"][lane]) { tutorial.chooseLane(lane) }
                                    .buttonStyle(ConsoleButtonStyle(selected: tutorial.selectedLane == lane))
                            }
                        }
                    }
                    .buttonStyle(ConsoleButtonStyle())
                    .labelStyle(.titleAndIcon)
                }
                .frame(width: 456)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ConsoleCaption(title: "\(section == .basics ? "Lesson" : "Guide") \(tutorial.lessonNumber) of \(section.lessons.count)", color: SlipframeStyle.ice)
                        Spacer()
                        Menu {
                            ForEach(section.lessons) { item in
                                Button { tutorial.select(item, resume: true) } label: {
                                    if tutorial.completedLessons.contains(item) {
                                        Label(item.title, systemImage: "checkmark")
                                    } else { Text(item.title) }
                                }
                            }
                        } label: {
                            Label("Lessons", systemImage: "list.bullet")
                                .font(.system(size: 13, weight: .medium))
                                .frame(minHeight: 36)
                        }
                        .accessibilityLabel("Choose a lesson")
                    }
                    Text(lesson.title).font(.system(size: 28, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(lesson.subtitle).font(.system(size: 15))
                        .foregroundStyle(SlipframeStyle.muted)
                    HStack(spacing: 6) {
                        ForEach(lesson.steps.indices, id: \.self) { index in
                            Button { tutorial.selectStep(index) } label: {
                                Text("\(index + 1)").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ConsoleButtonStyle(selected: index == tutorial.stepIndex))
                            .accessibilityLabel("Step \(index + 1): \(lesson.steps[index].title)")
                            .accessibilityAddTraits(index == tutorial.stepIndex ? .isSelected : [])
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tutorial.step.title).font(.system(size: 20, weight: .semibold))
                            Text(tutorial.step.instruction).font(.system(size: 18))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(tutorial.step.detail).font(.system(size: 15))
                                .foregroundStyle(SlipframeStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id("\(lesson.rawValue)-\(tutorial.stepIndex)")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle().fill(SlipframeStyle.line).frame(height: 1)
            HStack(spacing: 12) {
                Button { tutorial.previous() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(tutorial.lessonNumber == 1 && tutorial.stepIndex == 0)
                Text("Step \(tutorial.stepIndex + 1) of \(lesson.steps.count)")
                    .font(.system(size: 13)).foregroundStyle(SlipframeStyle.muted)
                Spacer()
                if lesson == .ready {
                    Button("Choose a mode") { tutorial.completeBasics(); returnToSetup() }
                        .buttonStyle(ConsoleButtonStyle())
                    Button("Start Normal") { tutorial.completeBasics(); startNormal() }
                        .buttonStyle(ConsoleButtonStyle(prominent: true))
                } else if tutorial.isLastStep && tutorial.lessonNumber == section.lessons.count {
                    Button("Done") { tutorial.next(); close() }.buttonStyle(ConsoleButtonStyle(prominent: true))
                } else {
                    Button {
                        tutorial.next()
                    } label: {
                        Label(tutorial.isLastStep ? "Next: \(section.lessons[tutorial.lessonNumber].title)" : "Next step", systemImage: "chevron.right")
                            .lineLimit(1)
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 920, height: 600)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.linearGradient(colors: [SlipframeStyle.panel, SlipframeStyle.ink],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(SlipframeStyle.line).allowsHitTesting(false) }
    }

    @ViewBuilder
    private var demonstrationReadout: some View {
        let collected = tutorial.progress >= 0.72
        if lesson == .tokens, tutorial.stepIndex < 2 {
            HStack(spacing: 36) {
                ConsoleMetric(title: "Example tokens", value: collected ? "1" : "0", color: SlipframeStyle.amber, size: 20)
                ConsoleMetric(title: "Example bonus", value: collected ? "+25%" : "+20%", color: SlipframeStyle.ice, size: 20)
            }
        } else if lesson == .tokens {
            bonusComparison(title: "Bonus between pickups", amount: 60 - Int(tutorial.playheadSeconds / 0.75))
        } else if let modifier = tutorial.modifier {
            switch modifier {
            case .tokenSurge:
                HStack(spacing: 36) {
                    ConsoleMetric(title: "Normal", value: collected ? "1 token" : "0 tokens", size: 20)
                    ConsoleMetric(title: "Token Surge", value: collected ? "2 tokens" : "0 tokens", color: SlipframeStyle.amber, size: 20)
                }
            case .aegis:
                HStack(spacing: 36) {
                    ConsoleMetric(title: "Aegis", value: collected ? "Shield spent" : "Shield ready", color: SlipframeStyle.ice, size: 20)
                    ConsoleMetric(title: "Example bonus", value: collected ? "+40%" : "+80%", size: 20)
                }
            case .overdrive:
                HStack(spacing: 36) {
                    ConsoleMetric(title: "Normal distance points", value: "\(Int(tutorial.progress * 100))", size: 20)
                    ConsoleMetric(title: "With Overdrive", value: "\(Int(tutorial.progress * 125))", color: SlipframeStyle.ice, size: 20)
                }
            case .bonusBank:
                HStack(spacing: 24) {
                    bonusComparison(title: "Normal · 30s comparison", amount: 80 - Int(tutorial.progress * 30 / 0.75))
                    bonusComparison(title: "Bonus Bank · Same interval", amount: 80 - Int(tutorial.progress * 30 / 1.5))
                }
            default:
                Text(tutorial.demoStatus).font(.system(size: 14, weight: .medium)).foregroundStyle(SlipframeStyle.ice)
            }
        } else {
            Text(tutorial.demoStatus).font(.system(size: 14, weight: .medium)).foregroundStyle(SlipframeStyle.ice)
        }
    }

    private func bonusComparison(title: String, amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(SlipframeStyle.muted)
                Spacer(minLength: 6)
                Text("+\(amount)%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(SlipframeStyle.ice)
                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, amount))) / 100)
            }
            .frame(height: 4)
        }
    }
}

/// Small, deliberately diagrammatic geometry. Every frame is computed from the
/// current lesson, step, and progress; no callbacks or accumulated transforms.
@MainActor
final class TutorialTheater {
    let root = Entity()
    private let actor = Entity()
    private let leftHand = Entity()
    private let rightHand = Entity()
    private let hazards = Entity()
    private let props = Entity()
    private let portal = Entity()
    private let token = Entity()
    private let shield = Entity()
    private let shape = Entity()
    private let secondShape = Entity()
    private let reward = Entity()
    private var walls: [Entity] = []
    private var gates: [Entity] = []
    private var halves: [Entity] = []
    private var slots: [Entity] = []
    private let pale = UIColor(red: 0.87, green: 0.94, blue: 0.96, alpha: 1)
    private let blue = UIColor(red: 0.39, green: 0.71, blue: 0.81, alpha: 1)
    private let gold = UIColor(red: 0.98, green: 0.73, blue: 0.38, alpha: 1)
    private let coral = UIColor(red: 0.94, green: 0.43, blue: 0.36, alpha: 1)

    private func box(_ size: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(0.006, min(size.x, min(size.y, size.z)) / 3)),
                    materials: [SimpleMaterial(color: color, roughness: 0.72, isMetallic: false)])
    }
    private func sphere(_ radius: Float, _ color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius), materials: [UnlitMaterial(color: color)])
    }
    private func asset(_ name: String, size: Float, fallback: UIColor) -> Entity {
        let holder = Entity()
        guard let model = BiomeAssetCatalog.clone(name) else {
            holder.addChild(sphere(size * 0.5, fallback)); return holder
        }
        // Tutorial assets are visual only. Imported input / collision components
        // must not intercept buttons on the attachment behind the miniature.
        func stripInput(_ entity: Entity) {
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(InputTargetComponent.self)
            for child in entity.children { stripInput(child) }
        }
        stripInput(model)
        let bounds = model.visualBounds(relativeTo: model)
        let scale = size / max(0.001, max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z)))
        model.scale *= SIMD3(repeating: scale)
        model.position -= bounds.center * scale
        holder.addChild(model)
        return holder
    }
    private func outline(width: Float, height: Float, color: UIColor) -> Entity {
        let entity = Entity()
        for side in 0..<4 {
            let bar = box(side < 2 ? [width, 0.004, 0.005] : [0.004, height, 0.005], color)
            bar.position = side < 2 ? [0, Float(side * 2 - 1) * height / 2, 0]
                : [Float((side - 2) * 2 - 1) * width / 2, 0, 0]
            entity.addChild(bar)
        }
        return entity
    }
    private func ring(_ radius: Float, color: UIColor, gap: Range<Int>? = nil) -> Entity {
        let entity = Entity()
        for i in 0..<64 {
            if let gap, gap.contains(i) { continue }
            let a = Float(i) / 64 * 2 * Float.pi
            let bar = box([0.006, radius * 0.105, 0.006], color)
            bar.position = [cos(a) * radius, sin(a) * radius, 0]
            bar.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            entity.addChild(bar)
        }
        return entity
    }
    private func add(_ entity: Entity, to parent: Entity, at position: SIMD3<Float>) {
        parent.addChild(entity); entity.position = position
    }

    func build(_ lesson: TutorialLesson) {
        for child in Array(root.children) { child.removeFromParent() }
        for container in [actor, leftHand, rightHand, hazards, props, portal, token, shield, shape, secondShape, reward] {
            for child in Array(container.children) { child.removeFromParent() }
            container.transform = .identity
            container.isEnabled = true
            container.components.set(OpacityComponent(opacity: 1))
            root.addChild(container)
        }
        walls = []; gates = []; halves = []; slots = []
        let base = box([0.73, 0.012, 0.89], UIColor(red: 0.055, green: 0.09, blue: 0.12, alpha: 1))
        add(base, to: root, at: [0, -0.15, 0])
        for x: Float in [-0.315, -0.105, 0.105, 0.315] {
            add(box([0.0015, 0.001, 0.85], blue), to: root, at: [x, -0.143, 0])
        }
        let marker = ring(0.07, color: blue)
        marker.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        add(marker, to: root, at: [0, -0.142, 0.30])
        actor.addChild(sphere(0.025, pale))
        add(box([0.033, 0.065, 0.022], pale), to: actor, at: [0, -0.052, 0])
        for x: Float in [-0.012, 0.012] {
            add(box([0.013, 0.048, 0.014], pale), to: actor, at: [x, -0.103, 0])
        }
        for hand in [leftHand, rightHand] {
            hand.addChild(box([0.020, 0.009, 0.030], pale))
            for i in 0..<4 {
                add(box([0.003, 0.005, 0.014], pale), to: hand, at: [Float(i) * 0.005 - 0.0075, 0, -0.021])
            }
        }
        portal.addChild(outline(width: 0.36, height: 0.27, color: blue))
        portal.position = [0, -0.005, -0.405]
        if let biome = lesson.biome {
            let preview = asset("preview_" + biome.rawValue, size: 0.26, fallback: blue)
            add(preview, to: portal, at: [0, 0, -0.045])
        }
        token.addChild(asset("token", size: 0.045, fallback: gold))
        reward.addChild(ring(0.045, color: gold))
        shield.addChild(ring(0.065, color: blue))
        reward.isEnabled = false
        shield.isEnabled = false

        switch lesson {
        case .space, .dodge, .emberRun, .ghostGlass, .stormPass, .pause, .modifiers:
            let wall = Entity()
            if lesson == .ghostGlass {
                let glass = box([0.19, 0.255, 0.018], blue)
                glass.components.set(OpacityComponent(opacity: 0.12))
                wall.addChild(glass)
                wall.addChild(outline(width: 0.19, height: 0.255, color: blue))
            } else { wall.addChild(box([0.19, 0.255, 0.028], coral)) }
            hazards.addChild(wall); walls.append(wall)
        case .lowCrawl:
            let wall = box([0.62, 0.14, 0.035], coral)
            hazards.addChild(wall); walls.append(wall)
        case .summitStep:
            let wall = box([0.62, 0.035, 0.035], coral)
            hazards.addChild(wall); walls.append(wall)
        case .crystalCave:
            for name in ["crystal_azure", "crystal_coral"] {
                let half = Entity()
                let normal = asset(name, size: 0.065, fallback: name == "crystal_azure" ? blue : coral)
                normal.name = "normal"
                let charged = asset(name + "_charged", size: 0.065, fallback: gold)
                charged.name = "charged"
                half.addChild(normal); half.addChild(charged)
                props.addChild(half); halves.append(half)
            }
        case .vectorFoundry:
            shape.addChild(asset("foundry_shape_cube", size: 0.06, fallback: blue))
            secondShape.addChild(asset("foundry_shape_sphere", size: 0.052, fallback: gold))
            let square = outline(width: 0.075, height: 0.075, color: blue)
            let circle = ring(0.037, color: gold)
            for (i, slot) in [square, circle].enumerated() {
                add(slot, to: props, at: [Float(i * 2 - 1) * 0.12, 0.025, -0.12]); slots.append(slot)
            }
            // Separate lintel/posts leave honest holes, rather than painting
            // slot outlines over solid panels that shapes appear to pass through.
            for side in 0..<2 {
                let panel = Entity()
                for x: Float in [-0.075, 0.075] { add(box([0.035, 0.22, 0.018], coral), to: panel, at: [x, 0, 0]) }
                for y: Float in [-0.09, 0.09] { add(box([0.16, 0.04, 0.018], coral), to: panel, at: [0, y, 0]) }
                add(panel, to: hazards, at: [Float(side * 2 - 1) * 0.12, 0.025, -0.14]); walls.append(panel)
            }
        case .orbitGate:
            let hoop = ring(0.10, color: gold)
            props.addChild(hoop); gates.append(hoop)
            // A real annular shutter with a radial opening; no solid fan drawn
            // across the center and no rotating whole-hoop proxy.
            let shutter = Entity()
            for radius: Float in [0.047, 0.057, 0.067, 0.077, 0.087, 0.097] {
                shutter.addChild(ring(radius, color: coral, gap: 0..<14))
            }
            props.addChild(shutter); gates.append(shutter)
        case .rifts, .difficulty, .modes:
            portal.isEnabled = false
            let biomes: [EnvironmentID] = [.ghostGlass, .crystalCave, .stormPass]
            for i in 0..<3 {
                let modifiers: [RiftModifier?] = lesson == .difficulty ? [.tokenSurge, .aegis, nil] : [nil, nil, nil]
                let gate = GameVisualBuilders.makeJunctionPortal(
                    option: RiftPortalOption(environment: biomes[i], risk: [.stable, .charged, .unstable][i], modifier: modifiers[i]), seed: 42)
                gate.scale = SIMD3(repeating: 0.085)
                props.addChild(gate); gates.append(gate)
            }
        case .tokens, .ready: break
        }
    }

    private func ease(_ t: Float, _ start: Float = 0, _ end: Float = 1) -> Float {
        let v = min(1, max(0, (t - start) / max(0.001, end - start)))
        return v * v * (3 - 2 * v)
    }

    func animate(lesson: TutorialLesson, step: Int, progress: Float, reduced: Bool, selectedLane: Int, modifier: RiftModifier?) {
        // Still poses cover setup, action, and result without spatial animation.
        let p: Float = reduced ? (progress < 0.28 ? 0 : progress < 0.72 ? 0.55 : 1) : progress
        let travel = ease(p, 0.12, 0.92)
        let dodge = ease(p, 0.10, 0.42)
        let collected = p >= 0.72
        actor.position = [0, -0.005, 0.28]
        actor.scale = SIMD3(repeating: 1)
        leftHand.position = [-0.052, -0.065, 0.26]
        rightHand.position = [0.052, -0.065, 0.26]
        leftHand.orientation = simd_quatf()
        rightHand.orientation = simd_quatf()
        token.isEnabled = false
        token.transform = .identity
        reward.isEnabled = false
        reward.transform = .identity
        reward.components.set(OpacityComponent(opacity: 1))
        shield.isEnabled = false
        shape.isEnabled = lesson == .vectorFoundry
        secondShape.isEnabled = lesson == .vectorFoundry
        hazards.isEnabled = true
        for wall in walls {
            wall.transform = .identity
            wall.isEnabled = true
            wall.components.set(OpacityComponent(opacity: 1))
        }
        for gate in gates { gate.isEnabled = true }

        switch lesson {
        case .space:
            actor.position.x = 0
            walls.first?.position = [0.21, -0.01, step == 0 ? -0.24 : -0.36 + travel * 0.77]
            token.isEnabled = step > 0
            token.position = [-0.21, -0.055, -0.36 + travel * 0.77]
        case .dodge, .emberRun, .ghostGlass:
            walls.first?.position = [0, -0.01, step == 0 ? -0.24 : -0.36 + travel * 0.88]
            actor.position.x = step == 0 ? 0 : -0.21 * (step == 2 ? 1 : dodge)
            if step == 2 { walls.first?.position.z = 0.12 + travel * 0.40 }
        case .tokens:
            token.isEnabled = !collected && step < 2
            token.position = [0.14, -0.045, -0.26 + ease(p, 0.05, 0.72) * 0.48]
            rightHand.position = [0.052 + ease(p, 0.20, 0.65) * 0.088, -0.045, 0.22]
            reward.isEnabled = collected && step < 2
            reward.position = token.position
            reward.scale = SIMD3(repeating: 1 + ease(p, 0.72, 1) * 0.35)
            reward.components.set(OpacityComponent(opacity: 1 - ease(p, 0.82, 1) * 0.7))
            if step == 2 { rightHand.position = [0.052, -0.065, 0.26] }
        case .pause:
            let outside: Float = step == 0 ? ease(p, 0.12, 0.48) : 1 - ease(p, 0.18, 0.55)
            actor.position.x = -0.43 * outside
            // Braking and return start at the same depth; replaying a new step
            // never advances a wall through a paused player.
            let z: Float = step == 0 ? -0.30 + ease(p, 0.05, 0.50) * 0.247 : -0.053 + ease(p, 0.55, 1) * 0.45
            walls.first?.position = [0.21, -0.01, z]
        case .rifts, .difficulty, .modes:
            let normalExample = lesson == .modes && step == 0
            let choose = (lesson == .rifts && step > 0) || normalExample
            let choice = normalExample ? 2 : selectedLane
            let arriving = (lesson == .rifts && step == 2) || normalExample
            actor.position.x = choose ? Float(choice - 1) * 0.21 * (lesson == .rifts && step == 2 ? 1 : dodge) : 0
            for (i, gate) in gates.enumerated() {
                gate.position = [Float(i - 1) * 0.21, -0.01, arriving ? -0.31 + travel * 0.76 : -0.27]
                var opacity: Float = choose && i != choice ? 0.28 : 1
                if lesson == .modes, step == 1 { gate.isEnabled = i == 1 }
                if lesson == .modes, step >= 2 { opacity = i == min(2, Int(p * 3)) ? 1 : 0.23 }
                gate.components.set(OpacityComponent(opacity: opacity))
            }
        case .lowCrawl:
            walls.first?.position = [0, 0.045, step == 0 ? -0.24 : -0.36 + travel * 0.88]
            if step > 0 {
                let crouch = ease(p, 0.12, 0.36) * (1 - ease(p, 0.90, 1))
                actor.position.y -= crouch * 0.085
                actor.scale.y = 1 - crouch * 0.45
            }
        case .summitStep:
            walls.first?.position = [0, -0.12, step == 0 ? -0.24 : -0.36 + travel * 0.88]
            if step > 0 { actor.position.y += sin(ease(p, 0.47, 0.91) * .pi) * 0.075 }
        case .stormPass:
            walls.first?.position = [ease(p, 0.15, 0.55) * 0.21, -0.01, step == 0 ? -0.24 : -0.36 + travel * 0.88]
            actor.position.x = step == 0 ? 0 : -0.21 * ease(p, 0.25, 0.55)
        case .crystalCave:
            let merge = step == 0 ? Float(0) : ease(p, 0.18, 0.72)
            for (i, half) in halves.enumerated() {
                half.findEntity(named: "normal")?.isEnabled = step != 2 || i != 0
                half.findEntity(named: "charged")?.isEnabled = step == 2 && i == 0
                half.position = [Float(i * 2 - 1) * (0.15 * (1 - merge) + 0.012), -0.03, 0.18]
                half.isEnabled = step == 0 || !collected
                half.components.set(OpacityComponent(opacity: step == 2 && i == 0 ? 1 : 0.85))
            }
            leftHand.position = [-0.15 * (1 - merge) - 0.012, -0.05, 0.20]
            rightHand.position = [0.15 * (1 - merge) + 0.012, -0.05, 0.20]
            for hand in [leftHand, rightHand] {
                for finger in hand.children.dropFirst() {
                    finger.orientation = simd_quatf(angle: 1.2 * ease(p, 0.1, 0.3), axis: [1, 0, 0])
                }
            }
            token.isEnabled = step > 0 && collected
            token.position = [0, -0.03, 0.18]
            if step == 2, let first = halves.first {
                // A steady halo distinguishes the charged half without flashing.
                shield.isEnabled = !collected
                shield.position = first.position
            }
        case .vectorFoundry:
            let fitCube = step == 0 ? Float(0) : step == 1 ? ease(p, 0.16, 0.78) : 1
            let fitSphere = step == 2 ? ease(p, 0.16, 0.78) : Float(0)
            shape.position = SIMD3<Float>(-0.24, -0.055, 0.18) * (1 - fitCube) + SIMD3<Float>(-0.12, 0.025, -0.12) * fitCube
            secondShape.position = SIMD3<Float>(0.23, -0.045, 0.16) * (1 - fitSphere) + SIMD3<Float>(0.12, 0.025, -0.12) * fitSphere
            leftHand.position = [-0.10 + fitCube * 0.045, -0.04 + fitCube * 0.03, 0.23]
            rightHand.position = [0.10 - fitSphere * 0.045, -0.04 + fitSphere * 0.03, 0.23]
            reward.isEnabled = step == 0 && collected
            reward.position = shape.position
            let open: Float = step == 2 ? ease(p, 0.80, 1) : 0
            for (i, wall) in walls.enumerated() { wall.position = [Float(i * 2 - 1) * (0.12 + open * 0.19), 0.025, -0.14] }
            for (i, slot) in slots.enumerated() { slot.position.x = Float(i * 2 - 1) * (0.12 + open * 0.19) }
            shape.position.x -= open * 0.19
            secondShape.position.x += open * 0.19
        case .orbitGate:
            guard gates.count == 2 else { break }
            gates[0].isEnabled = step == 0
            gates[1].isEnabled = step == 1
            let gate = gates[step == 0 ? 0 : 1]
            gate.position = [0, -0.005, -0.36 + travel * 0.88]
            gate.orientation = simd_quatf(angle: step == 0 ? sin(p * .pi) * 0.25 : (1 - ease(p, 0.10, 0.72)) * 1.6, axis: step == 0 ? [0, 1, 0] : [0, 0, 1])
            if step == 1 {
                actor.position.x = 0.065 * dodge
                actor.position.y += 0.045 * dodge
            }
        case .modifiers:
            hazards.isEnabled = modifier == .aegis || modifier == .closeCall
            if modifier == .aegis {
                walls.first?.position = [0, -0.01, -0.36 + ease(p, 0.10, 0.72) * 0.64]
                walls.first?.components.set(OpacityComponent(opacity: 1 - ease(p, 0.72, 0.88)))
                shield.isEnabled = !collected
                shield.position = actor.position
            } else if modifier == .closeCall {
                actor.position.x = 0.145
                leftHand.position.x = -0.022
                rightHand.position.x = 0.022
                walls.first?.position = [0, -0.01, -0.36 + travel * 0.88]
                reward.isEnabled = collected
                reward.position = actor.position
            } else if modifier != .bonusBank {
                let pickup = ease(p, 0.05, 0.72)
                token.isEnabled = !collected
                token.position = [modifier == .magnet ? 0.30 * (1 - pickup) + 0.08 * pickup : 0.14,
                                  -0.045, -0.26 + pickup * 0.48]
                rightHand.position = [modifier == .magnet ? 0.08 : 0.052 + ease(p, 0.20, 0.65) * 0.088, -0.045, 0.22]
                reward.isEnabled = collected
                reward.position = token.position
            }
        case .ready:
            token.isEnabled = true
            token.position = [0, -0.04, -0.10]
        }
        // Hands follow the body for head-movement lessons; collection and shape
        // lessons explicitly animate hands independently of the head.
        if ![.tokens, .crystalCave, .vectorFoundry].contains(lesson) {
            leftHand.position += actor.position - SIMD3<Float>(0, -0.005, 0.28)
            rightHand.position += actor.position - SIMD3<Float>(0, -0.005, 0.28)
        }
    }
}
