using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
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
    private bool _awaitingMaintenanceVerification;
    private bool _stackBody;
    private bool _stackHeader;
    private int _kpiColumns = 5;
    private string _scenarioText = "Normal akış. Hatlar nominal değerde.";

    public MainWindow()
    {
        InitializeComponent();
        _repository = DashboardRepository.Open();
        _simulator = new SimulatorService(_repository);
        FitToWorkArea();
        SizeChanged += (_, _) => UpdateResponsiveLayout();
        MachineList.PreviewMouseWheel += ForwardWheelWhenStacked;
        AlarmList.PreviewMouseWheel += ForwardWheelWhenStacked;
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

    private void UpdateResponsiveLayout()
    {
        double width = ActualWidth;
        if (width <= 0)
        {
            return;
        }

        bool stackBody = width < 960;
        bool stackHeader = stackBody;
        int kpiColumns = width >= 960 ? 5 : width >= 520 ? 2 : 1;
        bool tight = width < 520;

        RootScroll.VerticalScrollBarVisibility = stackBody
            ? ScrollBarVisibility.Auto
            : ScrollBarVisibility.Disabled;
        RootScroll.PanningMode = stackBody ? PanningMode.VerticalOnly : PanningMode.None;
        RootGrid.Margin = tight ? new Thickness(12) : stackBody ? new Thickness(16) : new Thickness(22);
        RootGrid.RowDefinitions[2].Height = stackBody ? GridLength.Auto : new GridLength(1, GridUnitType.Star);

        Thickness buttonPad = stackBody ? new Thickness(16, 11, 16, 11) : new Thickness(14, 7, 14, 7);
        NormalButton.Padding = buttonPad;
        FaultButton.Padding = buttonPad;
        MaintenanceButton.Padding = buttonPad;

        if (stackHeader != _stackHeader)
        {
            _stackHeader = stackHeader;
            ApplyHeaderLayout(stackHeader);
        }

        if (kpiColumns != _kpiColumns)
        {
            _kpiColumns = kpiColumns;
            ApplyKpiLayout(kpiColumns);
        }

        if (stackBody != _stackBody)
        {
            _stackBody = stackBody;
            ApplyBodyLayout(stackBody);
        }
    }

    private void ApplyHeaderLayout(bool stacked)
    {
        if (stacked)
        {
            Grid.SetRow(HeaderActions, 1);
            Grid.SetColumn(HeaderActions, 0);
            Grid.SetColumnSpan(TitleBlock, 2);
            Grid.SetColumnSpan(HeaderActions, 2);
            HeaderActions.Margin = new Thickness(0, 12, 0, 0);
            HeaderActions.HorizontalAlignment = HorizontalAlignment.Left;
            return;
        }

        Grid.SetRow(HeaderActions, 0);
        Grid.SetColumn(HeaderActions, 1);
        Grid.SetColumnSpan(TitleBlock, 1);
        Grid.SetColumnSpan(HeaderActions, 1);
        HeaderActions.Margin = new Thickness(16, 0, 0, 0);
        HeaderActions.HorizontalAlignment = HorizontalAlignment.Stretch;
    }

    private void ApplyKpiLayout(int columns)
    {
        Border[] cards = [KpiMachines, KpiPower, KpiCo2, KpiSavings, KpiLoss];
        KpiGrid.ColumnDefinitions.Clear();
        KpiGrid.RowDefinitions.Clear();

        if (columns >= cards.Length)
        {
            for (int index = 0; index < cards.Length; index++)
            {
                KpiGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                Grid.SetRow(cards[index], 0);
                Grid.SetColumn(cards[index], index);
                Grid.SetColumnSpan(cards[index], 1);
                cards[index].Margin = index == cards.Length - 1 ? new Thickness(0) : new Thickness(0, 0, 10, 0);
            }

            return;
        }

        if (columns == 1)
        {
            KpiGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int index = 0; index < cards.Length; index++)
            {
                KpiGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                Grid.SetRow(cards[index], index);
                Grid.SetColumn(cards[index], 0);
                Grid.SetColumnSpan(cards[index], 1);
                cards[index].Margin = index == cards.Length - 1 ? new Thickness(0) : new Thickness(0, 0, 0, 10);
            }

            return;
        }

        KpiGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        KpiGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (int index = 0; index < cards.Length - 1; index++)
        {
            if (index % 2 == 0)
            {
                KpiGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }

            Grid.SetRow(cards[index], index / 2);
            Grid.SetColumn(cards[index], index % 2);
            Grid.SetColumnSpan(cards[index], 1);
            cards[index].Margin = new Thickness(0, 0, index % 2 == 0 ? 10 : 0, 10);
        }

        KpiGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(cards[^1], 2);
        Grid.SetColumn(cards[^1], 0);
        Grid.SetColumnSpan(cards[^1], 2);
        cards[^1].Margin = new Thickness(0);
    }

    private void ApplyBodyLayout(bool stacked)
    {
        BodyGrid.ColumnDefinitions.Clear();
        BodyGrid.RowDefinitions.Clear();

        if (stacked)
        {
            BodyGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            BodyGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BodyGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BodyGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid.SetRow(MachinePanel, 0);
            Grid.SetColumn(MachinePanel, 0);
            Grid.SetRow(ChartPanel, 1);
            Grid.SetColumn(ChartPanel, 0);
            Grid.SetRow(AlarmPanel, 2);
            Grid.SetColumn(AlarmPanel, 0);

            MachinePanel.Margin = new Thickness(0, 0, 0, 12);
            ChartPanel.Margin = new Thickness(0, 0, 0, 12);
            AlarmPanel.Margin = new Thickness(0);
            MachinePanel.MinHeight = 220;
            AlarmPanel.MinHeight = 240;
            VoltageChart.MinHeight = 120;
            CurrentChart.MinHeight = 120;
            TemperatureChart.MinHeight = 120;
            ScrollViewer.SetVerticalScrollBarVisibility(MachineList, ScrollBarVisibility.Disabled);
            ScrollViewer.SetVerticalScrollBarVisibility(AlarmList, ScrollBarVisibility.Disabled);
            return;
        }

        BodyGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.15, GridUnitType.Star), MinWidth = 200 });
        BodyGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2.5, GridUnitType.Star), MinWidth = 280 });
        BodyGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.45, GridUnitType.Star), MinWidth = 240 });
        BodyGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        Grid.SetRow(MachinePanel, 0);
        Grid.SetColumn(MachinePanel, 0);
        Grid.SetRow(ChartPanel, 0);
        Grid.SetColumn(ChartPanel, 1);
        Grid.SetRow(AlarmPanel, 0);
        Grid.SetColumn(AlarmPanel, 2);

        MachinePanel.Margin = new Thickness(0, 0, 12, 0);
        ChartPanel.Margin = new Thickness(0, 0, 12, 0);
        AlarmPanel.Margin = new Thickness(0);
        MachinePanel.MinHeight = 0;
        AlarmPanel.MinHeight = 0;
        VoltageChart.MinHeight = 80;
        CurrentChart.MinHeight = 80;
        TemperatureChart.MinHeight = 80;
        MachineList.ClearValue(ScrollViewer.VerticalScrollBarVisibilityProperty);
        AlarmList.ClearValue(ScrollViewer.VerticalScrollBarVisibilityProperty);
    }

    private void ForwardWheelWhenStacked(object sender, MouseWheelEventArgs e)
    {
        if (!_stackBody)
        {
            return;
        }

        e.Handled = true;
        var forwarded = new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta)
        {
            RoutedEvent = MouseWheelEvent,
            Source = sender
        };
        RootScroll.RaiseEvent(forwarded);
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
            _scenarioText = _stackBody
                ? "Önce listeden bir makine seçin."
                : "Önce soldan bir makine seçin.";
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
        try
        {
            bool started = await Task.Run(() => _repository.ReportMaintenance(alarm.AnomalyId, alarm.MachineId));
            if (!started)
            {
                _scenarioText = "Alarm artık aktif değil; bakım doğrulaması başlatılmadı.";
                await RefreshAsync();
                return;
            }

            _simulator.ClearFault();
            _awaitingMaintenanceVerification = true;
            _scenarioText = "Müdahale başladı. Sonraki 3 normal ölçüm doğrulayacak.";
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
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(0x27, 0xAE, 0x60));
            StatusText.Text = "Yerel veriler kayıtlı  ·  " + _scenarioText;
        }
        catch (Exception ex)
        {
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B));
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
            LiveDot.Fill = new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B));
            StatusText.Text = "Simülasyon hatası: " + ex.Message;
        }
    }

    private void Apply(Snapshot snapshot, int? machineId, int? alarmId)
    {
        _loading = true;
        MachineCountText.Text = snapshot.MachineCount.ToString(Turkish);
        PowerText.Text = snapshot.TotalPowerKw.ToString("N1", Turkish) + " kW";
        Co2Text.Text = snapshot.VerifiedCo2KgPerHour.ToString("N2", Turkish) + " kg/saat";
        VerifiedSavingsText.Text = snapshot.VerifiedSavingsTlPerHour.ToString("N1", Turkish) + " TL/saat";
        LossText.Text = snapshot.ActiveLossTlPerHour.ToString("N1", Turkish) + " TL/saat";
        DailyLossText.Text = "Günlük tahmin " + (snapshot.ActiveLossTlPerHour * 24).ToString("N0", Turkish) + " TL";
        WorkOrderText.Text = $"Açık iş emri: {snapshot.OpenWorkOrders.ToString(Turkish)}"
            + $" · Doğrulama: {snapshot.VerifyingWorkOrders.ToString(Turkish)}";
        if (_awaitingMaintenanceVerification && snapshot.VerifyingWorkOrders == 0)
        {
            _awaitingMaintenanceVerification = false;
            _scenarioText = "Müdahale doğrulandı: 3 ardışık normal ölçüm.";
        }
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
