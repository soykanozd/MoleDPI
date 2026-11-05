# MoleDPI — macOS için yerel DPI aşma

**Deneysel yazılım: hatalar, bağlantı kesintileri ve erişim sorunları olabilir.**

MoleDPI, Apple Silicon Mac'lerde yerel TCP/TLS tekniklerini deneyen ücretsiz, açık kaynak bir menü çubuğu uygulamasıdır. VPN sunucusu, hesap veya abonelik gerektirmez. Uygulamanın arayüzü İngilizcedir.

[Mac için indir](https://github.com/soykanozd/MoleDPI/releases/latest/download/MoleDPI.dmg) · [Sürüm notları](https://github.com/soykanozd/MoleDPI/releases/latest) · [English](README.md)

## Kurulum

Apple Silicon işlemcili Mac ve macOS 13 veya üzeri hedeflenir. Eski macOS sürümleri ve farklı cihazlarda kapsamlı uyumluluk henüz doğrulanmamıştır.

1. Yukarıdaki bağlantıdan **MoleDPI.dmg** dosyasını indir.
2. Dosyayı aç; **MoleDPI** uygulamasını **Applications** klasörüne sürükle.
3. Applications içinden uygulamayı aç.
4. Menü çubuğundaki kask simgesine, ardından **Connect** düğmesine bas.
5. macOS isterse yerel ağ yardımcısına yönetici izni ver.

**Apple noter onayı yoktur.** Dağıtım geçici yerel imza kullanır; macOS indirilen uygulamayı engelleyebilir. Yalnızca güvendiğin kopyayı, [Apple'ın resmi açma yönergesini](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) izleyerek onayla. Gatekeeper'ı veya sistem güvenliğini kapatma. Sistem izin vermiyorsa noter onaylı sürümü bekle.

## Kullanım ve güncelleme

- Simgeye sol tık paneli açar; paneli kapatmak bağlantıyı kesmez.
- **Disconnect** oturumun ağ ayarlarını geri yükler ve otomatik toparlanmayı durdurur.
- Simgeye sağ tık → **Quit MoleDPI**, ağ temizliği tamamlandıktan sonra uygulamayı kapatır.
- **? → Connection Help** son gözlenen bağlantı hatasına göre yol gösterir.
- **? → Check for Updates**, GitHub üzerinden yeni sürüm arar. Yeni sürüm varsa **View Release** doğrudan o sürümün GitHub sayfasını açar.
- Güncellerken önce Disconnect ve Quit yap, sonra Applications içindeki kopyayı yenisiyle değiştir. Değişen derleme için bir kez yeniden yönetici izni gerekebilir.

## Gerçek sınırlar ve gizlilik

Bu araç VPN veya anonimlik hizmeti değildir; genel IP adresini gizlemez. DPI işlemesini TCP 80/443 üzerinde yapar. Uygulamaların UDP/QUIC trafiği normal ağ yolunu kullanır; MoleDPI bunu işlemez. Ağ yolları erişilebiliyorsa ses, ekran paylaşımı ve oyunlar çalışabilir. Bu, bir UDP engelinin aşıldığı anlamına gelmez. [UDP davranışı ve test kapsamı](docs/UDP.md) belgesine bak. Connected, belirli HTTPS kontrollerinin ve ağ motoru doğrulamasının geçtiğini gösterir; bütün internet için garanti vermez.

Gerekirse yalnızca kaynak kodda tanımlı sınırlı alan adları için Quad9 üzerinden HTTPS ile DNS kurtarması kullanılır. Quad9 bu sorguları görebilir; diğer DNS trafiği sistem ayarlarını izler. Uygulama tarama geçmişi veya trafik içeriği kaydetmez; tanılama raporlarını kendiliğinden göndermez. İsteğe bağlı güncelleme kontrolünde GitHub istek IP'sini görebilir.

Fiziksel uyku/uyanma, Wi-Fi değişimi, temiz cihazda kurulum/kaldırma, uzun süreli kararlılık ve bağımsız güvenlik incelemesi henüz tamamen doğrulanmamıştır. Teknik ayrıntılar ve lisanslar için [English README](README.md), [test kapsamı](RELEASE-TESTS.md) ve [GPL-3.0 lisansı](LICENSE) dosyalarına bak.

## Sorun bildir

[GitHub Issues](https://github.com/soykanozd/MoleDPI/issues/new/choose) üzerinden uygulama/macOS sürümü, izlenen adımlar ve beklenen sonucu paylaş. Parola, token, kişisel ağ adı, IP adresi, tarama geçmişi veya sansürlenmemiş ekran görüntüsü gönderme. **Review Diagnostics** içeriğini paylaşmadan önce incele.

## Kaldırma

Disconnect ve Quit yap. DMG içindeki **Uninstall MoleDPI** uygulamasını açıp macOS onayını ver; ardından ana uygulamayı Applications klasöründen Çöp Sepeti'ne taşı. Yalnızca ana uygulamayı silmek yardımcı bileşen kaydını kaldırmaz.
