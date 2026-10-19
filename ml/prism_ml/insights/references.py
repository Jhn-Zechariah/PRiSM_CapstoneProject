"""Sources behind the insight sentences. Every sentence lists the reference ids it relies on."""

REFERENCES = {
    "VERMEER2023": {
        "citation": "Vermeer, H. M. & Aarnink, A. J. A. (2023). Review on heat stress in pigs on farm. "
                    "EURCAW-Pigs, version 1.0. CC-BY-4.0.",
        "url": "https://doi.org/10.5281/zenodo.7620726",
        "used_for": "Animal-based indicators (respiration rate >50/min at rest per EU-PiG, panting, open-mouth "
                    "breathing, lying apart/laterally, pen fouling, reduced activity and feed intake, increased "
                    "water use); measures (maximise ventilation, check drinkers, use showers/sprinklers, spray "
                    "pigs and increase air speed at heavy heat stress, postpone treatments, avoid arousal in "
                    "the hottest period); THI formula and the THI>84 level for finishers; skin temperature "
                    "is a weaker indicator than core temperature.",
    },
    "PRISM2026": {
        "citation": "Code Vibers (2026). PRISM: An IoT-Based Smart Swine Temperature Monitoring and Management "
                    "System, Chapters 1-3. Polytechnic University of the Philippines.",
        "url": None,
        "used_for": "Scope: monitoring aid only; does not perform medical diagnosis or replace veterinary "
                    "assessment; sprinkler activation is the farmer's decision.",
    },
    "ADAFRUIT_AMG8833": {
        "citation": "Adafruit Industries. Adafruit AMG8833 8x8 Thermal Camera Sensor - Overview.",
        "url": "https://learn.adafruit.com/adafruit-amg8833-8x8-thermal-camera-sensor/overview",
        "used_for": "AMG8833 range 0-80 degC and accuracy +/-2.5 degC.",
    },
    "ADAFRUIT_DHT": {
        "citation": "Adafruit Industries. DHT11, DHT22 and AM2302 Sensors - Overview.",
        "url": "https://learn.adafruit.com/dht/overview",
        "used_for": "DHT22 humidity 0-100 % (2-5 % accuracy), temperature -40 to 80 degC (+/-0.5 degC).",
    },
}


def cite(*ids: str) -> list[str]:
    for i in ids:
        if i not in REFERENCES:
            raise KeyError(i)
    return list(ids)
