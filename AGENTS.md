# Takım kuralları

Bu dosya repodaki bütün yapay zeka araçları içindir. Cursor, ChatGPT, Claude, Copilot veya başka bir araç kullanıyorsan bu kuralları uygula.

Godot 4.7.2, yalnızca GDScript. C# ve Godot 3 sözdizimi yazma.

- `CharacterBody2D` kullan. `KinematicBody2D` yazma.
- `@export` ve `@onready` kullan. Eski `export` / `onready` yazma.
- `await` kullan. `yield` yazma.
- Hareket: `velocity` yaz, sonra `move_and_slide()`. Argüman verme.

```gdscript
velocity = direction * speed
move_and_slide()
```

Yalnızca kullanıcının bu turda adlandırdığı klasördeki dosyaları değiştir. `project.godot`, `export_presets.cfg` ve autoload dosyalarına kullanıcı açıkça istemeden dokunma.

Başka bir üyenin klasöründeki sahneyi, scripti veya asseti düzenleme. Ortak bir dosya gerekiyorsa dur ve söyle.

İstenen tek işi yap. Envanter, diyalog, skill tree veya kayıt sistemi ekleme. Tüm projeyi yeniden yazma.

Tuş kodunu scripte gömme. Projedeki input action adlarını kullan.

Lisansı yeniden dağıtıma izin vermeyen üçüncü taraf dosya ekleme. Parola ve erişim anahtarı yazma.

Sentezlenen müzik kulaklıkta kalıp hoparlörde kaybolmasın. Küçük hoparlör kalın notayı üretemez. Sıfırdan yazarken de aynı ölçüyü kullan: gövdeyi 80 Hz civarına indirme, duyulan kök yaklaşık 300 Hz olsun (örnek E4) ve üstüne yumuşak akor tonları gelsin, tiz bir katman ekleme. Dosyanın tepesi yaklaşık 0.8, sahnedeki çalma seviyesi -4 dB civarı olsun. İki kanal da parçanın tamamını taşısın; sağ kanal yaklaşık 12 ms geciksin, ses ortaya ya da tek tarafa hapsolmasın.

# Proje durumu

Oyunun adı Mayor's Call. "Call" karar demektir, telefon değil. Oyuncu küçük bir şehrin belediye başkanıdır. Masasına gelen kişiler öneri bırakır; başkan her öneriyi APPROVED ya da DENIED ile damgalar. Kararlar dört çubuğu değiştirir: Awareness, Money, Infrastructure, Bureaucracy. Hepsi 50'den başlar; 0 da 100 de kötüdür. Gün sonunda şehir haritası kararların sonucunu gösterir. Deprem rastgele bir günde gelir ve nihai sonu dengeye göre belirler. Oyun tekrar oynanan bir roguelike'tır.

Tasarımın tamamı ve kartlar `scenarios/cards.md` içindedir: kart türleri, açılan kartlar, son şans kartları, sonlar, harita değişiklikleri, karakter unvanları. Tasarım sorusunda önce oraya bak. Oyundaki bütün yazılar İngilizce; kod yorumları ve bu dosya Türkçe kalabilir.

Klasörler:

- `menu/` giriş ekranı, ana sahne `menu/title_screen.tscn`. Start, `menu/story_intro.tscn` sahnesine geçer; yazılar bitince ya da Skip ile başkan odası açılır. Menü açıkken `menu/audio/smooth_waters.mp3` (Serge Pavkin, Pixabay) döngüde çalar; hikayeye geçince susar. Hikaye ekranında `menu/audio/story_intro.wav` döner, açılışta yükselir, çıkışta kısılır. Start ya da Quit'e basınca düğmeye bir lastik damga iner (`menu/stamp_press.gd`); damga değdiği an ekran sarsılır ve `menu/audio/stamp.wav` çalar (baştaki ve sondaki sessizlik kesilmiş), damga kalkmadan oyun başlar ya da kapanır.
- `cards/` 2D kart prototipi. Kart sola (DENIED) veya sağa (APPROVED) kaydırılır, üstte dört ikon şeridi değerleriyle durur. İkon dosya adları eski (Halk, Para, Hazırlık, Bürokrasi). `CardData` alanları: `id`, `denied_effect`, `approved_effect` (Vector4i: Awareness, Money, Infrastructure, Bureaucracy). `cards/data/` içinde `scenarios/cards.md` kartlarından 24'ü var; son şans kartları ve hospital_cracks yok, contractor kartları kilitsiz havuzda. Açılma, takip, son şans, tür ve çubuk sonları yok; çubuk 0 ya da 100'de yalnızca durur. Gün döngüsü var: günde 4 kart, "Day N" ekranı, deprem 7-9. günler arasında rastgele bir anda gelir, "EARTHQUAKE" ekranından tıklayınca oyun yeniden başlar. Harita bağlantısı yok. Kart portreleri `denemegörselleri/1-7.jpeg`, The Town Fool'un portresi yok.
- Danışmanlar (`scenarios/cards.md` Danışmanlar bölümü) `cards/` içinde çalışıyor: `advisor_data.gd`, `advisor_offer.tscn`, `data/advisors/*.tres`, portreler `cards/images/advisor_*.jpg`. 3. ve 5. gün başında teklif çıkar; tutulan danışman sol üstte kalır.
- `testing,-akfcod/` akfcod'un çalışma klasörü. İçinde ayrı bir Godot projesi vardır (kendi `project.godot`, Forward+, Jolt). `City/` şehir ve inşa edilen arsalar, `Earthquake/` bina ve şehir depremi, `PresidentRoom/` başkan odası. Yollar `res://City/...` gibi o projenin köküne göre yazılıdır; ana projeden doğrudan açılmaz. akfcod'un izni olmadan dokunma.
- `saved/desk/` eski 2D masa ve damga denemesi, arşiv. Oynanmaz, dokunma.
- `denemegörselleri/` portre ve konsept denemeleri. `1-7.jpeg` kart portresi olarak kullanılıyor, konsept görselleri bağlı değil.
- `cards/audio/concert_crowd.wav` konser kartı için sentezlenmiş ses. Sahneye bağlı değil.

Ana proje GL Compatibility ile çalışır, akfcod'un projesi Forward+ ile. Birleştirme ortak bir karardır.

Hazır input action'lar: `move_left`, `move_right`, `move_up`, `move_down`, `jump`, `action`, `pause`.

Bu bölümü prompta kopyalama. İş bu duruma aykırıysa yalnızca aykırılığı yaz. İş bitince bu bölümü güncelle.
