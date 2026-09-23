// SearchRelevanceTests.swift
//
// The golden relevance suite (rebuild-food-search design.md D6, task 3.5):
// the acceptance test for every ranking weight in `SearchWeights`. The
// owner's #1 priority is finding foods, so "does search still find the
// right thing" is asserted here, in CI, with no network -- rather than
// discovered on the phone after a weight tweak.
//
// `fixtureTable` holds ~330 realistic candidates in the shapes the real
// sources produce (Garmin/FatSecret Czech-region names with brands, Open
// Food Facts names with pack sizes, English FatSecret generics, the
// user's own custom foods, and -- deliberately -- the unrelated garbage
// Garmin's own fuzzy search returned in the 2026-09-23 probes, e.g.
// "Prepared Squid [Rolin]" for "rohlik"). Every query runs against the
// WHOLE table through `SearchRanker.rank`, the same function the engine
// uses. Expectations prefer robust top-3 membership / "every top-3 row is
// about X" over brittle exact orderings, except where one answer is
// clearly the only right one.
//
// Row format -- fixtures: id|origin|name|brand|kcal per 100 g|aliases
//   origin: G = Garmin, O = Open Food Facts, L = a logged Garmin food from
//   the local library, C = a local custom food.
// Queries: query|kind:args, kinds:
//   top1:id  top3:id,id  top3all:stem  brandall:word  present:id  absent:id,id
//   below:a,b (a ranks above b)  merged:id=origin (id's row lists origin in
//   "also in")  empty
//
// Depends on FoodLogCore's SearchRanker/SearchText only.

import XCTest
@testable import FoodLogCore

final class SearchRelevanceTests: XCTestCase {
    private static let fixtureTable = """
    g-rohlik|G|Rohlík|Penam|290
    g-rohlik-tukovy|G|Rohlík tukový|Albert|305
    g-rohlik-celozrnny|G|Celozrnný rohlík|Penny|262
    o-rohliky-bonavita|O|Rohlíky Krehké Celozrné 250G Active|Bonavita|350
    o-rohlik-grahamovy|O|Grahamový rohlík 60 g|Globus|255
    g-houska|G|Houska|Penam|280
    o-houska-sezam|O|Houska se sezamem|Lidl|285
    g-chleb|G|Chléb|Penam|245
    g-chleb-zitny|G|Chléb Žitný|Globus|238
    g-chleb-kvaskovy|G|Chléb Kváskový Delikates|Tesco|250
    o-chleb-sumava|O|Šumava chléb konzumní|Penam|240
    o-chleb-toustovy|O|Toustový chléb světlý 500 g|Penny|265
    g-chleb-tostowy|G|chleb tostowy z mąką żytnią pełnoziarnistą|Lidl|250
    g-vanocka|G|Vánočka s rozinkami|Albert|360
    g-kolac-tvarohovy|G|Koláč tvarohový|Albert|320
    g-bageta|G|Bageta|Lidl|270
    o-krehky-chleb|O|Křehký chléb žitný|Wasa|334
    g-croissant|G|Croissant máslový|Albert|410
    g-kaiserka|G|Kaiserka|Albert|290
    g-perník|G|Perník s náplní|Albert|380
    g-tvaroh-madeta|G|Tvaroh|Madeta|63
    g-jihocesky-tvaroh|G|Jihočeský Tvaroh|Madeta|116
    o-jihocesky-tvaroh|O|Madeta Jihočeský tvaroh 250 g|Madeta|118
    g-tvaroh-odtucneny|G|Tvaroh Odtučněný|Madeta|63
    g-tvaroh-odtucneny-tatra|G|Tvaroh Odtučněný|Tatra|63
    g-tvaroh-pilos|G|Tvaroh|Pilos|86
    g-mekky-tvaroh|G|Měkký tvaroh|Pilos|90
    o-tvaroh-mekky-polotucny|O|Tvaroh měkký polotučný 250 g|K-Jarmark|96
    g-tvaroh-jemny|G|Tvaroh Jemný 2,5%|Pilos|95
    g-tvaroh-tvrdy|G|Tvaroh Tvrdý|Pilos|115
    g-tvoroh|G|Tvoroh|Albert|87
    o-tvaroh-podebrad|O|Tvaroh z Poděbrad polotučný|Milko|90
    o-tvaroh-a-jogurt|O|Tvaroh a jogurt||96
    c-domaci-tvaroh|C|Domácí tvaroh||110
    g-jogurt-bily-clever|G|Jogurt Bílý|Clever|64
    g-jogurt-bily-albert|G|Jogurt Bílý|Albert|66
    g-recky-jogurt-pilos|G|Řecký Jogurt Bílý|Pilos|57
    g-recky-jogurt-milko|G|Řecký Jogurt Bílý 0% Tuku|Milko|57
    o-bily-jogurt-kunin|O|Bílý jogurt|Kunín|108
    o-bily-jogurt-olma|O|Bily jogurt klasik|Olma|64
    g-jogurt-jahodovy|G|Jogurt Jahodový|Clever|106
    g-jogurt-broskev|G|Jogurt Broskev|Jarmark|95
    g-smetanovy-jogurt|G|Smetanový Jogurt Bílý|Ranko|121
    o-activia|O|Activia bílá|Danone|70
    g-yogurt|G|Yogurt||61
    g-greek-yogurt|G|Greek Yogurt||97
    g-fruit-yogurt|G|Fruit Variety Yogurt||99
    g-mleko-tatra|G|Mléko|Tatra|47
    g-mleko-polotucne|G|Mléko Polotučné|Madeta|47
    o-mleko-plnotucne|O|Čerstvé mléko plnotučné 1 l|K-Jarmark|64
    o-mleko-trvanlive|O|Trvanlivé mléko polotučné 1,5 %|Bohušovická mlékárna|46
    g-kefir-pilos|G|Kefírové Mléko|Pilos|56
    o-kefir-kunin|O|Kefírové mléko|Mlékárna Kunín|58|Kefir velky
    o-kefir-lifeway|O|Lifeway Kefir|Kefir|110
    g-acidko|G|Acidofilní mléko|Olma|52
    g-maslo|G|Máslo|Madeta|748
    g-maslo-tatra|G|Máslo 82%|Tatra|745
    g-pomazankove-maslo|G|Pomazánkové Máslo|Madeta|238
    g-eidam-pilos|G|Eidam|Pilos|350
    g-eidam-30|G|Eidam 30%|Albert|263
    g-eidam-platky|G|Eidam Plátky|Karlova Koruna|350
    o-eidam-45|O|Eidam 45% plátky 100 g|Milbona|356
    g-gouda|G|Gouda|Frico|356
    g-edam-cheese|G|Edam Cheese||357
    g-hermelin|G|Hermelín|Président|313
    g-niva|G|Niva|Madeta|334
    g-mozzarella|G|Mozzarella|Galbani|254
    g-cottage|G|Cottage Cheese|Pilos|98
    g-lucina|G|Lučina|Savencia|238
    g-zakysana-smetana|G|Zakysaná Smetana|Pilos|142
    g-smetana-slehani|G|Smetana ke šlehání 31%|Madeta|297
    g-syr-taveny|G|Tavený sýr|Veselá kráva|250
    g-syr-strouhany|G|Sýr strouhaný Eidam|Albert|350
    g-skyr-arla|G|Skyr|Arla|63
    o-skyr-danone|O|Skyr natur|Danone|60
    o-pribinacek|O|Pribináček vanilkový|Savencia|160
    o-lipanek|O|Lipánek|Madeta|135
    o-termix|O|Termix vanilkový|Savencia|190
    g-olomoucke-tvaruzky|G|Olomoucké Tvarůžky|A.W.|124
    g-kureci-prsa|G|Kuřecí Prsa|Vodňanské kuře|110
    g-kureci-prsni-rizek|G|Kuřecí Prsní Řízek|Albert|114
    g-kureci-sunka|G|Kuřecí Šunka|Albert|105
    g-kureci-prsni-sunka|G|Kuřecí Prsní Šunka|Lidl|99
    g-chicken-breast|G|Chicken Breast||165
    g-grilled-chicken|G|Grilled Chicken||190
    g-chicken-nuggets|G|Chicken Nuggets||296
    g-kure-cele|G|Kuře celé|Vodňanské kuře|215
    g-kureci-stehna|G|Kuřecí Stehna|Albert|190
    g-kureci-nugety|G|Kuřecí Nugety|Deli|250
    g-kruti-prsa|G|Krůtí Prsa|Albert|105
    g-sunka-veprova|G|Šunka Vepřová Výběrová|Kostelecké uzeniny|115
    g-sunka-dusena|G|Dušená šunka|Albert|120
    o-sunka-pro-deti|O|Sunka pro deti|Rohlik|109
    o-kruti-sunka|O|Kruti prsni sunka|Rohlik|89
    o-turkey-ham|O|Turkey Ham|Rohlik|89
    o-gorgonzola|O|Gorgonzola spoonable PDO|Rohlik|319
    o-carrot-cake|O|Carrot Cake|Rohlik|288
    o-nanuk|O|Jahodový nanuk|Rohlík|120
    o-tiramisu|O|Amaretto amore vegan tiramisu|The green garden&rohlik|294
    g-salam-herkules|G|Salám Herkules|Kostelecké uzeniny|480
    g-salam-vysocina|G|Salám Vysočina|Kostelecké uzeniny|460
    g-parky|G|Párky Jemné|Kostelecké uzeniny|260
    g-klobasa|G|Klobása|Albert|300
    g-slanina|G|Slanina Anglická|Albert|350
    g-hovezi-mlete|G|Hovězí Maso Mleté|Albert|200
    g-veprove-mlete|G|Vepřové Maso Mleté|Albert|250
    g-hovezi-gulas|G|Hovězí guláš|Hamé|120
    g-svickova|G|Svíčková na smetaně|Albert|150
    g-losos|G|Losos||208
    g-losos-uzeny|G|Uzený Losos|Albert|180
    g-tunak|G|Tuňák ve vlastní šťávě|Rio Mare|110
    g-vejce|G|Vejce||143
    g-vajicko|G|Vajíčko natvrdo||155
    g-vajeckova-pomazanka|G|Vajíčková Pomazánka|Albert|230
    g-pastika|G|Paštika Májka|Hamé|290
    g-sardinky|G|Sardinky v oleji|Albert|220
    g-rybi-prsty|G|Rybí Prsty|Iglo|200
    g-treska|G|Treska Filé|Albert|80
    g-kapr|G|Kapr||127
    g-pstruh|G|Pstruh Duhový||119
    g-banan|G|Banán||89
    g-bananas|G|Bananas||89
    g-banana|G|Banana||89
    o-banan-chiquita|O|Banán|Chiquita|90
    g-banan-chips|G|Banánové Chipsy|Albert|520
    g-banana-bread|G|Banana Bread||326
    g-jablko|G|Jablko||52
    g-jablko-gala|G|Jablko Gala||57
    g-hruska|G|Hruška||57
    g-pomeranc|G|Pomeranč||47
    g-mandarinka|G|Mandarinka||53
    g-jahody|G|Jahody||32
    g-boruvky|G|Borůvky||57
    g-maliny|G|Maliny||52
    g-hrozny|G|Hrozny||69
    g-kiwi|G|Kiwi||61
    g-ananas|G|Ananas||50
    g-mango|G|Mango||60
    g-broskev|G|Broskev||39
    g-svestky|G|Švestky||46
    g-tresne|G|Třešně||63
    g-citron|G|Citron||29
    g-meloun|G|Meloun vodní||30
    g-rajce|G|Rajče||18
    g-okurka|G|Okurka salátová||15
    g-okurky-sterilovane|G|Sterilované Okurky|Znojmia|30
    g-paprika|G|Paprika Červená||31
    g-mrkev|G|Mrkev||41
    g-brambory|G|Brambory vařené||77
    g-spenat|G|Špenát||23
    g-avokado|G|Avokádo||160
    g-cibule|G|Cibule||40
    g-cesnek|G|Česnek||149
    g-brokolice|G|Brokolice||34
    g-kvetak|G|Květák||25
    g-zeli|G|Zelí bílé||25
    g-kysane-zeli|G|Kysané Zelí|Hamé|20
    g-cuketa|G|Cuketa||17
    g-dyne|G|Dýně Hokkaido||40
    g-zampiony|G|Žampiony||22
    g-salat-hlavkovy|G|Hlávkový salát||14
    g-salat-vlassky|G|Vlašský salát|Albert|240
    g-salat-bramborovy|G|Bramborový salát|Albert|170
    g-hrasek|G|Hrášek zelený mražený|Iglo|81
    g-kukurice|G|Kukuřice sladká|Bonduelle|86
    g-fazole|G|Fazole v tomatě|Hamé|90
    g-cocka|G|Čočka|Lagris|350
    g-cizrna|G|Cizrna|Bonduelle|120
    g-tofu-uzene|G|Tofu uzené|Sunfood|160
    g-tofu|G|Tofu natural|Sunfood|120
    g-smoked-tofu|G|Smoked Tofu||160
    g-hummus|G|Hummus|Hummus Bar|250
    g-ovesne-vlocky|G|Ovesné Vločky|Emco|372
    g-ovesne-vlocky-jemne|G|Ovesné vločky jemné|Albert|370
    o-ovesna-kase|O|Ovesná kaše s jablky 65 g|Emco|380
    g-mysli|G|Mysli Čokoláda a Ořechy|Emco|450
    g-musli-ovocne|G|Müsli ovocné|Emco|360
    g-granola|G|Granola|Emco|470
    g-corn-flakes|G|Corn Flakes|Kellogg's|378
    g-kukuricne-lupinky|G|Kukuřičné Lupínky|Nestlé|380
    g-ryze|G|Rýže||130
    g-ryze-basmati|G|Rýže Basmati|Lagris|350
    g-jasmine-rice|G|Jasmine Rice||130
    g-rice-dressing|G|Rice Dressing||180
    g-testoviny|G|Těstoviny Penne|Barilla|359
    g-spagety|G|Špagety|Panzani|358
    g-kuskus|G|Kuskus|Lagris|376
    g-bulgur|G|Bulgur|Lagris|342
    g-quinoa|G|Quinoa||368
    g-pohanka|G|Pohanka|Lagris|343
    g-jahly|G|Jáhly|Lagris|378
    g-mouka-hladka|G|Hladká Mouka|Babiččina volba|340
    g-knedlik|G|Houskový Knedlík|Albert|230
    g-knedliky-bramborove|G|Bramborové Knedlíky|Albert|180
    g-med|G|Med květový|Medokomerc|330
    g-dzem|G|Džem Jahodový|Hamé|250
    g-cukr|G|Cukr krupice|Korunní|400
    g-olej|G|Olivový Olej|Albert|884
    g-horcice|G|Hořčice plnotučná|Kand|110
    g-kecup|G|Kečup jemný|Hellmann's|110
    g-majoneza|G|Majonéza|Hellmann's|680
    g-cokolada-horka|G|Čokoláda Hořká 70%|Orion|580
    g-cokolada-mlecna|G|Mléčná Čokoláda|Milka|530
    g-studentska|G|Studentská Pečeť|Orion|500
    g-nutella|G|Nutella|Ferrero|539
    g-susenky-bebe|G|Sušenky Bebe|Opavia|450
    g-tatranka|G|Tatranka Oříšková|Opavia|520
    g-horalky|G|Horalky|Sedita|520
    g-kinder-bueno|G|Kinder Bueno|Ferrero|572
    g-tycinka|G|Proteinová Tyčinka|Nutrend|380
    g-whey|G|Just Whey Salted Caramel|Nutrend|380
    g-orechy|G|Vlašské Ořechy||654
    g-kesu|G|Kešu Ořechy||553
    g-cashew|G|Cashew Nuts||553
    g-arasidy|G|Arašídy Pražené Solené|Albert|600
    g-mandle|G|Mandle||579
    g-chipsy|G|Chipsy Solené|Bohemia|540
    g-tycinky-solene|G|Tyčinky Solené|Bohemia|400
    g-kava|G|Káva s Mlékem||40
    g-caj|G|Čaj Zelený|Teekanne|1
    g-pivo|G|Pivo Ležák|Pilsner Urquell|43
    g-kofola|G|Kofola Original|Kofola|32
    g-dzus|G|Pomerančový Džus|Relax|45
    g-coca-cola|G|Coca-Cola|Coca-Cola|42
    g-coca-cola-zero|G|Coca-Cola Zero|Coca-Cola|0
    g-mattoni|G|Mattoni Neperlivá|Mattoni|0
    g-birell|G|Birell Světlý|Pilsner Urquell|20
    g-red-bull|G|Red Bull|Red Bull|45
    g-pizza|G|Pizza Margherita|Dr. Oetker|240
    g-rizek-veprovy|G|Vepřový Řízek||280
    g-smazeny-syr|G|Smažený Sýr||330
    g-polevka-cesnekova|G|Česneková Polévka||60
    g-polevka-gulasova|G|Gulášová Polévka|Knorr|50
    g-halusky|G|Brynzové Halušky||200
    g-bramboraky|G|Bramboráky||250
    g-livance|G|Lívance||230
    g-palacinky|G|Palačinky||227
    g-vetrnik|G|Větrník||380
    g-kremrole|G|Kremrole||420
    c-ovesna-kase|C|Ranní ovesná kaše s banánem||160
    c-babiccin-kolac|C|Babiččin koláč||350
    c-protein-shake|C|Proteinový shake po běhu||120
    l-recky-jogurt|L|Řecký Jogurt|Milko|60
    l-ovesne-vlocky|L|Ovesné Vločky|Emco|372
    g-squid-rolin|G|Prepared Squid|Rolin|90
    g-instant-oatmeal|G|Instant Oatmeal|Rollin' Oats|370
    g-heirloom-potatoes|G|Farmers Market Heirloom Potatoes|Roli Roti|80
    g-bone-broth|G|Chicken Bone Broth|Roli Roti|20
    g-cheese-dvaro|G|Cheese|Dvaro|300
    g-carrot-sticks|G|Carrot Sticks|Taro Brand|35
    g-poi|G|Poi|Taro Brand|112
    g-pure-organifi|G|Pure|Organifi|300
    g-pedia-sure|G|Pedia Sure|Pedia Sure|100
    g-skyr-lidl|G|Skyr|Lidl|62
    g-big-sur|G|Big Sur|Pizza My Heart|260
    g-syrup|G|Syrup||260
    g-syrniki|G|Syrniki||220
    g-maseca|G|Corn Flour|Maseca|360
    g-salsa-queso|G|Salsa Con Queso|Casa Mamita|110
    g-whole-milk|G|Whole Milk||61
    g-skim-milk|G|Skim Milk||34
    g-butter|G|Butter||717
    g-peanut-butter|G|Peanut Butter||588
    g-oatmeal|G|Oatmeal||68
    g-cheddar|G|Cheddar Cheese||403
    g-beef-burger|G|Beef Burger||250
    g-french-fries|G|French Fries||312
    g-hranolky|G|Hranolky|McCain|150
    g-hamburger|G|Hamburger|McDonald's|250
    g-apple|G|Apple||52
    g-orange-juice|G|Orange Juice||45
    g-white-bread|G|White Bread||265
    g-rye-bread|G|Rye Bread||259
    g-bread-roll|G|Bread Roll||290
    g-ham|G|Ham||145
    g-salami|G|Salami||336
    g-eggs|G|Eggs||143
    g-cream-cheese|G|Cream Cheese||342
    g-sour-cream|G|Sour Cream||198
    g-honey|G|Honey||304
    g-jam|G|Strawberry Jam||250
    o-hummus-cizrna|O|Cizrnová pomazánka hummus 200 g|Albert|280
    o-tatarska|O|Tatarská omáčka|Hellmann's|500
    o-rama|O|Rama Classic|Rama|530
    o-brambury|O|Brambůrky solené 60 g|Bohemia|540
    o-rakvicka|O|Rakvička se šlehačkou|Pekárna Kabát|300
    o-spicka|O|Špička kakaová|Pekárna Kabát|410
    o-buchty|O|Buchty s povidly|Albert|320
    o-kolacky|O|Koláčky makové|Penam|380
    o-venecek|O|Věneček|Pekárna Kabát|350
    o-mattoni-cit|O|Mattoni citron 1,5 l|Mattoni|10
    o-rajec|O|Rajec neperlivá|Kofola|0
    o-kozel|O|Kozel 11 světlý|Velkopopovický Kozel|40
    o-gambrinus|O|Gambrinus Originál 10|Plzeňský Prazdroj|35
    o-radegast|O|Radegast Ryze Hořká 12|Radegast|44
    o-budvar|O|Budweiser Budvar B:Original|Budějovický Budvar|42
    o-bernard|O|Bernard světlý ležák|Bernard|43
    o-semtex|O|Semtex Original|Kofola|46
    o-melounovy|O|Melounový sirup|Jupí|250
    o-cini-minis|O|Cini Minis|Nestlé|411
    o-lupinky|O|Kukuřičné lupínky 375 g|Albert|380
    o-chlebicky|O|Rýžové chlebíčky natural|Bonavita|380
    o-krupky|O|Pohankové krupky|Lagris|343
    o-kroupy|O|Kroupy|Lagris|350
    o-polenta|O|Polenta|Lagris|360
    o-polohruba|O|Polohrubá mouka|Babiččina volba|340
    o-celozrnna-mouka|O|Celozrnná pšeničná mouka|Albert|330
    o-tempeh|O|Tempeh natural|Sunfood|190
    o-avokado-pomazanka|O|Avokádová pomazánka|Albert|250
    o-rybi-pomazanka|O|Rybí pomazánka|Albert|240
    o-pangasius|O|Pangasius filé|Albert|90
    o-krevety|O|Krevety loupané|Albert|80
    o-hlíva|O|Hlíva ústřičná|Albert|33
    o-rukola|O|Rukola|Albert|25
    o-polnicek|O|Polníček|Albert|21
    o-celer|O|Celer bulvový|Albert|42
    o-kedlubna|O|Kedlubna|Albert|27
    o-redkvicky|O|Ředkvičky|Albert|16
    o-porek|O|Pórek|Albert|31
    o-lilek|O|Lilek|Albert|25
    o-grapefruit|O|Grapefruit|Albert|42
    o-limetka|O|Limetka|Albert|30
    o-meruňky|O|Meruňky sušené|Albert|241
    o-visne|O|Višně kompotované|Hamé|80
    o-rozinky|O|Rozinky|Albert|299
    o-datle|O|Datle sušené|Albert|282
    """

    private static let queryTable = """
    rohliky|top1:g-rohlik
    rohliky|top3all:rohlik
    rohliky|absent:g-squid-rolin,g-instant-oatmeal,g-heirloom-potatoes
    rohliky|below:o-rohlik-grahamovy,o-turkey-ham
    rohlik|top1:g-rohlik
    rohlík|top1:g-rohlik
    ROHLÍK|top1:g-rohlik
    rohl|top3all:rohlik
    tvaroh mekky|top3:g-mekky-tvaroh
    tvaroh me|top3:g-mekky-tvaroh
    mekky tvaroh|top1:g-mekky-tvaroh
    tvaroh|top3all:tvaroh
    tvaroh|present:c-domaci-tvaroh
    tvaroh|absent:g-cheese-dvaro,g-carrot-sticks,g-poi
    domaci tvaroh|top1:c-domaci-tvaroh
    tvaroh odtucneny|top3:g-tvaroh-odtucneny
    jihocesky tvaroh|top1:g-jihocesky-tvaroh
    jihocesky tvaroh|merged:g-jihocesky-tvaroh=openFoodFacts
    bily jogurt|top3all:jogurt
    bily jogurt|top3:g-jogurt-bily-clever
    jogurt bily|top3:g-jogurt-bily-clever
    jogurt|top3all:jogurt
    jgourt|top3all:jogurt
    yogurt|top3:g-yogurt,g-greek-yogurt
    banan|top3:g-banan
    bnan|top3:g-banan
    banán|top3:g-banan,o-banan-chiquita
    chlba|top3:g-chleb
    chleba|top3all:chlb
    chleb|top1:g-chleb
    kure prsa|top1:g-kureci-prsa
    kureci prsa|top1:g-kureci-prsa
    kure|top3all:kur
    kureci sunka|top1:g-kureci-sunka
    madeta|brandall:madeta
    mleko|top3:g-mleko-tatra
    mléko polotučné|top1:g-mleko-polotucne
    kefir|top3:g-kefir-pilos,o-kefir-kunin
    eidam|top3all:eidam
    eidam 30|top1:g-eidam-30
    sunka|top3all:sunk
    ovesne vlocky|top1:l-ovesne-vlocky
    ovesne vlocky|merged:l-ovesne-vlocky=garmin
    vlocky|top1:l-ovesne-vlocky
    ovesna kase|top3:o-ovesna-kase,c-ovesna-kase
    musli|top1:g-musli-ovocne
    chicken breast|top1:g-chicken-breast
    jasmine rice|top1:g-jasmine-rice
    ryze|top1:g-ryze
    spagety|top1:g-spagety
    testoviny|top1:g-testoviny
    horka cokolada|top1:g-cokolada-horka
    cokolada|top3all:cokolad
    vlassky salat|top1:g-salat-vlassky
    salam|top3:g-salam-herkules,g-salam-vysocina
    salam|below:g-salami,g-salat-vlassky
    coca cola zero|top1:g-coca-cola-zero
    kofola|top1:g-kofola
    hermelin|top1:g-hermelin
    pribinacek|top1:o-pribinacek
    smazeny syr|top1:g-smazeny-syr
    syr|top3all:syr
    xyzzy|empty
    qwrtp zzkx|empty
    """

    private static let candidates: [SearchCandidate] = SearchRelevanceTests.fixtureTable
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map(SearchRelevanceTests.candidate(from:))

    private static func candidate(from line: String) -> SearchCandidate {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        precondition(parts.count >= 5, "Malformed fixture row: \(line)")
        let origin: SearchOrigin
        let source: FoodSource
        switch parts[1] {
        case "G": origin = .garmin; source = .fatSecret
        case "O": origin = .openFoodFacts; source = .openFoodFacts
        case "L": origin = .local; source = .fatSecret
        case "C": origin = .local; source = .custom
        default: preconditionFailure("Unknown origin in fixture row: \(line)")
        }
        let food = Food(
            id: parts[0],
            name: parts[2],
            brandName: parts[3].isEmpty ? nil : parts[3],
            source: source,
            servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100, calories: Double(parts[4]))]
        )
        let aliases = parts.count > 5 ? parts[5].split(separator: ";").map(String.init) : []
        return SearchCandidate(food: food, origin: origin, alternateNames: aliases)
    }

    private struct GoldenQuery {
        let query: String
        let kind: String
        let arguments: [String]
    }

    private static let queries: [GoldenQuery] = SearchRelevanceTests.queryTable
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            let expectation = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            let arguments = expectation.count > 1 ? expectation[1].split(separator: ",").map(String.init) : []
            return GoldenQuery(query: parts[0], kind: expectation[0], arguments: arguments)
        }

    func testTheSuiteIsAsLargeAsDesignD6Requires() {
        XCTAssertGreaterThanOrEqual(Self.candidates.count, 300)
        XCTAssertGreaterThanOrEqual(Set(Self.queries.map(\.query)).count, 30)
        XCTAssertEqual(Set(Self.candidates.map(\.food.id)).count, Self.candidates.count, "fixture ids must be unique")
    }

    func testEveryGoldenQuery() {
        for golden in Self.queries {
            let results = SearchRanker.rank(SearchQuery(golden.query), candidates: Self.candidates)
            let passed = Self.check(golden, results)
            let top = results.prefix(5).map { "\($0.food.id) \(String(format: "%.3f", $0.score))" }.joined(separator: ", ")
            XCTAssertTrue(passed, "\"\(golden.query)\" expected \(golden.kind):\(golden.arguments.joined(separator: ",")) -- got [\(top)]")
        }
    }

    private static func check(_ golden: GoldenQuery, _ results: [SearchResult]) -> Bool {
        let ids = results.map(\.food.id)
        let top3 = Array(results.prefix(3))
        let arguments = golden.arguments
        switch golden.kind {
        case "top1":
            return ids.first == arguments.first
        case "top3":
            return arguments.allSatisfy { id in top3.contains { $0.food.id == id } }
        case "top3all":
            guard let stem = arguments.first else { return false }
            return top3.count == 3 && top3.allSatisfy { result in
                SearchText.tokenize(result.food.name).contains { $0.stem == stem || $0.text == stem }
            }
        case "brandall":
            guard let word = arguments.first else { return false }
            return top3.count == 3 && top3.allSatisfy { result in
                SearchText.tokenize(result.food.brandName ?? "").contains { $0.text == word }
            }
        case "present":
            return arguments.allSatisfy { ids.contains($0) }
        case "absent":
            return arguments.allSatisfy { !ids.contains($0) }
        case "below":
            guard arguments.count == 2,
                  let upper = ids.firstIndex(of: arguments[0]),
                  let lower = ids.firstIndex(of: arguments[1]) else { return false }
            return upper < lower
        case "merged":
            let pair = (arguments.first ?? "").split(separator: "=").map(String.init)
            guard pair.count == 2, let origin = SearchOrigin(rawValue: pair[1]) else { return false }
            return results.first { $0.food.id == pair[0] }?.alsoIn.contains(origin) ?? false
        case "empty":
            return results.isEmpty
        default:
            XCTFail("Unknown golden expectation kind \(golden.kind)")
            return false
        }
    }

    // MARK: - Spec scenarios that need more than a single ranking call

    /// food-catalog spec "Usual yogurt first": two equally matching
    /// yogurts, one logged 10 times last month.
    func testTheYogurtTheUserLogsOftenRanksFirst() {
        let now = Date()
        let events = (0..<10).map { day in
            UsageEvent(foodId: "g-jogurt-jahodovy", servingId: "100g", numberOfUnits: 1, timestamp: now.addingTimeInterval(-Double(day + 1) * 86_400 * 3))
        }
        let personal = SearchPersonalContext.build(events: events, favoriteFoodIds: [], now: now)

        let results = SearchRanker.rank(SearchQuery("jogurt"), candidates: Self.candidates, personal: personal)

        XCTAssertEqual(results.first?.food.id, "g-jogurt-jahodovy")
    }

    /// The personal boost scales with the text match, so a food eaten daily
    /// can't drag a half-matching name above a full match.
    func testHeavyUsageDoesNotLiftAHalfMatchAboveAFullMatch() {
        let now = Date()
        let events = (0..<30).map { day in
            UsageEvent(foodId: "g-tvaroh-pilos", servingId: "100g", numberOfUnits: 1, timestamp: now.addingTimeInterval(-Double(day) * 86_400))
        }
        let personal = SearchPersonalContext.build(events: events, favoriteFoodIds: [], now: now)

        let results = SearchRanker.rank(SearchQuery("tvaroh mekky"), candidates: Self.candidates, personal: personal)
        let ids = results.map(\.food.id)

        guard let full = ids.firstIndex(of: "g-mekky-tvaroh"), let half = ids.firstIndex(of: "g-tvaroh-pilos") else {
            return XCTFail("both tvarohy should be in the results: \(ids.prefix(8))")
        }
        XCTAssertLessThan(full, half)
    }

    /// czech-food-catalog spec "Czech-only name field": an OFF product whose
    /// displayed Czech name is "Kefírové mléko" matches "kefir" (stemmed
    /// "kefírové" -> "kefir").
    func testCzechNamedOpenFoodFactsProductMatchesKefir() {
        let results = SearchRanker.rank(SearchQuery("kefir"), candidates: Self.candidates)
        XCTAssertTrue(results.prefix(3).contains { $0.food.id == "o-kefir-kunin" })
    }
}
