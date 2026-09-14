# Hair Transplant Consultation App — Project Plan

> This document is available in both English and Turkish. The English version appears first, followed by the original Turkish version.
>
> Bu doküman İngilizce ve Türkçe olarak hazırlanmıştır. Önce İngilizce sürüm, ardından özgün Türkçe sürüm yer alır.

# English

## 1. Purpose and scope

The app manages hair-transplant consultation cases through a structured, traceable, role-based workflow between agents and doctors. The supplied HTML page is only a UX mock-up/prototype; the final product is intended to be a native mobile application, not a web app.

## 2. Roles and permissions

After sign-in, each user is sent to a role-specific workspace: **Doctor → case queue**, **Agent → case workspace**, **Admin → system management**. The roles do not share one main screen.

### Agent

- Creates a new case/post, uploads patient photos and adds the case note.
- Sets and locks the case **Graft Number** and **Price**; doctors cannot alter these agent values.
- Views the doctor's response and may add follow-up questions, information or photos.
- Closes a satisfactory response using **Confirm & Close**.
- Sees only their own name/**You** in uploader information, or no uploader field; other agents' identities are never shown.

### Doctor

- Sees cases assigned to their patients and new unassigned cases; doctors are the only role that replies to posts.
- Every response includes free text, **Approx. Graft Number**, and **Recommended Price**.
- Reviews unanswered cases FIFO by default (oldest first).
- A reply changes the case to **Waiting for Agent Confirmation / Answered**.
- Can see who uploaded each case.

### Admin

- Does not reply to posts or intervene in doctor-agent correspondence.
- Manages system settings, operations, users, roles and reporting.
- May see the uploader for audit/reporting, without gaining reply permission.
- Can assign a patient before a reply and reassign them with a required reason when needed.

### Simple web Admin Panel

- Available at `/admin` on the same server and accepts only server accounts with the **Admin** role.
- The user list shows Doctor, Agent and Admin accounts, username, display name, role, agency, active state, and related case/patient counts.
- An admin creates users with a display name, unique username, role and temporary password. Agents must be assigned to an existing agency; a new agency may be created in the same form. There is no public registration.
- **Deactivate** removes access and revokes active sessions; **Reactivate** restores access. Permanent **Delete** is permitted only for already-deactivated, unused accounts with no case, patient, message or photo history. Accounts with clinical history remain inactive to preserve audit integrity.
- The patient/case table tracks patient name and Patient ID, case reference, status, agent, assigned doctor, photo/message counts, graft/price values and upload time.
- Case lists can be filtered by status, doctor assignment, agency and doctor; user lists by role, access state and agency. Search works with active filter chips and filters can be cleared in one action.
- Admins can assign an active doctor from the table. Changing an existing doctor requires a reason and all assignments/reassignments are written to the audit trail.
- The panel is responsive: the page does not overflow on mobile, and wide case tables scroll horizontally inside their own area.

### Native mobile Admin area

- Admin users see only the admin management area in the iOS app, not the Doctor or Agent screens.
- The web panel's case tracking, user/agency management, doctor assignment and filtering are available through the same server API in the native client.
- Small screens use **Cases / Users** tabs, compact counters, one search field and a collapsible filter panel rather than a desktop table.
- Cases and users appear as summary cards; management actions are shown only when the relevant card is opened.
- Cases support status, assignment, agency and doctor filters; Users support role, active state and agency filters. Search combines with filters and all can be cleared at once.
- Admins can create users/agencies; creating an Agent requires an active agency.
- Changing or removing a doctor assignment requires a short reason. Deactivation and permanent deletion require clear confirmation.
- Lists support pull-to-refresh; all data is loaded from the server rather than copied into the app.

## 3. Case-state workflow

1. Agent uploads the case and photos → **Waiting for Doctor**.
2. Doctor replies → **Waiting for Agent Confirmation / Answered**.
3. Agent adds a question or photo → back to **Waiting for Doctor** and the case returns to the doctor's unanswered queue.
4. Agent chooses **Confirm & Close** → **Closed**.

Only the agent can close a case; a doctor reply alone does not close it.

### Patient-doctor assignment

- Every patient has a persistent server-side **Patient ID**; the displayed **HT-...** value is a separate case/post reference.
- Admin may assign a patient in advance. If there is no assignment, the first valid doctor to answer becomes the responsible doctor.
- The responsible-doctor relationship remains after closing; later photos, questions or updates from the same patient go directly to that doctor's queue.
- Other doctors do not see that patient in their default queues. Admin sees all patients and can transfer ownership.
- The server atomically applies **Waiting + Unassigned → Answered + Assigned Doctor**. The first reply is accepted; stale replies are rejected and the doctor sees the current state.
- Assignments, reassignments, first replies and rejected conflicts are recorded in the audit trail.

### Multiple agents and duplicate-patient checks

- Different agents may submit the same patient. Before saving, the server searches likely records using normalized patient name and, where permitted, secondary identifiers such as date of birth and phone/email.
- A name match never merges records automatically; an agent must make the final confirmation.
- On a possible match, the agent sees only that the patient may already have been recorded and consulted. The originating agent or company is never disclosed.
- A small verification flow displays privacy-banded photos only; it does not expose Patient ID, agent identity or other organization information.
- **Yes — Same Patient** stops the new record. The agent cannot open, edit or copy the existing record.
- **Different Patient** requires a second explicit confirmation after reviewing the profile photo; a new Patient ID is created and the decision is audited.
- The server repeats the check at creation time and uses transaction/unique-identity/revalidation safeguards against concurrent creation by two agents.
- MVP does not use automatic facial recognition; profile photos are shown for human verification only.

## 4. Doctor home screen

- Instant search by patient name, agent name, case reference or note, with **Oldest First / Newest First** ordering.
- **My Waiting / Unassigned / Answered / Closed** filters with counts below the search row.
- Search and sorting stay fixed below navigation while scrolling; filters remain in normal flow to preserve space.
- FIFO is the default: oldest waiting case first.
- The case list uses two columns on desktop and one on tablet/mobile while keeping the same card order.
- Cards show upload time, reference, one large photo preview, patient name, **Assigned to you / Unassigned**, note summary, locked **Graft Number / Price**, status and a compact uploader label.
- Selecting the uploader filters all posts from that agent; the active filter can be cleared by chip.
- Opening a waiting card reveals a detail area/modal with large and additional photos, full note, conversation and response form.
- Approximate graft number, recommended price and explanation are all mandatory in a doctor response and are stored/displayed together.
- Cards show one main photo; additional photos are available with swipe/arrows before opening, with a current/total chip.
- Full-screen viewing supports touch swipe, left/right controls and keyboard arrows.
- Doctors can draw and add text notes separately on every full-screen photo using Draw, Text, Undo, Clear and Done.
- On reply, the UI changes the case to Answered and updates counters. An unassigned-case reply is labelled **Respond & Take Patient** and creates the permanent assignment.
- In waiting-case detail, there is no duplicate Respond shortcut: **Doctor Response** is open at the end of the page, and the photo action is named **View & Annotate**.

## 5. Agent case-creation screen

- Available only to Agents as a separate native screen; the HTML file is only a mock-up.
- **New Case** opens it from the agent workspace and completion returns to **My Cases**.
- Desktop shows **Case Details** left and **Patient Photos** right; narrow screens retain that vertical order.
- Case Details is always open in create mode. In mobile edit mode it is collapsed by default and offers **Expand / Collapse**; desktop stays open.
- Agents can select multiple photos, receive shared photos, add/delete/reorder them.
- The system generates/retrieves a unique **Case Reference** for each post; agents cannot edit it. Persistent Patient ID is separate.
- The reference appears at the top right of Case Details as **Reference: HT-...**, shortened to **Ref:** on narrow mobile layouts.
- Required fields are **Patient Name**, agent note, **Graft Number**, currency and **Price**.
- Typing a patient name triggers duplicate checks. A match requires the agent to choose updating the existing patient or creating a same-name, different patient before proceeding.
- Required-field guidance appears as a small note below fields; the graft/price guidance appears full width immediately below Patient Name.
- A case cannot be sent until all required fields and at least two photos are present.
- Agent-set Graft Number and Price are locked at submit time; doctors enter their own estimates separately.
- **Save Draft** keeps only a draft. **Submit to Doctor** creates the case and sets **Waiting for Doctor**.
- There is no separate ready-information box: the button is disabled as **Not Ready** until complete, then becomes green **Ready to Submit**.
- The success screen clearly shows reference and new state.
- One shared form component supports both **New Case** and **Edit Case**.
- Edit mode loads patient information/photos and shows historical agent/doctor comments chronologically below photos, preserving doctor estimate values.
- Patient name and the first agent note are read-only in edit mode. Only **Graft Number**, currency and **Price** may be changed.
- **Save Graft & Price** saves only those values; adding/removing photos is written to the server immediately.
- New photos or follow-up comments/questions return the case to the responsible doctor as **Waiting for Doctor**.
- When a doctor reply is pending, **Confirm & Close** is a separate primary agent action.
- Comments remain comfortably readable on mobile, and the Case Details reference/edit controls stay responsively within card bounds.

## 6. App Store distribution model

- Publish a general-purpose, clinic-independent client that anyone can download from the App Store.
- The app bundle contains no clinic name/logo, live server address, patient data, access key or clinic-specific information.
- Store copy explains that authorized users connect to their organization's compatible server and require a valid server and account.
- On first launch, users enter their **Server Address**. QR code or secure-link setup may be added later.
- Each clinic connects by entering its real server address and manages its own data, users and settings in its own server environment.
- Apple review receives a separate continuously available **demo server** and active demo Doctor account, with address, credentials and core test steps in review notes.
- Demo uses only synthetic data, can be safely reset and remains available throughout review.
- A **Try Demo** option can securely fill the demo address; **Connect to Your Server** accepts a user's own address.
- Apple's Custom Apps and Unlisted Apps remain alternatives, but the chosen model is public App Store distribution.

### First connection and sign-in

- First launch requests only Server Address and validates availability, API version and capabilities through `/api/v1/health`.
- After connection, a separate Username/Password screen opens. There is no registration, invitation acceptance or public membership flow.
- Server-side admins create all users and determine roles/permissions.
- After their first successful sign-in on a server, Doctor and Agent users receive a role-specific **Quick Tour**; Admin does not.
- The Doctor tour covers queue search/filter/sort, cards, photos/full screen/annotation, Doctor Response and patient ownership. The Agent tour covers My Cases, **+ New**, duplicate checks, follow-up photo/message and **Confirm & Close**.
- The four-step tour clearly identifies each control, is skippable and does not repeat at every sign-in. Completion is stored on-device by server address, user, role and tour version; it can be reopened from Profile with **Show app tour again**.
- Users can update display name, email and phone from Profile; username and role remain server-managed.
- Signed-in users can change password after confirming the existing password; this ends other active sessions.
- **Forgot Password** requests a six-digit code valid for 10 minutes by username or registered email. Successful reset revokes older sessions, does not reveal account existence and rate-limits failed attempts.
- Codes are sent only via SMTP email; Firebase/OTP is not used. Passwords are never stored on-device; the server's time-limited session token is kept in iOS Keychain and deleted on logout.
- Users can log out or change server; changing server ends the session and returns to connection.
- Local development may permit LAN HTTP; App Store/production builds require HTTPS.

## 7. Modular client-server architecture

### Server

- Manages authentication, roles/permissions, durable patient-doctor assignment, duplicate checks, case states, atomic response transitions, messages, media, annotations, audit trail, reporting and notifications.
- The primary database for patients, cases, comments, assignments, prices and audit records is local **SQLite** running on the server.
- Only the server accesses SQLite; iOS/Android clients use a versioned HTTPS API and never connect to the database directly.
- Authentication uses username/password and time-limited session tokens. Password recovery uses SMTP, not Firebase; push notifications use an independent notification adapter and APNs on iOS.
- Clinic-specific settings (name, logo, support, timezone, feature flags and legal links) belong in server environment configuration. Secrets remain in environment/secret management and are never sent to clients.
- Safe branding/feature information is exposed through a versioned public configuration/capabilities endpoint. Clients validate health, API compatibility and supported features before connecting.

### Clients

- iOS and Android handle UI, server setup, photo upload/sharing, gallery, full-screen viewing and drawing/text annotations.
- Server address and session information use each platform's secure storage; users can log out or change server.
- HTTPS is mandatory for production/demo. Clients accept only the expected API contract and never load executable code from a remote server.
- Native clients and server can evolve separately through a common API contract. Recommended modules: **server**, **ios-client**, **android-client**, **shared-api-contract**.

### Environment separation and security

- Demo and production use fully separate domains, databases, media stores and access credentials.
- Every server must provide role-based access, tenant/clinic isolation, audit logging, rate limiting, secure media access and session revocation.
- A supplied server address is validated for format, HTTPS, certificate, API version and capabilities before sign-in/data transfer starts.
- Because addresses may change, use standard secure TLS validation rather than fixed single-domain pinning; organization-specific policies may be set server-side.

## 8. Mobile sharing target

- WhatsApp automation is not planned.
- Use an iOS **Share Extension** and Android **Share Intent**.
- Intended flow: select photos → **Share** → choose the app → add to a new or existing case.

## 9. Design principles

- Simple, professional, medical visual language.
- Light theme, high legibility and clear status indicators.
- Task-focused UI that avoids a social-media feel.
- Responsive across desktop, tablet and mobile.
- Patient privacy and role-based access are fundamental product requirements.

## 10. Post-prototype decisions

- Test usability of doctor cards and detail screens.
- Design the Agent case-creation and Confirm & Close flows.
- Finalize notification, authentication, audit-trail and data-retention requirements.
- Design first connection, server validation, demo selection and server-change screens.
- Finalize the shared API contract, compatibility policy and server capabilities model.
- Prepare demo-server lifecycle, review accounts and synthetic-data reset procedure for Apple review.
- After mock-up approval, detail the technical architecture and API/data model for native iOS/Android clients and the independent server.

---

# Türkçe

# Saç Ekimi Danışmanlık Uygulaması — Kısa Proje Planı

## 1. Amaç ve kapsam

Saç ekimi danışmanlık vakalarının agent ile doktor arasında düzenli, izlenebilir ve rol bazlı bir akışla yönetilmesi. Hazırlanan HTML sayfası yalnızca kullanıcı deneyimini denemek için bir mockup/prototiptir; nihai ürün web uygulaması değil, native mobil uygulama olarak hedeflenmektedir.

## 2. Roller ve yetkiler

Kullanıcı giriş yaptıktan sonra rolüne göre farklı bir çalışma alanına yönlendirilir: **Doctor → doktor vaka kuyruğu**, **Agent → agent vaka alanı**, **Admin → sistem yönetimi**. Roller aynı ana ekranı paylaşmaz.

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

### Basit web Admin Paneli

- Admin paneli aynı server üzerinde `/admin` adresinden açılır ve yalnızca **Admin** rolündeki server hesaplarını kabul eder.
- Kullanıcı listesinde Doctor, Agent ve Admin hesapları; kullanıcı adı, görünen isim, rol, bağlı ajans, aktiflik ve ilişkili vaka/hasta sayıları gösterilir.
- Admin yeni kullanıcı oluştururken görünen isim, benzersiz kullanıcı adı, rol ve geçici parola belirler. Agent rolü için mevcut bir ajans seçmek zorunludur; gerekiyorsa aynı form içinde yeni ajans oluşturulabilir. Uygulamada veya panelde herkese açık üyelik bulunmaz.
- **Deactivate** erişimi kapatır ve mevcut oturumları iptal eder; gerektiğinde **Reactivate** yapılabilir. Kalıcı **Delete** yalnızca önce pasifleştirilmiş ve hiçbir vaka, hasta, mesaj veya fotoğraf geçmişi olmayan kullanılmamış hesaplar için mümkündür. Klinik geçmişi bulunan hesaplar audit bütünlüğü için silinmez, pasif tutulur.
- Hasta/vaka tablosunda hasta adı ve Patient ID, vaka referansı, durum, agent, atanmış doktor, fotoğraf ve mesaj sayıları, graft/fiyat değerleri ve yüklenme zamanı izlenir.
- Hasta/vaka listesi durum, doktor ataması, ajans ve doktor çipleriyle; kullanıcı listesi rol, erişim durumu ve ajans çipleriyle hızlıca filtrelenebilir. Arama alanı aktif çiplerle birlikte çalışır ve filtreler tek eylemle temizlenebilir.
- Admin tablodan hastaya aktif bir doktor atayabilir. Mevcut doktor değiştiriliyorsa gerekçe zorunludur; atama ve yeniden atama audit trail'e yazılır.
- Panel responsive çalışır; mobilde genel sayfa taşmaz, geniş vaka tablosu kendi alanı içinde yatay kaydırılır.

### Native mobil Admin alanı

- Admin rolüyle giriş yapan kullanıcı iOS uygulamasında Doctor veya Agent ekranını değil, yalnızca admin yönetim alanını görür.
- Web panelindeki vaka takibi, kullanıcı yönetimi, ajans yönetimi, doktor atama ve filtreleme işlevleri aynı server API'si üzerinden native mobil istemcide de kullanılabilir.
- Küçük ekranda masaüstü tablosu kullanılmaz. **Cases / Users** sekmeleri, kompakt sayaçlar, tek arama alanı ve gerektiğinde açılan filtre paneli kullanılır; filtreler kapalıyken ekranı daraltmaz.
- Vaka ve kullanıcılar kısa özet kartlar halinde gösterilir. Doktor atama, pasifleştirme, yeniden aktifleştirme ve silme gibi yönetim eylemleri yalnızca ilgili kart açıldığında görünür.
- Cases alanında durum, atanmış/atanmamış, ajans ve doktor; Users alanında rol, aktiflik ve ajans filtreleri bulunur. Arama bu filtrelerle birlikte çalışır ve tüm filtreler tek işlemle temizlenebilir.
- Admin yeni kullanıcı ve yeni ajans oluşturabilir. Agent hesabı oluşturulurken aktif bir ajans seçmek zorunludur.
- Mevcut doktor değiştiriliyor veya atama kaldırılıyorsa kısa bir gerekçe zorunludur. Kullanıcı pasifleştirme ve kalıcı silme işlemleri açık bir onay adımı ister.
- Liste aşağı çekilerek yenilenebilir; tüm veriler uygulama içinde ayrıca kopyalanmadan server'dan alınır.

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
- Doctor ve Agent kullanıcılarına ilgili server'daki ilk başarılı girişlerinden sonra rollerine özel kısa bir **Quick Tour** gösterilir. Admin için bu tur açılmaz.
- Doctor turu kuyruk arama/filtreleme ve sıralamayı, vaka kartını açmayı, fotoğraflar arasında gezinme–tam ekran–çizim/metin anotasyonunu, Doctor Response alanını ve hasta–doktor sahipliğini açıklar.
- Agent turu kendi vaka listesini, **+ New** ile başlayan oluşturma sihirbazını, mükerrer hasta kontrolünü, doktor yanıtından sonra mesaj/fotoğraf eklemeyi ve **Confirm & Close** işlemini açıklar.
- Tur dört kısa adımdan oluşur; her adım hangi kontrole dokunulacağını açıkça belirtir. Kullanıcı turu atlayabilir; atlama da tamamlanmış sayılır ve her girişte tekrar gösterilmez.
- Turun tamamlanma durumu server adresi, kullanıcı kimliği, rol ve tur sürümüne göre cihazda tutulur. Başka server veya başka kullanıcı birbirinin durumunu paylaşmaz. Doctor ve Agent turu Profile içindeki **Show app tour again** seçeneğiyle yeniden açabilir.
- Her kullanıcı uygulamadaki profil sayfasından görünen adını, e-posta adresini ve telefon numarasını güncelleyebilir. Kullanıcı adı ve rol server yönetiminde kalır.
- Oturum açmış kullanıcı mevcut parolasını doğrulayarak yeni parola belirleyebilir; işlem diğer aktif oturumları kapatır.
- **Forgot Password** akışında kullanıcı adı veya kayıtlı e-posta ile altı haneli, 10 dakika geçerli doğrulama kodu istenir. Kod doğrulanınca parola yenilenir ve tüm eski oturumlar iptal edilir. Hesap varlığı dışarıya açıklanmaz ve başarısız kod denemeleri sınırlandırılır.
- Reset kodu yalnızca kayıtlı e-posta adresine **SMTP** üzerinden gönderilir. Firebase/OTP kullanılmayacaktır.
- Parola cihazda saklanmaz. Başarılı girişten sonra server'ın verdiği süreli oturum anahtarı iOS Keychain içinde tutulur; çıkışta silinir.
- Kullanıcı çıkış yapabilir veya bağlı server'ı değiştirebilir. Server değiştirme işlemi mevcut oturumu kapatır ve bağlantı adımına döner.
- Yerel geliştirme derlemesinde LAN üzerindeki HTTP server'a izin verilebilir; App Store/üretim derlemesinde HTTPS zorunludur.

## 7. Modüler istemci–sunucu mimarisi

### Sunucu

- Kimlik doğrulama, rol ve yetkiler, kalıcı hasta–doktor ataması, mükerrer hasta adayı arama/doğrulama, vaka durumları, atomik cevap geçişleri, mesajlar, medya, fotoğraf anotasyonları, audit trail, raporlama ve bildirimleri yönetir.
- Hasta, vaka, yorum, doktor ataması, fiyat ve audit kayıtlarının ana veritabanı sunucuda çalışan **lokal SQLite** olacaktır.
- SQLite erişimi yalnızca server katmanından yapılır; iOS/Android istemcileri veritabanına doğrudan bağlanmaz ve tüm işlemleri sürümlü HTTPS API üzerinden gerçekleştirir.
- Kimlik doğrulama server üzerinde kullanıcı adı/parola ve süreli oturum anahtarıyla yapılır. Parola kurtarma SMTP e-postasıyla yürütülür; Firebase kullanılmaz. Push bildirimleri kimlik doğrulamadan bağımsız bir bildirim adaptörüyle, iOS tarafında APNs üzerinden ele alınır.
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
