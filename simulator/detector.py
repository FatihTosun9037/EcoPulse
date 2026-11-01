"""Anomali kuralları. Kayıp hesabı ECOPULSE_FORMULAS içinden gelir."""

from formulas import (
    ARDISIK_OLCUM_SAYISI,
    AsiriAkimKayipKw,
    AsiriAkimSiddet,
    AtikIsiKayipKw,
    AtikIsiSiddet,
    BostaCalismaEsikAsildi,
    BostaCalismaKayipKw,
    BostaCalismaSiddet,
    KarbonKg,
    ZararTlSaat,
)


class Detector:
    def __init__(self):
        self._counts = {}

    def evaluate(self, connection, machine, voltage, current_amp, temperature, timestamp):
        machine_id = machine["machine_id"]
        nominal = float(machine["nominal_current"])
        max_temperature = float(machine["max_temperature"])
        area = float(machine["surface_area_m2"])

        self._track(
            connection,
            machine_id,
            "ASIRI_AKIM",
            AsiriAkimSiddet(current_amp, nominal),
            AsiriAkimKayipKw(voltage, current_amp, nominal),
            timestamp,
        )
        self._track(
            connection,
            machine_id,
            "ATIK_ISI_KAYBI",
            AtikIsiSiddet(temperature, max_temperature),
            AtikIsiKayipKw(temperature, area),
            timestamp,
        )
        self._track_bosta(connection, machine_id, nominal, voltage, current_amp, timestamp)

    def _track(self, connection, machine_id, anomaly_type, severity, loss_kw, timestamp):
        key = (machine_id, anomaly_type)
        if severity is None:
            self._counts[key] = 0
            return
        count = self._counts.get(key, 0) + 1
        self._counts[key] = count
        if count < ARDISIK_OLCUM_SAYISI:
            return
        self._write(connection, machine_id, anomaly_type, severity, loss_kw, timestamp)

    def _track_bosta(self, connection, machine_id, nominal, voltage, current_amp, timestamp):
        key = (machine_id, "BOSTA_CALISMA")
        if not BostaCalismaEsikAsildi(current_amp, nominal):
            self._counts[key] = 0
            return
        count = self._counts.get(key, 0) + 1
        self._counts[key] = count
        severity = BostaCalismaSiddet(count)
        if severity is None:
            return
        loss_kw = BostaCalismaKayipKw(voltage, current_amp)
        self._write(connection, machine_id, "BOSTA_CALISMA", severity, loss_kw, timestamp)

    def _write(self, connection, machine_id, anomaly_type, severity, loss_kw, timestamp):
        loss_tl = ZararTlSaat(loss_kw)
        co2_kg = KarbonKg(loss_kw)
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT anomaly_id
            FROM anomalies
            WHERE machine_id = %s AND anomaly_type = %s AND status = 'ACTIVE'
            ORDER BY anomaly_id DESC
            LIMIT 1
            """,
            (machine_id, anomaly_type),
        )
        row = cursor.fetchone()
        if row:
            cursor.execute(
                """
                UPDATE anomalies
                SET severity = %s, financial_loss_tl = %s, co2_impact_kg = %s
                WHERE anomaly_id = %s
                """,
                (severity, loss_tl, co2_kg, row[0]),
            )
        else:
            cursor.execute(
                """
                INSERT INTO anomalies (
                    machine_id, anomaly_type, severity,
                    financial_loss_tl, co2_impact_kg, status, created_at
                ) VALUES (%s, %s, %s, %s, %s, 'ACTIVE', %s)
                """,
                (machine_id, anomaly_type, severity, loss_tl, co2_kg, timestamp),
            )
        cursor.close()
