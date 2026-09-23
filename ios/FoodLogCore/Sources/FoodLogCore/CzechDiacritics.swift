// CzechDiacritics.swift
//
// Restores diacritics to common Czech food words typed without them
// ("mleko" -> "mléko"). Exists because both remote databases this app
// searches are diacritic-SENSITIVE (probed 2026-09-23, rebuild-food-search
// design.md): Search-a-licious returned 45 Czech hits for "mléko" but only
// 9 for "mleko", and 52 for "šunka" versus 11 for "sunka". Czech users type
// both ways, so `SearchText.remoteQueryVariants` sends the restored
// spelling as a second variant whenever this table recognises at least one
// of the typed words (unknown words are sent as typed). Local ranking never needs this -- it compares folded text.
//
// Deliberately a small, hand-written vocabulary of food words, not a
// general Czech dictionary: a wrong or missing entry only costs one extra
// (or one missing) remote request, never a wrong ranking. The table is
// built from the accented forms themselves, so its folded keys can't drift
// out of sync with `SearchText.fold`.

import Foundation

public enum CzechDiacritics {
    /// Returns `phrase` (lowercased, space-separated words) with every word
    /// found in the vocabulary replaced by its accented form, or `nil` if no
    /// word changed.
    public static func restore(_ phrase: String) -> String? {
        var changed = false
        let words = phrase.split(separator: " ", omittingEmptySubsequences: true).map { word -> String in
            let key = String(word)
            if let accented = vocabulary[key], accented != key {
                changed = true
                return accented
            }
            return key
        }
        return changed ? words.joined(separator: " ") : nil
    }

    /// Folded word -> accented word.
    static let vocabulary: [String: String] = {
        var table: [String: String] = [:]
        for word in accentedWords where table[SearchText.fold(word)] == nil {
            table[SearchText.fold(word)] = word
        }
        return table
    }()

    /// Only words that actually carry a diacritic are useful here.
    static let accentedWords: [String] = [
        // Bakery, grains, sides
        "rohlík", "rohlíky", "rohlíku", "chléb", "chlebíček", "chlebíčky", "pečivo", "vánočka",
        "koláč", "koláče", "loupák", "lívance", "palačinky", "knedlík", "knedlíky", "těstoviny",
        "špagety", "rýže", "bramborová", "bramborový", "bramboráky", "halušky", "kaše", "ovesné",
        "ovesná", "ovesný", "vločky", "müsli", "cereálie", "sušenky", "sušenka", "tyčinka",
        "žitný", "žitná", "pšeničný", "pšeničná", "celozrnný", "celozrnná", "celozrnné", "kváskový",
        "tmavý", "světlý",
        // Dairy
        "mléko", "mléčný", "mléčná", "máslo", "máslový", "sýr", "sýry", "sýrový", "tvarohový",
        "tvarohová", "jogurtový", "jogurtová", "bílý", "bílá", "bílé", "řecký", "řecká", "smetanový",
        "smetanová", "zakysaná", "kefírové", "kefírový", "acidofilní", "polotučné", "polotučný",
        "polotučná", "plnotučné", "plnotučný", "odtučněný", "odtučněné", "nízkotučný", "nízkotučné",
        "tučný", "tučné", "měkký", "měkká", "měkké", "tvrdý", "tvrdá", "čerstvý", "čerstvé", "čerstvá",
        "pomazánka", "pomazánkové", "žervé", "hermelín", "olomoucké", "tvarůžky", "bezlaktózový",
        // Meat, fish, eggs
        "kuře", "kuřecí", "krůtí", "krůta", "hovězí", "vepřové", "vepřová", "vepřový", "telecí",
        "jehněčí", "šunka", "šunky", "salám", "klobása", "párek", "párky", "špekáček",
        "řízek", "řízky", "prsní", "játra", "mleté", "mletý", "sekaná", "guláš", "svíčková",
        "polévka", "vývar", "tuňák", "vajíčko", "vajíčka", "vaječný", "vaječná", "uzený", "uzené",
        "uzená", "vařený", "vařené", "pečený", "pečené", "pečená", "smažený", "smažené",
        "grilovaný", "grilované",
        // Fruit, vegetables, nuts
        "jablečný", "jablečná", "hruška", "hrušky", "švestka", "švestky", "třešně", "višně",
        "meruňka", "meruňky", "jahodový", "jahodová", "borůvky", "borůvkový", "borůvková",
        "malinový", "malinová", "banán", "banány", "pomeranč", "pomeranče", "citrón", "ořechy",
        "ořech", "oříšky", "arašídy", "arašídové", "kešu", "lískové", "kokosový", "kokosová",
        "rajče", "rajčata", "česnek", "zelí", "kysané", "špenát", "květák", "dýně", "čočka",
        "hrách", "kukuřice", "žampiony", "ovocný", "ovocná", "zeleninový", "zeleninová",
        // Pantry, drinks, other
        "džem", "marmeláda", "sůl", "pepř", "olivový", "olivová", "slunečnicový", "čokoláda",
        "čokoládový", "čokoládová", "čaj", "káva", "džus", "víno", "minerálka", "limonáda", "nápoj",
        "proteinový", "proteinová", "sójový", "sójová", "rostlinný", "rostlinná", "domácí",
        "bezlepkový", "bylinkový"
    ]
}
