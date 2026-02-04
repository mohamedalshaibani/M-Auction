/**
 * Reset auctions and seed test data.
 *
 * Requirements:
 * - Remove all existing auctions
 * - Create 100 ACTIVE auctions with mixed end dates:
 *   - Some ending in 3 days
 *   - Some ending in 5 days
 *   - Some ending in 7+ days
 * - Semi-realistic data (new/used watches, bags, jewelry, fashion, etc.)
 * - Multiple images per product using public image URLs
 * - Seed 3 sample partner ads
 *
 * Prerequisites:
 * - Firebase project (default: luxuryauction-e9c56 from .firebaserc)
 * - Service account key with Firestore write access (Admin SDK bypasses security rules)
 *
 * Run from project root:
 *   cd functions && GOOGLE_APPLICATION_CREDENTIALS=../serviceAccountKey.json node scripts/seed_auctions.js
 *
 * Or from functions directory:
 *   GOOGLE_APPLICATION_CREDENTIALS=../serviceAccountKey.json npm run seed-auctions
 *
 * Optional: SEED_SELLER_UID=someExistingUserId to use a specific user as seller for all seed auctions.
 * If not set, the script uses the first user from the users collection, or a placeholder.
 */

const admin = require('firebase-admin');

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'luxuryauction-e9c56';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

const MIN_INCREMENT = 10;
const ANTI_SNIPING_WINDOW = 5;
const ANTI_SNIPING_EXTEND = 3;

const CONDITIONS = ['New', 'Like New', 'Excellent', 'Good', 'Pre-owned'];
const TITLE_SUFFIXES = ['Full Set', 'Box & Papers', 'Limited Edition', 'Classic', 'Heritage'];

const CATEGORY_CATALOG = [
  {
    key: 'watches',
    subcategory: 'watches',
    priceBase: 3500,
    priceStep: 500,
    items: [
      { brand: 'Rolex', title: 'Submariner Date 41mm' },
      { brand: 'Omega', title: 'Seamaster Diver 300M' },
      { brand: 'Patek Philippe', title: 'Nautilus' },
      { brand: 'Audemars Piguet', title: 'Royal Oak' },
      { brand: 'Cartier', title: 'Santos' },
      { brand: 'IWC', title: 'Portugieser Chronograph' },
      { brand: 'Breitling', title: 'Navitimer' },
      { brand: 'Vacheron Constantin', title: 'Overseas' },
      { brand: 'Hublot', title: 'Big Bang' },
      { brand: 'Panerai', title: 'Luminor Marina' },
      { brand: 'Tudor', title: 'Black Bay Fifty-Eight' },
      { brand: 'Grand Seiko', title: 'Heritage Spring Drive' },
    ],
    images: [
      'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1524592094714-0f0654e20314?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1522312346375-d1a52e2b99b3?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1508057198894-247b23fe5ade?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1526045431048-d5d2b6b8d6a5?auto=format&fit=crop&w=900&q=80',
    ],
  },
  {
    key: 'bags',
    subcategory: 'bags',
    priceBase: 2200,
    priceStep: 350,
    items: [
      { brand: 'Hermès', title: 'Birkin 30 Togo' },
      { brand: 'Chanel', title: 'Classic Flap Medium' },
      { brand: 'Louis Vuitton', title: 'Neverfull MM' },
      { brand: 'Dior', title: 'Lady D-Lite' },
      { brand: 'Fendi', title: 'Baguette Shoulder Bag' },
      { brand: 'Celine', title: 'Luggage Tote' },
      { brand: 'Prada', title: 'Re-Edition 2005' },
      { brand: 'Bottega Veneta', title: 'Jodie Mini' },
      { brand: 'Goyard', title: 'Saint Louis PM' },
      { brand: 'Loewe', title: 'Puzzle Bag' },
    ],
    images: [
      'https://images.unsplash.com/photo-1584917865442-de89df76afd3?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1518544801976-3e159e50e5bb?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=900&q=80',
    ],
  },
  {
    key: 'fashion',
    subcategory: 'clothing',
    priceBase: 700,
    priceStep: 120,
    items: [
      { brand: 'Gucci', title: 'Wool Blend Overcoat' },
      { brand: 'Prada', title: 'Saffiano Jacket' },
      { brand: 'Balenciaga', title: 'Logo Cap' },
      { brand: 'Burberry', title: 'Trench Coat' },
      { brand: 'Saint Laurent', title: 'Leather Biker Jacket' },
      { brand: 'Givenchy', title: 'Streetwear Hoodie' },
      { brand: 'Moncler', title: 'Down Jacket' },
      { brand: 'Loewe', title: 'Anagram Sweater' },
      { brand: 'Alexander McQueen', title: 'Tailored Blazer' },
      { brand: 'Tom Ford', title: 'Silk Shirt' },
    ],
    images: [
      'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1503341455253-b2e723bb3dbb?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=900&q=80',
    ],
  },
  {
    key: 'jewelry',
    subcategory: 'jewelry',
    priceBase: 1500,
    priceStep: 250,
    items: [
      { brand: 'Cartier', title: 'Love Bracelet' },
      { brand: 'Tiffany', title: 'Atlas Pendant' },
      { brand: 'Bulgari', title: 'Serpenti Ring' },
      { brand: 'Van Cleef', title: 'Alhambra Bracelet' },
      { brand: 'Chopard', title: 'Happy Diamonds' },
      { brand: 'Graff', title: 'Diamond Pendant' },
      { brand: 'Piaget', title: 'Possession Ring' },
      { brand: 'Chaumet', title: 'Liens Necklace' },
      { brand: 'Messika', title: 'Move Necklace' },
    ],
    images: [
      'https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1506634572416-48cdfe530110?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1522312346375-d1a52e2b99b3?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1518544889280-7f72b0b22778?auto=format&fit=crop&w=900&q=80',
    ],
  },
  {
    key: 'accessories',
    subcategory: 'wallets',
    priceBase: 400,
    priceStep: 60,
    items: [
      { brand: 'Bottega Veneta', title: 'Leather Wallet' },
      { brand: 'Hermès', title: 'Bearn Wallet' },
      { brand: 'Montblanc', title: 'Meisterstück Pen' },
      { brand: 'Ray-Ban', title: 'Aviator Classic' },
      { brand: 'Gucci', title: 'Aviator Sunglasses' },
      { brand: 'Tumi', title: 'Passport Wallet' },
      { brand: 'S.T. Dupont', title: 'Lighter Set' },
      { brand: 'Ferragamo', title: 'Gancini Belt' },
      { brand: 'Oliver Peoples', title: 'Finley Esq. Sunglasses' },
    ],
    images: [
      'https://images.unsplash.com/photo-1526045431048-d5d2b6b8d6a5?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1503602642458-232111445657?auto=format&fit=crop&w=900&q=80',
    ],
  },
  {
    key: 'collectibles',
    subcategory: 'collectibles',
    priceBase: 800,
    priceStep: 150,
    items: [
      { brand: 'Rimowa', title: 'Original Cabin' },
      { brand: 'Limited Edition', title: 'Art Sculpture' },
      { brand: 'Steiff', title: 'Limited Teddy' },
      { brand: 'Tumi', title: 'Alpha 3 Expandable' },
      { brand: 'Art Piece', title: 'Signed Art Print' },
      { brand: 'Vintage', title: 'Camera Collection' },
      { brand: 'Collectible', title: 'Designer Figurine' },
      { brand: 'Heritage', title: 'Travel Trunk' },
      { brand: 'Leica', title: 'M Series Camera' },
    ],
    images: [
      'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1503602642458-232111445657?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=900&q=80',
    ],
  },
];

const ADS = [
  {
    partnerId: 'aurora-watches',
    partnerName: 'Aurora Watches',
    imageUrl: 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=1200&q=80',
    linkUrl: 'https://example.com/aurora',
    order: 3,
  },
  {
    partnerId: 'luxe-travel',
    partnerName: 'Luxe Travel Co.',
    imageUrl: 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
    linkUrl: 'https://example.com/luxetravel',
    order: 2,
  },
  {
    partnerId: 'maison-elegance',
    partnerName: 'Maison Elegance',
    imageUrl: 'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=1200&q=80',
    linkUrl: 'https://example.com/maison',
    order: 1,
  },
];

const CATEGORY_WEIGHTS = [
  { key: 'watches', weight: 4 },
  { key: 'bags', weight: 3 },
  { key: 'jewelry', weight: 2 },
  { key: 'fashion', weight: 2 },
  { key: 'accessories', weight: 1 },
  { key: 'collectibles', weight: 1 },
];

function buildCategoryPool() {
  const pool = [];
  for (const entry of CATEGORY_WEIGHTS) {
    const category = CATEGORY_CATALOG.find((c) => c.key === entry.key);
    if (!category) continue;
    for (let i = 0; i < entry.weight; i++) {
      pool.push(category);
    }
  }
  return pool;
}

function buildImages(category, index) {
  const count = 2 + (index % 3); // 2, 3, or 4 images per auction
  const images = [];
  for (let i = 0; i < count; i++) {
    const urlIndex = (index + i) % category.images.length;
    images.push({
      url: category.images[urlIndex],
      isPrimary: i === 0,
    });
  }
  return images;
}

function daysFromNowForIndex(index) {
  if (index < 30) return 3;
  if (index < 60) return 5;
  return 7 + (index % 8); // 7-14 days
}

function buildAuction(sellerId, category, item, index) {
  const now = new Date();
  const endsAt = new Date(now.getTime() + daysFromNowForIndex(index) * 24 * 60 * 60 * 1000);
  const condition = CONDITIONS[index % CONDITIONS.length];
  const suffix = TITLE_SUFFIXES[index % TITLE_SUFFIXES.length];
  const year = 2016 + (index % 9);
  const startPrice = category.priceBase + (index % 10) * category.priceStep;
  const currentPrice = startPrice + (index % 4) * Math.round(category.priceStep / 2);

  return {
    sellerId,
    ownerUid: sellerId,
    categoryGroup: category.key,
    subcategory: category.subcategory,
    category: category.subcategory,
    brand: item.brand,
    title: `${item.brand} ${item.title} ${suffix}`,
    description: `${item.brand} ${item.title}, ${condition} condition. Includes accessories. Year ${year}.`,
    condition,
    itemIdentifier: `SEED-${Date.now()}-${index}`,
    images: buildImages(category, index),
    startPrice,
    reservePrice: startPrice + category.priceStep,
    currentPrice,
    currentWinnerId: null,
    bidCount: index % 12,
    state: 'ACTIVE',
    endsAt: admin.firestore.Timestamp.fromDate(endsAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    minIncrement: MIN_INCREMENT,
    antiSnipingWindowMinutes: ANTI_SNIPING_WINDOW,
    antiSnipingExtendMinutes: ANTI_SNIPING_EXTEND,
    winnerContactReleased: false,
    sellerConfirmedDelivery: false,
    buyerConfirmedDelivery: false,
    contactUnlockAt: null,
    listingFeePaid: true,
    activatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function clearCollection(name) {
  const snap = await db.collection(name).get();
  if (snap.empty) {
    console.log(`No documents to clear in ${name}`);
    return;
  }
  const deletes = snap.docs.map((doc) => {
    if (typeof db.recursiveDelete === 'function') {
      return db.recursiveDelete(doc.ref);
    }
    return doc.ref.delete();
  });
  await Promise.all(deletes);
  console.log(`Cleared ${snap.size} documents from ${name}`);
}

async function getSeedSellerUid() {
  const envUid = process.env.SEED_SELLER_UID;
  if (envUid) return envUid;
  const usersSnap = await db.collection('users').limit(1).get();
  if (!usersSnap.empty) return usersSnap.docs[0].id;
  return 'seed-seller-placeholder';
}

async function main() {
  console.log('Using project:', PROJECT_ID);
  const sellerId = await getSeedSellerUid();
  console.log('Seller UID for seed auctions:', sellerId);
  await clearCollection('auctions');
  await clearCollection('ads');

  const count = 100;
  const categoryPool = buildCategoryPool();
  const batch = db.batch();
  for (let i = 0; i < count; i++) {
    const category = categoryPool[i % categoryPool.length];
    const item = category.items[i % category.items.length];
    const ref = db.collection('auctions').doc();
    batch.set(ref, buildAuction(sellerId, category, item, i));
  }
  await batch.commit();
  console.log(`Created ${count} ACTIVE auctions.`);

  const adsRef = db.collection('ads');
  for (const ad of ADS) {
    await adsRef.doc(ad.partnerId).set({
      partnerId: ad.partnerId,
      partnerName: ad.partnerName,
      imageUrl: ad.imageUrl,
      linkUrl: ad.linkUrl,
      order: ad.order,
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  console.log('Seeded 3 partner ads.');

  console.log('Open the app: Home and Explore should list the auctions.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
