import SwiftUI

/// The herbarium page: plants pressed so far, the missing ones sketched in pencil, and the months.
/// Plants that came and were not pressed yet are pressed here when the page opens, with a small
/// landing (the one chosen in the moment first).
struct HerbariumView: View {
    @Environment(Vault.self) private var vault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The plant chosen with "Press into the herbarium", to land first.
    @Binding var landing: String?
    /// Plants still in the air: their place waits, then they settle.
    @State private var inAir: Set<String> = []
    @State private var settled: String?
    @State private var open: Herb?
    /// Counts the times the page is shown, so plants that came meanwhile are pressed each time.
    @State private var visits = 0

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)]

    private var book: HerbBook? { vault.contents?.herbarium }

    var body: some View {
        ScrollViewReader { proxy in
            NotebookPage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A pressed plant for showing up, never for how well it went. Nothing is ever lost.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                    Text("\(pressedCount) pressed").specimen()
                }

                if let contents = vault.contents {
                    let hasProgram = Herbarium.hasProgram(contents)
                    ForEach(HerbGroup.allCases, id: \.self) { group in
                        let herbs = Herb.visible(hasProgram: hasProgram).filter { $0.group == group }
                        if !herbs.isEmpty {
                            section(group.title, herbs: herbs)
                        }
                        if group == .firstSteps {
                            monthsSection
                        }
                    }
                }
            }
            .onAppear { visits += 1 }
            .task(id: "\(landing ?? "")#\(visits)") { await press(proxy) }
            // A soft tap as each plant settles on its place.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: settled) { _, id in id != nil }
        }
        .sheet(item: $open) { herb in
            PlantDetail(herb: herb, earned: book?.earned[herb.id], progress: vault.contents?.herbProgress(herb.id) ?? (0, 1))
                .presentationDetents([.medium])
        }
    }

    private var pressedCount: Int {
        guard let book else { return 0 }
        return book.earned.keys.filter { !inAir.contains($0) }.count
    }

    private func section(_ title: LocalizedStringResource, herbs: [Herb]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SpecimenLabel(text: title)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(herbs) { herb in cell(herb) }
            }
        }
    }

    /// Month plants: one for each month closed with its reflection, and this month still to come.
    private var monthsSection: some View {
        let earnedMonths = (book.map { Array($0.earned.keys) } ?? []).compactMap(Herb.monthOf).sorted(by: >)
        let current = MonthID.current()
        let months = earnedMonths.contains(current) ? earnedMonths : [current] + earnedMonths
        return VStack(alignment: .leading, spacing: 10) {
            SpecimenLabel(text: "Months")
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(months, id: \.description) { month in cell(Herb.monthHerb(month)) }
            }
        }
    }

    private func cell(_ herb: Herb) -> some View {
        let earned = book?.earned[herb.id] != nil && !inAir.contains(herb.id)
        return Button {
            open = herb
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if earned {
                        Image(herb.imageName)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .scale(scale: 1.9).combined(with: .offset(y: -160)).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        PlantSketch()
                            .padding(10)
                    }
                    if settled == herb.id {
                        Circle()
                            .stroke(Theme.sage, lineWidth: 2)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(width: 84, height: 84)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.cardBorder))
                .rotationEffect(.degrees(earned ? tilt(herb.id) : 0))

                label(herb, earned: earned)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // VoiceOver reads the plant's name and whether it came, not the drawing's file name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(herb.secret && !earned ? Text("Surprise") : Text(herb.name))
        .accessibilityValue(earned ? Text("Pressed") : Text("Not yet"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("herb.\(herb.id)")
        .id(herb.id)
    }

    @ViewBuilder
    private func label(_ herb: Herb, earned: Bool) -> some View {
        Group {
            if herb.secret && !earned {
                Text("Surprise")
            } else {
                Text(herb.name)
            }
        }
        .font(.footnote)
        .foregroundStyle(earned ? Theme.ink : Theme.inkMuted)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        if let level = herb.level {
            Text(verbatim: "· \(level) ·").specimen()
        }
    }

    /// A small, steady tilt per plant, as if taped by hand.
    private func tilt(_ id: String) -> Double {
        Double(id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7) - 3
    }

    /// Presses every plant that came: the chosen one first, each landing on its place.
    private func press(_ proxy: ScrollViewProxy) async {
        guard visits > 0, let book else { return }
        var queue = book.pending
        if let landing, let index = queue.firstIndex(of: landing) {
            queue.remove(at: index)
            queue.insert(landing, at: 0)
        }
        guard !queue.isEmpty else { return }
        if reduceMotion {
            try? vault.update { contents in
                for id in queue { contents.pressPlant(id) }
            }
            landing = nil
            return
        }
        inAir = Set(queue)
        for id in queue {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) {
                _ = inAir.remove(id)
            }
            try? vault.update { $0.pressPlant(id) }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.4)) { settled = id }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.4)) { settled = nil }
        }
        landing = nil
    }
}

/// A plant not pressed yet: a pencil sketch of a stem, a leaf and a flower.
struct PlantSketch: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 100
            var path = Path()
            path.move(to: CGPoint(x: 50 * s, y: 94 * s))
            path.addCurve(to: CGPoint(x: 50 * s, y: 44 * s), control1: CGPoint(x: 48 * s, y: 76 * s), control2: CGPoint(x: 52 * s, y: 60 * s))
            path.move(to: CGPoint(x: 50 * s, y: 74 * s))
            path.addCurve(to: CGPoint(x: 38 * s, y: 62 * s), control1: CGPoint(x: 42 * s, y: 72 * s), control2: CGPoint(x: 38 * s, y: 66 * s))
            path.addCurve(to: CGPoint(x: 50 * s, y: 74 * s), control1: CGPoint(x: 44 * s, y: 62 * s), control2: CGPoint(x: 48 * s, y: 68 * s))
            path.addEllipse(in: CGRect(x: 37 * s, y: 19 * s, width: 26 * s, height: 26 * s))
            context.stroke(path, with: .color(Theme.inkMuted.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3]))
        }
        .accessibilityHidden(true)
    }
}

/// One plant: what brings it, and when it came or how far along it is.
struct PlantDetail: View {
    let herb: Herb
    let earned: Date?
    let progress: (Int, Int)

    var body: some View {
        let hidden = herb.secret && earned == nil
        VStack(spacing: 14) {
            if earned != nil {
                Image(herb.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
            } else {
                PlantSketch().frame(width: 120, height: 120)
            }
            Group {
                if hidden {
                    Text("Surprise")
                } else {
                    Text(herb.name)
                }
            }
            .font(.notebookTitle(.title2))
            .foregroundStyle(Theme.ink)
            if !hidden {
                Text(herb.plant).specimen()
            }
            Group {
                if hidden {
                    Text("It comes on its own, doing what you usually do in Fallow.")
                } else {
                    Text(herb.how)
                }
            }
            .font(.body)
            .foregroundStyle(Theme.inkMuted)
            .multilineTextAlignment(.center)
            if let earned {
                Text("Pressed on \(earned.formatted(date: .long, time: .omitted))").specimen()
            } else if !hidden, progress.1 > 1, progress.0 > 0 {
                Text("\(min(progress.0, progress.1)) of \(progress.1)").specimen()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}

/// The moment a plant comes: its card on the table, with what brought it. "Press into the
/// herbarium" takes it there; "Later" leaves it waiting.
struct HerbMoment: View {
    let herb: Herb
    let onPress: () -> Void
    let onLater: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.35 : 0)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Image(herb.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                    Text(herb.plant)
                        .font(.notebookTitle(.headline).italic())
                        .foregroundStyle(Theme.moss)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.cardBorder))
                .rotationEffect(.degrees(shown ? -2 : -12))
                .offset(y: shown ? 0 : 60)

                SpecimenLabel(text: "A plant for the herbarium")
                Text(herb.name)
                    .font(.notebookTitle(.title2))
                    .foregroundStyle(Theme.ink)
                Text(herb.how)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                Text("You made time for yourself.")
                    .font(.subheadline.italic())
                    .foregroundStyle(Theme.moss)

                Button(action: onPress) {
                    Text("Press into the herbarium").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(action: onLater) {
                    Text("Later")
                }
                .foregroundStyle(Theme.inkMuted)
            }
            .padding(24)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .padding(24)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.3)) { shown = true } }
    }
}
