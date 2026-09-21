enum RevelationType {
  makki,
  madani,
}

class SurahModel {
  final int number;
  final String nameArabic;
  final String nameEnglish;
  final String transliteration;
  final int ayahCount;
  final RevelationType revelationType;
  final int revelationOrder;

  const SurahModel({
    required this.number,
    required this.nameArabic,
    required this.nameEnglish,
    required this.transliteration,
    required this.ayahCount,
    required this.revelationType,
    required this.revelationOrder,
  });

  String get revelationPlace {
    return revelationType == RevelationType.makki ? 'Makki' : 'Madani';
  }
}
