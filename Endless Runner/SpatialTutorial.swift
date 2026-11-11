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

struct TutorialTracking {
    var head: SIMD3<Float>?
    var hands: [SIMD3<Float>] = []
}

@MainActor
final class SpatialTutorial: ObservableObject {
    @Published var index = 0
    @Published var paused = false {
        didSet {
            if paused { speaker.pauseSpeaking(at: .immediate) }
            else if speaker.isPaused { speaker.continueSpeaking() }
            else if active { speak() }
        }
    }
    @Published var progress: Double = 0
    @Published var interaction = ""
    @Published var narration = true {
        didSet {
            speaker.stopSpeaking(at: .immediate)
            if narration && !paused { speak() }
        }
    }
    @Published private(set) var demonstrationBeat = 0
    let root = Entity()
    let controls = Entity()
    let theater = TutorialTheater()
    var reduceMotion = false
    private let speaker = AVSpeechSynthesizer()
    private var elapsed: Double = 0
    private var renderedIndex = -1
    private var reportedProgress = -1
    private var originHead: SIMD3<Float>?
    private var handLock: SIMD3<Float>?
    private var shapeStart = SIMD3<Float>.zero
    private var aimTime: Double = 0
    private var lastHandTime: Double = 0
    private var succeeded = false
    private var active = false
    var chapter: TutorialChapter { TutorialChapter.all[index] }
    var duration: Double { max(chapter.seconds, Double(chapter.text.split(separator: " ").count) / 2.3 + 2) }

    func mount(in parent: Entity, panel: Entity?) {
        if root.parent !== parent {
            parent.addChild(root)
            root.addChild(theater.root)
            parent.addChild(controls)
        }
        if let panel, panel.parent !== controls { controls.addChild(panel) }
    }

    func begin(head: SIMD3<Float>?) {
        active = true
        originHead = head
        let position = head ?? SIMD3<Float>(0, 1.5, 0)
        root.position = position + [0, -0.16, -1.1]
        controls.position = position + [0, -0.62, -1.3]
        paused = false
        seek(0)
    }

    func stop() {
        active = false
        speaker.stopSpeaking(at: .immediate)
    }

    func seek(_ newIndex: Int) {
        speaker.stopSpeaking(at: .immediate)
        index = min(max(0, newIndex), TutorialChapter.all.count - 1)
        elapsed = 0
        progress = 0
        reportedProgress = -1
        interaction = ""
        renderedIndex = -1
        handLock = nil
        aimTime = 0
        succeeded = false
        demonstrationBeat = 0
    }

    private func speak() {
        guard narration, active else { return }
        let utterance = AVSpeechUtterance(string: chapter.title + ". " + chapter.text)
        utterance.rate = 0.47
        speaker.speak(utterance)
    }

    func tap(_ entity: Entity) {
        guard !paused else { return }
        var candidate: Entity? = entity
        while let target = candidate {
            if target.name == "tutorialToken" { reward("Token collected. Reach into tokens during a run."); return }
            if target.name == "tutorialRunner" {
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
            theater.build(chapter)
            renderedIndex = index
            if !paused { speak() }
            GameSFX.shared.playJunctionOpen()
        }
        guard !paused else { return }
        let dt = min(delta, 0.1)
        elapsed += dt
        let p = min(1, elapsed / duration)
        let step = Int(p * 50)
        if step != reportedProgress { progress = p; reportedProgress = step }
        let beat = min(3, Int(p * 4))
        if beat != demonstrationBeat {
            demonstrationBeat = beat
            if chapter.title == "Storm Pass" { GameSFX.shared.playWindWhoosh() }
            else if chapter.title == "Aegis", beat == 2 { GameSFX.shared.playShieldBreak() }
            else { GameSFX.shared.playNearMiss() }
        }
        if originHead == nil, let head = tracking.head { originHead = head }
        let headDelta = tracking.head.flatMap { head in originHead.map { head - $0 } }
        if chapter.title == "The track comes to you" || chapter.title == "Choose your next world" {
            if let headDelta, abs(headDelta.x) > 0.06 {
                theater.selectedLane = headDelta.x < 0 ? 0 : 2
                reward("Opening found. Hold your lane as the wall passes.")
            }
        }
        let localHands = tracking.hands.map { root.convert(position: $0, from: root.parent) }
        if chapter.title == "Reach for gold", !succeeded {
            if localHands.contains(where: { distance($0, theater.token.position) < 0.11 }) {
                reward("Caught! Your token count and score bonus increase.")
            }
        }
        if chapter.title == "Lattice Forge", !succeeded {
            let headLocal = tracking.head.map { root.convert(position: $0, from: root.parent) }
            if let headLocal, let hand = localHands.first {
                lastHandTime = elapsed
                let direction = hand - headLocal
                let target = theater.shape.position - headLocal
                let aligned = length(direction) > 0.1 && dot(normalize(direction), normalize(target)) > 0.96
                if handLock == nil {
                    aimTime = aligned ? aimTime + dt : 0
                    if aimTime > 0.3 {
                        handLock = hand
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
            } else if elapsed - lastHandTime > 0.5 {
                handLock = nil
                aimTime = 0
            }
        }
        theater.animate(time: Float(elapsed), progress: Float(p), reduced: reduceMotion,
                        interactive: handLock != nil, succeeded: succeeded)
        if p >= 1 && (!narration || !speaker.isSpeaking) {
            if index + 1 < TutorialChapter.all.count { seek(index + 1) }
            else { paused = true }
        }
    }

    func remove() { stop(); root.removeFromParent(); controls.removeFromParent() }
}

struct TutorialControls: View {
    @ObservedObject var tutorial: SpatialTutorial
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOW TO PLAY").font(.caption.monospaced()).foregroundStyle(SlipframeStyle.ice)
                Spacer()
                Toggle("Narration", isOn: $tutorial.narration).toggleStyle(.button)
                Button("Done", action: close).buttonStyle(ConsoleButtonStyle())
            }
            Text(tutorial.chapter.title).font(.system(size: 27, weight: .semibold))
            ScrollView {
                Text(tutorial.chapter.text).font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
                if !tutorial.interaction.isEmpty { Text(tutorial.interaction).foregroundStyle(SlipframeStyle.ice).padding(.top, 8) }
            }.frame(height: 112)
            TutorialExamplePanel(tutorial: tutorial)
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
    private var walls: [Entity] = []
    private var pickups: [Entity] = []
    private var gates: [Entity] = []
    private var halves: [Entity] = []
    private var bonusBars: [Entity] = []
    private var title = ""
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

    private func interactive(_ entity: Entity, name: String) {
        entity.name = name
        entity.generateCollisionShapes(recursive: true)
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
    }

    func build(_ chapter: TutorialChapter) {
        for child in root.children { child.removeFromParent() }
        for container in [token, shape, slot, runner, portal, track, props, shield, glow, room, demoHands] {
            for child in container.children { child.removeFromParent() }
            container.transform = .identity
            container.isEnabled = true
            container.components.set(OpacityComponent(opacity: 1))
            root.addChild(container)
        }
        walls = []; pickups = []; gates = []; halves = []; bonusBars = []
        title = chapter.title
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
                    let half = asset(name, size: 0.11)
                    half.position = [Float(i * 2 - 1) * 0.19, 0, 0]
                    props.addChild(half); halves.append(half)
                }
            } else if biome == .vectorFoundry {
                shape.addChild(asset("foundry_shape_cube", size: 0.075))
                shape.position = [-0.23, 0.02, 0.2]
                slot.addChild(ring(radius: 0.055, color: .systemMint))
                slot.position = [0.17, 0.1, 0.2]
                for x in [Float(-0.16), 0.16] {
                    let panel = asset("foundry_door_panel", size: 0.28)
                    panel.position = [x, 0, -0.1]
                    props.addChild(panel); walls.append(panel)
                }
            } else if biome == .orbitGate {
                for i in 0..<3 {
                    let hoop = ring(radius: 0.1, color: .systemOrange, gap: i == 2 ? 12 : 0)
                    hoop.position = [0, -0.07, -Float(i) * 0.23]
                    props.addChild(hoop); gates.append(hoop)
                }
            }
        }
        let isWallScene = ["The track comes to you", "Ember Run", "Summit Step", "Low Crawl", "Ghost Glass", "Storm Pass", "Take a breath", "Aegis", "Close Call", "Every run tells a story"].contains(title)
        if isWallScene {
            for i in 0..<3 {
                let name = title == "Summit Step" ? "hazard_jump" : title == "Low Crawl" ? "hazard_duck" : "wall_emberRun_0"
                let wall = asset(name, size: title == "Low Crawl" || title == "Summit Step" ? 0.4 : 0.19, color: .systemRed)
                wall.position = [Float(i % 2) * 0.19, title == "Low Crawl" ? 0.03 : -0.12, -Float(i) * 0.3]
                if title == "Ghost Glass" { wall.components.set(OpacityComponent(opacity: 0.12)) }
                props.addChild(wall); walls.append(wall)
            }
        }
        if ["Choose your next world", "Read the diamonds", "Normal", "Loop", "Playlist", "Daily"].contains(title) {
            for i in 0..<3 {
                let gate = asset("junction_frame", size: 0.22)
                gate.position = [Float(i - 1) * 0.25, 0.02, -0.1]
                let preview = asset("preview_" + ["emberRun", "crystalCave", "stormPass"][i], size: 0.15)
                gate.addChild(preview)
                for d in 0...i {
                    let diamond = asset("glyph_risk", size: 0.021)
                    diamond.position = [Float(d) * 0.028 - Float(i) * 0.014, 0.14, 0]
                    gate.addChild(diamond)
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

    func showTrack(_ visible: Bool) { track.isEnabled = visible }
    func showGrid(_ visible: Bool) { room.isEnabled = visible }

    func animate(time: Float, progress: Float, reduced: Bool, interactive: Bool, succeeded: Bool) {
        let p = progress
        let cycle = time.truncatingRemainder(dividingBy: 5) / 5
        let motion = reduced ? Float(0.5) : cycle
        root.components.set(OpacityComponent(opacity: reduced ? 1 : min(1, time * 2)))
        for (i, hand) in demoHands.children.enumerated() {
            let direction = Float(i * 2 - 1)
            if title == "Crystal Cave" {
                hand.position.x = direction * max(0.015, 0.22 - motion * 0.44)
                hand.position.z = 0.04
            } else if title == "Lattice Forge" {
                hand.position.x = -0.18 + min(1, max(0, (p - 0.5) * 3)) * 0.35
            } else {
                hand.position.z = 0.4 - motion * 0.3
            }
        }
        if title == "Reach for gold", p > 0.8, !succeeded {
            glow.isEnabled = true
            token.scale = SIMD3(repeating: max(0.01, (1 - p) * 5))
        }
        let autoLane = Int(time / 2.5) % 3
        let lane = succeeded ? selectedLane : autoLane
        runner.position = [Float(lane - 1) * 0.19, -0.1, 0.29]
        token.orientation = simd_quatf(angle: reduced ? 0 : time, axis: [0, 1, 0])
        token.isEnabled = !succeeded
        glow.isEnabled = succeeded
        glow.position = title == "Lattice Forge" ? slot.position : token.position
        glow.scale = SIMD3(repeating: reduced ? 1 : 1 + 0.15 * sin(time * 5))
        for (i, wall) in walls.enumerated() {
            if title == "Lattice Forge" {
                wall.position.x = Float(i * 2 - 1) * (succeeded || p > 0.8 ? 0.3 : 0.16)
            } else {
                let travel = (motion + Float(i) * 0.33).truncatingRemainder(dividingBy: 1)
                wall.position.z = -0.45 + travel * 0.9
                if title == "Storm Pass" { wall.position.x = sin(motion * .pi * 2) * 0.22 }
                if title == "Take a breath", p > 0.3 && p < 0.65 { wall.position.z = -0.1 - Float(i) * 0.2; runner.position.x = 0.37 }
                if title == "Aegis", p > 0.5 { wall.scale = SIMD3(repeating: max(0.01, 1 - (p - 0.5) * 3)) }
                if title == "Every run tells a story", p > 0.3 {
                    wall.position.y = -0.12 - (p - 0.3) * 0.4
                    wall.scale.y = max(0.01, 1 - (p - 0.3) * 2)
                }
            }
        }
        for (i, bar) in bonusBars.enumerated() {
            let amount: Float
            switch title {
            case "Bonus Bank": amount = max(0.05, 1 - p * (i == 0 ? 1 : 0.5))
            case "Aegis": amount = p < 0.5 ? 0.8 : 0.4
            case "Overdrive": amount = min(1, p * (i == 0 ? 1 : 1.25))
            default: amount = min(1, 0.2 + p)
            }
            bar.scale.x = max(0.01, amount)
            bar.position.x = 0.2 + 0.125 * amount
        }
        shield.position = runner.position
        if title == "Aegis" { shield.isEnabled = p < 0.5 }
        if title == "Summit Step" { runner.position.y += max(0, sin(motion * .pi * 2)) * 0.12 }
        if title == "Low Crawl" { runner.position.y -= max(0, sin(motion * .pi * 2)) * 0.06 }
        if title == "Close Call" { runner.position.x = 0.12 }
        for (i, pickup) in pickups.enumerated() {
            let u = (motion + Float(i) * 0.18).truncatingRemainder(dividingBy: 1)
            pickup.position.z = -0.4 + u * 0.8
            pickup.position.x = title == "Magnet" ? 0.3 * (1 - u) : 0.19
            pickup.scale = SIMD3(repeating: u > 0.85 ? max(0.01, (1 - u) / 0.15) : 1)
        }
        for (i, gate) in gates.enumerated() {
            if title == "Gyre Gate" {
                gate.position.z = -0.4 + (motion + Float(i) / 3).truncatingRemainder(dividingBy: 1) * 0.8
                gate.orientation = simd_quatf(angle: reduced ? 0.5 : time, axis: i == 2 ? [0, 0, 1] : [0, 1, 0])
            } else {
                let chosen = title == "Loop" ? 1 : autoLane
                gate.scale = SIMD3(repeating: i == chosen ? 1.08 : 0.8)
                if title == "Choose your next world" { gate.position.z = -0.35 + p * 0.7 }
            }
        }
        for (i, half) in halves.enumerated() {
            half.position.x = Float(i * 2 - 1) * max(0, 0.22 - motion * 0.44)
            half.scale = SIMD3(repeating: motion > 0.65 ? 0.01 : 1)
            if motion > 0.65 { token.isEnabled = true; token.position = [0, 0, 0] }
        }
        if title == "Lattice Forge", !interactive {
            let u = max(0, min(1, (p - 0.5) * 3))
            shape.position = SIMD3<Float>(-0.23, 0.02, 0.2) * (1 - u) + slot.position * u
        }
        if title == "Find your opening" {
            let u = min(1, p * 2)
            token.position = [-0.4 + u * 0.4, 0.2 * sin(u * .pi), -0.43 * u]
            portal.scale = SIMD3(repeating: reduced ? 1 : max(0.01, (p - 0.25) / 0.5))
            track.scale.z = reduced ? 1 : max(0.01, min(1, (p - 0.5) * 3))
        } else if title == "Reach for gold" {
            // Forward of the miniature, inside easy reach relative to the launch pose.
            token.position = [0.16, -0.1, 0.65]
        } else if title == "Your next opening" {
            token.position = [0.14 * (1 - p), 0.02, -0.43 * p]
            portal.scale = SIMD3(repeating: 1 + (reduced ? 0 : p * 0.3))
        }
    }
}

/// Interactive examples share the console's labels and styling. Their draft values
/// belong to this view, so following the film cannot submit a score or change a run.
struct TutorialExamplePanel: View {
    @ObservedObject var tutorial: SpatialTutorial
    @State private var mode = PlayModeKind.normal
    @State private var selected: Set<EnvironmentID> = [.emberRun, .crystalCave]
    @State private var start: EnvironmentID?
    @State private var metric = LeaderboardMetric.score
    @State private var audience = LeaderboardAudience.allPlayers
    @State private var floor = true
    @State private var grid = true
    @State private var message = ""

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: tutorial.index) { _, _ in
            message = ""
            if let value = PlayModeKind.allCases.first(where: { $0.title == title }) { mode = value }
        }
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
        case "Read the diamonds": return ["◆ Stable · ×1", "◆ ◆ Charged · ×1.5", "◆ ◆ ◆ Unstable · ×2", "Choose the pattern density that suits you."][beat]
        case "Crystal Cave": return ["Close each hand around a different half.", "Bring the two halves together.", "A normal pair awards 5 tokens.", "Charged pairs award 50 or 10,000 tokens."][beat]
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
                    Button(option.title) { mode = option }
                        .buttonStyle(ConsoleButtonStyle(selected: mode == option))
                }
            }
            if mode == .playlist || mode == .solo {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(EnvironmentID.allCases) { biome in
                            Button(biome.displayName) {
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
                            let ordered = EnvironmentID.allCases.filter { selected.contains($0) }
                            if let start, let index = ordered.firstIndex(of: start), index + 1 < ordered.count {
                                self.start = ordered[index + 1]
                            } else { start = start == nil ? ordered.first : nil }
                        }.buttonStyle(ConsoleButtonStyle())
                        Text(selected.isEmpty ? "Select a biome to enable Start" : "Unranked · \(selected.count) biomes")
                    }
                }
            } else if mode == .daily {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(DailyChallenge.displayDate(for: context.date)) · Resets in \(DailyChallenge.formatCountdown(DailyChallenge.secondsUntilRollover(from: context.date))) · Midnight ET")
                        .monospacedDigit()
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
            Text("Peak bonus 100% + 5 close slips × 4 + 3 rifts × 10 = 150 → S")
            Text(beat < 2 ? "New personal best · Score and tokens" : "Track clear · Play again is available")
                .foregroundStyle(SlipframeStyle.ice)
        }
    }

    private var rankingExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(LeaderboardMetric.allCases) { value in
                    Button(value.title) { metric = value }.buttonStyle(ConsoleButtonStyle(selected: metric == value))
                }
                ForEach(LeaderboardAudience.allCases) { value in
                    Button(value.title) { audience = value }.buttonStyle(ConsoleButtonStyle(selected: audience == value))
                }
            }
            Text("Example Daily ranking · Your rank #8 · \(metric == .score ? "1,240 points" : "42 tokens")")
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
                Button("Preview recenter") { message = "Recenter aligns the track with your current position between runs." }
                    .buttonStyle(ConsoleButtonStyle())
                Text("Privacy policy opens from Settings.")
            }
            if !message.isEmpty { Text(message).foregroundStyle(SlipframeStyle.ice) }
        }
        .onChange(of: floor) { _, visible in tutorial.theater.showTrack(visible) }
        .onChange(of: grid) { _, visible in tutorial.theater.showGrid(visible) }
    }
}
