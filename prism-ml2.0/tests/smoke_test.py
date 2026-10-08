"""Checks the trained models behave sensibly.  Run:  python -m tests.smoke_test"""
from app import predictor as p

def check(label, got, expected):
    ok = got == expected
    print(("PASS" if ok else "FAIL"), "-", label, "->", got, "" if ok else f"(expected {expected})")
    return ok

results = [
    check("cool & dry barn",        p.predict_farm(34.0, 24, 55)["status"], "Good"),
    check("hot & humid barn",       p.predict_farm(36.0, 36, 90)["status"], "High Risk"),
    check("hot barn + fever-like",  p.predict_farm(38.0, 33, 80)["status"], "High Risk"),
    check("on-curve 14-wk pig",     p.predict_pig_growth(98, 54.0, 47.5, 7)["status"], "Within Expected"),
    check("light 14-wk pig",        p.predict_pig_growth(98, 40.0, 35.0, 7)["status"], "Below Expected"),
    check("heavy 14-wk pig",        p.predict_pig_growth(98, 66.0, 59.0, 7)["status"], "Above Expected"),
    check("pig too young",          p.predict_pig_growth(10, 3.0, 2.0, 3)["status"], "Out of reference range"),
    check("pig too old",            p.predict_pig_growth(250, 180.0, 170.0, 7)["status"], "Out of reference range"),
]
print(f"\n{sum(results)}/{len(results)} checks passed")
