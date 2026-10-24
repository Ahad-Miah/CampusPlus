const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

initializeApp();

const db = getFirestore();

exports.notifyIssueUpdates = onDocumentWritten(
  {
    document: "issues/{issueId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : null;
    const after = event.data?.after.exists ? event.data.after.data() : null;
    if (!after) return;

    const created = before == null;
    const statusChanged = before != null && before.status !== after.status;
    const assignmentChanged =
      before != null && before.assignedTo !== after.assignedTo;
    const inspectionAssignmentChanged =
      before != null &&
      before.verificationAssignedTo !== after.verificationAssignedTo;
    const deletionApprovalRequested =
      before != null &&
      before.deletionRequestStatus !== "pending" &&
      after.deletionRequestStatus === "pending";
    if (!created && !statusChanged && !assignmentChanged &&
        !inspectionAssignmentChanged && !deletionApprovalRequested) return;

    const issueId = event.params.issueId;
    const dispatchRef = db.collection("issues")
      .doc(issueId)
      .collection("notificationEvents")
      .doc(event.id);
    const claimed = await db.runTransaction(async (transaction) => {
      const dispatch = await transaction.get(dispatchRef);
      if (dispatch.exists) return false;
      transaction.create(dispatchRef, {
        createdAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!claimed) return;

    const title = deletionApprovalRequested
      ? "Issue deletion approval requested"
      : created
      ? "New campus issue"
      : inspectionAssignmentChanged && after.verificationAssignedTo
        ? "Staff inspection requested"
      : assignmentChanged
        ? "Maintenance task assigned"
        : `Issue ${after.status}`;
    const body = deletionApprovalRequested
      ? `Admin is asking permission to delete your resolved issue: ${after.title}.`
      : created
      ? `${after.title} · ${after.location}`
      : inspectionAssignmentChanged && after.verificationAssignedTo
        ? `${after.title} is ready for inspection.`
      : assignmentChanged
        ? `${after.title} has been assigned to your team.`
        : `${after.title} is now ${after.status}.`;

    const recipients = new Set();
    let reporterUid = after.reporterUid;
    if (!reporterUid) {
      const reporter = await db.collection("issues")
        .doc(issueId)
        .collection("private")
        .doc("reporter")
        .get();
      reporterUid = reporter.data()?.uid;
    }
    if (deletionApprovalRequested) {
      if (reporterUid) recipients.add(reporterUid);
    } else if (created) {
      const admins = await db.collection("users")
        .where("role", "==", "admin")
        .get();
      admins.docs.forEach((user) => recipients.add(user.id));
      if (reporterUid) recipients.add(reporterUid);
    } else {
      if (reporterUid) recipients.add(reporterUid);
      if (after.assignedTo) recipients.add(after.assignedTo);
      if (after.verificationAssignedTo) {
        recipients.add(after.verificationAssignedTo);
      }
      const followers = await db.collection("issues")
        .doc(issueId)
        .collection("followers")
        .get();
      followers.docs.forEach((follower) => recipients.add(follower.id));
      const affectedUsers = await db.collection("issues")
        .doc(issueId)
        .collection("affectedBy")
        .get();
      affectedUsers.docs.forEach((affectedUser) =>
        recipients.add(affectedUser.id));
    }

    const batch = db.batch();
    const tokenRefs = [];
    for (const uid of recipients) {
      const profileRef = db.collection("users").doc(uid);
      const notificationRef = profileRef
        .collection("notifications")
        .doc(event.id);
      if (!deletionApprovalRequested) {
        batch.set(notificationRef, {
          title,
          body,
          issueId,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      const profile = await profileRef.get();
      if (profile.exists && profile.data().pushEnabled === true) {
        const tokens = await profileRef.collection("fcmTokens").get();
        tokenRefs.push(...tokens.docs);
      }
    }
    await batch.commit();

    const tokens = [...new Set(tokenRefs
      .map((doc) => doc.data().token)
      .filter((token) => typeof token === "string" && token.length > 0))];
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens: tokens.slice(0, 500),
      notification: { title, body },
      data: {
        issueId,
        notificationType: deletionApprovalRequested
          ? "issue_deletion_request"
          : "issue_update",
        title,
        body,
      },
      android: {
        priority: "high",
        collapseKey: issueId,
        notification: {
          channelId: "campusplus_updates",
          tag: issueId,
        },
      },
    });

    const staleTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success &&
          (result.error?.code === "messaging/registration-token-not-registered" ||
           result.error?.code === "messaging/invalid-registration-token")) {
        const staleToken = tokens[index];
        tokenRefs
          .filter((ref) => ref.data().token === staleToken)
          .forEach((ref) => staleTokens.push(ref.ref.delete()));
      }
    });
    await Promise.all(staleTokens);
    logger.info("Issue notifications dispatched", {
      issueId,
      recipientCount: recipients.size,
      tokenCount: tokens.length,
      deliveredCount: response.successCount,
    });
  },
);
