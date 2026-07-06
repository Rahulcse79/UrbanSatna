import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class WorkerApplication {
  const WorkerApplication({
    required this.id,
    required this.status,
    required this.phone,
    required this.createdAt,
    this.fullName,
    this.skills,
    this.experience,
    this.note,
  });

  factory WorkerApplication.fromJson(Map<String, dynamic> json) =>
      WorkerApplication(
        id: json['id'] as String,
        status: json['status'] as String,
        phone: json['phone'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        fullName: json['full_name'] as String?,
        skills: json['skills'] as String?,
        experience: json['experience'] as String?,
        note: json['note'] as String?,
      );

  final String id;
  final String status;
  final String phone;
  final DateTime createdAt;
  final String? fullName;
  final String? skills;
  final String? experience;
  final String? note;

  bool get pending => status == 'pending';
  bool get approved => status == 'approved';
  bool get rejected => status == 'rejected';
}

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return WorkerRepository(ref.watch(dioProvider));
});

/// The signed-in user's latest application (null when never applied).
final myWorkerApplicationProvider =
    FutureProvider.autoDispose<WorkerApplication?>((ref) async {
  return ref.watch(workerRepositoryProvider).myApplication();
});

/// Admin verification queue.
final pendingApplicationsProvider =
    FutureProvider.autoDispose<List<WorkerApplication>>((ref) {
  return ref.watch(workerRepositoryProvider).pendingApplications();
});

class WorkerRepository {
  const WorkerRepository(this._dio);

  final Dio _dio;

  Future<WorkerApplication> apply({
    String? skills,
    String? experience,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/me/worker-application',
      data: {
        if (skills != null && skills.isNotEmpty) 'skills': skills,
        if (experience != null && experience.isNotEmpty)
          'experience': experience,
      },
    );
    return WorkerApplication.fromJson(
        unwrapEnvelope(res) as Map<String, dynamic>);
  }

  Future<WorkerApplication?> myApplication() async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/v1/me/worker-application');
    final data = unwrapEnvelope(res);
    if (data == null) return null;
    return WorkerApplication.fromJson(data as Map<String, dynamic>);
  }

  Future<List<WorkerApplication>> pendingApplications() async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/admin/worker-applications?status=pending');
    final data = unwrapEnvelope(res) as List<dynamic>;
    return data
        .map((a) => WorkerApplication.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<void> decide(String id, {required bool approve, String? note}) =>
      _dio.post('/api/v1/admin/worker-applications/$id/decide', data: {
        'approve': approve,
        if (note != null && note.isNotEmpty) 'note': note,
      });
}
