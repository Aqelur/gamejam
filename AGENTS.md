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

# Proje durumu

Afet hazırlığı temalı masa oyunu. Ekranda bir masa, masada bir yönerge kâğıdı ve iki damga vardır: APPROVED ve DENIED. Damga kâğıdın üstüne bırakılınca o yönerge kabul edilir veya reddedilir. Karar kaydırarak verilmez. Fare damganın üstüne gelince damga biraz yükselir. Kabul edilen kâğıt sola kayarak çıkar. Reddedilen kâğıt buruşturulup top olur ve sağa atılır.

Kişi gişe penceresinde, yönergesi masadaki kâğıtta, ikisi aynı anda durur. Kayıt değişince birlikte değişir. Pencere duvarın içinde, karakterin başı kesilmez. Gün sayacı ve şehir yok.

Dört çubuk: Halk, Para, Hazırlık, Bürokrasi. Denge ortadadır. 0 da 100 de kötüdür. Bu adımda yalnız ekranda görünürler. Damga basınca değişmezler. 0 veya 100 oyunu bitirmez.

Ana sahne `main.tscn`, boş. Masa sahnesi `cards/card_table.tscn`; onu çalıştırmak için F6.

Yönerge metni `CardData.text`. Kişi görseli `image`, adı `character_name`. Kâğıda basılan iz `cards/images/stamp_approved.png` ve `stamp_denied.png`. Damga yazıları APPROVED ve DENIED. `left_choice` ve `right_choice` kullanılmaz.

Hazır input action'lar: `move_left`, `move_right`, `move_up`, `move_down`, `jump`, `action`, `pause`.

`testing,-akfcod` yanlışlıkla oluşmuş ikinci projedir. Dokunma.

Bu bölümü prompta kopyalama. İş bu duruma aykırıysa yalnızca aykırılığı yaz. İş bitince bu bölümü güncelle.
