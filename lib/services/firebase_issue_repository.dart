import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/campus_issue.dart';
import '../models/work_update.dart';
import 'cloudinary_image_service.dart';

class FirebaseIssueRepository {
  FirebaseIssueRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    CloudinaryImageService? imageService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _imageService = imageService ?? CloudinaryImageService(),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final CloudinaryImageService _imageService;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _issues =>
      _firestore.collection('issues');

  Stream<List<CampusIssue>> watchIssues() =>
      _issues.orderBy('createdAt', descending: true).snapshots().map(
            (snapshot) => snapshot.docs
                .map((doc) => _issueFromMap(doc.id, doc.data()))
                .toList(growable: false),
          );

  Stream<List<String>> watchMyIssueIds(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('reportedIssues')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => doc.data()['issueId'] as String? ?? doc.id)
          .toList(growable: false));

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile(String uid) =>
      _firestore.collection('users').doc(uid).snapshots();

  Stream<List<Map<String, dynamic>>> watchNotifications(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(growable: false));

  Stream<int> watchUnreadNotificationCount(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .where('read', isEqualTo: false)
      .snapshots()
      .map((snapshot) => snapshot.size);

  Stream<List<Map<String, dynamic>>> watchUsers() => _firestore
      .collection('users')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList(growable: false));

  Stream<List<WorkUpdate>> watchWorkUpdates(String issueId) => _issues
      .doc(issueId)
      .collection('workUpdates')
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => WorkUpdate.fromMap(doc.id, doc.data()))
          .toList(growable: false));

  Future<void> addWorkUpdate({
    required String issueId,
    required String note,
    required List<String> completedSteps,
    required List<String> nextSteps,
    String? photoUrl,
  }) async {
    final user = _requireUser();
    final trimmedNote = note.trim();
    final completed = _validatedSteps(completedSteps, 'completedSteps');
    final next = _validatedSteps(nextSteps, 'nextSteps');
    if (trimmedNote.length < 3 || trimmedNote.length > 500) {
      throw ArgumentError.value(
        trimmedNote.length,
        'note',
        'Update note must be between 3 and 500 characters.',
      );
    }
    if (completed.isEmpty && next.isEmpty) {
      throw ArgumentError(
        'Add at least one completed step or one next step.',
      );
    }
    if (photoUrl != null && !_isCloudinaryPhotoUrl(photoUrl)) {
      throw ArgumentError.value(
        photoUrl,
        'photoUrl',
        'Invalid repair photo URL.',
      );
    }
    final profile = await _firestore.collection('users').doc(user.uid).get();
    final authorName = profile.data()?['displayName'] as String? ??
        user.displayName ??
        'Staff member';
    await _issues.doc(issueId).collection('workUpdates').add({
      'authorUid': user.uid,
      'authorName': authorName,
      'note': trimmedNote,
      'completedSteps': completed,
      'nextSteps': next,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  bool _isCloudinaryPhotoUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'res.cloudinary.com' &&
        uri.pathSegments.length >= 4 &&
        uri.pathSegments[0] == _imageService.cloudName;
  }

  List<String> _validatedSteps(List<String> steps, String field) {
    final cleaned = steps
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .toList();
    if (cleaned.length > 8 || cleaned.any((step) => step.length > 160)) {
      throw ArgumentError.value(
        steps,
        field,
        'Add up to 8 steps, each no longer than 160 characters.',
      );
    }
    return cleaned;
  }

  Stream<List<Map<String, dynamic>>> watchSupportMessages() => _firestore
      .collection('supportMessages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false));

  Stream<List<Map<String, dynamic>>> watchSuggestions() => _firestore
      .collection('suggestions')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList(growable: false));

  Future<List<Map<String, dynamic>>> getStaffUsers() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .get();
    final staff = snapshot.docs
        .map((doc) => _staffUserData(doc.id, doc.data()))
        .toList(growable: false);
    return staff
      ..sort((a, b) => (a['displayName'] as String)
          .toLowerCase()
          .compareTo((b['displayName'] as String).toLowerCase()));
  }

  Map<String, dynamic> _staffUserData(
    String uid,
    Map<String, dynamic> data,
  ) {
    final storedName = data['displayName'] as String? ?? '';
    final email = data['email'] as String? ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final displayName = storedName.trim().isNotEmpty && storedName.trim() != uid
        ? storedName.trim()
        : emailName.trim().isNotEmpty
            ? emailName.trim()
            : 'Maintenance staff';
    return {...data, 'uid': uid, 'displayName': displayName};
  }

  Future<void> updateSupportStatus(String requestId, String status) async {
    if (!const {'open', 'resolved'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unknown support status');
    }
    await _firestore.collection('supportMessages').doc(requestId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitSuggestion(String message) async {
    final user = _requireUser();
    final trimmedMessage = message.trim();
    if (trimmedMessage.length < 10 || trimmedMessage.length > 1000) {
      throw ArgumentError.value(
        trimmedMessage.length,
        'message',
        'Suggestion must be between 10 and 1000 characters.',
      );
    }
    await _firestore.collection('suggestions').add({
      'uid': user.uid,
      'email': user.email,
      'message': trimmedMessage,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSuggestionStatus(String id, String status) async {
    if (!const {'reviewed', 'implemented', 'declined'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unknown suggestion status');
    }
    await _firestore.collection('suggestions').doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadIssuePhoto({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    _requireUser();
    return _imageService.uploadImage(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
  }

  Future<String> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    _requireUser();
    return _imageService.uploadImage(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
  }

  Future<void> createIssue(CampusIssue issue) async {
    final user = _requireUser();
    final issueRef = _issues.doc(issue.id);
    final reporterRef = issueRef.collection('private').doc('reporter');
    final reporterAffectedRef = issueRef.collection('affectedBy').doc(user.uid);
    final existingIssue = await issueRef.get();
    if (existingIssue.exists) {
      final reporter = await reporterRef.get();
      if (reporter.data()?['uid'] == user.uid) return;
      throw StateError('Issue ID is already in use.');
    }
    final batch = _firestore.batch();
    batch.set(issueRef, {
      ..._issueToMap(issue),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(reporterRef, {
      'uid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(reporterAffectedRef, {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('reportedIssues')
          .doc(issue.id),
      {
        'issueId': issue.id,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> migrateLegacyReporterUids() async {
    final user = _requireUser();
    final preferences = await SharedPreferences.getInstance();
    final migrationKey = 'campusplus_reported_issue_index_v1_${user.uid}';
    if (preferences.getBool(migrationKey) == true) return;
    final allIssues = await _issues.get();
    for (var offset = 0; offset < allIssues.docs.length; offset += 150) {
      final end = offset + 150 < allIssues.docs.length
          ? offset + 150
          : allIssues.docs.length;
      final documents = allIssues.docs.sublist(offset, end);
      final reporterSnapshots = await Future.wait(
        documents.map((document) {
          final reporterUid = document.data()['reporterUid'] as String?;
          return reporterUid != null && reporterUid.isNotEmpty
              ? Future.value(null)
              : document.reference.collection('private').doc('reporter').get();
        }),
      );
      final indexSnapshots = await Future.wait(
        documents.asMap().entries.map((entry) {
          final data = entry.value.data();
          final legacyUid = data['reporterUid'] as String?;
          final reporterUid = legacyUid?.isNotEmpty == true
              ? legacyUid
              : reporterSnapshots[entry.key]?.data()?['uid'] as String?;
          if (reporterUid == null || reporterUid.isEmpty) {
            return Future.value(null);
          }
          return _firestore
              .collection('users')
              .doc(reporterUid)
              .collection('reportedIssues')
              .doc(entry.value.id)
              .get();
        }),
      );
      final batch = _firestore.batch();
      for (var index = 0; index < documents.length; index++) {
        final issueDoc = documents[index];
        final data = issueDoc.data();
        final legacyUid = data['reporterUid'] as String?;
        final reporterUid = legacyUid?.isNotEmpty == true
            ? legacyUid
            : reporterSnapshots[index]?.data()?['uid'] as String?;
        if (reporterUid == null || reporterUid.isEmpty) continue;
        batch.set(
            issueDoc.reference.collection('private').doc('reporter'),
            {
              'uid': reporterUid,
              'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        if (indexSnapshots[index]?.exists != true) {
          batch.set(
            _firestore
                .collection('users')
                .doc(reporterUid)
                .collection('reportedIssues')
                .doc(issueDoc.id),
            {
              'issueId': issueDoc.id,
              'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
            },
          );
        }
        if (legacyUid?.isNotEmpty == true) {
          batch.update(issueDoc.reference, {
            'reporterUid': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    }
    await preferences.setBool(migrationKey, true);
  }

  Future<void> migrateLegacyAssigneeNames() async {
    final issues = await _issues.where('assignedTo', isNotEqualTo: '').get();
    final staff = await getStaffUsers();
    final names = {
      for (final user in staff)
        user['uid'] as String: user['displayName'] as String,
    };
    for (var offset = 0; offset < issues.docs.length; offset += 400) {
      final batch = _firestore.batch();
      var hasUpdates = false;
      final end =
          offset + 400 < issues.docs.length ? offset + 400 : issues.docs.length;
      for (final document in issues.docs.sublist(offset, end)) {
        final data = document.data();
        final uid = data['assignedTo'] as String? ?? '';
        final name = names[uid];
        final currentName = data['assignedToName'] as String? ?? '';
        final history =
            (data['history'] as List<dynamic>? ?? const []).cast<String>();
        final updatedHistory = history.map((entry) {
          for (final staffUser in staff) {
            final staffUid = staffUser['uid'] as String;
            final staffName = staffUser['displayName'] as String;
            for (final prefix in [
              'Assigned to $staffUid',
              'Repair assigned to $staffUid',
            ]) {
              if (entry.startsWith(prefix)) {
                return entry.replaceFirst(
                  prefix,
                  'Repair assigned to $staffName',
                );
              }
            }
          }
          return entry;
        }).toList(growable: false);
        final changes = <String, Object?>{};
        if (name != null && (currentName.isEmpty || currentName == uid)) {
          changes['assignedToName'] = name;
        }
        if (updatedHistory.join('\n') != history.join('\n')) {
          changes['history'] = updatedHistory;
        }
        if (changes.isEmpty) continue;
        batch.update(document.reference, changes);
        hasUpdates = true;
      }
      if (hasUpdates) await batch.commit();
    }
  }

  Future<void> updateIssue(CampusIssue issue) async {
    final issueRef = _issues.doc(issue.id);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(issueRef);
      if (!snapshot.exists) throw StateError('Issue no longer exists.');
      final current = snapshot.data()!;
      final updates = <String, Object?>{
        'status': issue.status.name,
        'history': issue.history,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      void updateWhenChanged(String field, Object? value) {
        if (!current.containsKey(field) && value == '') return;
        if (current[field] != value) updates[field] = value;
      }

      updateWhenChanged('title', issue.title);
      updateWhenChanged('description', issue.description);
      updateWhenChanged('category', issue.category);
      updateWhenChanged('location', issue.location);
      updateWhenChanged('severity', issue.severity);
      updateWhenChanged('assignedTo', issue.assignedTo);
      updateWhenChanged('assignedToName', issue.assignedToName);
      updateWhenChanged(
        'verificationAssignedTo',
        issue.verificationAssignedTo,
      );
      updateWhenChanged(
        'verificationAssignedToName',
        issue.verificationAssignedToName,
      );
      updateWhenChanged('verificationNote', issue.verificationNote);
      updateWhenChanged('building', issue.building);
      updateWhenChanged('floor', issue.floor);
      updateWhenChanged('room', issue.room);
      updateWhenChanged('department', issue.department);
      updateWhenChanged('priorityOverride', issue.priorityOverride);
      updateWhenChanged('resolutionSummary', issue.resolutionSummary);
      updateWhenChanged('resolutionPhotoUrl', issue.resolutionPhotoUrl);
      updateWhenChanged('photoUrl', issue.imageUrl);
      final previousExpectedBy = current['expectedBy'];
      final previousDate =
          previousExpectedBy is Timestamp ? previousExpectedBy.toDate() : null;
      if (previousDate != issue.expectedBy) {
        updates['expectedBy'] = issue.expectedBy == null
            ? FieldValue.delete()
            : Timestamp.fromDate(issue.expectedBy!);
      }
      if (issue.status == IssueStatus.resolved &&
          current['status'] != IssueStatus.resolved.name) {
        updates['resolvedAt'] = FieldValue.serverTimestamp();
      }
      transaction.update(issueRef, updates);
    });
  }

  Future<void> requestIssueDeletion(String issueId) async {
    final user = _requireUser();
    final issueRef = _issues.doc(issueId);
    final reporterRef = issueRef.collection('private').doc('reporter');
    final issueSnapshot = await issueRef.get();
    if (!issueSnapshot.exists ||
        issueSnapshot.data()?['status'] != IssueStatus.resolved.name) {
      throw StateError('Only resolved issues can be submitted for deletion.');
    }
    if (issueSnapshot.data()?['deletionRequestStatus'] == 'pending') {
      throw StateError('A deletion approval request is already pending.');
    }
    final reporterSnapshot = await reporterRef.get();
    final reporterUid = reporterSnapshot.data()?['uid'] as String?;
    if (reporterUid == null || reporterUid.isEmpty) {
      throw StateError('The reporting student could not be identified.');
    }
    final history =
        (issueSnapshot.data()?['history'] as List<dynamic>? ?? const [])
            .cast<String>();
    final batch = _firestore.batch();
    batch.update(issueRef, {
      'deletionRequestStatus': 'pending',
      'deletionRequestedAt': FieldValue.serverTimestamp(),
      'deletionRequestedBy': user.uid,
      'history': [...history, 'Admin requested deletion approval'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _firestore
          .collection('users')
          .doc(reporterUid)
          .collection('notifications')
          .doc(),
      {
        'issueId': issueId,
        'type': 'issue_deletion_request',
        'title': 'Issue deletion approval requested',
        'body':
            'Admin requested permission to delete your resolved issue. Review it in My Issues.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> dismissIssueDeletionRequest(String issueId) async {
    final user = _requireUser();
    final issueRef = _issues.doc(issueId);
    final reporter = await issueRef.collection('private').doc('reporter').get();
    if (reporter.data()?['uid'] != user.uid) {
      throw StateError('You can only respond to your own issue request.');
    }
    await issueRef.update({
      'deletionRequestStatus': 'declined',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteIssue(String issueId) async {
    final user = _requireUser();
    final issueRef = _issues.doc(issueId);
    final issueSnapshot = await issueRef.get();
    if (!issueSnapshot.exists) {
      throw StateError('This issue has already been deleted.');
    }
    final issue = issueSnapshot.data()!;
    final reporter = await issueRef.collection('private').doc('reporter').get();
    final reporterUid = reporter.data()?['uid'] as String?;
    if (reporterUid != user.uid) {
      throw StateError(
          'Only the student who reported this issue can delete it.');
    }
    final profile = await _firestore.collection('users').doc(user.uid).get();
    if (profile.data()?['role'] != 'student') {
      throw StateError('Only student accounts can delete issues.');
    }
    final status = issue['status'];
    final canDelete = ((status == 'reported' || status == 'rejected') &&
            issue['assignedTo'] == '') ||
        (status == 'resolved' && issue['deletionRequestStatus'] == 'pending');
    if (!canDelete) {
      throw StateError(
        'An issue can only be deleted before assignment or after Admin '
        'requests approval for a resolved issue.',
      );
    }
    const childCollections = [
      'workUpdates',
      'affectedBy',
      'followers',
      'verificationVotes',
      'events',
      'notificationEvents',
    ];
    final deleteRefs = <DocumentReference<Map<String, dynamic>>>[];
    final followerUids = <String>{};
    for (final collectionName in childCollections) {
      final children = await issueRef.collection(collectionName).get();
      for (final child in children.docs) {
        deleteRefs.add(child.reference);
        if (collectionName == 'followers') {
          followerUids.add(child.id);
        }
      }
    }
    final notifications = await _firestore
        .collectionGroup('notifications')
        .where('issueId', isEqualTo: issueId)
        .get();
    deleteRefs.addAll(notifications.docs.map((document) => document.reference));
    for (final uid in followerUids) {
      deleteRefs.add(
        _firestore
            .collection('users')
            .doc(uid)
            .collection('following')
            .doc(issueId),
      );
    }
    deleteRefs.add(issueRef.collection('private').doc('reporter'));
    deleteRefs.add(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('reportedIssues')
          .doc(issueId),
    );
    deleteRefs.add(issueRef);
    for (var offset = 0; offset < deleteRefs.length; offset += 450) {
      final batch = _firestore.batch();
      final end =
          offset + 450 < deleteRefs.length ? offset + 450 : deleteRefs.length;
      for (final reference in deleteRefs.sublist(offset, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }

  Future<void> updateProfile({
    required String displayName,
    String? photoUrl,
  }) async {
    final user = _requireUser();
    final trimmedName = displayName.trim();
    await user.updateDisplayName(trimmedName);
    await _firestore.collection('users').doc(user.uid).update({
      'displayName': trimmedName,
      if (photoUrl != null) 'photoUrl': photoUrl,
    });
  }

  Future<void> updatePushPreference(bool enabled) async {
    final user = _requireUser();
    await _firestore.collection('users').doc(user.uid).update({
      'pushEnabled': enabled,
    });
  }

  Future<void> updateUserRole(String uid, String role) async {
    if (!const {'student', 'staff', 'admin'}.contains(role)) {
      throw ArgumentError.value(role, 'role', 'Unknown role');
    }
    await _firestore.collection('users').doc(uid).update({'role': role});
  }

  Future<void> createStaffAccount({
    required String displayName,
    required String email,
    required String password,
    required String department,
    String? phone,
  }) async {
    final admin = _requireUser();
    final trimmedName = displayName.trim();
    final trimmedEmail = email.trim();
    final trimmedDepartment = department.trim();
    if (trimmedName.length < 2 ||
        !trimmedEmail.contains('@') ||
        password.length < 6 ||
        trimmedDepartment.isEmpty) {
      throw ArgumentError('Enter valid staff account details.');
    }

    FirebaseApp? staffApp;
    for (final app in Firebase.apps) {
      if (app.name == 'campusplus-staff-provisioning') {
        staffApp = app;
        break;
      }
    }
    staffApp ??= await Firebase.initializeApp(
      name: 'campusplus-staff-provisioning',
      options: Firebase.app().options,
    );
    final staffAuth = FirebaseAuth.instanceFor(app: staffApp);
    User? newUser;
    try {
      final credential = await staffAuth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );
      newUser = credential.user;
      if (newUser == null) {
        throw StateError('Firebase did not return the new staff account.');
      }
      await newUser.updateDisplayName(trimmedName);
      await _firestore.collection('users').doc(newUser.uid).set({
        'uid': newUser.uid,
        'email': trimmedEmail,
        'displayName': trimmedName,
        'role': 'staff',
        'pushEnabled': false,
        'department': trimmedDepartment,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': admin.uid,
      });
    } catch (error) {
      if (newUser != null) {
        try {
          await newUser.delete();
        } catch (cleanupError) {
          throw StateError(
            'Staff profile creation failed ($error), and Firebase Auth account '
            'cleanup also failed ($cleanupError). Remove the incomplete account '
            'from Firebase Authentication before retrying.',
          );
        }
      }
      rethrow;
    } finally {
      if (staffAuth.currentUser != null) await staffAuth.signOut();
    }
  }

  Future<void> markNotificationRead(String uid, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  Future<void> submitSupportRequest({
    required String subject,
    required String message,
  }) async {
    final user = _requireUser();
    await _firestore.collection('supportMessages').add({
      'uid': user.uid,
      'email': user.email,
      'subject': subject.trim(),
      'message': message.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> markAffected(String issueId) async {
    final user = _requireUser();
    final issueRef = _issues.doc(issueId);
    final voteRef = issueRef.collection('affectedBy').doc(user.uid);

    return _firestore.runTransaction((transaction) async {
      final vote = await transaction.get(voteRef);
      final issue = await transaction.get(issueRef);
      if (vote.exists || !issue.exists) return false;

      final affectedCount =
          (issue.data()?['affectedCount'] as num?)?.toInt() ?? 1;
      transaction.set(voteRef, {'createdAt': FieldValue.serverTimestamp()});
      transaction.update(issueRef, {
        'affectedCount': affectedCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<bool> toggleFollow(String issueId) async {
    final user = _requireUser();
    final followRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('following')
        .doc(issueId);
    final followerRef =
        _issues.doc(issueId).collection('followers').doc(user.uid);

    return _firestore.runTransaction((transaction) async {
      final follow = await transaction.get(followRef);
      final issue = await transaction.get(_issues.doc(issueId));
      if (!issue.exists) throw StateError('Issue no longer exists.');
      if (follow.exists) {
        transaction.delete(followRef);
        transaction.delete(followerRef);
        return false;
      }
      transaction.set(followRef, {
        'issueId': issueId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(followerRef, {
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<bool> isFollowing(String issueId) async {
    final uid = _requireUser().uid;
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(issueId)
        .get();
    return snapshot.exists;
  }

  Future<bool> recordVerification(String issueId, String vote) async {
    if (!const {'Yes, fixed', 'Still exists', 'Not sure'}.contains(vote)) {
      throw ArgumentError.value(vote, 'vote', 'Unknown verification vote');
    }
    final user = _requireUser();
    final issueRef = _issues.doc(issueId);
    final voteRef = issueRef.collection('verificationVotes').doc(user.uid);
    final affectedRef = issueRef.collection('affectedBy').doc(user.uid);

    return _firestore.runTransaction((transaction) async {
      final previousVote = await transaction.get(voteRef);
      final issueSnapshot = await transaction.get(issueRef);
      final affected = await transaction.get(affectedRef);
      if (previousVote.exists || !issueSnapshot.exists || !affected.exists) {
        return false;
      }

      final issue = _issueFromMap(issueSnapshot.id, issueSnapshot.data()!);
      if (issue.status != IssueStatus.resolved) return false;
      if (issue.verificationVotes.containsKey(user.uid)) return false;
      issue.verificationCount++;
      if (vote == 'Still exists') issue.stillExistsVotes++;
      issue.history = [...issue.history, 'Student verification: $vote'];
      if (issue.hasMajorityStillExistsVotes) {
        issue.status = IssueStatus.inProgress;
        issue.history = [
          ...issue.history,
          'Reopened after student verification'
        ];
      }

      transaction.set(voteRef, {
        'vote': vote,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(issueRef, {
        'verificationCount': issue.verificationCount,
        'stillExistsVotes': issue.stillExistsVotes,
        'status': issue.status.name,
        'history': issue.history,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      issue.verificationVotes[user.uid] = vote;
      return true;
    });
  }

  Future<bool> isAffected(String issueId) async {
    final uid = _requireUser().uid;
    final document =
        await _issues.doc(issueId).collection('affectedBy').doc(uid).get();
    return document.exists;
  }

  Future<bool> hasVerification(String issueId) async {
    final uid = _requireUser().uid;
    final document = await _issues
        .doc(issueId)
        .collection('verificationVotes')
        .doc(uid)
        .get();
    return document.exists;
  }

  Future<void> createUserProfile({
    required User user,
    required String displayName,
  }) async {
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName,
      'role': 'student',
      'pushEnabled': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return snapshot.data() ?? const {};
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must sign in before using campus issues.');
    }
    return user;
  }

  Map<String, dynamic> _issueToMap(CampusIssue issue) => {
        'title': issue.title,
        'description': issue.description,
        'category': issue.category,
        'location': issue.location,
        'building': issue.building,
        'floor': issue.floor,
        'room': issue.room,
        'department': issue.department,
        'reporter': issue.reporter,
        'isAnonymous': issue.isAnonymous,
        'status': issue.status.name,
        'severity': issue.severity,
        'priorityOverride': issue.priorityOverride,
        'resolutionSummary': issue.resolutionSummary,
        'resolutionPhotoUrl': issue.resolutionPhotoUrl,
        if (issue.expectedBy != null)
          'expectedBy': Timestamp.fromDate(issue.expectedBy!),
        if (issue.resolvedAt != null)
          'resolvedAt': Timestamp.fromDate(issue.resolvedAt!),
        'affectedCount': issue.affectedCount,
        'assignedTo': issue.assignedTo,
        'assignedToName': issue.assignedToName,
        'verificationAssignedTo': issue.verificationAssignedTo,
        'verificationAssignedToName': issue.verificationAssignedToName,
        'verificationNote': issue.verificationNote,
        'photoUrl': issue.imageUrl,
        'history': issue.history,
        'verificationCount': issue.verificationCount,
        'stillExistsVotes': issue.stillExistsVotes,
        'createdAt': Timestamp.fromDate(issue.createdAt ?? DateTime.now()),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CampusIssue _issueFromMap(String id, Map<String, dynamic> data) {
    final statusName = data['status'] as String? ?? IssueStatus.reported.name;
    final status = IssueStatus.values.firstWhere(
      (candidate) => candidate.name == statusName,
      orElse: () => IssueStatus.reported,
    );
    final createdAt = data['createdAt'];
    final votes = data['verificationVotes'];

    return CampusIssue(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? 'Other',
      location: data['location'] as String? ?? '',
      building: data['building'] as String? ?? '',
      floor: data['floor'] as String? ?? '',
      room: data['room'] as String? ?? '',
      department: data['department'] as String? ?? '',
      priorityOverride: data['priorityOverride'] as String? ?? '',
      resolutionSummary: data['resolutionSummary'] as String? ?? '',
      resolutionPhotoUrl: data['resolutionPhotoUrl'] as String? ?? '',
      reporter: data['reporter'] as String? ?? 'Student',
      reporterUid: data['reporterUid'] as String? ?? '',
      imageUrl: data['photoUrl'] as String?,
      status: status,
      severity: data['severity'] as String? ?? 'Medium',
      affectedCount: (data['affectedCount'] as num?)?.toInt() ?? 1,
      isAnonymous: data['isAnonymous'] as bool? ?? false,
      assignedTo: data['assignedTo'] as String? ?? '',
      assignedToName: data['assignedToName'] as String? ?? '',
      verificationAssignedTo: data['verificationAssignedTo'] as String? ?? '',
      verificationAssignedToName:
          data['verificationAssignedToName'] as String? ?? '',
      verificationNote: data['verificationNote'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      expectedBy: data['expectedBy'] is Timestamp
          ? (data['expectedBy'] as Timestamp).toDate()
          : null,
      resolvedAt: data['resolvedAt'] is Timestamp
          ? (data['resolvedAt'] as Timestamp).toDate()
          : null,
      history: (data['history'] as List<dynamic>? ?? const []).cast<String>(),
      deletionRequestStatus: data['deletionRequestStatus'] as String? ?? '',
      verificationVotes: votes is Map
          ? votes
              .map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      verificationCount: (data['verificationCount'] as num?)?.toInt() ?? 0,
      stillExistsVotes: (data['stillExistsVotes'] as num?)?.toInt() ?? 0,
    );
  }

  static const anonymousReportsPreference = 'anonymous_reports_default';

  static Future<bool> anonymousReportsByDefault() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(anonymousReportsPreference) ?? false;
  }

  static Future<void> setAnonymousReportsByDefault(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(anonymousReportsPreference, value);
  }
}
