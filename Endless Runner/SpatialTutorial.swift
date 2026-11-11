import SwiftUI
import RealityKit
import UIKit
import AVFoundation

struct TutorialChapter: Identifiable {
    let id: Int
    let title: String
    let text: String
    let asset: String
    let seconds: Double

    static let all: [Self] = {
        var chapters: [Self] = []
        func add(_ title: String, _ text: String, _ asset: String = "token", _ seconds: Double = 9) {
            chapters.append(Self(id: chapters.count, title: title, text: text, asset: asset, seconds: seconds))
        }
        add("Find your opening", "A room. Three lanes. Endless possibilities. Follow the gold token through the rift, then discover how every world changes the game.", "rift_frame", 7)
        add("The track comes to you", "Stand at the start marker and face the rift. Lean or step left and right into open lanes. Your head and hands can hit walls. Try a small sideways lean. The miniature runner follows your head.", "wall_emberRun_0", 12)
        add("Reach for gold", "Reach into tokens with your hands to collect them. Reach toward the floating gold token to collect it in this demonstration. Your score rises with distance. Tokens have their own counter and rankings.", "token", 10)
        add("Build your bonus", "Tokens and close slips build a bonus up to +100%. It slowly drains during play. A close slip also awards score. Watch the bonus in the HUD alongside score and tokens.")
        add("Take a breath", "Move outside the play area and obstacles and music slow to a stop. Return to the start area to resume. A reminder appears in your HUD.")
        add("Choose your next world", "Normal starts in Ember Run. At a junction, three different destinations approach during a ten-second recovery. Move into the left, center, or right lane and hold it as the gates arrive. The world inside each gate shows its destination.", "rift_frame", 12)
        add("Read the diamonds", "One diamond means Stable, with 1× distance score. Two mean Charged, with 1.5×. Three mean Unstable, with 2×. Higher difficulty adds denser patterns and more reward opportunities. Each gate rolls its own difficulty.", "glyph_risk", 13)
        for modifier in RiftModifier.allCases {
            let assets: [RiftModifier: String] = [.tokenSurge: "token", .aegis: "glyph_aegis", .overdrive: "glyph_overdrive", .magnet: "glyph_magnet", .closeCall: "glyph_precision", .bonusBank: "glyph_lock"]
            add(modifier.displayName, modifier.effect + " The glyph below a portal identifies its modifier for that visit.", assets[modifier] ?? "token", 7)
        }
        add("Your active modifier", "A gate can also have no modifier. The HUD explains the active effect. Aegis shows Shield ready until it absorbs a hit, then Shield spent. Lattice Forge offers Token Surge, Aegis, Overdrive, Bonus Bank, or no modifier.", "glyph_aegis", 12)
        for biome in EnvironmentID.allCases {
            var detail = biome.mechanic
            switch biome {
            case .emberRun: detail = "Your starting world in Normal. Dodge standard walls across three lanes and reach for tokens. Clear visibility makes this the place to learn the rhythm."
            case .summitStep: detail = "Make a small rise or hop to clear low hurdles while continuing to dodge side walls. The game calibrates standing height between runs."
            case .ghostGlass: detail = "Some walls are almost transparent. Look for their edges and keep finding open lanes. These walls still collide with your head and hands."
            case .stormPass: detail += " A gust warns you before the obstacles shift sideways. Adjust to the new opening."
            case .crystalCave: detail = "Close a fist around a half-crystal. Hold one in each hand and bring DIFFERENT types together. Open your hand to drop one. Same types do not merge. Normal pairs award 5 tokens, one charged half awards 50, and two charged halves award 10,000 before modifiers."
            case .vectorFoundry: detail += " Each hand can guide its own shape. Fill every matching slot to open the approaching door. Higher difficulties can add more shapes and faster doors."
            case .orbitGate: detail += " Your head must pass through each opening. Hoops can tilt and rotate on different axes."
            default: break
            }
            add(biome.displayName, detail, "preview_" + biome.rawValue, biome == .crystalCave || biome == .vectorFoundry ? 16 : 10)
        }
        add("Normal", "Start in Ember Run and choose your route at each junction. Every destination combines a biome, difficulty, and optional modifier. Normal has separate score and token leaderboards.", "rift_frame")
        add("Loop", "Pick any one biome and play it continuously. Each Loop biome has its own score and token rankings. Browse Biomes to learn its mechanic, then choose Set up Loop.")
        add("Playlist", "Select one or more biomes. Pick the first biome or choose Random. Later visits shuffle within your selection. Removing the chosen first biome returns the start to Random. Select at least one biome to enable Start. Playlist runs are unranked.", "token", 14)
        add("Daily", "Everyone receives the same seeded biome sequence and obstacle patterns for the day. The console shows the challenge date, countdown to midnight Eastern Time, and your best score and tokens for today.", "token", 11)
        add("Preview your run", "Changing the mode or starting biome updates the live portal preview. Biomes explains all eight mechanics. Rift guide explains difficulty and modifiers. Short hints also appear when entering Lattice Forge and Gyre Gate.", "rift_frame", 11)
        add("Every run tells a story", "A collision ends the run unless Aegis absorbs it. Results show score, tokens, peak bonus, close slips, and rifts crossed. New personal bests are marked independently for score and tokens. Play again becomes available after the field clears.", "token", 12)
        add("Earn your grade", "Your grade uses peak bonus percentage + 4 per close slip + 10 per rift crossed. S begins at 150, A at 100, B at 65, and C at 30. Below 30 earns D. Build bonus, slip close, and cross rifts.", "glyph_risk", 12)
        add("Find your place", "Scores has separate Score and Tokens rankings for Normal, each Loop biome, and today's Daily. Switch between All Players and Friends. Your own rank and ranked value appear above the list. Local bests remain available while signed out.", "token", 12)
        add("Connect and share", "Sign in to Game Center from Scores, or in visionOS Settings, to load rankings and submit eligible bests. Rankings show loading, empty, or unavailable states. Share best on the Daily board opens Messages with your score and challenge date filled in.", "token", 12)
        add("Make room for your run", "Settings lets you show or hide the floor track and light-blue room grid. Both preferences persist. Hiding the track keeps the same playable boundaries. Recenter track aligns it with your current position. The privacy policy opens from Settings.", "rift_frame", 13)
        add("Your next opening", "You know the worlds, the choices, and the rewards. Return to the console to choose your mode and start. You can replay any chapter of How to play whenever you want.", "rift_frame", 8)
        return chapters
    }()
}

extension TutorialChapter {
    /// Speech, captions, and choreography advance through the same cues. The full
    /// explanation remains available from Details while the film is paused.
    var cues: [String] {
        switch title {
        case "Find your opening": return ["One room. Eight worlds. Find your opening.", "Follow the gold token. The track comes to you."]
        case "The track comes to you": return ["Stand at the start marker. Walls approach across three lanes.", "Try a small sideways lean. Your miniature follows you.", "Keep your head and hands in the opening as the wall passes."]
        case "Reach for gold": return ["Reach toward this token. Touch collects it during a run.", "Gold adds tokens and builds your score bonus.", "Your score grows with distance. Tokens have their own rankings."]
        case "Build your bonus": return ["Catch tokens and slip close to walls to build bonus.", "The meter can add up to one hundred percent to distance score.", "It gradually drains during play. Close slips also award points."]
        case "Take a breath": return ["Outside the play area, obstacles and music slow to a stop.", "Return to the start area to resume."]
        case "Choose your next world": return ["In Normal, each junction gives you three different destinations.", "Look inside the gates. Lean into the lane of your chosen world.", "Hold that lane as your gate arrives. The others peel away."]
        case "Read the diamonds": return ["One diamond is Stable, with normal distance score.", "Two are Charged, with one and a half times the score.", "Three are Unstable, with double score and denser patterns."]
        case "Token Surge": return ["Token Surge creates extra chains.", "Every token counts twice."]
        case "Aegis": return ["Aegis gives you one shield for this visit.", "A collision breaks the shield and halves your bonus.", "The HUD now says shield spent. The run continues."]
        case "Overdrive": return ["Overdrive adds twenty-five percent to distance rewards.", "Tokens and close slips build your bonus faster."]
        case "Magnet": return ["Magnet extends your pickup reach.", "Tokens and crystal halves can be collected from farther away."]
        case "Close Call": return ["Close Call gives you a wider close-slip window.", "Each close slip earns double points and bonus gain."]
        case "Bonus Bank": return ["Watch these two meters drain.", "Bonus Bank drains half as fast, preserving your score bonus."]
        case "Your active modifier": return ["The lower glyph identifies a gate's modifier. An empty position means none.", "Your HUD explains the active effect and tracks Aegis's shield.", "Forge offers Token Surge, Aegis, Overdrive, Bonus Bank, or none."]
        case "Ember Run": return ["Ember Run opens every Normal run.", "Read the walls, slip into open lanes, and catch gold."]
        case "Summit Step": return ["Summit Step adds low hurdles.", "Make a small rise or hop to clear them. Keep dodging side walls."]
        case "Low Crawl": return ["Low Crawl brings hanging barriers.", "Duck beneath them and reach for the low tokens."]
        case "Ghost Glass": return ["Ghost Glass makes some walls almost transparent.", "Follow their faint edges. They still collide with your head and hands."]
        case "Storm Pass": return ["A gust warns you before the obstacles move.", "Watch the opening shift sideways, then adjust your lane."]
        case "Crystal Cave": return ["Close your fists around two different crystal halves. Bring them together for five tokens.", "Same types stay separate.", "Open your hand to release a half.", "Each hand holds one half. Pick different types to merge.", "A rare charged half raises the pair to fifty tokens.", "Two charged halves award ten thousand before modifiers."]
        case "Lattice Forge": return ["Aim a raised hand at a floating shape. Hold briefly to lock on.", "Move your hand to guide it into the matching slot. Try the final cube.", "Each hand can guide a shape. Fill every slot to open the door.", "Higher difficulty adds shapes and can make the door approach faster."]
        case "Gyre Gate": return ["Guide your head through each hoop.", "Some hoops tilt. Watch their openings as they approach.", "Time the rotating shutter so your head passes through its open wedge."]
        case "Normal": return ["Normal begins in Ember Run and branches at every junction.", "Choose your next biome, difficulty, and modifier by moving into a lane."]
        case "Loop": return ["Loop stays in one biome. Choose any of the eight.", "Every Loop biome has separate score and token rankings."]
        case "Playlist": return ["Build a Playlist from one or more biomes. Later visits shuffle within your selection.", "Choose the first biome or leave it Random.", "Remove that first biome and the start returns to Random. Empty playlists cannot start.", "Playlist runs are unranked."]
        case "Daily": return ["Daily gives everyone the same route and obstacle patterns.", "Check today's date, bests, and the countdown to midnight Eastern Time."]
        case "Preview your run": return ["Your starting portal updates as you choose a mode or biome.", "Biomes explains each mechanic. Rift guide explains the gates.", "Forge and Gyre also show short hints during your run."]
        case "Every run tells a story": return ["A collision ends your run unless Aegis absorbs it.", "Review score, tokens, peak bonus, close slips, and rifts crossed.", "Score and token personal bests are independent. Play again when the field clears."]
        case "Earn your grade": return ["Peak bonus plus four per close slip plus ten per rift gives your grade.", "S starts at one hundred fifty. A at one hundred. B at sixty-five. C at thirty.", "Below thirty earns D. Every close slip and rift counts."]
        case "Find your place": return ["Choose Normal, a Loop biome, or today's Daily leaderboard.", "Switch Score or Tokens, and All Players or Friends. Your rank appears above the list.", "Loading, empty, and unavailable states explain missing rankings. Local bests remain while signed out."]
        case "Connect and share": return ["Sign in to Game Center from Scores or visionOS Settings to compete.", "Share your Daily best to open Messages with the score and date filled in."]
        case "Make room for your run": return ["Toggle the floor track and room grid in Settings. Both choices are saved.", "Hiding the track keeps the same play boundaries.", "Recenter aligns the track with you. The privacy policy also opens from Settings."]
        default: return ["The next opening is yours.", "Start Normal, choose a mode, or replay any chapter whenever you like."]
        }
    }
}

struct TutorialTracking {
    var head: SIMD3<Float>?
    var hands: [SIMD3<Float>?] = [nil, nil]
}

@MainActor
final class SpatialTutorial: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var index = 0
    @Published var paused = false {
        didSet {
            if paused { speaker.pauseSpeaking(at: .immediate); audio.pause() }
            else if speaker.isPaused { speaker.continueSpeaking() }
            else if active { speak() }
        }
    }
    @Published var progress: Double = 0
    @Published private(set) var cueIndex = 0
    @Published private(set) var sceneRevision = 0
    @Published var interaction = ""
    @Published var narration = true {
        didSet {
            expectedUtterance = nil
            speaker.stopSpeaking(at: .immediate)
            spokenCue = -1
            speechFinished = !narration
            if narration && !paused { speak() }
        }
    }
    @Published private(set) var demonstrationBeat = 0
    let root = Entity()
    let controls = Entity()
    let theater = TutorialTheater()
    var reduceMotion = false
    private let speaker = AVSpeechSynthesizer()
    private let audio = TutorialAudio()
    private var tokenDeparture: SIMD3<Float>?
    private var openingSurface: SIMD3<Float>?
    private var expectedUtterance: AVSpeechUtterance?
    private var spokenCue = -1
    private var speechFinished = false
    private var cueElapsed: Double = 0
    override init() {
        super.init()
        speaker.delegate = self
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.expectedUtterance === utterance else { return }
            self.speechFinished = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.expectedUtterance === utterance else { return }
            self.speechFinished = true
        }
    }
    private var elapsed: Double = 0
    private var renderedIndex = -1
    private var reportedProgress = -1
    private var originHead: SIMD3<Float>?
    private var handLock: SIMD3<Float>?
    private var shapeStart = SIMD3<Float>.zero
    private var aimTime: Double = 0
    private var lastHandTime: Double = 0
    private var lockedHandIndex: Int?
    private var transition: Entity?
    private var transitionTime: Double = 0
    private var succeeded = false
    private var playerSteering = false
    private var trackingInterrupted = false
    private var gateCommitted = false
    private var forgeDemonstrating = false
    private var active = false
    var chapter: TutorialChapter { TutorialChapter.all[index] }
    var caption: String { chapter.cues[cueIndex] }
    private var cueDuration: Double {
        max(chapter.seconds / Double(chapter.cues.count), Double(caption.split(separator: " ").count) / 2.5 + 0.6)
    }

    func mount(in parent: Entity, panel: Entity?) {
        if root.parent !== parent {
            parent.addChild(root)
            root.addChild(theater.root)
            parent.addChild(controls)
        }
        if let panel, panel.parent !== controls { controls.addChild(panel) }
    }

    func begin(head: SIMD3<Float>?, surface: SIMD3<Float>?) {
        active = false
        originHead = head
        let position = head ?? SIMD3<Float>(0, 1.5, 0)
        root.position = position + [0, -0.16, -1.1]
        openingSurface = surface.map { root.convert(position: $0, from: root.parent) }
        controls.position = position + [0, -0.62, -1.3]
        seek(0)
        active = true
        paused = false
    }

    func stop() {
        transition?.removeFromParent()
        transition = nil
        active = false
        audio.stop()
        expectedUtterance = nil
        speaker.stopSpeaking(at: .immediate)
    }

    func seek(_ newIndex: Int) {
        expectedUtterance = nil
        speaker.stopSpeaking(at: .immediate)
        index = min(max(0, newIndex), TutorialChapter.all.count - 1)
        elapsed = 0
        cueElapsed = 0
        cueIndex = 0
        spokenCue = -1
        speechFinished = !narration
        progress = 0
        reportedProgress = -1
        interaction = ""
        renderedIndex = -1
        handLock = nil
        lockedHandIndex = nil
        aimTime = 0
        succeeded = false
        playerSteering = false
        trackingInterrupted = false
        gateCommitted = false
        forgeDemonstrating = false
        demonstrationBeat = 0
    }

    private func speak() {
        guard narration, active, renderedIndex == index, spokenCue != cueIndex else { return }
        spokenCue = cueIndex
        speechFinished = false
        let utterance = AVSpeechUtterance(string: caption)
        utterance.rate = 0.47
        expectedUtterance = utterance
        speaker.speak(utterance)
    }

    func tap(_ entity: Entity) {
        guard !paused else { return }
        var candidate: Entity? = entity
        while let target = candidate {
            if target.name == "tutorialToken", chapter.title == "Reach for gold" { reward("Token collected. Reach into tokens during a run."); return }
            if target.name == "tutorialRunner" {
                playerSteering = true
                theater.selectedLane = (theater.selectedLane + 1) % 3
                interaction = "Your head position selects the lane in a run."
                return
            }
            candidate = target.parent
        }
    }

    private func reward(_ message: String) {
        guard !succeeded else { return }
        succeeded = true
        interaction = message
        GameSFX.shared.playCoinCollect()
    }

    func tick(_ delta: Double, tracking: TutorialTracking) {
        guard active else { return }
        if renderedIndex != index {
            tokenDeparture = theater.token.parent == nil ? nil : theater.token.position(relativeTo: root)
            transition?.removeFromParent()
            if !reduceMotion, !theater.root.children.isEmpty {
                let outgoing = theater.root.clone(recursive: true)
                func removeInput(_ entity: Entity) {
                    entity.components.remove(InputTargetComponent.self)
                    entity.components.remove(CollisionComponent.self)
                    for child in entity.children { removeInput(child) }
                }
                removeInput(outgoing)
                outgoing.findEntity(named: "tutorialToken")?.removeFromParent()
                root.addChild(outgoing)
                transition = outgoing
                transitionTime = 0
            }
            theater.build(chapter)
            audio.setBiome(EnvironmentID.allCases.first { $0.displayName == chapter.title } ?? .emberRun)
            renderedIndex = index
            sceneRevision += 1
            if paused { audio.pause() }
            if !paused { speak() }
            GameSFX.shared.playJunctionOpen()
        }
        guard !paused else { return }
        let dt = min(delta, 0.1)
        elapsed += dt
        if let transition {
            transitionTime += dt
            let fade = Float(min(1, transitionTime / 0.6))
            transition.components.set(OpacityComponent(opacity: 1 - fade))
            if fade >= 1 { transition.removeFromParent(); self.transition = nil }
        }
        cueElapsed += dt
        let cueProgress = min(1, cueElapsed / cueDuration)
        let p = (Double(cueIndex) + cueProgress) / Double(chapter.cues.count)
        let step = Int(p * 50)
        if step != reportedProgress { progress = p; reportedProgress = step }
        let beat = min(3, Int(p * 4))
        if beat != demonstrationBeat {
            demonstrationBeat = beat
            if chapter.title == "Storm Pass" { GameSFX.shared.playWindWhoosh() }
            else if chapter.title == "Aegis", beat == 2 { GameSFX.shared.playShieldBreak() }
            else if ["The track comes to you", "Close Call"].contains(chapter.title), beat == 2 { GameSFX.shared.playNearMiss() }
        }
        if originHead == nil, let head = tracking.head { originHead = head }
        let headDelta = tracking.head.flatMap { head in originHead.map { head - $0 } }
        if chapter.title == "The track comes to you" || chapter.title == "Choose your next world" {
            if let headDelta, !gateCommitted {
                if abs(headDelta.x) > 0.06 { playerSteering = true }
                if playerSteering {
                    theater.selectedLane = headDelta.x < -0.06 ? 0 : headDelta.x > 0.06 ? 2 : 1
                    if chapter.title == "The track comes to you", theater.selectedLane != 1 {
                        reward("Opening found. Keep your head and hands in the clear lane.")
                    }
                }
            }
            if chapter.title == "Choose your next world", p >= 0.82, !gateCommitted {
                gateCommitted = true
                interaction = ["Left", "Center", "Right"][theater.selectedLane] + " rift selected."
                GameSFX.shared.playJunctionCommit(risk: .stable, laneIndex: theater.selectedLane)
            }
        }
        let localHands = tracking.hands.map { hand in hand.map { root.convert(position: $0, from: root.parent) } }
        if chapter.title == "Reach for gold", !succeeded {
            if localHands.compactMap({ $0 }).contains(where: { distance($0, theater.token.position) < 0.11 }) {
                reward("Caught! Your token count and score bonus increase.")
            }
        }
        if chapter.title == "Lattice Forge", !succeeded, !forgeDemonstrating {
            let headLocal = tracking.head.map { root.convert(position: $0, from: root.parent) }
            let candidateIndex = lockedHandIndex ?? localHands.indices.filter { localHands[$0] != nil }.max { a, b in
                guard let headLocal, let left = localHands[a], let right = localHands[b] else { return false }
                let target = normalize(theater.shape.position - headLocal)
                let leftDirection = left - headLocal
                let rightDirection = right - headLocal
                guard length(leftDirection) > 0.1 else { return true }
                guard length(rightDirection) > 0.1 else { return false }
                return dot(normalize(leftDirection), target) < dot(normalize(rightDirection), target)
            }
            if let headLocal, let candidateIndex, localHands.indices.contains(candidateIndex), let hand = localHands[candidateIndex] {
                if trackingInterrupted, handLock != nil {
                    handLock = hand
                    shapeStart = theater.shape.position
                }
                trackingInterrupted = false
                lastHandTime = elapsed
                let direction = hand - headLocal
                let target = theater.shape.position - headLocal
                let aligned = length(direction) > 0.1 && dot(normalize(direction), normalize(target)) > 0.96
                if handLock == nil {
                    aimTime = aligned ? aimTime + dt : 0
                    if aimTime > 0.3 {
                        handLock = hand
                        lockedHandIndex = candidateIndex
                        shapeStart = theater.shape.position
                        interaction = "Locked. Move your hand to guide the shape into the glowing slot."
                    }
                }
                if let handLock {
                    var desired = shapeStart + (hand - handLock) * 2.5
                    desired.x = min(0.38, max(-0.38, desired.x))
                    desired.y = min(0.25, max(-0.15, desired.y))
                    desired.z = theater.slot.position.z
                    theater.shape.position += (desired - theater.shape.position) * min(1, Float(dt) * 10)
                    if distance(theater.shape.position, theater.slot.position) < 0.07 {
                        reward("Perfect fit. Filling every slot opens the door.")
                    }
                }
            } else {
                trackingInterrupted = true
                if elapsed - lastHandTime > 2 {
                    handLock = nil
                    lockedHandIndex = nil
                    aimTime = 0
                }
            }
        }
        // Complete a watchable example after the invitation, even if a player
        // acquired a shape but left it outside the slot.
        if chapter.title == "Lattice Forge", cueIndex >= 2, !succeeded {
            if !forgeDemonstrating {
                forgeDemonstrating = true
                handLock = nil
                theater.beginForgeDemonstration()
                interaction = "Watch the final shape settle into its matching slot."
            }
        }
        theater.animate(time: Float(elapsed), progress: Float(p), reduced: reduceMotion,
                        interactive: handLock != nil, succeeded: succeeded, steering: playerSteering)
        if index == 0, let openingSurface, p < 0.5, !reduceMotion {
            let u = Float(p * 2)
            let smooth = u * u * (3 - 2 * u)
            let destination = SIMD3<Float>(0, 0, -0.53)
            var position = openingSurface * (1 - smooth) + destination * smooth
            position.y += sin(u * .pi) * 0.12
            theater.token.setPosition(position, relativeTo: root)
        }
        if index > 0, let departure = tokenDeparture, elapsed < 0.6, !reduceMotion {
            let u = Float(elapsed / 0.6)
            let ease = u * u * (3 - 2 * u)
            let destination = theater.token.position(relativeTo: root)
            var position = departure * (1 - ease) + destination * ease
            position.y += sin(u * .pi) * 0.06
            theater.token.setPosition(position, relativeTo: root)
        }
        var audioFlow: Float = 1
        if chapter.title == "Take a breath" {
            audioFlow = p < 0.3 ? Float(max(0, 1 - p / 0.3)) : p < 0.65 ? 0 : Float(min(1, (p - 0.65) / 0.2))
        }
        audio.tick(delta: Float(dt), flow: audioFlow, speaking: narration && speaker.isSpeaking)
        if cueProgress >= 1 && (!narration || speechFinished) {
            if cueIndex + 1 < chapter.cues.count {
                cueIndex += 1
                cueElapsed = 0
                speak()
            } else if index + 1 < TutorialChapter.all.count {
                seek(index + 1)
            } else {
                UserDefaults.standard.set(true, forKey: "tutorial.completed.v2")
                paused = true
            }
        }
    }

    func remove() { stop(); root.removeFromParent(); controls.removeFromParent() }
}

struct TutorialControls: View {
    @State private var details = false
    @ObservedObject var tutorial: SpatialTutorial
    let close: () -> Void
    let startNormal: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOW TO PLAY").font(.caption.monospaced()).foregroundStyle(SlipframeStyle.ice)
                Spacer()
                Toggle("Narration", isOn: $tutorial.narration).toggleStyle(.button)
                Button("Done", action: close).buttonStyle(ConsoleButtonStyle())
            }
            Text(tutorial.chapter.title).font(.system(size: 27, weight: .semibold))
            Text(tutorial.caption)
                .font(.system(size: 21, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            if !tutorial.interaction.isEmpty {
                Text(tutorial.interaction).foregroundStyle(SlipframeStyle.ice)
            }
            DisclosureGroup("Full explanation", isExpanded: $details) {
                ScrollView { Text(tutorial.chapter.text).font(.system(size: 16)) }.frame(height: 110)
            }
            .onChange(of: details) { _, expanded in
                if expanded { tutorial.paused = true }
            }
            .onChange(of: tutorial.index) { _, _ in details = false }
            if tutorial.index == TutorialChapter.all.count - 1 {
                HStack {
                    Button("Start Normal", action: startNormal).buttonStyle(ConsoleButtonStyle(prominent: true))
                    Button("Choose a mode", action: close).buttonStyle(ConsoleButtonStyle())
                    Button("Replay from beginning") { tutorial.seek(0); tutorial.paused = false }
                        .buttonStyle(ConsoleButtonStyle())
                }
            }
            ScrollView {
                TutorialExamplePanel(tutorial: tutorial)
            }
            .frame(height: 180)
            ProgressView(value: tutorial.progress).tint(SlipframeStyle.ice)
            HStack {
                Button("Previous") { tutorial.seek(tutorial.index - 1) }.disabled(tutorial.index == 0)
                Button(tutorial.paused ? "Resume" : "Pause") { tutorial.paused.toggle() }
                Button("Replay") { tutorial.seek(tutorial.index); tutorial.paused = false }
                Button("Next") { tutorial.seek(tutorial.index + 1) }.disabled(tutorial.index == TutorialChapter.all.count - 1)
            }.buttonStyle(ConsoleButtonStyle())
            ScrollView(.horizontal) {
                HStack {
                    ForEach(TutorialChapter.all) { chapter in
                        Button(chapter.title) { tutorial.seek(chapter.id) }
                            .buttonStyle(ConsoleButtonStyle(selected: chapter.id == tutorial.index))
                    }
                }
            }
        }
        .padding(20).frame(width: 620)
        .foregroundStyle(.white)
        .background(SlipframeStyle.ink, in: RoundedRectangle(cornerRadius: 22))
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 22))
    }
}

/// A deterministic miniature stage. Seeking reconstructs a chapter without leaving
/// particles, interactions, or animation callbacks from the previous chapter alive.
@MainActor
final class TutorialTheater {
    let root = Entity()
    let token = Entity()
    let shape = Entity()
    let slot = Entity()
    private let runner = Entity()
    private let portal = Entity()
    private let track = Entity()
    private let props = Entity()
    private let shield = Entity()
    private let glow = Entity()
    private let room = Entity()
    private let demoHands = Entity()
    private let burst = Entity()
    private var walls: [Entity] = []
    private var pickups: [Entity] = []
    private var gates: [Entity] = []
    private var halves: [Entity] = []
    private var bonusBars: [Entity] = []
    private var title = ""
    private var recenterStarted: Float?
    private var currentTime: Float = 0
    private var previewDestinations: [EnvironmentID] = []
    private var forgeDemoStart: SIMD3<Float>?
    var selectedLane = 1

    private func box(_ size: SIMD3<Float>, _ color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
    }

    private func asset(_ name: String, size: Float, color: UIColor = .systemCyan) -> Entity {
        let holder = Entity()
        let model = BiomeAssetCatalog.clone(name) ?? box([size, size, size], color)
        let bounds = model.visualBounds(relativeTo: model)
        let scale = size / max(0.001, max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z)))
        model.scale = SIMD3(repeating: scale)
        model.position = -bounds.center * scale
        holder.addChild(model)
        return holder
    }

    private func ring(radius: Float, color: UIColor, gap: Int = 0) -> Entity {
        let ring = Entity()
        for i in gap..<48 {
            let a = Float(i) / 48 * 2 * Float.pi
            let bar = box([0.008, radius * 0.14, 0.008], color)
            bar.position = [cos(a) * radius, sin(a) * radius, 0]
            bar.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            ring.addChild(bar)
        }
        return ring
    }

    private func destinationWindow(_ biome: EnvironmentID, risk: RiftRisk, modifier: RiftModifier?) -> Entity {
        let window = GameVisualBuilders.makeJunctionPortal(
            option: RiftPortalOption(environment: biome, risk: risk, modifier: modifier), seed: 42
        )
        window.scale = SIMD3(repeating: 0.12)
        return window
    }

    private func interactive(_ entity: Entity, name: String) {
        entity.name = name
        entity.generateCollisionShapes(recursive: true)
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
    }

    func build(_ chapter: TutorialChapter) {
        root.transform = .identity
        for child in root.children { child.removeFromParent() }
        for container in [token, shape, slot, runner, portal, track, props, shield, glow, room, demoHands, burst] {
            for child in container.children { child.removeFromParent() }
            container.transform = .identity
            container.isEnabled = true
            container.components.set(OpacityComponent(opacity: 1))
            root.addChild(container)
        }
        walls = []; pickups = []; gates = []; halves = []; bonusBars = []
        title = chapter.title
        recenterStarted = nil
        forgeDemoStart = nil
        previewDestinations = []
        for i in -4...4 {
            let horizontal = box([0.9, 0.002, 0.002], .systemCyan)
            horizontal.position = [0, Float(i) * 0.1, -0.55]
            room.addChild(horizontal)
            let vertical = box([0.002, 0.8, 0.002], .systemCyan)
            vertical.position = [Float(i) * 0.1, 0, -0.55]
            room.addChild(vertical)
        }
        room.components.set(OpacityComponent(opacity: 0.13))
        for i in 0..<2 {
            let hand = Entity()
            hand.addChild(box([0.04, 0.015, 0.055], .systemCyan))
            for finger in 0..<4 {
                let part = box([0.007, 0.008, 0.035], .systemCyan)
                part.position = [Float(finger) * 0.01 - 0.015, 0, -0.04]
                hand.addChild(part)
            }
            hand.position = [Float(i * 2 - 1) * 0.2, -0.04, 0.22]
            demoHands.addChild(hand)
        }
        for i in 0..<16 {
            let shard = asset("fx_shard", size: 0.012, color: .systemYellow)
            shard.name = "spark_" + String(i)
            burst.addChild(shard)
        }
        burst.isEnabled = false
        if title == "Find your opening" {
            let blocker = box([0.025, 0.15, 0.025], .systemRed)
            blocker.name = "hookBlocker"
            blocker.position = [-0.16, 0.03, -0.2]
            props.addChild(blocker)
        }
        demoHands.isEnabled = ["Reach for gold", "Crystal Cave", "Lattice Forge", "Magnet"].contains(title)
        selectedLane = 1
        for lane in -1...1 {
            let rail = box([0.003, 0.003, 0.85], .systemCyan)
            rail.position = [Float(lane) * 0.19, -0.21, 0]
            track.addChild(rail)
        }
        let pad = asset("start_pad", size: 0.18)
        pad.position = [0, -0.21, 0.3]
        track.addChild(pad)
        runner.addChild(ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [UnlitMaterial(color: .white)]))
        let torso = box([0.027, 0.06, 0.018], .systemCyan)
        torso.position.y = -0.046
        runner.addChild(torso)
        interactive(runner, name: "tutorialRunner")
        portal.addChild(asset("rift_frame", size: 0.37))
        portal.position = [0, 0.01, -0.43]
        portal.addChild(ring(radius: 0.145, color: .systemCyan))
        token.addChild(asset("token", size: 0.07, color: .systemYellow))
        interactive(token, name: "tutorialToken")
        token.position = [0.18, 0, 0.32]
        glow.addChild(ring(radius: 0.06, color: .systemYellow))
        glow.isEnabled = false
        shield.addChild(ring(radius: 0.065, color: .systemMint))
        shield.isEnabled = false

        let biome = EnvironmentID.allCases.first { $0.displayName == title }
        if let biome {
            // Preview meshes retain their authored landscape composition.
            let scenery = asset("preview_" + biome.rawValue, size: 0.36)
            scenery.position = [0, 0.03, -0.46]
            portal.addChild(scenery)
            if biome == .crystalCave {
                for (i, name) in ["crystal_azure", "crystal_coral"].enumerated() {
                    let half = Entity()
                    let normal = asset(name, size: 0.11)
                    normal.name = "normal"
                    half.addChild(normal)
                    let charged = asset(name + "_charged", size: 0.11)
                    charged.name = "charged"
                    charged.isEnabled = false
                    half.addChild(charged)
                    let matching = asset("crystal_azure", size: 0.11)
                    matching.name = "matching"
                    matching.isEnabled = false
                    half.addChild(matching)
                    half.position = [Float(i * 2 - 1) * 0.19, 0, 0]
                    props.addChild(half); halves.append(half)
                }
            } else if biome == .vectorFoundry {
                shape.addChild(asset("foundry_shape_cube", size: 0.075))
                shape.position = [-0.23, 0.02, 0.2]
                for side in 0..<4 {
                    let edge = box(side < 2 ? [0.09, 0.006, 0.006] : [0.006, 0.09, 0.006], .systemMint)
                    edge.position = side < 2 ? [0, Float(side * 2 - 1) * 0.045, 0] : [Float((side - 2) * 2 - 1) * 0.045, 0, 0]
                    slot.addChild(edge)
                }
                slot.position = [0.17, 0.1, 0.2]
                let secondSlot = ring(radius: 0.045, color: .systemCyan)
                secondSlot.position = [-0.17, 0.1, 0.2]
                props.addChild(secondSlot)
                let secondShape = asset("foundry_shape_sphere", size: 0.06)
                secondShape.name = "secondShape"
                props.addChild(secondShape)
                for x in [Float(-0.16), 0.16] {
                    let panel = asset("foundry_door_panel", size: 0.28)
                    panel.position = [x, 0, -0.1]
                    props.addChild(panel); walls.append(panel)
                }
            } else if biome == .orbitGate {
                for i in 0..<3 {
                    let hoop = ring(radius: 0.1, color: .systemOrange)
                    if i == 2 {
                        var vertices: [SIMD3<Float>] = [[0, 0, 0]]
                        for segment in 12...48 {
                            let angle = Float(segment) / 48 * 2 * Float.pi
                            vertices.append([cos(angle) * 0.095, sin(angle) * 0.095, 0])
                        }
                        var indices: [UInt32] = []
                        for triangle in 1..<(vertices.count - 1) {
                            let n = UInt32(triangle)
                            indices += [0, n, n + 1, 0, n + 1, n]
                        }
                        var descriptor = MeshDescriptor(name: "Tutorial shutter")
                        descriptor.positions = MeshBuffers.Positions(vertices)
                        descriptor.primitives = .triangles(indices)
                        if let mesh = try? MeshResource.generate(from: [descriptor]) {
                            hoop.addChild(ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .systemOrange)]))
                        }
                    }
                    hoop.position = [0, -0.07, -Float(i) * 0.23]
                    props.addChild(hoop); gates.append(hoop)
                }
            }
        }
        let isWallScene = ["The track comes to you", "Ember Run", "Summit Step", "Low Crawl", "Ghost Glass", "Storm Pass", "Take a breath", "Aegis", "Close Call", "Every run tells a story"].contains(title)
        if isWallScene {
            for i in 0..<3 {
                let name = title == "Summit Step" ? "hazard_jump" : title == "Low Crawl" ? "hazard_duck" : "wall_" + (biome?.rawValue ?? "emberRun") + "_0"
                let wall = asset(name, size: title == "Low Crawl" || title == "Summit Step" ? 0.4 : 0.19, color: .systemRed)
                wall.position = [Float(i % 2) * 0.19, title == "Low Crawl" ? -0.08 : title == "Summit Step" ? -0.195 : -0.12, -Float(i) * 0.3]
                if title == "Ghost Glass" { wall.components.set(OpacityComponent(opacity: 0.12)) }
                props.addChild(wall); walls.append(wall)
            }
        }
        if ["Choose your next world", "Read the diamonds", "Normal", "Loop", "Playlist", "Daily", "Preview your run"].contains(title) {
            for i in 0..<3 {
                let gate = Entity()
                gate.position = [Float(i - 1) * 0.25, 0.02, -0.1]
                let biome: EnvironmentID = [.emberRun, .crystalCave, .stormPass][i]
                let preview = destinationWindow(biome, risk: [.stable, .charged, .unstable][i],
                                                modifier: ([.tokenSurge, .aegis, nil] as [RiftModifier?])[i])
                preview.name = "destination"
                gate.addChild(preview)
                if title == "Read the diamonds" {
                    for row in 0..<(i + 1) * 2 {
                        let hazard = box([0.028, 0.05, 0.015], [.systemMint, .systemOrange, .systemRed][i])
                        hazard.position = [Float(row % 2) * 0.045 - 0.023, -0.15, Float(row) * 0.037]
                        gate.addChild(hazard)
                    }
                }
                props.addChild(gate); gates.append(gate)
            }
            portal.isEnabled = false
        }
        if ["Token Surge", "Magnet", "Overdrive", "Bonus Bank", "Build your bonus"].contains(title) {
            for i in 0..<5 {
                let pickup = asset("token", size: 0.045)
                pickup.position = [0.19, -0.1, -Float(i) * 0.15]
                props.addChild(pickup); pickups.append(pickup)
            }
        }
        if ["Bonus Bank", "Overdrive", "Build your bonus", "Aegis"].contains(title) {
            for i in 0..<2 {
                let bar = box([0.25, 0.015, 0.012], i == 0 ? .white : .systemCyan)
                bar.position = [0.32, 0.16 - Float(i) * 0.04, 0]
                props.addChild(bar)
                bonusBars.append(bar)
            }
        }
        if let modifier = RiftModifier.allCases.first(where: { $0.displayName == title }) {
            let glyph = asset(chapter.asset, size: 0.11)
            glyph.position = [-0.38, 0.13, 0]
            props.addChild(glyph)
            shield.isEnabled = modifier == .aegis
        }
    }

    func setModePreview(_ mode: PlayModeKind, selection: Set<EnvironmentID>, start: EnvironmentID?) {
        var destinations: [EnvironmentID]
        switch mode {
        case .normal: destinations = [.emberRun, .crystalCave, .stormPass]
        case .solo: destinations = [start ?? selection.first ?? .emberRun]
        case .playlist:
            destinations = EnvironmentID.allCases.filter { selection.contains($0) }
            if let start, let index = destinations.firstIndex(of: start) {
                destinations.remove(at: index)
                destinations.insert(start, at: 0)
            }
        case .daily: destinations = DailyChallenge.previewSequence(dayKey: DailyChallenge.dayKey(), count: 3)
        }
        guard destinations != previewDestinations else { return }
        previewDestinations = destinations
        for (i, gate) in gates.enumerated() {
            gate.isEnabled = i < destinations.count
            guard i < destinations.count else { continue }
            gate.children.first(where: { $0.name == "destination" })?.removeFromParent()
            let preview = destinationWindow(destinations[i], risk: .stable, modifier: nil)
            preview.name = "destination"
            gate.addChild(preview)
        }
    }

    func previewRecenter() { recenterStarted = currentTime }

    func beginForgeDemonstration() { forgeDemoStart = shape.position }

    func showTrack(_ visible: Bool) { track.isEnabled = visible }
    func showGrid(_ visible: Bool) { room.isEnabled = visible }

    private func ease(_ value: Float) -> Float {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    private func interval(_ p: Float, _ start: Float, _ end: Float) -> Float {
        ease((p - start) / max(0.001, end - start))
    }

    func animate(time: Float, progress: Float, reduced: Bool, interactive: Bool, succeeded: Bool, steering: Bool) {
        currentTime = time
        if let recenterStarted {
            root.position.x = reduced ? 0 : 0.15 * (1 - interval(time - recenterStarted, 0, 0.8))
        }
        let p = min(1, progress)
        // Reduced Motion still teaches every state, with discrete pose changes.
        let t = reduced ? min(1, floor(p * 6) / 6) : p
        root.components.set(OpacityComponent(opacity: reduced ? 1 : ease(time / 0.6)))
        root.scale = SIMD3(repeating: title == "The track comes to you" && !reduced ? 1 + 0.12 * sin(t * .pi) : 1)
        token.isEnabled = true
        token.scale = SIMD3(repeating: 1)
        token.position = [0.19, -0.1, 0.26]
        token.orientation = simd_quatf(angle: reduced ? 0 : t * 2 * .pi, axis: [0, 1, 0])
        let dodge = interval(t, 0.2, 0.4)
        let targetX = steering ? Float(selectedLane - 1) * 0.19 : -0.19 * dodge
        let smoothX = runner.position.x + (targetX - runner.position.x) * (reduced ? 1 : 0.18)
        runner.position = [smoothX, -0.1, 0.29]
        glow.isEnabled = succeeded
        glow.position = title == "Lattice Forge" ? slot.position : token.position
        glow.scale = SIMD3(repeating: 1)
        shield.position = runner.position
        for (i, wall) in walls.enumerated() {
            let u = interval(t, 0.12 + Float(i) * 0.17, 0.55 + Float(i) * 0.17)
            wall.position.z = -0.45 + u * 0.9
            wall.components.set(OpacityComponent(opacity: title == "Ghost Glass" ? 0.12 : 1 - interval(u, 0.9, 1)))
            if title == "The track comes to you" {
                // Either outer lane is a valid first dodge.
                wall.position.x = 0
            }
            if title == "Storm Pass" { wall.position.x = 0.19 * interval(t, 0.24, 0.52) }
            if title == "Take a breath" {
                let travel: Float = t < 0.3 ? t : t < 0.65 ? 0.3 : t - 0.35
                wall.position.z = -0.4 + travel * 0.9 - Float(i) * 0.18
                runner.position.x = 0.36 * (interval(t, 0.16, 0.3) - interval(t, 0.65, 0.8))
            }
            if title == "Aegis" {
                wall.position.x = runner.position.x
                wall.scale = SIMD3(repeating: max(0.001, 1 - interval(t, 0.48, 0.65)))
                wall.position.z = -0.45 + min(0.74, t * 1.5)
            }
            if title == "Every run tells a story" {
                runner.position.x = 0
                wall.position.z = min(0.29, -0.45 + t * 2.4)
                wall.position.y = -0.12 - interval(t, 0.35, 0.7) * 0.3
                wall.scale.y = max(0.001, 1 - interval(t, 0.35, 0.7))
            }
        }
        if title == "Aegis" { shield.isEnabled = p < 0.5 }
        if title == "Summit Step" { runner.position = [0, -0.1 + sin(interval(t, 0.25, 0.65) * .pi) * 0.13, 0.29] }
        if title == "Low Crawl" { runner.position = [0, -0.1 - sin(interval(t, 0.25, 0.65) * .pi) * 0.06, 0.29] }
        if title == "Close Call" { runner.position.x = 0.12; glow.isEnabled = p > 0.5; glow.position = runner.position }
        for (i, pickup) in pickups.enumerated() {
            let u = interval(t, Float(i) * 0.1, 0.48 + Float(i) * 0.1)
            pickup.position = [title == "Magnet" ? 0.35 * (1 - u) : 0.19, -0.1, -0.4 + u * 0.69]
            pickup.scale = SIMD3(repeating: max(0.001, 1 - interval(u, 0.85, 1)))
        }
        for (i, bar) in bonusBars.enumerated() {
            let amount: Float
            switch title {
            case "Bonus Bank": amount = 1 - p * (i == 0 ? 1 : 0.5)
            case "Aegis": amount = p < 0.5 ? 0.8 : 0.4
            case "Overdrive": amount = p * (i == 0 ? 0.75 : 0.9375)
            default: amount = p < 0.65 ? 0.2 + p : 0.85 - (p - 0.65) * 0.4
            }
            bar.scale.x = max(0.001, min(1, amount))
            bar.position.x = 0.2 + 0.125 * amount
        }
        for (i, gate) in gates.enumerated() {
            if title == "Gyre Gate" {
                let segment = min(2, Int(p * 3))
                let local = p * 3 - Float(segment)
                gate.isEnabled = i == segment
                let u = interval(reduced ? floor(local * 3) / 3 : local, 0.05, 0.95)
                gate.position.z = -0.45 + u * 0.9
                // Keep the first opening head-on, tilt the next hoop, then
                // bring the shutter wedge to the runner at the crossing.
                let angle = i == 2 ? (1 - u) * .pi : i == 1 ? sin(u * .pi * 2) * 0.55 : 0
                gate.orientation = simd_quatf(angle: angle, axis: i == 2 ? [0, 0, 1] : [0, 1, 0])
                runner.position.x = i == 2 ? 0.045 : 0
                runner.position.y = i == 2 ? -0.025 : -0.07
            } else {
                let chosen = title == "Loop" ? 0 : steering ? selectedLane : 1
                let commitment = interval(t, 0.65, 0.9)
                gate.position.x = Float(i - 1) * 0.25
                gate.scale = SIMD3(repeating: i == chosen ? 1 : 1 - commitment * 0.35)
                if title == "Choose your next world" {
                    gate.position.z = -0.35 + t * 0.75
                    if i != chosen { gate.position.x += Float(i < chosen ? -1 : 1) * commitment * 0.3 }
                    token.position = [Float(chosen - 1) * 0.25, 0, -0.35 + t * 0.75]
                }
            }
        }
        for (i, half) in halves.enumerated() {
            let phase = min(5, Int(p * 6))
            let local = (p * 6) - Float(phase)
            let merge = interval(local, 0.15, 0.75)
            let sameType = phase == 1
            let dropping = phase == 2
            half.children.first(where: { $0.name == "normal" })?.isEnabled = !sameType && phase < 4
            half.children.first(where: { $0.name == "matching" })?.isEnabled = sameType
            half.children.first(where: { $0.name == "charged" })?.isEnabled = phase >= 4 && (i == 0 || phase == 5)
            if phase == 4 && i == 1 { half.children.first(where: { $0.name == "normal" })?.isEnabled = true }
            half.position = [Float(i * 2 - 1) * (sameType ? max(0.06, 0.2 * (1 - merge)) : 0.2 * (1 - merge)), dropping ? -merge * 0.17 : 0, 0.08]
            let vanish = sameType ? Float(0) : interval(local, 0.75, 0.9)
            half.scale = SIMD3(repeating: max(0.001, 1 - vanish))
            token.isEnabled = !sameType && !dropping && local > 0.75
            token.position = [0, 0, 0.08]
            glow.isEnabled = token.isEnabled
            glow.position = token.position
        }
        for (i, hand) in demoHands.children.enumerated() {
            if title == "Crystal Cave" {
                let phase = min(5, Int(p * 6))
                let local = p * 6 - Float(phase)
                let opening = phase == 2
                for finger in hand.children.dropFirst() {
                    finger.orientation = simd_quatf(angle: opening ? 0 : 1.2, axis: [1, 0, 0])
                }
                let separation = phase == 1 ? max(0.06, 0.2 * (1 - interval(local, 0.15, 0.75))) : 0.2 * (1 - interval(local, 0.15, 0.75))
                hand.position = [Float(i * 2 - 1) * separation, -0.04, 0.12]
            } else if title == "Lattice Forge" {
                hand.position = [-0.23 + interval(t, 0.55, 0.8) * 0.4, -0.05, 0.32]
            } else {
                hand.position = [0.16, -0.1, 0.9 - interval(t, 0.5, 0.8) * 0.25]
            }
        }
        if title == "Lattice Forge" {
            if let second = props.children.first(where: { $0.name == "secondShape" }) {
                let u = interval(t, 0.05, 0.22)
                second.position = [-0.17, -0.1 + u * 0.2, 0.2]
            }
            if !interactive && !succeeded {
                let u = interval(t, 0.5, 0.72)
                let from = forgeDemoStart ?? SIMD3<Float>(-0.23, 0.02, 0.2)
                shape.position = from * (1 - u) + slot.position * u
            }
            if succeeded { shape.position = slot.position }
            let opening = succeeded ? Float(1) : interval(t, 0.8, 0.95)
            for (i, wall) in walls.enumerated() {
                wall.position = [Float(i * 2 - 1) * (0.16 + opening * 0.15), 0, -0.1]
                wall.components.set(OpacityComponent(opacity: 1))
            }
            glow.isEnabled = interactive || succeeded || t > 0.8
            glow.position = shape.position
        }
        let sparkTime = interval(t, 0.5, 0.72)
        burst.isEnabled = ["Aegis", "Close Call", "Crystal Cave", "Reach for gold"].contains(title) && sparkTime > 0 && sparkTime < 1
        burst.position = title == "Aegis" || title == "Close Call" ? runner.position : token.position
        for (i, shard) in burst.children.enumerated() {
            let angle = Float(i) / 16 * 2 * Float.pi
            shard.position = [cos(angle) * sparkTime * 0.1, sin(angle) * sparkTime * 0.1, 0]
            shard.scale = SIMD3(repeating: max(0.001, 1 - sparkTime))
        }
        if title == "Find your opening" {
            let u = interval(t, 0, 0.5)
            token.position = [-0.4 + u * 0.4, sin(u * .pi) * 0.15, -0.53 * u]
            portal.scale = SIMD3(repeating: max(0.001, interval(t, 0.3, 0.7)))
            track.scale.z = max(0.001, interval(t, 0.55, 0.85))
            room.components.set(OpacityComponent(opacity: 0.13 + sin(t * .pi) * 0.2))
        } else if title == "Reach for gold" {
            token.position = [0.16, -0.1, 0.65]
            let caught = succeeded ? Float(1) : interval(t, 0.8, 0.95)
            token.scale = SIMD3(repeating: max(0.001, 1 - caught))
            glow.isEnabled = caught > 0
            glow.position = token.position
        } else if title == "Your next opening" {
            let u = interval(t, 0.1, 0.8)
            token.position = [0.19 * (1 - u), -0.1 + u * 0.23, 0.26 - u * 0.69]
            portal.scale = SIMD3(repeating: 1 + u * 0.15)
        }
    }

}

/// Interactive examples share the console's labels and styling. Their draft values
/// belong to this view, so following the film cannot submit a score or change a run.
struct TutorialExamplePanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var tutorial: SpatialTutorial
    @State private var mode = PlayModeKind.normal
    @State private var selected: Set<EnvironmentID> = [.emberRun, .crystalCave]
    @State private var start: EnvironmentID?
    @State private var metric = LeaderboardMetric.score
    @State private var audience = LeaderboardAudience.allPlayers
    @State private var board = LeaderboardBoard.normal
    @State private var floor = true
    @State private var grid = true
    @State private var message = ""
    @State private var userEditedExample = false

    private var title: String { tutorial.chapter.title }
    private var beat: Int { tutorial.demonstrationBeat }
    private let modeChapters = ["Normal", "Loop", "Playlist", "Daily", "Preview your run"]

    var body: some View {
        Group {
            if modeChapters.contains(title) {
                modeExample
            } else if title == "Every run tells a story" || title == "Earn your grade" {
                resultsExample
            } else if title == "Find your place" || title == "Connect and share" {
                rankingExample
            } else if title == "Make room for your run" {
                settingsExample
            } else if title == "Your next opening" {
                Text("Choose Done to return to your run setup, or select a chapter below to explore again.")
                    .foregroundStyle(SlipframeStyle.ice)
            } else {
                feedbackExample
            }
        }
        .font(.system(size: 14))
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: beat)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: tutorial.sceneRevision) { _, _ in
            floor = true
            grid = true
            if modeChapters.contains(title) { updatePreview() }
        }
        .onChange(of: tutorial.index) { _, _ in
            message = ""
            userEditedExample = false
            if let value = PlayModeKind.allCases.first(where: { $0.title == title }) { mode = value }
        }
        .onChange(of: mode) { _, _ in updatePreview() }
        .onChange(of: selected) { _, _ in updatePreview() }
        .onChange(of: start) { _, _ in updatePreview() }
        .onChange(of: tutorial.cueIndex) { _, cue in
            guard !userEditedExample else { return }
            switch title {
            case "Playlist":
                if cue == 0 { selected = [.emberRun, .crystalCave, .stormPass]; start = nil }
                if cue == 1 { start = .crystalCave }
                if cue == 2 { selected.remove(.crystalCave); start = nil }
            case "Loop": selected = [.crystalCave]; start = .crystalCave
            case "Find your place":
                if cue == 0 { board = .loop(.crystalCave) }
                if cue == 1 { metric = .coins; audience = .friends }
            case "Connect and share":
                if cue == 1 { message = DailyScoreShare.message(score: 1240) }
            case "Make room for your run":
                if cue == 0 { grid = false }
                if cue == 1 { floor = false }
                if cue == 2 { tutorial.theater.previewRecenter() }
            default: break
            }
            if modeChapters.contains(title) { updatePreview() }
        }
    }

    private func updatePreview() {
        tutorial.theater.setModePreview(mode, selection: selected, start: start)
    }

    private var feedbackExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 25) {
                ConsoleMetric(title: "Example score", value: "\(120 + beat * (title == "Overdrive" ? 25 : 20))", size: 20)
                ConsoleMetric(title: "Tokens", value: "\(beat * (title == "Token Surge" ? 2 : 1))", color: SlipframeStyle.amber, size: 20)
                ConsoleMetric(title: "Bonus", value: "+\(bonus)%", color: SlipframeStyle.ice, size: 20)
            }
            Text(beatCaption).foregroundStyle(SlipframeStyle.ice)
        }
        .accessibilityElement(children: .combine)
    }

    private var bonus: Int {
        if title == "Aegis" { return beat < 2 ? 80 : 40 }
        if title == "Bonus Bank" { return 80 - beat * 2 }
        if title == "Build your bonus" {
            let p = tutorial.progress
            return p < 0.65 ? min(100, Int(20 + p * 125)) : max(0, 100 - Int((p - 0.65) * 40))
        }
        return min(100, 20 + beat * 25)
    }

    private var beatCaption: String {
        switch title {
        case "Aegis", "Your active modifier": return beat < 2 ? "Aegis · Shield ready" : "Aegis · Shield spent · Bonus halved"
        case "Magnet": return "The token curves into the wider pickup area."
        case "Bonus Bank": return "Normal bonus drain is twice as fast as Bonus Bank."
        case "Overdrive": return "Distance rewards ×1.25 · Faster bonus gains"
        case "Token Surge": return "Each collected token counts twice."
        case "Close Call": return "Wider close-slip window · Double close-slip rewards"
        case "Take a breath": return beat == 1 || beat == 2 ? "Return to the start area to resume" : "Inside the play area · Moving"
        case "Read the diamonds": return ["◆ Stable · ×1", "◆ ◆ Charged · ×1.5", "◆ ◆ ◆ Unstable · ×2"][min(2, tutorial.cueIndex)]
        case "Crystal Cave": return tutorial.caption
        case "Lattice Forge": return tutorial.interaction.isEmpty ? "Aim a raised hand at the cube. Hold briefly to lock, then move toward the slot." : tutorial.interaction
        case "Gyre Gate": return "Watch the gap. Guide your head through the opening as it reaches you."
        case "Ghost Glass": return "Follow the faint edges. Transparent walls still collide."
        case "Storm Pass": return "A gust warns you. Watch the obstacle shift, then correct your lane."
        default: return tutorial.interaction.isEmpty ? "Watch the demonstration, or try the movement when invited." : tutorial.interaction
        }
    }

    private var modeExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(PlayModeKind.allCases) { option in
                    Button(option.title) { userEditedExample = true; mode = option }
                        .buttonStyle(ConsoleButtonStyle(selected: mode == option))
                }
            }
            if mode == .playlist || mode == .solo {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(EnvironmentID.allCases) { biome in
                            Button(biome.displayName) {
                                userEditedExample = true
                                if mode == .solo { selected = [biome]; start = biome }
                                else if selected.contains(biome) {
                                    selected.remove(biome)
                                    if start == biome { start = nil }
                                } else { selected.insert(biome) }
                            }.buttonStyle(ConsoleButtonStyle(selected: selected.contains(biome)))
                        }
                    }
                }
                if mode == .playlist {
                    HStack {
                        Text("First biome")
                        Button(start?.displayName ?? "Random") {
                            userEditedExample = true
                            let ordered = EnvironmentID.allCases.filter { selected.contains($0) }
                            if let start, let index = ordered.firstIndex(of: start), index + 1 < ordered.count {
                                self.start = ordered[index + 1]
                            } else { start = start == nil ? ordered.first : nil }
                        }.buttonStyle(ConsoleButtonStyle())
                        Text(selected.isEmpty ? "Select a biome to enable Start" : "Unranked · \(selected.count) biomes")
                    }
                }
                Button("Start · Example") { message = "Ready. Choose Done to set up your own run." }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(selected.isEmpty)
                if !message.isEmpty { Text(message) }
            } else if mode == .daily {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(DailyChallenge.displayDate(for: context.date)) · Resets in \(DailyChallenge.formatCountdown(DailyChallenge.secondsUntilRollover(from: context.date))) · Midnight ET")
                            .monospacedDigit()
                        let sequence = DailyChallenge.previewSequence(dayKey: DailyChallenge.dayKey(for: context.date), count: 3)
                        ForEach(["Your route", "Everyone's route"], id: \.self) { player in
                            HStack {
                                Text(player).frame(width: 120, alignment: .leading)
                                ForEach(Array(sequence.enumerated()), id: \.offset) { _, biome in
                                    Text(biome.displayName).foregroundStyle(biome.interfaceTint)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Ember Run → Choose one of three rifts → Choose again at the next junction")
            }
        }
    }

    private var resultsExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                ConsoleMetric(title: "Example score", value: "1,240", color: SlipframeStyle.ice, size: 24)
                ConsoleMetric(title: "Tokens", value: "42", color: SlipframeStyle.amber, size: 24)
                ConsoleMetric(title: "Grade", value: "S", size: 24)
            }
            HStack(spacing: 20) {
                ConsoleMetric(title: "Peak bonus", value: "100%", size: 18)
                ConsoleMetric(title: "Close slips", value: "5", size: 18)
                ConsoleMetric(title: "Rifts crossed", value: "3", size: 18)
            }
            Text("100 + 5 × 4 + 3 × 10 = 150 → S")
            Text("D below 30 · C 30 · B 65 · A 100 · S 150")
                .foregroundStyle(SlipframeStyle.muted)
            Text(beat < 2 ? "New personal best · Score" : "New personal best · Tokens")
                .foregroundStyle(SlipframeStyle.ice)
            Button("Play again · Example") { message = "Choose Done to set up your own run." }
                .buttonStyle(ConsoleButtonStyle(prominent: true))
                .disabled(tutorial.progress < 0.7)
            if !message.isEmpty { Text(message) }
        }
    }

    private var rankingExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(LeaderboardMetric.allCases) { value in
                    Button(value.title) { userEditedExample = true; metric = value }.buttonStyle(ConsoleButtonStyle(selected: metric == value))
                }
                ForEach(LeaderboardAudience.allCases) { value in
                    Button(value.title) { userEditedExample = true; audience = value }.buttonStyle(ConsoleButtonStyle(selected: audience == value))
                }
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(LeaderboardBoard.browseable()) { option in
                        Button(option.chipTitle) { userEditedExample = true; board = option }
                            .buttonStyle(ConsoleButtonStyle(selected: board == option))
                    }
                }
            }
            Text("Example \(board.title) ranking · Your rank #8 · \(metric == .score ? "1,240 points" : "42 tokens")")
            if title == "Connect and share" {
                Button("Preview Daily message") { message = DailyScoreShare.message(score: 1240) }
                    .buttonStyle(ConsoleButtonStyle())
                if !message.isEmpty { Text(message).foregroundStyle(SlipframeStyle.ice) }
            } else {
                Text(["Loading rankings…", "No ranked friends yet.", "Rankings are currently unavailable.", "Signed out · Your local bests are saved."][beat])
                    .foregroundStyle(SlipframeStyle.muted)
            }
        }
    }

    private var settingsExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Floor track", isOn: $floor)
                Toggle("Room grid", isOn: $grid)
            }
            Text(floor ? "Track visible · Play boundary active" : "Track hidden · Play boundary active")
            HStack {
                Button("Preview recenter") { tutorial.theater.previewRecenter(); message = "Recenter aligns the track with your current position between runs." }
                    .buttonStyle(ConsoleButtonStyle())
                Link("Privacy policy", destination: SlipframeLinks.privacyPolicy)
                    .buttonStyle(ConsoleButtonStyle())
            }
            if !message.isEmpty { Text(message).foregroundStyle(SlipframeStyle.ice) }
        }
        .onChange(of: floor) { _, visible in tutorial.theater.showTrack(visible) }
        .onChange(of: grid) { _, visible in tutorial.theater.showGrid(visible) }
    }
}

@MainActor
private final class TutorialAudio {
    private var current: AVAudioPlayer?
    private var outgoing: AVAudioPlayer?
    private var cue: String?
    private var fade: Float = 1

    func setBiome(_ biome: EnvironmentID) {
        guard cue != biome.musicCue else { return }
        cue = biome.musicCue
        guard let url = Bundle.main.url(forResource: biome.musicCue, withExtension: "m4a", subdirectory: "Music")
                ?? Bundle.main.url(forResource: biome.musicCue, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        outgoing?.stop()
        outgoing = current
        current = player
        player.enableRate = true
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        fade = 0
    }

    func tick(delta: Float, flow: Float, speaking: Bool) {
        fade = min(1, fade + delta / 0.8)
        let volume: Float = speaking ? 0.055 : 0.13
        current?.volume = volume * flow * fade
        outgoing?.volume = volume * flow * (1 - fade)
        for player in [current, outgoing].compactMap({ $0 }) {
            player.rate = max(0.5, flow)
            if flow < 0.01 { player.pause() }
            else if !player.isPlaying { player.play() }
        }
        if fade >= 1 { outgoing?.stop(); outgoing = nil }
    }

    func pause() { current?.pause(); outgoing?.pause() }
    func stop() {
        current?.stop()
        outgoing?.stop()
        current = nil
        outgoing = nil
        cue = nil
    }
}
