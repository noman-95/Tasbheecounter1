import 'package:flutter/services.dart';

import '../models/ayah_model.dart';
import '../models/surah_model.dart';

class QuranService {
  static Future<void>? _loadingFuture;
  static List<SurahModel> _surahs = const [];
  static final Map<int, List<AyahModel>> _ayahs = <int, List<AyahModel>>{};

  static Future<void> loadQuran() {
    return _loadingFuture ??= _loadQuran();
  }

  static Future<void> _loadQuran() async {
    final sql = await rootBundle.loadString('assets/quran/quran.sql');
    final urduRaw = await rootBundle.loadString(
      'assets/translations/ur.qadri.txt',
    );

    final urdu = _parsePipeTranslations(urduRaw);
    final arabicNames = _parseArabicNames(sql);
    final englishNames = _englishNames;
    final ayahsBySurah = <int, List<AyahModel>>{};

    final rowPattern = RegExp(
      r"\((\d+),\s*(\d+),\s*(\d+),\s*'((?:[^']|'')*)'\)",
      multiLine: true,
    );

    for (final match in rowPattern.allMatches(sql)) {
      final globalNumber = int.parse(match.group(1)!);
      final surahNumber = int.parse(match.group(2)!);
      final ayahNumber = int.parse(match.group(3)!);
      final arabic = (match.group(4) ?? '').replaceAll("''", "'");

      ayahsBySurah.putIfAbsent(surahNumber, () => <AyahModel>[]).add(
        AyahModel(
          number: globalNumber,
          numberInSurah: ayahNumber,
          arabic: arabic,
          urduTranslation: urdu['$surahNumber:$ayahNumber'] ?? '',
        ),
      );
    }

    _ayahs
      ..clear()
      ..addAll(
        ayahsBySurah.map(
          (key, value) => MapEntry(key, List.unmodifiable(value)),
        ),
      );

    _surahs = List.unmodifiable(
      List.generate(114, (index) {
        final number = index + 1;
        final ayahs = _ayahs[number] ?? const <AyahModel>[];
        final englishName = englishNames[index];

        return SurahModel(
          number: number,
          nameArabic: arabicNames[number] ?? 'السورة $number',
          nameEnglish: englishName,
          transliteration: englishName,
          ayahCount: ayahs.length,
          revelationType: _madaniSurahs.contains(number)
              ? RevelationType.madani
              : RevelationType.makki,
          revelationOrder: number,
        );
      }),
    );
  }

  static List<SurahModel> getSurahs() => _surahs;

  static SurahModel? getSurah(int number) {
    for (final surah in _surahs) {
      if (surah.number == number) return surah;
    }
    return null;
  }

  static List<AyahModel> getAyahs(int surahNumber) {
    return _ayahs[surahNumber] ?? const <AyahModel>[];
  }

  static Map<String, String> _parsePipeTranslations(String raw) {
    final result = <String, String>{};

    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split('|');
      if (parts.length < 3) continue;

      final chapter = int.tryParse(parts[0].trim());
      final verse = int.tryParse(parts[1].trim());
      if (chapter == null || verse == null) continue;

      final text = parts.sublist(2).join('|').trim();
      if (text.isEmpty) continue;

      result['$chapter:$verse'] = text;
    }

    return result;
  }

  static Map<int, String> _parseArabicNames(String raw) {
    final result = <int, String>{};
    final pattern = RegExp(r'^-- Sura (\d+) \((.+)\)$', multiLine: true);
    for (final match in pattern.allMatches(raw)) {
      result[int.parse(match.group(1)!)] = match.group(2)!.trim();
    }
    return result;
  }

  static const Set<int> _madaniSurahs = {
    2, 3, 4, 5, 8, 9, 13, 22, 24, 33, 47, 48, 49, 55, 57, 58, 59, 60,
    61, 62, 63, 64, 65, 66, 76, 98, 110,
  };

  static const List<String> _englishNames = [
    'Al-Fatihah', 'Al-Baqarah', 'Aal-E-Imran', 'An-Nisa', 'Al-Maidah',
    'Al-Anam', 'Al-Araf', 'Al-Anfal', 'At-Tawbah', 'Yunus', 'Hud',
    'Yusuf', 'Ar-Rad', 'Ibrahim', 'Al-Hijr', 'An-Nahl', 'Al-Isra',
    'Al-Kahf', 'Maryam', 'Ta-Ha', 'Al-Anbiya', 'Al-Hajj', 'Al-Muminun',
    'An-Nur', 'Al-Furqan', 'Ash-Shuara', 'An-Naml', 'Al-Qasas', 'Al-Ankabut',
    'Ar-Rum', 'Luqman', 'As-Sajdah', 'Al-Ahzab', 'Saba', 'Fatir', 'Ya-Sin',
    'As-Saffat', 'Sad', 'Az-Zumar', 'Ghafir', 'Fussilat', 'Ash-Shura',
    'Az-Zukhruf', 'Ad-Dukhan', 'Al-Jathiyah', 'Al-Ahqaf', 'Muhammad',
    'Al-Fath', 'Al-Hujurat', 'Qaf', 'Adh-Dhariyat', 'At-Tur', 'An-Najm',
    'Al-Qamar', 'Ar-Rahman', 'Al-Waqiah', 'Al-Hadid', 'Al-Mujadilah',
    'Al-Hashr', 'Al-Mumtahanah', 'As-Saff', 'Al-Jumuah', 'Al-Munafiqun',
    'At-Taghabun', 'At-Talaq', 'At-Tahrim', 'Al-Mulk', 'Al-Qalam',
    'Al-Haqqah', 'Al-Maarij', 'Nuh', 'Al-Jinn', 'Al-Muzzammil', 'Al-Muddaththir',
    'Al-Qiyamah', 'Al-Insan', 'Al-Mursalat', 'An-Naba', 'An-Naziat', 'Abasa',
    'At-Takwir', 'Al-Infitar', 'Al-Mutaffifin', 'Al-Inshiqaq', 'Al-Buruj',
    'At-Tariq', 'Al-Ala', 'Al-Ghashiyah', 'Al-Fajr', 'Al-Balad', 'Ash-Shams',
    'Al-Lail', 'Ad-Duha', 'Ash-Sharh', 'At-Tin', 'Al-Alaq', 'Al-Qadr',
    'Al-Bayyinah', 'Az-Zalzalah', 'Al-Adiyat', 'Al-Qariah', 'At-Takathur',
    'Al-Asr', 'Al-Humazah', 'Al-Fil', 'Quraysh', 'Al-Maun', 'Al-Kawthar',
    'Al-Kafirun', 'An-Nasr', 'Al-Masad', 'Al-Ikhlas', 'Al-Falaq', 'An-Nas',
  ];
}
