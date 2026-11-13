import SwiftUI
import ExamsCore

/// Tema "inchiostro e evidenziatore": sfondo blu-inchiostro, testo color carta, esami come evidenziatori.
/// La gerarchia la fa la tipografia: il countdown in SF Pro Compressed, i nomi degli esami in New York.
enum Theme {
    static let background = Color(hex: Palette.background)
    static let surface = Color(hex: Palette.surface)
    static let elevated = Color(hex: Palette.elevated)
    static let stroke = Color(hex: Palette.stroke)
    static let textPrimary = Color(hex: Palette.textPrimary)
    static let textSecondary = Color(hex: Palette.textSecondary)

    static let accent = Color(hex: Palette.accent)
    static let success = Color(hex: Palette.success)
    static let warning = Color(hex: Palette.warning)
    static let danger = Color(hex: Palette.danger)
    static let gold = Color(hex: Palette.gold)
    /// Linea del grafico: indaco un po' più scuro dell'accento, validato per il tema scuro
    /// (luminosità OKLCH nella fascia 0,48–0,67, contrasto ≥ 3:1 sulla superficie).
    static let chartLine = Color(hex: 0x86A6F5)

    /// Colori degli esami; ogni esame salva il suo indice, scelto tra i meno usati.
    static let examPalette: [Color] = Palette.examColors.map { Color(hex: $0) }

    static func color(index: Int?) -> Color {
        examPalette[(index ?? 0) % examPalette.count]
    }

    static func color(for exam: Exam) -> Color {
        color(index: exam.colorIndex)
    }

    /// Colore del countdown: quello dell'esame finché c'è tempo, poi ambra e corallo.
    static func countdownColor(days: Int, examColor: Color) -> Color {
        switch Urgency(days: days) {
        case .calm: examColor
        case .soon: warning
        case .urgent: danger
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Testo dell'interfaccia: SF Pro.
    static func ui(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, weight: weight)
    }

    /// Nomi degli esami: New York, il serif di sistema, con un tono da libretto.
    static func examName(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Il countdown, l'unico elemento che alza la voce: SF Pro Compressed Black.
    static func countdown(size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
}

extension View {
    /// Intestazione di sezione: in minuscolo come scritta, color matita.
    func sectionHeaderStyle() -> some View {
        font(.ui(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(nil)
    }

    /// Lista o form sullo sfondo del tema, con righe su superficie.
    func themedListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

/// Countdown in giorni: numero compresso e nerissimo, "Oggi" e "Domani" in parole.
struct CountdownText: View {
    let days: Int
    let color: Color
    var isLarge = true
    /// Seguono la dimensione del testo scelta nelle impostazioni di iOS.
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber: CGFloat = 76
    @ScaledMetric(relativeTo: .headline) private var smallNumber: CGFloat = 24

    var body: some View {
        Group {
            switch days {
            case 0:
                Text("Oggi").font(.countdown(size: isLarge ? bigNumber * 0.72 : smallNumber))
            case 1:
                Text("Domani").font(.countdown(size: isLarge ? bigNumber * 0.72 : smallNumber))
            default:
                HStack(alignment: .firstTextBaseline, spacing: isLarge ? 6 : 2) {
                    Text("\(days)")
                        .font(.countdown(size: isLarge ? bigNumber : smallNumber))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(isLarge ? "giorni" : "g")
                        .font(.ui(isLarge ? .title3 : .subheadline, weight: .semibold))
                        .opacity(0.8)
                }
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 0 ? "Oggi" : days == 1 ? "Domani" : "Tra \(days) giorni")
    }
}

/// Anello di avanzamento con la percentuale al centro.
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.ui(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avanzamento dello studio")
        .accessibilityValue("\(Int((progress * 100).rounded())) per cento")
    }
}

/// Etichetta discreta del corso di laurea.
struct DegreeTag: View {
    @Environment(\.degreeVisibility) private var visibility
    let degree: Degree

    var body: some View {
        // Con un solo corso mostrato l'etichetta non serve.
        if visibility.fixedDegree == nil {
            label
        }
    }

    private var label: some View {
        Text(degree.label)
            .font(.ui(.caption2, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()   // mai spezzata con il trattino nelle colonne strette
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

/// Interruttore a capsule tra Triennale e Magistrale, nei colori del tema.
struct DegreeSwitcher: View {
    @Binding var selection: Degree
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Degree.allCases) { degree in
                let isSelected = degree == selection
                Button {
                    withAnimation(.snappy) { selection = degree }
                } label: {
                    Text(degree.label)
                        .font(.ui(.footnote, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            // Selezione come carta in rilievo: l'accento resta alla navigazione.
                            if isSelected {
                                Capsule()
                                    .fill(Theme.elevated)
                                    .matchedGeometryEffect(id: "selected", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .textCase(nil)
    }
}

/// Esito di un esame passato: voto, lode, non superato o da inserire.
struct GradeBadge: View {
    let exam: Exam

    var body: some View {
        let (content, color): (AnyView, Color) = switch exam.passed {
        case true? where exam.isMasterThesis:
            (AnyView(Text(exam.thesisPointsLabel ?? "✓")), Theme.gold)
        case true? where exam.honors:
            (AnyView(Text("30L")), Theme.gold)
        case true?:
            (AnyView(Text(exam.grade.map(String.init) ?? "✓")), Theme.success)
        case false?:
            (AnyView(Image(systemName: "xmark")), Theme.danger)
        case nil:
            (AnyView(Image(systemName: "questionmark")), Theme.textSecondary)
        }
        content
            .font(.ui(.subheadline, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(Circle().fill(color.opacity(0.16)))
            .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(exam.outcomeLabel)
    }
}
