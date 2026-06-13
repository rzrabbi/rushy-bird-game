const admin = require('firebase-admin');

// Initialize Firebase Admin using credentials stored in the GitHub Secret
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const auth = admin.auth();
const db = admin.firestore();

async function cleanup() {
  let nextPageToken;
  let totalDeletedAuth = 0;
  let totalDeletedFirestore = 0;

  console.log("Starting Firebase Auth guest cleanup. Looking for all anonymous users.");

  do {
    const listUsersResult = await auth.listUsers(1000, nextPageToken);
    const usersToDelete = [];

    for (const user of listUsersResult.users) {
      const isAnonymous = user.providerData.length === 0;

      // Check if the user is anonymous (no auth providers linked)
      if (isAnonymous) {
        usersToDelete.push(user.uid);
      }
    }

    if (usersToDelete.length > 0) {
      console.log(`Found ${usersToDelete.length} anonymous users to delete: ${JSON.stringify(usersToDelete)}`);

      // Delete documents from Firestore collections
      const collections = ['player_data_rushybird', 'leaderboard_rushybird_alltime', 'leaderboard_rushybird_seasonal'];
      
      // Delete in batches of 150 users (450 document delete operations per batch, within Firestore's 500 limit)
      const batchSize = 150;
      for (let i = 0; i < usersToDelete.length; i += batchSize) {
        const chunk = usersToDelete.slice(i, i + batchSize);
        const batch = db.batch();
        let opsCount = 0;

        for (const uid of chunk) {
          for (const col of collections) {
            const docRef = db.collection(col).doc(uid);
            batch.delete(docRef);
            opsCount++;
          }
        }

        if (opsCount > 0) {
          await batch.commit();
          totalDeletedFirestore += opsCount;
          console.log(`Deleted Firestore documents for ${chunk.length} guest accounts.`);
        }
      }

      // Delete from Firebase Auth
      const deleteResult = await auth.deleteUsers(usersToDelete);
      totalDeletedAuth += deleteResult.successCount;
      console.log(`Auth deletion finished. Successfully deleted: ${deleteResult.successCount}. Failures: ${deleteResult.failureCount}`);
      if (deleteResult.errors.length > 0) {
        console.error(`Deletion errors: ${JSON.stringify(deleteResult.errors)}`);
      }
    }

    nextPageToken = listUsersResult.nextPageToken;
  } while (nextPageToken);

  const summaryMarkdown = `### 🧹 Firebase Auth & Firestore Guest Cleanup Report
- **Run Date**: ${new Date().toUTCString()}
- **Total Auth Accounts Cleaned**: **${totalDeletedAuth}** anonymous accounts deleted from Firebase Auth
- **Total Firestore Documents Cleaned**: **${totalDeletedFirestore}** guest database documents deleted
`;
  
  const fs = require('fs');
  fs.writeFileSync('step_summary.md', summaryMarkdown);

  console.log(`Cleanup complete. Total users deleted from Auth: ${totalDeletedAuth}. Total docs deleted from Firestore: ${totalDeletedFirestore}`);
}

cleanup().catch(err => {
  console.error("Cleanup failed:", err);
  process.exit(1);
});
