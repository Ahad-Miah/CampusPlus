import 'package:cloud_firestore/cloud_firestore.dart';

class WorkUpdate {
  const WorkUpdate({
    required this.id,
    required this.authorName,
    required this.note,
    required this.completedSteps,
    required this.nextSteps,
    required this.createdAt,
    this.photoUrl,
  });

  final String id;
  final String authorName;
  final String note;
  final List<String> completedSteps;
  final List<String> nextSteps;
  final DateTime? createdAt;
  final String? photoUrl;

  factory WorkUpdate.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return WorkUpdate(
      id: id,
      authorName: data['authorName'] as String? ?? 'Staff member',
      note: data['note'] as String? ?? '',
      completedSteps:
          (data['completedSteps'] as List<dynamic>? ?? const []).cast<String>(),
      nextSteps:
          (data['nextSteps'] as List<dynamic>? ?? const []).cast<String>(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      photoUrl: data['photoUrl'] as String?,
    );
  }
}
