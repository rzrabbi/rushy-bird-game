const admin = require('firebase-admin');

// Initialize Firebase Admin using credentials stored in the GitHub Secret
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const auth = admin.auth();
const db = admin.firestore();

async function cleanup() {
  let totalDeleted = 0;
  
  console.log("Fetching all active Firebase Authentication users...");
  const activeUids = new Set();
  let nextPageToken;
  do {
    const listUsersResult = await auth.listUsers(1000, nextPageToken);
    listUsersResult.users.forEach(user => activeUids.add(user.uid));
    nextPageToken = listUsersResult.nextPageToken;
  } while (nextPageToken);

  console.log(`Found ${activeUids.size} active users in Firebase Authentication.`);

  const collections = [
    'player_data_rushybird',
    'leaderboard_rushybird_alltime',
    'leaderboard_rushybird_seasonal'
  ];

  for (const colName of collections) {
    console.log(`Checking Firestore collection: ${colName}`);
    const snapshot = await db.collection(colName).get();

    if (snapshot.empty) {
      console.log(`Collection ${colName} is empty.`);
      continue;
    }

    let batch = db.batch();
    let count = 0;
    let colDeleted = 0;

    for (const doc of snapshot.docs) {
      const uid = doc.id;
      if (!activeUids.has(uid)) {
        batch.delete(doc.ref);
        count++;
        colDeleted++;
        totalDeleted++;

        // Commit batch in chunks of 400 (well within the 500 operation limit)
        if (count === 400) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    console.log(`Deleted ${colDeleted} orphan documents from ${colName}.`);
  }

  const summaryMarkdown = `### 🧹 Scheduled Firestore Orphan Cleanup Report
- **Run Date**: ${new Date().toUTCString()}
- **Criteria**: Deleted data for users who do not exist in Firebase Authentication (deleted/expired accounts)
- **Total Firestore Documents Cleaned**: **${totalDeleted}** orphan documents deleted
`;
  
  const fs = require('fs');
  fs.writeFileSync('step_summary.md', summaryMarkdown);

  console.log(`Cleanup complete. Total documents deleted: ${totalDeleted}`);
}

cleanup().catch(err => {
  console.error("Cleanup failed:", err);
  process.exit(1);
});
