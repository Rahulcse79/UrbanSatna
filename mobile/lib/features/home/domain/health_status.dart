/// Backend health as reported by GET /health.
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.database,
    required this.redis,
    required this.version,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    final checks = (json['checks'] as Map<String, dynamic>?) ?? const {};
    return HealthStatus(
      status: (json['status'] as String?) ?? 'unknown',
      database: (checks['database'] as String?) ?? 'unknown',
      redis: (checks['redis'] as String?) ?? 'unknown',
      version: (json['version'] as String?) ?? 'unknown',
    );
  }

  final String status;
  final String database;
  final String redis;
  final String version;

  bool get healthy => status == 'ok';
}
