# EcoPulse OSB istemcisi

Windows, Android ve web için tek Flutter uygulaması. Ortak API'ye (`http://127.0.0.1:5080`) bağlanır.

```bash
flutter pub get
flutter run -d windows              # masaüstü
flutter run -d <cihaz>              # Android (önce: adb reverse tcp:5080 tcp:5080)
flutter test
```

Farklı bir API adresi için: `flutter run --dart-define=API_BASE=http://<adres>:5080`

Normal kullanımda depo kökündeki `Start-EcoPulse.ps1` derleme ve başlatmayı kendisi yapar.
