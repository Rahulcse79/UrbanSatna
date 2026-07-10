import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class WorkerApplication {
  const WorkerApplication({
    required this.id,
    required this.status,
    required this.phone,
    required this.createdAt,
    this.userId,
    this.fullName,
    this.skills,
    this.experience,
    this.note,
    this.hasKycDoc = false,
    this.hasKycSelfie = false,
  });

  factory WorkerApplication.fromJson(Map<String, dynamic> json) =>
      WorkerApplication(
        id: json['id'] as String,
        status: json['status'] as String,
        phone: json['phone'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        userId: json['user_id'] as String?,
        fullName: json['full_name'] as String?,
        skills: json['skills'] as String?,
        experience: json['experience'] as String?,
        note: json['note'] as String?,
        hasKycDoc: json['has_kyc_doc'] as bool? ?? false,
        hasKycSelfie: json['has_kyc_selfie'] as bool? ?? false,
      );

  final String id;
  final String status;
  final String phone;
  final DateTime createdAt;
  final String? userId;
  final String? fullName;
  final String? skills;
  final String? experience;
  final String? note;
  final bool hasKycDoc;
  final bool hasKycSelfie;

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

/// One page of the admin verification queue.
typedef ApplicationsPage = ({
  List<WorkerApplication> items,
  int total,
  int page
});

/// Admin verification queue keyed by page — server paginates 10/page.
final pendingApplicationsProvider = FutureProvider.autoDispose
    .family<ApplicationsPage, int>((ref, page) {
  return ref.watch(workerRepositoryProvider).pendingApplications(page);
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

  Future<ApplicationsPage> pendingApplications(int page) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/admin/worker-applications?status=pending&page=$page');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return (
      items: (data['items'] as List<dynamic>)
          .map((a) => WorkerApplication.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      page: data['page'] as int,
    );
  }

  /// Admin: a user's profile photo; null when unset.
  Future<Uint8List?> userAvatar(String userId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/api/v1/admin/users/$userId/avatar',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException {
      return null;
    }
  }

  Future<void> decide(String id, {required bool approve, String? note}) =>
      _dio.post('/api/v1/admin/worker-applications/$id/decide', data: {
        'approve': approve,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  /// Attach a KYC photo ("doc" | "selfie") to the pending application.
  Future<void> uploadKyc(String kind, Uint8List bytes, String mime) =>
      _dio.post(
        '/api/v1/me/worker-application/kyc/$kind',
        data: Stream.fromIterable([bytes]),
        options: Options(
          contentType: mime,
          headers: {Headers.contentLengthHeader: bytes.length},
        ),
      );

  /// Admin: fetch a KYC photo for review; null when not uploaded.
  Future<Uint8List?> kycImage(String applicationId, String kind) async {
    try {
      final res = await _dio.get<List<int>>(
        '/api/v1/admin/worker-applications/$applicationId/kyc/$kind',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException {
      return null;
    }
  }
}
