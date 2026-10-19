# Sensor display thresholds (Low / Normal / High) and their sources

These bands label the live readings on the Temperature and Humidity pages and the Dashboard
("Room Temp" in Quick Stats).
They are display bands from published sources, **not** the ML thermal-status classifier (Dashboard
recommendation card). Code: `lib/core/constants/thermal_thresholds.dart`; tests:
`test/thermal_thresholds_test.dart`. All sources were opened and checked on 2026-10-12.

| Reading (sensor) | Low | Normal | High | Sources |
|---|---|---|---|---|
| Pig skin-surface temperature (AMG8833) | < 32 °C | 32–35 °C | > 35 °C | [2], [3], [5] |
| Relative humidity (DHT22) | < 50 % | 50–70 % | > 70 % | [8], [3] |
| Air temperature (DHT22), Dashboard "Room Temp" | < 15.6 °C | 15.6–23.9 °C | > 23.9 °C | [9], [5], [7] |

## Rationale

* **Why skin and not rectal temperature.** The AMG8833 is an infrared sensor: it measures the pig's
  apparent *surface* temperature. The normal *rectal* (core) temperature of pigs is 38.7–39.8 °C [1], and
  surface temperature is lower than core (rectal 38.9 ± 0.4 °C vs eye surface 36.7 °C, r = 0.58 [6]).
  Applying the rectal range to the AMG8833 would label most healthy pigs "Low". The rectal range should
  appear in the paper as the pig's normal body temperature, not as the sensor threshold.
* **Skin 32–35 °C = Normal.** The comfort skin temperature of homeothermic animals is 32–35 °C (Geers
  et al., 1987, citing Fanger, 1972, as reported and confirmed in [2]). Group-housed 60 kg pigs had skin
  temperatures of 33–35 °C at air temperatures of 16–22 °C [2], [3]. Skin temperature rose 0.25 °C for
  every 1 °C rise in air temperature [3].
* **Skin > 35 °C = High.** A skin temperature of 36 °C is reported as a heat-stress threshold for 60 kg
  pigs ([5], citing Huynh, 2005). Readings above the 35 °C comfort limit are flagged before that
  threshold (conservative). Under tropical conditions, uncooled pens averaged 35.6 °C and reached
  36.3–37.5 °C in the afternoon [4].
* **Skin < 32 °C = Low.** Below the comfort skin range [2].
* **Humidity 50–70 % = Normal.** "A relative humidity between 50 and 70% is desirable in most swine
  buildings" [8]. At 80 % RH, heat-stress responses began at lower air temperatures, and daily gain was
  highest at 50 % RH [3]. (The app previously used 60–70 % without a cited source.)
* **Air temperature 15.6–23.9 °C = Normal.** The comfort zone (effective critical temperatures) of grower
  pigs (50–130 lb) is 60–75 °F = 15.6–23.9 °C; finishers (130–275 lb) 55–75 °F = 12.8–23.9 °C; nursery
  (18–50 lb) 70–85 °F = 21.1–29.4 °C [9]. The grower range is used because PRISM targets small
  grower-finisher pens and the app does not know each pig's stage (its lower bound is the more cautious).
  The upper limit agrees with the thermoneutral upper limits by body weight (grower 30 kg: 28 °C;
  finisher > 60 kg: 25 °C) [5]. The Philippine standard PAES 401:2001 sets 30 °C as the **maximum**
  allowed for housed growers/finishers in still air [7]; readings above 30 °C exceed the national
  standard, not only the comfort zone.
* **Expect "High" often.** [9] notes that in tropical Guam (typically 24–31 °C) grower-finisher pigs are
  "constantly being exposed to the heat stress alert or danger zone". In Philippine pens "Room Temp: High"
  will therefore be frequent; this is accurate, not a sensor fault.

## Limitations (state these in the paper)

* AMG8833 accuracy is ±2.5 °C (Adafruit). The firmware reports the **hottest pixel** of the 8×8 frame,
  which may be a hot floor or wall rather than a pig. Distance, angle, wet or dirty skin, and sunlight
  change the reading.
* Sources [2]–[4] measured specific body sites (loin, ham, behind the ear) on dry skin with calibrated
  handheld infrared thermometers; the AMG8833 averages a much larger area per pixel. The bands are
  reliable only after the sensor calibration against a reference (paper objective 2).
* The studies used European/Vietnamese growing pigs of about 60 kg. Validate the bands on your own farm.
* [8] is an archived 1984 extension bulletin; it is supported by the experimental results in [3].
* The deployed firmware's own `humidityStatus` text (`PIG_HUM_LOW_NORMAL` = 60) is not used by the app;
  change it to 50 for consistency if the firmware is updated.

## References (APA 7)

1. Fielder, S. E. (2022, updated 2024). *Normal rectal temperature ranges*. MSD Veterinary Manual.
   https://www.msdvetmanual.com/reference-values-and-conversion-tables/reference-guides/normal-rectal-temperature-ranges
2. Huynh, T. T. T. (2005). *Heat stress in growing pigs* [Doctoral dissertation, Wageningen University].
   https://edepot.wur.nl/121639
3. Huynh, T. T. T., Aarnink, A. J. A., Verstegen, M. W. A., Gerrits, W. J. J., Heetkamp, M. J. W.,
   Kemp, B., & Canh, T. T. (2005). Effects of increasing temperatures on physiological changes in pigs at
   different relative humidities. *Journal of Animal Science, 83*(6), 1385–1396.
   https://doi.org/10.2527/2005.8361385x
4. Huynh, T. T. T., Aarnink, A. J. A., Truong, C. T., Kemp, B., & Verstegen, M. W. A. (2006). Effects of
   tropical climate and water cooling methods on growing pigs' responses. *Livestock Science, 104*(3),
   278–291. https://doi.org/10.1016/j.livsci.2006.04.029
5. Vermeer, H. M., & Aarnink, A. J. A. (2023). *Review on heat stress in pigs on farm* (Version 1.0).
   European Union Reference Centre for Animal Welfare Pigs (EURCAW-Pigs).
   https://doi.org/10.5281/zenodo.7620726
6. Barbieri, S., Talamonti, Z., Nannoni, E., Heinzl, E. U. L., Minero, M., & Canali, E. (2021). Use of
   thermography in pigs: Relationship between surface and core temperature. *Veterinaria Italiana,
   57*(1), 79–82. https://doi.org/10.12834/VetIt.1077.5873.2
7. Agricultural Machinery Testing and Evaluation Center. (2001). *PAES 401:2001 Agricultural
   structures – Housing for swine production*. Bureau of Agricultural Research, Department of Agriculture.
   https://amtec.uplb.edu.ph/wp-content/uploads/2019/07/401.pdf
8. Fehr, R. L., & Huhnke, R. L. (1984). *Energy conservation in ventilating and heating swine buildings*
   (Extension Bulletin E-1760, Pork Industry Handbook). Michigan State University Cooperative Extension
   Service. https://sanweb.lib.msu.edu/DMC/extension_publications/E1760/e1760-1984.pdf
9. Liu, J.-H. (2025). *Swine welfare essentials: Heat stress, nutrients, and data collection* (Fact Sheet
   EXT-02-2025). University of Guam Cooperative Extension & Outreach.
   https://www.uog.edu/_resources/files/extension/2025-uog-extension-fact-sheet-swine-welfare-10-3-25.pdf
