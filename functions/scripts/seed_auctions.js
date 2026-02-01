/**
 * Seed 30 ACTIVE auctions in Firestore for testing.
 *
 * Requirements:
 * - 30 ACTIVE auctions (not drafts)
 * - Balanced across: Watches, Bags, Fashion, Jewelry, Accessories, Collectibles (5 per category)
 * - Fields match app UI: title, categoryGroup, subcategory, state, endsAt, currentPrice, startPrice,
 *   images array with { url, isPrimary } (1–3 images per auction, one primary)
 * - Future endsAt: mix of ending soon (1–3 days) and ending later (5–30 days)
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

// Stable placeholder image URLs (picsum.photos) – app expects { url, isPrimary }
const IMAGE_URLS = [
  'https://picsum.photos/id/1/400/300',
  'https://picsum.photos/id/10/400/300',
  'https://picsum.photos/id/100/400/300',
  'https://picsum.photos/id/1001/400/300',
  'https://picsum.photos/id/1002/400/300',
  'https://picsum.photos/id/1003/400/300',
  'https://picsum.photos/id/1004/400/300',
  'https://picsum.photos/id/1005/400/300',
  'https://picsum.photos/id/101/400/300',
  'https://picsum.photos/id/1011/400/300',
];

// 30 auctions: 5 per category. categoryGroup + subcategory match app defaults.
const SAMPLE_AUCTIONS = [
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Rolex', title: 'Rolex Submariner Date 41mm' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Omega', title: 'Omega Seamaster Diver 300M' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Patek Philippe', title: 'Patek Philippe Nautilus' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Audemars Piguet', title: 'Audemars Piguet Royal Oak' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Tag Heuer', title: 'Tag Heuer Monaco' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Hermès', title: 'Hermès Birkin 30 Togo' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Chanel', title: 'Chanel Classic Flap Medium' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Louis Vuitton', title: 'Louis Vuitton Neverfull MM' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Dior', title: 'Dior Lady D-Lite' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Fendi', title: 'Fendi Baguette Shoulder Bag' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Gucci', title: 'Gucci Wool Blend Overcoat' },
  { categoryGroup: 'fashion', subcategory: 'shoes', brand: 'Christian Louboutin', title: 'Louboutin Pigalle 100' },
  { categoryGroup: 'fashion', subcategory: 'caps', brand: 'Balenciaga', title: 'Balenciaga Logo Cap' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Prada', title: 'Prada Saffiano Jacket' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Burberry', title: 'Burberry Trench Coat' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Cartier', title: 'Cartier Love Bracelet' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Tiffany', title: 'Tiffany Atlas Pendant' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Bulgari', title: 'Bulgari Serpenti Ring' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Van Cleef', title: 'Van Cleef Alhambra Bracelet' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Chopard', title: 'Chopard Happy Diamonds' },
  { categoryGroup: 'accessories', subcategory: 'wallets', brand: 'Bottega Veneta', title: 'Bottega Veneta Leather Wallet' },
  { categoryGroup: 'accessories', subcategory: 'eyewear', brand: 'Ray-Ban', title: 'Ray-Ban Aviator Classic' },
  { categoryGroup: 'accessories', subcategory: 'pens', brand: 'Montblanc', title: 'Montblanc Meisterstück' },
  { categoryGroup: 'accessories', subcategory: 'wallets', brand: 'Hermès', title: 'Hermès Bearn Wallet' },
  { categoryGroup: 'accessories', subcategory: 'eyewear', brand: 'Gucci', title: 'Gucci Aviator Sunglasses' },
  { categoryGroup: 'collectibles', subcategory: 'travel_bags', brand: 'Rimowa', title: 'Rimowa Original Cabin' },
  { categoryGroup: 'collectibles', subcategory: 'collectibles', brand: 'Limited Edition', title: 'Limited Edition Art Sculpture' },
  { categoryGroup: 'collectibles', subcategory: 'collectibles', brand: 'Steiff', title: 'Steiff Limited Teddy' },
  { categoryGroup: 'collectibles', subcategory: 'travel_bags', brand: 'Tumi', title: 'Tumi Alpha 3 Expandable' },
  { categoryGroup: 'collectibles', subcategory: 'collectibles', brand: 'Art Piece', title: 'Signed Art Print' },
];

function buildImages(index) {
  const n = 1 + (index % 3); // 1, 2, or 3 images per auction
  const images = [];
  for (let i = 0; i < n; i++) {
    const urlIndex = (index + i) % IMAGE_URLS.length;
    images.push({
      url: IMAGE_URLS[urlIndex],
      isPrimary: i === 0,
    });
  }
  return images;
}

function buildAuction(sellerId, sample, index) {
  const now = new Date();
  // Mix of ending soon (1–3 days), mid (5–14 days), later (15–30 days)
  let daysFromNow;
  if (index < 10) {
    daysFromNow = 1 + (index % 3);
  } else if (index < 20) {
    daysFromNow = 5 + (index % 10);
  } else {
    daysFromNow = 15 + (index % 16);
  }
  const endsAt = new Date(now.getTime() + daysFromNow * 24 * 60 * 60 * 1000);

  return {
    sellerId,
    ownerUid: sellerId,
    categoryGroup: sample.categoryGroup,
    subcategory: sample.subcategory,
    category: sample.subcategory,
    brand: sample.brand,
    title: sample.title,
    description: `Premium ${sample.title}. Authentic, excellent condition. Ideal for collectors.`,
    condition: index % 3 === 0 ? 'Like New' : index % 3 === 1 ? 'Excellent' : 'Good',
    itemIdentifier: `SEED-${Date.now()}-${index}`,
    images: buildImages(index),
    startPrice: 500 + index * 100,
    reservePrice: 600 + index * 100,
    currentPrice: 500 + index * 100,
    currentWinnerId: null,
    bidCount: 0,
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

  const count = 30;
  // Firestore batch limit is 500; we write 30 docs
  const batch = db.batch();
  for (let i = 0; i < count; i++) {
    const sample = SAMPLE_AUCTIONS[i];
    const ref = db.collection('auctions').doc();
    batch.set(ref, buildAuction(sellerId, sample, i));
  }
  await batch.commit();
  console.log(`Created ${count} ACTIVE auctions.`);
  console.log('Categories: 5 Watches, 5 Bags, 5 Fashion, 5 Jewelry, 5 Accessories, 5 Collectibles.');
  console.log('Open the app: Home and Explore should list them; tap any to open Auction Detail.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
