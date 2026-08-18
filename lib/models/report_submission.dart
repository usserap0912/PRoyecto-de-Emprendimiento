import 'package:safezone/models/report.dart';

class ReportCoordinates {
  final double latitude;
  final double longitude;

  const ReportCoordinates({required this.latitude, required this.longitude});
}

class ReportDraft {
  final String userCode;
  final int zone;
  final String category;
  final String description;
  final String severity;
  final double? latitude;
  final double? longitude;

  const ReportDraft({
    required this.userCode,
    required this.zone,
    required this.category,
    required this.description,
    required this.severity,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toInsertPayload({String? imageUrl, String? videoUrl}) {
    return <String, dynamic>{
      'user_code': userCode,
      'zone': zone,
      'category': category,
      'description': description,
      'tag': severity,
      'status': 'activo',
      'latitude': ?latitude,
      'longitude': ?longitude,
      'image_url': ?imageUrl,
      'video_url': ?videoUrl,
    };
  }
}

enum ReportSubmissionFailure {
  none,
  duplicate,
  invalidCategory,
  invalidSeverity,
  invalidZone,
  missingProfile,
  mediaUpload,
  authentication,
  rejected,
  schema,
  timeout,
  backendUnavailable,
  unknown,
}

class ReportSubmissionResult {
  final Report? report;
  final ReportSubmissionFailure failure;
  final String message;
  final String? technicalCode;

  const ReportSubmissionResult._({
    required this.failure,
    required this.message,
    this.report,
    this.technicalCode,
  });

  const ReportSubmissionResult.success(Report report)
    : this._(
        report: report,
        failure: ReportSubmissionFailure.none,
        message: 'Reporte enviado correctamente',
      );

  const ReportSubmissionResult.failure({
    required ReportSubmissionFailure failure,
    required String message,
    String? technicalCode,
  }) : this._(failure: failure, message: message, technicalCode: technicalCode);

  bool get isSuccess => failure == ReportSubmissionFailure.none;
}
