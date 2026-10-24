enum IssueStatus {
  reported,
  verified,
  verificationRequested,
  assigned,
  inProgress,
  resolved,
  rejected
}

extension IssueStatusLabel on IssueStatus {
  String get label {
    switch (this) {
      case IssueStatus.reported:
        return 'Reported';
      case IssueStatus.verified:
        return 'Verified';
      case IssueStatus.verificationRequested:
        return 'Verification requested';
      case IssueStatus.assigned:
        return 'Assigned';
      case IssueStatus.inProgress:
        return 'In Progress';
      case IssueStatus.resolved:
        return 'Resolved';
      case IssueStatus.rejected:
        return 'Rejected';
    }
  }
}

class CampusIssue {
  CampusIssue({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.reporter,
    this.status = IssueStatus.reported,
    this.severity = 'Medium',
    this.affectedCount = 1,
    this.isAnonymous = false,
    this.assignedTo = '',
    this.assignedToName = '',
    this.verificationAssignedTo = '',
    this.verificationAssignedToName = '',
    this.verificationNote = '',
    this.reporterUid = '',
    this.imageUrl,
    this.building = '',
    this.floor = '',
    this.room = '',
    this.department = '',
    this.priorityOverride = '',
    this.resolutionSummary = '',
    this.resolutionPhotoUrl = '',
    this.expectedBy,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
    this.history = const [],
    this.deletionRequestStatus = '',
    this.following = false,
    this.verificationVotes = const {},
    this.verificationCount = 0,
    this.stillExistsVotes = 0,
  });

  final String id;
  String title;
  String description;
  String category;
  String location;
  String reporter;
  IssueStatus status;
  String severity;
  int affectedCount;
  bool isAnonymous;
  String assignedTo;
  String assignedToName;
  String verificationAssignedTo;
  String verificationAssignedToName;
  String verificationNote;
  String reporterUid;
  String? imageUrl;
  String building;
  String floor;
  String room;
  String department;
  String priorityOverride;
  String resolutionSummary;
  String resolutionPhotoUrl;
  DateTime? expectedBy;
  DateTime? resolvedAt;
  DateTime? createdAt;
  DateTime? updatedAt;
  List<String> history;
  String deletionRequestStatus;
  bool following;
  Map<String, String> verificationVotes;
  int verificationCount;
  int stillExistsVotes;

  bool get isOpen =>
      status != IssueStatus.resolved && status != IssueStatus.rejected;

  String get assigneeDisplayName =>
      assignedToName.trim().isNotEmpty && assignedToName.trim() != assignedTo
          ? assignedToName.trim()
          : 'Maintenance staff';

  String get verifierDisplayName =>
      verificationAssignedToName.trim().isNotEmpty &&
              verificationAssignedToName.trim() != verificationAssignedTo
          ? verificationAssignedToName.trim()
          : 'Staff member';

  int get priorityScore {
    final severityScore = switch (severity.toLowerCase()) {
      'urgent' => 40,
      'high' => 30,
      'medium' => 20,
      _ => 10,
    };
    final impactScore = (affectedCount - 1).clamp(0, 5).toInt() * 3;
    final ageHours =
        DateTime.now().difference(createdAt ?? DateTime.now()).inHours;
    final ageScore = ageHours >= 48
        ? 15
        : ageHours >= 24
            ? 10
            : ageHours >= 8
                ? 5
                : 0;
    return severityScore + impactScore + ageScore;
  }

  String get priority => priorityOverride.isNotEmpty
      ? priorityOverride
      : priorityScore >= 40
          ? 'Urgent'
          : priorityScore >= 30
              ? 'High'
              : priorityScore >= 20
                  ? 'Medium'
                  : 'Low';

  bool get hasBreachedSla =>
      isOpen && expectedBy != null && DateTime.now().isAfter(expectedBy!);

  bool get hasMajorityStillExistsVotes => stillExistsVotes * 2 > affectedCount;
}
