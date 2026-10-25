import 'model/assessment.dart';
import 'model/assessment_ui_config.dart';

/// Evaluates the THI formula string from the rule config (GET /config/rules).
/// Only numbers, the named variables, + - * / ** and parentheses are accepted.
double evalFormula(String expr, Map<String, double> vars) {
  final p = _Parser(expr, vars);
  final v = p.expr();
  p.skipSpace();
  if (!p.done) throw FormatException('unexpected text at ${p.i} in formula');
  return v;
}

class _Parser {
  final String s;
  final Map<String, double> vars;
  int i = 0;
  _Parser(this.s, this.vars);

  bool get done => i >= s.length;
  void skipSpace() {
    while (!done && s[i].trim().isEmpty) {
      i++;
    }
  }

  bool eat(String tok) {
    skipSpace();
    if (s.startsWith(tok, i)) {
      i += tok.length;
      return true;
    }
    return false;
  }

  double expr() {
    var v = term();
    while (true) {
      if (eat('+')) {
        v += term();
      } else if (eat('-')) {
        v -= term();
      } else {
        return v;
      }
    }
  }

  double term() {
    var v = power();
    while (true) {
      skipSpace();
      if (s.startsWith('**', i)) return v;
      if (eat('*')) {
        v *= power();
      } else if (eat('/')) {
        v /= power();
      } else {
        return v;
      }
    }
  }

  double power() {
    final base = unary();
    if (eat('**')) {
      final exp = power();
      return _pow(base, exp);
    }
    return base;
  }

  double unary() {
    if (eat('-')) return -unary();
    if (eat('+')) return unary();
    return primary();
  }

  double primary() {
    skipSpace();
    if (eat('(')) {
      final v = expr();
      if (!eat(')')) throw const FormatException('missing )');
      return v;
    }
    final m = RegExp(r'\d+(\.\d+)?([eE][+-]?\d+)?|[A-Za-z_]\w*').matchAsPrefix(s, i);
    if (m == null) throw FormatException('unexpected text at $i in formula');
    i = m.end;
    final tok = m.group(0)!;
    final n = double.tryParse(tok);
    if (n != null) return n;
    final v = vars[tok];
    if (v == null) throw FormatException('unknown variable $tok');
    return v;
  }

  static double _pow(double b, double e) {
    var r = 1.0;
    if (e == e.roundToDouble() && e >= 0) {
      for (var k = 0; k < e; k++) {
        r *= b;
      }
      return r;
    }
    throw const FormatException('only whole non-negative exponents are supported');
  }
}

/// THI band computed on the phone from the cached rule config. Used ONLY when the
/// API is unreachable. Always method "rule", never a forecast, never stored.
Assessment localThiBand(Map<String, dynamic> rules, double? tempC, double? humidityPct,
    {DateTime? observedAt, required AssessmentUiConfig ui, required DateTime now}) {
  final thi = rules['thi'] as Map<String, dynamic>;
  final labels = Map<String, dynamic>.from(rules['labels']['status'] as Map);
  final category = thi['default_category'] as String;
  final inputs = [
    AssessmentInput(name: 'dht_temp_c', value: tempC, unit: 'degC', source: 'sensor', observedAt: observedAt),
    AssessmentInput(name: 'dht_humidity_pct', value: humidityPct, unit: '%RH', source: 'sensor', observedAt: observedAt),
  ];
  Assessment make(String status, List<String> reasons, String dq, {Map<String, dynamic> details = const {}}) =>
      Assessment(
        component: 'thi_band',
        status: status,
        statusLabel: (labels[status] ?? status).toString(),
        method: 'rule',
        reasons: reasons,
        inputs: inputs,
        dataQualityStatus: dq,
        warnings: [ui.t('states', 'local_fallback')],
        configWarnings: thi['formula_status'] == 'placeholder_pending_confirmation'
            ? ['THI formula is a placeholder pending confirmation']
            : const [],
        configVersion: rules['config_version'] as String,
        timestamp: now,
        disclaimer: rules['labels']['disclaimer'] as String,
        details: details,
        origin: 'phone',
      );

  if (tempC == null || humidityPct == null) {
    return make('insufficient_data', ['DHT22 temperature and humidity are both required.'], 'insufficient');
  }
  final imp = rules['impossible'] as Map<String, dynamic>;
  for (final e in {'dht_temp_c': tempC, 'dht_humidity_pct': humidityPct}.entries) {
    final r = (imp[e.key] as List).map((x) => (x as num).toDouble()).toList();
    if (e.value < r[0] || e.value > r[1]) {
      return make('unavailable', ['${e.key}=${e.value} is outside the possible range ${r[0]}..${r[1]}.'], 'invalid');
    }
  }
  final value = evalFormula(thi['formula'] as String, {'T': tempC, 'RH': humidityPct});
  final cat = (thi['categories'] as Map)[category] as Map?;
  final thresholds = (cat?['thresholds'] as List?)?.map((x) => (x as num).toDouble()).toList();
  final details = {'thi': double.parse(value.toStringAsFixed(2)), 'category': category};
  if (thresholds == null) {
    return make('not_configured', ['THI thresholds for $category are not set.'], 'ok', details: details);
  }
  final keys = List<String>.from(thi['band_keys'] as List);
  final idx = thresholds.where((t) => value >= t).length;
  final reason = idx == 0
      ? 'THI ${value.toStringAsFixed(1)} is below ${thresholds[0]}.'
      : 'THI ${value.toStringAsFixed(1)} is at or above ${thresholds[idx - 1]}.';
  return make(keys[idx], [reason], 'ok', details: details);
}
