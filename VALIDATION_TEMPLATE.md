# Validation protocol (for Chapter 4)

Use the dashboard's **Tools → Download CSV** for device data, and record the reference readings by hand in the table below.

## Setup
- Subjects: at least 10 volunteers, with signed consent (get ethics approval from your supervisor/department first).
- References: commercial fingertip pulse oximeter (HR + SpO₂), clinical/medical thermometer, and ideally a reference ECG or chest-strap HR monitor.
- Conditions per subject: **rest** (5 min seated) and **after exercise** (e.g. 2 min stair climb). Take 3 readings per condition.
- Keep the sensor placement, finger pressure, ambient temperature and thermometer site identical every time.
- The sensors are not SpO₂-valid below about 90 %. Healthy volunteers will mostly sit at 95–100 %, so your calibration range is narrow. State that as a limitation.

## Data sheet
| Subject | Condition | Ref HR | Device HR (PPG) | Device HR (ECG) | Ref SpO₂ | Device SpO₂ | Ref temp °C | Device temp °C |
|---|---|---|---|---|---|---|---|---|
| 1 | Rest | | | | | | | |
| 1 | Exercise | | | | | | | |

## Analysis to report
For each of HR (PPG), HR (ECG), SpO₂ and temperature:
- Mean error (bias) and standard deviation
- RMSE
- Bland–Altman plot (difference vs. mean, with limits of agreement)
- Correlation (Pearson r) and a scatter plot with the line of identity

## Calibration procedure
1. Collect paired readings (device raw vs. reference). On the Tools tab the live `R` value and raw temperature are displayed.
2. SpO₂: fit `SpO₂ = A − B·R` by linear regression of the reference SpO₂ against `R`, then enter A and B.
3. Temperature: set the offset to the mean of (reference − raw device) readings.
4. Re-run the test on **new** data and report the errors before and after calibration.
