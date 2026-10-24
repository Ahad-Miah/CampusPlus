import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campus_plus/app.dart';
import 'package:campus_plus/models/campus_issue.dart';
import 'package:campus_plus/models/work_update.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('priority responds to severity and affected count', () {
    final issue = CampusIssue(
      id: 'CP-1',
      title: 'Broken light',
      description: 'A corridor light is broken.',
      category: 'Electrical',
      location: 'Main · 2 · 204',
      reporter: 'Anonymous',
      severity: 'Medium',
      createdAt: DateTime.now(),
    );
    expect(issue.priority, 'Medium');
    issue.severity = 'High';
    expect(issue.priority, 'High');
    issue.affectedCount = 5;
    expect(issue.priority, 'Urgent');
    issue.priorityOverride = 'Low';
    expect(issue.priority, 'Low');
  });

  test('SLA is breached only after the expected response time', () {
    final issue = CampusIssue(
      id: 'CP-2',
      title: 'Water leak',
      description: 'Water is leaking in the corridor.',
      category: 'Plumbing',
      location: 'Main · 1 · Hall',
      reporter: 'Student',
      expectedBy: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(issue.hasBreachedSla, isTrue);
    issue.status = IssueStatus.resolved;
    expect(issue.hasBreachedSla, isFalse);
  });

  test('reopening requires a strict majority of affected students', () {
    final issue = CampusIssue(
      id: 'CP-3',
      title: 'Broken door',
      description: 'The door does not close properly.',
      category: 'Safety',
      location: 'Main · 1 · entrance',
      reporter: 'Student',
      affectedCount: 4,
      stillExistsVotes: 2,
    );
    expect(issue.hasMajorityStillExistsVotes, isFalse);
    issue.stillExistsVotes = 3;
    expect(issue.hasMajorityStillExistsVotes, isTrue);
  });

  test('verification-request status is labeled for the issue workflow', () {
    expect(IssueStatus.verificationRequested.label, 'Verification requested');
  });

  test('work progress updates preserve completed and remaining steps', () {
    final update = WorkUpdate.fromMap('update-1', {
      'authorName': 'Rafi',
      'note': 'Inspected the electrical panel.',
      'completedSteps': ['Checked the breaker'],
      'nextSteps': ['Replace the damaged switch'],
      'photoUrl': 'https://res.cloudinary.com/be4i3h7e/image/upload/repair.jpg',
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 24, 10)),
    });

    expect(update.authorName, 'Rafi');
    expect(update.completedSteps, ['Checked the breaker']);
    expect(update.nextSteps, ['Replace the damaged switch']);
    expect(
      update.photoUrl,
      'https://res.cloudinary.com/be4i3h7e/image/upload/repair.jpg',
    );
    expect(update.createdAt, DateTime(2026, 10, 24, 10));
  });

  test('legacy assignee UIDs are never displayed as staff names', () {
    final issue = CampusIssue(
      id: 'CP-5',
      title: 'Broken fan',
      description: 'The fan is not working.',
      category: 'Electrical',
      location: 'Room 5',
      reporter: 'Student',
      assignedTo: 'legacy-staff-uid',
      assignedToName: 'legacy-staff-uid',
    );

    expect(issue.assigneeDisplayName, 'Maintenance staff');
    issue.assignedToName = 'Rafi Hasan';
    expect(issue.assigneeDisplayName, 'Rafi Hasan');
  });

  testWidgets('CampusPlus sign-in page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));
    expect(find.text('CampusPlus'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in as'), findsNothing);
    expect(find.text('Verify your email'), findsNothing);
  });

  testWidgets('Splash screen shows CampusPlus branding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.text('C+'), findsOneWidget);
    expect(find.text('CampusPlus'), findsOneWidget);
    expect(find.text('REPORT  ·  TRACK  ·  RESOLVE'), findsOneWidget);
  });

  testWidgets('Onboarding walks through all three introduction screens', (
    WidgetTester tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          onFinished: () async => finished = true,
        ),
      ),
    );

    expect(find.text('Report Campus Problems'), findsOneWidget);
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.text('Track Every Update'), findsOneWidget);

    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.text('Make Campus Better'), findsOneWidget);
    await tester.tap(find.text('Get Started →'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('Onboarding Skip completes setup from the first page', (
    WidgetTester tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          onFinished: () async => finished = true,
        ),
      ),
    );

    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('Student registration validates required fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New to CampusPlus? Create a student account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your student account'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
        find.text('Password must be at least 6 characters.'), findsOneWidget);
  });

  testWidgets('Sign-in has no role picker', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));
    expect(find.text('Student'), findsNothing);
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('Assigned issue cards show the staff member name and open', (
    WidgetTester tester,
  ) async {
    var opened = false;
    final issue = CampusIssue(
      id: 'CP-4',
      title: 'Broken corridor light',
      description: 'Light is not working.',
      category: 'Electrical',
      location: 'Main building',
      reporter: 'Student',
      assignedTo: 'staff-uid',
      assignedToName: 'Rafi Hasan',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IssueTile(
            issue: issue,
            onTap: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Assigned to Rafi Hasan'), findsOneWidget);
    await tester.tap(find.byType(IssueTile));
    expect(opened, isTrue);
  });

  testWidgets('Issue cards fit on a narrow phone and show the next action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final issue = CampusIssue(
      id: 'CP-NARROW',
      title: 'Long issue title that needs to wrap on a small phone',
      description: 'The light is not working.',
      category: 'Electrical',
      location: 'Engineering building · 2nd floor · East hallway',
      reporter: 'Student',
      status: IssueStatus.inProgress,
      assignedTo: 'staff-uid',
      assignedToName: 'Rafi Hasan',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IssueTile(
            issue: issue,
            actionHint: 'Open to post repair steps or submit completion',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('In Progress'), findsOneWidget);
    expect(
      find.text('Open to post repair steps or submit completion'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unread notifications show a red count badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnreadNotificationIcon(
            count: Stream<int>.value(4),
            icon: Icons.notifications_none_rounded,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.backgroundColor, Colors.red);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('Yes, fixed submits a single resolution verification vote', (
    WidgetTester tester,
  ) async {
    final issue = CampusIssue(
      id: 'CP-VERIFICATION',
      title: 'Repaired hallway light',
      description: 'The east hallway light was repaired.',
      category: 'Electrical',
      location: 'Engineering · 2 · East hallway',
      reporter: 'Student',
      status: IssueStatus.resolved,
      affectedCount: 1,
    );
    String? submittedVote;

    await tester.pumpWidget(
      MaterialApp(
        home: IssueDetailPage(
          issue: issue,
          role: 'Student',
          onChanged: (_) async {},
          onMarkAffected: (_) async => false,
          onVerify: (issueId, vote) async {
            expect(issueId, 'CP-VERIFICATION');
            submittedVote = vote;
            return true;
          },
          onToggleFollow: (_) async => false,
          checkFollowing: (_) async => false,
          checkAffected: (_) async => true,
          checkVerification: (_) async => false,
          loadStaffUsers: () async => [],
          watchWorkUpdates: (_) => Stream.value(const []),
          addWorkUpdate: ({
            required issueId,
            required note,
            required completedSteps,
            required nextSteps,
            photoUrl,
          }) async {},
          uploadPhoto: ({
            required bytes,
            required fileName,
            required contentType,
          }) async =>
              '',
          onMessage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Yes, fixed'));
    await tester.tap(find.text('Yes, fixed'));
    await tester.pumpAndSettle();

    expect(submittedVote, 'Yes, fixed');
    expect(
      find.text('Your verification has already been recorded.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inspection note dialog submits the note and disposes cleanly', (
    WidgetTester tester,
  ) async {
    String? submittedNote;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submittedNote = await showDialog<String>(
                  context: context,
                  builder: (_) => const InspectionNoteDialog(
                    result: IssueStatus.verified,
                    initialNote: '',
                  ),
                );
              },
              child: const Text('Open inspection'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open inspection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Confirmed broken pipe');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit inspection'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Submit inspection'));
    await tester.pumpAndSettle();

    expect(submittedNote, 'Confirmed broken pipe');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Repair progress photo can be selected and submitted safely', (
    WidgetTester tester,
  ) async {
    WorkProgressDraft? submitted;
    final photo = XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: 'repair.jpg',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submitted = await showDialog<WorkProgressDraft>(
                  context: context,
                  builder: (_) => WorkProgressDialog(
                    pickPhoto: () async => photo,
                  ),
                );
              },
              child: const Text('Open repair progress'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open repair progress'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Fixed wiring');
    await tester.enterText(find.byType(TextField).at(1), 'Replaced cable');
    await tester.pumpAndSettle();
    final addRepairPhoto = find.widgetWithText(
      OutlinedButton,
      'Add repair photo',
    );
    await tester.ensureVisible(addRepairPhoto);
    tester.widget<OutlinedButton>(addRepairPhoto).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post update'));
    await tester.pumpAndSettle();

    expect(submitted?.note, 'Fixed wiring');
    expect(submitted?.completedSteps, 'Replaced cable');
    expect(submitted?.photo, same(photo));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Completion photo can be selected and submitted safely', (
    WidgetTester tester,
  ) async {
    ({String summary, XFile? photo})? submitted;
    final photo = XFile.fromData(
      Uint8List.fromList([4, 5, 6]),
      name: 'completed.jpg',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submitted = await showDialog<({String summary, XFile? photo})>(
                  context: context,
                  builder: (_) => ResolutionSummaryDialog(
                    initialSummary: '',
                    pickPhoto: () async => photo,
                  ),
                );
              },
              child: const Text('Open completion'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open completion'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Replaced cable and tested the circuit.',
    );
    await tester.pumpAndSettle();
    final addCompletionPhoto = find.widgetWithText(
      OutlinedButton,
      'Add completion photo',
    );
    await tester.ensureVisible(addCompletionPhoto);
    tester.widget<OutlinedButton>(addCompletionPhoto).onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit completion'));
    await tester.pumpAndSettle();

    expect(submitted?.summary, 'Replaced cable and tested the circuit.');
    expect(submitted?.photo, same(photo));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Updates feed shows staff steps and opens the full timeline', (
    WidgetTester tester,
  ) async {
    final issue = CampusIssue(
      id: 'CP-ACTIVITY',
      title: 'Repair hallway lights',
      description: 'Lights in the east hallway are not working.',
      category: 'Electrical',
      location: 'Engineering · 2 · East hallway',
      reporter: 'Student',
      status: IssueStatus.inProgress,
      history: const ['Repair started'],
    );
    var openedIssue = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IssueUpdatesPage(
            issues: [issue],
            notificationUid: 'student-uid',
            notifications: Stream.value(const []),
            watchWorkUpdates: (_) => Stream.value([
              WorkUpdate(
                id: 'step-1',
                authorName: 'Rafi Hasan',
                note: 'Replaced the damaged switch.',
                completedSteps: const ['Removed the broken switch'],
                nextSteps: const ['Test the circuit'],
                createdAt: DateTime(2026, 10, 25),
              ),
            ]),
            markNotificationRead: (_, __) async {},
            approveDeletionRequest: (_) async {},
            declineDeletionRequest: (_) async {},
            onOpenIssue: (_) => openedIssue = true,
            onMessage: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Tap to view the complete timeline  ›'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Rafi Hasan'), findsOneWidget);
    expect(find.textContaining('Removed the broken switch'), findsOneWidget);
    expect(find.textContaining('Test the circuit'), findsOneWidget);
    await tester.tap(find.text('Tap to view the complete timeline  ›'));
    expect(openedIssue, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Deletion request notification only opens approval actions', (
    WidgetTester tester,
  ) async {
    var approvedIssueId = '';
    var openedIssue = false;
    var markedRead = false;
    final notifications = Stream<List<Map<String, dynamic>>>.value([
      {
        'id': 'notice-1',
        'issueId': 'CP-DELETE',
        'type': 'issue_deletion_request',
        'title': 'Issue deletion approval requested',
        'body': 'Admin requested permission to delete the resolved issue.',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 25)),
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IssueUpdatesPage(
            issues: const [],
            notificationUid: 'reporter-uid',
            notifications: notifications,
            watchWorkUpdates: (_) => Stream.value(const []),
            markNotificationRead: (_, __) async => markedRead = true,
            approveDeletionRequest: (id) async => approvedIssueId = id,
            declineDeletionRequest: (_) async {},
            onOpenIssue: (_) => openedIssue = true,
            onMessage: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issue deletion approval requested'));
    await tester.pumpAndSettle();

    expect(find.text('Approve issue deletion?'), findsOneWidget);
    expect(find.text('Approve deletion'), findsOneWidget);
    await tester.tap(find.text('Approve deletion'));
    await tester.pumpAndSettle();

    expect(markedRead, isTrue);
    expect(approvedIssueId, 'CP-DELETE');
    expect(openedIssue, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin must request approval before deleting a resolved issue', (
    WidgetTester tester,
  ) async {
    final issue = CampusIssue(
      id: 'CP-DELETE',
      title: 'Fixed water leak',
      description: 'The pipe leak in the north hall has been repaired.',
      category: 'Plumbing',
      location: 'North Hall · 1 · Washroom',
      reporter: 'Student',
      status: IssueStatus.resolved,
    );
    String? requestedIssueId;
    await tester.pumpWidget(
      MaterialApp(
        home: ManageAllIssuesPage(
          watchIssues: () => Stream.value([issue]),
          requestDeletion: (issueId) async => requestedIssueId = issueId,
          onOpenIssue: (_) {},
          onMessage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request deletion approval'));
    await tester.pumpAndSettle();
    expect(find.text('Send request'), findsOneWidget);
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(requestedIssueId, issue.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Student approval deletes a resolved report without admin retry',
      (
    WidgetTester tester,
  ) async {
    final issue = CampusIssue(
      id: 'CP-APPROVAL',
      title: 'Repaired classroom door',
      description: 'The classroom door hinge was fixed and tested.',
      category: 'Furniture',
      location: 'Classroom · 3 · 301',
      reporter: 'Student',
      status: IssueStatus.resolved,
      deletionRequestStatus: 'pending',
    );
    String? deletedIssueId;
    await tester.pumpWidget(
      MaterialApp(
        home: MyIssuesPage(
          uid: 'student-1',
          watchIssues: () => Stream.value([issue]),
          watchMyIssueIds: (_) => Stream.value([issue.id]),
          updateIssue: (_) async {},
          deleteIssue: (issueId) async => deletedIssueId = issueId,
          dismissDeletionRequest: (_) async {},
          uploadPhoto: ({
            required Uint8List bytes,
            required String fileName,
            required String contentType,
          }) async =>
              'https://res.cloudinary.com/test/image/upload/$fileName',
          onOpenIssue: (_) {},
          onMessage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve & delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve & delete').last);
    await tester.pumpAndSettle();

    expect(deletedIssueId, issue.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Student can edit their own unassigned issue and its photo', (
    WidgetTester tester,
  ) async {
    final issue = CampusIssue(
      id: 'CP-MY-ISSUE',
      title: 'Broken hallway light',
      description: 'The hallway light has been out since yesterday.',
      category: 'Electrical',
      location: 'Engineering · 2 · Room 204',
      reporter: 'Student',
      building: 'Engineering',
      floor: '2',
      room: 'Room 204',
    );
    final photo = XFile.fromData(
      Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        6,
        0,
        0,
        0,
        31,
        21,
        196,
        137,
        0,
        0,
        0,
        13,
        73,
        68,
        65,
        84,
        8,
        215,
        99,
        248,
        207,
        192,
        240,
        31,
        0,
        5,
        0,
        1,
        255,
        137,
        153,
        61,
        29,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ]),
      path: 'updated.png',
    );
    CampusIssue? updatedIssue;
    var uploadedPhoto = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MyIssuesPage(
          uid: 'student-1',
          watchIssues: () => Stream.value([issue]),
          watchMyIssueIds: (_) => Stream.value(['CP-MY-ISSUE']),
          updateIssue: (value) async => updatedIssue = value,
          deleteIssue: (_) async {},
          dismissDeletionRequest: (_) async {},
          uploadPhoto: ({
            required Uint8List bytes,
            required String fileName,
            required String contentType,
          }) async {
            uploadedPhoto = fileName == 'updated.png' &&
                contentType == 'image/png' &&
                bytes.isNotEmpty;
            return 'https://res.cloudinary.com/test/image/upload/updated.png';
          },
          pickPhoto: () async {
            return photo;
          },
          onOpenIssue: (_) {},
          onMessage: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit report'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).at(0), 'Light is still broken');
    await tester.enterText(
      find.byType(TextField).at(1),
      'The hallway light has been out since yesterday morning.',
    );
    final changePhoto = find.widgetWithText(OutlinedButton, 'Change photo');
    await tester.ensureVisible(changePhoto);
    await tester.tap(changePhoto);
    await tester.pumpAndSettle();
    expect(find.text('Photo selected'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(updatedIssue?.title, 'Light is still broken');
    expect(uploadedPhoto, isTrue);
    expect(updatedIssue?.imageUrl,
        'https://res.cloudinary.com/test/image/upload/updated.png');
    expect(tester.takeException(), isNull);
  });
}
