// Ruby Key - Firebase web config.
//
// Values below come from the SAME Firebase project as the Android app
// (ruby-invoice-c17bd). The only thing you may need to add is the WEB
// appId: Firebase Console -> Project settings -> Your apps -> Web app
// (</>) "Ruby Key" -> copy appId and paste it below.
// Full steps: docs/FIREBASE_SETUP.md (section "Ruby Key admin panel").

window.RUBY_FIREBASE_CONFIG = {
  apiKey: "AIzaSyCBPMZrOqIN8mO3lEWknvK_LnuzakpeWjU",
  authDomain: "ruby-invoice-c17bd.firebaseapp.com",
  projectId: "ruby-invoice-c17bd",
  storageBucket: "ruby-invoice-c17bd.firebasestorage.app",
  messagingSenderId: "972758775225",
  // Register the web app in the Firebase console, then paste its appId:
  appId: "PASTE_WEB_APP_ID_HERE",
};

// The ONLY Gmail that may open Ruby Key (enforced here AND in the
// Firestore security rules - any other Gmail is signed out instantly).
window.RUBY_KEY_ADMIN_EMAIL = "Ahemadjuneja@gmail.com";
