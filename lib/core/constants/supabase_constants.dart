class SupabaseConstants {
  static const String url = 'https://supabase.pauserdistribucionessac.com';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzcyODU5NjAwLCJleHAiOjE5MzA2MjYwMDB9.kRsHdYxiP9wHzNcfx5g1vM0ZbyU-XdvU6Gb2WhVzE4s';

  /// Normaliza URLs de storage: reemplaza cualquier variante de IP:puerto por el dominio correcto.
  static String fixStorageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    return rawUrl
        .replaceFirst('https://161.132.48.71:8443', url)
        .replaceFirst('http://161.132.48.71:8000', url);
  }
}
