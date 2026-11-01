using System.Globalization;
using System.IO;
using System.Windows.Media;
using Microsoft.Data.Sqlite;

namespace EcoPulse.Dashboard;

public sealed class MachineRow
{
    public int MachineId { get; init; }
    public string Name { get; init; } = "";
    public string Location { get; init; } = "";
    public string Meta { get; init; } = "";
}

public sealed class AlarmRow
{
    public int AnomalyId { get; init; }
    public int MachineId { get; init; }
    public string MachineName { get; init; } = "";
    public string TypeLabel { get; init; } = "";
    public string SeverityLabel { get; init; } = "";
    public string LossText { get; init; } = "";
    public string MetaText { get; init; } = "";
    public string Status { get; init; } = "";
    public Brush BadgeBrush { get; init; } = Brushes.Gray;
    public Brush BadgeSoftBrush { get; init; } = Brushes.Transparent;
}

public sealed class TelemetryPoint
{
    public DateTime Timestamp { get; init; }
    public double Voltage { get; init; }
    public double Current { get; init; }
    public double Temperature { get; init; }
}

public sealed class Snapshot
{
    public int MachineCount { get; init; }
    public double TotalPowerKw { get; init; }
    public double PreventedCo2Kg { get; init; }
    public double ActiveLossTlPerHour { get; init; }
    public int OpenWorkOrders { get; init; }
    public List<MachineRow> Machines { get; init; } = new();
    public List<AlarmRow> Alarms { get; init; } = new();
    public List<TelemetryPoint> Series { get; init; } = new();
}

internal sealed record SimulationMachine(
    int Id,
    string Name,
    string Location,
    double NominalCurrent,
    double MaxTemperature,
    double SurfaceArea);

internal sealed record SimulationReading(
    int MachineId,
    double Voltage,
    double Current,
    double Temperature,
    double Power,
    DateTime Timestamp);

internal sealed record SimulationAnomaly(
    int MachineId,
    string Type,
    string Severity,
    double LossKw,
    DateTime Timestamp);

public sealed class DashboardRepository
{
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");
    private readonly string _connectionString;

    private DashboardRepository(string databasePath)
    {
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            ForeignKeys = true,
            Pooling = true
        }.ToString();
    }

    public static DashboardRepository Open()
    {
        string directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "EcoPulse");
        Directory.CreateDirectory(directory);

        var repository = new DashboardRepository(Path.Combine(directory, "ecopulse.db"));
        repository.Initialize();
        return repository;
    }

    public Snapshot Load(int? machineId)
    {
        using var connection = OpenConnection();
        List<MachineRow> machines = LoadMachines(connection);
        int? selected = machineId ?? machines.FirstOrDefault()?.MachineId;
        return new Snapshot
        {
            MachineCount = ScalarInt(connection, "SELECT COUNT(*) FROM machines"),
            TotalPowerKw = ScalarDouble(connection, """
                SELECT COALESCE(SUM(t.active_power_kw), 0)
                FROM telemetry_data t
                INNER JOIN (
                    SELECT machine_id, MAX(data_id) AS data_id
                    FROM telemetry_data
                    GROUP BY machine_id
                ) latest ON latest.data_id = t.data_id
                """),
            PreventedCo2Kg = ScalarDouble(connection, """
                SELECT COALESCE(SUM(co2_impact_kg), 0)
                FROM anomalies
                WHERE status = 'RESOLVED'
                """),
            ActiveLossTlPerHour = ScalarDouble(connection, """
                SELECT COALESCE(SUM(financial_loss_tl), 0)
                FROM anomalies
                WHERE status = 'ACTIVE'
                """),
            OpenWorkOrders = ScalarInt(connection, "SELECT COUNT(*) FROM work_orders WHERE status = 'OPEN'"),
            Machines = machines,
            Alarms = LoadAlarms(connection),
            Series = selected is int id ? LoadSeries(connection, id) : new List<TelemetryPoint>()
        };
    }

    public void ReportMaintenance(int anomalyId, int machineId)
    {
        using var connection = OpenConnection();
        using var transaction = connection.BeginTransaction();
        using var statusCommand = new SqliteCommand(
            "SELECT status FROM anomalies WHERE anomaly_id = @id",
            connection,
            transaction);
        statusCommand.Parameters.AddWithValue("@id", anomalyId);
        if (statusCommand.ExecuteScalar() as string != "ACTIVE")
        {
            transaction.Commit();
            return;
        }

        using var insert = new SqliteCommand("""
            INSERT INTO work_orders (anomaly_id, machine_id, note, status)
            VALUES (@anomaly, @machine, 'Panelden bakım bildirimi', 'OPEN')
            """, connection, transaction);
        insert.Parameters.AddWithValue("@anomaly", anomalyId);
        insert.Parameters.AddWithValue("@machine", machineId);
        insert.ExecuteNonQuery();

        using var update = new SqliteCommand(
            "UPDATE anomalies SET status = 'RESOLVED' WHERE anomaly_id = @id",
            connection,
            transaction);
        update.Parameters.AddWithValue("@id", anomalyId);
        update.ExecuteNonQuery();
        transaction.Commit();
    }

    internal List<SimulationMachine> GetSimulationMachines()
    {
        using var connection = OpenConnection();
        using var command = new SqliteCommand("""
            SELECT machine_id, machine_name, location, nominal_current, max_temperature, surface_area_m2
            FROM machines
            ORDER BY machine_id
            """, connection);
        using var reader = command.ExecuteReader();
        var machines = new List<SimulationMachine>();
        while (reader.Read())
        {
            machines.Add(new SimulationMachine(
                reader.GetInt32(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? "" : reader.GetString(2),
                reader.GetDouble(3),
                reader.GetDouble(4),
                reader.GetDouble(5)));
        }

        return machines;
    }

    internal void SaveSimulationTick(
        IReadOnlyList<SimulationReading> readings,
        IReadOnlyList<SimulationAnomaly> anomalies)
    {
        using var connection = OpenConnection();
        using var transaction = connection.BeginTransaction();

        foreach (SimulationReading reading in readings)
        {
            using var command = new SqliteCommand("""
                INSERT INTO telemetry_data
                    (machine_id, voltage, current_amp, temperature, active_power_kw, timestamp)
                VALUES (@machine, @voltage, @current, @temperature, @power, @timestamp)
                """, connection, transaction);
            command.Parameters.AddWithValue("@machine", reading.MachineId);
            command.Parameters.AddWithValue("@voltage", reading.Voltage);
            command.Parameters.AddWithValue("@current", reading.Current);
            command.Parameters.AddWithValue("@temperature", reading.Temperature);
            command.Parameters.AddWithValue("@power", reading.Power);
            command.Parameters.AddWithValue("@timestamp", FormatTimestamp(reading.Timestamp));
            command.ExecuteNonQuery();
        }

        foreach (SimulationAnomaly anomaly in anomalies)
        {
            using var find = new SqliteCommand("""
                SELECT anomaly_id FROM anomalies
                WHERE machine_id = @machine AND anomaly_type = @type AND status = 'ACTIVE'
                ORDER BY anomaly_id DESC LIMIT 1
                """, connection, transaction);
            find.Parameters.AddWithValue("@machine", anomaly.MachineId);
            find.Parameters.AddWithValue("@type", anomaly.Type);
            object? existing = find.ExecuteScalar();

            if (existing is not null)
            {
                using var update = new SqliteCommand("""
                    UPDATE anomalies
                    SET severity = @severity, financial_loss_tl = @loss, co2_impact_kg = @co2
                    WHERE anomaly_id = @id
                    """, connection, transaction);
                update.Parameters.AddWithValue("@severity", anomaly.Severity);
                update.Parameters.AddWithValue("@loss", anomaly.LossKw * 4.092);
                update.Parameters.AddWithValue("@co2", anomaly.LossKw * 0.436);
                update.Parameters.AddWithValue("@id", (long)existing);
                update.ExecuteNonQuery();
            }
            else
            {
                using var insert = new SqliteCommand("""
                    INSERT INTO anomalies
                        (machine_id, anomaly_type, severity, financial_loss_tl,
                         co2_impact_kg, status, created_at)
                    VALUES (@machine, @type, @severity, @loss, @co2, 'ACTIVE', @created)
                    """, connection, transaction);
                insert.Parameters.AddWithValue("@machine", anomaly.MachineId);
                insert.Parameters.AddWithValue("@type", anomaly.Type);
                insert.Parameters.AddWithValue("@severity", anomaly.Severity);
                insert.Parameters.AddWithValue("@loss", anomaly.LossKw * 4.092);
                insert.Parameters.AddWithValue("@co2", anomaly.LossKw * 0.436);
                insert.Parameters.AddWithValue("@created", FormatTimestamp(anomaly.Timestamp));
                insert.ExecuteNonQuery();
            }
        }

        transaction.Commit();
    }

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        return connection;
    }

    private void Initialize()
    {
        using var connection = OpenConnection();
        using (var schema = new SqliteCommand("""
            CREATE TABLE IF NOT EXISTS machines (
                machine_id INTEGER PRIMARY KEY AUTOINCREMENT,
                machine_name TEXT NOT NULL,
                location TEXT,
                nominal_current REAL NOT NULL,
                max_temperature REAL NOT NULL,
                surface_area_m2 REAL NOT NULL DEFAULT 2.0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS telemetry_data (
                data_id INTEGER PRIMARY KEY AUTOINCREMENT,
                machine_id INTEGER NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
                voltage REAL NOT NULL,
                current_amp REAL NOT NULL,
                temperature REAL NOT NULL,
                active_power_kw REAL NOT NULL,
                timestamp TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_machine_time ON telemetry_data(machine_id, timestamp);
            CREATE TABLE IF NOT EXISTS anomalies (
                anomaly_id INTEGER PRIMARY KEY AUTOINCREMENT,
                machine_id INTEGER NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
                anomaly_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                financial_loss_tl REAL NOT NULL,
                co2_impact_kg REAL NOT NULL,
                status TEXT NOT NULL DEFAULT 'ACTIVE',
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_anomalies_status ON anomalies(status);
            CREATE INDEX IF NOT EXISTS idx_anomalies_open ON anomalies(machine_id, anomaly_type, status);
            CREATE TABLE IF NOT EXISTS work_orders (
                work_order_id INTEGER PRIMARY KEY AUTOINCREMENT,
                anomaly_id INTEGER NOT NULL REFERENCES anomalies(anomaly_id) ON DELETE CASCADE,
                machine_id INTEGER NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
                note TEXT,
                status TEXT NOT NULL DEFAULT 'OPEN',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """, connection))
        {
            schema.ExecuteNonQuery();
        }

        using var count = new SqliteCommand("SELECT COUNT(*) FROM machines", connection);
        if (Convert.ToInt32(count.ExecuteScalar(), CultureInfo.InvariantCulture) != 0)
        {
            return;
        }

        (string Name, string Location, double Current, double Temperature, double Area)[] machines =
        [
            ("Kompresör Hattı A", "Pres Atölyesi", 100, 75, 4),
            ("Enjeksiyon Makinesi 2", "Plastik Üretim", 80, 85, 3),
            ("Fırın Konveyörü", "Isıl İşlem", 60, 180, 8),
            ("Soğutma Pompası", "Enerji Merkezi", 40, 55, 1.5),
            ("CNC İşleme Merkezi", "Talaşlı İmalat", 50, 70, 2.5)
        ];
        using var transaction = connection.BeginTransaction();
        foreach (var machine in machines)
        {
            using var insert = new SqliteCommand("""
                INSERT INTO machines (machine_name, location, nominal_current, max_temperature, surface_area_m2)
                VALUES (@name, @location, @current, @temperature, @area)
                """, connection, transaction);
            insert.Parameters.AddWithValue("@name", machine.Name);
            insert.Parameters.AddWithValue("@location", machine.Location);
            insert.Parameters.AddWithValue("@current", machine.Current);
            insert.Parameters.AddWithValue("@temperature", machine.Temperature);
            insert.Parameters.AddWithValue("@area", machine.Area);
            insert.ExecuteNonQuery();
        }

        transaction.Commit();
    }

    private static List<MachineRow> LoadMachines(SqliteConnection connection)
    {
        using var command = new SqliteCommand("""
            SELECT machine_id, machine_name, location, nominal_current, max_temperature
            FROM machines ORDER BY machine_id
            """, connection);
        using var reader = command.ExecuteReader();
        var rows = new List<MachineRow>();
        while (reader.Read())
        {
            rows.Add(new MachineRow
            {
                MachineId = reader.GetInt32(0),
                Name = reader.GetString(1),
                Location = reader.IsDBNull(2) ? "" : reader.GetString(2),
                Meta = $"{reader.GetDouble(3).ToString("0", Turkish)} A nominal · {reader.GetDouble(4).ToString("0", Turkish)} °C eşik"
            });
        }

        return rows;
    }

    private static List<AlarmRow> LoadAlarms(SqliteConnection connection)
    {
        using var command = new SqliteCommand("""
            SELECT a.anomaly_id, a.machine_id, m.machine_name, m.location,
                   a.anomaly_type, a.severity, a.financial_loss_tl, a.co2_impact_kg,
                   a.status, a.created_at
            FROM anomalies a
            INNER JOIN machines m ON m.machine_id = a.machine_id
            ORDER BY a.created_at DESC, a.anomaly_id DESC LIMIT 40
            """, connection);
        using var reader = command.ExecuteReader();
        var rows = new List<AlarmRow>();
        while (reader.Read())
        {
            string severity = reader.GetString(5);
            string status = reader.GetString(8);
            double loss = reader.GetDouble(6);
            double co2 = reader.GetDouble(7);
            DateTime created = ParseTimestamp(reader.GetString(9));
            string location = reader.IsDBNull(3) ? "" : reader.GetString(3);
            (Brush badge, Brush soft) = Badge(status, severity);
            rows.Add(new AlarmRow
            {
                AnomalyId = reader.GetInt32(0),
                MachineId = reader.GetInt32(1),
                Status = status,
                MachineName = reader.GetString(2),
                TypeLabel = TypeLabel(reader.GetString(4)),
                SeverityLabel = status == "RESOLVED" ? "Kapandı" : severity == "CRITICAL" ? "Kritik" : "Uyarı",
                LossText = loss.ToString("N1", Turkish) + " TL/saat",
                MetaText = $"{location} · {co2.ToString("N2", Turkish)} kg CO₂ · {created:HH:mm:ss}",
                BadgeBrush = badge,
                BadgeSoftBrush = soft
            });
        }

        return rows;
    }

    private static List<TelemetryPoint> LoadSeries(SqliteConnection connection, int machineId)
    {
        using var command = new SqliteCommand("""
            SELECT timestamp, voltage, current_amp, temperature
            FROM telemetry_data WHERE machine_id = @id
            ORDER BY data_id DESC LIMIT 40
            """, connection);
        command.Parameters.AddWithValue("@id", machineId);
        using var reader = command.ExecuteReader();
        var rows = new List<TelemetryPoint>();
        while (reader.Read())
        {
            rows.Add(new TelemetryPoint
            {
                Timestamp = ParseTimestamp(reader.GetString(0)),
                Voltage = reader.GetDouble(1),
                Current = reader.GetDouble(2),
                Temperature = reader.GetDouble(3)
            });
        }

        rows.Reverse();
        return rows;
    }

    private static int ScalarInt(SqliteConnection connection, string sql)
    {
        using var command = new SqliteCommand(sql, connection);
        return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture);
    }

    private static double ScalarDouble(SqliteConnection connection, string sql)
    {
        using var command = new SqliteCommand(sql, connection);
        object? value = command.ExecuteScalar();
        return value is null or DBNull
            ? 0
            : Convert.ToDouble(value, CultureInfo.InvariantCulture);
    }

    private static string FormatTimestamp(DateTime timestamp) =>
        timestamp.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);

    private static DateTime ParseTimestamp(string timestamp) =>
        DateTime.Parse(timestamp, CultureInfo.InvariantCulture);

    private static string TypeLabel(string anomalyType) => anomalyType switch
    {
        "ASIRI_AKIM" => "Aşırı akım",
        "ATIK_ISI_KAYBI" => "Atık ısı kaybı",
        "BOSTA_CALISMA" => "Boşta çalışma",
        _ => anomalyType
    };

    private static (Brush Badge, Brush Soft) Badge(string status, string severity)
    {
        if (status == "RESOLVED")
        {
            return (BrushOf(142, 170, 160), BrushOf(142, 170, 160, 36));
        }

        if (severity == "CRITICAL")
        {
            return (BrushOf(255, 106, 106), BrushOf(255, 106, 106, 36));
        }

        return (BrushOf(245, 196, 81), BrushOf(245, 196, 81, 36));
    }

    private static SolidColorBrush BrushOf(byte r, byte g, byte b, byte a = 255)
    {
        var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        brush.Freeze();
        return brush;
    }
}
