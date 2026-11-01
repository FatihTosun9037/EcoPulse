using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace EcoPulse.Dashboard;

public partial class MainWindow : Window
{
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");
    private readonly DashboardRepository _repository;
    private readonly SimulatorService _simulator;
    private readonly DispatcherTimer _timer;
    private int _busy;
    private bool _loading;
    private string _scenarioText = "Normal akış. Hatlar nominal değerde.";

    public MainWindow()
    {
        InitializeComponent();
        _repository = DashboardRepository.Open();
        _simulator = new SimulatorService(_repository);
        FitToWorkArea();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += async (_, _) => await TimerTickAsync();
        Loaded += async (_, _) =>
        {
            await Task.Run(_simulator.Tick);
            await RefreshAsync();
            _timer.Start();
        };
    }

    private void FitToWorkArea()
    {
        Rect area = SystemParameters.WorkArea;
        Width = Math.Min(Width, area.Width - 24);
        Height = Math.Min(Height, area.Height - 24);
        Left = area.Left + Math.Max(0, (area.Width - Width) / 2);
        Top = area.Top + Math.Max(0, (area.Height - Height) / 2);
    }

    private async void MachineList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        await RefreshAsync();
    }

    private void AlarmList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        MaintenanceButton.IsEnabled = AlarmList.SelectedItem is AlarmRow { Status: "ACTIVE" };
    }

    private void NormalButton_Click(object sender, RoutedEventArgs e)
    {
        _simulator.ClearFault();
        _scenarioText = "Normal akış. Hatlar nominal değerde.";
        StatusText.Text = _scenarioText;
    }

    private void FaultButton_Click(object sender, RoutedEventArgs e)
    {
        if (MachineList.SelectedItem is not MachineRow selected)
        {
            _scenarioText = "Önce soldan bir makine seçin.";
            StatusText.Text = _scenarioText;
            return;
        }

        _simulator.SetFault(selected.MachineId);
        _scenarioText = $"{selected.Name} arızada ({FaultLabel(selected.Name)}). Alarm yaklaşık 6 saniye içinde açılır.";
        StatusText.Text = _scenarioText;
    }

    private async void MaintenanceButton_Click(object sender, RoutedEventArgs e)
    {
        if (AlarmList.SelectedItem is not AlarmRow alarm || alarm.Status != "ACTIVE")
        {
            return;
        }

        MaintenanceButton.IsEnabled = false;
        _simulator.ClearFault();
        _scenarioText = "Bakım bildirildi. Seçili hat normale döndü.";
        try
        {
            await Task.Run(() => _repository.ReportMaintenance(alarm.AnomalyId, alarm.MachineId));
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Bakım bildirimi yazılamadı: " + ex.Message;
        }
    }

    private static string FaultLabel(string machineName) => machineName switch
    {
        "Enjeksiyon Makinesi 2" or "CNC İşleme Merkezi" => "boşta çalışma",
        "Fırın Konveyörü" or "Soğutma Pompası" => "atık ısı",
        _ => "aşırı akım"
    };

    private async Task RefreshAsync()
    {
        if (Interlocked.Exchange(ref _busy, 1) == 1)
        {
            return;
        }

        int? machineId = (MachineList.SelectedItem as MachineRow)?.MachineId;
        int? alarmId = (AlarmList.SelectedItem as AlarmRow)?.AnomalyId;
        try
        {
            Snapshot snapshot = await Task.Run(() => _repository.Load(machineId));
            Apply(snapshot, machineId, alarmId);
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(61, 220, 151));
            StatusText.Text = "Yerel veriler kayıtlı  ·  " + _scenarioText;
        }
        catch (Exception ex)
        {
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(255, 106, 106));
            StatusText.Text = "Yerel veriler okunamadı: " + ex.Message;
        }
        finally
        {
            Interlocked.Exchange(ref _busy, 0);
        }
    }

    private async Task TimerTickAsync()
    {
        try
        {
            await Task.Run(_simulator.Tick);
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(255, 106, 106));
            StatusText.Text = "Simülasyon hatası: " + ex.Message;
        }
    }

    private void Apply(Snapshot snapshot, int? machineId, int? alarmId)
    {
        _loading = true;
        MachineCountText.Text = snapshot.MachineCount.ToString(Turkish);
        PowerText.Text = snapshot.TotalPowerKw.ToString("N1", Turkish) + " kW";
        Co2Text.Text = snapshot.PreventedCo2Kg.ToString("N2", Turkish) + " kg";
        LossText.Text = snapshot.ActiveLossTlPerHour.ToString("N1", Turkish) + " TL/saat";
        DailyLossText.Text = "Günlük tahmin " + (snapshot.ActiveLossTlPerHour * 24).ToString("N0", Turkish) + " TL";
        WorkOrderText.Text = "Açık iş emri: " + snapshot.OpenWorkOrders.ToString(Turkish);
        ClockText.Text = DateTime.Now.ToString("HH:mm:ss", Turkish);

        MachineList.ItemsSource = snapshot.Machines;
        MachineRow? selectedMachine = snapshot.Machines.FirstOrDefault(row => row.MachineId == machineId)
            ?? snapshot.Machines.FirstOrDefault();
        MachineList.SelectedItem = selectedMachine;
        ChartTitleText.Text = selectedMachine is null ? "Telemetri" : selectedMachine.Name;

        AlarmList.ItemsSource = snapshot.Alarms;
        AlarmList.SelectedItem = snapshot.Alarms.FirstOrDefault(row => row.AnomalyId == alarmId);
        EmptyAlarmText.Visibility = snapshot.Alarms.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        MaintenanceButton.IsEnabled = AlarmList.SelectedItem is AlarmRow { Status: "ACTIVE" };

        VoltageChart.SetValues(snapshot.Series.Select(point => point.Voltage).ToArray());
        CurrentChart.SetValues(snapshot.Series.Select(point => point.Current).ToArray());
        TemperatureChart.SetValues(snapshot.Series.Select(point => point.Temperature).ToArray());

        TelemetryPoint? last = snapshot.Series.LastOrDefault();
        VoltageValueText.Text = last is null ? "—" : last.Voltage.ToString("N1", Turkish) + " V";
        CurrentValueText.Text = last is null ? "—" : last.Current.ToString("N1", Turkish) + " A";
        TemperatureValueText.Text = last is null ? "—" : last.Temperature.ToString("N1", Turkish) + " °C";
        _loading = false;
    }
}
