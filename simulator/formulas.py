# =============================================================================
# ECOPULSE_FORMULAS
# Test formül seti kilitlendi: 31 Ekim 2026
#
# Değiştirmek için yalnızca bu dosyayı açın.
# Katsayılar üst bloktadır; formül gövdeleri alt bloktadır.
# Arama ifadesi: ECOPULSE_FORMULAS
# =============================================================================

import math

# --- Katsayılar. Sayı değişecekse formül gövdesine dokunmayın. ---

# Üç fazlı hat. Tek faza dönmek için FAZ_KATSAYISI = 1 yapın.
FAZ_KATSAYISI = math.sqrt(3)

# Yüklü endüstriyel motor için tipik güç faktörü.
COS_PHI_YUKLU = 0.85

# Boşta çalışmada mıknatıslanma akımı yüzünden güç faktörü düşer.
COS_PHI_BOSTA = 0.25

# EPDK 4 Nisan 2026, orta gerilim sanayi, tek terimli, tek zamanlı.
# Enerji 2.909687 + dağıtım 1.182457 = 4.092 TL/kWh. Vergi hariç.
TARIFE_TL_PER_KWH = 4.092

# ETKB / EVÇED, 2023 tüketim noktası, iletim hattı, kg CO2-eşd. / kWh.
# Dağıtım hattına geçmek için 0.469 yazın.
SEBEKE_CO2_KG_PER_KWH = 0.436

# Atık ısı: Q (W) = U × A × ΔT. U birimi W/m²·°C.
ISI_GECIS_KATSAYISI_U = 10.0

# Ortam sensörü (BME280) gelene kadar test ortam sıcaklığı, °C.
ORTAM_SICAKLIK_C = 25.0

# Aşırı akım, nominalin bu oranını aşınca başlar. 0.20 = %20.
ASIRI_AKIM_ESIK_ORANI = 0.20

# Aşım bu oranı da geçerse CRITICAL. 0.40 = %40.
ASIRI_AKIM_CRITICAL_ORAN = 0.40

# Boşta çalışma bandı: nominalin %10'u ile %35'i arası. Altı "kapalı" sayılır.
BOSTA_ALT_ORAN = 0.10
BOSTA_UST_ORAN = 0.35

# T_max bu kadar °C aşılırsa atık ısı CRITICAL olur.
ATIK_ISI_CRITICAL_DELTA_C = 10.0

# Tek ölçüm alarm açmasın. Eşik bu kadar ardışık ölçüm sürerse yazılır.
ARDISIK_OLCUM_SAYISI = 3

# Boşta çalışma bu kadar ardışık ölçüm sürerse CRITICAL olur.
BOSTA_CRITICAL_ARDISIK = 10

# Paneldeki "engellenen CO2" kartı bu durumdaki kayıtları toplar.
ENGELLENEN_CO2_DURUMU = "RESOLVED"


def AnlikGucKw(voltage, current_amp, cos_phi=COS_PHI_YUKLU):
    """Çekilen aktif güç. P (kW) = √3 × V × I × cosφ / 1000"""
    return FAZ_KATSAYISI * voltage * current_amp * cos_phi / 1000.0


def AsiriAkimKayipKw(voltage, current_amp, nominal_current):
    """P_kayıp (kW) = √3 × V × (I_ölçülen − I_nominal) × cosφ_yüklü / 1000"""
    delta_i = current_amp - nominal_current
    if delta_i <= 0:
        return 0.0
    return FAZ_KATSAYISI * voltage * delta_i * COS_PHI_YUKLU / 1000.0


def AsiriAkimEsikAsildi(current_amp, nominal_current):
    if nominal_current <= 0:
        return False
    return (current_amp - nominal_current) > (nominal_current * ASIRI_AKIM_ESIK_ORANI)


def AsiriAkimSiddet(current_amp, nominal_current):
    if not AsiriAkimEsikAsildi(current_amp, nominal_current):
        return None
    oran = (current_amp - nominal_current) / nominal_current
    if oran > ASIRI_AKIM_CRITICAL_ORAN:
        return "CRITICAL"
    return "WARNING"


def AtikIsiKayipKw(temperature, surface_area_m2, ambient_c=ORTAM_SICAKLIK_C, u=ISI_GECIS_KATSAYISI_U):
    """P_kayıp (kW) = U × A × (T_yüzey − T_ortam) / 1000"""
    delta_t = temperature - ambient_c
    if delta_t <= 0 or surface_area_m2 <= 0:
        return 0.0
    return u * surface_area_m2 * delta_t / 1000.0


def AtikIsiEsikAsildi(temperature, max_temperature):
    return temperature > max_temperature


def AtikIsiSiddet(temperature, max_temperature):
    if not AtikIsiEsikAsildi(temperature, max_temperature):
        return None
    if (temperature - max_temperature) > ATIK_ISI_CRITICAL_DELTA_C:
        return "CRITICAL"
    return "WARNING"


def BostaCalismaEsikAsildi(current_amp, nominal_current):
    if nominal_current <= 0:
        return False
    oran = current_amp / nominal_current
    return BOSTA_ALT_ORAN <= oran < BOSTA_UST_ORAN


def BostaCalismaKayipKw(voltage, current_amp):
    """P_kayıp (kW) = √3 × V × I_ölçülen × cosφ_boşta / 1000. Üretim yok, çekilen gücün tamamı kayıptır."""
    if current_amp <= 0:
        return 0.0
    return FAZ_KATSAYISI * voltage * current_amp * COS_PHI_BOSTA / 1000.0


def BostaCalismaSiddet(ardisik_olcum):
    if ardisik_olcum >= BOSTA_CRITICAL_ARDISIK:
        return "CRITICAL"
    if ardisik_olcum >= ARDISIK_OLCUM_SAYISI:
        return "WARNING"
    return None


def ZararTlSaat(p_kayip_kw, tarife=TARIFE_TL_PER_KWH):
    """TL/saat = P_kayıp (kW) × tarife (TL/kWh)"""
    return p_kayip_kw * tarife


def KarbonKg(p_kayip_kw, faktor=SEBEKE_CO2_KG_PER_KWH):
    """kg CO2 = P_kayıp (kW) × şebeke faktörü (kg/kWh)"""
    return p_kayip_kw * faktor


if __name__ == "__main__":
    akim = AsiriAkimKayipKw(400, 130, 100)
    beklenen_akim = math.sqrt(3) * 400 * 30 * COS_PHI_YUKLU / 1000.0
    assert abs(akim - beklenen_akim) < 1e-6

    isi = AtikIsiKayipKw(80, 4)
    assert abs(isi - (10 * 4 * 55 / 1000.0)) < 1e-6

    bosta = BostaCalismaKayipKw(400, 25)
    beklenen_bosta = math.sqrt(3) * 400 * 25 * COS_PHI_BOSTA / 1000.0
    assert abs(bosta - beklenen_bosta) < 1e-6

    assert AsiriAkimSiddet(150, 100) == "CRITICAL"
    assert AsiriAkimSiddet(130, 100) == "WARNING"
    assert AtikIsiSiddet(82, 75) == "WARNING"
    assert AtikIsiSiddet(90, 75) == "CRITICAL"
    assert BostaCalismaEsikAsildi(25, 100) is True
    assert BostaCalismaEsikAsildi(5, 100) is False

    print("ECOPULSE_FORMULAS doğrulandı")
    print(
        f"Aşırı akım örneği (400 V, 130 A, nominal 100 A): "
        f"{akim:.2f} kW, {ZararTlSaat(akim):.2f} TL/saat, {KarbonKg(akim):.2f} kg CO2"
    )
