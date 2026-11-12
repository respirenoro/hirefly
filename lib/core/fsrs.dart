// FSRS-6 memory maths for Terra's flashcards.
//
// Adapted from py-fsrs (https://github.com/open-spaced-repetition/py-fsrs,
// `fsrs/scheduler.py`, release v6.3.2, commit 9446cb06605c597a063aeee49f7d188d42e34dc2).
//
// MIT License
//
// Copyright (c) 2022 Open Spaced Repetition
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// What was adapted: the formulas (initial stability and difficulty, next
// difficulty, recall / forget / same-day stability, forgetting curve, interval,
// fuzz range), the 21 default weights and their lower and upper bounds. What is
// Terra's own: the weight validator and parser, the integer fuzz draw and the
// seeded random behind it (see `scheduler.dart`), and everything that deals
// with days. No Anki code is used (Anki is AGPL).
//
// Everything here is a pure function of numbers; it knows nothing about dates.
import 'dart:math' as math;

/// Number of weights in FSRS-6.
const int fsrsWeightCount = 21;

/// Default weights w0..w20. The FSRS algorithm wiki and py-fsrs agree on this
/// list. The pub.dev `fsrs` package ships a different one, so "FSRS-6 defaults"
/// is not one number set across ports; Terra pins this one.
const List<double> fsrsDefaultWeights = [
  0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, //
  0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
  0.0912, 0.0658, 0.1542,
];

/// Smallest stability ever stored (py-fsrs `STABILITY_MIN`).
const double stabilityMin = 0.001;

/// py-fsrs `LOWER_BOUNDS_PARAMETERS`.
const List<double> fsrsWeightLowerBounds = [
  stabilityMin, stabilityMin, stabilityMin, stabilityMin, 1.0, 0.001, 0.001, //
  0.001, 0.0, 0.0, 0.001, 0.001, 0.001, 0.001, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
  0.1,
];

/// py-fsrs `UPPER_BOUNDS_PARAMETERS` (`INITIAL_STABILITY_MAX` = 100).
const List<double> fsrsWeightUpperBounds = [
  100.0, 100.0, 100.0, 100.0, 10.0, 4.0, 4.0, 0.75, 4.5, 0.8, 3.5, 5.0, //
  0.25, 0.9, 4.0, 1.0, 6.0, 2.0, 2.0, 0.8, 0.8,
];

const double minDifficulty = 1.0;
const double maxDifficulty = 10.0;

/// Longest interval a Review card may be given, in days.
const int defaultMaximumInterval = 36500;

/// Outcome of checking a weight list.
class WeightsCheck {
  const WeightsCheck._(this.weights, this.problems);

  /// The accepted weights, or null when [problems] is not empty.
  final List<double>? weights;

  /// One human-readable reason per problem; empty when the list is fine.
  final List<String> problems;

  bool get isValid => problems.isEmpty;

  /// All reasons in one string, for an error dialog.
  String get message => problems.join('\n');
}

String _fmt(double v) {
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Checks a list of weights against FSRS-6's count and py-fsrs's bounds.
WeightsCheck validateWeights(List<double> weights) {
  if (weights.length != fsrsWeightCount) {
    final hint = switch (weights.length) {
      17 => ' (that looks like an FSRS-4 list)',
      19 => ' (that looks like an FSRS-5 list)',
      _ => '',
    };
    return WeightsCheck._(null, [
      'Expected $fsrsWeightCount weights for FSRS-6, got ${weights.length}$hint.',
    ]);
  }
  final problems = <String>[];
  for (var i = 0; i < fsrsWeightCount; i++) {
    final w = weights[i];
    if (!w.isFinite) {
      problems.add('w$i = $w is not a finite number.');
    } else if (w < fsrsWeightLowerBounds[i] || w > fsrsWeightUpperBounds[i]) {
      problems.add(
        'w$i = ${_fmt(w)} is out of bounds '
        '(${_fmt(fsrsWeightLowerBounds[i])} to ${_fmt(fsrsWeightUpperBounds[i])}).',
      );
    }
  }
  if (problems.isNotEmpty) return WeightsCheck._(null, problems);
  return WeightsCheck._(List.unmodifiable(weights), const []);
}

/// Reads pasted weights: numbers separated by commas, semicolons, spaces or
/// line breaks, optionally inside `[ ]` or `( )`, as the Anki optimizer and
/// FSRS tools print them. Rejects anything else with a reason.
WeightsCheck parseWeights(String text) {
  var body = text.trim();
  if (body.isEmpty) {
    return const WeightsCheck._(null, ['Nothing was pasted.']);
  }
  final open = body[0];
  final close = body[body.length - 1];
  if ((open == '[' && close == ']') || (open == '(' && close == ')')) {
    body = body.substring(1, body.length - 1);
  }
  final tokens = body.split(RegExp(r'[\s,;]+')).where((t) => t.isNotEmpty);
  final values = <double>[];
  final problems = <String>[];
  var n = 0;
  for (final token in tokens) {
    n++;
    final v = double.tryParse(token);
    if (v == null) {
      problems.add('"$token" (item $n) is not a number.');
    } else {
      values.add(v);
    }
  }
  if (problems.isNotEmpty) return WeightsCheck._(null, problems);
  return validateWeights(values);
}

/// The FSRS-6 formulas for one weight list. Immutable; build once, reuse.
class Fsrs {
  /// Throws [ArgumentError] (with the reasons) when [weights] fail
  /// [validateWeights].
  factory Fsrs(List<double> weights) {
    final check = validateWeights(weights);
    if (!check.isValid) throw ArgumentError(check.message);
    return Fsrs._(check.weights!);
  }

  Fsrs._(this.w)
      : _decay = -w[20],
        _factor = math.pow(0.9, 1 / -w[20]).toDouble() - 1;

  /// The 21 weights w0..w20.
  final List<double> w;
  final double _decay;
  final double _factor;

  /// Probability of recall after [elapsedDays] whole days at stability [s].
  double retrievability(int elapsedDays, double s) {
    final t = elapsedDays < 0 ? 0 : elapsedDays;
    return math.pow(1 + _factor * t / s, _decay).toDouble();
  }

  /// Days until recall falls to [desiredRetention], rounded to whole days,
  /// at least 1 and at most [maximumInterval].
  int nextInterval(double s, double desiredRetention, int maximumInterval) {
    final raw = s / _factor * (math.pow(desiredRetention, 1 / _decay) - 1);
    final days = raw.round();
    return math.min(math.max(days, 1), maximumInterval);
  }

  double _clampS(double s) => s < stabilityMin ? stabilityMin : s;

  double _clampD(double d) =>
      d < minDifficulty ? minDifficulty : (d > maxDifficulty ? maxDifficulty : d);

  /// Stability of a first review: w[rating-1]. [rating] is 1 to 4.
  double initialStability(int rating) => _clampS(w[rating - 1]);

  /// Difficulty of a first review. The Easy value used for mean reversion
  /// stays unclamped, as in py-fsrs.
  double initialDifficulty(int rating, {required bool clamp}) {
    final d = w[4] - math.exp(w[5] * (rating - 1)) + 1;
    return clamp ? _clampD(d) : d;
  }

  double nextDifficulty(double d, int rating) {
    final delta = -(w[6] * (rating - 3));
    final damped = d + (10.0 - d) * delta / 9.0;
    final reverted = w[7] * initialDifficulty(4, clamp: false) + (1 - w[7]) * damped;
    return _clampD(reverted);
  }

  /// Stability after a review on a later day.
  double nextStability(double d, double s, double r, int rating) {
    final next = rating == 1 ? _forgetStability(d, s, r) : _recallStability(d, s, r, rating);
    return _clampS(next);
  }

  double _forgetStability(double d, double s, double r) {
    final longTerm = w[11] *
        math.pow(d, -w[12]) *
        (math.pow(s + 1, w[13]) - 1) *
        math.exp((1 - r) * w[14]);
    final shortTerm = s / math.exp(w[17] * w[18]);
    return math.min(longTerm, shortTerm);
  }

  double _recallStability(double d, double s, double r, int rating) {
    final hardPenalty = rating == 2 ? w[15] : 1.0;
    final easyBonus = rating == 4 ? w[16] : 1.0;
    return s *
        (1 +
            math.exp(w[8]) *
                (11 - d) *
                math.pow(s, -w[9]) *
                (math.exp((1 - r) * w[10]) - 1) *
                hardPenalty *
                easyBonus);
  }

  /// Stability after a second (or later) review on the same day. Never lower
  /// than before when the answer was Hard, Good or Easy.
  double shortTermStability(double s, int rating) {
    var increase = math.exp(w[17] * (rating - 3 + w[18])) * math.pow(s, -w[19]);
    if (rating >= 2 && increase < 1.0) increase = 1.0;
    return _clampS(s * increase);
  }

  /// Fuzz range for a Review interval of [days] (py-fsrs `_get_fuzz_range`):
  /// bands 2.5-7 days at 15%, 7-20 at 10%, 20+ at 5%.
  (int, int) fuzzRange(int days, int maximumInterval) {
    const bands = [(2.5, 7.0, 0.15), (7.0, 20.0, 0.10), (20.0, double.infinity, 0.05)];
    var delta = 1.0;
    for (final (start, end, factor) in bands) {
      delta += factor * math.max(math.min(days.toDouble(), end) - start, 0.0);
    }
    var lo = (days - delta).round();
    var hi = (days + delta).round();
    lo = math.max(2, lo);
    hi = math.min(hi, maximumInterval);
    lo = math.min(lo, hi);
    return (lo, hi);
  }
}
