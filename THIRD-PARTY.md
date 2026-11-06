# Third-party source and license record

MoleDPI kendi Swift kaynakları, ayrıcalıklı PF yardımcısı ve betikleri: GPL-3.0-only (`LICENSE`).

## Paketlenen motor

**bol-van/zapret tpws**

- Kaynak: https://github.com/bol-van/zapret
- Sabit revizyon: `73ee2aa04e6e94922e7dc07554a1c3a456dc3201`
- Lisans: MIT, Copyright (c) 2016–2024 bol-van.
- Kaynak ve lisans: `vendor/zapret/tpws`, `vendor/zapret/LICENSE.txt`.
- epoll-shim, uthash, kavl ve macOS uyumluluk başlıklarının kendi telif/lisans bildirimleri kaynak dosyalarında korunur. Sistem zlib/pthread bileşenleri macOS'tan bağlanır, yeniden paketlenmez.
- Hazır motor ikilisi indirilmez. Apple clang ile arm64/macOS 13 hedefi için kaynak dosyaları derlenir.

**MoleDPI uyarlaması:** `tpws_conn.c` içine, yalnızca ilk TLS bölümü arasında isteğe bağlı 0–20.000 mikro saniye bekleyen dar bir ek yapıldı. `MOLEDPI_SPLIT_DELAY_US` sayısal, sınırlı değer dışında kabul edilmez. Normal hızlı profillerde 0'dır. Son yedek profilde 20 ms'dir; bu bekleme olay döngüsünü kısa süre durdurur. Buradaki gerçek testte beklemesiz ilk profil başarılı oldu. Değişiklik upstream'e aitmiş gibi sunulmaz.

## İncelenen; kodu/ikilisi paketlenmeyen projeler

| Proje | İncelenen revizyon | Lisans |
| --- | --- | --- |
| FreeDPI | `faa2bfc57fe3298c532f64583e87a07f85986526` | GPL-3.0 |
| GoodbyeDPI | `f593a276f9ec753889f80208c6a7c5cf455df94a` | Apache-2.0 |
| SpoofDPI-Turkiye | `1ee03b200c0991e809b24e5c69bde8d0d22638a4` | MIT |
| darkware-zapret | `1d9834a5716d65b6140df24dd64fec350d461bb9` | MIT üst proje; motorların ayrı lisansları var |

ByeDPI Android, onun MIT lisanslı ByeDPI C alt modülü ve hev-socks5-tunnel kaynakları da mimari araştırma için incelendi. Bunlar bu uygulamaya veya kaynak arşivine eklenmedi. GPL lisanslı bir arayüzün MIT lisanslı motor kullanması, bütün bu projelerin aynı lisansa sahip olduğu anlamına gelmez.

Kaynak/ikili dağıtırken MoleDPI'ın ilgili tam kaynak kodunu, derleme betiklerini, bu bildirimleri ve upstream lisanslarını koru. Bu arşiv kaynakları ve paketleme betiklerini birlikte sunar; uygulama paketinde de lisans dosyaları bulunur.

epoll-shim uyumluluk kodu için Jan Kokemüller’in MIT bildirimi de pakete eklenmiştir (jiixyj/epoll-shim, lisans karşılaştırması 18159584bb3d17e601b9315a7398ace018251bdc). Bu kimlik lisansın alındığı kaynaktır; zapret içindeki eski uyarlamanın birebir revizyonu olarak kullanılmaz. uthash BSD-1-Clause, kavl MIT ve macos/sys/tree.h içindeki BSD bildirimi ilgili kaynaklarda yer alır.

## Experimental QUIC components
ByeDPI e2684772fbda45f2ff4fc220922a010370534216 (MIT), with the documented macOS shutdown patch and a local QUIC Initial gate, and HEV SOCKS tunnel 21bb3d77e64ad5a413d4d851b9f4cacf2098cd77 (MIT), plus its pinned MIT/BSD dependencies, are source-built and bundled. Full sources are in vendor/byedpi and vendor/hev. Original notices are preserved there and in Experimental/UDP/Licenses. These are local processes, not remote VPN services.
