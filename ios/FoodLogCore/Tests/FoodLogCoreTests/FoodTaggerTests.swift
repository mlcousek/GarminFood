// FoodTaggerTests.swift
//
// The golden suite for `FoodTagger` (design D13): Czech and English food
// names, including the known traps -- "rybíz" (currant) is not fish,
// "pivoňka" (peony) is not beer, "kuřecí" is poultry, "Kofola bez cukru" is
// not a sugary drink, "syrové" (raw) is not cheese, "pórek" (leek) is not
// pork, and the 859-barcode fallback applies only when the brand is
// unknown. Each fixture asserts tags that MUST be present and tags that
// MUST NOT be, rather than the exact set, so adding a new (correct) tag to
// a rule does not break unrelated fixtures.
//
// When the owner reports a mis-tag: add the failing fixture here first.

import XCTest
@testable import FoodLogCore

final class FoodTaggerTests: XCTestCase {
    private struct Fixture {
        let name: String
        let brand: String?
        let barcode: String?
        let mustInclude: Set<FoodTag>
        let mustExclude: Set<FoodTag>
    }

    private static let fixtures: [Fixture] = [
        Fixture(name: "Rybízový džem", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.fish, .fruit]),
        Fixture(name: "Rybíz červený", brand: nil, barcode: nil, mustInclude: [.fruit, .colourRed], mustExclude: [.fish]),
        Fixture(name: "Pivoňkový čaj", brand: nil, barcode: nil, mustInclude: [.tea], mustExclude: [.beer, .alcohol]),
        Fixture(name: "Kuřecí prsa", brand: nil, barcode: nil, mustInclude: [.poultry, .meat], mustExclude: [.redMeat]),
        Fixture(name: "Kofola Original", brand: "Kofola", barcode: nil, mustInclude: [.sugaryDrink, .czechBrand], mustExclude: []),
        Fixture(name: "Kofola", brand: nil, barcode: nil, mustInclude: [.sugaryDrink, .czechBrand], mustExclude: []),
        Fixture(name: "Kofola bez cukru", brand: "Kofola", barcode: nil, mustInclude: [.czechBrand], mustExclude: [.sugaryDrink]),
        Fixture(name: "Kysané zelí", brand: nil, barcode: nil, mustInclude: [.fermented, .vegetable], mustExclude: []),
        Fixture(name: "Hollandia Selský jogurt", brand: nil, barcode: nil, mustInclude: [.dairy, .fermented, .czechBrand], mustExclude: []),
        Fixture(name: "Selský jogurt bílý", brand: "Hollandia", barcode: nil, mustInclude: [.dairy, .fermented, .czechBrand], mustExclude: []),
        Fixture(name: "Tvaroh měkký", brand: nil, barcode: "8594001234567", mustInclude: [.dairy, .czechBrand], mustExclude: []),
        Fixture(name: "Neznámý výrobek", brand: nil, barcode: "8594001234567", mustInclude: [.czechBrand], mustExclude: []),
        Fixture(name: "Neznámý výrobek", brand: "Nestlé", barcode: "8594001234567", mustInclude: [], mustExclude: [.czechBrand]),
        Fixture(name: "Neznámý výrobek", brand: nil, barcode: "4001234567890", mustInclude: [], mustExclude: [.czechBrand]),
        Fixture(name: "Neznámý výrobek", brand: nil, barcode: "859400123456", mustInclude: [], mustExclude: [.czechBrand]),
        Fixture(name: "", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.fruit, .vegetable, .fish, .czechBrand]),
        Fixture(name: "Losos na grilu", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: [.meat]),
        Fixture(name: "Tuňákový salát", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: [.meat]),
        Fixture(name: "Tuňák ve vlastní šťávě", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Jablko", brand: nil, barcode: nil, mustInclude: [.fruit], mustExclude: [.vegetable]),
        Fixture(name: "Jablka červená", brand: nil, barcode: nil, mustInclude: [.fruit, .colourRed], mustExclude: []),
        Fixture(name: "Banán", brand: nil, barcode: nil, mustInclude: [.fruit, .colourYellow], mustExclude: []),
        Fixture(name: "Banány", brand: nil, barcode: nil, mustInclude: [.fruit, .colourYellow], mustExclude: []),
        Fixture(name: "Jahody čerstvé", brand: nil, barcode: nil, mustInclude: [.fruit, .colourRed], mustExclude: []),
        Fixture(name: "Jahodový jogurt", brand: nil, barcode: nil, mustInclude: [.dairy, .fermented], mustExclude: [.fruit, .colourRed]),
        Fixture(name: "Borůvky", brand: nil, barcode: nil, mustInclude: [.fruit, .colourPurple], mustExclude: []),
        Fixture(name: "Pomeranč", brand: nil, barcode: nil, mustInclude: [.fruit, .colourOrange], mustExclude: []),
        Fixture(name: "Pomerančový džus", brand: nil, barcode: nil, mustInclude: [.sugaryDrink], mustExclude: [.fruit, .colourOrange]),
        Fixture(name: "Orange juice", brand: nil, barcode: nil, mustInclude: [.sugaryDrink], mustExclude: [.fruit]),
        Fixture(name: "Kiwi", brand: nil, barcode: nil, mustInclude: [.fruit, .colourGreen], mustExclude: []),
        Fixture(name: "Avokádo", brand: nil, barcode: nil, mustInclude: [.fruit, .colourGreen], mustExclude: []),
        Fixture(name: "Švestky", brand: nil, barcode: nil, mustInclude: [.fruit, .colourPurple], mustExclude: []),
        Fixture(name: "Hroznové víno bílé", brand: nil, barcode: nil, mustInclude: [.fruit], mustExclude: [.alcohol]),
        Fixture(name: "Meruňky sušené", brand: nil, barcode: nil, mustInclude: [.fruit, .colourOrange], mustExclude: []),
        Fixture(name: "Strawberries", brand: nil, barcode: nil, mustInclude: [.fruit, .colourRed], mustExclude: []),
        Fixture(name: "Apple", brand: nil, barcode: nil, mustInclude: [.fruit], mustExclude: []),
        Fixture(name: "Grapes", brand: nil, barcode: nil, mustInclude: [.fruit], mustExclude: []),
        Fixture(name: "Mango", brand: nil, barcode: nil, mustInclude: [.fruit, .colourOrange], mustExclude: []),
        Fixture(name: "Ananas", brand: nil, barcode: nil, mustInclude: [.fruit, .colourYellow], mustExclude: []),
        Fixture(name: "Hruška", brand: nil, barcode: nil, mustInclude: [.fruit], mustExclude: []),
        Fixture(name: "Maliny", brand: nil, barcode: nil, mustInclude: [.fruit, .colourRed], mustExclude: []),
        Fixture(name: "Mrkev", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourOrange], mustExclude: [.fruit]),
        Fixture(name: "Mrkev strouhaná", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourOrange], mustExclude: []),
        Fixture(name: "Rajčata cherry", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourRed], mustExclude: []),
        Fixture(name: "Rajče", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourRed], mustExclude: []),
        Fixture(name: "Kečup jemný", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.vegetable, .colourRed]),
        Fixture(name: "Brokolice vařená", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Špenát listový", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: [.pastry]),
        Fixture(name: "Okurka salátová", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Paprika červená", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourRed], mustExclude: []),
        Fixture(name: "Paprika žlutá", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourYellow], mustExclude: []),
        Fixture(name: "Cibule", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourWhite], mustExclude: [.colourRed]),
        Fixture(name: "Červená cibule", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourPurple], mustExclude: [.colourWhite, .colourRed]),
        Fixture(name: "Květák", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourWhite], mustExclude: []),
        Fixture(name: "Lilek", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourPurple], mustExclude: []),
        Fixture(name: "Dýně Hokkaido", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourOrange], mustExclude: []),
        Fixture(name: "Cuketa", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Červená řepa", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourRed], mustExclude: []),
        Fixture(name: "Pórek", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: [.meat]),
        Fixture(name: "Pork chop", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: [.vegetable]),
        Fixture(name: "Žampiony", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourWhite], mustExclude: []),
        Fixture(name: "Zeleninový salát", brand: nil, barcode: nil, mustInclude: [.vegetable], mustExclude: []),
        Fixture(name: "Ledový salát", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Bramborový salát", brand: nil, barcode: nil, mustInclude: [.potato], mustExclude: [.vegetable]),
        Fixture(name: "Broccoli", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Carrots", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourOrange], mustExclude: []),
        Fixture(name: "Spinach", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourGreen], mustExclude: []),
        Fixture(name: "Zelené fazolky", brand: nil, barcode: nil, mustInclude: [.vegetable, .legume, .colourGreen], mustExclude: []),
        Fixture(name: "Červené zelí", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourPurple], mustExclude: []),
        Fixture(name: "Kapr smažený", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Pstruh na másle", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Treska filé", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Rybí prsty", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Makrela uzená", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Salmon fillet", brand: nil, barcode: nil, mustInclude: [.fish], mustExclude: []),
        Fixture(name: "Krevety", brand: nil, barcode: nil, mustInclude: [.seafood], mustExclude: [.fish]),
        Fixture(name: "Krabí tyčinky", brand: nil, barcode: nil, mustInclude: [.seafood], mustExclude: [.sweets]),
        Fixture(name: "Krabice mléka", brand: nil, barcode: nil, mustInclude: [.dairy], mustExclude: [.seafood]),
        Fixture(name: "Chobotnice", brand: nil, barcode: nil, mustInclude: [.seafood], mustExclude: []),
        Fixture(name: "Hovězí guláš", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat, .cuisineCzech], mustExclude: [.poultry]),
        Fixture(name: "Vepřová pečeně", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: []),
        Fixture(name: "Svíčková na smetaně s knedlíkem", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat, .cuisineCzech, .knedlik], mustExclude: []),
        Fixture(name: "Kuřecí řízek", brand: nil, barcode: nil, mustInclude: [.meat, .poultry], mustExclude: [.redMeat]),
        Fixture(name: "Krůtí šunka", brand: nil, barcode: nil, mustInclude: [.meat, .poultry], mustExclude: [.redMeat]),
        Fixture(name: "Šunka od kosti", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: []),
        Fixture(name: "Kachna pečená", brand: nil, barcode: nil, mustInclude: [.meat, .poultry], mustExclude: []),
        Fixture(name: "Párky", brand: nil, barcode: nil, mustInclude: [.meat], mustExclude: []),
        Fixture(name: "Vegetariánský burger", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.meat, .redMeat]),
        Fixture(name: "Sójový plátek", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.meat]),
        Fixture(name: "Chicken breast", brand: nil, barcode: nil, mustInclude: [.meat, .poultry], mustExclude: [.redMeat]),
        Fixture(name: "Beef steak", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: []),
        Fixture(name: "Salám Vysočina", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: []),
        Fixture(name: "Slanina", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: []),
        Fixture(name: "Kuřecí vývar", brand: nil, barcode: nil, mustInclude: [.soup], mustExclude: [.poultry]),
        Fixture(name: "Vejce slepičí", brand: nil, barcode: nil, mustInclude: [.egg], mustExclude: []),
        Fixture(name: "Vajíčka natvrdo", brand: nil, barcode: nil, mustInclude: [.egg], mustExclude: []),
        Fixture(name: "Míchaná vejce", brand: nil, barcode: nil, mustInclude: [.egg], mustExclude: []),
        Fixture(name: "Omeleta se sýrem", brand: nil, barcode: nil, mustInclude: [.egg, .cheese, .dairy], mustExclude: []),
        Fixture(name: "Vaječné těstoviny", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.egg]),
        Fixture(name: "Scrambled eggs", brand: nil, barcode: nil, mustInclude: [.egg], mustExclude: []),
        Fixture(name: "Eggplant", brand: nil, barcode: nil, mustInclude: [.vegetable, .colourPurple], mustExclude: [.egg]),
        Fixture(name: "Mléko polotučné", brand: nil, barcode: nil, mustInclude: [.dairy], mustExclude: []),
        Fixture(name: "Mléčná čokoláda", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: [.dairy]),
        Fixture(name: "Kokosové mléko", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.dairy]),
        Fixture(name: "Kefír", brand: nil, barcode: nil, mustInclude: [.dairy, .fermented], mustExclude: []),
        Fixture(name: "Tvaroh tučný", brand: "Madeta", barcode: nil, mustInclude: [.dairy, .czechBrand], mustExclude: []),
        Fixture(name: "Eidam 30%", brand: nil, barcode: nil, mustInclude: [.dairy, .cheese], mustExclude: []),
        Fixture(name: "Sýr Eidam plátky", brand: nil, barcode: nil, mustInclude: [.dairy, .cheese], mustExclude: []),
        Fixture(name: "Smažený sýr", brand: nil, barcode: nil, mustInclude: [.dairy, .cheese, .cuisineCzech], mustExclude: []),
        Fixture(name: "Hermelín", brand: nil, barcode: nil, mustInclude: [.cheese, .cuisineCzech], mustExclude: []),
        Fixture(name: "Olomoucké tvarůžky", brand: nil, barcode: nil, mustInclude: [.cheese], mustExclude: []),
        Fixture(name: "Máslo", brand: nil, barcode: nil, mustInclude: [.dairy], mustExclude: []),
        Fixture(name: "Peanut butter", brand: nil, barcode: nil, mustInclude: [.nuts], mustExclude: [.dairy]),
        Fixture(name: "Řecký jogurt", brand: nil, barcode: nil, mustInclude: [.dairy, .fermented, .cuisineGreek], mustExclude: []),
        Fixture(name: "Mozzarella", brand: nil, barcode: nil, mustInclude: [.cheese, .cuisineItalian], mustExclude: []),
        Fixture(name: "Syrové maso", brand: nil, barcode: nil, mustInclude: [.meat], mustExclude: [.cheese]),
        Fixture(name: "Kysaná smetana", brand: nil, barcode: nil, mustInclude: [.dairy, .fermented], mustExclude: []),
        Fixture(name: "Sójový jogurt", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.dairy]),
        Fixture(name: "Pribináček vanilkový", brand: nil, barcode: nil, mustInclude: [.dairy, .czechBrand], mustExclude: []),
        Fixture(name: "Čočka", brand: nil, barcode: nil, mustInclude: [.legume], mustExclude: []),
        Fixture(name: "Čočková polévka", brand: nil, barcode: nil, mustInclude: [.legume, .soup], mustExclude: []),
        Fixture(name: "Červená čočka", brand: nil, barcode: nil, mustInclude: [.legume, .colourRed], mustExclude: []),
        Fixture(name: "Cizrna", brand: nil, barcode: nil, mustInclude: [.legume], mustExclude: []),
        Fixture(name: "Hummus", brand: nil, barcode: nil, mustInclude: [.legume, .cuisineMiddleEastern], mustExclude: []),
        Fixture(name: "Fazole v tomatové omáčce", brand: nil, barcode: nil, mustInclude: [.legume], mustExclude: []),
        Fixture(name: "Lentilky", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: [.legume]),
        Fixture(name: "Tofu natural", brand: nil, barcode: nil, mustInclude: [.legume], mustExclude: [.meat]),
        Fixture(name: "Vlašské ořechy", brand: nil, barcode: nil, mustInclude: [.nuts], mustExclude: []),
        Fixture(name: "Mandle", brand: nil, barcode: nil, mustInclude: [.nuts], mustExclude: []),
        Fixture(name: "Kešu ořechy", brand: nil, barcode: nil, mustInclude: [.nuts], mustExclude: []),
        Fixture(name: "Arašídy solené", brand: nil, barcode: nil, mustInclude: [.nuts], mustExclude: []),
        Fixture(name: "Muškátový oříšek", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.nuts]),
        Fixture(name: "Ovesné vločky", brand: nil, barcode: nil, mustInclude: [.wholeGrain], mustExclude: []),
        Fixture(name: "Celozrnný chléb", brand: nil, barcode: nil, mustInclude: [.wholeGrain], mustExclude: []),
        Fixture(name: "Pohanka", brand: nil, barcode: nil, mustInclude: [.wholeGrain], mustExclude: []),
        Fixture(name: "Kukuřičné lupínky", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.wholeGrain, .vegetable, .colourYellow]),
        Fixture(name: "Quinoa", brand: nil, barcode: nil, mustInclude: [.wholeGrain], mustExclude: []),
        Fixture(name: "Müsli s ovocem", brand: nil, barcode: nil, mustInclude: [.wholeGrain], mustExclude: [.fruit]),
        Fixture(name: "Gulášová polévka", brand: nil, barcode: nil, mustInclude: [.soup], mustExclude: []),
        Fixture(name: "Bramboračka", brand: nil, barcode: nil, mustInclude: [.soup, .potato, .cuisineCzech], mustExclude: []),
        Fixture(name: "Česnečka", brand: nil, barcode: nil, mustInclude: [.soup, .cuisineCzech], mustExclude: []),
        Fixture(name: "Kulajda", brand: nil, barcode: nil, mustInclude: [.soup, .cuisineCzech], mustExclude: []),
        Fixture(name: "Tomato soup", brand: nil, barcode: nil, mustInclude: [.soup], mustExclude: []),
        Fixture(name: "Ramen", brand: nil, barcode: nil, mustInclude: [.soup, .cuisineJapanese], mustExclude: []),
        Fixture(name: "Pho bo", brand: nil, barcode: nil, mustInclude: [.soup, .cuisineVietnamese], mustExclude: []),
        Fixture(name: "Káva s mlékem", brand: nil, barcode: nil, mustInclude: [.coffee, .dairy], mustExclude: []),
        Fixture(name: "Espresso", brand: nil, barcode: nil, mustInclude: [.coffee], mustExclude: []),
        Fixture(name: "Cappuccino", brand: nil, barcode: nil, mustInclude: [.coffee], mustExclude: []),
        Fixture(name: "Kávová zmrzlina", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: [.coffee]),
        Fixture(name: "Kaviár", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.coffee]),
        Fixture(name: "Zelený čaj", brand: nil, barcode: nil, mustInclude: [.tea], mustExclude: [.vegetable]),
        Fixture(name: "Čaj ovocný", brand: nil, barcode: nil, mustInclude: [.tea], mustExclude: [.fruit]),
        Fixture(name: "Ledový čaj broskev", brand: nil, barcode: nil, mustInclude: [.tea, .sugaryDrink], mustExclude: [.fruit]),
        Fixture(name: "Coca-Cola", brand: nil, barcode: nil, mustInclude: [.sugaryDrink], mustExclude: []),
        Fixture(name: "Coca-Cola Zero", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.sugaryDrink]),
        Fixture(name: "Pepsi Max", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.sugaryDrink]),
        Fixture(name: "Red Bull", brand: nil, barcode: nil, mustInclude: [.sugaryDrink], mustExclude: [.colourRed]),
        Fixture(name: "Mattoni pomeranč", brand: "Mattoni", barcode: nil, mustInclude: [.czechBrand], mustExclude: []),
        Fixture(name: "Pivo Pilsner Urquell", brand: nil, barcode: nil, mustInclude: [.alcohol, .beer], mustExclude: []),
        Fixture(name: "Plzeňský Prazdroj", brand: nil, barcode: nil, mustInclude: [.alcohol, .beer], mustExclude: []),
        Fixture(name: "Pivo nealkoholické", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.alcohol, .beer]),
        Fixture(name: "Birell", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.alcohol]),
        Fixture(name: "Červené víno", brand: nil, barcode: nil, mustInclude: [.alcohol], mustExclude: [.colourRed]),
        Fixture(name: "Vinný ocet", brand: nil, barcode: nil, mustInclude: [], mustExclude: [.alcohol]),
        Fixture(name: "Becherovka", brand: nil, barcode: nil, mustInclude: [.alcohol], mustExclude: []),
        Fixture(name: "Pivní sýr", brand: nil, barcode: nil, mustInclude: [.cheese], mustExclude: [.beer, .alcohol]),
        Fixture(name: "Hořká čokoláda", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: []),
        Fixture(name: "Tatranka oříšková", brand: "Opavia", barcode: nil, mustInclude: [.sweets, .czechBrand], mustExclude: []),
        Fixture(name: "Horalky", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: []),
        Fixture(name: "Zmrzlina vanilková", brand: nil, barcode: nil, mustInclude: [.sweets], mustExclude: [.dairy]),
        Fixture(name: "Koblih s marmeládou", brand: nil, barcode: nil, mustInclude: [.sweets, .pastry], mustExclude: []),
        Fixture(name: "Rohlík", brand: nil, barcode: nil, mustInclude: [.pastry], mustExclude: []),
        Fixture(name: "Rohlík tukový", brand: "Penam", barcode: nil, mustInclude: [.pastry, .czechBrand], mustExclude: []),
        Fixture(name: "Houska", brand: nil, barcode: nil, mustInclude: [.pastry], mustExclude: []),
        Fixture(name: "Koláč tvarohový", brand: nil, barcode: nil, mustInclude: [.pastry, .pie, .dairy], mustExclude: []),
        Fixture(name: "Jablečný závin", brand: nil, barcode: nil, mustInclude: [.pastry, .pie], mustExclude: [.fruit]),
        Fixture(name: "Palačinky", brand: nil, barcode: nil, mustInclude: [.pastry], mustExclude: []),
        Fixture(name: "Croissant", brand: nil, barcode: nil, mustInclude: [.pastry, .cuisineFrench], mustExclude: []),
        Fixture(name: "Buchty", brand: nil, barcode: nil, mustInclude: [.pastry, .cuisineCzech], mustExclude: []),
        Fixture(name: "Vánočka", brand: nil, barcode: nil, mustInclude: [.pastry, .cuisineCzech], mustExclude: []),
        Fixture(name: "Apple pie", brand: nil, barcode: nil, mustInclude: [.pie], mustExclude: []),
        Fixture(name: "Tatarák", brand: nil, barcode: nil, mustInclude: [.meat, .redMeat], mustExclude: [.pie]),
        Fixture(name: "Pizza Margherita", brand: nil, barcode: nil, mustInclude: [.pizza, .cuisineItalian], mustExclude: []),
        Fixture(name: "Pizza Quattro Formaggi", brand: nil, barcode: nil, mustInclude: [.pizza, .cuisineItalian], mustExclude: []),
        Fixture(name: "Špagety carbonara", brand: nil, barcode: nil, mustInclude: [.cuisineItalian], mustExclude: []),
        Fixture(name: "Lasagne", brand: nil, barcode: nil, mustInclude: [.cuisineItalian], mustExclude: []),
        Fixture(name: "Rizoto s houbami", brand: nil, barcode: nil, mustInclude: [.cuisineItalian, .vegetable], mustExclude: []),
        Fixture(name: "Sushi maki", brand: nil, barcode: nil, mustInclude: [.cuisineJapanese], mustExclude: []),
        Fixture(name: "Kuře kung pao", brand: nil, barcode: nil, mustInclude: [.cuisineChinese, .poultry], mustExclude: []),
        Fixture(name: "Chicken tikka masala", brand: nil, barcode: nil, mustInclude: [.cuisineIndian, .poultry], mustExclude: []),
        Fixture(name: "Thajské zelené kari", brand: nil, barcode: nil, mustInclude: [.cuisineThai], mustExclude: [.cuisineIndian]),
        Fixture(name: "Burrito s hovězím", brand: nil, barcode: nil, mustInclude: [.cuisineMexican, .redMeat], mustExclude: []),
        Fixture(name: "Tortilla chips", brand: nil, barcode: nil, mustInclude: [.cuisineMexican], mustExclude: [.colourYellow]),
        Fixture(name: "Gyros", brand: nil, barcode: nil, mustInclude: [.cuisineGreek, .meat], mustExclude: []),
        Fixture(name: "Kebab v housce", brand: nil, barcode: nil, mustInclude: [.cuisineTurkish, .meat], mustExclude: []),
        Fixture(name: "Paella", brand: nil, barcode: nil, mustInclude: [.cuisineSpanish], mustExclude: []),
        Fixture(name: "Španělský ptáček", brand: nil, barcode: nil, mustInclude: [.cuisineCzech], mustExclude: [.cuisineSpanish]),
        Fixture(name: "Francouzské brambory", brand: nil, barcode: nil, mustInclude: [.potato], mustExclude: [.cuisineFrench]),
        Fixture(name: "Quiche Lorraine", brand: nil, barcode: nil, mustInclude: [.pie, .cuisineFrench], mustExclude: []),
        Fixture(name: "Cheeseburger", brand: nil, barcode: nil, mustInclude: [.cuisineAmerican, .redMeat, .cheese], mustExclude: []),
        Fixture(name: "Kimchi", brand: nil, barcode: nil, mustInclude: [.fermented, .cuisineKorean], mustExclude: []),
        Fixture(name: "Falafel", brand: nil, barcode: nil, mustInclude: [.legume, .cuisineMiddleEastern], mustExclude: []),
        Fixture(name: "Bánh mì", brand: nil, barcode: nil, mustInclude: [.cuisineVietnamese], mustExclude: []),
        Fixture(name: "Vepřo knedlo zelo", brand: nil, barcode: nil, mustInclude: [.redMeat, .knedlik, .cuisineCzech, .vegetable], mustExclude: []),
        Fixture(name: "Ovocné knedlíky", brand: nil, barcode: nil, mustInclude: [.knedlik, .cuisineCzech], mustExclude: []),
        Fixture(name: "Bramborové knedlíky", brand: nil, barcode: nil, mustInclude: [.knedlik, .potato], mustExclude: []),
        Fixture(name: "Hranolky", brand: nil, barcode: nil, mustInclude: [.potato], mustExclude: []),
        Fixture(name: "Brambory vařené", brand: nil, barcode: nil, mustInclude: [.potato], mustExclude: [.vegetable]),
        Fixture(name: "Jogurt jahodový", brand: "Olma", barcode: nil, mustInclude: [.czechBrand, .dairy], mustExclude: []),
        Fixture(name: "Mléko", brand: "Kunín", barcode: nil, mustInclude: [.czechBrand, .dairy], mustExclude: []),
        Fixture(name: "Pomazánkové", brand: "Madeta", barcode: nil, mustInclude: [.czechBrand], mustExclude: []),
        Fixture(name: "Šunka výběrová", brand: "Kostelecké uzeniny", barcode: nil, mustInclude: [.czechBrand, .redMeat], mustExclude: []),
        Fixture(name: "Pašteta", brand: "Hamé", barcode: nil, mustInclude: [.czechBrand, .meat], mustExclude: []),
        Fixture(name: "Ham sandwich", brand: nil, barcode: nil, mustInclude: [.meat], mustExclude: [.czechBrand]),
        Fixture(name: "Studentská pečeť", brand: "Orion", barcode: nil, mustInclude: [.sweets, .czechBrand], mustExclude: []),
        Fixture(name: "Corn flakes", brand: "Emco", barcode: nil, mustInclude: [.czechBrand], mustExclude: []),
        Fixture(name: "Rajec neperlivý", brand: "Rajec", barcode: nil, mustInclude: [], mustExclude: [.czechBrand]),
        Fixture(name: "Chléb Šumava", brand: "Albert Quality", barcode: nil, mustInclude: [.czechBrand], mustExclude: []),
        Fixture(name: "Mléko trvanlivé", brand: "Choceňská mlékárna", barcode: nil, mustInclude: [.czechBrand, .dairy], mustExclude: []),
    ]

    func testGoldenFixtures() {
        XCTAssertGreaterThanOrEqual(Self.fixtures.count, 120)
        for fixture in Self.fixtures {
            let tags = FoodTagger.tags(name: fixture.name, brand: fixture.brand, barcode: fixture.barcode)
            let missing = fixture.mustInclude.subtracting(tags)
            let unexpected = fixture.mustExclude.intersection(tags)
            XCTAssertTrue(missing.isEmpty, "\(fixture.name) [\(fixture.brand ?? "-")]: missing \(missing.sorted()) in \(tags.sorted())")
            XCTAssertTrue(unexpected.isEmpty, "\(fixture.name) [\(fixture.brand ?? "-")]: unexpected \(unexpected.sorted())")
        }
    }

    func testSpecScenarioKysaneZeli() {
        let tags = FoodTagger.tags(name: "Kysané zelí", brand: nil, barcode: nil)
        XCTAssertTrue(tags.isSuperset(of: [.fermented, .vegetable]))
    }

    func testSpecScenarioExclusionBeatsSimilarWord() {
        XCTAssertFalse(FoodTagger.tags(name: "Rybízový džem", brand: nil, barcode: nil).contains(.fish))
    }

    func testSpecScenarioCzechBrandByList() {
        let tags = FoodTagger.tags(name: "Kofola Original", brand: "Kofola", barcode: nil)
        XCTAssertTrue(tags.isSuperset(of: [.sugaryDrink, .czechBrand]))
    }

    func testSpecScenarioCzechBrandByBarcodeFallback() {
        XCTAssertTrue(FoodTagger.tags(name: "Neznámý výrobek", brand: nil, barcode: "8594001234567").contains(.czechBrand))
        XCTAssertFalse(FoodTagger.tags(name: "Neznámý výrobek", brand: "Nestlé", barcode: "8594001234567").contains(.czechBrand))
    }

    func testUntaggableFoodHasNoTags() {
        XCTAssertTrue(FoodTagger.tags(name: nil, brand: nil, barcode: nil).isEmpty)
        XCTAssertTrue(FoodTagger.tags(name: "", brand: nil, barcode: nil).isEmpty)
    }

    func testPhraseMatchesOnWholeTokensOnly() {
        let pivo = FoodTagPhrase("pivo")
        XCTAssertTrue(pivo.matches(SearchText.tokenize("Pivo světlé")))
        XCTAssertFalse(pivo.matches(SearchText.tokenize("Pivoňka")))
        let multi = FoodTagPhrase("kysan* zeli")
        XCTAssertTrue(multi.matches(SearchText.tokenize("Zelí kysané, kysané zelí")))
        XCTAssertFalse(multi.matches(SearchText.tokenize("Zelí kysané")))
    }

    func testWordPatternModes() {
        XCTAssertEqual(FoodTagWordPattern("=Pórek"), .exact("porek"))
        XCTAssertEqual(FoodTagWordPattern("Jahod*"), .prefix("jahod"))
        XCTAssertEqual(FoodTagWordPattern("ryba"), .stem(CzechLightStemmer.stem("ryba")))
    }

    func testRegistryListsEveryPlannedRuleSetOnce() {
        let ids = FoodTagRuleRegistry.all.map(\.id)
        XCTAssertEqual(ids, ["core", "seasonal", "collections", "sport"])
        XCTAssertFalse(FoodTagRuleSet.core.rules.isEmpty)
    }

    func testFoodTagRoundTripsByRawValueIncludingUnknownTags() throws {
        let tags: [FoodTag] = [.fish, FoodTag("seasonal.goose")]
        let data = try JSONEncoder().encode(tags)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"fish\",\"seasonal.goose\"]")
        XCTAssertEqual(try JSONDecoder().decode([FoodTag].self, from: data), tags)
    }
}
