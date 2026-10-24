import '../models/campus_issue.dart';

class DemoRepository {
  DemoRepository._();
  static final DemoRepository instance = DemoRepository._();

  final List<CampusIssue> issues = [
    CampusIssue(
      id: 'CP-1042',
      title: 'Broken lights in corridor',
      description: 'The corridor lights on the second floor are not working.',
      category: 'Electrical',
      location: 'Academic Building A · Floor 2',
      reporter: 'Student',
      status: IssueStatus.inProgress,
      severity: 'Medium',
      affectedCount: 12,
      assignedTo: 'Electrical Team',
      createdAt: DateTime.now().subtract(const Duration(hours: 18)),
      history: ['Reported · 18 hours ago', 'Verified · 16 hours ago', 'Assigned to Electrical Team · 14 hours ago', 'Work in progress'],
    ),
    CampusIssue(
      id: 'CP-1041',
      title: 'Water leakage near washroom',
      description: 'Water is collecting outside the washroom.',
      category: 'Plumbing',
      location: 'Science Building · Floor 1',
      reporter: 'Anonymous',
      isAnonymous: true,
      status: IssueStatus.verified,
      severity: 'High',
      affectedCount: 23,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      history: ['Reported · Yesterday', 'Verified · Yesterday'],
    ),
    CampusIssue(
      id: 'CP-1038',
      title: 'Broken classroom chair',
      description: 'One chair has a damaged leg in room 302.',
      category: 'Furniture',
      location: 'Academic Building B · Room 302',
      reporter: 'Student',
      status: IssueStatus.resolved,
      severity: 'Low',
      affectedCount: 4,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      history: ['Reported · 3 days ago', 'Verified · 3 days ago', 'Assigned · 2 days ago', 'Resolved · Yesterday'],
    ),
  ];

  void add(CampusIssue issue) => issues.insert(0, issue);
}
