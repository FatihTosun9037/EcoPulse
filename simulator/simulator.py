"""EcoPulse sensör simülatörü.

Canlı çalıştırma:
    py -3 simulator.py

Klavye:
    n  tüm makineler normal
    1  Kompresör Hattı A  -> aşırı akım
    2  Enjeksiyon Makinesi 2 -> boşta çalışma
    3  Fırın Konveyörü -> atık ısı
    q  çıkış

Kendini denetleyen kısa tur:
    py -3 simulator.py --tur 8
"""

import argparse
import random
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from db import connect
from detector import Detector
from formulas import AnlikGucKw, COS_PHI_BOSTA, COS_PHI_YUKLU, ORTAM_SICAKLIK_C

MACHINES = (
    ("Kompresör Hattı A", "Pres Atölyesi", 100.0, 75.0, 4.0),
    ("Enjeksiyon Makinesi 2", "Plastik Üretim", 80.0, 85.0, 3.0),
    ("Fırın Konveyörü", "Isıl İşlem", 60.0, 180.0, 8.0),
    ("Soğutma Pompası", "Enerji Merkezi", 40.0, 55.0, 1.5),
    ("CNC İşleme Merkezi", "Talaşlı İmalat", 50.0, 70.0, 2.5),
)

# Senaryo turunda bu makineler kasıtlı olarak eşiği aşar.
SCRIPT_FAULTS = {
    "Kompresör Hattı A": "asiri_akim",
    "Enjeksiyon Makinesi 2": "bosta",
    "Fırın Konveyörü": "atik_isi",
}


def seed_machines(connection):
    cursor = connection.cursor()
    cursor.execute("SELECT COUNT(*) FROM machines")
    (count,) = cursor.fetchone()
    if count:
        cursor.close()
        return
    cursor.executemany(
        """
        INSERT INTO machines
            (machine_name, location, nominal_current, max_temperature, surface_area_m2)
        VALUES (%s, %s, %s, %s, %s)
        """,
        MACHINES,
    )
    connection.commit()
    cursor.close()


def load_machines(connection):
    cursor = connection.cursor(dictionary=True)
    cursor.execute(
        """
        SELECT machine_id, machine_name, location, nominal_current, max_temperature, surface_area_m2
        FROM machines
        ORDER BY machine_id
        """
    )
    rows = cursor.fetchall()
    cursor.close()
    return rows


def sample(machine, mode):
    nominal = float(machine["nominal_current"])
    max_temperature = float(machine["max_temperature"])
    voltage = max(360.0, random.gauss(400.0, 1.5))

    if mode == "asiri_akim":
        current = nominal * random.uniform(1.45, 1.60)
        temperature = _normal_temperature(max_temperature)
        cos_phi = COS_PHI_YUKLU
    elif mode == "atik_isi":
        current = nominal * random.uniform(0.75, 0.90)
        temperature = max_temperature + random.uniform(12.0, 18.0)
        cos_phi = COS_PHI_YUKLU
    elif mode == "bosta":
        current = nominal * random.uniform(0.18, 0.30)
        temperature = ORTAM_SICAKLIK_C + random.uniform(4.0, 10.0)
        cos_phi = COS_PHI_BOSTA
    else:
        current = nominal * random.uniform(0.72, 0.90)
        temperature = _normal_temperature(max_temperature)
        cos_phi = COS_PHI_YUKLU

    power = AnlikGucKw(voltage, current, cos_phi)
    return voltage, current, temperature, power


def _normal_temperature(max_temperature):
    span = max(max_temperature - ORTAM_SICAKLIK_C, 1.0)
    temperature = ORTAM_SICAKLIK_C + span * random.uniform(0.45, 0.68)
    return min(temperature, max_temperature - 3.0)


def insert_reading(connection, machine, voltage, current, temperature, power, timestamp):
    cursor = connection.cursor()
    cursor.execute(
        """
        INSERT INTO telemetry_data
            (machine_id, voltage, current_amp, temperature, active_power_kw, timestamp)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (
            machine["machine_id"],
            round(voltage, 2),
            round(current, 2),
            round(temperature, 2),
            round(power, 3),
            timestamp,
        ),
    )
    cursor.close()


def read_key():
    try:
        import msvcrt
    except ImportError:
        return None
    if not msvcrt.kbhit():
        return None
    key = msvcrt.getwch()
    return key.lower()


def apply_key(key, modes, machines):
    if key == "n":
        for machine in machines:
            modes[machine["machine_id"]] = "normal"
        print("Tüm makineler normal akışa döndü.")
        return False
    if key == "q":
        print("Simülatör duruyor.")
        return True
    targets = {"1": "asiri_akim", "2": "bosta", "3": "atik_isi"}
    if key in targets and len(machines) >= 3:
        machine = machines[int(key) - 1]
        modes[machine["machine_id"]] = targets[key]
        print(f"{machine['machine_name']} -> {targets[key]}")
    return False


def run_tick(connection, detector, machines, modes):
    timestamp = datetime.now().replace(microsecond=0)
    for machine in machines:
        mode = modes.get(machine["machine_id"], "normal")
        voltage, current, temperature, power = sample(machine, mode)
        insert_reading(connection, machine, voltage, current, temperature, power, timestamp)
        detector.evaluate(
            connection,
            machine,
            voltage,
            current,
            temperature,
            timestamp,
        )
    connection.commit()
    return timestamp


def print_banner():
    print("EcoPulse simülatörü çalışıyor. Formüller: simulator/formulas.py (ECOPULSE_FORMULAS)")
    print("n = normal   1 = aşırı akım   2 = boşta   3 = atık ısı   q = çıkış")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tur", type=int, default=0, help="Bitince çıkan kısa tur sayısı")
    parser.add_argument("--saniye", type=float, default=2.0)
    args = parser.parse_args()

    connection = connect()
    seed_machines(connection)
    machines = load_machines(connection)
    if not machines:
        print("Makine bulunamadı.")
        return 1

    detector = Detector()
    modes = {machine["machine_id"]: "normal" for machine in machines}

    if args.tur > 0:
        for step in range(1, args.tur + 1):
            if step > 3:
                for machine in machines:
                    fault = SCRIPT_FAULTS.get(machine["machine_name"])
                    if fault:
                        modes[machine["machine_id"]] = fault
            stamp = run_tick(connection, detector, machines, modes)
            print(f"tur {step}  {stamp:%H:%M:%S}")
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT anomaly_type, severity, ROUND(financial_loss_tl, 2), ROUND(co2_impact_kg, 2)
            FROM anomalies
            ORDER BY anomaly_id
            """
        )
        for row in cursor.fetchall():
            print("anomali", row)
        cursor.close()
        connection.close()
        return 0

    print_banner()
    while True:
        if apply_key(read_key(), modes, machines):
            break
        stamp = run_tick(connection, detector, machines, modes)
        active = sum(1 for mode in modes.values() if mode != "normal")
        print(f"{stamp:%H:%M:%S}  ölçüm yazıldı  senaryo={active}")
        time.sleep(args.saniye)

    connection.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
