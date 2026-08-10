# Saç Ekimi Danışmanlık Uygulaması — Kısa Proje Planı

## 1. Amaç ve kapsam

Saç ekimi danışmanlık vakalarının agent ile doktor arasında düzenli, izlenebilir ve rol bazlı bir akışla yönetilmesi. Hazırlanan HTML sayfası yalnızca kullanıcı deneyimini denemek için bir mockup/prototiptir; nihai ürün web uygulaması değil, native mobil uygulama olarak hedeflenmektedir.

## 2. Roller ve yetkiler

Kullanıcı giriş yaptıktan sonra rolüne göre farklı bir çalışma alanına yönlendirilir: **Doctor → doktor vaka kuyruğu**, **Agent → agent vaka alanı**, **Manager → operasyon takip alanı**, **Admin → sistem yönetimi**. Roller aynı ana ekranı paylaşmaz; Manager ve Admin aynı yönetim görünümünü farklı yetkilerle kullanır.

### Agent

- Yeni vaka/post oluşturur; hasta fotoğraflarını ve vaka notunu yükler.
- Vaka için **Graft Number** ve **Price** değerlerini belirler ve sabitler; doktor bu agent değerlerini değiştiremez.
- Doktorun cevabını görür.
- Gerekirse yeni soru, bilgi veya fotoğraf ekler.
- Doktor cevabını yeterli bulduğunda **Confirm & Close** ile vakayı kapatır.
- Yükleyen bilgisinde yalnızca kendi adını/**You** ifadesini görür veya bu alan tamamen gizlenir; başka agent’ların yükleyen kimliği gösterilmez.

### Doctor

- Kendi hastalarına atanmış vakaları ve henüz atanmamış yeni vakaları görür; postlara cevap veren tek roldür.
- Her doktor cevabı; serbest metin açıklamasına ek olarak **Approx. Graft Number** ve **Recommended Price** tavsiyelerini içerir.
- Cevapsız vakaları varsayılan olarak FIFO sırasında (en eski önce) inceler.
- Cevap verdiğinde vaka **Waiting for Agent Confirmation / Answered** durumuna geçer.
- Her vakanın kim tarafından yüklendiğini görür.

### Admin

- Postlara cevap vermez ve doktor–agent yazışmasına karışmaz.
- Yalnızca sistem ayarları, sistem/operasyon yönetimi, kullanıcı ve rol yönetimi ile raporlamadan sorumludur.
- Denetim ve raporlama amacıyla vakayı kimin yüklediğini görür; bu görünürlük cevap verme yetkisi sağlamaz.
- Hastayı cevap gelmeden önce bir doktora atayabilir ve doktorun izinli/uygun olmadığı durumlarda gerekçesiyle birlikte yeniden atayabilir.

### Manager

- Tüm kullanıcıları ve tüm vaka/postları görebilir; operasyonel durum kontrolü yapar ve eksik kalan işleri takip eder.
- Kullanıcı, ajans, vaka içeriği veya durumunu oluşturamaz, değiştiremez, pasifleştiremez ya da silemez.
- Tek yazma yetkisi hastanın atanmış doktorunu değiştirmektir. Mevcut atama değiştiriliyor veya kaldırılıyorsa gerekçe zorunludur ve işlem audit trail'e yazılır.
- Kullanıcı adına dokunarak veya tıklayarak telefon, e-posta, ajans, rol, erişim durumu ve aktivite özetini görebilir.

### Basit web Admin Paneli

- Admin paneli aynı server üzerinde `/admin` adresinden açılır ve **Admin** ile **Manager** rollerindeki server hesaplarını kabul eder.
- Kullanıcı listesinde Doctor, Agent, Manager ve Admin hesapları; kullanıcı adı, görünen isim, rol, bağlı ajans, aktiflik ve ilişkili vaka/hasta sayıları gösterilir. İsme tıklandığında telefon ve e-posta dahil kullanıcı detayları pop-up içinde açılır.
- Admin yeni kullanıcı oluştururken görünen isim, benzersiz kullanıcı adı, rol ve geçici parola belirler. Agent rolü için mevcut bir ajans seçmek zorunludur; gerekiyorsa aynı form içinde yeni ajans oluşturulabilir. Uygulamada veya panelde herkese açık üyelik bulunmaz.
- **Deactivate** erişimi kapatır ve mevcut oturumları iptal eder; gerektiğinde **Reactivate** yapılabilir. Kalıcı **Delete** yalnızca önce pasifleştirilmiş ve hiçbir vaka, hasta, mesaj veya fotoğraf geçmişi olmayan kullanılmamış hesaplar için mümkündür. Klinik geçmişi bulunan hesaplar audit bütünlüğü için silinmez, pasif tutulur.
- Hasta/vaka tablosunda hasta adı ve Patient ID, vaka referansı, durum, agent, atanmış doktor, fotoğraf ve mesaj sayıları, graft/fiyat değerleri ve yüklenme zamanı izlenir.
- Hasta/vaka listesi durum, doktor ataması, ajans ve doktor seçimleriyle; kullanıcı listesi rol, erişim durumu ve ajans seçimleriyle hızlıca filtrelenebilir. Her bölümde tek bir **All** düğmesi tüm filtreleri temizler.
- Admin tablodan hastaya aktif bir doktor atayabilir. Mevcut doktor değiştiriliyorsa gerekçe zorunludur; atama ve yeniden atama audit trail'e yazılır.
- Panel responsive çalışır; mobilde genel sayfa taşmaz, geniş vaka tablosu kendi alanı içinde yatay kaydırılır.
- Manager panelde aynı verileri görür; kullanıcı/ajans yönetim butonları ve diğer değişiklik eylemleri gösterilmez, yalnızca doktor atama seçimi kullanılabilir.

### Native mobil Admin alanı

- Admin rolüyle giriş yapan kullanıcı iOS uygulamasında Doctor veya Agent ekranını değil, yalnızca admin yönetim alanını görür.
- Web panelindeki vaka takibi, kullanıcı yönetimi, ajans yönetimi, doktor atama ve filtreleme işlevleri aynı server API'si üzerinden native mobil istemcide de kullanılabilir.
- Küçük ekranda masaüstü tablosu kullanılmaz. **Cases / Users** sekmeleri, kompakt sayaçlar, tek arama alanı ve gerektiğinde açılan filtre paneli kullanılır; filtreler kapalıyken ekranı daraltmaz.
- Vaka ve kullanıcılar kısa özet kartlar halinde gösterilir. Doktor atama, pasifleştirme, yeniden aktifleştirme ve silme gibi yönetim eylemleri yalnızca ilgili kart açıldığında görünür.
- Cases alanında durum, atanmış/atanmamış, ajans ve doktor; Users alanında rol, aktiflik ve ajans filtreleri bulunur. Arama bu filtrelerle birlikte çalışır ve tüm filtreler tek işlemle temizlenebilir.
- Admin yeni kullanıcı ve yeni ajans oluşturabilir. Agent hesabı oluşturulurken aktif bir ajans seçmek zorunludur.
- Mevcut doktor değiştiriliyor veya atama kaldırılıyorsa kısa bir gerekçe zorunludur. Kullanıcı pasifleştirme ve kalıcı silme işlemleri açık bir onay adımı ister.
- Liste aşağı çekilerek yenilenebilir; tüm veriler uygulama içinde ayrıca kopyalanmadan server'dan alınır.
- Manager aynı native yönetim alanını salt-okunur kullanıcı ve vaka erişimiyle kullanır; yeni kullanıcı/ajans, pasifleştirme ve silme kontrolleri gösterilmez. Doktor atama kontrolü açık kalır ve kullanıcı adına dokunulduğunda iletişim/hesap detayları sheet içinde gösterilir.

## 3. Vaka durum akışı

1. Agent vaka ve fotoğrafları yükler → **Waiting for Doctor**.
2. Doctor cevap verir → **Waiting for Agent Confirmation / Answered**.
3. Agent yeni soru veya fotoğraf eklerse → tekrar **Waiting for Doctor**; vaka yeniden doktorun cevapsız listesine girer.
4. Agent cevabı onaylayıp **Confirm & Close** seçerse → **Closed**.

Yalnızca agent vakayı kapatabilir. Doktor cevabı tek başına vakayı kapatmaz.

### Hasta–doktor ataması

- Her hasta sunucuda kalıcı bir **Patient ID** ile tutulur; ekranda gösterilen **HT-...** değeri ise ayrı bir vaka/post referansıdır.
- Admin hastayı önceden bir doktora atayabilir. Atama yoksa ilk geçerli doktor cevabını gönderen doktor hastanın sorumlu doktoru olur.
- Sorumlu doktor bağlantısı vaka kapandığında kaybolmaz. Aynı hastadan gelen yeni fotoğraf, soru veya vaka güncellemesi doğrudan aynı doktorun kuyruğuna gider.
- Diğer doktorlar bu hastayı varsayılan kuyruklarında görmez. Admin tüm hastaları görür ve gerektiğinde atamayı devredebilir.
- İki doktor aynı atanmamış vakayı açmış olsa bile sunucu **Waiting + Unassigned → Answered + Assigned Doctor** geçişini atomik yapar. İlk cevap kabul edilir; daha sonra gönderilen eski ekran cevabı reddedilir ve doktora güncel durum gösterilir.
- Atama, yeniden atama, ilk cevap ve reddedilen çakışma denemeleri audit trail içinde kaydedilir.

### Birden fazla agent ve mükerrer hasta kontrolü

- Aynı hasta farklı agent'lar tarafından yeniden getirilebilir. Vaka kaydedilmeden önce sunucu normalize edilmiş hasta adına göre olası mevcut kayıtları arar; gerektiğinde doğum tarihi, telefon/e-posta gibi yetkili ikincil tanımlayıcılar eşleşmeyi güçlendirir.
- Yalnızca isim eşleşmesi hastaları otomatik birleştirmez. Aynı isimli farklı kişiler olabileceği için son karar agent doğrulaması gerektirir.
- Olası eşleşmede agent'a yalnızca **Bu hasta daha önce kaydedilmiş ve konsultasyon yapılmış olabilir** bilgisi gösterilir. Önceki kaydı oluşturan agent veya şirket bilgisi hiçbir şekilde açıklanmaz.
- Küçük doğrulama sihirbazı mevcut hastanın gizlilik bandı taşıyan fotoğraflarını gösterir; Patient ID, agent kimliği ve başka organizasyonlarla çalışıldığına işaret eden bilgiler gösterilmez. Agent, fotoğraftaki kişinin kaydetmek istediği hasta olup olmadığını doğrular.
- **Yes — Same Patient** seçilirse yeni kayıt işlemi sonlandırılır; agent mevcut kaydı açamaz, değiştiremez veya içeriğini kopyalayamaz.
- **Different Patient** seçilirse agent profil fotoğrafını kontrol ettiğini ikinci adımda açıkça onaylar; yeni Patient ID oluşturulur ve aynı isimli farklı hasta kararı audit trail'e yazılır.
- İstemci kontrol yapmış olsa bile sunucu oluşturma anında eşleşmeyi yeniden denetler. İki agent'ın aynı hastayı eşzamanlı oluşturmasına karşı transaction/benzersiz kimlik ve yeniden doğrulama kuralları uygulanır.
- MVP'de otomatik yüz tanıma kullanılmaz; profil fotoğrafı insan doğrulaması için gösterilir.

## 4. Doktor ana ekranı

- En üstte hasta adı, agent adı, vaka referansı veya not içeriğine göre anlık arama; arama alanının yanında **Oldest First / Newest First** sıralama kontrolü.
- Arama satırının altında sayılarıyla **My Waiting / Unassigned / Answered / Closed** filtreleri.
- Arama alanı ve yanındaki sıralama kontrolü sayfa kaydırılırken kaybolmaz; masaüstünde ve mobilde üst navigation barının hemen altında sabit kalır. Filtreler ekranı gereksiz daraltmamak için normal sayfa akışında kalır.
- Varsayılan sıralama FIFO: en eski bekleyen vaka en üstte, en yeni en altta.
- Vaka listesi masaüstünde alanı verimli kullanmak için iki kolon, tablet ve mobilde tek kolon gösterilir. Her iki düzende de kart içeriği aynı dikey sırayı korur.
- Vaka kartında: üst-sol köşede yüklenme zamanı, üst-sağ köşede vaka referansı, tek ve büyük fotoğraf önizlemesi, hasta adı, **Assigned to you / Unassigned** bilgisi, agent note özeti, agent tarafından sabitlenen **Graft Number / Price** alanları ve durum rozeti bulunur. Yükleyen bilgisi durum hapının sağında kısa **by Selin Arslan** biçiminde gösterilir.
- Yükleyen adına tıklanınca durumdan bağımsız olarak o agent tarafından yüklenmiş tüm postlar filtrelenir; aktif filtre ayrı bir çipten temizlenebilir.
- Waiting kartı açıldığında aynı sayfada detay alanı/modal: büyük fotoğraf, diğer fotoğraflar, tam agent note, yorum akışı ve doktor cevap kutusu.
- Doktor cevap kutusunda **Approx. Graft Number**, **Recommended Price** ve açıklama alanları birlikte zorunludur. Bu üç değer tek bir doktor tavsiyesi olarak kaydedilir ve her doktor yorumunun içinde birlikte gösterilir.
- Kartta aynı anda yalnızca tek büyük fotoğraf gösterilir. Kart açılmadan fotoğraf üzerinde sağ/sol kaydırma veya oklarla diğer fotoğraflara geçilir; sağ-alt köşedeki çip mevcut/toplam fotoğraf sayısını gösterir.
- Tam ekran fotoğraf görüntüleyicide dokunmatik kaydırma, sağ/sol kontrolleri ve klavye okları desteklenir.
- Doktor tam ekran görüntüleyicide her fotoğraf üzerine ayrı ayrı serbest çizim ve metin notu ekleyebilir. Basit editör yalnızca Draw, Text, Undo, Clear ve Done araçlarını içerir.
- Doktor cevap gönderince arayüzde vaka Answered durumuna geçer ve sayaçlar güncellenir.
- Atanmamış vakadaki cevap eylemi **Respond & Take Patient** olarak gösterilir; cevapla birlikte kalıcı doktor ataması oluşur.
- Waiting durumundaki doktor vaka detayında ayrı bir **Respond** kısayolu gösterilmez; **Doctor Response** alanı sayfanın sonunda doğrudan açık gelir. Fotoğraf eylemi çizim özelliğini açık etmek için **View & Annotate** olarak adlandırılır.

## 5. Agent vaka oluşturma ekranı

- Yalnızca agent rolünde görünür ve doktor ana ekranından tamamen ayrı bir native ekran olarak tasarlanır; HTML dosyası yalnızca bu akışın mockup'ıdır.
- Agent kendi ana alanından **New Case** seçerek bu ekrana gelir; işlem bitince **My Cases** listesine döner.
- Masaüstü formunda **Case Details** solda, **Patient Photos** sağda gösterilir. Dar ekranlarda aynı sıra korunur: önce **Case Details**, ardından **Patient Photos**.
- Yeni vaka ekleme modunda **Case Details** her zaman açıktır ve **Expand / Collapse** kontrolü gösterilmez. Mobil edit modunda kontrol görünür ve bölüm varsayılan kapalı gelir. Genel işlem çubuğu Case Details dışında kaldığı için bölüm kapalıyken de erişilebilir; masaüstünde bölüm sürekli açık kalır.
- Agent çoklu fotoğraf seçebilir, paylaşım uzantısından gelen fotoğrafları görebilir, yeni fotoğraf ekleyebilir, silebilir ve sıralayabilir.
- Her yeni vaka/post için benzersiz **Case Reference** sistem tarafından otomatik oluşturulur veya sunucudan alınır; agent bu değeri giremez ya da değiştiremez. Kalıcı **Patient ID** ayrı tutulur.
- Otomatik vaka referansı agent formunda **Case Details** başlığının sağ üst köşesinde tek satırda **Referans: HT-...** biçiminde gösterilir; mobilde alan daraldığında etiket **Ref:** olarak kısaltılır.
- Vaka için zorunlu **Patient Name**, agent note, **Graft Number**, para birimi ve **Price** alanları bulunur.
- Patient Name girildiğinde yeni kayıt oluşturulmadan önce olası mevcut hasta eşleşmeleri kontrol edilir. Eşleşme varsa agent **mevcut hastayı güncelleme** veya **aynı isimli farklı hasta oluşturma** yollarından birini tamamlamadan devam edemez.
- Zorunlu alan açıklaması **Case Details** başlığında değil, form alanlarının altında küçük bir bilgi notu olarak gösterilir.
- Graft/fiyat bilgilendirme kutusu **Patient Name** alanının hemen altında ve tam genişlikte gösterilir.
- En az iki fotoğraf ile tüm zorunlu alanlar tamamlanmadan vaka doktora gönderilemez.
- **Graft Number** ve **Price** gönderim anında agent tarafından sabitlenir. Doktor bunları değiştirmez; kendi yaklaşık greft ve önerilen fiyat değerlerini cevabında ayrı olarak girer.
- **Save Draft** yalnızca taslağı saklar. **Submit to Doctor** vakayı oluşturur ve **Waiting for Doctor** durumuna geçirir.
- Ayrı bir “Ready for doctor review” bilgi kutusu gösterilmez. Gönderim butonu eksik bilgi varken pasif **Not Ready**, tüm zorunlu alanlar ve en az iki fotoğraf tamamlandığında yeşil ve aktif **Ready to Submit** durumuna geçer.
- Başarılı gönderim ekranında vaka referansı ve yeni durum açıkça gösterilir.
- Aynı agent form bileşeni hem **New Case** hem **Edit Case** modunda kullanılır; ayrı ve tekrar eden bir edit ekranı geliştirilmez.
- Edit modunda mevcut hasta bilgileri ve fotoğraflar forma yüklenir. Daha önce gönderilmiş agent/doktor yorumları fotoğrafların hemen altında kronolojik olarak gösterilir; doktor yorumlarında yaklaşık greft ve önerilen fiyat değerleri korunur.
- Edit modunda hasta adı ve ilk agent note salt okunurdur. Agent'ın değiştirebildiği sabit vaka değerleri yalnızca **Graft Number**, para birimi ve **Price** alanlarıdır.
- Edit modundaki **Save Graft & Price** yalnızca bu değerleri kaydeder. Fotoğraf ekleme/silme işlemleri seçildiği anda otomatik olarak sunucuya yazılır ve Save düğmesine bağlı değildir.
- Agent yeni fotoğraf yüklediğinde veya yeni yorum/soru gönderdiğinde vaka otomatik olarak aynı sorumlu doktora **Waiting for Doctor** durumunda döner.
- Doktor cevabı bekleyen edit ekranında **Confirm & Close** ayrı bir birincil eylemdir; bu eylem yalnızca agent tarafından kullanılabilir.
- Agent edit ekranındaki ve doktor vaka detayındaki yorum metinleri mobilde de rahat okunacak boyutta gösterilir.
- Mobil **Case Details** başlığındaki takip numarası ve edit modu **Expand / Collapse** kontrolü kart sınırları içinde kalacak şekilde responsive hizalanır.

## 6. App Store dağıtım modeli

- Seçilen model, App Store'da herkesin indirebildiği **genel amaçlı ve kliniğe bağımlı olmayan bir istemci uygulama** yayınlamaktır.
- Uygulama paketi içinde klinik adı, logo, gerçek sunucu adresi, hasta verisi, erişim anahtarı veya başka bir kliniğe özel bilgi bulunmaz.
- Mağaza açıklaması uygulamayı, yetkili kullanıcıların kendi kurumlarına ait uyumlu sunucuya bağlanarak kullandığı yapılandırılabilir bir klinik danışmanlık istemcisi olarak açıklar. Uygulamanın kullanılabilmesi için geçerli bir sunucu ve kullanıcı hesabı gerektiği açıkça belirtilir.
- İlk açılışta kullanıcı kendi **Server Address** bilgisini girer. İleride kolay kurulum için QR kod veya güvenli bağlantı ile adres tanımlama eklenebilir.
- Üretim ortamında klinik, istemciden kendi gerçek sunucu adresini girerek bağlanır. Her klinik kendi verisini, kullanıcılarını ve ayarlarını kendi sunucu ortamında yönetir.
- Apple incelemesi için ayrı, sürekli erişilebilir bir **demo sunucu** ve aktif demo doktor hesabı sağlanır. App Review notlarına sunucu adresi, kullanıcı bilgileri ve temel test adımları eksiksiz yazılır.
- Demo ortamında yalnızca sentetik hasta ve vaka verileri kullanılır; gerçek hasta verisi bulunmaz. Demo verileri güvenli şekilde sıfırlanabilir ve inceleme süresince backend hizmeti kesintisiz açık tutulur.
- İlk ekranda **Try Demo** seçeneği demo sunucu adresini güvenli biçimde doldurabilir; kullanıcı ayrıca **Connect to Your Server** ile kendi adresini girebilir.
- Apple'ın Custom Apps ve Unlisted Apps dağıtım seçenekleri alternatif olarak kayıtta tutulur; mevcut ürün kararı genel App Store dağıtımıdır.

### İlk bağlantı ve giriş

- Uygulama ilk açılışta yalnızca **Server Address** ister ve `/api/v1/health` üzerinden sunucu erişimi, API sürümü ve temel yetenekleri doğrular.
- Başarılı bağlantıdan sonra ayrı **Username / Password** ekranı açılır. Uygulamada kayıt olma, davet kabul etme veya herkese açık üyelik ekranı bulunmaz.
- Kullanıcılar yalnızca server tarafında admin tarafından oluşturulur; rol ve yetkiler server tarafından belirlenir.
- Doctor ve Agent kullanıcılarına ilgili server'daki ilk başarılı girişlerinden sonra rollerine özel kısa bir **Guided Tips** turu gösterilir. Admin ve Manager için bu tur açılmaz.
- Tur ayrı bilgi/onboarding sayfaları açmaz; kullanıcının gerçek ana ekranı üzerinde ilgili kontrolü vurgulayan kısa tooltip ve spotlight katmanı kullanır.
- Doctor için en fazla üç hedef gösterilir: vaka filtresi, Oldest/Newest sıralaması ve açılabilir vaka kartı. Agent için en fazla üç hedef gösterilir: vaka filtresi, **+ New** ve düzenlemek/güncellemek için açılabilir vaka kartı.
- Her tooltip **Next**, **Skip** ve son adımda **Done** eylemlerini sunar. Görünmeyen veya boş liste nedeniyle bulunamayan hedef adımı engellemez; uygun bir sonraki görünür hedefe geçilir.
- Kullanıcı turu atlayabilir; atlama da tamamlanmış sayılır ve her girişte tekrar gösterilmez.
- Turun tamamlanma durumu server adresi, kullanıcı kimliği, rol ve tur sürümüne göre cihazda tutulur. Başka server veya başka kullanıcı birbirinin durumunu paylaşmaz. Doctor ve Agent tooltip turunu Profile içindeki **Show guided tips again** seçeneğiyle yeniden açabilir.
- Her kullanıcı uygulamadaki profil sayfasından görünen adını, e-posta adresini ve telefon numarasını güncelleyebilir. Kullanıcı adı ve rol server yönetiminde kalır.
- Oturum açmış kullanıcı mevcut parolasını doğrulayarak yeni parola belirleyebilir; işlem diğer aktif oturumları kapatır.
- **Forgot Password** akışında kullanıcı adı veya kayıtlı e-posta ile altı haneli, 10 dakika geçerli doğrulama kodu istenir. Kod doğrulanınca parola yenilenir ve tüm eski oturumlar iptal edilir. Hesap varlığı dışarıya açıklanmaz ve başarısız kod denemeleri sınırlandırılır.
- Reset kodu yalnızca kayıtlı e-posta adresine **SMTP** üzerinden gönderilir.
- Parola cihazda saklanmaz. Başarılı girişten sonra server'ın verdiği süreli oturum anahtarı iOS Keychain içinde tutulur; çıkışta silinir.
- Kullanıcı çıkış yapabilir veya bağlı server'ı değiştirebilir. Server değiştirme işlemi mevcut oturumu kapatır ve bağlantı adımına döner.
- Yerel geliştirme derlemesinde LAN üzerindeki HTTP server'a izin verilebilir; App Store/üretim derlemesinde HTTPS zorunludur.

## 7. Modüler istemci–sunucu mimarisi

### Sunucu

- Kimlik doğrulama, rol ve yetkiler, kalıcı hasta–doktor ataması, mükerrer hasta adayı arama/doğrulama, vaka durumları, atomik cevap geçişleri, mesajlar, medya, fotoğraf anotasyonları, audit trail, raporlama ve bildirimleri yönetir.
- Hasta, vaka, yorum, doktor ataması, fiyat ve audit kayıtlarının ana veritabanı sunucuda çalışan **lokal SQLite** olacaktır.
- SQLite erişimi yalnızca server katmanından yapılır; iOS/Android istemcileri veritabanına doğrudan bağlanmaz ve tüm işlemleri sürümlü HTTPS API üzerinden gerçekleştirir.
- Kimlik doğrulama server üzerinde kullanıcı adı/parola ve süreli oturum anahtarıyla yapılır. Parola kurtarma SMTP e-postasıyla yürütülür. Push bildirimleri kimlik doğrulamadan bağımsız bir bildirim adaptörüyle, iOS tarafında APNs üzerinden ele alınır.
- Klinik adı, logo, destek bilgileri, saat dilimi, özellik bayrakları, yasal metin bağlantıları ve benzeri kliniğe özel ayarlar sunucu tarafındaki ortam yapılandırmasında tutulur.
- Parola, token imzalama anahtarı ve depolama anahtarı gibi sırlar yalnızca sunucunun environment/secret manager katmanında kalır; hiçbir zaman istemciye gönderilmez.
- İstemcinin görmesi güvenli olan marka ve özellik bilgileri, sürümlenmiş bir public configuration/capabilities endpoint'i üzerinden sunulur.
- API sürümlenir; istemci bağlanmadan önce sunucu sağlığını, API sürüm uyumluluğunu ve desteklenen özellikleri doğrular.

### İstemciler

- iOS ve Android uygulamaları arayüz, sunucu bağlantı kurulumu, fotoğraf yükleme/paylaşma, galeri, tam ekran görüntüleme ve çizim/metin anotasyonu görevlerini üstlenir.
- Sunucu adresi ve oturum bilgileri platformun güvenli saklama alanında tutulur; kullanıcı çıkış yapabilir veya bağlı sunucuyu değiştirebilir.
- Üretim ve demo bağlantılarında HTTPS zorunludur. İstemci yalnızca beklenen API sözleşmesini kabul eder; uzak sunucudan çalıştırılabilir kod yüklemez.
- Native istemciler ve sunucu ayrı geliştirilebilir, ayrı sürümlenebilir ve ortak bir API sözleşmesiyle birbirine bağlanır.
- Önerilen modüller: **server**, **ios-client**, **android-client** ve **shared-api-contract**.

### Ortam ayrımı ve güvenlik

- Demo ve üretim ortamlarının domainleri, veritabanları, medya depoları ve erişim bilgileri tamamen ayrıdır.
- Her sunucu rol bazlı erişim, tenant/klinik izolasyonu, audit kayıtları, hız sınırlama, güvenli medya erişimi ve oturum iptali sağlamalıdır.
- İstemciye verilen sunucu adresi önce biçim, HTTPS, sertifika, API sürümü ve capabilities cevabı açısından doğrulanır; doğrulama tamamlanmadan kullanıcı girişi veya veri aktarımı başlamaz.
- Sunucu adresinin değiştirilebilmesi nedeniyle sabit tek-domain pinleme yerine standart güvenli TLS doğrulaması temel alınır; kuruma özel ek güven politikaları sunucu yapılandırmasıyla uygulanabilir.

## 8. Mobil paylaşım hedefi

- WhatsApp otomasyonu planlanmıyor.
- iOS'ta **Share Extension**, Android'de **Share Intent** kullanılacak.
- Hedef akış: Fotoğrafları seç → **Share** → uygulamayı seç → yeni/mevcut vakaya ekle.

## 9. Tasarım ilkeleri

- Sade, profesyonel ve tıbbi görsel dil.
- Açık tema, yüksek okunabilirlik ve belirgin durumlar.
- Sosyal medya hissinden kaçınan, göreve odaklı arayüz.
- Masaüstü, tablet ve mobil ekranlara responsive uyum.
- Hasta verilerinin gizliliği ve rol bazlı erişim, nihai ürünün temel gereksinimi olacaktır.

## 10. Prototip sonrası kararlar

- Doktor kart ve detay ekranının kullanılabilirliğini test etmek.
- Agent vaka oluşturma ve Confirm & Close akışını tasarlamak.
- Bildirim, kimlik doğrulama, audit trail ve veri saklama gereksinimlerini netleştirmek.
- İlk bağlantı, server doğrulama, demo seçimi ve sunucu değiştirme ekranlarını tasarlamak.
- Ortak API sözleşmesini, sürüm uyumluluğu politikasını ve server capabilities modelini netleştirmek.
- Apple incelemesi için demo sunucu yaşam döngüsü, demo hesapları ve sentetik veri sıfırlama prosedürünü hazırlamak.
- Onaylanan mockup sonrası native iOS/Android istemcileri ile bağımsız sunucu uygulamasının teknik mimarisini ve API/veri modelini ayrıntılandırmak.
