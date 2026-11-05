using System.Globalization;
using Microsoft.Extensions.Hosting;

namespace EcoPulse.Api;

public sealed class PlantEngine : BackgroundService
{
    private const double PhaseFactor = 1.7320508075688772;
    private const double LoadedPowerFactor = 0.85;
    private const double IdlePowerFactor = 0.25;
    private const double AmbientTemperature = 25.0;
    private const double HeatTransferCoefficient = 10.0;
    private const double TlPerKw = 4.092;
    // ETKB 2022 tüketim noktası emisyon faktörü, dağıtım şebekesine bağlı tüketici: 0,474 tCO₂/MWh.
    private const double Co2PerKw = 0.474;
    private const string Co2FactorText = "0,474 kg CO₂/kWh";
    private const string Co2SourceText =
        "T.C. Enerji ve Tabii Kaynaklar Bakanlığı, Türkiye Elektrik Üretimi ve Elektrik Tüketim Noktası Emisyon Faktörleri Bilgi Formu (ETKB-EVÇED-FRM-042), 2022: dağıtım şebekesine bağlı tüketim noktası 0,474 tCO₂/MWh.";
    private const string Co2SourceUrl =
        "https://enerji.gov.tr/Media/Dizin/EVCED/tr/ÇevreVeİklim/İklimDeğişikliği/EmisyonFaktorleri/2022_Uretim_Tuketim_EF.pdf";
    private const double HoursPerYear = 8760;
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    private readonly object _gate = new();
    private readonly Random _random = new();
    private readonly MachineState[] _machines =
    [
        // Başlangıçta her makine kendi alanındaki uzmana atanır; yönetici Personel ekranından değiştirebilir.
        // NominalFlow: soğutma / proses suyu debisi (m³/h). FlowPeriod ve FlowPhase pompa salınımını belirler.
        new(1, "Kompresör Hattı A", "Pres Atölyesi", 100, 75, 4, "ELEKTRIK") { PersonnelId = 1, NominalFlow = 6.0, FlowPeriod = 26, FlowPhase = 0.0 },
        new(2, "Enjeksiyon Makinesi 2", "Plastik Üretim", 80, 85, 3, "URETIM") { PersonnelId = 3, NominalFlow = 4.5, FlowPeriod = 34, FlowPhase = 1.3 },
        new(3, "Fırın Konveyörü", "Isıl İşlem", 60, 180, 8, "ISI") { PersonnelId = 2, NominalFlow = 9.0, FlowPeriod = 40, FlowPhase = 2.1 },
        new(4, "Soğutma Pompası", "Enerji Merkezi", 40, 55, 1.5, "ISI") { PersonnelId = 2, NominalFlow = 18.0, FlowPeriod = 22, FlowPhase = 3.4 },
        new(5, "CNC İşleme Merkezi", "Talaşlı İmalat", 50, 70, 2.5, "URETIM") { PersonnelId = 3, NominalFlow = 2.5, FlowPeriod = 30, FlowPhase = 4.6 }
    ];
    private readonly PersonnelState[] _personnel =
    [
        new(1, "Kerem Aydın", "ELEKTRIK", "Aşırı akım ve elektrik hatları"),
        new(2, "Selin Arslan", "ISI", "Atık ısı ve izolasyon"),
        new(3, "Burak Demir", "URETIM", "Boşta çalışma ve üretim hatları")
    ];
    private readonly Dictionary<(int MachineId, string Type), int> _counts = new();
    private readonly List<AlarmState> _alarms = new();
    private readonly List<OrderState> _orders = new();
    private readonly List<DeviceState> _devices = new();
    private readonly List<NoticeState> _notices = new();
    private int _faultMachineId;
    private int _nextAlarmId = 1;
    private int _nextOrderId = 1;
    private int _nextNoticeId = 1;
    private readonly List<double> _totalFlowSeries = new();
    private readonly WaterFactor? _waterFactor;
    private long _tick;

    public PlantEngine(IConfiguration configuration)
    {
        // Elektrik → su katsayısı yapılandırmadan okunur; tanımlı değilse önlenen su hesaplanmaz.
        double factor = configuration.GetValue<double?>("Water:M3PerMWh") ?? 0;
        _waterFactor = factor > 0
            ? new WaterFactor(
                factor,
                configuration["Water:Scope"] ?? "",
                configuration["Water:Source"] ?? "",
                configuration["Water:SourceUrl"] ?? "")
            : null;
    }

    public IReadOnlyList<MachineDto> Machines()
    {
        lock (_gate)
        {
            return _machines.Select(ToMachine).ToArray();
        }
    }

    public IReadOnlyList<PersonnelDto> Personnel()
    {
        lock (_gate)
        {
            return _personnel
                .Select(person => new PersonnelDto(person.Id, person.FullName, person.Expertise, person.ExpertiseLabel))
                .ToArray();
        }
    }

    public AssignmentResultDto AssignMachine(int personnelId, int machineId)
    {
        lock (_gate)
        {
            PersonnelState? person = _personnel.FirstOrDefault(item => item.Id == personnelId);
            MachineState? machine = Find(machineId);
            if (person is null || machine is null)
            {
                return new AssignmentResultDto(false, false, "Personel veya makine bulunamadı.");
            }

            bool mismatch = person.Expertise != machine.Domain;
            machine.PersonnelId = person.Id;
            return new AssignmentResultDto(
                true,
                mismatch,
                mismatch
                    ? $"Uyarı: {machine.Name}, {person.FullName} uzmanlığıyla uyuşmuyor. Atama kaydedildi."
                    : $"{machine.Name}, {person.FullName} üzerine atandı.");
        }
    }

    public AssignmentResultDto UnassignMachine(int machineId)
    {
        lock (_gate)
        {
            MachineState? machine = Find(machineId);
            if (machine is null)
            {
                return new AssignmentResultDto(false, false, "Makine bulunamadı.");
            }

            machine.PersonnelId = null;
            return new AssignmentResultDto(true, false, $"{machine.Name} ataması kaldırıldı.");
        }
    }

    public IReadOnlyList<AlarmDto> Alarms()
    {
        lock (_gate)
        {
            return BuildAlarms();
        }
    }

    public DashboardDto Dashboard()
    {
        lock (_gate)
        {
            double power = _machines.Sum(machine => machine.Power);
            double activeLoss = _alarms.Where(alarm => alarm.Status == "ACTIVE").Sum(alarm => alarm.LossTl);
            double verifiedLoss = _orders.Where(order => order.Status == "VERIFIED").Sum(order => order.LossTl);
            double verifiedCo2 = _orders.Where(order => order.Status == "VERIFIED").Sum(order => order.Co2);
            int verifying = _orders.Count(order => order.Status == "VERIFYING");
            return new DashboardDto(
                _machines.Length,
                _alarms.Count(alarm => alarm.Status == "ACTIVE"),
                verifying,
                verifying,
                power.ToString("N1", Turkish) + " kW",
                activeLoss.ToString("N1", Turkish) + " TL/saat",
                verifiedLoss.ToString("N1", Turkish) + " TL/saat",
                verifiedCo2.ToString("N2", Turkish) + " kg/saat",
                _machines.Select(ToMachine).ToArray(),
                BuildAlarms(),
                // Varsayım: doğrulanan kayıp oranı yıl boyu (8760 saat) sürseydi.
                (verifiedLoss * HoursPerYear).ToString("N0", Turkish) + " TL/yıl",
                _machines.Sum(machine => machine.Flow).ToString("N1", Turkish) + " m³/h",
                _totalFlowSeries.ToArray(),
                _machines.Sum(machine => machine.NominalFlow).ToString("N1", Turkish) + " m³/h",
                WaterImpact(verifiedLoss / TlPerKw));
        }
    }

    // Önlenen su (dolaylı): doğrulanan enerji tasarrufunun santral soğutmasında önlediği su.
    private WaterImpactDto WaterImpact(double verifiedKw)
    {
        const string formula = "Önlenen su (m³/yıl) = doğrulanan tasarruf (kWh/yıl) × katsayı (m³/MWh) ÷ 1000";
        if (_waterFactor is null)
        {
            return new WaterImpactDto(false, "—", "—", "Katsayı tanımlı değil", "", "", "", formula, Co2FactorText, Co2SourceText, Co2SourceUrl);
        }

        double kwhPerYear = verifiedKw * HoursPerYear;
        double m3PerYear = kwhPerYear / 1000 * _waterFactor.M3PerMWh;
        return new WaterImpactDto(
            true,
            m3PerYear.ToString(m3PerYear < 100 ? "N1" : "N0", Turkish) + " m³/yıl",
            kwhPerYear.ToString("N0", Turkish) + " kWh/yıl",
            _waterFactor.M3PerMWh.ToString("0.###", Turkish) + " m³/MWh",
            _waterFactor.Scope,
            _waterFactor.Source,
            _waterFactor.SourceUrl,
            formula,
            Co2FactorText,
            Co2SourceText,
            Co2SourceUrl);
    }

    public string? SetFault(int machineId)
    {
        lock (_gate)
        {
            MachineState? machine = Find(machineId);
            if (machine is null)
            {
                return null;
            }

            _faultMachineId = machineId;
            return $"{machine.Name} arızada ({FaultLabel(machine.Name)}). Alarm yaklaşık 6 saniye içinde açılır.";
        }
    }

    public string? ClearFault(int machineId)
    {
        lock (_gate)
        {
            MachineState? machine = Find(machineId);
            if (machine is null)
            {
                return null;
            }

            // Yalnızca bu makinedeki arızayı kapat; başka hattaki demo arızasına dokunma.
            if (_faultMachineId != machineId)
            {
                return $"{machine.Name} zaten normal akışta.";
            }

            _faultMachineId = 0;
            return $"{machine.Name} normal akışa döndü. Hat nominal değerde.";
        }
    }

    public string? ReportMaintenance(int alarmId)
    {
        lock (_gate)
        {
            AlarmState? alarm = _alarms.FirstOrDefault(item => item.Id == alarmId && item.Status == "ACTIVE");
            if (alarm is null)
            {
                return null;
            }

            _orders.Add(new OrderState(_nextOrderId++, alarm.Id, alarm.MachineId, alarm.Type, "VERIFYING", 0, alarm.LossTl, alarm.Co2));
            alarm.Status = "RESOLVED";
            if (_faultMachineId == alarm.MachineId)
            {
                _faultMachineId = 0;
            }
            return "Müdahale başladı. Sonraki 3 normal ölçüm doğrulayacak.";
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(2));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            lock (_gate)
            {
                Tick(DateTime.Now);
            }
        }
    }

    private void Tick(DateTime timestamp)
    {
        double seconds = ++_tick * 2.0;
        foreach (MachineState machine in _machines)
        {
            string mode = Mode(machine);
            double voltage = Math.Max(360, NextGaussian(400, 1.5));
            double current;
            double temperature;
            double powerFactor;
            switch (mode)
            {
                case "asiri_akim":
                    current = machine.NominalCurrent * Next(1.45, 1.60);
                    temperature = NormalTemperature(machine.MaxTemperature);
                    powerFactor = LoadedPowerFactor;
                    break;
                case "atik_isi":
                    current = machine.NominalCurrent * Next(0.75, 0.90);
                    temperature = machine.MaxTemperature + Next(12, 18);
                    powerFactor = LoadedPowerFactor;
                    break;
                case "bosta":
                    current = machine.NominalCurrent * Next(0.18, 0.30);
                    temperature = AmbientTemperature + Next(4, 10);
                    powerFactor = IdlePowerFactor;
                    break;
                default:
                    current = machine.NominalCurrent * Next(0.72, 0.90);
                    temperature = NormalTemperature(machine.MaxTemperature);
                    powerFactor = LoadedPowerFactor;
                    break;
            }

            double power = PhaseFactor * voltage * current * powerFactor / 1000;
            double flow = NextFlow(machine, mode, seconds);
            machine.Voltage = Math.Round(voltage, 2);
            machine.Current = Math.Round(current, 2);
            machine.Temperature = Math.Round(temperature, 2);
            machine.Power = Math.Round(power, 3);
            machine.Flow = Math.Round(flow, 3);
            machine.HasReading = true;
            Remember(machine.VoltageSeries, machine.Voltage);
            Remember(machine.CurrentSeries, machine.Current);
            Remember(machine.TemperatureSeries, machine.Temperature);
            Remember(machine.FlowSeries, machine.Flow);

            TrackOvercurrent(machine, voltage, current, timestamp);
            TrackWasteHeat(machine, temperature, timestamp);
            TrackIdle(machine, voltage, current, timestamp);
            Verify(machine);
        }

        Remember(_totalFlowSeries, Math.Round(_machines.Sum(machine => machine.Flow), 3));
    }

    /// <summary>
    /// Soğutma / proses suyu debisi (m³/h): pompa salınımı (iki frekans) + ölçüm gürültüsü + arıza tepkisi.
    /// Atık ısıda soğutma debisi düşer (sıcaklığın nedeni), aşırı akımda artar, boşta çalışmada makine
    /// üretmese de su akmaya devam eder.
    /// </summary>
    private double NextFlow(MachineState machine, string mode, double seconds)
    {
        double slow = Math.Sin(2 * Math.PI * seconds / machine.FlowPeriod + machine.FlowPhase);
        double pulse = Math.Sin(2 * Math.PI * seconds / 9.0 + machine.FlowPhase * 2);
        double wave = 1 + 0.07 * slow + 0.025 * pulse;
        double response = mode switch
        {
            "atik_isi" => Next(0.42, 0.55),
            "asiri_akim" => Next(1.12, 1.22),
            "bosta" => Next(0.92, 1.0),
            _ => 1.0
        };
        return Math.Max(0, machine.NominalFlow * wave * response * (1 + NextGaussian(0, 0.012)));
    }

    private void TrackOvercurrent(MachineState machine, double voltage, double current, DateTime timestamp)
    {
        const string type = "ASIRI_AKIM";
        double excess = current - machine.NominalCurrent;
        if (excess <= machine.NominalCurrent * 0.20)
        {
            _counts[(machine.Id, type)] = 0;
            return;
        }

        if (Increment(machine.Id, type) < 3)
        {
            return;
        }

        double ratio = excess / machine.NominalCurrent;
        double lossKw = PhaseFactor * voltage * excess * LoadedPowerFactor / 1000;
        UpsertAlarm(machine, type, ratio > 0.40 ? "CRITICAL" : "WARNING", lossKw, timestamp);
    }

    private void TrackWasteHeat(MachineState machine, double temperature, DateTime timestamp)
    {
        const string type = "ATIK_ISI_KAYBI";
        double excess = temperature - machine.MaxTemperature;
        if (excess <= 0)
        {
            _counts[(machine.Id, type)] = 0;
            return;
        }

        if (Increment(machine.Id, type) < 3)
        {
            return;
        }

        double lossKw = HeatTransferCoefficient * machine.SurfaceArea * (temperature - AmbientTemperature) / 1000;
        UpsertAlarm(machine, type, excess > 10 ? "CRITICAL" : "WARNING", lossKw, timestamp);
    }

    private void TrackIdle(MachineState machine, double voltage, double current, DateTime timestamp)
    {
        const string type = "BOSTA_CALISMA";
        double ratio = current / machine.NominalCurrent;
        if (ratio < 0.10 || ratio >= 0.35)
        {
            _counts[(machine.Id, type)] = 0;
            return;
        }

        int count = Increment(machine.Id, type);
        if (count < 3)
        {
            return;
        }

        double lossKw = PhaseFactor * voltage * current * IdlePowerFactor / 1000;
        UpsertAlarm(machine, type, count >= 10 ? "CRITICAL" : "WARNING", lossKw, timestamp);
    }

    private void UpsertAlarm(MachineState machine, string type, string severity, double lossKw, DateTime timestamp)
    {
        AlarmState? existing = _alarms.FirstOrDefault(alarm =>
            alarm.MachineId == machine.Id && alarm.Type == type && alarm.Status == "ACTIVE");
        double loss = lossKw * TlPerKw;
        double co2 = lossKw * Co2PerKw;
        if (existing is not null)
        {
            existing.Severity = severity;
            existing.LossTl = loss;
            existing.Co2 = co2;
            return;
        }

        AlarmState created = new(_nextAlarmId++, machine.Id, type, severity, loss, co2, "ACTIVE", timestamp);
        _alarms.Insert(0, created);
        TrimAlarms();

        NotifyManagers(created, machine);
    }

    // Her cihaz ayrı kaydedilir: aynı yönetici hem masaüstünde hem telefonda açık olabilir.
    public void RegisterDevice(string username, string role, string token)
    {
        lock (_gate)
        {
            UpsertDevice(username, role, token);
        }
    }

    public void RemoveDevice(string token)
    {
        lock (_gate)
        {
            _devices.RemoveAll(device => device.Token == token);
            _notices.RemoveAll(notice => notice.Recipient == token);
        }
    }

    // Bildirimler cihaz jetonuna göre kuyruklanır; bir cihazın okuması diğerinin bildirimini silmez.
    // Sorgu aynı zamanda cihazı yeniden kaydeder, böylece API yeniden başlasa da bildirimler sürer.
    public IReadOnlyList<NoticeDto> Notices(string username, string role, string? deviceToken)
    {
        lock (_gate)
        {
            string recipient = RecipientKey(username, deviceToken);
            if (!string.IsNullOrWhiteSpace(deviceToken))
            {
                UpsertDevice(username, role, deviceToken);
            }

            return _notices
                .Where(notice => notice.Recipient == recipient && !notice.Seen)
                .Select(notice => new NoticeDto(notice.Id, notice.AlarmId, notice.Title, notice.Body))
                .ToArray();
        }
    }

    public void Ack(string username, string? deviceToken, int noticeId)
    {
        lock (_gate)
        {
            string recipient = RecipientKey(username, deviceToken);
            NoticeState? notice = _notices.FirstOrDefault(item => item.Id == noticeId && item.Recipient == recipient);
            if (notice is not null)
            {
                notice.Seen = true;
            }

            _notices.RemoveAll(item => item.Seen && item.Id < _nextNoticeId - 200);
        }
    }

    private void UpsertDevice(string username, string role, string token)
    {
        DeviceState? existing = _devices.FirstOrDefault(device => device.Token == token);
        if (existing is not null && existing.Username == username && existing.Role == role)
        {
            return;
        }

        _devices.RemoveAll(device => device.Token == token);
        _devices.Add(new DeviceState(token, username, role));
    }

    private static string RecipientKey(string username, string? deviceToken) =>
        string.IsNullOrWhiteSpace(deviceToken) ? "user:" + username : deviceToken;

    private void NotifyManagers(AlarmState alarm, MachineState machine)
    {
        string body = $"{TypeLabel(alarm.Type)} · {alarm.LossTl.ToString("N1", Turkish)} TL/saat · {ResponsibleText(machine)}";
        foreach (string recipient in _devices
                     .Where(device => device.Role == "manager" && !string.IsNullOrEmpty(device.Token))
                     .Select(device => device.Token)
                     .Distinct(StringComparer.Ordinal)
                     .ToArray())
        {
            bool alreadyQueued = _notices.Any(notice =>
                notice.Recipient == recipient && notice.AlarmId == alarm.Id && !notice.Seen);
            if (alreadyQueued)
            {
                continue;
            }

            _notices.Add(new NoticeState(_nextNoticeId++, recipient, alarm.Id, machine.Name, body));
        }
    }

    // En eski kapanmış alarmlardan başlayarak siler; aktif alarmlar ve
    // doğrulaması süren iş emirlerinin alarmları listede kalır.
    private void TrimAlarms()
    {
        for (int index = _alarms.Count - 1; index >= 0 && _alarms.Count > 40; index--)
        {
            AlarmState candidate = _alarms[index];
            bool inUse = candidate.Status == "ACTIVE"
                || _orders.Any(order => order.AlarmId == candidate.Id && order.Status == "VERIFYING");
            if (!inUse)
            {
                _alarms.RemoveAt(index);
            }
        }
    }

    private static void Remember(List<double> series, double value)
    {
        series.Add(value);
        if (series.Count > 40)
        {
            series.RemoveAt(0);
        }
    }

    private void Verify(MachineState machine)
    {
        foreach (OrderState order in _orders.Where(order => order.MachineId == machine.Id && order.Status == "VERIFYING"))
        {
            bool normal = order.Type switch
            {
                "ASIRI_AKIM" => machine.Current <= machine.NominalCurrent * 1.20,
                "ATIK_ISI_KAYBI" => machine.Temperature <= machine.MaxTemperature,
                "BOSTA_CALISMA" => machine.Current / machine.NominalCurrent < 0.10
                    || machine.Current / machine.NominalCurrent >= 0.35,
                _ => false
            };
            order.Count = normal ? order.Count + 1 : 0;
            if (order.Count >= 3)
            {
                order.Status = "VERIFIED";
                order.Count = 3;
            }
        }
    }

    private IReadOnlyList<AlarmDto> BuildAlarms()
    {
        var rows = new List<AlarmDto>();
        foreach (AlarmState alarm in _alarms.Where(alarm => alarm.Status == "ACTIVE"))
        {
            rows.Add(ToAlarm(alarm, "ACTIVE", alarm.Severity == "CRITICAL" ? "Kritik" : "Uyarı", ""));
        }

        foreach (OrderState order in _orders.Where(order => order.Status == "VERIFYING"))
        {
            AlarmState? alarm = _alarms.FirstOrDefault(item => item.Id == order.AlarmId);
            if (alarm is null)
            {
                continue;
            }

            rows.Add(ToAlarm(alarm, "VERIFYING", "Doğrulanıyor", $"Doğrulama {order.Count}/3"));
        }

        foreach (OrderState order in _orders
                     .Where(order => order.Status == "VERIFIED")
                     .OrderByDescending(order => order.Id)
                     .Take(8))
        {
            AlarmState? alarm = _alarms.FirstOrDefault(item => item.Id == order.AlarmId);
            if (alarm is null)
            {
                continue;
            }

            rows.Add(ToAlarm(alarm, "VERIFIED", "Doğrulandı", "3 ardışık normal ölçüm"));
        }

        return rows;
    }

    private AlarmDto ToAlarm(AlarmState alarm, string status, string severityLabel, string extra)
    {
        MachineState machine = Find(alarm.MachineId)!;
        string meta = $"{ResponsibleText(machine)} · {machine.Location} · {alarm.Co2.ToString("N2", Turkish)} kg CO₂/saat · {alarm.Created:HH:mm:ss}";
        if (extra.Length > 0)
        {
            meta = extra + " · " + meta;
        }

        return new AlarmDto(
            alarm.Id,
            alarm.MachineId,
            machine.Name,
            TypeLabel(alarm.Type),
            severityLabel,
            status,
            alarm.LossTl.ToString("N1", Turkish) + " TL/saat",
            meta);
    }

    private MachineDto ToMachine(MachineState machine)
    {
        string dash = "—";
        PersonnelState? assignee = machine.PersonnelId is int personnelId
            ? _personnel.FirstOrDefault(person => person.Id == personnelId)
            : null;
        string assigneeName = assignee?.FullName ?? "";
        bool mismatch = assignee is not null && assignee.Expertise != machine.Domain;
        string meta = $"{machine.NominalCurrent.ToString("0", Turkish)} A nominal · {machine.MaxTemperature.ToString("0", Turkish)} °C eşik · "
            + (assignee is null ? "Personel atanmadı" : assignee.FullName + (mismatch ? " · uzmanlık uyuşmuyor" : ""));
        return new MachineDto(
            machine.Id,
            machine.Name,
            machine.Location,
            meta,
            _faultMachineId == machine.Id,
            machine.HasReading ? machine.Voltage.ToString("N1", Turkish) + " V" : dash,
            machine.HasReading ? machine.Current.ToString("N1", Turkish) + " A" : dash,
            machine.HasReading ? machine.Temperature.ToString("N1", Turkish) + " °C" : dash,
            machine.HasReading ? machine.Power.ToString("N1", Turkish) + " kW" : dash,
            machine.HasReading ? machine.Flow.ToString("N2", Turkish) + " m³/h" : dash,
            machine.VoltageSeries.ToArray(),
            machine.CurrentSeries.ToArray(),
            machine.TemperatureSeries.ToArray(),
            machine.FlowSeries.ToArray(),
            machine.NominalFlow.ToString("N1", Turkish) + " m³/h",
            machine.Domain,
            DomainLabel(machine.Domain),
            machine.PersonnelId,
            assigneeName,
            mismatch);
    }

    // Alarmın kime düştüğünü gösterir; atama yoksa yöneticiyi atama yapmaya yönlendirir.
    private string ResponsibleText(MachineState machine)
    {
        PersonnelState? assignee = machine.PersonnelId is int personnelId
            ? _personnel.FirstOrDefault(person => person.Id == personnelId)
            : null;
        return assignee is null ? "Sorumlu atanmadı" : "Sorumlu: " + assignee.FullName;
    }

    private static string DomainLabel(string domain) => domain switch
    {
        "ELEKTRIK" => "Aşırı akım ve elektrik hatları",
        "ISI" => "Atık ısı ve izolasyon",
        "URETIM" => "Boşta çalışma ve üretim hatları",
        _ => "Tanımsız alan"
    };

    private MachineState? Find(int id) => _machines.FirstOrDefault(machine => machine.Id == id);

    private string Mode(MachineState machine)
    {
        if (_faultMachineId != machine.Id)
        {
            return "normal";
        }

        return FaultLabel(machine.Name) switch
        {
            "boşta çalışma" => "bosta",
            "atık ısı" => "atik_isi",
            _ => "asiri_akim"
        };
    }

    private static string FaultLabel(string name) => name switch
    {
        "Enjeksiyon Makinesi 2" or "CNC İşleme Merkezi" => "boşta çalışma",
        "Fırın Konveyörü" or "Soğutma Pompası" => "atık ısı",
        _ => "aşırı akım"
    };

    private static string TypeLabel(string type) => type switch
    {
        "ASIRI_AKIM" => "Aşırı akım",
        "ATIK_ISI_KAYBI" => "Atık ısı",
        "BOSTA_CALISMA" => "Boşta çalışma",
        _ => type
    };

    private int Increment(int machineId, string type)
    {
        var key = (machineId, type);
        int count = _counts.GetValueOrDefault(key) + 1;
        _counts[key] = count;
        return count;
    }

    private double NormalTemperature(double maximum)
    {
        double span = Math.Max(maximum - AmbientTemperature, 1);
        return Math.Min(AmbientTemperature + span * Next(0.45, 0.68), maximum - 3);
    }

    private double Next(double minimum, double maximum) => minimum + _random.NextDouble() * (maximum - minimum);

    private double NextGaussian(double mean, double standardDeviation)
    {
        double first = 1 - _random.NextDouble();
        double second = 1 - _random.NextDouble();
        double standardNormal = Math.Sqrt(-2 * Math.Log(first)) * Math.Sin(2 * Math.PI * second);
        return mean + standardNormal * standardDeviation;
    }

    private sealed class MachineState(
        int id,
        string name,
        string location,
        double nominalCurrent,
        double maxTemperature,
        double surfaceArea,
        string domain)
    {
        public int Id { get; } = id;
        public string Name { get; } = name;
        public string Location { get; } = location;
        public double NominalCurrent { get; } = nominalCurrent;
        public double MaxTemperature { get; } = maxTemperature;
        public double SurfaceArea { get; } = surfaceArea;
        public string Domain { get; } = domain;
        public int? PersonnelId { get; set; }
        public double Voltage { get; set; }
        public double Current { get; set; }
        public double Temperature { get; set; }
        public double Power { get; set; }
        public bool HasReading { get; set; }
        public List<double> VoltageSeries { get; } = new();
        public List<double> CurrentSeries { get; } = new();
        public List<double> TemperatureSeries { get; } = new();
        public double NominalFlow { get; init; }
        public double FlowPeriod { get; init; } = 30;
        public double FlowPhase { get; init; }
        public double Flow { get; set; }
        public List<double> FlowSeries { get; } = new();
    }

    private sealed class PersonnelState(int id, string fullName, string expertise, string expertiseLabel)
    {
        public int Id { get; } = id;
        public string FullName { get; } = fullName;
        public string Expertise { get; } = expertise;
        public string ExpertiseLabel { get; } = expertiseLabel;
    }

    private sealed class AlarmState(
        int id,
        int machineId,
        string type,
        string severity,
        double lossTl,
        double co2,
        string status,
        DateTime created)
    {
        public int Id { get; } = id;
        public int MachineId { get; } = machineId;
        public string Type { get; } = type;
        public string Severity { get; set; } = severity;
        public double LossTl { get; set; } = lossTl;
        public double Co2 { get; set; } = co2;
        public string Status { get; set; } = status;
        public DateTime Created { get; } = created;
    }

    private sealed class OrderState(
        int id,
        int alarmId,
        int machineId,
        string type,
        string status,
        int count,
        double lossTl,
        double co2)
    {
        public int Id { get; } = id;
        public int AlarmId { get; } = alarmId;
        public int MachineId { get; } = machineId;
        public string Type { get; } = type;
        public string Status { get; set; } = status;
        public int Count { get; set; } = count;
        public double LossTl { get; } = lossTl;
        public double Co2 { get; } = co2;
    }

    private sealed class DeviceState(string token, string username, string role)
    {
        public string Token { get; } = token;
        public string Username { get; } = username;
        public string Role { get; } = role;
    }

    private sealed class NoticeState(int id, string recipient, int alarmId, string title, string body)
    {
        public int Id { get; } = id;
        public string Recipient { get; } = recipient;
        public int AlarmId { get; } = alarmId;
        public string Title { get; } = title;
        public string Body { get; } = body;
        public bool Seen { get; set; }
    }
}

public sealed record MachineDto(
    int Id,
    string Name,
    string Location,
    string Meta,
    bool FaultActive,
    string VoltageText,
    string CurrentText,
    string TemperatureText,
    string PowerText,
    string FlowText,
    IReadOnlyList<double> VoltageSeries,
    IReadOnlyList<double> CurrentSeries,
    IReadOnlyList<double> TemperatureSeries,
    IReadOnlyList<double> FlowSeries,
    string NominalFlowText,
    string Domain,
    string DomainLabel,
    int? PersonnelId,
    string AssigneeName,
    bool ExpertiseMismatch);

public sealed record PersonnelDto(int Id, string FullName, string Expertise, string ExpertiseLabel);

public sealed record AssignmentResultDto(bool Saved, bool ExpertiseMismatch, string Message);

public sealed record AlarmDto(
    int Id,
    int MachineId,
    string MachineName,
    string TypeLabel,
    string SeverityLabel,
    string Status,
    string LossText,
    string MetaText);

public sealed record DashboardDto(
    int MachineCount,
    int ActiveAlarms,
    int OpenWorkOrders,
    int VerifyingWorkOrders,
    string TotalPowerText,
    string ActiveLossText,
    string VerifiedSavingsText,
    string VerifiedCo2Text,
    IReadOnlyList<MachineDto> Machines,
    IReadOnlyList<AlarmDto> Alarms,
    string VerifiedAnnualText,
    string TotalFlowText,
    IReadOnlyList<double> TotalFlowSeries,
    string NominalFlowText,
    WaterImpactDto Water);

public sealed record WaterFactor(double M3PerMWh, string Scope, string Source, string SourceUrl);

public sealed record WaterImpactDto(
    bool Configured,
    string AvoidedText,
    string AvoidedKwhText,
    string FactorText,
    string ScopeText,
    string SourceText,
    string SourceUrl,
    string FormulaText,
    string Co2FactorText,
    string Co2SourceText,
    string Co2SourceUrl);

public sealed record MessageDto(string Message);

public sealed record NoticeDto(int Id, int AlarmId, string Title, string Body);

public sealed record DeviceRequest(string Token);
