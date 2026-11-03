# EcoPulse OSB

Windows masaüstü enerji izleme panosu. Simülasyon ve SQLite veritabanı uygulamaya dahildir; son kullanıcıda Docker, Python veya ayrıca .NET kurulumu gerekmez.

## İndir ve çalıştır

[**Windows x64 uygulamasını indir**](https://github.com/FatihTosun9037/EcoPulse/releases/latest/download/EcoPulse-Windows-x64.zip)

1. ZIP dosyasını indirin ve bir klasöre çıkarın.
2. `EcoPulse.Dashboard.exe` dosyasına çift tıklayın.

Uygulama Windows x64 içindir. İlk açılışta Windows SmartScreen uyarısı gösterebilir; yalnızca bu depodaki resmi sürümü indirdiğinizden emin olduktan sonra devam edin.

Her bilgisayar kendi verisini `%LOCALAPPDATA%\EcoPulse\ecopulse.db` dosyasında saklar. Bilgisayarlar arasında ortak veritabanı kullanılmaz.

## Demo akışı

Panelde bir makine seçip **Arıza bas** ile simülasyon arızası oluşturun. Alarm yaklaşık 6 saniye içinde görünür. Alarmı seçip **Bakım Bildir** dediğinizde uygulama müdahale öncesi tahmini kayıp oranını kaydeder; sonraki üç normal ölçüm müdahaleyi doğrular. Doğrulanan kayıp ve CO₂ değerleri saatlik oranlardır, sahada ölçülmüş veya birikmiş tasarruf tutarı değildir.

## Kaynaktan derleme

Geliştirme için Windows ve .NET 9 SDK gerekir:

```powershell
dotnet run --project .\dashboard\EcoPulse.Dashboard.csproj
```

Bağımsız, paylaşılabilir Windows paketini üretmek için proje klasöründeki `Publish-EcoPulse.ps1` betiğini çalıştırın. Betik `EcoPulse-Windows-x64` klasörünü ve ZIP paketini oluşturur.

GitHub Actions sürüm oluşturma iş akışı, `v` ile başlayan bir etiket yayımlandığında kendi Windows x64 paketini oluşturup GitHub Release'e yükler.

## Proje yapısı

- `dashboard/` — WPF masaüstü uygulaması, yerel SQLite deposu ve sensör simülatörü.

Teknik rapor: [EcoPulse-Proje-Teknik-Raporu.docx](./EcoPulse-Proje-Teknik-Raporu.docx).
