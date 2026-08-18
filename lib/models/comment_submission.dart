import 'package:safezone/models/report_comment.dart';

enum CommentSubmissionFailure {
  none,
  empty,
  missingProfile,
  missingPublication,
  authentication,
  schema,
  timeout,
  backend,
}

class CommentSubmissionResult {
  const CommentSubmissionResult.success(this.comment)
    : failure = CommentSubmissionFailure.none,
      message = 'Comentario publicado';

  const CommentSubmissionResult.failure({
    required this.failure,
    required this.message,
  }) : comment = null;

  final ReportComment? comment;
  final CommentSubmissionFailure failure;
  final String message;

  bool get isSuccess => failure == CommentSubmissionFailure.none;
}
