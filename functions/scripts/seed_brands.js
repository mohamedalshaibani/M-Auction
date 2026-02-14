/**
 * Seed the Firestore brands collection.
 *
 * Run: npm run seed-brands   (from functions directory)
 * Or:  node scripts/seed_brands.js
 *
 * Credentials: Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON path, or
 * place serviceAccountKey.json in project root. Alternatively run: gcloud auth application-default login
 */
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function getProjectId() {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  if (process.env.GCP_PROJECT) return process.env.GCP_PROJECT;
  try {
    const firebaserc = path.join(__dirname, '../../.firebaserc');
    const data = JSON.parse(fs.readFileSync(firebaserc, 'utf8'));
    return data?.projects?.default || 'luxuryauction-e9c56';
  } catch {
    return 'luxuryauction-e9c56';
  }
}

function findServiceAccountKey() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const p = path.isAbsolute(process.env.GOOGLE_APPLICATION_CREDENTIALS)
      ? process.env.GOOGLE_APPLICATION_CREDENTIALS
      : path.resolve(process.cwd(), process.env.GOOGLE_APPLICATION_CREDENTIALS);
    if (fs.existsSync(p)) return p;
  }
  const candidates = [
    path.join(__dirname, '../../serviceAccountKey.json'),
    path.join(__dirname, '../serviceAccountKey.json'),
    path.join(process.cwd(), 'serviceAccountKey.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function getInitOptions() {
  const projectId = getProjectId();
  const keyPath = findServiceAccountKey();
  if (keyPath) {
    const key = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
    return {
      projectId,
      credential: admin.credential.cert(key),
    };
  }
  // Fall back to Application Default Credentials (gcloud auth application-default login)
  return { projectId };
}

if (!admin.apps.length) {
  admin.initializeApp(getInitOptions());
}
const db = admin.firestore();

const BRANDS = [
  // watches
  { name: 'Rolex', category: 'watches' },
  { name: 'Patek Philippe', category: 'watches' },
  { name: 'Audemars Piguet', category: 'watches' },
  { name: 'Omega', category: 'watches' },
  { name: 'Cartier', category: 'watches' },
  { name: 'Tag Heuer', category: 'watches' },
  { name: 'Breitling', category: 'watches' },
  { name: 'IWC', category: 'watches' },
  { name: 'Panerai', category: 'watches' },
  { name: 'Tudor', category: 'watches' },
  { name: 'Hublot', category: 'watches' },
  { name: 'Richard Mille', category: 'watches' },
  { name: 'Vacheron Constantin', category: 'watches' },
  { name: 'Jaeger-LeCoultre', category: 'watches' },
  { name: 'Grand Seiko', category: 'watches' },
  { name: 'Hermès', category: 'watches' },
  { name: 'Chanel', category: 'watches' },
  { name: 'Louis Vuitton', category: 'watches' },
  { name: 'Other', category: 'watches' },
  // bags
  { name: 'Hermès', category: 'bags' },
  { name: 'Chanel', category: 'bags' },
  { name: 'Louis Vuitton', category: 'bags' },
  { name: 'Dior', category: 'bags' },
  { name: 'Gucci', category: 'bags' },
  { name: 'Prada', category: 'bags' },
  { name: 'Fendi', category: 'bags' },
  { name: 'Celine', category: 'bags' },
  { name: 'Bottega Veneta', category: 'bags' },
  { name: 'Goyard', category: 'bags' },
  { name: 'Loewe', category: 'bags' },
  { name: 'Other', category: 'bags' },
  // fashion
  { name: 'Gucci', category: 'fashion' },
  { name: 'Prada', category: 'fashion' },
  { name: 'Balenciaga', category: 'fashion' },
  { name: 'Burberry', category: 'fashion' },
  { name: 'Saint Laurent', category: 'fashion' },
  { name: 'Givenchy', category: 'fashion' },
  { name: 'Moncler', category: 'fashion' },
  { name: 'Loewe', category: 'fashion' },
  { name: 'Alexander McQueen', category: 'fashion' },
  { name: 'Tom Ford', category: 'fashion' },
  { name: 'Other', category: 'fashion' },
  // jewelry
  { name: 'Cartier', category: 'jewelry' },
  { name: 'Tiffany', category: 'jewelry' },
  { name: 'Bulgari', category: 'jewelry' },
  { name: 'Van Cleef & Arpels', category: 'jewelry' },
  { name: 'Chopard', category: 'jewelry' },
  { name: 'Graff', category: 'jewelry' },
  { name: 'Piaget', category: 'jewelry' },
  { name: 'Chaumet', category: 'jewelry' },
  { name: 'Other', category: 'jewelry' },
  // accessories
  { name: 'Bottega Veneta', category: 'accessories' },
  { name: 'Hermès', category: 'accessories' },
  { name: 'Montblanc', category: 'accessories' },
  { name: 'Ray-Ban', category: 'accessories' },
  { name: 'Gucci', category: 'accessories' },
  { name: 'Tumi', category: 'accessories' },
  { name: 'Other', category: 'accessories' },
  // collectibles
  { name: 'Rimowa', category: 'collectibles' },
  { name: 'Tumi', category: 'collectibles' },
  { name: 'Leica', category: 'collectibles' },
  { name: 'Other', category: 'collectibles' },
];

function slug(name, category) {
  return `${category}_${name.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '')}`;
}

async function seed() {
  const batch = db.batch();
  for (const b of BRANDS) {
    const id = slug(b.name, b.category);
    const ref = db.collection('brands').doc(id);
    batch.set(ref, {
      name: b.name,
      category: b.category,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
  console.log(`Seeded ${BRANDS.length} brands`);
}

seed().catch((err) => {
  console.error(err.message || err);
  if (/credentials|authentication|UNAUTHENTICATED/i.test(String(err))) {
    console.error('\nTo fix: Download a service account key from Firebase Console → Project Settings → Service Accounts');
    console.error('Save as serviceAccountKey.json in the project root, then run: npm run seed-brands');
    console.error('Or run: gcloud auth application-default login');
  }
  process.exit(1);
});
