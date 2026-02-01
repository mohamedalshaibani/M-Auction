/**
 * Seed 30 ACTIVE auctions in Firestore for testing.
 *
 * Prerequisites:
 * - Firebase project (default from .firebaserc: luxuryauction-e9c56)
 * - Service account key with Firestore write access
 *
 * Run from project root:
 *   cd functions && node scripts/seed_auctions.js
 *
 * Or with explicit credentials:
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json node functions/scripts/seed_auctions.js
 *
 * Optional: SEED_SELLER_UID=someExistingUserId to use a specific user as seller for all seed auctions.
 * If not set, the script uses the first user from the users collection, or a placeholder.
 */

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'luxuryauction-e9c56';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

const MIN_INCREMENT = 10;
const ANTI_SNIPING_WINDOW = 5;
const ANTI_SNIPING_EXTEND = 3;

// Placeholder image (public) so auction cards show something
const PLACEHOLDER_IMAGE = 'https://via.placeholder.com/400x300/f5f5f5/666?text=Luxury+Item';

const SAMPLE_AUCTIONS = [
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Rolex', title: 'Rolex Submariner Date 41mm' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Omega', title: 'Omega Seamaster Diver 300M' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Patek Philippe', title: 'Patek Philippe Nautilus' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Hermès', title: 'Hermès Birkin 30 Togo' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Chanel', title: 'Chanel Classic Flap Medium' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Louis Vuitton', title: 'Louis Vuitton Neverfull MM' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Gucci', title: 'Gucci Wool Blend Overcoat' },
  { categoryGroup: 'fashion', subcategory: 'shoes', brand: 'Christian Louboutin', title: 'Louboutin Pigalle 100' },
  { categoryGroup: 'fashion', subcategory: 'caps', brand: 'Balenciaga', title: 'Balenciaga Logo Cap' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Cartier', title: 'Cartier Love Bracelet' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Tiffany', title: 'Tiffany Atlas Pendant' },
  { categoryGroup: 'accessories', subcategory: 'wallets', brand: 'Bottega Veneta', title: 'Bottega Veneta Leather Wallet' },
  { categoryGroup: 'accessories', subcategory: 'eyewear', brand: 'Ray-Ban', title: 'Ray-Ban Aviator Classic' },
  { categoryGroup: 'accessories', subcategory: 'pens', brand: 'Montblanc', title: 'Montblanc Meisterstück' },
  { categoryGroup: 'collectibles', subcategory: 'travel_bags', brand: 'Rimowa', title: 'Rimowa Original Cabin' },
  { categoryGroup: 'collectibles', subcategory: 'collectibles', brand: 'Limited Edition', title: 'Limited Edition Art Sculpture' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Audemars Piguet', title: 'Audemars Piguet Royal Oak' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Dior', title: 'Dior Lady D-Lite' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Prada', title: 'Prada Saffiano Jacket' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Bulgari', title: 'Bulgari Serpenti Ring' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'Tag Heuer', title: 'Tag Heuer Monaco' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Bottega Veneta', title: 'Bottega Veneta Cassette Bag' },
  { categoryGroup: 'fashion', subcategory: 'shoes', brand: 'Gucci', title: 'Gucci Horsebit Loafer' },
  { categoryGroup: 'accessories', subcategory: 'wallets', brand: 'Hermès', title: 'Hermès Bearn Wallet' },
  { categoryGroup: 'collectibles', subcategory: 'collectibles', brand: 'Steiff', title: 'Steiff Limited Teddy' },
  { categoryGroup: 'watches', subcategory: 'watches', brand: 'IWC', title: 'IWC Portugieser Chronograph' },
  { categoryGroup: 'jewelry', subcategory: 'jewelry', brand: 'Van Cleef', title: 'Van Cleef Alhambra Bracelet' },
  { categoryGroup: 'fashion', subcategory: 'clothing', brand: 'Burberry', title: 'Burberry Trench Coat' },
  { categoryGroup: 'accessories', subcategory: 'eyewear', brand: 'Gucci', title: 'Gucci Aviator Sunglasses' },
  { categoryGroup: 'bags', subcategory: 'bags', brand: 'Fendi', title: 'Fendi Baguette Shoulder Bag' },
];

function buildAuction(sellerId, sample, index) {
  const now = new Date();
  const endsAt = new Date(now.getTime() + (7 + index) * 24 * 60 * 60 * 1000); // 7–36 days from now
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
    images: [{ url: PLACEHOLDER_IMAGE, isPrimary: true }],
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

  const batch = db.batch();
  const count = Math.min(30, SAMPLE_AUCTIONS.length);
  for (let i = 0; i < count; i++) {
    const sample = SAMPLE_AUCTIONS[i % SAMPLE_AUCTIONS.length];
    const ref = db.collection('auctions').doc();
    batch.set(ref, buildAuction(sellerId, sample, i));
  }
  await batch.commit();
  console.log(`Created ${count} ACTIVE auctions.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
