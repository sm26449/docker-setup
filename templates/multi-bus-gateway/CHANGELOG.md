# Changelog

Toate modificarile notabile ale proiectului sunt documentate in acest fisier.

## [3.0.0] — Multi-device platform + security (intern, in testare)

> Release major. In dezvoltare/testare interna sub freeze de publicare pana la
> finalizare. Migrare **invizibila**: o instalare existenta cu un singur contor
> devine automat „device #1" — topicuri MQTT, bucket, taguri Influx si entitati
> Home Assistant identice. Detalii: `docs/design/tier2-device-profiles.md`.

### Adaugat — extindere gateway (2026-07-05)

- **Sink HTTP/JSON output** (stil Solar API): un dispozitiv poate fi expus
  read-only la `GET /api/meters/<id>`, servind valorile live ca JSON indexat pe
  numele masuratorii — alaturi de MQTT/InfluxDB. Opt-in per dispozitiv, protejat
  de acelasi IP-allowlist/auth ca UI-ul. Card in tab-ul Outputs cu URL copiabil
  si **preview live** (numar valori, prospetime, snapshot JSON).
- **Masuratori calculate (motor de expresii)**: derivi masuratori noi prin
  formula (factor de putere, sume pe faze, conversii, dezechilibru, flag-uri
  booleene), injectate in fluxul de valori → curg la **toate** sink-urile ca
  orice masuratoare. Evaluator AST **sigur** (nu `eval`; whitelist de operatori/
  functii; referinte pe nume acelasi-dispozitiv + `dispozitiv.registru`), nume cu
  paranteze (`_G_ULN[1]`) suportate, preset-uri parametrizate + **„salveaza ca
  template propriu"**, si **stateful `prev()` / `dt`** (ex. putere medie dintr-un
  contor Wh: `(E - prev(E)) / dt * 3600`). Tab „Calculated" cu builder (campuri
  din Measurements + paleta de functii + preview live); apar si in **Monitor** si
  **History**.
- **Sink REST push generic**: POST periodic de telemetrie JSON catre un URL
  arbitrar (webhook / platforma cloud), interval configurabil, headere (secrete
  mascate), format nativ/plat, verify-TLS, status ultimul push, buton Test.
  URL-uri externe permise (admin-gated). Card in Outputs.
- **Auto-discovery Modbus**: scan de retea TCP (CIDR privat, plafonat /24) +
  sweep de unit-id pe un endpoint (TCP/RTU), probe read-only. Modalul „Discover"
  a primit metoda „Modbus TCP scan" (CIDR pre-completat din /24-ul dispozitivului
  #1) → lista de responderi cu badge Modbus/port-open + „Use" care pre-completeaza
  wizard-ul. Endpoints `/api/discover/modbus/scan` + `/units`.
- **Driver de intrare MQTT**: un dispozitiv `protocol: mqtt` se aboneaza la un
  topic pe un broker si transforma mesajele JSON in aceleasi batch-uri normalizate
  (extractie prin `json_path`, topic per-registru cu wildcard `+`/`#`) → curg la
  toate sink-urile/vmeters/calcule. Optiune MQTT in wizard (broker/topic/user/
  parola/TLS + Test), template built-in „Generic MQTT (JSON)".

### Adaugat — /metrics Prometheus (2026-07-06)

- Endpoint `GET /metrics` in formatul de expunere Prometheus (0.0.4), generat
  de mana — zero dependente noi. Serii: per device (up/poll_rate/reads ok+error/
  latency/staleness/health), sink-uri (MQTT connected+published, Influx
  connected+written+buffer+dropped), metere virtuale (up/requests/rate/errors/
  connections + calitatea per registru la compozite). Citit la scrape din
  singleton-urile live — fara colector de fundal, fara atingerea hot-path-ului.
- Accesibil fara sesiune de login (un scraper nu se poate loga), ca `/health`;
  IP-allowlist-ul ramane aplicat; expune doar countere/health, niciodata config.

### Adaugat — dashboard per device + culori default (Phase B, 2026-07-06)

- **Dashboard-ul are acum dimensiune de device**: chips-uri sub header
  (single-select, persistate) — un click comuta intre Janitza, Fronius si
  orice senzor viitor, cu widget-urile, valorile live si istoricul
  sparkline-urilor ale device-ului respectiv. WS-ul difuzeaza acum TOATE
  device-urile, taggate cu id (spatiile de adrese se suprapun intre device-uri
  — un merge netaggat ar fi coliziune); clientul tine un store separat pe
  device-ul activ, `currentValues` ramane contractual store-ul primary
  (Monitor/Measurements neatinse).
- **Lista de registre a dashboard-ului e decuplata** de pagina Measurements
  (care isi inlocuieste lista cand navighezi alt device) — repara si un bug
  latent in care dashboard-ul putea randa lista altui device cu valorile
  primary-ului. Customize / Edit / Reaplica-culorile opereaza pe device-ul
  activ si salveaza cu `?device=` (verificat: edit pe Fronius persistat la
  Fronius, Janitza necontaminat).
- **Empty-state per device** care distinge „nicio masuratoare aleasa" de
  „sursa nu raspunde" (data_health), cu CTA spre Measurements.
- **Culori default pentru widget-uri** (Settings → General): conventie de faza
  L1/L2/L3 — Distinct (albastru/teal/violet, default) · IEC RO/UE
  (maro/negru/gri, theme-aware: „negru" devine aproape-alb pe dark) · RST
  clasic (cu avertisment de coliziune cu culorile de alarma) · Custom — plus
  nuante pe categorii (temperatura/umiditate/putere/energie). Aplicate DOAR
  widget-urilor noi (detectie faza din nume + categorie din unitate);
  widget-urile stocheaza `var(--phase-lN)` → schimbarea conventiei/temei le
  recoloreaza live; buton explicit „Reaplica culorile default" in Customize.

### Imbunatatit — UI/UX runda 2: P2/P3 (2026-07-06)

- **Sparkline-urile din Status** nu mai arata „—" la primul render (parea
  stricat) — placeholder explicit „se colecteaza date…" pana la al doilea
  esantion; istoricul persista intre vizite.
- **Empty-state Calculated care invata**: primele 3 preset-uri ca notite
  clicabile (nume + formula + hint) — un click deschide builder-ul
  precompletat; nu doar un rand de text.
- **Lexicon de status unificat**: badge-urile vmeter (LISTENING/STALE/DOWN/
  starting/disabled, 5 span-uri inline stilizate diferit) folosesc acum
  aceeasi componenta `sink-pill` ca sink-urile din Outputs (+ varianta `bad`).
- **Toggle de densitate compacta pe dashboard** (persistat): ~60% mai multe
  carduri pe ecran in modul compact; baseline min-height uniform pe carduri ca
  numerele singure sa nu para vacante linga sparkline-uri.
- **Editorul vmeter**: „Add measurement" continua adresarea de la ultimul rand
  (adresa + span-ul tipului), buton de duplicare per rand (toate campurile,
  adresa urmatoare libera), tooltip pe coloana Scale.

### Imbunatatit — UI/UX (review de arhitect, 2026-07-06)

Review complet cu Playwright (28 de capturi: desktop/dark/mobil, toate
paginile); primele 5 constatari, in ordinea impactului:

- **Bug de incredere pe Status**: `devices[]` nu includea `poll_rate` → tabelul
  "Polling & threads" arata 0.00/s in timp ce pipeline-ul arata 4.2/s — doua
  cifre contradictorii pe acelasi ecran. Reparat + test de regresie.
- **Formatare numerica unificata**: helper `_fmtNum` locale-aware (54840 →
  54,840; -45017.62 → -45,017.62) aplicat pe KPI-urile dashboard-ului, pe
  toate cardurile (inclusiv sparkline, care ocolea formatarea) si pe tabel.
- **Empty-state la Monitor**: canvasul nu mai e un dreptunghi alb — titlu +
  indrumare ("apasa pe o valoare din stanga"), theme-aware, i18n EN/RO.
- **Audit culori de severitate**: (a) editorul de praguri arata acum UNITATEA
  BRUTA + valoarea live curenta — pragurile se compara cu valoarea bruta (VA),
  nu cu cea afisata (kVA); un "100" gandit ca 100 kVA facea orice citire peste
  100 VA rosie (falsa alarma reala pe _S_SUM3, praguri corectate 90k/100k);
  (b) picker-ul de culori widget primeste swatch-uri identity-safe + sfat sa
  evite verde/galben/rosu (se citesc ca status).
- **Densitate operationala pe dashboard**: valori aliniate dreapta cu
  tabular-nums linga unitate (golul mort de ~40% eliminat), randuri mai
  stranse, header sticky cu scroll in container (KPI-urile raman vizibile);
  badge-ul de poll-group apare DOAR pe exceptii (grupul majoritar tacut) — pe
  tabel si pe carduri; 15 chip-uri REALTIME identice erau zgomot pur.

### Adaugat — senzori Zigbee / BLE (template-uri + preset wizard, 2026-07-06)

- **Template-uri built-in de senzori** (transport MQTT, apar automat la pasul
  MQTT din wizard): `zigbee2mqtt_sensor` (temperature/humidity/pressure/
  battery/voltage/linkquality — exposes standard z2m) si `ble_theengs_sensor`
  (tempc/hum/batt/volt/rssi — proprietatile decodorului Theengs; LYWSD03MMC,
  RuuviTag, Govee…). Campurile sunt json_path-uri editabile; sursele sunt
  documentate in fiecare template (zigbee2mqtt.io / decoder.theengs.io).
- **Preseturi in wizard** (pasul MQTT): chip-uri „Zigbee (zigbee2mqtt)" si
  „BLE (Theengs/BTHome)" care completeaza pattern-ul de topic al bridge-ului
  (`zigbee2mqtt/<friendly_name>`, `home/TheengsGateway/BTtoMQTT/<MAC>`) si
  preselecteaza template-ul pentru pasul urmator.
- Calea Zigbee/BLE ramane prin bridge-uri batute in lupta (zigbee2mqtt,
  Theengs/ESPHome) → driverul MQTT-in existent — fara stive radio in gateway
  (modelul L1 al platformei). Senzorii devin direct surse pentru metere
  compozite / Influx / REST.

### Adaugat — metere compozite (agregator multi-sursa, 2026-07-06)

> Aplicatia se numeste acum **Multi-Bus Gateway** (titlu UI + API; repo-ul
> ramane `janitza-monitor` pana la urmatorul major, conform freeze-ului).

- **Surse cross-device in meterele virtuale**: un rand din template poate fi
  `dispozitiv.registru` — un singur meter Modbus TCP (si feed JSON) aduna
  registre din mai multe surse (Janitza + HTTP + MQTT). Numele simple raman
  legate de device-ul instantei (byte-identical); prefixul cu punct se
  activeaza doar cand e un id de device cunoscut.
- **Conventia de staleness** (absenta nu se serveste NICIODATA ca 0/false):
  politici per instanta `on_stale` = `legacy` (default — comportamentul clasic,
  meterele existente neatinse) / `fail` (citirea care atinge un registru stale
  → exceptie Modbus; blocurile peste el refuzate — fara adevar partial) /
  `sentinel` (N/A SunSpec: float→NaN, int16→0x8000, uint16→0xFFFF…) / `hold`
  (ultima valoare plafonata la `max_hold_s`, apoi fail). Prag de prospetime
  per rand (`stale_after_s`), default = pragul device-ului sursa; sumele preiau
  calitatea celui mai slab membru (niciodata sume partiale); serverul ramane
  pornit cat cel putin o sursa e proaspata.
- **Feed JSON per meter** `GET /api/virtual-meters/<id>/values`: aceeasi
  conventie — `value: null` + `quality: good|stale|missing` + `age_s`,
  `last_value` separat, `complete`/`stale_fields` la nivel de feed.
- **Editor**: picker de surse grupat pe device (valori `dispozitiv.registru`),
  coloana „Stale s" per rand, politica + max-hold in modalele de instanta,
  avertisment la salvare pentru prefixe de device necunoscute.
- **Guard la stergerea unui device** referit de metere compozite (instanta sau
  randuri `device.registru` in template) — dependenta e facuta explicita.
- Amanat (documentat): blocul optional de registre de calitate in-band Modbus
  (bitmask status per sursa + varsta) — calitatea e vizibila prin status/JSON.
- Verificat live in productie: compozit umg512 (viu) + fronius-solar (cazut
  peste noapte) — `fail`: 239.6V servit, registrul mort refuzat cu exceptie,
  blocul care il traverseaza refuzat; `sentinel`: tot blocul citibil cu NaN;
  meterele de productie au ramas pe `legacy`, neatinse.

### Adaugat — setari UI (2026-07-06)

- **Fusul orar in Settings → General**: `ui.timezone` (granitele lunii pentru
  raportul Energy) se seteaza acum din UI — picker cu toate zonele IANA de pe
  server (~486), validare server-side (un typo ar muta tacut granitele
  rapoartelor), aplicare live fara restart. Endpoint nou
  `/api/config/general` (GET/POST) in `routes/general_config.py`.
  Nota: pattern-urile `default_topic_pattern` (MQTT) si `default_bucket_pattern`
  (InfluxDB) erau deja editabile in cardurile lor din Settings.

### Refactor — arhitectură (2026-07-06, zero schimbări de comportament)

- **Teste golden de caracterizare** (`tests/test_golden_routing.py`): pin pe
  contractul byte-identical al caii poller→sink-uri (primary: topic_prefix/
  bucket/tag `None` + device_id `""` = fallback pe config-ul publisher-ului;
  izolarea store-urilor; injectia calc la 8M+i; izolarea esecului unui sink)
  + unealta `tools/mqtt_capture_schema.py` (captura 30s → schema topicuri/
  payload, diff inainte/dupa fiecare faza).
- **Motor de calcul extras** in `janitza/calc_engine.py` (clasa `CalcEngine`):
  mutare verbatim din closure-ul `create_api()`; publisher-ele se rezolva la
  momentul rularii (lambda peste scope — `/api/config/apply` le poate rebind-ui
  cu `nonlocal`), altfel s-ar publica intr-un obiect mort.
- **`DeviceRegistry`** (`janitza/device_registry.py`): perechile
  (DeviceConfig, client) + store-urile per-dispozitiv au acum un proprietar cu
  mutatii atomice (add/replace/remove/resync) in locul listei + dict-ului +
  lock-ului mutate inline de rutele CRUD. Store-ul primary ramane ALIAS la
  `current_values` (migrare invizibila); citirile raman snapshot-uri lock-free.
- **U1 — delegare de evenimente in UI**: cele 29 de handler-e inline
  `onclick="app.m('…')"` cu date dinamice interpolate au fost inlocuite
  cu `data-action`/`data-args` + un listener delegat global (`_wireActionDelegation`
  in app-core.js). Motivatie: `_esc` e escaper de context HTML, dar handler-ul
  inline e context JS-string-in-atribut — parserul HTML decodeaza `&#39;` inapoi
  in `'` inainte ca JS sa parseze, deci o valoare cu apostrof evada din string.
  Cu `data-*` valoarea traieste doar in context de atribut, unde `_esc` e corect.
  Suport: `data-with-el` (elementul ca ultim argument), `data-guard` (click-ul
  pe rand vs. celula de butoane), `data-key-enter` (Enter pe randuri div).
- Verificare live dupa fiecare faza: diff schema MQTT identic cu baseline-ul,
  ciclu CRUD dispozitive prin registru, calc register creat/rulat/sters live,
  smoke Playwright pe delegare (39 butoane dashboard, rand → detaliu, guard).

### Reparat — login hardening + a11y/UX (backlog review, 2026-07-06)

- **Anti-enumerare la login**: `authenticate()` ruleaza acum **exact un** verify
  PBKDF2 indiferent daca username-ul exista (verify contra unui hash-momeala cand
  nu se potriveste), cu comparatie constant-time a username-ului → timpul de
  raspuns nu mai dezvaluie ce useri sunt valizi.
- **PBKDF2 240k → 600k** (pragul OWASP 2023). Hash-urile sunt auto-descriptive
  (poarta propriul iteration count) → cele vechi verifica in continuare.
- **config.yaml scris `0600`** (contine hash-uri de parole + tokenuri MQTT/Influx)
  — creat cu mode restrictiv din start (fara race open→chmod) + tightening pe un
  fisier deja existent.
- **Parola plaintext semnalata**: o autentificare reusita contra unei parole
  stocate in clar (config hand-edited) logheaza un warning ca sa fie re-hash-uita.
- **Nav-tabs = tab pattern real**: `role="tablist"`/`role="tab"` + `aria-selected`
  (comutat live) + `aria-controls` catre panouri `role="tabpanel"`; iconițele
  `aria-hidden`. Cititoarele de ecran anunta acum „tab, selected".
- **Race la History**: schimbari rapide de interval/registre lansau query-uri
  suprapuse; unul mai lent putea suprascrie rezultatul mai nou. Garda de secventa
  (last-wins) pe raspuns si pe eroare.
- **Conexiune pierduta vizibila**: heartbeat-ul de status arata acum un toast la
  pierderea legaturii cu gateway-ul (o singura data, nu la fiecare 5s) si la
  revenire — un UI gol/vechi la boot sau in timpul unei caderi nu mai e silentios.

### Reparat — logging (backlog review, 2026-07-06)

- **Secrete redactate din URL-uri logate**: un webhook de alerta / REST-push /
  URL de dispozitiv HTTP poate purta credentiale in userinfo (`user:token@`) sau
  in query (`?api_key=…`). La un POST esuat, URL-ul brut ajungea in log →
  scurgere. Helper nou `redact_url()` (userinfo eliminat, valorile-secret din
  query mascate `***`, restul pastrat) aplicat in `alerts`, `rest_push`,
  `http_client`.
- **Logurile poller-ului poarta id-ul de dispozitiv**: thread-name
  `Poller-<device>-<grup>` + prefix `[<device>]` pe liniile poller-ului, ca sa
  distingi grupurile identice (realtime/normal/slow) intre mai multe
  dispozitive. Calea legacy cu un singur dispozitiv ramane fara tag.

### Reparat — fiabilitate (backlog review, 2026-07-05)

- **Dead-man write-lease supravietuieste unui crash**: lease-urile erau doar in
  RAM — daca procesul cadea cat un setpoint periculos era scris (asteptand
  revert-ul), lease-ul se pierdea si setpoint-ul ramanea live fara revert. Acum
  partea *declarativa* (dispozitiv/adresa/valoare-safe) e oglindita atomic pe
  disc (`config/write_leases.json`, scris doar la schimbarea setului, nu la
  reinnoire); la boot fiecare lease e re-armat **deja-expirat** → primul sweep
  revine la valoarea safe (reincercand pana cand dispozitivul e reachable).
- **Precizie int64/uint64 la vmeter**: contoarele mari (Wh) treceau prin `float`
  (mantisa 53 biti) → biti inferiori corupti peste 2^53; iar valorile in afara
  intervalului erau taiate **tacut**. Acum multiplicarea e in spatiu intreg cand
  operanzii sunt intregi, si clamp-ul logheaza un warning in loc sa ascunda.
- **Fus orar configurabil** pentru raportul lunar de energie (`ui.timezone`,
  default `Europe/Bucharest`) — granitele lunii nu mai sunt hardcodate; CLI
  `backfill --window` respecta un offset explicit in loc sa-l reeticheteze UTC.
- **Leak de event-loop la reload**: fiecare pornire de poller crea un
  `asyncio` loop nou fara sa-l inchida → FD-uri acumulate la fiecare reload de
  registre. Loop-ul propriu se inchide acum in `finally`.
- **Harvester-ul de evenimente** era un `while True` neopribil care inghitea
  erorile de top-level la DEBUG; acum se opreste curat la shutdown si
  logheaza erorile reale (deduplicat, fara spam la 5s).
- **Race la citirea inelului de evenimente**: `get_stats()` copia deque-ul fara
  lock (putea da „deque mutated during iteration" cand un poller adauga la
  maxlen); snapshot-ul e acum sub lock.

### Reparat — workspace mobil + embedded (2026-07-04)

- **Monitor pe iOS/iPhone**: valorile din picker sunt acum tap-abile
  (`cursor: pointer` + `role="button"` — iOS Safari nu declanseaza click pe un
  `<div>` cu `cursor: grab`).
- **Graficul Monitor** si **refresh-ul live din Measurements** functionau doar
  cand `currentPage` era pagina respectiva; acum ca traiesc doar in workspace-ul
  dispozitivului (embedded), au fost trecute pe un test de vizibilitate reala →
  esantioneaza si se actualizeaza cat tab-ul e deschis.

### Adaugat — multi-device
- **Mai multe contoare** dintr-o singura instalare, fiecare cu conexiune,
  template si rutare proprie. Intrare **Modbus TCP si Modbus RTU** (serial, prin
  `pyserial`); iesire per dispozitiv pe **MQTT** (prefix de topic propriu +
  Home Assistant discovery ca device separat) si **InfluxDB** (bucket + tag
  proprii) — nu mai exista un singur sink global.
- **Template-uri de dispozitiv** = harta de registre ca artefact portabil.
  Built-in **Janitza UMG 512-PRO** (4126 registre, 29 categorii, defaults
  curatoriate). Biblioteca: built-ins in pachet + template-uri utilizator in
  `config/device_templates/`.
- **UI Devices**: card cu sanatate live + **wizard Add Device in 3 pasi**
  (Conexiune TCP/RTU cu *Test connection* real, alegere/creare/upload template,
  rutare date cu preview live de topic). Pagina Registers condusa de template,
  cu selector de dispozitiv.
- **Editor de template-uri** in UI: metadate + tabel de registre cu cautare si
  validare pe rand; upload cu confirmare la suprascriere; export/descarcare;
  duplicare built-in; stergere blocata cat timp e folosit.
- **Backup & Restore**: export/import ZIP al configuratiei (dispozitive,
  selectii de registre, template-uri, contoare virtuale) — secretele si
  identitatea de retea excluse implicit.
- **Persistenta bufferului InfluxDB pe disc**: bufferul store-and-forward
  supravietuieste unui restart in timpul unei pane (verificat live: restart
  mid-outage → 579 puncte recuperate de pe disc, 823 replay-ate, 0 pierdute).

### Adaugat — securitate (optional, dezactivat implicit)
- **MQTT TLS / mutual TLS** (port 8883): CA + certificat/cheie de client.
- **HTTPS** pentru UI (uvicorn TLS; certificat self-signed generat automat).
- **Listă IP permise** (IP-uri/CIDR) pentru UI/API, cu loopback mereu permis.
- **Autentificare** cu roluri **admin** (complet) + **viewer** (doar citire),
  parole cu hash PBKDF2, blocare per-IP la login esuat, ecran de login + logout.

### Reparat — audit cap-coada (2026-07-02)
- **Fail-safe metere virtuale:** o sursa (device) care nu mai exista NU mai cade
  pe datele primarului — meterul devine stale si watchdog-ul il opreste (un
  consumator de control nu primeste niciodata valorile altui contor). Stergerea
  unui device folosit ca sursa de un vmeter este blocata explicit.
- **config.yaml corupt** nu mai porneste pe default-uri + suprascris la primul
  save: fisierul stricat e pastrat ca `.yaml.bad`, iar salvarile sunt blocate
  pana la reparare.
- **Citirile Modbus plafonate la 120 registre** (limita de protocol 125) —
  selectiile late generau citiri ilegale care esuau mereu, silentios.
- **Intrarea HTTP publica doar numere finite** — un `json_path` care rezolva
  text/dict nu mai otraveste batch-ul InfluxDB (conflict de tip) si nu mai
  blocheaza vmeter-ul sursa.
- **Auto-select** respecta setul curatoriat `defaults` al template-ului
  (Janitza: 58, nu 4126) si refuza potopul dintr-un template necurat >300.
- **Securitate:** CORS wildcard eliminat (UI-ul e same-origin; acces extern
  opt-in prin `CORS_ALLOW_ORIGINS`); XSS stocat reparat in toate sink-urile
  innerHTML (etichete/descrieri/unitati registre, URL-uri device).
- **Concurenta:** mutatiile listei de device-uri serializate (lock + re-rezolvare
  dupa id); apply/reload mutate de pe event-loop; disconnect-ul HTTP asteapta
  thread-urile (join).
- **UX post-reorganizare:** editarea unui device HTTP incarca URL-ul (Save nu
  mai da 422), wizard-ul nu mai arata campurile RTU langa HTTP, onboarding-ul
  duce la tab-ul Editare al contorului, feedback-ul de conexiune pierduta e
  restaurat (toast), schimbarea limbii nu mai inchide workspace-ul deschis,
  bara cu 7 tab-uri face wrap la orice latime.

### Imbunatatit
- **Intrare HTTP/JSON + navigatie pe dispozitiv.** Un dispozitiv poate fi citit
  acum si prin **HTTP/JSON** (Fronius Solar API, Shelly, Tasmota, Enphase…), nu
  doar Modbus: harta de registre are un `json_path` per intrare, valorile vin deja
  scalate si alimenteaza aceleasi `device_values` normalizate — toate sink-urile
  merg neschimbate. Wizard-ul are optiunea HTTP/JSON (URL + Test). **Devices** a
  urcat in meniul principal (Dashboard · Devices · Config · Virtual Meters), iar
  **Monitor/History/Energy** au iesit din meniu si traiesc **per dispozitiv**,
  activate doar cand exista datele (Monitor↔polling, History+Energy↔InfluxDB).
- **Gateway multi-device (pas 1-3).** Fiecare dispozitiv = o sursa Modbus cu
  iesiri independente. Registrele traiesc **per dispozitiv**, cu tab-uri
  **Available / Selected** (catalog + set polat), **adaugare de registru custom**
  (adresa manuala) si **upload/download** al hartii de registre (model Janitza).
  **MQTT si InfluxDB sunt sink-uri per dispozitiv**, fiecare cu **toggle** propriu
  si **status live** (activ / neconectat / oprit) — un dispozitiv poate cita si
  redistribui fara sa publice. Device #1 (UMG512) ramane blocat pornit pe ambele
  (protejeaza dashboard-urile, Home Assistant si istoricul). Pagina separata
  „Registers" a disparut — tot ce tine de registre e in dispozitiv.
- **Metere virtuale legate de dispozitivul sursa.** Un meter virtual re-serveste
  acum valorile **unui dispozitiv anume** (nu doar ale celui primar): pagina
  Virtual Meters are un selector **„Dispozitiv sursa"** si afiseaza sursa fiecarui
  meter. Identitatea instantei ramane pe id-ul de template, deci meterele
  existente (em24_av53 :1502 pentru Victron, fronius_ts_native :502 pentru
  Fronius) raman **byte-identice** — topicuri, entitati HA si valori neschimbate.
- **Monitor / History / Energy pe dispozitiv.** Selector comun de „dispozitiv
  vizualizat" pe cele trei pagini (aparut doar cand exista >1 device). Citirile
  din InfluxDB sunt per-device — `query_history`/`energy_report` primesc bucket +
  tag; `/api/history`, `/api/history/registers` si `/api/energy/monthly` accepta
  `?device=`. Primar/absent → bucket-ul implicit fara filtru (byte-identic).
  Monitor incarca registrele device-ului si face poll la valorile lui live
  (WebSocket-ul difuzeaza doar primarul).
- **Pagina Virtual Meters reorganizata.** Doua tab-uri sus (Metere | Template-uri)
  si un buton **„Adauga instanta"** (modal: dispozitiv sursa / template / port /
  unit). Fiecare meter e o sectiune cu sub-tab-uri proprii — **Prezentare / Valori
  live / Loguri / Statistici & Debug** — deci toate datele meterului sunt sub el
  (sursa, template, port/unit, status, throughput, freshness, conexiuni). Editarea
  ramane in modal si poate schimba **dispozitivul sursa**. Stergerea cere
  **scrierea cuvantului DELETE** (dubla confirmare).
- **Pagina Config reorganizata pe dispozitiv.** Sub-tab-uri orizontale
  (Devices / MQTT / InfluxDB / Backup / Security) — totul in fata, fara scroll.
  Conexiunea globala (un broker MQTT, un InfluxDB) e separata de **rutarea per
  dispozitiv**: MQTT si InfluxDB pastreaza doar un **tipar implicit `{device}`**
  pentru topic/bucket care alimenteaza dispozitivele noi; fiecare dispozitiv
  are topic, bucket, tag si **toggle de Home Assistant discovery** proprii.
- **Editare pe pagina completa a dispozitivului** (click pe rand): Conexiune /
  Identitate & template / Rutare date, cu *Test connection* live. Cardul
  Modbus TCP separat si sub-tab-urile Settings/Registers au disparut —
  registrele se editeaza per dispozitiv. **Device #1 (UMG512) complet editabil
  cu identitate pastrata** (id/topic/bucket/tag read-only, istoricul si
  entitatile Home Assistant raman neatinse).
- **Accesibilitate: 0 incalcari WCAG 2A/AA** (axe-core) pe toate paginile +
  modale, ambele teme; **responsive verificat pe iPhone/iPad** (zero overflow).
- Suita Playwright (functional + a11y) integrata in verificare.

### Teste
- 113 teste (migrare byte-identica, CRUD devices incl. editare device #1 cu
  identitate pastrata, tipare implicite de rutare + flag HA per dispozitiv,
  template save/upload/export/delete, RTU transport, backup round-trip,
  persistenta buffer, hashing/lockout/sesiuni/roluri, gate de login, IP
  allowlist, MQTT TLS).

## [2.7.0] - 2026-07-02

Audit de fiabilitate cap-coada pe tot lantul de date (Modbus TCP → MQTT / InfluxDB / metere virtuale), cu garantii explicite de "zero pierderi" si igiena conexiunilor. Toate scenariile au fost validate live (pana InfluxDB simulata in productie: 923 puncte bufferate → 923 replay-ate → 0 pierdute, cu meterele virtuale neafectate).

### Adaugat
- **Buffer store-and-forward pentru InfluxDB** - punctele care nu pot fi livrate (InfluxDB picat, retry-uri epuizate) intra intr-un buffer RAM marginit (implicit **10 minute / 50.000 puncte**, configurabil prin `influxdb.buffer_minutes` / `buffer_max_points`) si sunt **replay-ate cu timestamp-urile originale** la reconectare. InfluxDB deduplica pe (measurement, taguri, timestamp), deci replay-ul e **idempotent - zero duplicate prin constructie**. Batch-urile abandonate de clientul oficial dupa ~5 min de retry sunt si ele **recuperate in buffer** (inainte se pierdeau definitiv).
- **Timestamp la momentul citirii Modbus** - punctele InfluxDB sunt stampilate cu ora masuratorii, nu a flush-ului (batching-ul decala pana la ~12s), ceea ce face si replay-ul posibil.
- **TCP keepalive pe meterele virtuale** - un consumator care dispare fara FIN/RST (ex. DataManager-ul Fronius care adoarme la apus) lasa conexiunea ESTABLISHED pe veci; kernelul o reapa acum in ~90s. Fix pentru **189 de conexiuni agatate** acumulate in 5 zile (epuizare de file descriptors in ~3 saptamani).
- **Observabilitate noua** in `/api/status`: `buffer_points` / `buffered_total` / `replayed_total` / `dropped_total` (InfluxDB), `messages_failed` / `disconnected_for_s` (MQTT).

### Schimbat
- **Boot rezilient** - polling-ul Modbus porneste chiar daca meterul nu raspunde la boot (pollerele se reconecteaza singure la fiecare citire); inainte, un meter picat la pornire lasa colectorul mort pana la restart manual.
- **Init InfluxDB non-blocant** - conectarea se face in thread-ul de monitor, ca la MQTT; inainte, un InfluxDB picat bloca pornirea intregii aplicatii (UI + Modbus) pana la ~6 minute.
- **Reconnect MQTT consolidat** - dupa prima conexiune, auto-reconnect-ul paho e singura autoritate (inainte, doua mecanisme concurau pe acelasi socket); thread-ul propriu ramane doar pentru cazul "niciodata conectat".

### Reparat
- **Cache-ul de change-detection InfluxDB** se actualiza la enqueue, nu la livrare - un batch pierdut cu o valoare care se schimba rar lasa o gaura permanenta (valoarea nu se mai rescria niciodata).
- **Leak de socket la reconectarea Modbus** - clientul vechi nu era inchis inainte de a fi inlocuit (FD-uri scurse la fiecare flap de legatura).
- **Lock tinut peste I/O de retea** la reconectarea InfluxDB (gasit la validarea live a acestei versiuni): DNS-ul lent catre un server picat bloca pollerele Modbus prin lock-ul partajat → cache-ul live ingheta → meterele virtuale isi opreau consumatorii (~50s). Lock-ul de client acopera acum doar swap-ul de referinte, iar cache-ul are lock propriu; calea de scriere nu mai atinge niciodata lock-ul de client (acoperit de test de regresie).

### Teste
- **+14 teste** (`tests/test_reliability.py`): buffer/replay/margini (varsta+numar), recuperare batch esuat, ordinea la replay dupa esec, keepalive pe socketuri reale, calea de scriere fara lock de client, ownership-ul reconnect-ului MQTT, timestamp de poll atasat de poller.

## [2.6.1] - 2026-06-26

### Adaugat
- **Onboarding prim-run** - pe un deploy nou/neconfigurat (Modbus nu s-a conectat niciodata) apare un modal „Connect your meter" cu buton direct spre **Config → Settings**. Apare doar dupa o pauza de gratie si **doar** cand meterul nu s-a conectat niciodata - **nu** deranjeaza un sistem configurat aflat intr-o pana temporara, si se inchide singur cand prima citire reuseste. Tradus EN/RO.
- **Buton „Save & Apply" per sectiune** in Config → Settings (Modbus/MQTT/InfluxDB) cu feedback inline („✓ Saved & applied") - salvarea nu mai e doar un autosave invizibil.
- **Istoric la click pe valoare** - click pe orice valoare live de pe Dashboard deschide un modal cu graficul ultimelor **1h / 3h / 6h** (din InfluxDB). Reutilizeaza render-ul paginii History. Tradus EN/RO.

### Schimbat
- **„Modbus" → „Modbus TCP"** in indicatorul de status si in antetul cardului de setari (mai exact).
- **Un singur flux de save in Settings** - s-a eliminat auto-save-ul invizibil + banner-ul global „Apply"; ramane doar butonul explicit **Save & Apply** per sectiune.
- **Config editabil din UI, autoritar** - documentatia (README + manuale) duce acum cu „seteaza din UI" (Config → Settings, persistat in `config.yaml`, aplicat fara restart); variabilele `.env`/env devin optionale (bootstrap) si au intaietate cand sunt setate. Exemplul (`docker-compose.yml` + `.env.example`) comenteaza acum variabilele de conexiune.

### Reparat (audit cap-coada)
- **Securitate: scurgere de secrete** - `GET /api/config/env-overrides` returna `INFLUXDB_TOKEN`/`MQTT_PASSWORD` in clar; acum sunt **redactate** (`***`).
- **Securitate: HTML injection** - `label`/`name`/`unit`/topic/measurement ale registrilor + titlurile/mesajele toast erau injectate raw in `innerHTML`; acum trec prin escaping.
- **Bug: `showToast` cu argumente inversate** in 5 locuri (icon/stil gresit, titlu literal „error/success").
- **Bug: leak de listeneri** pe pagina Monitor (re-legare la fiecare vizita + la schimbarea limbii) - acum se leaga o singura data.
- **Robustete:** `ws.onmessage` prinde acum frame-uri JSON malformate; comparatie API key in timp constant (`hmac.compare_digest`).
- **UX:** click pe valoare deschide istoricul si in vederea Table (nu doar Cards).
- **Docs:** README corectat (variabile env **fara** prefix `JANITZA_`) + tabelul de endpoint-uri completat (`/api/history`, `/api/history/registers`, `/api/energy/monthly`).
- **Teste:** +7 (languages + guard de path, redactare env-overrides, pastrarea secretului la update, 503 history/energy).

## [2.6.0] - 2026-06-22

### Adaugat
- **Interfata multi-limba (i18n)** - selector de limba in bara de titlu, **implicit English** (mai international). Limbile sunt fisiere `ui/languages/<cod>.json` **descoperite dinamic**: copiezi `en.json` -> `es.json`, traduci valorile si limba apare in selector la urmatorul reload, fara modificari de cod si fara rebuild (`ui/` e servit live). `en.json` e **sursa de adevar si fallback** - English e mereu incarcat, apoi limba selectata e suprapusa, deci **traducerile partiale functioneaza** (orice cheie lipsa cade pe English). Alegerea persista in `localStorage`. Romana inclusa (`ro.json`). Ghid de contributie in `ui/languages/README.md`. Endpoint-uri `GET /api/languages` (listeaza limbile din director) si `GET /api/languages/{cod}`.

## [2.5.0] - 2026-06-22

### Adaugat
- **Vedere Energy (energie lunara)** - alegi o luna -> totaluri **consum (import)**, **injectie (export)**, **reactiva**, **aparenta** (delta contoarelor cumulative pe luna) + grafic cu defalcare zilnica import/export, citite din InfluxDB. Endpoint `GET /api/energy/monthly?year=&month=`.

### Reparat
- **History fara InfluxDB** - cand InfluxDB nu e activat, History afiseaza acum un mesaj clar („not configured") in loc de un grafic gol/rupt (`/api/history/registers` raporteaza `influx_enabled`).
- **Securitate: injectie Flux** prin `start`/`stop` (regex RFC3339 ne-ancorat lasa sa treaca un payload) si prin `measurement` (curata doar `"`) - acum validare ancorata + whitelist de caractere.
- **query_history robust** - client cu **timeout** rulat **in afara event loop-ului** (un InfluxDB blocat nu mai ingheata tot API-ul) si client scurt dedicat (fara race cu clientul de scriere inchis de thread-ul de reconectare).
- **update_instance** - **rollback** la configul anterior daca repornirea instantei esueaza (nu mai persista un port/unit invalid).
- **Wrapper-ul de fetch al cheii API** - robust la `Headers`/`Request`, nu mai muta obiectul de optiuni al apelantului.

## [2.4.0] - 2026-06-22

### Adaugat
- **Editare instanta vMeter din UI** - port / unit_id / stale_after_s / update_interval_s ale unei instante existente se modifica acum dintr-un dialog (buton „Edit settings" pe fiecare contor), nu doar editand `virtual_meters.yaml` manual. Endpoint `PATCH /api/virtual-meters/{template}`; schimbarea portului/unit reporneste contorul (avertisment in dialog ca scapa consumatorii conectati).
- **Sanatate achizitie date + istoric dropout-uri** - `modbus_client` tine acum un inel de evenimente (esecuri de citire, cu timestamp) + ora ultimei citiri reusite si prospetimea per poll-group, expuse in `/api/status`, in `/health` (bloc `modbus`; `status` = cel mai prost dintre vmeter si modbus) si pe MQTT (`<prefix>/data_health`, pentru alertd). `/health` ramane probe-safe: o sursa Janitza stale degradeaza `status` dar intoarce **HTTP 200** (nu reporneste containerul — restart-ul nu repara un dispozitiv inaccesibil). Config `modbus.stale_after_s` / env `MODBUS_STALE_AFTER_S` (implicit 30s).
- **Vedere istoric/trend (tab History)** - citeste datele **inapoi** din InfluxDB (pana acum app-ul doar scria). Selector de registri cautabil, grupat pe categorii, cu click pentru adaugare/scoatere (punct colorat = culoarea liniei); suprapune **mai multi registri** pe axa Y comuna; banda min/max pentru un singur registru; **hover** cu crosshair + tooltip ce listeaza valoarea fiecarei serii la momentul cel mai apropiat; ora locala. Endpoint `GET /api/history` (+ `GET /api/history/registers`).

## [2.3.1] - 2026-06-21

### Reparat
- **Interval realtime afisat in bara de status** - bara afisa mereu `realtime: 1s` (text hardcodat in template), indiferent de intervalul configurat. Acum se randeaza dinamic din `poll_groups` (ex. `realtime: 250ms`), mereu sincron cu config-ul; etichetele cu interval hardcodat din dropdown-urile de poll-group au fost eliminate.

## [2.3.0] - 2026-06-21

### Adaugat
- **IP-uri clienti in starea publicata (`peers`)** - payload-ul `<prefix>/vmeter/<id>/state` include acum `peers`, un CSV cu IP-urile clientilor conectati. Permite unui monitor (alertd) sa potriveasca un consumator anume cu `contains()` — alerta cand un IP asteptat se deconecteaza sau cand apare unul neasteptat — fara a parsa lista de conexiuni.

## [2.2.0] - 2026-06-19

### Adaugat
- **Decodare interogari** - click pe orice rand din jurnalul Logs deschide un modal care desface raspunsul Modbus brut in valori ingineresti: adresa (dec+hex), variabila sursa, tip, cuvinte brute, valoare decodata. Cel mai rapid mod de a confirma o mapa.
- **Jurnal de evenimente per contor** - ultimele 50 de evenimente de ciclu-de-viata in RAM (started / crash / restart_failed / wedged / stopped-stale / supervise), afisate in tab-ul Stats & Debug. Vezi *de ce* a tacut un contor, nu doar *ca* a tacut.
- **Endpoint `/health` constient de metere** - 200 pentru ok/degraded, 503 doar cand un contor activat e `down` (crash/pornire esuata). Healthcheck-ul Docker reflecta acum starea meterelor, nu doar „e serverul pornit". O sursa stale = degraded (200), fail-safe corect, fara restart inutil.
- **Stare MQTT completa** - payload-ul `<prefix>/vmeter/<id>/state` include acum conexiunile active (ip:port), req/s, bytes RX/TX, uptime, vechimea datelor, ultima eroare si starea `ok/stale/down` — imaginea completa pentru monitorizare, fara a duplica datele electrice.
- **Autodiscovery Home Assistant pentru contoare virtuale** - fiecare contor apare automat ca device HA (legat de Janitza prin `via_device`) cu entitati: serving, state, req/s, requests, errors, connections, data age, uptime, last error.
- **Indicator vMeter in bara de status** - langa Modbus/MQTT/InfluxDB, un pill `vMeter N/M` arata cate contoare sunt online/total (verde toate ok, gri unele stale, rosu vreunul down); click deschide pagina Virtual Meters.

### Imbunatatit
- **Logs - panou de decodare lateral** - click pe un rand decodeaza in dreapta tabelului (rand evidentiat persistent), in loc de modal; hover + eticheta `decode ›` fac actiunea descoperibila; randurile cu exceptie (EXC) sunt evidentiate subtil rosu pentru depanare rapida a maparilor.
- **Uptime per conexiune** - fiecare conexiune activa afiseaza de cat timp e stabila (`connected_s` in payload-ul MQTT + `up 5m` in cardul Meters). O conexiune care flapeaza (uptime mic, mereu resetat) e un semnal clar ca un consumator se reconecteaza.

## [2.1.0] - 2026-06-18

### Adaugat
- **Monitorizare prin MQTT** - fiecare contor virtual isi publica starea (retained) pe `<prefix>/vmeter/<id>/state` la 10s, pentru alertare externa (ex. alertd: `state != "listening"` sau `var_age()`).
- **Sonda de liveness** - detecteaza un server de contor blocat (thread viu dar care nu mai accepta conexiuni) si il reporneste; pe langa recovery-ul la crash de thread.
- Imagine prebuilt **multi-arch (amd64/arm64)** publicata automat pe GHCR la fiecare release; **manual de utilizare** + **ghid Virtual Meter** bilingve (EN/RO) cu diagrame.

### Reparat
- XSS in pagina Virtual Meters (nume/id sablon, valori string neescapate); poll-urile se opresc cand tab-ul e ascuns; cache-buster pe CSS; accesibilitate acordeon (tastatura/ARIA).
- Scriere **atomica** a config-ului de instante; race la restart de server (thread); freshness watchdog nu mai fabrica prospetime cand lipseste timestamp-ul (fail-safe).
- Dockerfile include `config/` (imaginea prebuilt vine cu sabloanele); curatat IP/org private din `backfill.py`; CORS fara credentiale.

## [2.0.0] - 2026-06-18

### Adaugat
- **Motor de contoare virtuale** - serveste un singur Janitza ca mai multe contoare Modbus definite prin sabloane YAML: Carlo Gavazzi EM24 -> Victron ESS, Fronius Smart Meter TS -> Fronius DataManager (mapa nativa Carlo Gavazzi), si un exemplu generic SunSpec 213.
- **Observabilitate** - pagina cu tab-uri (Meters/Templates/Logs/Stats): jurnal live al ultimelor 1024 cereri Modbus (adresa/count/raspuns/latenta), chart cereri/secunda, registrele cele mai citite, conexiuni client; import/export sabloane YAML.
- **Fiabilitate** - watchdog de prospetime (sursa stale -> opreste = fail-safe consumator), recovery automat la crash de thread, I/O intarit (Modbus client/server, MQTT, InfluxDB).

### Schimbat
- Relicentiat la **PolyForm Noncommercial 1.0.0** (gratis pentru uz personal/necomercial; uz comercial necesita licenta separata).

## [1.5.0] - 2026-06-03

### Adaugat
- **Auto-backfill din memoria contorului** (`janitza/backfill.py`) - recupereaza automat golurile din InfluxDB citind inregistrarea on-board de 1 minut a contorului prin API-ul HTTP `HIST_DATA`. Cand colectorul pierde conexiunea de retea (ex. un dip de tensiune reseteaza switch-ul), stream-ul live - si InfluxDB - ramane cu un gol, dar contorul (alimentat din retea) continua sa logheze in flash-ul propriu. Job-ul scrie punctele lipsa inapoi, cu aceeasi schema masura/field/tag ca publisher-ul live, asa ca graficele se completeaza fara discontinuitate.
  - Moduri: auto (detecteaza golul de la coada si il umple), `--window <ISO_UTC> <ISO_UTC>` (gol istoric), `--dry-run`, `--verbose`
  - Acopera tensiunile L-N si L-L la 1 minut (singurii parametri inregistrati istoric de UMG512; curent/putere/frecventa sunt doar live)
  - Idempotent (puncte pe granite de minut); marcaj `backfilled=1` pentru trasabilitate
  - Rulare: `docker exec pv-stack-janitza-monitor python -m janitza.backfill`; cron `*/10 * * * *`

## [1.4.0] - 2026-03-19

### Adaugat
- **Unit scaling automat** - Conversie automata Wh→kWh→MWh, W→kW→MW, VA→kVA, var→kvar pentru vizualizare mai clara
- **Gauge Options in UI** - Campuri Min, Max si Color in modalul Edit/Add register, vizibile doar pentru widget-ul Gauge
- **Auto-derive gauge range** - Min/Max se calculeaza automat din thresholds daca nu sunt setate explicit (±15% margine)
- **Gauge threshold colors** - Arcul gauge-ului isi schimba culoarea bazat pe zonele threshold (normal/warning/danger)
- **Screenshots documentatie** - 9 screenshots dark mode pentru toate paginile si modalele UI

### Fixed
- **Widget type change** - Schimbarea tipului de widget (value→gauge) se reflecta instant pe dashboard
- **Auto-save la edit** - Salvarea modificarilor din edit modal triggereaza auto-save pe server si re-render dashboard
- **Auto-reload registre** - Salvarea registrelor din UI reincarca automat pollerii Modbus, MQTT si InfluxDB
- Registrele adaugate din UI nu apareau pe dashboard fara restart container

## [1.3.0] - 2026-03-19

### Adaugat
- **pv-stack integration** - Template `service.yaml` pentru deploy in docker-setup cu dependinte mosquitto/influxdb
- Auto-republish Home Assistant discovery la modificarea registrelor

## [1.2.0] - 2026-01-08

### Adaugat
- **Settings UI** - Configurare Modbus, MQTT, InfluxDB direct din interfata web
- **Hot-reload** - Buton "Apply Configuration" pentru reconectare servicii fara restart
- **ENV override warnings** - Afisare warning in UI cand variabilele ENV suprascriu config.yaml
- **.env file support** - Variabile environment externalizate in fisier .env
- **.env.example** - Template pentru configurare rapida
- **Status hints** - Explicatii pentru mesajele "skipped" in MQTT/InfluxDB status
- **Publish mode display** - Afisare mod publicare in status modals

### Modificat
- docker-compose.yml foloseste acum variabile din .env
- Structura CSS modulara (base, dashboard, monitor, registers, config)
- README.md actualizat cu instructiuni complete de instalare si configurare

### Sters
- ui/index.html (inlocuit cu ui/templates/index.html)
- ui/css/styles.css (inlocuit cu fisiere CSS modulare)

### Fixed
- InfluxDB publisher nu se reconecta dupa enable din UI
- Campuri status InfluxDB (writes_total, writes_failed, writes_skipped)

## [1.1.0] - 2026-01-07

### Adaugat
- **Thresholds per registru** - Color coding pentru valori (danger/warning/normal/success)
- **Threshold templates** - Auto-fill bazat pe tipul de masurare (voltage, frequency, etc.)
- **Dashboard table view** - Vizualizare alternativa tip tabel
- **Monitor page** - Grafic real-time cu multiple registre suprapuse
- **Zoom & Pan** - Control grafic in pagina Monitor
- **Drag & drop** - Adaugare registre in Monitor prin drag & drop

### Modificat
- Structura CSS refactorizata in module separate
- Imbunatatiri performanta pentru liste mari de registri

## [1.0.0] - 2026-01-05

### Adaugat
- **Modbus TCP client** - Conectare la dispozitive Janitza UMG 512-PRO
- **MQTT publisher** - Publicare valori cu Home Assistant autodiscovery
- **InfluxDB publisher** - Stocare time-series
- **Publish mode "changed"** - Publica doar valorile modificate
- **Web UI** - Dashboard, Registers browser, Query on-demand
- **WebSocket** - Actualizari real-time in UI
- **Poll Groups** - Intervale diferite (realtime: 1s, normal: 5s, slow: 60s)
- **REST API** - Endpoints pentru configurare si query
- **Docker support** - Dockerfile si docker-compose.yml
- **4126 registri** - Documentatie completa din manualul Janitza

### Configurare
- config.yaml pentru setari principale
- selected_registers.json pentru registri monitorizati
- Variabile ENV pentru override configuratie
