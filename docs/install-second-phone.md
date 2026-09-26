# Installing GarminFood on a second iPhone

*(add-standalone-mode D12, task 7.3. English first, [Czech below](#čeština).)*

This is for installing GarminFood on someone else's iPhone, such as the
owner's fiancée, who uses it **without a Garmin account** ("Just on this
phone" / standalone mode). Everything stays on her phone: nothing is shared
with the owner's install, and nothing is sent to Garmin.

## What you need

- **Her own iPhone** and **her own Apple ID**. A free Apple ID is enough.
  Don't sign in with the owner's Apple ID: free-account limits count per
  Apple ID, and her install should belong to her.
- The same unsigned build the owner uses: the `GarminFood-unsigned-ipa`
  artifact from the latest green `Build iOS app` run on `main`
  (GitHub → Actions). Unzip it to get `GarminFood-unsigned.ipa`.
- One of:
  - **AltStore**, installed through AltServer for Windows on the owner's PC.
    Her phone has to reach that PC (same Wi-Fi, or USB) at least every 7
    days to refresh the app.
  - **SideStore**, which needs a PC only once for pairing and then refreshes
    on the phone itself. This is the easier choice if the PC isn't always
    nearby.

## Steps

1. On her iPhone: Settings → Privacy & Security → **Developer Mode** → on
   (the phone restarts).
2. Install AltStore (through AltServer on the PC) or SideStore, signed in
   with **her** Apple ID.
3. Copy `GarminFood-unsigned.ipa` to her phone (AirDrop, Files, or
   iCloud Drive), then open it with AltStore/SideStore → **My Apps → +**.
4. If iOS says the developer isn't trusted: Settings → General → VPN &
   Device Management → her Apple ID → **Trust**.
5. Open GarminFood. On first launch choose **"Just on this phone"**, set
   her goals with the calculator (or skip), and read the backup screen.
   With the phone in Czech, the app is in Czech.

## Free-account limits (per Apple ID)

- **About 3 active sideloaded apps per device**, AltStore or SideStore
  itself included.
- **10 new App IDs per 7 days.** GarminFood uses 2 (the app and its
  widget extension), so a reinstall or two in a week is fine; many in a
  row are not.
- **A 7-day re-sign.** AltStore/SideStore refreshes the app before it
  expires. If a refresh is missed, the app stops opening until it's
  refreshed, but **its data is kept**.

## Bundle ID

AltStore re-signs the app under her Personal Team and, as documented by
AltStore, adds her team ID to the bundle ID
(`com.mlcousek.garminfood.<TEAMID>`). Nothing in the app depends on the
exact ID: `project.yml` declares no entitlements, App Groups or Keychain
groups. *To confirm on her first install (task 7.5): the bundle ID
AltStore shows, and that the widget still appears.*

## Keeping her data safe

- Her data exists **only on her phone**. There is no iCloud backup on a
  free account.
- The app takes a snapshot every day and keeps 14 of them (Settings →
  **Data**), but those are deleted if the app is deleted.
- So every couple of weeks: Settings → Data → **Export backup…** and save
  the file to Files or iCloud Drive. The app reminds her on the Today
  screen when the last export is older than 14 days.
- **Restore** (after a reinstall or on a new phone): Settings → Data →
  **Import backup…**, check the preview, tap Restore, then close and reopen
  the app.

## Don'ts

- **Don't install an older build over a newer one.** Data written by a
  newer version might not be readable by an older one. The app refuses to
  restore a backup from a newer version, and tells you to update.
- **Don't delete the app to "fix" something** before exporting a backup.
  Deleting it deletes all her data and its daily snapshots.
- **Don't reinstall through a different Apple ID.** A different signer is
  a different app to iOS, and it starts empty.

---

## Čeština

# Instalace GarminFood na druhý iPhone

Tento návod je pro instalaci GarminFood na cizí iPhone (třeba snoubenky),
kde se aplikace používá **bez účtu Garmin** („Jen v tomto telefonu“).
Všechno zůstává v jejím telefonu: nic se nesdílí s majitelovou instalací
a nic se neposílá do Garminu.

## Co je potřeba

- **Její vlastní iPhone** a **její vlastní Apple ID**. Stačí bezplatné.
  Nepřihlašuj se majitelovým Apple ID: limity bezplatného účtu se počítají
  na Apple ID a instalace má patřit jí.
- Stejný nepodepsaný build, jaký používá majitel: artefakt
  `GarminFood-unsigned-ipa` z posledního zeleného běhu `Build iOS app` na
  `main` (GitHub → Actions). Po rozbalení vznikne `GarminFood-unsigned.ipa`.
- Jedno z:
  - **AltStore**, nainstalovaný přes AltServer pro Windows na majitelově
    PC. Telefon se k tomu PC musí aspoň jednou za 7 dní dostat (stejná
    Wi-Fi nebo USB), aby se aplikace obnovila.
  - **SideStore**, který PC potřebuje jen jednou při spárování a pak se
    obnovuje přímo v telefonu. Jednodušší, když PC není pořád po ruce.

## Postup

1. V jejím iPhonu: Nastavení → Soukromí a zabezpečení → **Režim pro
   vývojáře** → zapnout (telefon se restartuje).
2. Nainstaluj AltStore (přes AltServer na PC) nebo SideStore, přihlášený
   **jejím** Apple ID.
3. Zkopíruj `GarminFood-unsigned.ipa` do telefonu (AirDrop, Soubory nebo
   iCloud Drive) a otevři ho v AltStore/SideStore → **My Apps → +**.
4. Když iOS hlásí nedůvěryhodného vývojáře: Nastavení → Obecné → Správa
   VPN a zařízení → její Apple ID → **Důvěřovat**.
5. Otevři GarminFood. Při prvním spuštění zvol **„Jen v tomto telefonu“**,
   nastav cíle kalkulačkou (nebo přeskoč) a přečti si obrazovku o
   zálohách. Když je telefon v češtině, je aplikace v češtině.

## Limity bezplatného účtu (na jedno Apple ID)

- **Zhruba 3 aktivní sideloadované aplikace na zařízení**, včetně samotného
  AltStore nebo SideStore.
- **10 nových App ID za 7 dní.** GarminFood používá 2 (aplikaci a widget),
  takže jedna dvě reinstalace týdně nevadí, hodně za sebou ano.
- **Podpis na 7 dní.** AltStore/SideStore aplikaci obnoví, než vyprší.
  Když se obnova nestihne, aplikace se neotevře, dokud se neobnoví, ale
  **data zůstanou**.

## Bundle ID

AltStore aplikaci podepíše jejím Personal Teamem a podle své dokumentace
přidá k bundle ID její team ID (`com.mlcousek.garminfood.<TEAMID>`).
Aplikace na přesném ID nezávisí: `project.yml` nedeklaruje žádné
entitlementy, App Groups ani skupiny Keychainu. *Při první instalaci
ověřit (úkol 7.5): jaké bundle ID AltStore ukazuje a že widget funguje.*

## Jak neztratit data

- Její data jsou **jen v jejím telefonu**. Bezplatný účet nemá zálohu na
  iCloud.
- Aplikace si každý den udělá zálohu a nechává si jich 14 (Nastavení →
  **Data**), ale ty se smažou spolu s aplikací.
- Proto jednou za pár týdnů: Nastavení → Data → **Exportovat zálohu…** a
  soubor uložit do Souborů nebo na iCloud Drive. Když je poslední export
  starší než 14 dní, aplikace to připomene na obrazovce Dnes.
- **Obnova** (po přeinstalaci nebo v novém telefonu): Nastavení → Data →
  **Importovat zálohu…**, zkontrolovat náhled, klepnout na Obnovit a
  aplikaci zavřít a znovu otevřít.

## Čeho se vyvarovat

- **Neinstaluj starší build přes novější.** Data zapsaná novější verzí
  nemusí starší verze přečíst. Zálohu z novější verze aplikace odmítne
  obnovit a řekne, ať ji aktualizuješ.
- **Nemaž aplikaci, abys něco „opravila“**, dokud nemáš exportovanou
  zálohu. Smazáním zmizí všechna data i denní zálohy.
- **Nepřeinstalovávej přes jiné Apple ID.** Jiný podpis je pro iOS jiná
  aplikace a začne prázdná.
