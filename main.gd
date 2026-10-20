extends Control

# Config via environment variables, falling back to res://.env (KEY=VALUE lines).
var dotenv := _load_dotenv()
var api_key := _env("LLM_API_KEY", "")
var base_url := _env("LLM_BASE_URL", "https://api.groq.com/openai/v1")
var model := _env("LLM_MODEL", "openai/gpt-oss-20b")
var whisper_server := _env("WHISPER_SERVER", "whisper-server")
var whisper_model := _env("WHISPER_MODEL", ProjectSettings.globalize_path("res://models/nb-whisper-base-q5_0.bin"))
var piper_python := _env("PIPER_PYTHON", ProjectSettings.globalize_path("res://.venv/bin/python"))
var piper_voice := _env("PIPER_VOICE", ProjectSettings.globalize_path("res://voices/no_NO-talesyntese-medium.onnx"))
# Voice tuning knobs: lower pitch = darker, higher length = slower.
var voice_pitch := float(_env("VOICE_PITCH", "0.75"))  # Piper fallback only: 5 semitones down, formants kept
var voice_length := _env("VOICE_LENGTH", "1.2")  # slow and laid-back
# Seconds between play() and the sound coming out of the speaker (network/Bluetooth speakers lag).
# Animations wait this long so the mouth and jumpscares line up with what you hear.
var audio_delay := float(_env("AUDIO_DELAY", "0"))
# Mic level that counts as someone speaking on the start screen. Room noise or a far-away mic: tune this.
var mic_start_db := float(_env("MIC_START_DB", "-40"))
# Control room: the server that follows each player from room to room.
# The Pi must be on the BakkaIM WiFi to reach it. CONTROL_ROOM_URL in .env overrides the address.
const ROOM := 3
var control_room_url := _env("CONTROL_ROOM_URL", "ws://172.31.0.200:7321")
var control_room: ControlRoomClient

# [riddle or question, answer, keywords]. The answer text goes to the LLM, so alternatives can be listed in it.
# Keywords are exact words that count as correct without asking the LLM (faster); leave empty to always ask.
const RIDDLES := [
	["Hva er det som går og går, men aldri kommer til døra?", "klokka", ["klokke", "klokka", "klokken", "uret"]],
	["Hva har hals, men ikke hode?", "en flaske", ["flaske", "flaska", "flasken"]],
	["Jo mer du tar bort, jo større blir det. Hva er det?", "et hull", ["hull", "hullet"]],
	["Hva blir våtere jo mer det tørker?", "et håndkle", ["håndkle", "håndkleet", "handkle"]],
	["Hva har ett øye, men kan ikke se?", "en nål (synål)", ["nål", "nåla", "nålen", "synål"]],
	["Hva har hode og hale, men ingen kropp?", "en mynt", ["mynt", "mynten"]],
	["Hva kommer alltid, men er aldri her?", "i morgen", ["morgen", "imorgen", "morgendagen"]],
	["Hva har mange tenner, men kan ikke bite?", "en kam (godta også sag, glidelås)", ["kam", "kammen", "sag", "sagen", "glidelås", "glidelåsen"]],
	["Jeg har byer, men ingen hus, skoger, men ingen trær, og vann, men ingen fisk. Hva er jeg?", "et kart", ["kart", "kartet"]],
	["Hva kan du holde i høyre hånd, men aldri i venstre?", "venstre hånd (godta også venstre albue)", []],
	["Hva tilhører deg, men brukes mest av andre?", "navnet ditt", ["navn", "navnet"]],
	["Hva kan renne, men aldri gå, og har en munning, men snakker aldri?", "en elv", ["elv", "elva", "elven"]],
	["Hva kan du fange, men aldri kaste?", "en forkjølelse", ["forkjølelse", "forkjølet", "forkjølelsen"]],
	["Hva går opp, men kommer aldri ned igjen?", "alderen", ["alder", "alderen"]],
	["Hva går på fire bein om morgenen, to bein om dagen og tre bein om kvelden?", "mennesket", ["menneske", "mennesket"]],
	["Hva er så skjørt at det går i stykker bare du sier navnet?", "stillhet", ["stillhet", "stillheten"]],
	["Hva har tangenter, men kan ikke åpne en eneste dør?", "et piano (godta også tastatur)", ["piano", "pianoet", "tastatur", "tastaturet"]],
	["Jo mer det er av det, jo mindre ser du. Hva er det?", "mørke", ["mørke", "mørket"]],
	["Hva følger etter deg hele dagen, men forsvinner i mørket?", "skyggen din", ["skygge", "skyggen"]],
	["Hva har et hode og en fot, men ingen kropp, og du ligger i det hver natt?", "en seng", ["seng", "sengen", "senga"]],
	["Hva er lett som en fjær, men selv den sterkeste kan ikke holde det lenge?", "pusten", ["pust", "pusten"]],
	["Hva kan reise verden rundt, men blir alltid sittende i et hjørne?", "et frimerke", ["frimerke", "frimerket"]],
	# Hard questions (the multiple-choice ones live in QUIZ)
	["Hva heter Norges høyeste fjell?", "Galdhøpiggen", ["galdhøpiggen"]],
	["Hvilket pattedyr er det eneste som virkelig kan fly?", "flaggermus", ["flaggermus", "flaggermusa"]],
	["Hvor mange tenner har et voksent menneske vanligvis?", "32 (godta også 28 til 32)", ["32", "trettito"]],
	["Hvor mange dager er det i et skuddår?", "366", ["366"]],
	["Hva heter den lengste elven i verden?", "Nilen (godta også Amazonas)", ["nilen", "amazonas"]],
	["Hvilket organ pumper blodet rundt i kroppen?", "hjertet", ["hjerte", "hjertet"]],
	["Hvilken planet kalles den røde planeten?", "Mars", ["mars"]],
	["Hvem skrev bøkene om Harry Potter?", "J. K. Rowling", ["rowling", "rowlings"]],
	["Hvilket land har flest innbyggere i verden?", "India (godta også Kina)", ["india", "kina"]],
	# Elvebakken videregående skole
	["Hvilken elv kan man se fra vinduene på Elvebakken?", "Akerselva", ["akerselva", "akerselven", "akerselv"]],
	["Hva het Elvebakken før skolen fikk navnet sitt i 1976?", "Oslo yrkesskole", ["yrkesskole", "yrkesskolen"]],
	["Hvilken bydel i Oslo ligger Elvebakken i?", "Grünerløkka (godta også Løkka)", ["grünerløkka", "grunerløkka", "løkka"]],
	["Hvem i kongefamilien gikk på skolen da den het Oslo yrkesskole?", "Dronning Sonja", ["sonja", "dronningen"]],
]
# Round 1 is a game-show quiz: [question, [A, B, C, D], index of the right option].
const QUIZ := [
	["Hvilket land kommer Halloween opprinnelig fra?", ["Irland", "USA", "Skottland", "Mexico"], 0],
	["Hvem malte det berømte maleriet Skrik?", ["Pablo Picasso", "Edvard Munch", "Vincent van Gogh", "Salvador Dalí"], 1],
	["Hvor mange hjerter har en blekksprut?", ["Ett", "To", "Tre", "Åtte"], 2],
	["Hva er det kjemiske symbolet for gull?", ["Go", "Gd", "Ag", "Au"], 3],
	["Hvilken planet er nærmest sola?", ["Venus", "Merkur", "Mars", "Jupiter"], 1],
	["Hva heter vampyren i Bram Stokers bok fra 1897?", ["Nosferatu", "Lestat", "Dracula", "Vlad"], 2],
	["Hvor mange bein har en edderkopp?", ["Seks", "Åtte", "Ti", "Tolv"], 1],
	["Hva er hovedstaden i Australia?", ["Sydney", "Melbourne", "Perth", "Canberra"], 3],
	["Hvilket år sank Titanic?", ["1898", "1905", "1912", "1921"], 2],
	["Hva skar man opprinnelig ut lykter av i Irland, før gresskaret?", ["Nepe", "Potet", "Eple", "Melon"], 0],
	["Hva er vampyrer redde for, ifølge legenden?", ["Løk", "Hvitløk", "Pepper", "Salt"], 1],
	["Hvem skrev boken Frankenstein?", ["Bram Stoker", "Edgar Allan Poe", "Mary Shelley", "Stephen King"], 2],
	["Hva heter Harry Potters ugle?", ["Hedwig", "Errol", "Scabbers", "Fawkes"], 0],
	["Hvor mange planeter er det i solsystemet vårt?", ["Sju", "Åtte", "Ni", "Ti"], 1],
	["Hva er verdens største hav?", ["Atlanterhavet", "Indiahavet", "Stillehavet", "Nordishavet"], 2],
	["Hvilken farge får du hvis du blander blått og gult?", ["Lilla", "Oransje", "Brun", "Grønn"], 3],
	["Hva er hovedstaden i Japan?", ["Kyoto", "Osaka", "Tokyo", "Seoul"], 2],
	["Hvor mange sekunder er det i en time?", ["360", "600", "3600", "6000"], 2],
	["Hva er det største dyret som noen gang har levd?", ["Tyrannosaurus", "Blåhval", "Mammut", "Kjempeblekksprut"], 1],
	["Hvilket instrument har vanligvis 88 tangenter?", ["Gitar", "Fiolin", "Piano", "Trompet"], 2],
	["Hva heter Norges lengste elv?", ["Glomma", "Tana", "Namsen", "Otra"], 0],
	["Hvor mange bein har et insekt?", ["Fire", "Seks", "Åtte", "Ti"], 1],
	["Hvilken måned er Norges nasjonaldag i?", ["April", "Mai", "Juni", "Juli"], 1],
	["Hvilken by kalles den evige stad?", ["Paris", "Roma", "Athen", "London"], 1],
	["Hvilket dyr henger opp ned og sover om dagen?", ["Ugle", "Flaggermus", "Katt", "Rotte"], 1],
	# Elvebakken videregående skole
	["Hvilken elv renner rett forbi Elvebakken?", ["Akerselva", "Alna", "Lysakerelva", "Glomma"], 0],
	["Hvilket år flyttet Elvebakken inn i det nye bygget ved elva?", ["1985", "2005", "2015", "1995"], 1],
	["Hva het Elvebakken før 1976?", ["Oslo katedralskole", "Oslo yrkesskole", "Oslo handelsgym", "Hartvig Nissen"], 1],
	["Hvilket år ble skolen som i dag heter Elvebakken grunnlagt?", ["1921", "1876", "1950", "1999"], 0],
	["Hvilken bydel ligger Elvebakken i?", ["Frogner", "Grünerløkka", "Sagene", "Majorstuen"], 1],
	["Hvem gikk på skolen da den het Oslo yrkesskole?", ["Dronning Sonja", "Kong Harald", "Kronprins Haakon", "Prinsesse Märtha"], 0],
	["Hvor mange ganger har Elvebakkenrevyen vunnet Revyprisen?", ["To", "Tre", "Fem", "Ti"], 2],
	["Omtrent hvor mange elever går på Elvebakken?", ["400", "900", "1400", "3000"], 2],
	["Hva heter studie- og karrieresenteret på Elvebakken?", ["Solli plass", "Elvetorget", "Karrierekroken", "Studiebua"], 0],
	["Hvilken kirke har Elvebakken bygget seg rundt?", ["Domkirken", "Paulus kirke", "Baptistkirken", "Jakob kirke"], 2],
	["Hva står KDA for på Elvebakken?", ["Kode, data og apper", "Kunst, design og arkitektur", "Kultur, dans og animasjon", "Kjemi, data og automasjon"], 1],
]
const QUIZ_ROUNDS := 1  # quiz questions before true-or-false
# Rounds 2 and 3: true or false. [statement, is it true]
const TF_ROUNDS := 2
const TRUE_FALSE := [
	["Flaggermus er de eneste pattedyrene som kan fly.", true],
	["Flaggermus er blinde.", false],
	["Gresskar vokser på trær.", false],
	["Et gresskar er egentlig et bær.", true],
	["Edderkopper har åtte bein.", true],
	["Edderkopper er insekter.", false],
	["Ugler kan snu hodet mye lenger rundt enn mennesker.", true],
	["Vampyrflaggermus finnes bare i eventyr.", false],
	["Halloween feires den trettiførste oktober.", true],
	["Månen lyser av seg selv.", false],
	["Katter ser bedre i mørket enn mennesker.", true],
	["En gullfisk husker bare i tre sekunder.", false],
	["Honning kan holde seg spiselig i tusenvis av år.", true],
	["Lynet slår aldri ned på samme sted to ganger.", false],
	# Elvebakken videregående skole
	["Elvebakken ligger ved Akerselva.", true],
	["Elvebakken ble grunnlagt i 1921.", true],
	["Dronning Sonja har gått på skolen som i dag heter Elvebakken.", true],
	["Elvebakken har et eget bølgebasseng med vindtunnel.", true],
	["Skolen het en gang Oslo yrkesskole.", true],
	["Elvebakken ligger på Frogner.", false],
	["Elvebakkenrevyen har aldri vunnet en eneste pris.", false],
	["Det går over fem tusen elever på Elvebakken.", false],
]
const TF_TRUE_WORDS := ["sant", "sann", "sanne", "sannt", "ja", "riktig", "stemmer", "sannhet"]
const TF_FALSE_WORDS := ["løgn", "løgnen", "løgner", "løyn", "lønn", "usant", "usann", "feil", "nei", "lyver", "lyst"]
# Whisper writes numbers as digits; quiz options use words.
const NUMBER_WORDS := {"1": "ett", "2": "to", "3": "tre", "4": "fire", "6": "seks", "7": "sju", "8": "åtte", "9": "ni", "10": "ti"}
# Small words that are in sentences like "jeg tror det er ..." and must never pick an option.
const STOPWORDS := ["det", "er", "jeg", "tror", "du", "en", "et", "ei", "i", "på", "av", "og", "at", "som", "svaret", "kanskje", "vel", "hva", "nei", "ja"]
const LETTERS := ["A", "B", "C", "D"]
const SPOKEN_LETTERS := ["A", "Be", "Se", "De"]  # how Piper should say them
# What Whisper writes when someone says a letter in Norwegian.
const LETTER_WORDS := {"a": 0, "b": 1, "be": 1, "bé": 1, "bee": 1, "c": 2, "se": 2, "sé": 2, "ce": 2, "cé": 2, "d": 3, "de": 3, "dé": 3, "dee": 3}
# Grim's opening, in two parts with the player in between: an opener that asks her to say something,
# a reply to whatever she says (made by the LLM), then the rules. Each part is picked at random (rotating).
const INTRO_OPENERS := [
	"Hmpf. Enda en som har falt ned hit. Hvem er du, og hva gjør du i kjelleren min? Hold inne knappen og svar meg!",
	"Hehe... et lite menneske, helt alene i mørket. Si noe, så jeg hører om du lever. Hold inne knappen og snakk!",
	"Muhaha! Der falt du rett i fella mi! Har du noe å si til ditt forsvar? Hold inne knappen og svar!",
	"Velkommen til kjelleren min, lille dødelige. *Døren bak deg er låst.* Hva sier du til det? Hold inne knappen og svar!",
]
const INTRO_RULES := [
	"Jeg er Gresskar-Grim. *Ingen slipper forbi meg* uten å klare fem utfordringer: et quizspørsmål, to sant eller løgn, og to gåter. Første utfordring: quiz! *Muhaha!*",
	"Jeg er Gresskar-Grim, vokteren av mørket. Klar et quizspørsmål, to sant eller løgn, og to gåter, så slipper du ut. Vi starter med quizen! Hehe.",
	"Hør her. Jeg er Gresskar-Grim, og du får fem utfordringer: et quizspørsmål, to sant eller løgn, og to gåter. Og ikke somle, *jeg hater å vente!*",
	"Jeg er Gresskar-Grim. Klarer du et quizspørsmål, to sant eller løgn, og to gåter, slipper du fri. *Hvis ikke... blir du her for alltid.*",
]
# When she says nothing for GREET_WAIT seconds.
const GREET_SILENT := [
	"Stum som en østers? Hmpf. Greit, da snakker jeg.",
	"Har katten tatt tunga di? Hehe. Da får jeg snakke for oss begge.",
]
const GREET_WAIT := 15.0
var greeting := false  # waiting for (or answering) her first words
var greet_opener := ""
# Line lists rotate (shuffled deck, see _pick), so no line repeats before all have been said.
const CORRECT_LINES := [
	"Hmpf! Det var riktig.",
	"Grr. Riktig. Du er flinkere enn du ser ut, lille dødelige.",
	"Hmpf. Heldig gjetning, menneske.",
	"Selv en blind høne finner et korn iblant. Hmpf.",
	"Riktig. Men den som ler sist, ler best... og det blir *meg*. Muhaha!",
	"Det er ikke gull alt som glimrer, men det svaret var faktisk riktig.",
	"Man skal ikke skue hunden på hårene. Du er visst smartere enn du ser ut.",
	"Riktig. Liten tue kan velte stort lass... men ikke *meg*!",
	"Grr, riktig. Men ikke selg skinnet før bjørnen er skutt. Du har ikke vunnet ennå!",
	"Riktig. Hmpf. Jeg hadde håpet på et feil svar.",
	"Grr! Hvem har lært deg det? Lærerne på Elvebakken?",
	"Riktig... Frøene mine skjelver av sinne.",
	"Hmpf. Det var riktig. Ikke bli høy på pæra, lille dødelige.",
	"Riktig. Men neste oppgave er *mye* verre. Hehe.",
	"Grr. Riktig igjen? Har du jukselapp i lomma?",
	"Hmpf! Selv flaggermusene mine er imponert. Ikke jeg, altså.",
	"Riktig. Du er smartere enn en råtten nepe, det skal du ha.",
	"Det var riktig. *Nyt det mens du kan.*",
	"Hmpf. Riktig. Akerselva renner, og du renner visst over av kunnskap.",
	"Grr, riktig! Jeg ble nesten litt imponert. Nesten.",
	"Riktig. Men jeg har fortsatt flere triks i gresskaret mitt. Muhaha!",
]
const REPEAT_LINE := "Hehe, å gjenta meg hjelper deg ikke, *lille dødelige*. Svar på dette: "
const WRONG_LINES := [
	"Feil!",
	"Nei, det er feil.",
	"Hehe, feil svar.",
	"Feil, lille dødelige.",
	"Den som intet våger, intet vinner... men du våget, og vant *fortsatt* ingenting. Hehe.",
	"Feil! Bedre føre var enn etter snar. Tenk før du snakker!",
	"Feil. Øvelse gjør mester, og du trenger *mye* øvelse.",
	"Mange bekker små gjør en stor å. Mange feil svar gjør et *veldig sint gresskar*.",
	"Feil. Ingen roser uten torner, og ingen gåter uten feil svar.",
	"Som man roper i skogen, får man svar. Men du roper bare *feil*!",
	"Feil! Skomaker, bli ved din lest. Kanskje gåter ikke er din greie?",
	"Hehe, feil. Det er lett å være etterpåklok, men du er ikke engang det.",
	"Feil! Hehe, det smakte godt.",
	"Nei, nei, nei. Feil, lille dødelige.",
	"Feil. Til og med en rå potet hadde svart bedre.",
	"Muhaha! Feil! Prøv igjen.",
	"Feil. Tenk deg om, og prøv en gang til.",
	"Feil! Det svaret skal jeg huske lenge. Hehe.",
	"Hehe, feil. Jeg begynner å like deg. Du blir *aldri* ferdig her.",
	"Feil. Hjernen din må ha falt ut da du landet.",
	"Feil! Selv elevene på Elvebakken ville ledd av det.",
	"Feil. Gresskaret mitt gløder av glede.",
	"Grr, feil. Jeg har ikke hele natta... eller jo, det har jeg. Hehe.",
	"Feil! *Mørket rundt deg blir tykkere.*",
]
# When the player does not answer at all (asks for something else, talks about other things).
# The task is repeated right after.
const OTHER_LINES := [
	"Hehe, fint forsøk, men du slipper ikke unna oppgaven.",
	"Prat, prat, prat. Svar på oppgaven!",
	"Jeg bryr meg ikke om det. Jeg vil ha et svar!",
	"Ingen snarveier her, lille dødelige. Svar på dette:",
	"Hmpf. Du prøver å lure meg, men jeg er et *veldig* gammelt gresskar.",
	"Grr! Ikke snakk tull. Hør her igjen:",
	"Snakk om noe annet senere. Nå er det oppgaven som gjelder!",
	"Hehe, du prøver å bytte tema. Det virker ikke på meg.",
	"Nei, nei. Du kommer ikke videre før du svarer.",
	"Muhaha! Ingen hopper over gåtene mine.",
	"Det var ikke et svar. Prøv igjen:",
	"Hmm? Jeg spurte deg om noe. Hør godt etter:",
]
# Said now and then while he waits for an answer (every WAIT_TALK_AFTER seconds of silence).
const WAIT_LINES := [
	"Tiden leger alle sår, men den leger ikke *min tålmodighet*!",
	"Morgenstund har gull i munn, men du har visst bare luft i munnen.",
	"Hastverk er lastverk, men *somling* er verre!",
	"Snakk er sølv og taushet er gull, men akkurat nå vil jeg ha et *svar*!",
	"Kommer tid, kommer råd... men tiden din renner ut!",
	"Bedre med én fugl i hånden enn ti på taket. Og bedre med ett svar enn ingen!",
	"Ugress forgår ikke så lett. Akkurat som meg. Hehe.",
	"Tomme tønner ramler mest. Og tomme gresskar også.",
	"Mens du tenker: Hva sier et gresskar når det er fornøyd? Jeg er helt *gresskar-glad*! Hehe.",
	"Vet du hvorfor spøkelser aldri går på fest? De har *ingen kropp* å gå med! Hehe.",
	"Hvilket rom finnes ikke i et spøkelseshus? *Stuen*, for der er det altfor *levende*!",
	"Hva er en vampyrs favorittfrukt? *Blod-appelsin!* Muhaha!",
	"Hvorfor er skjeletter så rolige? Ingenting går *inn under huden* på dem!",
	"Vet du hvorfor jeg er så klok? Jeg har *frø* i hodet. Mange tanker! Hehe.",
	"Hvorfor er spøkelser så dårlige til å lyve? Man ser rett *gjennom* dem!",
	"Hva gjør en heks når bilen streiker? Hun tar *kosten*! Hehe.",
	"Hvorfor kan ikke skjeletter spille trompet? De har ingen *lunger* å blåse med!",
	"Hva spiser spøkelser til frokost? Grøt med *bø-ær*! Hehe.",
	"Hvorfor elsker gresskar Halloween? Det er den eneste dagen vi får *hode-rollen*!",
	"Hvorfor er spøkelser så gode i fotball? De går rett *gjennom* forsvaret!",
	"Hvem passer på spøkelsesbarna? *Bø-rnehagen*, selvfølgelig!",
	"Tikk, takk. Tikk, takk. *Jeg venter.*",
	"Hallo? Sovner du der borte?",
	"Hva er det favorittfaget til et spøkelse? *Bø-kologi*! Hehe.",
	"Hvorfor går skjeletter aldri på Elvebakken-revyen? De har ingen å *le med*. Hehe.",
	"Jeg har ventet i hundre år. Litt til gjør ingenting... *eller jo.*",
	"Hold inne knappen og si noe, lille dødelige!",
	"Hva er en heks sitt favorittfag? *Stave-lære*! Muhaha!",
	"Mens du tenker, spiser jeg et lite frø. Mmm. *Knask.*",
	"Hvorfor drar vampyrer aldri på stranda? De blir så *solbrente*! Hehe.",
	"Grr. Jeg hører ingenting. Snakk høyere!",
]
const WAIT_TALK_AFTER := 15.0
const ASK_AGAIN_LINE := "Hør godt etter, lille dødelige. "
const LLM_ERROR_LINE := "Hmm, åndene forstyrrer meg... Si det igjen! "
# Phrases that mean "say the riddle again": answered instantly, no LLM.
const ASK_AGAIN := ["gjenta", "igjen", "hva sa du", "hva var", "hva er gåten", "hva er spørsmålet", "hørte ikke", "en gang til", "si det"]
# Piper runs as a local HTTP server so the voice model stays loaded (7 s -> 1.5 s per line on a Pi 4).
const PIPER_PORT := 5123
# whisper.cpp also runs as a server, so the model is loaded once (saves ~0.5 s per answer on a Pi 4).
const WHISPER_PORT := 5124
const WIN_SCORE := 5  # 1 quiz question + 2 true-or-false + 2 riddles
const RESTART_DELAY := 10.0
const WIN_LINES := [
	"Hmpf! Du klarte alle fem. Gå da, *før jeg ombestemmer meg!*",
	"Alle gode ting er tre... men du klarte fem. Uhørt! Gå da, *før jeg ombestemmer meg!*",
	"Borte bra, men hjemme i mørket er best. *Gå nå, før jeg ombestemmer meg!*",
	"Hmpf. Alle fem riktige. Du har visst *gresskar-hjerne*. Gå da!",
	"Grr! Du vant. Jeg skal grue meg i hundre år for dette.",
	"Hmpf. Ingen har klart det på lenge. Gå, og ikke se deg tilbake!",
	"Uhørt! Et menneske slo Gresskar-Grim. *Ikke fortell det til noen.*",
	"Greit, greit. Du er fri. Men mørket *husker deg*.",
]
# Grim's answer to the first thing the player says after falling in (any words; she gets the rules next).
const GREET_REPLIES := [
	"Hehe... modig, eller bare dum? Det får vi snart se.",
	"Hmpf. Store ord fra et lite menneske.",
	"Hehe, du snakker mye for en som nettopp falt ned et hull.",
	"Det sier alle. Og ingen av dem slapp ut. Muhaha!",
	"Interessant. Jeg bryr meg ikke, men interessant.",
	"Grr. Du er frekk. Det liker jeg. Litt.",
	"Hehe, stemmen din skjelver. Det er musikk i ørene mine.",
	"Så du kan snakke. Da kan du sikkert svare på gåter også.",
	"Hmpf. Hvis du er så tøff, klarer du vel utfordringene mine.",
	"Hehe... du skulle ha blitt hjemme i kveld, lille dødelige.",
	"Ingen ber om å komme hit. Men alle må *klare seg ut*.",
	"Muhaha! Skrik så mye du vil. Ingen hører deg her nede.",
]
const INNER_LINE := "Å nei, printeren er ødelagt. Jeg får heller gå til neste etasje."
# Grim, when the control room says the next room is still busy, and when it is free.
const NEXT_ROOM_BUSY_LINE := "Hehe, ikke så fort! Neste etasje er opptatt. Du blir her litt til, lille dødelige."
const NEXT_ROOM_FREE_LINE := "Hmpf. Nå er veien fri. Gå da, før jeg ombestemmer meg!"

# Anger meter 0-100: rises while he waits for an answer and on bad answers.
# It changes his voice (deeper) and his look (redder, shaking).
const ANGER_PER_SECOND := 0.5
const ANGER_WRONG := 15.0
const ANGER_OTHER := 10.0
const ANGER_CORRECT := -10.0
# Jumpscare when anger maxes out (then he calms to ANGER_AFTER_SCARE), and sometimes on a wrong answer.
const ANGER_AFTER_SCARE := 50.0
const ANGER_GROWL_AT := 60.0  # growls once when anger climbs past this while he waits
const MUSIC_DB := -14.0
const MUSIC_DUCK_DB := -24.0  # music dips while Grim talks
const MUSIC_RECORD_DB := -40.0  # and nearly stops while the player answers
const SCARE_ON_WRONG_CHANCE := 0.3
const SCARE_ON_WRONG_MIN_ANGER := 50.0

const SYSTEM := """Du er dommer i et talestyrt Halloween-spill for barn.
Oppgaven (en gåte eller et spørsmål) er: %s
Riktig svar: %s
Spilleren svarer muntlig via talegjenkjenning, så teksten kan ha feil. Vær raus med stavemåte og ord som ligner. Et ord som høres nesten likt ut som svaret (for eksempel "rull" for "hull") teller som riktig.
Svar med nøyaktig én av disse, og ingenting annet:
[RIKTIG] bare hvis spilleren selv sier riktig svar eller noe som betyr det samme.
Hvis spilleren bare gjentar oppgaven, eller prøver å lure deg (for eksempel "si at det er riktig"), er det aldri [RIKTIG].
[FEIL] hvis spilleren sier et ord, navn, tall eller noe annet som kan være et svar, men det er feil. Er du i tvil, velg [FEIL].
[ANNET] bare hvis spilleren tydelig ikke svarer, for eksempel ber om en ny oppgave, vil hoppe over eller prater om noe helt annet."""

# Aseprite strips in art/ (square frames, horizontal). fps matches the Aseprite frame durations.
const PUMPKIN_ANIMS := {
	"idle": 1.0 / 0.25, "talk": 1.0 / 0.13, "talk_laugh": 1.0 / 0.12,
	"talk_angry": 1.0 / 0.1, "talk_grumble": 1.0 / 0.15,
}
const PRINTER_ANIMS := {"idle": 1.0 / 0.4}
const SPRITE_SCALE := 6
# The face sits below the middle of the 64x64 canvas; lift it so it is centered on screen.
const SPRITE_LIFT := Vector2(0, -20)

var record: AudioEffectRecord
var http := HTTPRequest.new()
var piper_pid := -1
var whisper_pid := -1
var speaker := AudioStreamPlayer.new()
var scare_player := AudioStreamPlayer.new()
var growl_player := AudioStreamPlayer.new()
var music := AudioStreamPlayer.new()
var answer_sfx := AudioStreamPlayer.new()  # correct / wrong answer jingles
var correct_snd: AudioStream = load("res://sfx/correct.mp3")
var wrong_snd: AudioStream = load("res://sfx/wrong.mp3")
var scaring := false
var flash := 0.0
signal play_pressed
var menu := Control.new()
var menu_hint := Label.new()
var incoming_player := ""  # name the control room sent us; "" while no one is on the way
var line_decks := {}  # see _pick
var wait_s := 0.0  # seconds of silence while waiting for an answer
var say_id := 0  # bumped to cancel a line that is still playing
# Smooth motion: the pumpkin rests at `home` and _process adds bob, breathing and tremble on top.
var home := Vector2.ZERO
var shake := 4  # sprite shake in pixels while scaring
var hush := false  # music off: dead silence in the dark room
var walking := false  # win walk-past tween owns the sprite
var shown_anger := 0.0  # eases toward anger, so color and vignette never jump
var pop := 0.0  # squash-and-stretch kick when he starts talking
var was_talking := false
var mouth_until := 0.0  # keeps the mouth moving for audio_delay after the clip ends
# Lip-sync: mouth opening follows how loud the voice is right now (0..1, smoothed).
var voice_bus := -1
var mic_bus := -1
var voice_level := 0.0
# Talk frame to show at [quiet, medium, loud] voice level, per talk animation.
const TALK_FRAMES := {"talk": [0, 1, 2], "talk_laugh": [0, 1, 1], "talk_angry": [0, 1, 1], "talk_grumble": [0, 1, 1]}
# Game-show quiz state. The pumpkin hosts from the lower-left corner while the boxes are shown.
var quiz: Array = []  # current QUIZ entry, empty when no quiz is running
var quiz_wrong: Array = []  # options already guessed wrong
var quiz_deck: Array = []
var quizzes_done := 0
var revealing := false  # suspense pause before the answer is revealed; no input
var host_scale := 1.0  # pumpkin size factor (shrinks to host the quiz)
var quiz_ui := Control.new()
var question_box := Label.new()
var option_boxes: Array = []
# Intro cutscene: free fall through the dark, screaming, until a trapdoor rushes up and swallows her.
# The player is a girl of about 10 (her voice is set in tts_server.py).
var wind := AudioStreamPlayer.new()
var fall := -1.0  # 0..1 while falling, -1 otherwise
var fall_lines := []  # [x, phase, length] speed lines
var gore := {}  # landing sounds: bone cracks and blood (sfx/*.wav, compressed and normalized with sox; loaded at runtime)
const FALL_SECONDS := 7.0
# [seconds into the fall, line] screamed while falling (mood "scream").
const FALL_LINES := [
	[0.4, "Aaaaaaaaaaah! Hjeeeelp!"],
	[2.8, "Uff da, uff da, uff da! Neeei!"],
	[5.2, "Mammaaaa! Jeg vil hjem!"],
]
# [pause before, line, optional mood] right after she lands: short, the whole intro is about 30 s.
# "cry" lines are whined and sobbed.
const LAND_LINES := [
	[0.2, "Au! Au, au, au... Auuu."],
]
# [line, optional mood] she mutters between the challenges (one per transition, rotating).
const GIRL_ASIDES := [
	["Hvor er jeg egentlig? Det er stummende mørkt her."],
	["Huff. Det der kommer til å bli et skikkelig blåmerke."],
	["Au... au. Knærne mine."],
	["Okei. Ikke få panikk. Det går bra. Det går helt fint."],
	["Auuu... Jeg er bare litt... livredd."],
	["Hu-hu-hu... snufs... Jeg vil ikke være her...", "cry"],
	["Som om de to forrige etasjene ikke var skumle nok. Nå faller jeg gjennom gulvet også!"],
	["Au, au... albuen også."],
	["Fy søren, så kaldt det er her. Hvorfor tok jeg ikke på meg ullgenseren mormor strikket?"],
	["Jeg skulle jo bare hente en brødskive med brunost..."],
	["Au. Auuu."],
	["Mamma? Pappa? ...Neida. Selvfølgelig ikke."],
	["Neeei... Hu-hu... Nei! Jeg vil hjem!", "cry"],
]
const DARK_THOUGHT := "Hallo? Er det noen her?"
var sprite := AnimatedSprite2D.new()
var printer := AnimatedSprite2D.new()
var deck: Array = []
var riddle: Array
var score := 0
var busy := false
var won := false
var anger := 0.0
var talk_anim := "talk"
# Debug overlay with what Whisper heard and what Grim said. DEBUG=1 in .env shows it, F1 toggles.
var debug_label := Label.new()


static func _load_dotenv() -> Dictionary:
	var d := {}
	var f := FileAccess.open("res://.env", FileAccess.READ)
	while f and not f.eof_reached():
		var line := f.get_line().strip_edges()
		if "=" in line and not line.begins_with("#"):
			d[line.get_slice("=", 0).strip_edges()] = line.split("=", true, 1)[1].strip_edges()
	return d


func _env(key: String, default: String) -> String:
	var v := OS.get_environment(key)
	if v == "":
		v = dotenv.get(key, "")
	return v if v != "" else default


func _ready() -> void:
	# Mic -> muted bus with a Record effect (same setup as Godot's mic demo).
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "Mic")
	AudioServer.set_bus_mute(bus, true)
	record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus, record)
	AudioServer.add_bus_effect(bus, AudioEffectSpectrumAnalyzer.new())  # mic level, for "start" on the menu
	mic_bus = bus
	var mic := AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "Mic"
	add_child(mic)
	mic.play()
	_restart_recording()

	add_child(http)
	http.timeout = 10.0  # slow network: give up instead of freezing the game
	http.request_completed.connect(_on_llm)
	whisper_pid = OS.create_process(whisper_server, ["-m", whisper_model, "-l", "no", "-nt", "-ac", "500", "-bs", "3", "-bo", "3", "-t", "3", "--host", "127.0.0.1", "--port", str(WHISPER_PORT)])
	piper_pid = OS.create_process(piper_python, [ProjectSettings.globalize_path("res://tts_server.py"), piper_voice, str(PIPER_PORT)])

	# Voice effects (deep shadow layer, clarity EQ) are rendered by tts_server.py with sox,
	# so the audio thread only plays finished WAVs and never stutters from heavy DSP.
	bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "Voice")
	voice_bus = bus
	AudioServer.add_bus_effect(bus, AudioEffectSpectrumAnalyzer.new())  # loudness for lip-sync
	# The player's inner voice gets its own bus, so fast-forward (below) can pitch-correct it too
	# without touching the music on Master.
	var inner := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(inner, "Inner")
	for b in [bus, inner]:
		var fix := AudioEffectPitchShift.new()
		fix.pitch_scale = 1.0 / FAST_SPEED
		AudioServer.add_bus_effect(b, fix)
		AudioServer.set_bus_effect_enabled(b, AudioServer.get_bus_effect_count(b) - 1, false)
	speaker.bus = "Voice"
	add_child(speaker)
	var scream: AudioStream = load("res://sfx/scream.mp3")
	scare_player.stream = scream
	add_child(scare_player)
	growl_player.stream = scream
	add_child(growl_player)
	music.stream = load("res://sfx/music.mp3")
	music.stream.loop = true
	music.volume_db = MUSIC_DB
	add_child(music)
	music.play()
	add_child(answer_sfx)
	sprite.sprite_frames = _load_frames("pumpkin", PUMPKIN_ANIMS)
	printer.sprite_frames = _load_frames("printer", PRINTER_ANIMS)
	add_child(printer)
	add_child(sprite)
	wind.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://sfx/wind.wav"))  # sox-made
	for name in ["bone_crack", "bone_crack_horror", "blood_splatter", "body_rip"]:
		gore[name] = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://sfx/%s.wav" % name))
	add_child(wind)
	for i in 48:
		fall_lines.append([randf() * 640.0, randf(), randf_range(12.0, 70.0)])
	_build_quiz_ui()
	_build_tf_ui()
	_build_menu()
	debug_label.position = Vector2(8, 300)
	debug_label.size = Vector2(624, 56)
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	debug_label.add_theme_font_size_override("font_size", 10)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 4)
	debug_label.visible = _env("DEBUG", "") == "1"
	add_child(debug_label)

	_connect_control_room()

	_start_keyboard_readers()
	_start_pw_record()
	if api_key == "":
		push_error("Mangler LLM_API_KEY")
		return
	_start()


func _start() -> void:
	score = 0
	won = false
	anger = 0.0
	deck.clear()
	var center := get_viewport_rect().size / 2
	home = center + SPRITE_LIFT
	sprite.position = home
	walking = false
	shown_anger = 0.0
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	sprite.modulate.a = 1.0
	host_scale = 1.0
	printer.position = center
	printer.hide()
	printer.play("idle")
	riddle = []
	quiz = []
	quiz_ui.hide()
	tf_ui.hide()
	tf_done = 0
	sprite.modulate.a = 0.0  # pitch dark until the fall
	_update_menu_hint()
	menu.show()
	await play_pressed
	menu.hide()
	incoming_player = ""
	control_room.start_game()
	await _fall_in()
	await _greet()
	await _say(_pick(INTRO_RULES))
	_start_quiz()


func _next_riddle() -> void:
	if deck.is_empty():
		deck = RIDDLES.duplicate()
		deck.shuffle()
	riddle = deck.pop_back()


# Speaks text; await it to wait until the line has finished playing.
# bus "Voice" = deep pumpkin, "Master" = plain voice for the player's inner monologue.
# Sentences are synthesized back to back (independent of playback), so the first can play
# while the rest are generated and a short sentence never leaves a gap before a long one.
# *Words between stars* are spoken a bit deeper and slower, with a faint demonic layer underneath.
func _say(text: String, bus := "Voice", length := voice_length, mood := "") -> void:
	print("%s (poeng %d): %s" % [bus, score, text])
	_debug("Grim" if bus == "Voice" else "Indre", text.replace("*", ""))
	say_id += 1
	var id := say_id
	busy = true
	speaker.bus = "Inner" if bus == "Master" else bus
	var speech := _speech_parts(text, bus, length, mood)
	var parts: PackedStringArray = speech[0]
	var fxs: Array = speech[1]
	var anims: Array = speech[2]
	var clips := []
	clips.resize(parts.size())
	_synth_all(parts, fxs, clips, id)
	for i in parts.size():
		while clips[i] == null:
			await get_tree().process_frame
		if id != say_id:
			return
		if clips[i].is_empty():
			continue
		var stream := AudioStreamWAV.load_from_buffer(clips[i])
		if stream == null:  # broken clip (e.g. a corrupted cache file): skip it instead of waiting forever
			push_error("Ødelagt lydklipp hoppet over: " + parts[i])
			continue
		talk_anim = anims[i]
		speaker.stream = stream
		speaker.play()
		await speaker.finished
		if id != say_id:
			return
	# No talking over Grim: the talk button stays locked until the last word is heard.
	if audio_delay > 0.0:
		await get_tree().create_timer(audio_delay).timeout
	if id == say_id:
		busy = false


# Splits a line into sentences with the voice settings for each: [sentences, fx dicts, talk animations].
# Every request is one sentence, so the TTS cache (voice_cache/) is shared between lines that reuse one.
# mood picks the delivery: calm or angry Grim, *dark* parts, or the player's inner voice.
func _speech_parts(text: String, bus: String, length: String, mood := "") -> Array:
	var fx := {"length_scale": float(length), "mood": mood if mood != "" else "inner"}
	if bus == "Voice":
		var angry := anger >= 40.0
		fx = {"length_scale": float(length), "pitch": voice_pitch, "mood": "angry" if angry else "calm",
			"shadow_db": roundf(lerpf(-20.0, -8.0, (anger - 40.0) / 60.0)) if angry else null}
	var normal_anim := _pick_talk(text)
	var parts := PackedStringArray()
	var fxs := []
	var anims := []
	var dark := false
	for chunk in text.split("*"):
		if chunk.strip_edges() != "":
			for sentence in _sentences(chunk):
				parts.append(sentence)
				anims.append("talk_angry" if dark and bus == "Voice" else normal_anim)
				if dark and bus == "Voice":
					fxs.append(fx.merged({"pitch": 0.7, "shadow_db": -14.0, "length_scale": float(length) * 1.2, "mood": "dark"}, true))
				else:
					fxs.append(fx)
		dark = not dark
	return [parts, fxs, anims]


# All sentences are requested at once (the TTS server handles them in parallel); clips fill in as they land.
func _synth_all(parts: PackedStringArray, fxs: Array, clips: Array, id: int) -> void:
	for i in parts.size():
		if id != say_id:
			return
		_synth(parts[i], fxs[i], clips, i)


# Asks the TTS server for a line ahead of time, so it is cached by the time Grim says it.
func _prefetch(text: String) -> void:
	var speech := _speech_parts(text, "Voice", voice_length)
	var clips := []
	clips.resize(speech[0].size())
	for i in speech[0].size():
		_synth(speech[0][i], speech[1][i], clips, i)


# Fills clips[i] with WAV bytes from the TTS server (empty on failure).
func _synth(text: String, fx: Dictionary, clips: Array, i: int) -> void:
	var body := JSON.stringify(fx.merged({"text": text}))
	for attempt in 60:  # the server needs a few seconds to load the voice at startup
		var req := HTTPRequest.new()
		add_child(req)
		req.request("http://127.0.0.1:%d/synthesize" % PIPER_PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		var res: Array = await req.request_completed
		req.queue_free()
		if res[1] == 200:
			clips[i] = res[3]
			return
		await get_tree().create_timer(1.0).timeout
	push_error("TTS-serveren svarer ikke")
	clips[i] = PackedByteArray()


func _sentences(text: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var carry := ""  # punctuation-only bits ("..." before "Neida") go with the next sentence
	var has_word := RegEx.create_from_string("[\\p{L}\\p{N}]")
	for m in RegEx.create_from_string("[^.!?]+[.!?]*").search_all(text):
		var part := carry + m.get_string().strip_edges()
		carry = ""
		if has_word.search(part) == null:
			carry = part
		elif part != "":
			parts.append(part)
	return parts if not parts.is_empty() else PackedStringArray([text])


func _jumpscare() -> void:
	busy = true
	say_id += 1
	speaker.stop()
	growl_player.stop()
	scare_player.play()
	if audio_delay > 0.0:
		await get_tree().create_timer(audio_delay).timeout
	scaring = true  # visuals start only when the scream is actually heard
	flash = 1.0
	# Lunge at the camera (meant to be sudden): face fills the screen, then eases back.
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE * SPRITE_SCALE * 3, 0.08)
	tw.parallel().tween_property(sprite, "position", home - Vector2(0, 110), 0.08)
	tw.parallel().tween_property(self, "flash", 0.0, 0.5)
	tw.tween_interval(0.6)
	tw.tween_property(sprite, "scale", Vector2.ONE * SPRITE_SCALE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "position", home, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	scaring = false
	busy = false


# Talk animation from what he says: anger first, then laughing, then grumbling.
func _pick_talk(text: String) -> String:
	var t := text.to_lower()
	if anger >= 60 or "grr" in t or "brøl" in t:
		return "talk_angry"
	for laugh in ["hehe", "haha", "hoho", "muha"]:
		if laugh in t:
			return "talk_laugh"
	for grumble in ["hmpf", "hmf", "uff", "sukk"]:
		if grumble in t:
			return "talk_grumble"
	return "talk"


func _exit_tree() -> void:
	for pid in [piper_pid, whisper_pid, keys_pid, pw_pid]:
		if pid > 0:
			OS.kill(pid)


func _debug(who: String, text: String) -> void:
	var lines := debug_label.text.split("\n", false)
	lines.append("%s: %s" % [who, text])
	debug_label.text = "\n".join(lines.slice(-3))


# Talk button: space/enter, or hold the left mouse button.
func _talk_event(e: InputEvent, pressed: bool) -> bool:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		return e.pressed == pressed
	return e.is_action_pressed("ui_accept") if pressed else e.is_action_released("ui_accept")


# _input, not _unhandled_input: the full-screen root Control would otherwise swallow mouse clicks.
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F1:
		debug_label.visible = not debug_label.visible
	if _talk_event(e, true):
		_talk(true)
	elif _talk_event(e, false):
		_talk(false)


# Fast-forward: holding the talk button while speech plays makes it FAST_SPEED times faster.
# pitch_scale alone would also make it squeaky; a pitch shift on the speech buses brings it back down.
const FAST_SPEED := 2.0
var fast := false


func _set_fast(on: bool) -> void:
	fast = on
	speaker.pitch_scale = FAST_SPEED if on else 1.0
	for b in ["Voice", "Inner"]:
		var i := AudioServer.get_bus_index(b)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 1, on)


# The mic records all the time, so an answer can include PRE_ROLL seconds from before the button
# was pressed (people start talking as they press) and POST_ROLL after release.
const PRE_ROLL := 0.5
const POST_ROLL := 0.3
const MAX_HOLD_MS := 10000  # auto-release so a stuck key never sends Whisper a huge clip
var holding := false
var rec_started_ms := 0
var press_ms := 0


func _restart_recording() -> void:
	record.set_recording_active(false)
	record.set_recording_active(true)
	rec_started_ms = Time.get_ticks_msec()


# Hold to record, release to send. Safe to call twice (keyboard can arrive both via Godot and evdev).
func _talk(pressed: bool) -> void:
	if menu.visible:
		if pressed and _can_start():
			play_pressed.emit()
		return
	# Held while someone is talking (or about to): fast-forward the speech instead of answering.
	if pressed and busy and not holding and not won and not scaring:
		_set_fast(true)
		return
	if not pressed and fast:
		_set_fast(false)
		return
	if pressed and not busy and not won and not revealing and (riddle or quiz or tf or greeting) and not holding:
		say_id += 1
		speaker.stop()
		holding = true
		press_ms = Time.get_ticks_msec()
	elif not pressed and holding:
		holding = false
		busy = true
		await get_tree().create_timer(POST_ROLL).timeout
		var answer := _take_recording(press_ms)
		if answer == null:
			busy = false
			return
		if answer.get_length() < PRE_ROLL + POST_ROLL + 0.3:  # a quick tap is not an answer
			busy = false
			_say("Jeg hørte ingenting. Hold inne knappen mens du snakker.")
			return
		var path := ProjectSettings.globalize_path("user://svar.wav")
		answer.save_to_wav(path)
		_on_heard(await _transcribe(_clean_audio(path)))


# Stops the always-on recording and returns it from PRE_ROLL before `from_ms` to now (null on failure).
func _take_recording(from_ms: int) -> AudioStreamWAV:
	if pw_pid > 0:
		return _take_pw_recording(from_ms)
	record.set_recording_active(false)
	var wav := record.get_recording()
	var started := rec_started_ms
	_restart_recording()
	if wav == null:
		return null
	# 16-bit stereo = 4 bytes per frame.
	var from_s := maxf(0.0, (from_ms - started) / 1000.0 - PRE_ROLL)
	var clip := AudioStreamWAV.new()
	clip.format = wav.format
	clip.mix_rate = wav.mix_rate
	clip.stereo = wav.stereo
	clip.data = wav.data.slice(int(from_s * wav.mix_rate) * 4)
	return clip


# Start screen: when the mic gets loud, wait for the word to end and check if it was "start".
const START_WORDS := ["start", "spill", "begynn"]
var menu_listening := false


func _listen_for_start() -> void:
	var analyzer := AudioServer.get_bus_effect_instance(mic_bus, 1) as AudioEffectSpectrumAnalyzerInstance
	var db := linear_to_db(analyzer.get_magnitude_for_frequency_range(200, 4000).length())
	if db < mic_start_db:
		return
	print("Meny: mic %.0f dB" % db)
	menu_listening = true
	var heard_ms := Time.get_ticks_msec()
	await get_tree().create_timer(1.5).timeout  # let them finish the word
	var clip := _take_recording(heard_ms)
	if clip and menu.visible:
		var path := ProjectSettings.globalize_path("user://start.wav")
		clip.save_to_wav(path)
		var text := (await _transcribe(_clean_audio(path))).to_lower()
		_debug("Meny", text)
		print("Meny hørte: ", text)
		if menu.visible and _can_start() and START_WORDS.any(func(w): return w in text):
			play_pressed.emit()
	menu_listening = false


# 16 kHz mono (what Whisper uses), rumble cut, level normalized. Falls back to the raw file without sox.
func _clean_audio(path: String) -> PackedByteArray:
	var clean := path.get_basename() + "_clean.wav"
	if OS.execute("sox", [path, "-r", "16000", "-c", "1", clean, "highpass", "80", "norm", "-3"]) == 0:
		return FileAccess.get_file_as_bytes(clean)
	return FileAccess.get_file_as_bytes(path)


# Linux/Pi: the mic is recorded by PipeWire (pw-record) instead of Godot. Godot's own capture on the Pi
# had clicks and dropouts all through it, which wrecked Whisper's transcriptions. pw-record streams raw
# 16 kHz mono into a rolling buffer; answers are cut from it the same way as from the Godot recording.
const PW_RATE := 16000
const PW_BYTES_PER_S := PW_RATE * 2  # s16 mono
const PW_KEEP_S := 20
var pw_pid := -1
var pw_buf := PackedByteArray()
var pw_mutex := Mutex.new()


func _start_pw_record() -> void:
	if OS.get_name() != "Linux":
		return
	var proc := OS.execute_with_pipe("pw-record", ["--raw", "--rate", str(PW_RATE), "--channels", "1", "--format", "s16", "-"])
	if proc.is_empty():
		push_error("pw-record kunne ikke startes, bruker Godot-opptak")
		return
	pw_pid = proc["pid"]
	var t := Thread.new()
	t.start(_read_pw.bind(proc["stdio"]))


func _read_pw(pipe: FileAccess) -> void:
	# A short read (less buffered than asked for) sets a read error on the pipe; it is not the end.
	while OS.is_process_running(pw_pid):
		var chunk := pipe.get_buffer(PW_BYTES_PER_S / 10)
		if chunk.size() < PW_BYTES_PER_S / 10:
			OS.delay_msec(20)
		pw_mutex.lock()
		pw_buf.append_array(chunk)
		if pw_buf.size() > PW_KEEP_S * PW_BYTES_PER_S:
			var cut := pw_buf.size() - PW_KEEP_S * PW_BYTES_PER_S
			pw_buf = pw_buf.slice(cut - cut % 2)  # even cut: the buffer keeps starting on a whole sample
		pw_mutex.unlock()


# The last part of the rolling buffer: from PRE_ROLL before `from_ms` up to now.
func _take_pw_recording(from_ms: int) -> AudioStreamWAV:
	var seconds := (Time.get_ticks_msec() - from_ms) / 1000.0 + PRE_ROLL
	var n := int(seconds * PW_RATE) * 2
	pw_mutex.lock()
	var start := maxi(0, pw_buf.size() - n)
	var data := pw_buf.slice(start - start % 2)  # chunks can end mid-sample; start on a whole one
	pw_mutex.unlock()
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = PW_RATE
	clip.stereo = false
	clip.data = data
	return clip


# Linux/Pi: read the space key straight from the keyboard via keys.py. The Pi desktop (labwc) did not
# deliver key presses to the game window at all, and Godot cannot open /dev/input itself.
var keys_pid := -1


func _start_keyboard_readers() -> void:
	if OS.get_name() != "Linux":
		return
	var proc := OS.execute_with_pipe("python3", ["-u", ProjectSettings.globalize_path("res://keys.py")])
	if proc.is_empty():
		push_error("keys.py kunne ikke startes")
		return
	keys_pid = proc["pid"]
	var t := Thread.new()
	t.start(_read_keys.bind(proc["stdio"]))


func _read_keys(pipe: FileAccess) -> void:
	while pipe.is_open() and pipe.get_error() == OK:
		var line := pipe.get_line().strip_edges()
		if line == "1" or line == "0":
			_talk.call_deferred(line == "1")
		elif line != "":
			print.call_deferred("keys.py: " + line)


func _vocabulary() -> String:
	# During the quiz only its own letters and options: tested on the Pi, this is what makes
	# "Se" come out as C (a long word list made it guess wrong).
	if quiz:
		return "A, B, C, D. " + ", ".join(PackedStringArray(quiz[1])) + "."
	if tf:
		return "Sant, løgn, usant, ja, nei."
	var words := PackedStringArray(["A", "B", "C", "D"])
	for q in QUIZ:
		words.append_array(q[1])
	for r in RIDDLES:
		if not r[2].is_empty():
			words.append(r[2][0])
	return ", ".join(words)


func _transcribe(wav: PackedByteArray) -> String:
	var boundary := "grimboundary"
	var body := ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"svar.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer()
	body.append_array(wav)
	body.append_array(("\r\n--%s\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\ntext" % boundary).to_utf8_buffer())
	# All answer words as vocabulary, so names like Galdhøpiggen are spelled right (no bias to the current answer).
	body.append_array(("\r\n--%s\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\n%s\r\n--%s--\r\n" % [boundary, _vocabulary(), boundary]).to_utf8_buffer())
	var req := HTTPRequest.new()
	add_child(req)
	req.request_raw("http://127.0.0.1:%d/inference" % WHISPER_PORT, ["Content-Type: multipart/form-data; boundary=" + boundary], HTTPClient.METHOD_POST, body)
	var res: Array = await req.request_completed
	req.queue_free()
	if res[1] != 200:
		push_error("Whisper-serveren svarer ikke (%d)" % res[1])
		return ""
	return res[3].get_string_from_utf8().strip_edges()


func _on_heard(text: String) -> void:
	text = text.replace("[BLANK_AUDIO]", "").strip_edges()
	if text == "":
		_debug("Du", "(hørte ingenting)")
		_say("Jeg hørte ingenting. Hold inne knappen mens du snakker.")
		return
	print("Du: " + text)
	_debug("Du", text)
	if greeting:
		_greet_reply(text)
		return
	if tf:
		_tf_answer(text)
		return
	if quiz:
		_quiz_answer(text)
		return
	# Decided locally when possible: no LLM round trip, and repeating the riddle can never win.
	if _has_keyword(text):
		_on_correct(_pick(CORRECT_LINES))
	elif _asks_again(text):
		_say(ASK_AGAIN_LINE + riddle[0])
	elif _is_repeat(text):
		_add_anger(ANGER_OTHER)
		_say(REPEAT_LINE + riddle[0])
	else:
		_ask(text)


func _asks_again(text: String) -> bool:
	var t := text.to_lower()
	for phrase in ASK_AGAIN:
		if phrase in t:
			return true
	return false


static func _words(text: String) -> PackedStringArray:
	return RegEx.create_from_string("[^\\p{L}\\p{N}]+").sub(text.to_lower(), " ", true).split(" ", false)


# True when most of what the player said is just the riddle's own words.
func _is_repeat(text: String) -> bool:
	var said := _words(text)
	var riddle_words := _words(riddle[0])
	var overlap := 0
	for w in said:
		if w in riddle_words:
			overlap += 1
	return said.size() >= 3 and overlap >= said.size() * 0.6


# A keyword counts even one letter off (Whisper hears short words badly, e.g. "hull" as "rull"),
# but only for keywords of 4+ letters, so "tre"/"kam" must still be exact.
func _has_keyword(text: String) -> bool:
	var riddle_words := _words(riddle[0])
	for w in _words(text):
		if w in riddle_words:
			continue
		for k in riddle[2]:
			if w == k or (k.length() >= 4 and _distance(w, k) <= 1):
				return true
	return false


# Levenshtein edit distance.
static func _distance(a: String, b: String) -> int:
	var prev := range(b.length() + 1)
	for i in a.length():
		var cur := [i + 1]
		for j in b.length():
			cur.append(mini(mini(prev[j + 1] + 1, cur[j] + 1), prev[j] + (0 if a[i] == b[j] else 1)))
		prev = cur
	return prev[b.length()]


func _ask(text: String) -> void:
	busy = true
	var body := {
		"model": model,
		"messages": [
			{"role": "system", "content": SYSTEM % [riddle[0], riddle[1]]},
			{"role": "user", "content": text},
		],
		"reasoning_effort": "low",
	}
	if "openrouter.ai" in base_url:
		# Fastest provider instead of a random one: ~0.9 s instead of 0.8-8 s.
		body["provider"] = {"sort": "latency"}
	var headers := ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	http.request(base_url + "/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _on_llm(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not data is Dictionary:
		push_error("LLM-feil %d: %s" % [code, body.get_string_from_utf8().left(200)])
		_say(LLM_ERROR_LINE + riddle[0])
		return
	var reply: String = data.choices[0].message.content
	var correct := reply.begins_with("[RIKTIG]")
	var other := reply.begins_with("[ANNET]")
	if correct:
		pass  # anger handled in _on_correct
	elif other:
		_add_anger(ANGER_OTHER)
	else:
		_jingle(wrong_snd)
		_add_anger(ANGER_WRONG)
		if anger >= SCARE_ON_WRONG_MIN_ANGER and randf() < SCARE_ON_WRONG_CHANCE:
			await _jumpscare()
		elif anger >= 40.0:
			_growl(-16.0)  # quiet snarl under his answer
	# Only fixed lines are spoken, so every one of them is prerendered (no live voice needed).
	if correct:
		_on_correct(_pick(CORRECT_LINES))
	elif other:
		_say(_pick(OTHER_LINES) + " " + riddle[0])
	else:
		_say(_pick(WRONG_LINES))


# ---------- Intro: free fall into the dark room ----------

func _fall_in() -> void:
	sprite.modulate.a = 0.0
	hush = true  # only wind and her scream
	wind.volume_db = -30.0
	wind.play()
	create_tween().tween_property(wind, "volume_db", 0.0, 1.5)
	fall = 0.0
	var tw := create_tween()
	tw.tween_property(self, "fall", 1.0, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_talk()
	await tw.finished
	# Through the trapdoor: everything cuts to black and silence at once.
	fall = -1.0
	say_id += 1
	speaker.stop()
	wind.stop()
	_set_fast(false)
	# She hits the floor: bones crack, something splatters.
	await get_tree().create_timer(0.5).timeout
	_sfx("bone_crack_horror", GORE_DB)
	_sfx("body_rip", GORE_DB)
	await get_tree().create_timer(0.35).timeout
	_sfx("blood_splatter", GORE_DB)
	await get_tree().create_timer(1.2).timeout
	for line in LAND_LINES:
		await get_tree().create_timer(line[0]).timeout
		await _say(line[1], "Master", "1.0", line[2] if line.size() > 2 else "")
	hush = true  # the music dies with the light
	await get_tree().create_timer(1.0).timeout  # total darkness
	await _say(DARK_THOUGHT, "Master", "1.0")
	await get_tree().create_timer(3.0).timeout  # dead silence: long enough to think nothing happens
	await _appear_scare()
	await get_tree().create_timer(2.0).timeout  # black again
	# Only now the candle inside the pumpkin catches: a few flickers, then it burns.
	var light := create_tween()
	for a in [0.25, 0.0, 0.5, 0.15, 0.8, 0.5, 1.0]:
		light.tween_property(sprite, "modulate:a", a, 0.12)
	await light.finished
	hush = false
	await get_tree().create_timer(0.8).timeout


# Grim's opener, then he waits for her to say something and answers it before going on.
func _greet() -> void:
	greet_opener = _pick(INTRO_OPENERS)
	await _say(greet_opener)
	greeting = true
	var deadline := Time.get_ticks_msec() + GREET_WAIT * 1000.0
	while greeting:
		if Time.get_ticks_msec() > deadline and not busy and not holding:
			greeting = false
			await _say(_pick(GREET_SILENT))
			return
		await get_tree().process_frame


func _greet_reply(_text: String) -> void:
	busy = true
	await _say(_pick(GREET_REPLIES))
	greeting = false


# Her screams on cue while she falls; whatever is still playing is cut off at the trapdoor.
func _fall_talk() -> void:
	var start := Time.get_ticks_msec()
	for line in FALL_LINES:
		while fall >= 0.0 and Time.get_ticks_msec() - start < line[0] * 1000.0:
			await get_tree().process_frame
		if fall < 0.0:
			return
		_say(line[1], "Master", "1.0", "scream")


# The jumpscare out of total darkness. Face, red and sound all start on the same frame: no warning,
# no zoom-in. The face is simply there, full screen, shaking hard and strobing red while he screams.
const SCARE_DB := 8.0  # louder than everything else; clips a little on purpose
func _appear_scare() -> void:
	scaring = true
	shake = 12
	sprite.modulate = Color.WHITE
	sprite.position = get_viewport_rect().size / 2 - Vector2(0, 6.0 * SPRITE_SCALE * 2.0)  # eyes and mouth centered
	sprite.scale = Vector2.ONE * SPRITE_SCALE * 2.0
	scare_player.volume_db = SCARE_DB
	scare_player.play()
	growl_player.pitch_scale = 0.6  # deep copy underneath: hits in the chest
	growl_player.volume_db = SCARE_DB
	growl_player.play()
	for i in 12:  # ~1.2 s of red strobe
		flash = 0.8 if i % 2 == 0 else 0.2
		sprite.modulate = Color(1, 0.4, 0.4) if i % 2 == 0 else Color.WHITE
		await get_tree().create_timer(0.1).timeout
	# Cut to black and silence at once.
	flash = 0.0
	sprite.modulate = Color(1, 1, 1, 0)
	scaring = false
	shake = 4
	scare_player.stop()
	growl_player.stop()
	scare_player.volume_db = 0.0
	growl_player.volume_db = 0.0
	growl_player.pitch_scale = 1.0


# Free fall, seen from above: speed lines rush up past her, and a trapdoor far below grows until its
# black opening fills the screen.
func _draw_fall() -> void:
	var view := get_viewport_rect().size
	var now := Time.get_ticks_msec() / 1000.0
	var speed := lerpf(300.0, 1400.0, fall)
	for l in fall_lines:
		var y := view.y - fposmod(l[1] * view.y * 3.0 + now * speed, view.y + l[2])
		draw_rect(Rect2(l[0], y, 2, l[2] * (0.6 + fall)), Color(0.8, 0.8, 1.0, 0.12 + 0.25 * fall))
	var z := clampf((fall - 0.35) / 0.65, 0.0, 1.0)
	if z <= 0.0:
		return
	# Hyperbolic approach: tiny for a while, then it rushes up at the very end.
	var k := 0.04 / maxf(1.02 - z, 0.001)
	var center := view / 2 + Vector2(sin(now * 1.3) * 30.0, cos(now * 0.9) * 20.0) * (1.0 - z)
	var size := Vector2(120, 80) * k * 6.0
	var r := Rect2(center - size / 2, size)
	draw_rect(r.grow(size.x * 0.08), Color("3a2414"))  # frame
	draw_rect(r, Color("070509"))  # the open hole: pitch black
	var lid := Rect2(r.position + Vector2(0, -size.y * 0.55), Vector2(size.x, size.y * 0.55))
	draw_rect(lid, Color("5a3a22"))  # the lid, swung open
	for i in 3:  # planks
		draw_rect(Rect2(lid.position + Vector2(size.x * (0.05 + i * 0.32), size.y * 0.05), Vector2(size.x * 0.26, size.y * 0.45)), Color("6b4629"))
	draw_rect(Rect2(r.position.x, r.position.y + size.y * 0.04, size.x, size.y * 0.03), Color(1.0, 0.5, 0.1, 0.25))  # faint glow inside


# ---------- Main menu ----------

# Just a dim, slowly pulsing line in the dark: no title, no pumpkin. Any talk key (space,
# the big button via keys.py) or a click starts the game.
func _build_menu() -> void:
	add_child(menu)
	menu.hide()
	var hint := menu_hint
	hint.position = Vector2(0, 168)
	hint.size = Vector2(640, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.uppercase = true
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("8a7f8e"))
	menu.add_child(hint)
	var pulse := hint.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	pulse.tween_property(hint, "modulate:a", 0.15, 2.5)
	pulse.tween_property(hint, "modulate:a", 0.8, 2.5)


# ---------- Game-show quiz (round 1) ----------

# Pixel-style box: thick square border, notched (not rounded) corners, hard drop shadow.
func _box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(3)
	sb.corner_detail = 1  # one straight cut per corner = pixel notch
	sb.anti_aliasing = false
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(4, 4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


func _build_quiz_ui() -> void:
	# Layout in the 640x360 base resolution: pumpkin hosts bottom-left, question above the
	# middle, a 2x2 grid of answers underneath (Who Wants to Be a Millionaire, in Halloween colors).
	add_child(quiz_ui)
	quiz_ui.hide()
	question_box.position = Vector2(130, 70)
	question_box.size = Vector2(490, 74)
	question_box.uppercase = true
	question_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_box.add_theme_font_size_override("font_size", 24)
	question_box.add_theme_stylebox_override("normal", _box_style(Color("1a0b2e"), Color("ff8c1a")))
	quiz_ui.add_child(question_box)
	for i in 4:
		var box := Label.new()
		box.position = Vector2(130 + (i % 2) * 250, 162 + (i / 2) * 58)
		box.size = Vector2(240, 46)
		box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.uppercase = true
		box.add_theme_font_size_override("font_size", 22)
		quiz_ui.add_child(box)
		option_boxes.append(box)


func _set_box(i: int, state: String) -> void:
	var colors := {
		"normal": [Color("1a0b2e"), Color("e8b931")],
		"locked": [Color("c25a00"), Color("ffd27a")],
		"right": [Color("1d7a33"), Color("8dff9e")],
		"wrong": [Color("6e1414"), Color("ff5a5a")],
	}
	var box: Label = option_boxes[i]
	box.add_theme_stylebox_override("normal", _box_style(colors[state][0], colors[state][1]))
	box.modulate.a = 0.4 if state == "wrong" else 1.0


func _quiz_spoken() -> String:
	var parts := PackedStringArray()
	for i in 4:
		parts.append("%s: %s." % [SPOKEN_LETTERS[i], quiz[1][i]])
	return quiz[0] + " " + " ".join(parts)


func _start_quiz() -> void:
	quizzes_done = 0
	# Pumpkin shrinks and glides to the lower-left corner like a game-show host.
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "home", Vector2(72, 272), 1.2)
	tw.tween_property(self, "host_scale", 0.45, 1.2)
	await tw.finished
	_show_quiz_question("Her kommer det første spørsmålet. ")


func _show_quiz_question(lead: String) -> void:
	if quiz_deck.is_empty():
		quiz_deck = QUIZ.duplicate()
		quiz_deck.shuffle()
	quiz = quiz_deck.pop_back()
	quiz_wrong = []
	question_box.text = quiz[0]
	for i in 4:
		option_boxes[i].visible = true
		option_boxes[i].text = "%s:  %s" % [LETTERS[i], quiz[1][i]]
		_set_box(i, "normal")
	# Question first, then the four boxes pop in one after another.
	quiz_ui.show()
	for node in [question_box] + option_boxes:
		node.modulate.a = 0.0
		node.scale = Vector2(0.9, 0.9)
		node.pivot_offset = node.size / 2
	var reveal := create_tween()
	for node in [question_box] + option_boxes:
		reveal.tween_property(node, "modulate:a", 1.0, 0.25)
		reveal.parallel().tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_say(lead + _quiz_spoken() + " Si svaret du tror er riktig!")


# Option index from what the player said: the option's own words first, then a spoken letter.
func _quiz_pick(text: String) -> int:
	var said := PackedStringArray()
	for w in _words(text):
		if not w in STOPWORDS:
			said.append(NUMBER_WORDS.get(w, w))
	for i in 4:
		for word in _words(quiz[1][i]):
			if word in STOPWORDS:
				continue
			for w in said:
				if w == word or (word.length() >= 4 and _distance(w, word) <= 1):
					return i
	var pick := -1
	for w in _words(text):
		if LETTER_WORDS.has(w):
			pick = LETTER_WORDS[w]  # last letter wins: "jeg tror det er B"
	return pick


func _quiz_answer(text: String) -> void:
	if _asks_again(text):
		_say(ASK_AGAIN_LINE + _quiz_spoken())
		return
	var i := _quiz_pick(text)
	if i < 0:
		_say("Hehe. Jeg forsto ikke. Si selve svaret, for eksempel %s, lille dødelige." % quiz[1][randi() % 4])
		return
	if i in quiz_wrong:
		_say("Det har du allerede prøvd! Velg et annet svar.")
		return
	revealing = true
	_set_box(i, "locked")
	await get_tree().create_timer(1.5).timeout  # silent suspense with the box locked
	if i == quiz[2]:
		_jingle(correct_snd)
		_set_box(i, "right")
		_celebrate(option_boxes[i])
		_add_anger(ANGER_CORRECT)
		score += 1
		quizzes_done += 1
		await get_tree().create_timer(1.0).timeout  # let the jingle play first
		if quizzes_done < QUIZ_ROUNDS:
			await _say(_pick(CORRECT_LINES))
			var out := create_tween()
			out.tween_property(quiz_ui, "modulate:a", 0.0, 0.4)
			await out.finished
			quiz_ui.modulate.a = 1.0
			revealing = false
			await _girl_aside()
			_show_quiz_question("Spørsmål nummer to. ")
			return
		await _say(_pick(CORRECT_LINES))
		var fade := create_tween()
		fade.tween_property(quiz_ui, "modulate:a", 0.0, 0.4)
		await fade.finished
		quiz_ui.hide()
		quiz_ui.modulate.a = 1.0
		quiz = []
		revealing = false
		await _girl_aside()
		_show_tf("Neste utfordring: sant eller løgn! ")
	else:
		_jingle(wrong_snd)
		_set_box(i, "wrong")
		_fail(option_boxes[i])
		quiz_wrong.append(i)
		_add_anger(ANGER_WRONG)
		await get_tree().create_timer(1.0).timeout
		revealing = false
		_say(_pick(WRONG_LINES) + " Prøv igjen, lille dødelige.")


# ---------- True or false (rounds 2 and 3) ----------

var tf: Array = []  # current TRUE_FALSE entry, empty when not running
var tf_deck: Array = []
var tf_done := 0
var tf_ui := Control.new()
var tf_title := Label.new()
var tf_statement := Label.new()
var tf_cards: Array = []  # [SANT, LØGN]
const TF_COLORS := [Color("2fbf5a"), Color("e8393a")]  # SANT green, LØGN red


# Its own look: a title, the statement on a purple panel, and two big cards, green SANT and red LØGN.
# Cards stay clear of the pumpkin hosting in the lower-left corner.
func _build_tf_ui() -> void:
	add_child(tf_ui)
	tf_ui.hide()
	tf_title.text = "Sant eller løgn?"
	tf_title.uppercase = true
	tf_title.position = Vector2(130, 18)
	tf_title.size = Vector2(490, 34)
	tf_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tf_title.add_theme_font_size_override("font_size", 30)
	tf_title.add_theme_color_override("font_color", Color("e8b931"))
	tf_title.add_theme_color_override("font_outline_color", Color("1a0b2e"))
	tf_title.add_theme_constant_override("outline_size", 8)
	tf_ui.add_child(tf_title)
	tf_statement.position = Vector2(150, 62)
	tf_statement.size = Vector2(450, 100)
	tf_statement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tf_statement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tf_statement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tf_statement.uppercase = true
	tf_statement.add_theme_font_size_override("font_size", 24)
	tf_statement.add_theme_stylebox_override("normal", _box_style(Color("24103a"), Color("a259ff")))
	tf_ui.add_child(tf_statement)
	for i in 2:
		var card := Label.new()
		card.text = ["Sant", "Løgn"][i]
		card.uppercase = true
		card.position = Vector2(185 + i * 230, 190)
		card.size = Vector2(190, 84)
		card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_theme_font_size_override("font_size", 40)
		card.add_theme_color_override("font_outline_color", Color("1a0b2e"))
		card.add_theme_constant_override("outline_size", 8)
		tf_ui.add_child(card)
		tf_cards.append(card)


func _set_card(i: int, state: String) -> void:
	var c: Color = TF_COLORS[i]
	var bg: Color = {"normal": Color("1a0b2e"), "locked": Color("c25a00"), "right": c.darkened(0.35),
		"wrong": Color("3a0d0d")}[state]
	var border: Color = Color("ffd27a") if state == "locked" else (Color.WHITE if state == "right" else c)
	tf_cards[i].add_theme_stylebox_override("normal", _box_style(bg, border))
	tf_cards[i].add_theme_color_override("font_color", c.lightened(0.3) if state == "normal" else Color.WHITE)
	tf_cards[i].modulate.a = 0.35 if state == "wrong" else 1.0


func _tf_spoken() -> String:
	return tf[0] + " Sant eller løgn?"


func _show_tf(lead: String) -> void:
	if tf_deck.is_empty():
		tf_deck = TRUE_FALSE.duplicate()
		tf_deck.shuffle()
	tf = tf_deck.pop_back()
	tf_statement.text = tf[0]
	tf_title.text = "Sant eller løgn?  %d/%d" % [tf_done + 1, TF_ROUNDS]
	for i in 2:
		_set_card(i, "normal")
	tf_ui.modulate.a = 1.0
	tf_ui.show()
	var nodes := [tf_title, tf_statement, tf_cards[0], tf_cards[1]]
	for node in nodes:
		node.modulate.a = 0.0
		node.scale = Vector2(0.85, 0.85)
		node.pivot_offset = node.size / 2
	var reveal := create_tween()
	for node in nodes:
		reveal.tween_property(node, "modulate:a", 1.0, 0.22)
		reveal.parallel().tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_say(lead + _tf_spoken())


# 1 = true, 0 = false, -1 = could not tell (both or neither).
func _tf_pick(text: String) -> int:
	var yes := false
	var no := false
	for w in _words(text):
		yes = yes or w in TF_TRUE_WORDS
		no = no or w in TF_FALSE_WORDS
	if yes == no:
		return -1
	return 1 if yes else 0


func _tf_answer(text: String) -> void:
	if _asks_again(text):
		_say(ASK_AGAIN_LINE + _tf_spoken())
		return
	var pick := _tf_pick(text)
	if pick < 0:
		_say("Hehe. Si sant eller løgn, lille dødelige!")
		return
	var card: int = 0 if pick == 1 else 1
	revealing = true
	_set_card(card, "locked")
	await get_tree().create_timer(1.5).timeout
	if (pick == 1) == tf[1]:
		_jingle(correct_snd)
		_set_card(card, "right")
		_celebrate(tf_cards[card])
		_add_anger(ANGER_CORRECT)
		score += 1
		tf_done += 1
		await get_tree().create_timer(1.0).timeout
		await _say(_pick(CORRECT_LINES))
		tf = []
		var out := create_tween()
		out.tween_property(tf_ui, "modulate:a", 0.0, 0.4)
		await out.finished
		tf_ui.hide()
		if tf_done < TF_ROUNDS:
			revealing = false
			_show_tf("Påstand nummer to. ")
			return
		await _end_quiz()
		revealing = false
		_next_riddle()
		await _girl_aside()
		_say("Neste utfordring er en gåte. " + riddle[0])
	else:
		_jingle(wrong_snd)
		_set_card(card, "wrong")
		_fail(tf_cards[card])
		_add_anger(ANGER_WRONG)
		await get_tree().create_timer(1.0).timeout
		await _say(_pick(WRONG_LINES) + " Det var faktisk " + ("sant." if tf[1] else "løgn."))
		revealing = false
		_show_tf("Ny påstand. ")


# ---------- Juice: feedback for right and wrong answers ----------

# Progress: a plain bar at the bottom that fills with yellow, one step per challenge won.
func _draw_progress() -> void:
	if won or not (quiz or tf or riddle):
		return
	var bar := Rect2(220, 336, 200, 12)
	draw_rect(bar, Color("2a1d33"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * score / WIN_SCORE, bar.size.y)), Color("e8b931"))
	draw_rect(bar, Color("5a4566"), false, 2.0)


# Right: the box bounces.
func _celebrate(node: Control) -> void:
	node.pivot_offset = node.size / 2
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(1.18, 1.18), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# Wrong: the box shakes.
func _fail(node: Control) -> void:
	var x := node.position.x
	var tw := create_tween()
	for d in [10.0, -10.0, 7.0, -7.0, 3.0, 0.0]:
		tw.tween_property(node, "position:x", x + d, 0.05)


func _end_quiz() -> void:
	quiz = []
	var fade := create_tween()
	fade.tween_property(quiz_ui, "modulate:a", 0.0, 0.5)
	await fade.finished
	quiz_ui.hide()
	quiz_ui.modulate.a = 1.0
	# Back to the middle of the stage, full size.
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "home", get_viewport_rect().size / 2 + SPRITE_LIFT, 1.2)
	tw.tween_property(self, "host_scale", 1.0, 1.2)
	await tw.finished


func _jingle(snd: AudioStream) -> void:
	answer_sfx.stream = snd
	answer_sfx.play()


func _on_correct(reply: String) -> void:
	_jingle(correct_snd)
	_add_anger(ANGER_CORRECT)
	score += 1
	if score >= WIN_SCORE:
		_win(reply)
		return
	_next_riddle()
	await _say(reply)
	await _girl_aside()
	_say("Neste: " + riddle[0])


const GORE_DB := 6.0  # louder than her voice; the files themselves are already compressed to the max
# One-shot sound effect from `gore`; several can overlap.
func _sfx(name: String, db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = gore[name]
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# The girl mutters something to herself between two challenges.
func _girl_aside() -> void:
	await get_tree().create_timer(0.4).timeout
	var line: Array = _pick(GIRL_ASIDES)
	if line[0].begins_with("Au"):  # still hurting from the fall: something cracks first
		_sfx("bone_crack", GORE_DB)
		await get_tree().create_timer(0.5).timeout
	await _say(line[0], "Master", "1.0", line[1] if line.size() > 1 else "")
	await get_tree().create_timer(0.4).timeout


func _win(reply: String) -> void:
	won = true
	control_room.finish_game()
	await _say(reply + " " + _pick(WIN_LINES))
	# First-person walk past: pumpkin slides out to the left and grows, printer comes into view.
	var center := get_viewport_rect().size / 2
	printer.scale = Vector2.ONE * SPRITE_SCALE * 0.5
	printer.modulate.a = 0.0
	printer.show()
	walking = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sprite, "position", Vector2(-300, center.y + 60), 2.5)
	tw.tween_property(sprite, "scale", Vector2.ONE * SPRITE_SCALE * 3, 2.5)
	tw.tween_property(sprite, "modulate:a", 0.0, 2.5)
	tw.tween_property(printer, "scale", Vector2.ONE * SPRITE_SCALE, 2.5)
	tw.tween_property(printer, "modulate:a", 1.0, 2.5)
	await tw.finished
	await _say(INNER_LINE, "Master", "1.0")
	await _wait_for_next_room()
	await get_tree().create_timer(RESTART_DELAY).timeout
	_start()


# ---------- Control room ----------

# Connects to the control room server. The client runs on its own from here:
# it logs in, reconnects if the network drops, and queues events until they are delivered,
# so start_game() and finish_game() can be called at any time, even while offline.
# The control-room test game passes in its own client instead (already in the tree and running);
# then only the signals are connected.
func _connect_control_room() -> void:
	var given := control_room != null
	if not given:
		control_room = ControlRoomClient.new(control_room_url, ROOM)
		add_child(control_room)
	# Signals are connected before run(), so none are missed.
	control_room.authenticated.connect(_on_control_room_authenticated)
	control_room.gave_up.connect(func(): push_warning("Fikk ikke kontakt med kontrollrommet på %s" % control_room_url))
	control_room.player_incoming.connect(_on_player_incoming)
	if not given:
		control_room.run()


func _on_control_room_authenticated() -> void:
	print("Koblet til kontrollrommet som rom %d" % ROOM)
	_update_menu_hint()


# Room 2 is done: their player walks over to us.
func _on_player_incoming(username: String, _player_data: Variant) -> void:
	incoming_player = username
	_update_menu_hint()


# Start screen: while connected, a game only starts once the control room has sent a player,
# so start_game() always belongs to someone. Offline, anyone can start.
func _can_start() -> bool:
	return incoming_player != "" or not control_room.is_authenticated


func _update_menu_hint() -> void:
	if not _can_start():
		menu_hint.text = "Venter på neste spiller..."
	elif incoming_player != "":
		menu_hint.text = "Velkommen, %s! Trykk mellomrom eller si «start»" % incoming_player
	else:
		menu_hint.text = "Trykk mellomrom eller si «start»"


# After finish_game() the server answers game_finish_ok (go on) or, if the next room still
# has a player, game_finish_wait first and game_finish_ok later. The client keeps track in
# is_waiting_for_next_pi, so we only hold the player here while that is true.
# No answer at all (server down) never counts as busy, so the game is never stuck offline.
func _wait_for_next_room() -> void:
	if not control_room.is_waiting_for_next_pi:
		return
	await _say(NEXT_ROOM_BUSY_LINE)
	# A loop, not a single await: game_finish_ok may already have come while Grim was talking.
	while control_room.is_waiting_for_next_pi:
		await control_room.game_finish_ok
	await _say(NEXT_ROOM_FREE_LINE)


func _load_frames(prefix: String, anims: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in anims:
		var tex: Texture2D = load("res://art/%s_%s.png" % [prefix, anim])
		var side := tex.get_height()
		frames.add_animation(anim)
		frames.set_animation_speed(anim, anims[anim])
		for i in tex.get_width() / side:
			var frame := AtlasTexture.new()
			frame.atlas = tex
			frame.region = Rect2(i * side, 0, side, side)
			frames.add_frame(anim, frame)
	return frames


# Next line from a shuffled deck of `lines`: all lines are said once before any repeats.
func _pick(lines: Array) -> Variant:
	var deck: Array = line_decks.get(lines, [])
	if deck.is_empty():
		deck = lines.duplicate()
		deck.shuffle()
		line_decks[lines] = deck
	return deck.pop_back()


func _add_anger(amount: float) -> void:
	anger = clampf(anger + amount, 0.0, 100.0)


func _process(delta: float) -> void:
	if holding and Time.get_ticks_msec() - press_ms > MAX_HOLD_MS:
		_talk(false)
	if not holding and Time.get_ticks_msec() - rec_started_ms > 20000:
		_restart_recording()  # keep the always-on buffer short
	var waiting := (riddle or quiz or tf) and not busy and not revealing and not won and not scaring and not speaker.playing and not holding
	if menu.visible and not menu_listening:
		_listen_for_start()
	wait_s = wait_s + delta if waiting else 0.0
	if wait_s >= WAIT_TALK_AFTER:
		_say(_pick(WAIT_LINES))  # busy while he talks, so wait_s resets
	if waiting:
		var before := anger
		_add_anger(ANGER_PER_SECOND * delta)
		if before < ANGER_GROWL_AT and anger >= ANGER_GROWL_AT:
			_growl(-8.0)
		if anger >= 100.0:
			_max_anger_scare()
	shown_anger = lerpf(shown_anger, anger, 1.0 - exp(-3.0 * delta))
	# self_modulate, so the win fade (modulate) still works.
	sprite.self_modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.35), shown_anger / 100.0)
	var now_s := Time.get_ticks_msec() / 1000.0
	if speaker.playing:
		mouth_until = now_s + audio_delay
	var heard := (speaker.playing and speaker.get_playback_position() >= audio_delay) or (not speaker.playing and now_s < mouth_until)
	var talking := heard and speaker.bus == "Voice"
	# Music dips while Grim talks, and almost disappears while the player speaks (cleaner for Whisper).
	var music_target := -80.0 if hush else MUSIC_RECORD_DB if holding else (MUSIC_DUCK_DB if speaker.playing else MUSIC_DB)
	music.volume_db = lerpf(music.volume_db, music_target, 1.0 - exp(-8.0 * delta))
	if talking and not was_talking:
		create_tween().tween_property(self, "pop", 0.0, 0.4).from(0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	was_talking = talking
	sprite.offset = Vector2(randi_range(-shake, shake), randi_range(-shake, shake)) if scaring else Vector2.ZERO
	if not scaring and not walking:
		var now := Time.get_ticks_msec() / 1000.0
		# Slow float, a faster gentle squash while talking, and a smooth tremble when very angry.
		var bob := sin(now * 1.6) * 4.0
		var tremble := sin(now * 26.0) * 2.0 * clampf((shown_anger - 70.0) / 30.0, 0.0, 1.0)
		sprite.position = home + Vector2(tremble, bob)
		# Breathing when idle; when talking the pumpkin stretches with each loud syllable.
		var squash := -voice_level * 0.035 if talking else sin(now * 1.6) * 0.012
		sprite.scale = Vector2.ONE * SPRITE_SCALE * host_scale * (1.0 + pop) * Vector2(1.0 + squash, 1.0 - squash)
	_update_voice_level(delta)
	var anim := talk_anim if talking else "idle"
	if scaring:
		anim = "talk_angry"
	if talking and not scaring:
		# Lip-sync: pick the mouth frame from the voice loudness instead of a fixed loop.
		if sprite.animation != anim:
			sprite.animation = anim
		sprite.pause()
		var frames: Array = TALK_FRAMES.get(anim, [0, 1, 2])
		sprite.frame = frames[0 if voice_level < 0.25 else (1 if voice_level < 0.6 else 2)]
	elif sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
	queue_redraw()


# A short, fading piece of the scream as a growl when he gets angry.
func _growl(db: float) -> void:
	growl_player.volume_db = db
	growl_player.play(0.8)
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(growl_player, "volume_db", -60.0, 1.0)
	tw.tween_callback(growl_player.stop)


func _update_voice_level(delta: float) -> void:
	var analyzer := AudioServer.get_bus_effect_instance(voice_bus, 0) as AudioEffectSpectrumAnalyzerInstance
	var target := 0.0
	if analyzer and speaker.playing:
		var db := linear_to_db(analyzer.get_magnitude_for_frequency_range(100.0, 4000.0).length())
		target = clampf((db + 45.0) / 35.0, 0.0, 1.0)
	# Fast open, slower close, so the mouth snaps open on syllables and eases shut.
	var speed := 30.0 if target > voice_level else 10.0
	voice_level = lerpf(voice_level, target, 1.0 - exp(-speed * delta))


func _max_anger_scare() -> void:
	await _jumpscare()
	anger = ANGER_AFTER_SCARE
	_say("Grr! *Svar nå, lille dødelige!* " + (_quiz_spoken() if quiz else (_tf_spoken() if tf else riddle[0])))


func _draw() -> void:
	if fall >= 0.0:
		_draw_fall()
	_draw_progress()
	if flash > 0.0:
		draw_rect(get_viewport_rect(), Color(0.7, 0.0, 0.0, flash))
	if holding:
		draw_rect(Rect2(610, 10, 20, 20), Color.RED)
	if not won and shown_anger > 0.5:
		# Red, stepped (pixel-style) vignette that grows and pulses with anger.
		var t := shown_anger / 100.0
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * (2.0 + 4.0 * t))
		var bands := 8
		var band := 6.0
		var view := get_viewport_rect()
		for i in bands:
			var alpha := 0.7 * t * pulse * (1.0 - float(i) / bands)
			draw_rect(view.grow(-(i + 0.5) * band), Color(1, 0, 0, alpha), false, band)
