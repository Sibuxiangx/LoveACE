class AnalyticsConfig {
  AnalyticsConfig._();

  static const String endpoint = String.fromEnvironment(
    'ANALYTICS_ENDPOINT',
    defaultValue: 'https://analyst-api.linota.cn/v1/events',
  );

  static const String apiKey = String.fromEnvironment('ANALYTICS_API_KEY');

  static const String signingSecret = String.fromEnvironment('ANALYTICS_SIGNING_SECRET');

  static const String hashSalt = String.fromEnvironment('ANALYTICS_HASH_SALT');
}
