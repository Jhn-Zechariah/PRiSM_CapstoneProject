from risk import recommendation, risk_level, risk_levels


def test_bands(cfg):
    r = cfg["risk"]
    assert risk_level(r["needs_attention_above"], cfg) == "Good"          # at the upper limit is Good
    assert risk_level(r["needs_attention_above"] + 0.01, cfg) == "Needs Attention"
    assert risk_level(r["high_risk_at"] - 0.01, cfg) == "Needs Attention"
    assert risk_level(r["high_risk_at"], cfg) == "High Risk"
    assert risk_level(30.0, cfg) == "Good"


def test_cutoff_tied_to_normal_band(cfg):
    assert cfg["risk"]["needs_attention_above"] == cfg["normal_band"]["pigBodyTemp"]["max"]
    assert cfg["risk"]["high_risk_at"] > cfg["risk"]["needs_attention_above"]


def test_vectorised_matches_scalar(cfg):
    temps = [30, 37.0, 37.2, 38.5, 40]
    assert list(risk_levels(temps, cfg)) == [risk_level(t, cfg) for t in temps]


def test_recommendation_mentions_sprinkler(cfg):
    assert "sprinkler is currently running" in recommendation("Good", True, cfg)
    assert "diagnos" not in recommendation("High Risk", False, cfg).lower()
