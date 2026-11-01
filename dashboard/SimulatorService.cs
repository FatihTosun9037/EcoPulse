namespace EcoPulse.Dashboard;

internal sealed class SimulatorService
{
    private const double PhaseFactor = 1.7320508075688772;
    private const double LoadedPowerFactor = 0.85;
    private const double IdlePowerFactor = 0.25;
    private const double AmbientTemperature = 25.0;
    private const double HeatTransferCoefficient = 10.0;
    private readonly DashboardRepository _repository;
    private readonly List<SimulationMachine> _machines;
    private readonly Dictionary<(int MachineId, string Type), int> _counts = new();
    private readonly Random _random = new();
    private int _faultMachineId;

    public SimulatorService(DashboardRepository repository)
    {
        _repository = repository;
        _machines = repository.GetSimulationMachines();
    }

    public void Tick()
    {
        DateTime timestamp = DateTime.Now;
        var readings = new List<SimulationReading>(_machines.Count);
        var anomalies = new List<SimulationAnomaly>();

        foreach (SimulationMachine machine in _machines)
        {
            string mode = GetMode(machine);
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
            readings.Add(new SimulationReading(
                machine.Id,
                Math.Round(voltage, 2),
                Math.Round(current, 2),
                Math.Round(temperature, 2),
                Math.Round(power, 3),
                timestamp));

            TrackOvercurrent(machine, voltage, current, timestamp, anomalies);
            TrackWasteHeat(machine, temperature, timestamp, anomalies);
            TrackIdle(machine, voltage, current, timestamp, anomalies);
        }

        _repository.SaveSimulationTick(readings, anomalies);
    }

    public void SetFault(int machineId) => Volatile.Write(ref _faultMachineId, machineId);

    public void ClearFault() => Volatile.Write(ref _faultMachineId, 0);

    private string GetMode(SimulationMachine machine)
    {
        if (Volatile.Read(ref _faultMachineId) != machine.Id)
        {
            return "normal";
        }

        return machine.Name switch
        {
            "Enjeksiyon Makinesi 2" or "CNC İşleme Merkezi" => "bosta",
            "Fırın Konveyörü" or "Soğutma Pompası" => "atik_isi",
            _ => "asiri_akim"
        };
    }

    private void TrackOvercurrent(
        SimulationMachine machine,
        double voltage,
        double current,
        DateTime timestamp,
        List<SimulationAnomaly> anomalies)
    {
        string type = "ASIRI_AKIM";
        double excess = current - machine.NominalCurrent;
        if (excess <= machine.NominalCurrent * 0.20)
        {
            _counts[(machine.Id, type)] = 0;
            return;
        }

        int count = Increment(machine.Id, type);
        if (count < 3)
        {
            return;
        }

        double ratio = excess / machine.NominalCurrent;
        double loss = PhaseFactor * voltage * excess * LoadedPowerFactor / 1000;
        anomalies.Add(new SimulationAnomaly(
            machine.Id,
            type,
            ratio > 0.40 ? "CRITICAL" : "WARNING",
            loss,
            timestamp));
    }

    private void TrackWasteHeat(
        SimulationMachine machine,
        double temperature,
        DateTime timestamp,
        List<SimulationAnomaly> anomalies)
    {
        string type = "ATIK_ISI_KAYBI";
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

        double loss = HeatTransferCoefficient
            * machine.SurfaceArea
            * (temperature - AmbientTemperature)
            / 1000;
        anomalies.Add(new SimulationAnomaly(
            machine.Id,
            type,
            excess > 10 ? "CRITICAL" : "WARNING",
            loss,
            timestamp));
    }

    private void TrackIdle(
        SimulationMachine machine,
        double voltage,
        double current,
        DateTime timestamp,
        List<SimulationAnomaly> anomalies)
    {
        string type = "BOSTA_CALISMA";
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

        double loss = PhaseFactor * voltage * current * IdlePowerFactor / 1000;
        anomalies.Add(new SimulationAnomaly(
            machine.Id,
            type,
            count >= 10 ? "CRITICAL" : "WARNING",
            loss,
            timestamp));
    }

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
        return Math.Min(
            AmbientTemperature + span * Next(0.45, 0.68),
            maximum - 3);
    }

    private double Next(double minimum, double maximum) =>
        minimum + _random.NextDouble() * (maximum - minimum);

    private double NextGaussian(double mean, double standardDeviation)
    {
        double first = 1 - _random.NextDouble();
        double second = 1 - _random.NextDouble();
        double standardNormal = Math.Sqrt(-2 * Math.Log(first))
            * Math.Sin(2 * Math.PI * second);
        return mean + standardNormal * standardDeviation;
    }
}
