# Customer Flow — Çalışma Durumu

Son güncelleme: 10 Ağustos 2026

## Bugünkü durum

- iOS istemcisi gerçek API bağlantısıyla Doctor, Agent, Admin ve Manager rollerini destekliyor.
- Manager tüm kullanıcıları ve vakaları salt okunur görebiliyor; yalnızca vakaya atanmış doktoru değiştirebiliyor.
- Admin web ve mobil ekranlarında kullanıcı/vaka filtreleri sade dropdown yapısında; tek bir **All** sıfırlama eylemi bulunuyor.
- Admin ve Manager kullanıcı adına dokunarak telefon ve e-posta gibi iletişim ayrıntılarını açabiliyor.
- Doctor ve Agent için eski tanıtım sayfaları kaldırıldı; gerçek kontrolleri işaretleyen üç adımlı Guided Tips akışı kullanılıyor.
- Tooltip kartları ters tema kontrastına geçirildi: Dark Mode'da açık kart, Light Mode'da koyu kart.
- Son iOS sürümü Drascom iPhone'a yüklendi. Yüklü kaynak sürümü: `7351024`.

## Sonraki çalışma için

- Doctor ve Agent akışlarını gerçek cihazda uçtan uca yeniden kontrol etmek.
- Manager rolünün web ve mobil izinlerini gerçek verilerle doğrulamak.
- SMTP bilgileri hazır olduğunda e-posta ile parola kurtarma gönderimini tamamlamak.
- APNs bildirim kurulumu ve olay bazlı bildirim akışlarını tamamlamak.
- Fotoğraf anotasyon editörünün çizim ve metin araçlarını gerçek vaka akışında doğrulamak.
- App Store demo sunucusu, demo hesabı ve inceleme notlarını hazırlamak.

