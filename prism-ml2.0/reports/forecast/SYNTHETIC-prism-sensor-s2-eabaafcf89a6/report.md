# B2 forecasting experiment: PIPELINE TEST ONLY, NOT VALID RESULTS

> **PIPELINE TEST ONLY, NOT VALID RESULTS.** Built from synthetic fixtures to check that the code runs. Do not cite any number below.

- Status: **completed**
- Dataset version: `SYNTHETIC-prism-sensor-s2-eabaafcf89a6`
- Config: `forecast-1.0.0` (sha256 0656bec74ce7)
- Seed: 42; target: thi (delta); horizons: [30, 60, 120] min
- Software: {'python': '3.13.1', 'scikit-learn': '1.8.0', 'numpy': '2.4.4', 'pandas': '3.0.2'}

## Data (PIPELINE TEST ONLY, NOT VALID RESULTS)

- Independent days (≥ 50% usable target bins): **40** (required 31)
- Data summary: `{"raw_records": 23004, "records_with_trusted_time_not_duplicate": 23004, "schema_versions": {"2": 23004}, "usable_dht_temp_c_records": 22926, "usable_dht_humidity_pct_records": 20666, "pens": ["SYN-pen1", "SYN-pen2"], "misting_logged": true}`

## Conclusion (PIPELINE TEST ONLY, NOT VALID RESULTS)

- [PIPELINE TEST ONLY, NOT VALID RESULTS] 30 min: best candidate (chosen on validation) random_forest test MAE 0.4103 vs best baseline (chosen on validation) ridge test MAE 0.4009; difference 0.0094 (95% CI [-0.0044, 0.0213]). Lower MAE than the best baseline: no. Candidates whose MAE-difference CI is entirely below zero: none.
- [PIPELINE TEST ONLY, NOT VALID RESULTS] 60 min: best candidate (chosen on validation) gradient_boosting test MAE 0.4762 vs best baseline (chosen on validation) ridge test MAE 0.4644; difference 0.0118 (95% CI [-0.0061, 0.0289]). Lower MAE than the best baseline: no. Candidates whose MAE-difference CI is entirely below zero: none.
- [PIPELINE TEST ONLY, NOT VALID RESULTS] 120 min: best candidate (chosen on validation) gradient_boosting test MAE 0.5447 vs best baseline (chosen on validation) ridge test MAE 0.504; difference 0.0407 (95% CI [0.024, 0.057]). Lower MAE than the best baseline: no. Candidates whose MAE-difference CI is entirely below zero: none.

Any candidate beat the best baseline (MAE-difference CI below zero) at any horizon: **no**

## Acceptance (PIPELINE TEST ONLY, NOT VALID RESULTS)

- Allowed to enable: **no**: synthetic data: pipeline test only, no model may be enabled

## Horizon 30 min (PIPELINE TEST ONLY, NOT VALID RESULTS)

- Rows: dev 16854, test 2639; independent test days 7; gap 30 min; test period from 2026-09-02T16:00:00+00:00
- Best baseline (validation): ridge; best candidate (validation): random_forest

| model | chosen params | mean val MAE | test MAE [95% CI] | test RMSE [95% CI] | MAE − best baseline [95% CI] | hottest-hours MAE |
|---|---|---|---|---|---|---|
| persistence | `{}` | 0.623 | 0.6093 [0.5868, 0.6311] | 0.7442 [0.7198, 0.7651] | 0.2084 [0.187, 0.2319] | 0.42 |
| same_time_yesterday | `{}` | 0.8119 | 0.6937 [0.6024, 0.7766] | 0.8598 [0.7663, 0.9389] | 0.2928 [0.1927, 0.3863] | 0.7117 |
| ridge | `{"alpha": 1.0}` | 0.4163 | 0.4009 [0.3761, 0.427] | 0.5035 [0.4724, 0.5324] | 0.0 [0.0, 0.0] | 0.3554 |
| decision_tree | `{"max_depth": 5, "min_samples_leaf": 20}` | 0.4388 | 0.4261 [0.3999, 0.4488] | 0.5339 [0.5079, 0.5602] | 0.0252 [0.014, 0.0378] | 0.4025 |
| random_forest | `{"max_depth": 8, "min_samples_leaf": 10, "n_estimators": 100}` | 0.4199 | 0.4103 [0.38, 0.4389] | 0.5153 [0.4839, 0.5476] | 0.0094 [-0.0044, 0.0213] | 0.3972 |
| gradient_boosting | `{"learning_rate": 0.1, "max_depth": 3, "max_iter": 200}` | 0.4207 | 0.402 [0.3691, 0.4337] | 0.5043 [0.4705, 0.5377] | 0.0011 [-0.0091, 0.0115] | 0.3814 |

Hottest hours (local, from training data): [13, 14, 15, 16]

Alert (THI ≥ 80.0 within 30 min): rows where THI < threshold at t; actual = any measured THI in (t, t+h] >= threshold; predicted = forecast for t+h >= threshold. Crossing events in test: 14.

| model | TN | FP | FN | TP | precision | recall [CI] | F1 [CI] | alerts/day | median lead min | lead gained vs persistence |
|---|---|---|---|---|---|---|---|---|---|---|
| persistence | 2447 | 0 | 61 | 0 | – | 0.0 [0.0, 0.0] | 0.0 [0.0, 0.0] | 0.0 | – | – |
| same_time_yesterday | 2400 | 47 | 48 | 13 | 0.2167 | 0.2131 [0.0, 0.6333] | 0.2149 [0.0, 0.343] | 1.571 | 30.0 | 30.0 |
| ridge | 2443 | 4 | 54 | 7 | 0.6364 | 0.1148 [0.0, 0.3339] | 0.1944 [0.0, 0.5] | 0.714 | 15.0 | 15.0 |
| decision_tree | 2437 | 10 | 52 | 9 | 0.4737 | 0.1475 [0.0, 0.2963] | 0.225 [0.0, 0.4] | 1.714 | 20.0 | 20.0 |
| random_forest | 2440 | 7 | 56 | 5 | 0.4167 | 0.082 [0.0123, 0.1429] | 0.137 [0.022, 0.2353] | 1.429 | 12.5 | 12.5 |
| gradient_boosting | 2442 | 5 | 56 | 5 | 0.5 | 0.082 [0.0, 0.2292] | 0.1408 [0.0, 0.3438] | 1.0 | 10.0 | 10.0 |

Error analysis (test MAE): 'weather' uses pen conditions measured by the DHT22 (terciles from development data); no external weather data is logged in PRISM.

*by_time_of_day_local*

| group | n | ridge | random_forest | persistence |
|---|---|---|---|---|
| 00-04h | 116 | 0.3826 | 0.428 | 0.5346 |
| 04-08h | 256 | 0.4476 | 0.435 | 0.73 |
| 08-12h | 578 | 0.4335 | 0.3572 | 0.652 |
| 12-16h | 660 | 0.3521 | 0.3915 | 0.4794 |
| 16-20h | 661 | 0.3886 | 0.4351 | 0.6106 |
| 20-24h | 368 | 0.4322 | 0.4601 | 0.7125 |

*by_pen_air_temperature*

| group | n | ridge | random_forest | persistence |
|---|---|---|---|---|
| high (>=27.6) | 197 | 0.371 | 0.427 | 0.4607 |
| low (<24.6) | 1576 | 0.4277 | 0.4315 | 0.6511 |
| mid (24.6-27.6) | 866 | 0.3587 | 0.3679 | 0.567 |

*by_pen_humidity*

| group | n | ridge | random_forest | persistence |
|---|---|---|---|---|
| high (>=91.3) | 1614 | 0.4244 | 0.4289 | 0.6513 |
| low (<84.8) | 192 | 0.3614 | 0.4028 | 0.4384 |
| mid (84.8-91.3) | 833 | 0.3644 | 0.3759 | 0.5674 |

*by_recent_sensor_fault*

| group | n | ridge | random_forest | persistence |
|---|---|---|---|---|
| fault in last window | 221 | 0.4561 | 0.3902 | 0.6675 |
| no fault | 2418 | 0.3958 | 0.4121 | 0.604 |

*by_misting_state*

| group | n | ridge | random_forest | persistence |
|---|---|---|---|---|
| misting off | 2597 | 0.4031 | 0.4117 | 0.6045 |
| misting on | 42 | 0.2611 | 0.322 | 0.9069 |

Held-out pen: {"possible": true, "pens": {"SYN-pen1": {"n_test": 949, "persistence": 0.6004, "same_time_yesterday": 0.735, "ridge": 0.4449, "decision_tree": 0.4503, "random_forest": 0.4489, "gradient_boosting": 0.4629}, "SYN-pen2": {"n_test": 1690, "persistence": 0.6143, "same_time_yesterday": 0.6705, "ridge": 0.3848, "decision_tree": 0.4255, "random_forest": 0.3991, "gradient_boosting": 0.399}}, "note": "models trained on the other pens' development data, scored on the held-out pen's test period"}

## Horizon 60 min (PIPELINE TEST ONLY, NOT VALID RESULTS)

- Rows: dev 16755, test 2585; independent test days 7; gap 60 min; test period from 2026-09-02T16:00:00+00:00
- Best baseline (validation): ridge; best candidate (validation): gradient_boosting

| model | chosen params | mean val MAE | test MAE [95% CI] | test RMSE [95% CI] | MAE − best baseline [95% CI] | hottest-hours MAE |
|---|---|---|---|---|---|---|
| persistence | `{}` | 1.0277 | 1.0043 [0.9658, 1.0453] | 1.1949 [1.1493, 1.245] | 0.5399 [0.5118, 0.5832] | 0.6616 |
| same_time_yesterday | `{}` | 0.8109 | 0.6932 [0.6096, 0.7715] | 0.8595 [0.7745, 0.9346] | 0.2288 [0.1119, 0.3278] | 0.7109 |
| ridge | `{"alpha": 1.0}` | 0.5 | 0.4644 [0.4284, 0.5109] | 0.5836 [0.5335, 0.6377] | 0.0 [0.0, 0.0] | 0.4281 |
| decision_tree | `{"max_depth": 5, "min_samples_leaf": 50}` | 0.5428 | 0.5185 [0.4849, 0.5625] | 0.6508 [0.6089, 0.7017] | 0.0541 [0.0355, 0.0741] | 0.4888 |
| random_forest | `{"max_depth": 16, "min_samples_leaf": 10, "n_estimators": 100}` | 0.5123 | 0.4847 [0.4439, 0.536] | 0.6097 [0.5602, 0.6642] | 0.0203 [-0.0091, 0.0432] | 0.4814 |
| gradient_boosting | `{"learning_rate": 0.05, "max_depth": 3, "max_iter": 200}` | 0.5111 | 0.4762 [0.439, 0.5313] | 0.5978 [0.5517, 0.6576] | 0.0118 [-0.0061, 0.0289] | 0.4754 |

Hottest hours (local, from training data): [13, 14, 15, 16]

Alert (THI ≥ 80.0 within 60 min): rows where THI < threshold at t; actual = any measured THI in (t, t+h] >= threshold; predicted = forecast for t+h >= threshold. Crossing events in test: 14.

| model | TN | FP | FN | TP | precision | recall [CI] | F1 [CI] | alerts/day | median lead min | lead gained vs persistence |
|---|---|---|---|---|---|---|---|---|---|---|
| persistence | 2353 | 0 | 101 | 0 | – | 0.0 [0.0, 0.0] | 0.0 [0.0, 0.0] | 0.0 | – | – |
| same_time_yesterday | 2313 | 40 | 74 | 27 | 0.403 | 0.2673 [0.0489, 0.6402] | 0.3214 [0.0908, 0.4648] | 1.714 | 45.0 | 45.0 |
| ridge | 2353 | 0 | 88 | 13 | 1.0 | 0.1287 [0.0, 0.3134] | 0.2281 [0.0, 0.4773] | 0.429 | 35.0 | 35.0 |
| decision_tree | 2351 | 2 | 72 | 29 | 0.9355 | 0.2871 [0.1621, 0.4464] | 0.4394 [0.2714, 0.6137] | 2.857 | 42.5 | 42.5 |
| random_forest | 2353 | 0 | 91 | 10 | 1.0 | 0.099 [0.0, 0.2683] | 0.1802 [0.0, 0.4231] | 0.714 | 40.0 | 40.0 |
| gradient_boosting | 2353 | 0 | 85 | 16 | 1.0 | 0.1584 [0.0337, 0.3384] | 0.2735 [0.0652, 0.5057] | 1.429 | 27.5 | 27.5 |

Error analysis (test MAE): 'weather' uses pen conditions measured by the DHT22 (terciles from development data); no external weather data is logged in PRISM.

*by_time_of_day_local*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| 00-04h | 94 | 0.4787 | 0.4578 | 0.819 |
| 04-08h | 274 | 0.506 | 0.4556 | 1.2886 |
| 08-12h | 581 | 0.4476 | 0.4034 | 1.0574 |
| 12-16h | 662 | 0.4281 | 0.4754 | 0.6616 |
| 16-20h | 657 | 0.4749 | 0.5291 | 1.0975 |
| 20-24h | 317 | 0.5089 | 0.5246 | 1.2387 |

*by_pen_air_temperature*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| high (>=27.6) | 197 | 0.4333 | 0.5221 | 0.6913 |
| low (<24.7) | 1567 | 0.4994 | 0.4978 | 1.0822 |
| mid (24.7-27.6) | 821 | 0.405 | 0.4238 | 0.9307 |

*by_pen_humidity*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| high (>=91.2) | 1580 | 0.5007 | 0.5017 | 1.089 |
| low (<84.8) | 191 | 0.4323 | 0.5157 | 0.6814 |
| mid (84.8-91.2) | 814 | 0.4015 | 0.4173 | 0.9157 |

*by_recent_sensor_fault*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| fault in last window | 240 | 0.4763 | 0.453 | 1.0752 |
| no fault | 2345 | 0.4632 | 0.4785 | 0.9971 |

*by_misting_state*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| misting off | 2543 | 0.4651 | 0.4766 | 0.9977 |
| misting on | 42 | 0.4203 | 0.4516 | 1.4034 |

Held-out pen: {"possible": true, "pens": {"SYN-pen1": {"n_test": 913, "persistence": 0.9338, "same_time_yesterday": 0.7346, "ridge": 0.5782, "decision_tree": 0.5967, "random_forest": 0.5648, "gradient_boosting": 0.5687}, "SYN-pen2": {"n_test": 1672, "persistence": 1.0428, "same_time_yesterday": 0.6705, "ridge": 0.4342, "decision_tree": 0.5008, "random_forest": 0.4598, "gradient_boosting": 0.4463}}, "note": "models trained on the other pens' development data, scored on the held-out pen's test period"}

## Horizon 120 min (PIPELINE TEST ONLY, NOT VALID RESULTS)

- Rows: dev 16577, test 2449; independent test days 7; gap 120 min; test period from 2026-09-02T16:00:00+00:00
- Best baseline (validation): ridge; best candidate (validation): gradient_boosting

| model | chosen params | mean val MAE | test MAE [95% CI] | test RMSE [95% CI] | MAE − best baseline [95% CI] | hottest-hours MAE |
|---|---|---|---|---|---|---|
| persistence | `{}` | 1.8641 | 1.8135 [1.7508, 1.8847] | 2.0693 [2.0029, 2.1477] | 1.3095 [1.2507, 1.3856] | 1.024 |
| same_time_yesterday | `{}` | 0.8062 | 0.6995 [0.6231, 0.7706] | 0.8669 [0.787, 0.9397] | 0.1955 [0.116, 0.2729] | 0.7112 |
| ridge | `{"alpha": 1.0}` | 0.5601 | 0.504 [0.4746, 0.5316] | 0.6351 [0.5887, 0.674] | 0.0 [0.0, 0.0] | 0.4409 |
| decision_tree | `{"max_depth": 8, "min_samples_leaf": 50}` | 0.6301 | 0.6122 [0.5919, 0.6296] | 0.7744 [0.7383, 0.8046] | 0.1082 [0.0908, 0.1308] | 0.5449 |
| random_forest | `{"max_depth": 16, "min_samples_leaf": 10, "n_estimators": 100}` | 0.5821 | 0.5571 [0.5229, 0.5867] | 0.7044 [0.6601, 0.7462] | 0.0531 [0.0283, 0.0781] | 0.5069 |
| gradient_boosting | `{"learning_rate": 0.05, "max_depth": 3, "max_iter": 200}` | 0.5803 | 0.5447 [0.5174, 0.5713] | 0.6814 [0.645, 0.7105] | 0.0407 [0.024, 0.057] | 0.4984 |

Hottest hours (local, from training data): [13, 14, 15, 16]

Alert (THI ≥ 80.0 within 120 min): rows where THI < threshold at t; actual = any measured THI in (t, t+h] >= threshold; predicted = forecast for t+h >= threshold. Crossing events in test: 14.

| model | TN | FP | FN | TP | precision | recall [CI] | F1 [CI] | alerts/day | median lead min | lead gained vs persistence |
|---|---|---|---|---|---|---|---|---|---|---|
| persistence | 2156 | 0 | 161 | 0 | – | 0.0 [0.0, 0.0] | 0.0 [0.0, 0.0] | 0.0 | – | – |
| same_time_yesterday | 2131 | 25 | 98 | 63 | 0.7159 | 0.3913 [0.1311, 0.6945] | 0.506 [0.2318, 0.6646] | 1.857 | 105.0 | 105.0 |
| ridge | 2156 | 0 | 139 | 22 | 1.0 | 0.1366 [0.0, 0.3258] | 0.2404 [0.0, 0.4914] | 1.143 | 65.0 | 65.0 |
| decision_tree | 2154 | 2 | 127 | 34 | 0.9444 | 0.2112 [0.1267, 0.2961] | 0.3452 [0.2181, 0.4569] | 2.714 | 90.0 | 90.0 |
| random_forest | 2156 | 0 | 138 | 23 | 1.0 | 0.1429 [0.0476, 0.2535] | 0.25 [0.0909, 0.4045] | 2.143 | 97.5 | 97.5 |
| gradient_boosting | 2156 | 0 | 134 | 27 | 1.0 | 0.1677 [0.0201, 0.3398] | 0.2872 [0.0393, 0.5073] | 1.286 | 55.0 | 55.0 |

Error analysis (test MAE): 'weather' uses pen conditions measured by the DHT22 (terciles from development data); no external weather data is logged in PRISM.

*by_time_of_day_local*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| 00-04h | 76 | 0.7544 | 0.7871 | 1.008 |
| 04-08h | 275 | 0.5306 | 0.4987 | 2.587 |
| 08-12h | 578 | 0.4386 | 0.4491 | 1.9942 |
| 12-16h | 664 | 0.4439 | 0.5151 | 0.8561 |
| 16-20h | 584 | 0.5593 | 0.6352 | 2.2355 |
| 20-24h | 272 | 0.5742 | 0.6048 | 2.3036 |

*by_pen_air_temperature*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| high (>=27.6) | 197 | 0.5283 | 0.6225 | 1.2434 |
| low (<24.7) | 1430 | 0.5335 | 0.5566 | 1.9458 |
| mid (24.7-27.6) | 822 | 0.447 | 0.5054 | 1.72 |

*by_pen_humidity*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| high (>=91.1) | 1456 | 0.5275 | 0.5561 | 1.9394 |
| low (<84.7) | 182 | 0.5125 | 0.5945 | 1.2379 |
| mid (84.7-91.1) | 811 | 0.4599 | 0.5131 | 1.7167 |

*by_recent_sensor_fault*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| fault in last window | 240 | 0.5554 | 0.5386 | 2.2265 |
| no fault | 2209 | 0.4985 | 0.5454 | 1.7686 |

*by_misting_state*

| group | n | ridge | gradient_boosting | persistence |
|---|---|---|---|---|
| misting off | 2407 | 0.5046 | 0.5446 | 1.8131 |
| misting on | 42 | 0.4728 | 0.5513 | 1.833 |

Held-out pen: {"possible": true, "pens": {"SYN-pen1": {"n_test": 830, "persistence": 1.5561, "same_time_yesterday": 0.7484, "ridge": 0.6364, "decision_tree": 0.6556, "random_forest": 0.6326, "gradient_boosting": 0.5939}, "SYN-pen2": {"n_test": 1619, "persistence": 1.9454, "same_time_yesterday": 0.6744, "ridge": 0.4847, "decision_tree": 0.571, "random_forest": 0.5131, "gradient_boosting": 0.5336}}, "note": "models trained on the other pens' development data, scored on the held-out pen's test period"}

## Features

dht_temp_c_now, dht_temp_c_lag5m, dht_temp_c_lag10m, dht_temp_c_lag15m, dht_temp_c_lag30m, dht_temp_c_lag60m, dht_temp_c_rate15m_per_h, dht_temp_c_rate60m_per_h, dht_temp_c_roll30m_mean, dht_temp_c_roll30m_std, dht_temp_c_roll30m_min, dht_temp_c_roll30m_max, dht_temp_c_roll60m_mean, dht_temp_c_roll60m_std, dht_temp_c_roll60m_min, dht_temp_c_roll60m_max, dht_temp_c_roll180m_mean, dht_temp_c_roll180m_std, dht_temp_c_roll180m_min, dht_temp_c_roll180m_max, dht_humidity_pct_now, dht_humidity_pct_lag5m, dht_humidity_pct_lag10m, dht_humidity_pct_lag15m, dht_humidity_pct_lag30m, dht_humidity_pct_lag60m, dht_humidity_pct_rate15m_per_h, dht_humidity_pct_rate60m_per_h, dht_humidity_pct_roll30m_mean, dht_humidity_pct_roll30m_std, dht_humidity_pct_roll30m_min, dht_humidity_pct_roll30m_max, dht_humidity_pct_roll60m_mean, dht_humidity_pct_roll60m_std, dht_humidity_pct_roll60m_min, dht_humidity_pct_roll60m_max, dht_humidity_pct_roll180m_mean, dht_humidity_pct_roll180m_std, dht_humidity_pct_roll180m_min, dht_humidity_pct_roll180m_max, thi_now, thi_lag5m, thi_lag10m, thi_lag15m, thi_lag30m, thi_lag60m, thi_rate15m_per_h, thi_rate60m_per_h, thi_roll30m_mean, thi_roll30m_std, thi_roll30m_min, thi_roll30m_max, thi_roll60m_mean, thi_roll60m_std, thi_roll60m_min, thi_roll60m_max, thi_roll180m_mean, thi_roll180m_std, thi_roll180m_min, thi_roll180m_max, tod_sin, tod_cos, mist_on_now, mist_on_frac_60m, mist_active_s_now
