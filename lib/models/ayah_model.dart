enum TranslationLanguage {
  english,
  urdu,
}

class AyahModel {
  final int number;
  final int numberInSurah;
  final String arabic;
  final String englishTranslation;
  final String urduTranslation;

  const AyahModel({
    required this.number,
    required this.numberInSurah,
    required this.arabic,
    this.englishTranslation = '',
    this.urduTranslation = '',
  });

  String audioUrlForSurah(int surahNumber) =>
      'https://the-quran-project.github.io/Quran-Audio/Data/1/${surahNumber}_$numberInSurah.mp3';

  String getTranslation(TranslationLanguage language) {
    switch (language) {
      case TranslationLanguage.english:
        return englishTranslation;
      case TranslationLanguage.urdu:
        return urduTranslation;
    }
  }
}
