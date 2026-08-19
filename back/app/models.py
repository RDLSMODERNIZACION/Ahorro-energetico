from datetime import date
from decimal import Decimal
from pydantic import BaseModel, Field

class SiteCreate(BaseModel):
    organization_id: str
    name: str = Field(min_length=2, max_length=160)
    site_type: str | None = None
    address: str | None = None
    latitude: Decimal | None = None
    longitude: Decimal | None = None

class MeterCreate(BaseModel):
    organization_id: str
    site_id: str | None = None
    meter_number: str
    nis: str | None = None
    supply_number: str | None = None
    voltage_level: str | None = None
    current_tariff_code: str | None = None
    contracted_kw_peak: Decimal | None = None
    contracted_kw_off_peak: Decimal | None = None
    service_capacity_kw: Decimal | None = None

class LocationUpdate(BaseModel):
    latitude: Decimal = Field(ge=-90, le=90)
    longitude: Decimal = Field(ge=-180, le=180)

class TariffScheduleCreate(BaseModel):
    provider: str = "EPEN"
    resolution_number: str
    consumption_month: date
    billing_month: date
    valid_from: date
    valid_to: date | None = None
    notes: str | None = None

class TariffRateCreate(BaseModel):
    category_code: str
    voltage_level: str = "NA"
    customer_segment: str = "general"
    min_capacity_kw: Decimal | None = None
    max_capacity_kw: Decimal | None = None
    charge_code: str
    charge_name: str
    unit: str
    time_band: str = "all"
    subsidized: bool = False
    unit_price: Decimal

class ScenarioRequest(BaseModel):
    organization_id: str
    opportunity_ids: list[str]
    years: int = Field(default=5, ge=1, le=20)
