/// Modelo de datos para un comentario en un reporte del muro
class ReportComment {
  final String id;
  final String reportId;
  final String userCode;
  final String content;
  final DateTime createdAt;

  ReportComment({
    required this.id,
    required this.reportId,
    required this.userCode,
    required this.content,
    required this.createdAt,
  });

  factory ReportComment.fromMap(Map<String, dynamic> map) {
    return ReportComment(
      id: map['id'] as String,
      reportId: map['report_id'] as String,
      userCode: map['user_code'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'report_id': reportId,
      'user_code': userCode,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
