/// Colori del tema "inchiostro e evidenziatore", condivisi da app e widget: sfondo blu-inchiostro,
/// testo color carta, gli esami come tinte da evidenziatore.
public enum Palette {
    /// Inchiostro: il blu della penna, non un grigio neutro.
    public static let background: UInt32 = 0x0F1728
    /// Carta di notte: righe e riquadri.
    public static let surface: UInt32 = 0x172238
    public static let elevated: UInt32 = 0x1D2A42
    /// Filetti e bordi.
    public static let stroke: UInt32 = 0x26324A
    /// Carta.
    public static let textPrimary: UInt32 = 0xECE8DD
    /// Matita.
    public static let textSecondary: UInt32 = 0x93A0B8

    /// Penna blu: navigazione e azioni principali.
    public static let accent: UInt32 = 0x8FB0FF
    public static let success: UInt32 = 0x5BD6A0
    public static let warning: UInt32 = 0xF6B94A
    public static let danger: UInt32 = 0xFF7D8E
    public static let gold: UInt32 = 0xF5CB45

    /// Colori degli esami: tinte da evidenziatore, luminose sull'inchiostro, senza rosso e oro
    /// (riservati a urgenza e lode). L'ordine resta quello di sempre (gli esami salvano l'indice)
    /// e alterna tinte lontane, così esami creati uno dopo l'altro hanno colori ben distinti.
    public static let examColors: [UInt32] = [
        0x9AA5FF, // indaco
        0x4FE3A6, // smeraldo
        0xFF9F5A, // arancio
        0x5CCBFF, // azzurro
        0xF08CFF, // fucsia
        0xC6F24E, // lime
        0xB59CFF, // viola
        0x3EE6CF, // verde acqua
        0xFFD15C, // ambra
        0x76AEFF, // blu
        0xFF8FC8, // rosa
        0x6EEB8E, // verde
        0xD39BFF, // porpora
        0x45E0F2, // ciano
    ]

    /// Colore per un nuovo esame: il meno usato; a parità, il primo nell'ordine della tavolozza.
    public static func balancedColorIndex(used: [Int]) -> Int {
        var counts = [Int](repeating: 0, count: examColors.count)
        for index in used where counts.indices.contains(index) {
            counts[index] += 1
        }
        let fewest = counts.min() ?? 0
        return counts.firstIndex(of: fewest) ?? 0
    }
}
