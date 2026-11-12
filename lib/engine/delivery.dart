// How an answer would land when spoken: length, pace, and the filler and
// hedge words that weaken it. Works on text, so it covers typed answers and
// answers dictated with Windows voice typing (Win+H).

/// Words that fill a pause.
const fillerWords = ['um', 'uh', 'er', 'like', 'you know', 'basically', 'actually', 'literally', 'i mean', 'sort of', 'kind of', 'so yeah', 'right'];

/// Words that undercut a claim.
const hedgeWords = ['i think', 'i guess', 'maybe', 'probably', 'just', 'a little', 'hopefully', 'i feel like', 'somewhat', 'try to', 'tried to'];

class Delivery {
  Delivery({required this.words, required this.seconds, required this.fillers, required this.hedges, this.longestPause, this.pauses});
  final int words;

  /// Time taken, or null when it was not timed.
  final int? seconds;
  final Map<String, int> fillers, hedges;

  /// For a spoken answer: the longest silence in seconds, and how many
  /// silences ran two seconds or more. Null for a typed answer.
  final int? longestPause, pauses;

  bool get spoken => longestPause != null;

  int get fillerCount => fillers.values.fold(0, (a, b) => a + b);
  int get hedgeCount => hedges.values.fold(0, (a, b) => a + b);

  /// Words per minute as delivered, when timed and long enough to mean something.
  int? get wpm => seconds == null || seconds! < 10 ? null : (words * 60 / seconds!).round();

  /// How long the answer runs at a steady speaking pace (140 words a minute).
  int get spokenSeconds => (words * 60 / 140).round();

  /// Short, plain observations, most important first; empty when all is well.
  List<String> get notes => [
        if (words < 60) 'Very short. Most interview answers need 60 to 120 seconds, about 140 to 280 words.',
        if (words >= 60 && spokenSeconds < 45) 'On the short side: about $spokenSeconds seconds spoken.',
        if (spokenSeconds > 150) 'Long: about ${(spokenSeconds / 60).toStringAsFixed(1)} minutes spoken. Cut to the action and the result.',
        if (wpm != null && wpm! > 175) 'Fast: $wpm words a minute. Aim for 130 to 160.',
        if (wpm != null && wpm! < 105 && seconds! >= 30) 'Slow: $wpm words a minute. Aim for 130 to 160.',
        if ((longestPause ?? 0) >= 5) 'Longest pause: $longestPause seconds. A breath is fine; past four seconds it reads as being stuck. Bridge with "What I did next was...".',
        if ((pauses ?? 0) >= 4) '$pauses pauses of two seconds or more. Knowing your first sentence for each part of the story removes most of them.',
        if (fillerCount >= 3) 'Fillers: ${_top(fillers)}.',
        if (hedgeCount >= 3) 'Hedges that weaken your claims: ${_top(hedges)}.',
      ];

  static String _top(Map<String, int> m) {
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return e.take(4).map((x) => '"${x.key}" ×${x.value}').join(', ');
  }

  Map<String, Object?> toJson() => {'words': words, 'seconds': seconds, 'wpm': wpm, 'fillers': fillerCount, 'hedges': hedgeCount, 'spoken': spoken, 'longestPause': longestPause, 'pauses': pauses};
}

Map<String, int> _count(String text, List<String> phrases) {
  final out = <String, int>{};
  for (final ph in phrases) {
    final n = RegExp('(?<![a-z\'])${RegExp.escape(ph)}(?![a-z\'])').allMatches(text).length;
    if (n > 0) out[ph] = n;
  }
  return out;
}

Delivery analyse(String answer, {int? seconds, int? longestPause, int? pauses}) {
  final text = answer.toLowerCase();
  final words = RegExp(r"[a-z0-9']+").allMatches(text).length;
  return Delivery(words: words, seconds: seconds, fillers: _count(text, fillerWords), hedges: _count(text, hedgeWords), longestPause: longestPause, pauses: pauses);
}

String clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
