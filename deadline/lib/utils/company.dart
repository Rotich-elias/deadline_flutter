/// Company details shared by the About page and the footer credit.
class Company {
  const Company._();

  static const name = 'teto technologies';
  static const websiteLabel = 'teto.co.ke';
  static const websiteUrl = 'https://teto.co.ke';

  /// Where the latest APK is uploaded. The app checks this URL for changes;
  /// no version file or API is needed. Update this if the download moves.
  static const apkUrl = 'https://www.teto.co.ke/download/deadlines-notes';

  /// Public JSON feed of launch adverts published in the Teto admin console.
  static const advertUrl = 'https://www.teto.co.ke/api/adverts?app=deadlines-notes';
}
