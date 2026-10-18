# Kartlar

Oyunda görünen her şey İngilizce: unvanlar, metinler, sonlar. Notlar Türkçe.

## Ana amaç

Oyuncu küçük bir şehrin belediye başkanı. Baş sismolog büyük depremin yakında şehri vuracağını söylüyor, ama tarih belli değil.

Her gün başkanın masasına 3-4 kişi gelir, her biri bir kart. Gün bitince şehir haritası açılır ve o gün verilen kararların sonucu haritada görünür: onaylanan hastane inşaata başlar, konser sahnesi kurulur, kestirme yapılan binada çatlak belirir. Deprem 6 ile 8. gün arasında rastgele bir anda gelir; oyuncu tam zamanını bilmez. Gün yapısı henüz kesinleşmedi.

Amaç deprem gelene kadar dört çubuğu dengede tutmak. Deprem anındaki denge nihai sonu belirler. Oraya kadar bir çubuk 0'a veya 100'e değerse o çubuğun sonu gelir.

| Çubuk | Ne ölçer | 0 | 100 |
|---|---|---|---|
| Awareness (Bilinç) | Halkın deprem bilinci: ne yapacağını biliyor mu, çantası hazır mı | Kayıtsızlık: küçük bir sarsıntıda kimse ne yapacağını bilmez, panik yaralanmalara yol açar | Paranoya: bir kamyonun titreşimi depremle karıştırılır, kasaba aynı anda sokağa ve yola dökülür, deprem olmadan kazalar ve yaralılar olur |
| Money (Para) | Belediye kasası | Maaş alamayan itfaiye, sağlık ve arama-kurtarma personeli topluca istifa eder, kalabalık belediyeyi basar | Para sahaya indirilmez, fırsatçıları çeker. Yolsuzluk baskınıyla görevden alınırsın, afet vurduğunda binalar çürüktür |
| Infrastructure (Altyapı) | Şehrin altyapısı: binalar, hastane, depolar, ekipler | Büyük deprem bile gelmeden küçük bir sarsıntı eski binaları yıkar, yollar kapanır | Kasaba yıkılmaz bir beton kaleye döner, park betonlanır, insanlar yaşamayı reddedip göçer |
| Bureaucracy (Bürokrasi) | Kural, izin, denetim | Kural kalmaz. Downtown'daki yüksek binalar denetlenmeden kaldığı için küçük bir sarsıntıda çöker; Old Quarter ayakta kalır | Kimse imzasız adım atamaz, deprem vurduğunda kurtarma ekipleri izin beklerken ilk 72 saat kaybolur |

## Harita

Kartlardaki `Map` satırı, gün sonunda haritada neyin değişeceğini söyler.

Harita küçük. Şehir denemesindeki (`testing,-akfcod/City/city.tscn`) bölgeler:

| Bölge | İçinde ne var |
|---|---|
| Downtown | Gökdelenler |
| Main Street | Dükkanlı alçak binalar |
| Old Quarter | Eski binalar |
| Riverside | Nehir kenarı |
| Central Park | Toplanma alanı: çeşmeli meydan, gölet, çalgı köşkü |

Hastane, polis karakolu ve itfaiyenin her birinin kendi boş arsası var. Bina, kartta onaylanırsa o arsada yükselir. Arsalar şu an yan yana, ileride şehrin içine dağılacak; bu yüzden kartlar arsaların yerine bağlı yazılmaz.

Haritada büyük olay yok. Bir kartın haritadaki etkisi küçük ve tek bir noktadadır: arsada bina yükselir, binaya iskele kurulur, parka çadır dikilir. Elde hazır parçalar: iskele, ahşap destek, çadır, malzeme sandıkları, tahliye tabelası, uyarı tabelası, bariyer, trafik konisi.

| Haritadaki değişiklik | Yer | Açan kart |
|---|---|---|
| Hastane | Hastane arsası | health_hospital |
| Hastanede çatlak, sonra iskele | Hastane | contractor_hospital, hospital_cracks |
| Polis karakolu | Karakol arsası | interior_police |
| İtfaiye | İtfaiye arsası | agency_fire_station |
| Konser | Central Park çalgı köşkü, ertesi gün kalkar | influencer_concert |
| Malzeme sandıkları | Main Street | headman_supplies |
| Ahşap destek ve iskele | Old Quarter binaları | urban_braces, headman_braces |
| Çadırlar ve tahliye tabelaları | Central Park çeşmeli meydan | agency_park_tents |
| Tuğla yığınları, kalaslar, bariyerler | Central Park kuzey çimi | contractor_park |
| Tahliye tabelaları | Main Street boyunca | headman_signs |
| Tatbikat kalabalığı, ertesi gün dağılır | Central Park çeşmeli meydan | seismologist_drill |

Fikir: influencer_bracelet onaylanınca Main Street'e bilezik reklam panosu eklenebilir.

## Damga

Başkan her kartı damgalar. Sola kaydırmak DENIED, sağa kaydırmak APPROVED. Bu yüzden her kart bir istek ya da teklif olarak yazılır; ayrı seçim yazısı yoktur.
## Roguelike

- Her oyun tekrar tekrar oynanır. İlk kart her zaman seismologist_warning; ondan sonra kartlar havuzdan karışık sırayla gelir.
- Deprem günü her oyunda rastgele, oyuncu bilmez.
- Bazı seçimler yeni bir kart açar. Açılan kart kalıcıdır, sonraki oyunlarda havuzda gelme şansı vardır. Böylece her oyun bir öncekinden biraz farklı başlar.
- Bazı tek seçimler oyunu anında bitirir.

## Kart türleri

- **Takas:** kartların çoğu. Her damga bir çubuğu yükseltir, birini düşürür. Bir damganın toplamı -5 ile +5 arasında. İstisna: kart bir teklifse ve reddetmenin mantıklı bir bedeli yoksa DENIED etkisiz kalır. Teklifi reddetmek ceza gibi hissettirmemeli.
- **Yardım:** APPROVED yalnızca yükseltir, DENIED ya küçük bir eksi verir ya da hiçbir şey. Toplam en fazla +15.
- **Zarar:** iki damga da düşürür. Oyuncu sadece hangi çubuğun yanacağını seçer. Toplam en fazla -20.
- **Kazanç:** zararın tersi. İki damga da yükseltir, oyuncu sadece hangi çubuğun artacağını seçer. Bir damganın toplamı en fazla +15. Dolu bir çubuğa gelirse oyuncuyu sona itebilir.
- **Deli:** yalnızca The Town Fool. Üç alt türü var:
  - **Mit:** deli yaygın bir deprem mitini önerir. APPROVED Awareness düşürür, DENIED etkisiz.
  - **Doğru:** herkes güler ama deli haklıdır. APPROVED küçük bir ödül verir, DENIED etkisiz.
  - **Troll:** iki damga da etkisiz. Gerilen oyuncu için mola.
- Havuz oranı: yaklaşık %50 takas, %20 yardım, %20 zarar, %10 kazanç. Deli kartları bu orana girmez, havuza ayrıca eklenir.
- Yardım kartları havuzda düşmeye eğilimli çubuklara, zarar kartları yükselmeye eğilimli çubuklara gider. Denge tablosu hangisinin hangi yöne kaydığını gösterir.
- 100 de kötü olduğu için yardım her zaman iyi değildir. Dolu bir çubuğa gelen yardım oyuncuyu sona itebilir.

Her kartın bir **zinciri** vardır ya da `tek` yazar. Zincirdeki kartlar birbirini açar; tek kartlar hiçbir şeye bağlı değildir.

`Unlocks` kalıcıdır, sonraki oyunlarda da geçerlidir. `Takip` ise yalnızca o oyun içindir: damga basılınca takip kartı aynı oyunda birkaç kart sonra gelir. Oyuncuya kötü bir kararın ardından bir çıkış yolu vermek için kullanılır.

## Denge kuralları

- Dört çubuk 50'den başlar, 0 ile 100 arasında kalır.
- Etkiler 5'in katı. ±5 küçük, ±10 orta, ±15 büyük. ±20 yalnızca açılan kartlarda ve dramatik damgalarda.
- Bir damga en fazla üç çubuğa dokunur.
- Bürokrasi devletle iş yapılınca oynar: bakanlar, Afet Kurumu, izin ve denetim isteyen müteahhit. Muhtar, fenomen gibi vatandaş kartları bürokrasiye dokunmaz.
- `Unlocks` kalıcıdır: kart bir kez açılınca sonraki oyunlarda havuza girer. `Start: no` yazan kart açılana kadar havuzda yoktur; diğerleri ilk oyundan beri havuzdadır.

## Karakterler

Oyunda isim yok, unvan var. Portreler sonra eşlenecek.

| Name | Türkçesi | Ne ister | Ton |
|---|---|---|---|
| Minister of Interior | İçişleri Bakanı | Düzen, kontrol, prosedür | sert |
| Minister of Finance | Maliye Bakanı | Para harcanmasın | cimri, kuru mizah |
| Minister of Urban Planning | Şehircilik Bakanı | Bina denetimi, kentsel dönüşüm | yorgun, ciddi |
| Minister of Health | Sağlık Bakanı | Hastaneler, kan stoku | ciddi |
| Minister of Education | Eğitim Bakanı | Okullar, tatbikatlar | iyimser, haritada okul olmadığı için henüz kartı yok |
| Head of Disaster Agency | Afet Kurumu Başkanı | Altyapı, depolar, ekipler | gergin |
| Chief Seismologist | Baş Sismolog | Bilimsel uyarılar | ciddi, sabırsız |
| The Contractor | Müteahhit | İmar affı, kat, para | komik, şüpheli |
| The Headman | Muhtar | Mahallenin sesi | sıcak |
| The Influencer | Fenomen | Görünürlük, viral içerik | komik, yanlış bilgi |
| Opposition Leader | Muhalefet Lideri | Seni zor durumda bırakmak | alaycı |
| The Town Fool | Kasabanın Delisi | Kafasına eseni; bazen bir mit, bazen gerçek, bazen hiçbir şey | troll, lastik tavuğuyla gezer |

## Haritayı değiştiren kartlar

Bu kartların damgası şehirde bir şey kurar, ekler ya da değiştirir. Her kartın `Map` satırı neyin değiştiğini söyler. Zincirdeki bir kartın haritaya etkisi olmasa da zinciriyle birlikte burada durur.

### health_hospital
- Character: Minister of Health
- Tür: takas
- Zincir: hastane, 1. halka
- Says: "Mayor, this city doesn't have a single hospital. When the quake hits, the injured will have nowhere to go. Give me the land and the budget."
- DENIED: Money +15, Infrastructure -15
- APPROVED: Money -15, Infrastructure +15, Bureaucracy +5
- Unlocks: APPROVED → contractor_hospital
- Map: APPROVED → hastane arsasında inşaat başlar, birkaç gün sonra bina tamamlanır

### contractor_hospital
- Character: The Contractor
- Tür: takas
- Zincir: hastane, 2. halka
- Start: no, health_hospital APPROVED açar
- Says: "Mayor! I can finish your hospital in half the time. Just sign off on a little less concrete. Nobody looks inside a wall, right?"
- DENIED: Money -10, Infrastructure +5, Bureaucracy +5
- APPROVED: Money +15, Infrastructure -15, Bureaucracy -5
- Unlocks: APPROVED → hospital_cracks
- Map: APPROVED → hastane hemen tamamlanır ama duvarlarda ince çatlaklar vardır. DENIED → inşaat normal hızında sürer

### hospital_cracks
- Character: Minister of Urban Planning
- Tür: zarar
- Zincir: hastane, 3. halka
- Start: no, contractor_hospital APPROVED açar
- Says: "My inspectors found cracks in every column of the new hospital. I need to shut it down and rebuild the frame. Yes, it'll cost us."
- DENIED: anında son, Paper Walls
- APPROVED: Money -15, Infrastructure -5
- Map: APPROVED → hastane iskeleyle sarılır, birkaç gün kapalı kalır

### headman_supplies
- Character: The Headman
- Tür: yardım
- Zincir: tek
- Says: "My neighbors chipped in to buy emergency supplies for the whole block. Can we store them in the community hall?"
- DENIED: Awareness -5
- APPROVED: Money +5, Infrastructure +10
- Map: APPROVED → Main Street'te mahalle salonunun önüne malzeme sandıkları gelir

### interior_police
- Character: Minister of Interior
- Tür: takas
- Zincir: tek
- Says: "This town doesn't have a police station. When the ground shakes, someone has to keep order and stop the looting. Sign the order and I'll have officers here by the end of the week."
- DENIED: Money +10, Infrastructure -5, Bureaucracy -5
- APPROVED: Money -10, Infrastructure +5, Bureaucracy +10
- Son şans: APPROVED → Bureaucracy
- Map: APPROVED → karakol arsasında polis karakolu yapılır

### agency_fire_station
- Character: Head of Disaster Agency
- Tür: takas
- Zincir: tek
- Says: "This town doesn't have a fire station. After a big quake, the fires kill more people than the shaking. I need a station and two trucks."
- DENIED: Money +15, Infrastructure -10
- APPROVED: Awareness +5, Money -15, Infrastructure +10
- Map: APPROVED → itfaiye arsasında itfaiye yapılır

### influencer_concert
- Character: The Influencer
- Tür: takas
- Zincir: tek
- Says: "Let me throw a concert at the park bandstand! Free entry, and everyone gets an emergency kit at the gate. One epic night, zero excuses!"
- DENIED: Awareness -5, Money +5
- APPROVED: Awareness +15, Money -10
- Map: APPROVED → Central Park'taki çalgı köşküne ışıklar ve hoparlörler gelir, ertesi gün kalkar

### urban_braces
- Character: Minister of Urban Planning
- Tür: takas
- Zincir: destek, 1. halka
- Says: "The old quarter is held together by old bricks and good luck. Let me brace every building with timber before the big one. It's ugly, but it holds."
- DENIED: etkisi yok
- APPROVED: Money -10, Infrastructure +10
- Takip: DENIED → headman_braces, aynı oyunda birkaç kart sonra gelir
- Map: APPROVED → Old Quarter'daki binaların cephesine ahşap destekler ve iskele kurulur

### headman_braces
- Character: The Headman
- Tür: zarar
- Zincir: destek, 2. halka
- Start: no, yalnızca urban_braces DENIED ile aynı oyunda gelir
- Says: "Mayor, last night's little tremor shook the plaster off every wall in the old quarter. My neighbors are sleeping in the street. Please, brace the buildings. I know it costs more now."
- DENIED: anında son, House of Cards
- APPROVED: Money -15, Infrastructure +5
- Map: APPROVED → Old Quarter'daki binalara aceleyle ahşap destekler ve iskele kurulur

### agency_park_tents
- Character: Head of Disaster Agency
- Tür: takas
- Zincir: park, 1. halka
- Says: "If the big one hits at night, people will need somewhere to sleep. Let me set up tents and evacuation signs in Central Park, ready to go."
- DENIED: Money +5, Infrastructure -5
- APPROVED: Money -10, Infrastructure +10, Bureaucracy +5
- Unlocks: APPROVED → contractor_park
- Map: APPROVED → Central Park'taki çeşmeli meydana çadırlar, girişlere tahliye tabelaları gelir

### contractor_park
- Character: The Contractor
- Tür: takas
- Zincir: park, 2. halka
- Start: no, agency_park_tents APPROVED açar
- Says: "Mayor, my bricks need a home and your park has all that empty grass. Let me store my materials there. I'll pay rent, cash, every month!"
- DENIED: Money -5, Bureaucracy +5
- APPROVED: Money +15, Infrastructure -15, Bureaucracy -5
- Map: APPROVED → Central Park'ın kuzey çimine tuğla yığınları, kalaslar ve bariyerler gelir, çadırların bir kısmı kalkar

### headman_signs
- Character: The Headman
- Tür: yardım
- Zincir: tek
- Says: "Half the town doesn't know where the park is in the dark. Let me put up evacuation signs along Main Street. My nephew has a paint brush."
- DENIED: etkisi yok
- APPROVED: Awareness +5, Infrastructure +10
- Map: APPROVED → Main Street boyunca yeşil tahliye tabelaları dikilir

### seismologist_drill
- Character: Chief Seismologist
- Tür: takas
- Zincir: tek
- Says: "Let's run a town-wide drill on Sunday. Sirens at noon, everyone walks to Central Park. Shops close for an hour, and yes, people will grumble."
- DENIED: Awareness -10, Money +10
- APPROVED: Awareness +10, Money -10, Infrastructure +5
- Son şans: APPROVED → Awareness
- Map: APPROVED → Central Park'taki çeşmeli meydanda tatbikat kalabalığı toplanır, ertesi gün dağılır

## Haritayı değiştirmeyen kartlar

Bu kartlar yalnızca çubukları oynatır. Şehirde hiçbir şey değişmez.

### seismologist_warning
- Character: Chief Seismologist
- Tür: takas
- Zincir: tek
- Says: "Mayor, the fault under our city is waking up. I can't give you a date, but the big one is coming. I want to go on TV tonight and warn everyone."
- DENIED: Awareness -10, Money +10
- APPROVED: Awareness +15, Money -10

### agency_rescue_training
- Character: Head of Disaster Agency
- Tür: yardım
- Zincir: tek
- Says: "A foreign rescue team offered to train our firefighters for free. I just need your signature."
- DENIED: etkisi yok
- APPROVED: Awareness +5, Infrastructure +10
- Son şans: APPROVED → Infrastructure

### opposition_fearmongering
- Character: Opposition Leader
- Tür: zarar
- Zincir: tek
- Says: "The mayor is scaring people to win votes! I'll say it on every channel tonight, unless you give me a seat on your disaster council."
- DENIED: Awareness -15
- APPROVED: Awareness -5, Infrastructure -10

### finance_fund
- Character: Minister of Finance
- Tür: yardım
- Zincir: tek
- Says: "The capital sent us an earthquake fund. Sign here and it's in our account by Monday. Try not to spend it all on concrete."
- DENIED: Bureaucracy -5
- APPROVED: Money +15

### interior_inspectors
- Character: Minister of Interior
- Tür: zarar
- Zincir: tek
- Says: "The capital is cutting our building inspectors. Either we pay their salaries ourselves, or they're gone by Friday."
- DENIED: Infrastructure -5, Bureaucracy -10
- APPROVED: Money -15
- Son şans: APPROVED → Money

### influencer_bracelet
- Character: The Influencer
- Tür: takas
- Zincir: tek
- Says: "A brand wants to sponsor the town! They make Quake-Proof Bracelets. Totally scientific, probably. They'll pay us just to say we like them!"
- DENIED: etkisi yok
- APPROVED: Awareness -10, Money +15

### fool_doorway
- Character: The Town Fool
- Tür: deli, mit
- Zincir: tek
- Says: "Mayor! I've found the safest spot in any quake: the doorway! Let me paint every doorframe in town gold, so people know where to run."
- DENIED: etkisi yok
- APPROVED: Awareness -10, Money -5
- Not: modern binalarda kapı eşiği daha güvenli değildir. Doğrusu çök, kapan, tutun.

### fool_goat
- Character: The Town Fool
- Tür: deli, mit
- Zincir: tek
- Says: "My goat stared at the wall all night. That means a quake is coming! Ring the sirens!"
- DENIED: etkisi yok
- APPROVED: Awareness -5
- Not: hayvanların depremi önceden bildiği kanıtlanmamıştır.

### fool_bag
- Character: The Town Fool
- Tür: deli, doğru
- Zincir: tek
- Says: "I keep a bag by my door: water, a flashlight, a whistle and my rubber chicken. Everyone laughs at me. Want one, Mayor?"
- DENIED: etkisi yok
- APPROVED: Awareness +5, Money -5

### fool_umbrella
- Character: The Town Fool
- Tür: deli, troll
- Zincir: tek
- Says: "Mayor, I'd like a permit to sell earthquake-proof umbrellas. They're regular umbrellas. But I say it with confidence."
- DENIED: etkisi yok
- APPROVED: etkisi yok

### finance_leftover
- Character: Minister of Finance
- Tür: kazanç
- Zincir: tek
- Says: "There's some money left in this year's disaster budget. I'd rather keep it in the treasury, but the seismologist wants it for an awareness campaign. Shall I hand it over?"
- DENIED: Money +10
- APPROVED: Awareness +10

### headman_donation
- Character: The Headman
- Tür: kazanç
- Zincir: tek
- Says: "The neighbors passed a hat around and raised some money for the quake. They want to run a first-aid course with it. Or you can take it for the treasury. Will you let them run the course?"
- DENIED: Money +15
- APPROVED: Awareness +10

### agency_grant
- Character: Head of Disaster Agency
- Tür: kazanç
- Zincir: tek
- Says: "The capital is offering a disaster grant. It comes with a pile of reporting forms. If you don't want the paperwork, I can send you a free volunteer training team instead."
- DENIED: Awareness +5
- APPROVED: Money +10, Bureaucracy +5

### health_blood_drive
- Character: Minister of Health
- Tür: takas
- Zincir: tek
- Says: "After a big quake, the first thing a hospital runs out of is blood. Let me run a blood drive and stock up before it happens. It isn't cheap to store."
- DENIED: Money +5, Infrastructure -5
- APPROVED: Awareness +5, Money -10, Infrastructure +5

### urban_soil_survey
- Character: Minister of Urban Planning
- Tür: takas
- Zincir: tek
- Says: "I want a new rule: no building permit without a soil survey first. Half this town sits on soft river mud. The contractors will scream and the permit fees will drop."
- DENIED: Money +5, Bureaucracy -10
- APPROVED: Money -10, Infrastructure +5, Bureaucracy +10

### contractor_cheap_steel
- Character: The Contractor
- Tür: takas
- Zincir: tek
- Says: "Mayor, I found a supplier with steel at half price. Don't ask where it comes from. Sign the import paper and the town saves a fortune on every project."
- DENIED: etkisi yok
- APPROVED: Money +15, Infrastructure -10, Bureaucracy -5

### interior_gas_valves
- Character: Minister of Interior
- Tür: takas
- Zincir: tek
- Says: "Half the fires after a quake start with a broken gas line. I want a law: every building gets a valve that shuts the gas off when the ground shakes."
- DENIED: Money +5, Infrastructure -5
- APPROVED: Money -10, Infrastructure +5, Bureaucracy +5

### influencer_challenge
- Character: The Influencer
- Tür: takas
- Zincir: tek
- Says: "New trend alert: the Drop-Cover-Hold Challenge! Everyone films themselves under a table. I just need a little budget for prizes. It'll go viral, trust me!"
- DENIED: Awareness -5, Money +5
- APPROVED: Awareness +10, Money -10

### headman_whistles
- Character: The Headman
- Tür: yardım
- Zincir: tek
- Says: "A shop owner gave me a box of whistles. I want to hand one to every family. If you're trapped under rubble, a whistle carries much further than a voice."
- DENIED: etkisi yok
- APPROVED: Awareness +5, Infrastructure +5

### seismologist_sensors
- Character: Chief Seismologist
- Tür: yardım
- Zincir: tek
- Says: "The university wants to install free quake sensors around town. They only need permission to bolt them onto a few rooftops."
- DENIED: Awareness -5
- APPROVED: Awareness +5, Infrastructure +5

### opposition_audit
- Character: Opposition Leader
- Tür: zarar
- Zincir: tek
- Says: "I demand an audit of every lira you spent on disaster prep. Freeze all your projects until it's done, or I take my files to the press tonight."
- DENIED: Awareness -10
- APPROVED: Infrastructure -10

### finance_cuts
- Character: Minister of Finance
- Tür: zarar
- Zincir: tek
- Says: "The capital is cutting your budget. Sign here to accept the cut. Refuse, and I'll cancel your preparedness programs instead. Your choice, Mayor."
- DENIED: Awareness -5, Infrastructure -5
- APPROVED: Money -15

### agency_volunteers
- Character: Head of Disaster Agency
- Tür: kazanç
- Zincir: tek
- Says: "Thirty people signed up as search-and-rescue volunteers! I can register them as an official team. Or skip the paperwork and send them out to teach first aid in the neighborhoods."
- DENIED: Awareness +5
- APPROVED: Infrastructure +5, Bureaucracy +5

## Son şans kartları

Bir çubuk 0'a düşünce oyun hemen bitmez, eğer o çubuğun son şansını kazanmışsan. Son şans, belli kartlarda belli bir damgayı basınca o oyun için kazanılır. Kartlarda `Son şans` satırı hangi damganın hangi çubuğun son şansını verdiğini söyler.

- Son şans kazanılmamışsa çubuk 0'a düşünce o çubuğun sonu gelir.
- Kazanılmışsa çubuk 0'da kalır ve sıradaki kart o çubuğun son şans kartı olur. APPROVED çubuğu 20'ye çıkarır ama ağır bir bedeli vardır. DENIED o çubuğun sonunu getirir.
- Her son şans bir oyunda bir kez kullanılır. Oyun bitince sıfırlanır, kalıcı değildir.
- Son şans kartları denge kurallarına ve denge tablosuna girmez.
- 100 için son şans yok.

| Çubuk | Kazandıran damga | Son şans kartı |
|---|---|---|
| Awareness | seismologist_drill APPROVED | lastchance_awareness |
| Money | interior_inspectors APPROVED | lastchance_money |
| Infrastructure | agency_rescue_training APPROVED | lastchance_infrastructure |
| Bureaucracy | interior_police APPROVED | lastchance_bureaucracy |

### lastchance_awareness
- Character: The Headman
- Kazanılır: seismologist_drill APPROVED
- Says: "Mayor, people stopped caring. But the neighbors who came to your drill still remember. Let them knock on every door tonight. We'll need flyers, a few buses and a lot of snacks."
- DENIED: son, Six Seconds
- APPROVED: Awareness +20, Money -15

### lastchance_money
- Character: Minister of Finance
- Kazanılır: interior_inspectors APPROVED
- Says: "We're broke. But you paid the inspectors when nobody else would, so the capital trusts our books. They'll lend us money. They'll also want to approve every receipt."
- DENIED: son, Walkout
- APPROVED: Money +20, Bureaucracy +15

### lastchance_infrastructure
- Character: Head of Disaster Agency
- Kazanılır: agency_rescue_training APPROVED
- Says: "The town is falling apart. That foreign rescue team you trained with is back. They'll fix our roads and pipes, but they bill by the hour."
- DENIED: son, House of Cards
- APPROVED: Infrastructure +20, Money -15

### lastchance_bureaucracy
- Character: Minister of Interior
- Kazanılır: interior_police APPROVED
- Says: "There are no rules left in this town. Let me declare a state of emergency. My officers will enforce the building code door to door."
- DENIED: son, The Contractor's Town
- APPROVED: Bureaucracy +20, Awareness -15

## Danışmanlar

HOI4'teki danışmanlar gibi: para ile tutulur, oyunun geri kalanında kalıcı bir etki bırakır. Üç danışman var, üçü de gerçek yerbilimci. Karakterlerdeki "isim yok, unvan var" kuralının tek istisnası onlar; adları ekranda görünür.

### Ne zaman çıkar

- 3. ve 5. gün başlamadan, ilk kart gelmeden önce bir teklif ekranı açılır.
- Her teklif ekranında, o oyunda daha önce çıkmamış danışmanlardan rastgele biri gelir. Böylece her danışman bir oyunda en fazla bir kez çıkar ve bir oyunda üçünden yalnızca ikisi görülür. Her oyunda farklı bir ikili gelir.
- Oyuncu HIRE ya da PASS seçer. PASS bedelsizdir. Geçilen danışman o oyunda bir daha gelmez.
- Tutulan danışman kalıcıdır, oyun bitince gider. `Unlocks` gibi sonraki oyunlara geçmez.

### Para dengesi

- Fiyat Money çubuğundan düşülür.
- Money 80 ve üstündeyse fiyat 5 artar ("Word got around that the treasury is full."). Money 100 de kötü olduğu için danışman, dolan kasayı boşaltmanın bir yoludur.
- Ödemeden sonra Money 20'nin altına düşecekse HIRE kapalıdır, altında "The treasury can't afford this." yazar. Danışman kimseyi sona itmez.

### Ekran

- Teklif ekranında danışmanın portresi, portrenin altında adının yazdığı bir isim plakası, tek satırlık sözü, fiyatı, etkileri ve HIRE / PASS düğmeleri durur.
- Tutulan danışmanın küçük portresi isim plakasıyla birlikte oyun boyunca masanın köşesinde kalır. İkisi tutulduysa yan yana durur.
- Portreler çizim ya da karikatür olur. İnternetten fotoğraf alınmaz; lisansı yeniden dağıtıma izin vermez.
- İsimlerde Türkçe harfler var (Ş, ü, ö). Kullanılan font bu harfleri göstermeli.

### Denge kuralları

- Danışman etkisi bir kartın etkisine eklenir ya da onu değiştirir. Etkiler yine 5'in katıdır.
- Danışman eki bir damgayı ±20'nin ötesine taşımaz ve bir damganın dokunduğu çubuk sayısını üçün üstüne çıkarmaz.
- Anında son veren damgalara ve son şans kartlarına danışman etkisi işlemez.
- Her danışmanın bir yükü vardır. Yük, faydadan küçüktür ama oyuncunun kararını değiştirecek kadar hissedilir.

### advisor_sengor
- Name: Prof. Celal Şengör
- Unvan: Geologist
- Ton: sert, sabırsız, safsataya tahammülü yok
- Says: "I will not repeat myself, Mayor. Science or nonsense, choose one. I am expensive because I am right."
- Fiyat: Money -20
- Fayda: Deli kartlarının mit türü (fool_doorway, fool_goat) kartın üstünde "MYTH" notuyla gelir ve APPROVED etkisi sıfırlanır. Chief Seismologist kartlarında APPROVED'daki Awareness artışı 5 fazla olur.
- Yük: The Influencer kartlarında APPROVED'daki Awareness artışı 5 azalır. Şengör fenomenle televizyonda alay eder, onun izleyicisi küser.

### advisor_gorur
- Name: Prof. Naci Görür
- Unvan: Geologist
- Ton: sakin, ısrarcı, yıllardır aynı uyarıyı yapıyor
- Says: "I have said it for twenty years and I will say it again: the buildings kill, not the quake. Let me check every one of them."
- Fiyat: Money -15
- Fayda: The Contractor kartlarında APPROVED'daki Infrastructure kaybı 5 azalır. Minister of Urban Planning kartlarında APPROVED'daki Money kaybı 5 azalır.
- Yük: Minister of Urban Planning kartlarında DENIED ek olarak Awareness -5 verir. Görür o akşam televizyona çıkar ve kararı eleştirir.

### advisor_usumezsoy
- Name: Prof. Şener Üşümezsoy
- Unvan: Geologist
- Ton: kendinden emin, herkese karşı kendi fay haritası olan
- Says: "Everyone is looking at the wrong fault. I know which segment is loaded. Give me a day and I will tell you when it is not coming."
- Fiyat: Money -10
- Fayda: Tutulduğu gün, deprem günü olabilecek 6, 7, 8 günlerinden biri, deprem günü dışında kalanlar arasından rastgele seçilir ve gün başı ekranında söylenir. Örnek: "Not on day 8. I am sure of it." Bilgi doğrudur. Deprem günü daha önce geçti sanılacak bir gün çıkmaz; elenecek gün kalmadıysa söz yine söylenir ama bilgi vermez.
- Yük: Chief Seismologist kartlarında APPROVED'daki Awareness artışı 5 azalır. İki bilim insanı ekranda birbirini yalanlar, halk kafası karışık kalır.

Not: Şengör ve Üşümezsoy aynı oyunda tutulursa Chief Seismologist kartlarındaki ekleri birbirini götürür.

### Etkilenen damgalar

| Danışman | Kart | Damga | Kart etkisi | Danışmanla |
|---|---|---|---|---|
| Şengör | fool_doorway | APPROVED | Awareness -10, Money -5 | etkisi yok |
| Şengör | fool_goat | APPROVED | Awareness -5 | etkisi yok |
| Şengör | seismologist_drill | APPROVED | Awareness +10, Money -10, Infrastructure +5 | Awareness +15, Money -10, Infrastructure +5 |
| Şengör | influencer_concert | APPROVED | Awareness +15, Money -10 | Awareness +10, Money -10 |
| Görür | contractor_hospital | APPROVED | Money +15, Infrastructure -15, Bureaucracy -5 | Money +15, Infrastructure -10, Bureaucracy -5 |
| Görür | contractor_park | APPROVED | Money +15, Infrastructure -15, Bureaucracy -5 | Money +15, Infrastructure -10, Bureaucracy -5 |
| Görür | urban_braces | APPROVED | Money -10, Infrastructure +10 | Money -5, Infrastructure +10 |
| Görür | hospital_cracks | APPROVED | Money -15, Infrastructure -5 | Money -10, Infrastructure -5 |
| Görür | urban_braces | DENIED | etkisi yok | Awareness -5 |
| Üşümezsoy | seismologist_drill | APPROVED | Awareness +10, Money -10, Infrastructure +5 | Awareness +5, Money -10, Infrastructure +5 |
| Şengör | seismologist_sensors | APPROVED | Awareness +5, Infrastructure +5 | Awareness +10, Infrastructure +5 |
| Şengör | influencer_challenge | APPROVED | Awareness +10, Money -10 | Awareness +5, Money -10 |
| Görür | contractor_cheap_steel | APPROVED | Money +15, Infrastructure -10, Bureaucracy -5 | Money +15, Infrastructure -5, Bureaucracy -5 |
| Görür | urban_soil_survey | APPROVED | Money -10, Infrastructure +5, Bureaucracy +10 | Money -5, Infrastructure +5, Bureaucracy +10 |
| Görür | urban_soil_survey | DENIED | Money +5, Bureaucracy -10 | Awareness -5, Money +5, Bureaucracy -10 |
| Üşümezsoy | seismologist_sensors | APPROVED | Awareness +5, Infrastructure +5 | Infrastructure +5 |

seismologist_warning her zaman ilk kart olduğu için danışmanlardan önce gelir; ona etki işlemez.

## Sonlar

Her son bir başlık, bir harita sahnesi, bir metin ve bir `Tip` satırından oluşur. Önce harita sahnesi oynar ve sonun şehre etkisini gösterir; sonra metin ve Tip gelir. Tip, oyuncuya gösterilen gerçek bir deprem bilgisidir; oyun bitse bile oyuncu bir şey öğrenmiş olur.

### Çubuk sonları

#### Six Seconds
- Gelir: Awareness 0
- Map: harita kısa süre sallanır. İnsanlar binalardan dışarı koşar, bazıları pencereden atlar (hazır animasyon). Binalar sağlam kalır.
- Text: "A small tremor shook the town for six seconds. Nobody knew what to do. People rushed the stairs, packed into elevators, and some jumped from their windows. The buildings held. Almost every injury came from the panic. By evening, the capital had removed you from office."
- Tip: "During an earthquake: drop, cover, hold on. Never jump from a window or run for the stairs while the ground is shaking."

#### False Alarm
- Gelir: Awareness 100
- Map:
  1. Gece. Tek bir ağır kamyon Main Street boyunca geçer.
  2. Evlerin pencerelerinde ışıklar teker teker yanar.
  3. Kasabadan çıkan yola arabalar teker teker, küçükten büyüyerek belirir ve sıkışır. Birkaçının yerine kaza yapmış araba modeli gelir.
  4. Kamera kasabaya döner: hiçbir bina yıkılmamıştır.
- Text: "Your town became so aware of the danger that it forgot how to stay calm. One night a heavy truck rumbled down Main Street and rattled the windows. Someone screamed 'Earthquake!' Within a minute the whole town was in the street, and every car was racing for the only road out. There was no quake. But there were crashes at every corner and people hurt in the crush at the edge of town. The capital removed you from office the next morning."
- Tip: "Awareness means knowing what to do and staying calm, not living in fear. A panicked crowd can hurt more people than a small tremor."

#### Walkout
- Gelir: Money 0
- Map:
  1. Hastane, itfaiye ya da karakoldan hangisi yapıldıysa ışıkları söner, önündeki araçların tepe lambaları kapanır, kapısına "CLOSED" tabelası gelir. İnsan figürü gerekmez.
  2. Hiçbiri yapılmadıysa 1. adım atlanır.
  3. Tek bir araba (başkan) ara sokaktan sessizce kasabadan çıkar.
- Text: "Nobody had been paid in months. One morning the firefighters, the paramedics and the search-and-rescue volunteers left their badges on your desk and walked out together. With the big one on its way, there was no one left who knew how to pull people from the rubble. By evening an angry crowd was storming city hall, and you left through the back door."
- Tip: "Firefighters, paramedics and rescue teams are a town's first line of defense in an earthquake. Buildings and equipment mean nothing without trained, paid people to use them."

#### Golden Grave
- Gelir: Money 100
- Map:
  1. Şafak vakti. İki polis arabası tepe lambaları yanıp sönerek kasabaya giren yoldan gelir ve Main Street'te durur.
  2. Harita sallanır. Old Quarter'daki güçlendirilmemiş binalar çöker (House of Cards'taki yıkılma animasyonu tekrar kullanılır).
- Text: "You filled the vault to the brim, but you never put that money to work making the town stronger. A fund that big drew bureaucrats and opportunists like flies. You were caught in a web of corruption, and a police raid at dawn removed you from office. When disaster struck, the bank accounts were full. The buildings were rotten."
- Tip: "Disaster funds aren't meant to be saved. They're meant to become life-saving projects before the danger arrives."

#### House of Cards
- Gelir: Infrastructure 0, headman_braces DENIED
- Map:
  1. Harita hafifçe, kısa bir süre sallanır.
  2. Old Quarter'daki binalar tek tek çöker (hazır yıkılma animasyonu).
  3. Ana yolda yarıklar açılır, moloz yığınları sokakları kapatır.
  4. Kasabaya giren yolun başında birkaç araba durur, ilerleyemez.
- Text: "It wasn't even the big one. A small tremor, the kind the town usually sleeps through, rolled in at dawn. The old quarter came down brick by brick, and the main road split in two. Rescue trucks couldn't get past the rubble. If a small one did this, nobody wanted to imagine the big one."
- Tip: "Old, unreinforced buildings can collapse even in a small earthquake. Reinforcing them costs far less than rebuilding them."

#### Concrete Jungle
- Gelir: Infrastructure 100
- Map:
  1. Central Park'ın çimi gri betona döner (zemin materyali değişir). Ağaçların yerine hazır kuru ağaç modeli gelir.
  2. Binaların etrafında iskele, destek kirişi, çit ve bariyer teker teker belirir.
  3. Ekranın rengi yavaşça solar (WorldEnvironment doygunluğu düşer). Pencere ışıkları söner.
  4. Harita kısa bir süre sallanır. Hiçbir şey düşmez. Sokakta kimse yoktur.
- Text: "You turned the town into a fortress. Every building wore a cage of steel braces. Walls went up along every street, and the park was paved over in gray concrete. One by one, families packed their cars and left for somewhere they could actually live. When the quake finally came, not a single brick fell. But the town you saved was an empty shell."
- Tip: "A resilient town isn't a bunker. Strengthen buildings and keep open spaces green and free, because a park is also your assembly area after an earthquake."

#### The Contractor's Town
- Gelir: Bureaucracy 0
- Map:
  1. Harita kısa ve hafif sallanır.
  2. Downtown'daki gökdelenler teker teker çöker. House of Cards'taki yıkılma animasyonu kullanılır, hedef bu binalardır. Yeni kule, tabela veya çit eklenmez.
  3. Old Quarter ayakta kalır. Kulelerin yerinde moloz yığını kalır.
- Text: "There was no inspector left to climb those stairs. The towers downtown had gone up fast, with nobody to ask what was inside the walls. A tremor small enough to leave the old quarter standing reached them at dawn. One by one they dropped into their own footprints. The dust crossed Main Street and kept going. By evening the capital had removed you from office."
- Tip: "A building that never passed inspection can fail in a quake that leaves older, simpler houses standing. Ask whether your home was permitted and inspected."

#### Awaiting Signature
- Gelir: Bureaucracy 100
- Map:
  1. Harita kısa bir süre sallanır. Old Quarter'da birkaç moloz yığını belirir.
  2. Haritadaki her hareket donar: arabalar, araç lambaları, animasyonlar.
  3. Hastane, itfaiye ya da karakoldan hangisi yapıldıysa ve Central Park'ın üstüne kırmızı "PENDING" damgası sertçe iner. Masadaki DENIED / APPROVED damgalarıyla aynı stil. Hiçbiri yapılmadıysa yalnızca park.
  4. Gökten beyaz kâğıtlar kar gibi yavaşça yağar (parçacık efekti).
- Text: "You tightened the rules until nobody in town could move without a signature. When the quake hit, the rescue trucks sat waiting for a dispatch order. The rescue volunteers were turned away because their forms were incomplete. The tents in the park stayed folded, waiting for a permit. On paper, the town was in perfect order. In the rubble, people waited for help that was still being stamped. By the time the last signature arrived, the first 72 hours were gone."
- Tip: "The first 72 hours after an earthquake are the most important for saving people trapped in the rubble. Good emergency plans let rescuers act right away, without waiting for paperwork."

### Anında sonlar

#### Paper Walls
- Gelir: hospital_cracks, DENIED
- Text: "The inspection report came back with your DENIED stamp on it. Three weeks later, a tremor barely strong enough to rattle a cup brought down the hospital's east wing."
- Tip: "Never stay in a building with cracked columns. Get out and report it."

### Deprem sonları

Henüz yazılmadı. Aday:

#### The Cold Night
- Map: harita sallanır, binaların çoğu ayakta kalır. Sonra gece çöker, kasaba karanlıkta kalır. İnsanlar çadırsız ve jeneratörsüz, açık havada toplanır.
- Text: "The town made it through the shaking. Most buildings stood. But that night the temperature dropped below zero, and there were no tents, no generators, no blankets. People had climbed out of the rubble only to face the cold. Within a week, hunger and disease had done what the quake couldn't."
- Tip: "Surviving the quake is only the first step. Keep blankets, warm clothes, water and food ready for the days after."

## Denge tablosu

Her kartın iki damgası ayrı satır. Anında son veren damga tabloya girmez. Takas kartlarının toplamı sıfıra yakın kalmalı; yardım ve zarar kartları kayan çubukları geri çeker.

| Kart | Tür | Damga | Awareness | Money | Infrastructure | Bureaucracy |
|---|---|---|---|---|---|---|
| seismologist_warning | takas | DENIED | -10 | +10 | 0 | 0 |
| seismologist_warning | takas | APPROVED | +15 | -10 | 0 | 0 |
| health_hospital | takas | DENIED | 0 | +15 | -15 | 0 |
| health_hospital | takas | APPROVED | 0 | -15 | +15 | +5 |
| contractor_hospital | takas | DENIED | 0 | -10 | +5 | +5 |
| contractor_hospital | takas | APPROVED | 0 | +15 | -15 | -5 |
| hospital_cracks | zarar | APPROVED | 0 | -15 | -5 | 0 |
| agency_rescue_training | yardım | DENIED | 0 | 0 | 0 | 0 |
| agency_rescue_training | yardım | APPROVED | +5 | 0 | +10 | 0 |
| opposition_fearmongering | zarar | DENIED | -15 | 0 | 0 | 0 |
| opposition_fearmongering | zarar | APPROVED | -5 | 0 | -10 | 0 |
| headman_supplies | yardım | DENIED | -5 | 0 | 0 | 0 |
| headman_supplies | yardım | APPROVED | 0 | +5 | +10 | 0 |
| interior_police | takas | DENIED | 0 | +10 | -5 | -5 |
| interior_police | takas | APPROVED | 0 | -10 | +5 | +10 |
| agency_fire_station | takas | DENIED | 0 | +15 | -10 | 0 |
| agency_fire_station | takas | APPROVED | +5 | -15 | +10 | 0 |
| influencer_concert | takas | DENIED | -5 | +5 | 0 | 0 |
| influencer_concert | takas | APPROVED | +15 | -10 | 0 | 0 |
| urban_braces | takas | DENIED | 0 | 0 | 0 | 0 |
| urban_braces | takas | APPROVED | 0 | -10 | +10 | 0 |
| headman_braces | zarar | APPROVED | 0 | -15 | +5 | 0 |
| finance_fund | yardım | DENIED | 0 | 0 | 0 | -5 |
| finance_fund | yardım | APPROVED | 0 | +15 | 0 | 0 |
| agency_park_tents | takas | DENIED | 0 | +5 | -5 | 0 |
| agency_park_tents | takas | APPROVED | 0 | -10 | +10 | +5 |
| contractor_park | takas | DENIED | 0 | -5 | 0 | +5 |
| contractor_park | takas | APPROVED | 0 | +15 | -15 | -5 |
| headman_signs | yardım | DENIED | 0 | 0 | 0 | 0 |
| headman_signs | yardım | APPROVED | +5 | 0 | +10 | 0 |
| interior_inspectors | zarar | DENIED | 0 | 0 | -5 | -10 |
| interior_inspectors | zarar | APPROVED | 0 | -15 | 0 | 0 |
| seismologist_drill | takas | DENIED | -10 | +10 | 0 | 0 |
| seismologist_drill | takas | APPROVED | +10 | -10 | +5 | 0 |
| influencer_bracelet | takas | DENIED | 0 | 0 | 0 | 0 |
| influencer_bracelet | takas | APPROVED | -10 | +15 | 0 | 0 |
| fool_doorway | deli | DENIED | 0 | 0 | 0 | 0 |
| fool_doorway | deli | APPROVED | -10 | -5 | 0 | 0 |
| fool_goat | deli | DENIED | 0 | 0 | 0 | 0 |
| fool_goat | deli | APPROVED | -5 | 0 | 0 | 0 |
| fool_bag | deli | DENIED | 0 | 0 | 0 | 0 |
| fool_bag | deli | APPROVED | +5 | -5 | 0 | 0 |
| fool_umbrella | deli | DENIED | 0 | 0 | 0 | 0 |
| fool_umbrella | deli | APPROVED | 0 | 0 | 0 | 0 |
| finance_leftover | kazanç | DENIED | 0 | +10 | 0 | 0 |
| finance_leftover | kazanç | APPROVED | +10 | 0 | 0 | 0 |
| headman_donation | kazanç | DENIED | 0 | +15 | 0 | 0 |
| headman_donation | kazanç | APPROVED | +10 | 0 | 0 | 0 |
| agency_grant | kazanç | DENIED | +5 | 0 | 0 | 0 |
| agency_grant | kazanç | APPROVED | 0 | +10 | 0 | +5 |
| health_blood_drive | takas | DENIED | 0 | +5 | -5 | 0 |
| health_blood_drive | takas | APPROVED | +5 | -10 | +5 | 0 |
| urban_soil_survey | takas | DENIED | 0 | +5 | 0 | -10 |
| urban_soil_survey | takas | APPROVED | 0 | -10 | +5 | +10 |
| contractor_cheap_steel | takas | DENIED | 0 | 0 | 0 | 0 |
| contractor_cheap_steel | takas | APPROVED | 0 | +15 | -10 | -5 |
| interior_gas_valves | takas | DENIED | 0 | +5 | -5 | 0 |
| interior_gas_valves | takas | APPROVED | 0 | -10 | +5 | +5 |
| influencer_challenge | takas | DENIED | -5 | +5 | 0 | 0 |
| influencer_challenge | takas | APPROVED | +10 | -10 | 0 | 0 |
| headman_whistles | yardım | DENIED | 0 | 0 | 0 | 0 |
| headman_whistles | yardım | APPROVED | +5 | 0 | +5 | 0 |
| seismologist_sensors | yardım | DENIED | -5 | 0 | 0 | 0 |
| seismologist_sensors | yardım | APPROVED | +5 | 0 | +5 | 0 |
| opposition_audit | zarar | DENIED | -10 | 0 | 0 | 0 |
| opposition_audit | zarar | APPROVED | 0 | 0 | -10 | 0 |
| finance_cuts | zarar | DENIED | -5 | 0 | -5 | 0 |
| finance_cuts | zarar | APPROVED | 0 | -15 | 0 | 0 |
| agency_volunteers | kazanç | DENIED | +5 | 0 | 0 | 0 |
| agency_volunteers | kazanç | APPROVED | 0 | 0 | +5 | +5 |
| **Toplam** | | | **+15** | **-10** | **+5** | **+10** |
