// FoodTagRules+Core.swift
//
// The core keyword dictionary (design D1/D2): food groups, drinks, produce
// colours, cuisines -- the tags more than one gamification feature needs.
// Czech first (the owner logs Czech foods: "Kysané zelí", "Svíčková"),
// English second (Garmin/FatSecret names are often English).
//
// Phrase syntax (see FoodTagRule.swift): "ryba" = stem match, "jahod*" =
// folded prefix, "=porek" = exact folded word; words are written without
// diacritics. Exclusions veto a whole rule, which is why flavoured
// products ("jahodový jogurt", "pomerančový džus") are excluded from the
// produce and colour rules -- a strawberry yoghurt is not a portion of
// fruit.
//
// Every entry here is exercised by FoodTaggerTests' golden fixtures; when
// the owner reports a mis-tag, add the fixture there first, then fix the
// rule. Keyword tagging is knowingly imperfect (design "Risks"): a wrong
// tag costs a bingo square, never data.

import Foundation

extension FoodTagRuleSet {
    public static let core = FoodTagRuleSet(id: "core", rules: FoodTagRuleSet.coreRules)

    static let coreRules: [FoodTagRule] = [
        FoodTagRule(
            tags: [.fruit],
            anyPhrases: [
                "jablk*", "jablic*", "jablec*", "apple*", "hrusk*", "pear", "pears", "banan*", "pomeranc*",
                "orange", "oranges", "mandarink*", "mandarin*", "klementink*", "citron*", "lemon*", "limet*",
                "grapefruit*", "jahod*", "strawberr*", "malin*", "raspberr*", "boruvk*", "blueberr*",
                "bruslin*", "cranberr*", "tresn*", "visn*", "cherr*", "svestk*", "plum", "plums", "merunk*",
                "apricot*", "broskev", "broskv*", "peach*", "nektarink*", "nectarin*", "hrozn*", "grape",
                "kiwi", "mango", "manga", "ananas*", "pineapple*", "meloun*", "melon*", "watermelon*",
                "avokad*", "avocado*", "datle", "datl*", "fik", "fiky", "fig", "figs", "rybiz*", "currant*",
                "angrest*", "ostruzin*", "blackberr*", "rozink*", "raisin*", "ovoce", "fruit", "fruits",
                "granatov* jablk*", "pomegranate*", "papaj*", "papaya", "kaki", "liči", "lici", "lychee*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure"
            ]
        ),
        FoodTagRule(
            tags: [.vegetable],
            anyPhrases: [
                "zelenin*", "vegetable*", "veggie*", "mrkev", "mrkv*", "carrot*", "rajc*", "tomat*",
                "paprik*", "bell pepper*", "okurk*", "cucumber*", "zeli", "kapust*", "kale", "cabbage*",
                "kvetak*", "cauliflower*", "brokolic*", "broccoli", "spenat*", "spinach*", "cibul*",
                "onion*", "cesnek", "cesnak*", "garlic*", "cuket*", "cukin*", "zucchin*", "courgette*",
                "lilek", "lilk*", "eggplant*", "aubergin*", "dyne", "dyn*", "pumpkin*", "hrasek", "hrask*",
                "cervena repa", "cervene repy", "cvikl*", "beetroot*", "redkvick*", "radish*", "celer*",
                "=porek", "=porku", "leek*", "rukol*", "arugula", "chrest*", "asparag*", "houb*", "zampion*",
                "mushroom*", "fazolk*", "green bean*", "kedluben*", "kohlrabi", "pastinak*", "parsnip*",
                "fenykl*", "fennel", "batat*", "sweet potato*", "polnick*", "pak choi", "kukuric*",
                "sweetcorn"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "kecup*", "ketchup", "chips*",
                "lupin*", "flakes", "vinaigrette", "sadlo"
            ]
        ),
        FoodTagRule(
            tags: [.vegetable, .colourGreen],
            anyPhrases: [
                "salat*", "salad*", "lettuce*"
            ],
            excludePhrases: [
                "vlassk*", "bramborov*", "potato*", "ovocn*", "fruit*", "testovin*", "pasta", "vajeckov*",
                "majonez*", "tunakov*", "=tuna", "coleslaw", "caesar"
            ]
        ),
        FoodTagRule(
            tags: [.fish],
            anyPhrases: [
                "ryba", "ryby", "rybi", "rybu", "rybou", "fish*", "losos*", "salmon*", "tunak*", "=tuna",
                "kapr", "kapra", "kapri", "kaprem", "kaprik*", "carp", "pstruh*", "trout", "tresk*", "=cod",
                "makrel*", "mackerel", "sled", "sledi", "slede", "sledu", "herring*", "sardink*", "sardin*",
                "pangas*", "tilapi*", "=hejk", "zavinac*", "ancovick*", "anchov*", "candat*", "halibut*",
                "platyz*", "okoun*", "stik*", "=sumec", "surimi"
            ],
            excludePhrases: [
                "rybiz*", "fish sauce", "rybi omack*"
            ]
        ),
        FoodTagRule(
            tags: [.seafood],
            anyPhrases: [
                "kreve*", "shrimp*", "prawn*", "morsk* plod*", "seafood", "chobotnic*", "octopus",
                "kalamar*", "squid", "slavk*", "mussel*", "ustric*", "oyster*", "=krab", "=krabi", "crab",
                "crabs", "surimi", "lobster*", "humr*", "scallop*"
            ]
        ),
        FoodTagRule(
            tags: [.meat],
            anyPhrases: [
                "maso", "masa", "masem", "masove", "masovy", "masova", "meat", "meats", "salam*", "salami",
                "klobas*", "sausage*", "parek", "parky", "parku", "parkem", "frankfurt*", "rizek", "rizky",
                "rizku", "schnitzel*", "sekan*", "meatloaf", "kebab*", "kebap*", "gyros", "doner", "uzenin*",
                "uzen* maso", "tlacenk*", "jatr*", "liver*", "pastik*", "pastet*", "pate", "karbanatek",
                "karbanatk*", "meatball*", "prosciutto", "pepperoni", "chorizo", "jamon", "serrano",
                "burger*", "hamburger*", "cheeseburger*", "hot dog*", "hotdog*", "wiener*", "cevap*",
                "gulas*", "goulash"
            ],
            excludePhrases: [
                "vege*", "vegan*", "bezmas*", "sojov*", "soy*", "tofu", "rostlinn*", "plant based",
                "veggie*", "vegetarian*", "seitan"
            ]
        ),
        FoodTagRule(
            tags: [.meat, .redMeat],
            anyPhrases: [
                "hovez*", "beef", "veprov*", "vepro", "=pork", "telec*", "veal", "jehne*", "lamb", "skopov*",
                "mutton", "zverin*", "venison", "jelen*", "srnc*", "divocak*", "kanci", "svickov*", "gulas*",
                "goulash", "steak*", "burger*", "hamburger*", "cheeseburger*", "krkovic*", "bucek", "buck*",
                "zebirk*", "ribs", "kotlet*", "slanin*", "bacon", "sunk*", "=ham", "salam*", "salami",
                "klobas*", "sausage*", "chorizo", "pepperoni", "prosciutto", "jamon", "serrano", "tlacenk*",
                "roastbeef", "rostenk*", "biftek*", "tatarak*", "tartar*", "sekan*", "cevap*", "kabanos*"
            ],
            excludePhrases: [
                "vege*", "vegan*", "bezmas*", "sojov*", "soy*", "tofu", "rostlinn*", "plant based",
                "veggie*", "vegetarian*", "seitan", "kure", "kruti", "kruta", "krutich", "chicken*",
                "turkey*", "drubez*", "kachn*", "husi", "husa", "ryb*", "tunak*", "losos*", "=tuna",
                "salmon*"
            ]
        ),
        FoodTagRule(
            tags: [.meat, .poultry],
            anyPhrases: [
                "kure", "chicken*", "kruti", "kruta", "krutich", "krutim", "turkey*", "kachn*", "duck*",
                "husa", "husi", "husu", "goose", "slepic*", "drubez*", "poultry", "nugget*", "=wings",
                "kridelk*", "kridla"
            ],
            excludePhrases: [
                "vege*", "vegan*", "sojov*", "soy*", "tofu", "rostlinn*", "plant based", "veggie*",
                "vegetarian*", "seitan", "vyvar*", "bujon*", "stock cube*", "husten*"
            ]
        ),
        FoodTagRule(
            tags: [.egg],
            anyPhrases: [
                "vejce", "vajec", "vajic*", "vajec*", "egg", "eggs", "omelet*", "omeleta", "frittat*",
                "shakshuka", "saksuk*", "hemenex*", "benedikt*"
            ],
            excludePhrases: [
                "testovin*", "nudl*", "eggplant*", "pasta", "vajecny likér", "vajecny liker",
                "vajecn* liker*", "kinder", "=vajecne", "=vajecnych", "=vajecnymi", "cokolad*",
                "velikonoc* vajic* cokol*"
            ]
        ),
        FoodTagRule(
            tags: [.dairy],
            anyPhrases: [
                "mleko", "mleka", "mlekem", "mlecn*", "milk", "tvaroh*", "quark", "smetan*", "cream",
                "kefir*", "podmasl*", "acidofil*", "skyr", "maslo", "masla", "maslem", "butter", "zakys*",
                "pribinac*", "lassi", "cottage", "ricott*", "mascarpone", "gervais", "lucin*", "ayran",
                "kysan* mlek*", "latte", "cappuccino", "kapucin*", "bilý jogurt", "whey", "syrovatk*"
            ],
            excludePhrases: [
                "cokolad*", "chocolate*", "kokos*", "mandlov*", "almond*", "sojov*", "soy*", "rostlinn*",
                "ovesn* napoj*", "oat milk", "ovesn* mlek*", "ryzov* napoj*", "ice cream", "peanut*",
                "arasidov*", "=sour", "arasid*", "cream cheese", "zmrzlin*", "susenk*", "cookie*"
            ]
        ),
        FoodTagRule(
            tags: [.dairy, .fermented],
            anyPhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "kefir*", "skyr", "zakys*", "acidofil*", "podmasl*",
                "lassi", "ayran", "kysan* mlek*", "kysan* smetan*", "sour cream"
            ],
            excludePhrases: [
                "sojov*", "soy*", "kokos*", "rostlinn*", "vegan*", "ovesn*", "mandlov*", "coconut*",
                "almond*"
            ]
        ),
        FoodTagRule(
            tags: [.dairy, .cheese],
            anyPhrases: [
                "=syr", "=syra", "=syru", "=syry", "=syrem", "=syrech", "cheese*", "mozzarell*", "parmazan*",
                "parmesan*", "parmigian*", "eidam*", "edam*", "gouda", "ementa*", "emmental*", "cheddar*",
                "hermelin*", "niva", "nivy", "feta", "fety", "brynz*", "tvaruzk*", "syrec*", "camembert*",
                "brie", "gorgonzol*", "roquefort", "halloumi", "grana padano", "pecorino", "gruyere",
                "raclett*", "mascarpone", "ricott*", "cottage", "cream cheese", "cheeseburger*", "smazak",
                "korbacik*", "paneer", "manchego", "maasdam*", "gran moravia", "blaticko"
            ],
            excludePhrases: [
                "vegan*", "rostlinn*", "cheesecake*", "ricotta sirup"
            ]
        ),
        FoodTagRule(
            tags: [.fermented],
            anyPhrases: [
                "kysan*", "kimchi", "kombuch*", "miso", "tempeh", "sauerkraut", "kvas", "natto", "kvaskov*",
                "sourdough"
            ],
            excludePhrases: [
                "kysanik"
            ]
        ),
        FoodTagRule(
            tags: [.legume],
            anyPhrases: [
                "fazol*", "bean", "beans", "cocka", "lentil*", "cizrn*", "chickpea*", "hummus", "humus",
                "hrach*", "hrasek", "hrask*", "peas", "pea", "soja", "sojov* bob*", "soybean*", "tofu",
                "tempeh", "edamame", "falafel*", "dal", "dhal", "daal", "mungo", "adzuki", "vigna", "lupin",
                "lentilky zluta"
            ],
            excludePhrases: [
                "kavov* zrn*", "coffee*", "kakaov*", "cocoa*", "jelly*", "vanilk*", "vanilla*",
                "sojov* omack*", "soy sauce", "lentilk*", "=lentilky"
            ]
        ),
        FoodTagRule(
            tags: [.nuts],
            anyPhrases: [
                "orech*", "orisk*", "nut", "nuts", "mandle", "mandli", "mandlem", "mandlov*", "almond*",
                "kesu", "kešu", "cashew*", "pistac*", "pistachi*", "lisk*", "hazelnut*", "walnut*",
                "peanut*", "arasid*", "burak*", "pekan*", "pecan*", "makadam*", "macadamia*", "pinie*",
                "pine nut*", "para orech*", "brazil nut*", "nutella", "studentsk* smes*"
            ],
            excludePhrases: [
                "muskat*", "nutmeg", "kokos*", "coconut*", "burak cukrov*"
            ]
        ),
        FoodTagRule(
            tags: [.wholeGrain],
            anyPhrases: [
                "celozrn*", "wholegrain*", "whole grain*", "wholemeal", "whole wheat", "vlock*", "oves*",
                "oat", "oats", "oatmeal", "porridge", "kase ovesn*", "musli*", "muesli*", "granol*",
                "pohank*", "buckwheat", "quinoa", "kvinoa", "bulgur*", "jahl*", "millet", "hneda ryze",
                "natural* ryze", "brown rice", "graham*", "spald*", "spelt", "amarant*", "psenic* klic*",
                "otrub*", "bran", "knackebrot", "kvaskovy chleb zitny", "zitn* celozr*", "chia",
                "lnene seminko"
            ],
            excludePhrases: [
                "vlock* kukuric*", "cornflakes", "oves* napoj*", "oat milk", "ovesn* mlek*",
                "bramborov* vlock*", "kokosov* vlock*", "coconut flakes", "=vlocky cokoladove",
                "cokoladov* musli*", "cookie*", "susenk*", "tycink* cokolad*"
            ]
        ),
        FoodTagRule(
            tags: [.soup],
            anyPhrases: [
                "polevk*", "soup*", "vyvar*", "broth", "kulajd*", "gulasovk*", "bramboracka", "bramborack*",
                "cesnecka", "cesneck*", "drstkov*", "minestron*", "ramen", "=pho", "gazpacho", "bujon*",
                "kyselo", "zelnacka", "zelnack*", "borsc*", "borscht", "vyvarem", "krem z", "chowder",
                "bouillabaisse", "tom yum", "tom kha", "miso polevk*", "cockovk*", "fazolack*", "hrachovk*",
                "rajsk* polevk*", "frankfurtsk* polevk*", "dršťková"
            ],
            excludePhrases: [
                "=vyvarova", "bujon* kostk*", "stock cube*", "polevkov* koren*", "koreni", "=soup cube"
            ]
        ),
        FoodTagRule(
            tags: [.coffee],
            anyPhrases: [
                "kava", "kavu", "kavou", "kavy", "coffee*", "espresso*", "presso", "cappuccino", "kapucin*",
                "latte", "americano", "flat white", "lungo", "ristretto", "macchiato", "frappe",
                "frappuccino", "mocha", "moka", "cafe", "caffe", "cold brew", "turek", "vidensk* kava",
                "ledov* kav*", "iced coffee", "instantni kava", "nescafe", "kavov* napoj*"
            ],
            excludePhrases: [
                "zmrzlin*", "ice cream", "dort*", "cake*", "cokolad*", "chocolate*", "tiramisu", "susenk*",
                "cookie*", "=kavovina", "cigor*", "bonbon*", "=latte macchiato jogurt", "jogurt*", "yogurt*",
                "kavov* zrn* v cokol*"
            ]
        ),
        FoodTagRule(
            tags: [.tea],
            anyPhrases: [
                "caj*", "tea", "teas", "matcha", "rooibos", "earl grey", "chai", "green tea", "herbal tea",
                "maté", "yerba*", "kombuch*", "ledov* caj*", "iced tea", "ice tea", "lipton", "pickwick",
                "teekanne", "infuze", "odvar", "maty caj"
            ],
            excludePhrases: [
                "cajov* pecivo", "cajov* susenk*", "cajov* salam*", "=cajovy salam", "sušenk*", "tea cake*",
                "tea biscuit*", "teacake*", "chai seed*", "chia"
            ]
        ),
        FoodTagRule(
            tags: [.sugaryDrink],
            anyPhrases: [
                "kofol*", "cola", "coca cola", "pepsi", "fanta", "sprite", "limonad*", "lemonade", "sirup*",
                "dzus*", "juice*", "nektar", "energy drink*", "energetick* napoj*", "red bull", "redbull",
                "monster energy", "=monster", "ice tea", "iced tea", "ledov* caj*", "tonic", "tonik",
                "mountain dew", "7up", "mirinda", "schweppes", "vinea", "top topic", "capri sun",
                "caprisonne", "cappy", "rauch", "hello", "relax dzus*", "big shock", "milkshake*", "frappe",
                "frappuccino", "soda", "sladk* napoj*", "soft drink*", "lipton ice", "fuze tea", "fuzetea",
                "mattoni s prichut*", "aquila s prichut*", "birell ochucen*", "kinley", "bubble tea",
                "slush*", "ledova trist"
            ],
            excludePhrases: [
                "zero", "light", "bez cukr*", "sugar free", "sugarfree", "no sugar", "diet*", "=max",
                "neslazen*", "unsweetened", "sodastream bez", "soda water", "sodovk*", "club soda",
                "=bez cukru", "sirup bez", "stevi*"
            ]
        ),
        FoodTagRule(
            tags: [.alcohol, .beer],
            anyPhrases: [
                "pivo", "piva", "pivem", "pivu", "beer*", "lezak*", "lager*", "=ale", "=ipa", "=apa",
                "stout", "porter", "pilsner*", "prazdroj*", "radegast", "kozel", "gambrinus", "staropramen",
                "budvar", "budweiser", "velkopopovick*", "bernard", "krusovic*", "svijan*", "branik",
                "desitk*", "dvanactk*", "jedenactk*", "=radler", "weissbier", "psenicne pivo", "=heineken",
                "=guinness", "=corona", "=starobrno", "=holba", "=zubr", "=primator", "=lobkowicz", "=rebel",
                "=ostravar", "=matuska"
            ],
            excludePhrases: [
                "nealko*", "non alcoholic", "alcohol free", "bez alkohol*", "birell", "pivni syr*",
                "pivni sýr", "pivni tycink*", "pivovarsk* kvasnic*", "=pivni", "pivn* syr*", "nealkoholick*"
            ]
        ),
        FoodTagRule(
            tags: [.alcohol],
            anyPhrases: [
                "vino", "vina", "vinem", "wine*", "prosecco", "sekt", "champagne", "sampan*", "rum", "vodk*",
                "whisk*", "gin", "becherovk*", "slivovic*", "tequil*", "liker*", "liqueur*", "cider",
                "=radler", "spritz", "aperol", "mojito", "koktejl*", "cocktail*", "fernet*", "jagermeister",
                "griotk*", "medovin*", "svarak", "svarene vino", "brandy", "cognac", "koniak", "absinth*",
                "absint*", "rakij*", "grog", "pina colada", "margarita", "bozkov*", "tuzemak*", "hruskovic*",
                "merunkovic*", "palenk*", "destilat*", "martini", "baileys", "vermut*", "portsk*", "sherry"
            ],
            excludePhrases: [
                "nealko*", "non alcoholic", "alcohol free", "bez alkohol*", "ocet", "vinegar*", "hroznov*",
                "=vinny ocet", "birell", "vinn* ocet", "vinna klobas*", "vinn* klobas*", "rumov* pralink*",
                "rumov* kulick*", "rumov* aroma", "=rumove", "rum aroma"
            ]
        ),
        FoodTagRule(
            tags: [.sweets],
            anyPhrases: [
                "cokolad*", "chocolate*", "bonbon*", "candy", "candies", "lizatk*", "lollipop*",
                "gumov* medvid*", "gummy*", "haribo", "susenk*", "cookie*", "biscuit*", "oplatk*", "wafer*",
                "zmrzlin*", "ice cream", "gelato", "nanuk*", "sorbet*", "dort*", "cake", "cakes", "cupcake*",
                "cheesecake*", "donut*", "doughnut*", "koblih*", "muffin*", "brownie*", "tiramisu",
                "puding*", "pudding*", "dezert*", "dessert*", "marcipan*", "marzipan*", "nugat*", "nutella",
                "lentilk*", "kinder", "milka", "snickers", "=mars", "twix", "kitkat", "kit kat", "bounty",
                "tatrank*", "horalk*", "=mila", "fidorka", "studentsk* pecet*", "zakusek", "zakusk*",
                "vetrnik*", "laskonk*", "cukrovi", "pernik*", "gingerbread", "dzem*", "=jam", "marmelad*",
                "karamel*", "caramel*", "pralink*", "praline*", "trufl*", "truffle*", "bebe", "=deli",
                "margot", "kremrol*", "rakvick*", "indianek", "indianck*", "beehive", "=med", "honey",
                "sladkost*", "sweets", "dezertn*", "zele", "=jelly", "jellies", "marshmallow*", "=pez",
                "orion", "=toffifee", "ferrero", "raffaello", "merci", "maltesers", "knoppers",
                "kinder bueno", "sachr*", "sacher*", "medovnik*", "babovk*", "=zmrzlinovy pohar",
                "palacink* s nutell*"
            ],
            excludePhrases: [
                "kakaov* bob*", "cocoa bean*", "proteinov* puding* bez cukr*", "bez cukr*",
                "cokoladov* mlek*"
            ]
        ),
        FoodTagRule(
            tags: [.pastry],
            anyPhrases: [
                "pecivo", "peciva", "rohlik*", "rohlick*", "housk*", "baget*", "baguette*", "croissant*",
                "kroasan*", "loupak*", "kolac*", "kolacek", "kolack*", "bucht*", "vanock*", "mazanec",
                "mazanc*", "zavin*", "strudl*", "strudel*", "koblih*", "donut*", "doughnut*", "muffin*",
                "pletynk*", "danish", "pastry", "pastries", "listov* testo", "listov* pecivo",
                "listov* tast*", "trdeln*", "livan*", "palacink*", "pancake*", "vafl*", "waffle*", "babovk*",
                "perník", "croissan*", "brioche", "bagel*", "cinnamon roll*", "skorico* sne*",
                "skoricov* sne*", "kaiserk*", "kobliz*", "sniz*", "pain au chocolat", "eclair*", "eklair*",
                "vetrnik*", "kremrol*", "trubick*", "=pletenka", "=pletynka", "calta", "=calta", "houstick*"
            ],
            excludePhrases: [
                "listov* salat*", "listov* spenat*", "listova zelenina", "salat listovy", "listovy salat",
                "=rohlikova houska testo"
            ]
        ),
        FoodTagRule(
            tags: [.pie],
            anyPhrases: [
                "pie", "pies", "quiche", "kolac*", "slany kolac", "tarte", "tartlet*", "pirog*", "pirozk*",
                "=pot pie", "slan* kolac*", "tartaleti*", "=pastiera", "strudel*", "zavin*", "strudl*",
                "jablecny zavin", "=frgal", "=frgale", "=koláč", "sweet potato pie", "cheesecake*", "tart",
                "tarts"
            ],
            excludePhrases: [
                "tartar*", "=tatarak"
            ]
        ),
        FoodTagRule(
            tags: [.pizza, .cuisineItalian],
            anyPhrases: [
                "pizz*", "calzone*", "focacci*"
            ]
        ),
        FoodTagRule(
            tags: [.potato],
            anyPhrases: [
                "brambor*", "potato*", "hranolk*", "fries", "french fries", "hash brown*", "gnocchi", "noky",
                "kroket*", "rosti", "pommes", "chipsy bramb*", "pure bramb*", "bramborack*",
                "americk* brambor*", "batat*", "sweet potato*", "=bramborak", "lupinky bramborove", "wedges",
                "=kase"
            ],
            excludePhrases: [
                "bramborov* skrob*", "potato starch", "skrob*"
            ]
        ),
        FoodTagRule(
            tags: [.knedlik, .cuisineCzech],
            anyPhrases: [
                "knedl*", "dumpling* czech", "czech dumpling*", "=knedliky", "=knedlik"
            ]
        ),
        FoodTagRule(
            tags: [.colourRed],
            anyPhrases: [
                "jahod*", "strawberr*", "malin*", "raspberr*", "tresn*", "visn*", "cherr*", "rajc*",
                "tomat*", "cerven* paprik*", "red pepper*", "cervena repa", "cervene repy", "cvikl*",
                "beetroot*", "redkvick*", "radish*", "vodni meloun*", "watermelon*", "bruslin*", "cranberr*",
                "granatov* jablk*", "pomegranate*", "cerven* rybiz*", "red currant*", "red apple*",
                "cerven* jablk*", "cerven* fazol*", "cerven* cock*", "kidney bean*", "red lentil*", "chilli",
                "chili", "=chilli papricka"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "kecup*", "ketchup", "chips*",
                "omack*", "sauce", "kecupem", "chilli omack*", "=chili con carne"
            ]
        ),
        FoodTagRule(
            tags: [.colourOrange],
            anyPhrases: [
                "mrkev", "mrkv*", "carrot*", "pomeranc*", "orange", "oranges", "mandarink*", "mandarin*",
                "klementink*", "dyne", "dyn*", "pumpkin*", "merunk*", "apricot*", "mango", "manga", "batat*",
                "sweet potato*", "sladk* brambor*", "oranzov* paprik*", "papaj*", "papaya", "kaki",
                "cantaloupe", "broskev", "broskv*", "peach*", "nektarink*", "nectarin*", "hokkaido",
                "butternut", "rakytnik*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "orange juice",
                "pomerancov* dzus*", "fanta", "=mrkvovy dort"
            ]
        ),
        FoodTagRule(
            tags: [.colourYellow],
            anyPhrases: [
                "banan*", "citron*", "lemon*", "zlut* paprik*", "yellow pepper*", "kukuric*", "sweetcorn",
                "corn", "ananas*", "pineapple*", "zlut* meloun*", "zlut* cuket*", "grapefruit*",
                "=hruska zluta", "zlut* cock*", "yellow lentil*", "=zluty kiwi", "golden kiwi",
                "zlut* rajc*", "=zlute tresne", "quince", "kdoul*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "kukuric* lupin*", "cornflakes",
                "popcorn", "corn flakes", "kukuric* skrob*", "corn dog*", "kukuric* chips*",
                "tortill* chips*", "nachos", "kukuric* mouk*", "cornmeal", "polent*"
            ]
        ),
        FoodTagRule(
            tags: [.colourGreen],
            anyPhrases: [
                "brokolic*", "broccoli", "spenat*", "spinach*", "okurk*", "cucumber*", "kiwi", "avokad*",
                "avocado*", "hrasek", "hrask*", "peas", "fazolk*", "green bean*", "cuket*", "cukin*",
                "zucchin*", "courgette*", "kapust*", "kale", "rukol*", "arugula", "chrest*", "asparag*",
                "petrzel*", "parsley", "bazalk*", "basil", "pistac*", "pistachi*", "zelen* paprik*",
                "green pepper*", "zelen* jablk*", "green apple*", "zelen* salat*", "=porek", "=porku",
                "leek*", "edamame", "hlavkov* salat*", "polnick*", "ledov* salat*", "iceberg", "pak choi",
                "limet*", "=lime", "celer* nat*", "celery", "zelen* fazol*", "matcha", "zelen* caj*",
                "green tea", "zelen* olivy", "green olive*", "brussel* sprout*", "ruzicková kapusta",
                "ruzickov* kapust*", "koriandr*", "cilantro", "kopr*", "dill", "pazitk*", "chives",
                "salvej*", "mint", "sprout*", "klicky", "klick*", "hrozn* zelen*", "zelen* hrozn*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "pistaciov* zmrzlin*", "=pesto"
            ]
        ),
        FoodTagRule(
            tags: [.colourPurple],
            anyPhrases: [
                "lilek", "lilk*", "eggplant*", "aubergin*", "boruvk*", "blueberr*", "cerven* cibul*",
                "red onion*", "cerven* zeli", "red cabbage*", "fialov*", "purple*", "ostruzin*",
                "blackberr*", "cern* rybiz*", "blackcurrant*", "svestk*", "plum", "plums", "fik", "fiky",
                "fig", "figs", "acai", "aronie", "aroni*", "cerven* hrozn*", "black grape*", "red grape*",
                "tmav* hrozn*", "baklazan*", "cerven* cekank*", "radicchio", "fialov* mrkev",
                "purple carrot*", "fialov* brambor*", "purple potato*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "svestkov* knedl*",
                "svestkov* kolac*", "povidl*", "slivovic*"
            ]
        ),
        FoodTagRule(
            tags: [.colourWhite],
            anyPhrases: [
                "kvetak*", "cauliflower*", "cibul*", "onion*", "cesnek", "cesnak*", "garlic*", "zampion*",
                "mushroom*", "hlivk*", "pastinak*", "parsnip*", "petrzel* koren*", "parsley root*",
                "kedluben*", "kohlrabi", "bil* redkev", "daikon", "celer*", "celeriac", "fenykl*", "fennel",
                "cekank*", "chicory", "bil* chrest*", "white asparag*", "jicam*", "=turin", "turnip*",
                "vodnice", "tuřín"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "cerven* cibul*", "red onion*",
                "cibulov* krouzk*", "onion ring*", "celer* nat*", "celery", "cesnek* bageta",
                "cesnekov* bageta", "garlic bread", "cesnekov* chleb*", "sus* cesn*", "granul*", "=chips",
                "chips*", "cibulov* chips*", "=onion chips"
            ]
        ),
        FoodTagRule(
            tags: [.colourRed],
            anyPhrases: [
                "cerven*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "cibul*", "zeli", "vino",
                "wine*", "cekank*", "hrozn*", "kecup*", "pivo", "=red bull"
            ]
        ),
        FoodTagRule(
            tags: [.colourOrange],
            anyPhrases: [
                "oranzov*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "fanta"
            ]
        ),
        FoodTagRule(
            tags: [.colourYellow],
            anyPhrases: [
                "zlut*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "syr", "syra", "syru", "syry",
                "cheese*", "hrach*", "=zlutak", "zloutk*", "=zloutek"
            ]
        ),
        FoodTagRule(
            tags: [.colourGreen],
            anyPhrases: [
                "zeleny", "zelena", "zelene", "zeleneho", "green"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure", "green tea", "zelen* caj*",
                "=green onion", "green curry", "zelen* kari", "=green giant"
            ]
        ),
        FoodTagRule(
            tags: [.colourPurple],
            anyPhrases: [
                "fialov*"
            ],
            excludePhrases: [
                "jogurt*", "yogurt*", "yoghurt*", "dzus*", "juice*", "nektar", "sirup*", "limonad*", "dzem*",
                "marmelad*", "jam", "zmrzlin*", "ice cream", "bonbon*", "cokolad*", "chocolate*", "prichut*",
                "flavour*", "flavor*", "napoj*", "drink*", "caj*", "tea", "susenk*", "cookie*", "dort*",
                "cake*", "musli*", "muesli*", "tycink*", "lizatk*", "kolac*", "zavin*", "strudl*", "muffin*",
                "koblih*", "donut*", "smoothie*", "kompot*", "pyre", "pure"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineCzech],
            anyPhrases: [
                "svickov*", "knedl*", "gulas*", "smazen* syr*", "smazak", "bramborak*", "kulajd*",
                "koprovk*", "koprov* omack*", "rajsk* omack*", "spanelsk* ptacek", "spanelsk* ptack*",
                "segedin*", "utopen*", "tlacenk*", "tvaruzk*", "chlebicek", "chlebick*", "vanock*",
                "mazanec", "mazanc*", "bramboracka", "cesnecka", "zelnacka", "drstkov*", "sekan*",
                "hermelin*", "bucht*", "livan*", "moravsk* vrabec", "moravsk* vrabc*", "kyselo", "na kyselo",
                "vetrnik*", "laskonk*", "kremrol*", "zemlovk*", "vepro knedlo", "rizek s bramborov* salat*",
                "kuba", "=houbovy kuba", "pecen* kachn*", "kachn* se zeli*", "nakladan* hermelin*",
                "=parek v rohliku", "parek v rohliku", "ovocn* knedl*", "trdeln*", "kolac* frgal*", "=frgal",
                "=frgale", "halusk*", "stavnat* rizek", "smazen* rizek", "vepro", "cmunda", "lokse",
                "=lokse", "chodsk*", "=bramboraky", "=prazska sunka", "prazsk* sunk*", "olomouck*",
                "pardubick* pernik*", "karlovarsk* oplatk*", "=hoficky", "hoick*", "=jihoceska"
            ],
            excludePhrases: [
                "spanelsk* ptacek vegan"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineItalian],
            anyPhrases: [
                "=pasta", "spaget*", "spaghett*", "lasagn*", "rizot*", "risott*", "penne", "fusilli",
                "tagliatell*", "fettuccin*", "linguin*", "raviol*", "tortellin*", "gnocchi", "carbonar*",
                "bolonsk*", "bolognes*", "pesto", "mozzarell*", "parmazan*", "parmigian*", "parmesan*",
                "prosciutto", "bruschett*", "focacci*", "ciabatt*", "tiramisu", "panna cotta", "gelato",
                "minestron*", "caprese", "calzone*", "antipast*", "mascarpone", "ricott*", "arancin*",
                "carpaccio", "italsk*", "italian", "grana padano", "pecorino", "gorgonzol*", "cannelloni",
                "farfalle", "rigatoni", "orecchiette", "vitello tonnato", "saltimbocca", "ossobuco",
                "polent*", "panettone", "cantucci*", "amaretti", "limoncello", "grissin*", "salami milano",
                "=milano"
            ],
            excludePhrases: [
                "=pesto vegan"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineJapanese],
            anyPhrases: [
                "sushi", "maki", "nigiri", "sashimi", "ramen", "udon", "soba", "miso", "teriyaki", "tempura",
                "edamame", "onigiri", "gyoza", "katsu", "matcha", "wasabi", "yakitori", "japonsk*",
                "japanese", "mochi", "okonomiyaki", "donburi", "tonkatsu", "yakisoba", "unagi", "furikake",
                "takoyaki", "sake", "ponzu"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineChinese],
            anyPhrases: [
                "cinsk*", "chinese", "dim sum", "wonton*", "kung pao", "chow mein", "sladkokysel*",
                "sweet and sour", "pekingsk*", "peking", "jarn* zavitek", "jarn* zavitk*", "spring roll*",
                "=bao", "baozi", "mapo", "char siu", "=wok", "hoisin", "szechuan", "secuansk*", "sichuan",
                "chop suey", "dumplings chinese", "=chow"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineIndian],
            anyPhrases: [
                "indick*", "indian", "curry", "kari", "tikka", "masala", "korma", "vindaloo", "biryani",
                "birjani", "tandoori", "naan", "chapati", "capati", "samosa*", "samos*", "=dal", "dhal",
                "daal", "paneer", "lassi", "chutney", "pakora*", "bhaji", "palak", "rogan josh",
                "butter chicken", "madras", "jalfrezi", "raita", "dosa", "=roti", "garam", "tadka", "chana"
            ],
            excludePhrases: [
                "thai", "thajsk*", "thai curry", "thajsk* kari", "green curry", "red curry", "panang",
                "massaman", "japonsk* kari", "japanese curry", "=kari koreni"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineMexican],
            anyPhrases: [
                "mexick*", "mexican", "burrito*", "taco", "tacos", "tortill*", "quesadill*", "nacho*",
                "fajit*", "guacamol*", "salsa", "enchilad*", "con carne", "jalapen*", "chimichang*",
                "tex mex", "texmex", "=tamales", "churros"
            ],
            excludePhrases: [
                "tortilla espanola", "spanelsk* omelet*", "spanish omelet*", "=salsa verde"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineThai],
            anyPhrases: [
                "thajsk*", "thai", "tom yum", "tom kha", "green curry", "red curry", "massaman", "satay",
                "=sate", "som tam", "larb", "panang", "khao", "=pad see ew", "=pad kra pao"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineVietnamese],
            anyPhrases: [
                "vietnamsk*", "vietnamese", "=pho", "bun bo", "bun cha", "banh mi", "banh", "=nem", "nemy",
                "goi cuon", "bo bun", "bun thit", "=com", "=vietnam"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineGreek],
            anyPhrases: [
                "reck*", "greek", "gyros", "tzatzik*", "tzaziki", "feta", "fety", "souvlaki", "musaka",
                "moussaka", "baklav*", "halloumi", "spanakopit*", "dolmad*", "horiatiki", "=pita", "=pitta",
                "tarama*", "kleftiko", "stifado", "=giouvetsi", "ouzo", "metax*", "gyro"
            ],
            excludePhrases: [
                "recky jogurt vegan"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineTurkish],
            anyPhrases: [
                "tureck*", "turkish", "kebab*", "kebap*", "doner", "durum", "lahmacun", "baklav*", "=pide",
                "ayran", "kofte", "borek", "lokum", "simit", "gozleme", "iskender", "menemen", "sucuk",
                "tureck* med"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineSpanish],
            anyPhrases: [
                "spanelsk*", "spanish", "paella", "tapas", "chorizo", "gazpacho", "jamon", "serrano",
                "churros", "churro", "manchego", "bravas", "sangria", "tortilla espanola", "espanola",
                "pimientos", "croquetas", "crema catalana", "=pisto"
            ],
            excludePhrases: [
                "spanelsk* ptacek", "spanelsk* ptack*", "=spanelsky ptacek"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineFrench],
            anyPhrases: [
                "francouzsk*", "french", "croissant*", "kroasan*", "baguette*", "quiche", "ratatouille",
                "brulee", "crepe", "crepes", "camembert*", "brie", "roquefort", "foie gras", "bouillabaisse",
                "coq au vin", "cassoulet", "croque", "eclair*", "eklair*", "macaron", "macarons",
                "madeleine*", "tarte", "confit", "bechamel", "dijon", "beouf bourguignon", "bourguignon",
                "tartiflette", "gratin*", "soufflé", "souffle", "vichyssoise", "baget* francouzsk*",
                "pain au chocolat", "profiterol*"
            ],
            excludePhrases: [
                "francouzsk* brambor*", "french fries", "=fries", "french toast", "francouzsk* hot dog*",
                "francouzsk* hotdog*", "french dressing"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineAmerican],
            anyPhrases: [
                "americk*", "american", "burger*", "hamburger*", "cheeseburger*", "hot dog*", "hotdog*",
                "pancake*", "bagel*", "brownie*", "donut*", "doughnut*", "mac and cheese", "mac n cheese",
                "bbq", "barbecue", "coleslaw", "cheesecake*", "nugget*", "peanut butter", "fried chicken",
                "chicken wings", "buffalo wings", "corn dog*", "milkshake*", "pulled pork", "cornbread",
                "muffin*", "cupcake*", "=kfc", "mcdonald*", "big mac", "whopper", "=subway", "mcchicken",
                "mcflurry", "french fries", "cookie*"
            ],
            excludePhrases: [
                "americk* brambor*", "americk* sal*"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineKorean],
            anyPhrases: [
                "korejsk*", "korean", "kimchi", "bibimbap", "bulgogi", "gochujang", "tteokbokki", "japchae",
                "kimbap", "gimbap", "=bibim", "samgyeopsal", "=soju"
            ]
        ),
        FoodTagRule(
            tags: [.cuisineMiddleEastern],
            anyPhrases: [
                "hummus", "humus", "falafel*", "tahini", "tahin*", "shawarma", "sawarm*", "baba ganoush",
                "ganoush", "tabouleh", "tabbouleh", "tabule", "labneh", "shakshuka", "saksuk*", "=pita",
                "=pitta", "fattoush", "kibbeh", "mezze", "meze", "=halva", "chalva", "halvah", "dukkah",
                "zaatar", "=za atar", "libanonsk*", "lebanese", "arabsk*", "arabic", "persian", "persk*",
                "=fatteh", "musakhan", "kunafa", "=datle medjool", "medjool"
            ],
            excludePhrases: [
                "humus vegan"
            ]
        ),
    ]
}
