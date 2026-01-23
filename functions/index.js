const functions = require('firebase-functions');
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const admin = require('firebase-admin');
const stripeSecretKey = functions.config().stripe?.secret_key || 
                        process.env.STRIPE_SECRET_KEY;
const stripe = require('stripe')(stripeSecretKey);
const {Storage} = require('@google-cloud/storage');
const sharp = require('sharp');

admin.initializeApp();
const db = admin.firestore();
const storage = new Storage();

// Create PaymentIntent
exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const uid = context.auth.uid; // Use authenticated user's UID
  const {type, amount, currency = 'aed', auctionId = null} = data;

  // Log request for debugging
  console.log('createPaymentIntent request:', {
    uid,
    type,
    amount,
    amountType: typeof amount,
    currency,
    auctionId,
    requestBody: JSON.stringify(data),
  });

  // Validate input
  if (!type || amount === undefined || amount === null) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: type and amount');
  }

  if (type !== 'deposit' && type !== 'listing_fee' && type !== 'buyer_commission' && type !== 'seller_commission') {
    throw new functions.https.HttpsError('invalid-argument', `Invalid payment type: ${type}. Must be 'deposit', 'listing_fee', 'buyer_commission', or 'seller_commission'`);
  }

  // For commission types, auctionId is required
  if ((type === 'buyer_commission' || type === 'seller_commission') && !auctionId) {
    throw new functions.https.HttpsError('invalid-argument', `auctionId is required for ${type} payments`);
  }

  // Parse amount to number (handle string inputs)
  const amountNum = typeof amount === 'string' ? parseFloat(amount) : Number(amount);
  
  if (isNaN(amountNum) || !isFinite(amountNum)) {
    throw new functions.https.HttpsError('invalid-argument', `Invalid amount: ${amount}. Must be a valid number`);
  }

  if (amountNum <= 0) {
    throw new functions.https.HttpsError('invalid-argument', `Amount must be positive, got: ${amountNum}`);
  }

  // Convert amount to minor units (fils for AED)
  // AED uses fils as minor unit (1 AED = 100 fils)
  const currencyLower = currency.toLowerCase();
  let amountInMinorUnits;
  
  if (currencyLower === 'aed') {
    // AED: multiply by 100 to get fils, then round to integer
    amountInMinorUnits = Math.round(amountNum * 100);
  } else {
    // For other currencies, use standard conversion
    amountInMinorUnits = Math.round(amountNum * 100);
  }

  // Validate converted amount is a positive integer
  if (!Number.isInteger(amountInMinorUnits) || amountInMinorUnits <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 
      `Invalid amount after conversion: ${amountInMinorUnits} (from ${amountNum} ${currency}). Must be positive integer.`);
  }

  console.log('Amount conversion:', {
    original: amountNum,
    currency: currencyLower,
    minorUnits: amountInMinorUnits,
    isInteger: Number.isInteger(amountInMinorUnits),
  });

  try {
    // Create payment document first to get paymentId for metadata
    const paymentRef = db.collection('payments').doc();
    const paymentId = paymentRef.id;
    
    // Create PaymentIntent with proper configuration for Payment Element
    const paymentIntentParams = {
      amount: amountInMinorUnits,
      currency: currencyLower,
      metadata: {
        uid: uid,
        type: type,
        auctionId: auctionId || '',
        paymentId: paymentId, // Include paymentId in metadata for webhook lookup
      },
      // Use automatic_payment_methods for Payment Element compatibility
      automatic_payment_methods: {
        enabled: true,
      },
    };

    // For commission types, ensure metadata includes auctionId
    if (type === 'buyer_commission' || type === 'seller_commission') {
      paymentIntentParams.metadata.auctionId = auctionId;
    }

    console.log('Creating PaymentIntent with params:', {
      ...paymentIntentParams,
      amount: amountInMinorUnits,
      amountType: typeof amountInMinorUnits,
    });

    const paymentIntent = await stripe.paymentIntents.create(paymentIntentParams);

    console.log('PaymentIntent created successfully:', {
      id: paymentIntent.id,
      amount: paymentIntent.amount,
      currency: paymentIntent.currency,
      status: paymentIntent.status,
    });

    // Create payment document in Firestore (paymentId already created above)
    const paymentData = {
      uid: uid,
      type: type,
      auctionId: (type === 'buyer_commission' || type === 'seller_commission' || type === 'listing_fee') ? auctionId : (auctionId || null),
      amount: amountNum, // Store original amount (major currency units)
      currency: currency,
      stripePaymentIntentId: paymentIntent.id,
      status: 'created',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await paymentRef.set(paymentData);

    return {
      clientSecret: paymentIntent.client_secret,
      paymentId: paymentId,
    };
  } catch (error) {
    // Detailed error logging
    const errorDetails = {
      message: error.message,
      type: error.type,
      code: error.code,
      raw: error.raw ? {
        message: error.raw.message,
        param: error.raw.param,
        type: error.raw.type,
        code: error.raw.code,
      } : null,
      requestBody: {
        type,
        amount: amountNum,
        currency: currencyLower,
        amountInMinorUnits,
        auctionId,
      },
    };

    console.error('Error creating PaymentIntent - Full details:', JSON.stringify(errorDetails, null, 2));
    console.error('Error stack:', error.stack);

    // Return detailed error message
    const errorMessage = error.raw?.message || error.message || 'Unknown error';
    const errorParam = error.raw?.param ? ` (parameter: ${error.raw.param})` : '';
    
    throw new functions.https.HttpsError(
      'internal',
      `Failed to create payment intent: ${errorMessage}${errorParam}. Amount: ${amountNum} ${currency} = ${amountInMinorUnits} minor units.`
    );
  }
});

// Create ephemeral payment record (called after creating PaymentIntent)
exports.createEphemeralPaymentRecord = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const {paymentId, stripePaymentIntentId} = data;

  if (!paymentId || !stripePaymentIntentId) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  // Verify payment belongs to user
  const paymentDoc = await db.collection('payments').doc(paymentId).get();
  if (!paymentDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Payment not found');
  }

  const paymentData = paymentDoc.data();
  if (paymentData.uid !== context.auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'Not authorized');
  }

  // Update payment record with stripePaymentIntentId if not set
  if (!paymentData.stripePaymentIntentId) {
    await paymentDoc.ref.update({
      stripePaymentIntentId: stripePaymentIntentId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return {success: true};
});

// Forfeit or refund (admin only)
exports.forfeitOrRefund = functions.https.onCall(async (data, context) => {
  // Verify authentication and admin status
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  // Check if user is admin
  const userDoc = await db.collection('users').doc(context.auth.uid).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError('permission-denied', 'User not found');
  }

  const userData = userDoc.data();
  if (userData.role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Admin access required');
  }

  const {auctionId, uid, action, amount} = data;

  if (!auctionId || !uid || !action || !amount) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required fields');
  }

  if (action !== 'forfeit' && action !== 'refund') {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid action (must be "forfeit" or "refund")');
  }

  try {
    // Find payment for this auction and user
    const paymentsSnapshot = await db.collection('payments')
      .where('uid', '==', uid)
      .where('auctionId', '==', auctionId)
      .where('type', '==', 'deposit')
      .where('status', '==', 'succeeded')
      .limit(1)
      .get();

    if (paymentsSnapshot.empty) {
      throw new functions.https.HttpsError('not-found', 'Payment not found for this auction');
    }

    const paymentDoc = paymentsSnapshot.docs[0];
    const paymentData = paymentDoc.data();
    const stripePaymentIntentId = paymentData.stripePaymentIntentId;
    const paymentId = paymentDoc.id;

    let result;

    if (action === 'forfeit') {
      // For MVP, record forfeit in Firestore (manual Stripe refund can be done separately)
      // Update wallet - move from locked to forfeited
      const walletRef = db.collection('wallets').doc(uid);
      await walletRef.update({
        lockedDeposit: admin.firestore.FieldValue.increment(-amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Create forfeit payment record
      const forfeitPaymentRef = db.collection('payments').doc();
      await forfeitPaymentRef.set({
        uid: uid,
        type: 'forfeit',
        auctionId: auctionId,
        amount: amount,
        currency: 'aed',
        stripePaymentIntentId: stripePaymentIntentId,
        relatedPaymentId: paymentId,
        status: 'succeeded',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update original payment status
      await paymentDoc.ref.update({
        status: 'forfeited',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      result = {status: 'forfeited', paymentId: forfeitPaymentRef.id};
    } else {
      // Refund via Stripe
      const amountInCents = Math.round(amount * 100);
      
      // Get the charge ID from PaymentIntent
      const paymentIntent = await stripe.paymentIntents.retrieve(stripePaymentIntentId);
      const chargeId = paymentIntent.latest_charge;
      
      // Create refund
      const refund = await stripe.refunds.create({
        charge: chargeId,
        amount: amountInCents,
      });

      result = {status: 'refunded', refundId: refund.id};

      // Update wallet - move from locked to available
      const walletRef = db.collection('wallets').doc(uid);
      await walletRef.update({
        lockedDeposit: admin.firestore.FieldValue.increment(-amount),
        availableDeposit: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Create refund payment record
      const refundPaymentRef = db.collection('payments').doc();
      await refundPaymentRef.set({
        uid: uid,
        type: 'refund',
        auctionId: auctionId,
        amount: amount,
        currency: 'aed',
        stripePaymentIntentId: stripePaymentIntentId,
        refundId: refund.id,
        relatedPaymentId: paymentId,
        status: 'succeeded',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update original payment status
      await paymentDoc.ref.update({
        status: 'refunded',
        refundId: refund.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      result.paymentId = refundPaymentRef.id;
    }

    return result;
  } catch (error) {
    console.error('Error in forfeit/refund:', error);
    throw new functions.https.HttpsError('internal', `Failed to ${action} payment: ${error.message}`);
  }
});

// Stripe webhook handler
exports.stripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const webhookSecret = functions.config().stripe?.webhook_secret || 
                       process.env.STRIPE_WEBHOOK_SECRET;

  if (!webhookSecret) {
    console.error('Webhook secret not configured');
    return res.status(500).send('Webhook secret not configured');
  }

  let event;

  try {
    // Get raw body - Firebase Functions provides req.rawBody for webhooks
    // If not available, use req.body as Buffer or string
    let payload;
    if (req.rawBody) {
      payload = req.rawBody;
    } else if (Buffer.isBuffer(req.body)) {
      payload = req.body;
    } else if (typeof req.body === 'string') {
      payload = Buffer.from(req.body);
    } else {
      payload = Buffer.from(JSON.stringify(req.body));
    }

    event = stripe.webhooks.constructEvent(
      payload,
      sig,
      webhookSecret
    );
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  try {
    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentIntentSucceeded(event.data.object);
        break;
      case 'payment_intent.payment_failed':
        await handlePaymentIntentFailed(event.data.object);
        break;
      case 'charge.refunded':
        await handleChargeRefunded(event.data.object);
        break;
      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    res.json({received: true});
  } catch (error) {
    console.error('Error processing webhook:', error);
    res.status(500).send('Webhook processing error');
  }
});

async function handlePaymentIntentSucceeded(paymentIntent) {
  const paymentIntentId = paymentIntent.id;
  const metadata = paymentIntent.metadata;
  const uid = metadata.uid;
  const type = metadata.type;
  const auctionId = metadata.auctionId;
  const paymentIdFromMetadata = metadata.paymentId; // Preferred: use paymentId from metadata
  const amount = paymentIntent.amount / 100; // Convert from cents

  // Find payment document: prefer paymentId from metadata, fallback to stripePaymentIntentId
  let paymentDoc;
  if (paymentIdFromMetadata) {
    const paymentRef = db.collection('payments').doc(paymentIdFromMetadata);
    paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists) {
      console.warn('Payment document not found by paymentId from metadata:', paymentIdFromMetadata);
      // Fallback to stripePaymentIntentId lookup
      const paymentsSnapshot = await db.collection('payments')
        .where('stripePaymentIntentId', '==', paymentIntentId)
        .limit(1)
        .get();
      if (paymentsSnapshot.empty) {
        console.error('Payment document not found for PaymentIntent:', paymentIntentId);
        return;
      }
      paymentDoc = paymentsSnapshot.docs[0];
    }
  } else {
    // Fallback: find by stripePaymentIntentId
    const paymentsSnapshot = await db.collection('payments')
      .where('stripePaymentIntentId', '==', paymentIntentId)
      .limit(1)
      .get();
    if (paymentsSnapshot.empty) {
      console.error('Payment document not found for PaymentIntent:', paymentIntentId);
      return;
    }
    paymentDoc = paymentsSnapshot.docs[0];
  }

  const paymentId = paymentDoc.id;

    // Update payment status
    await paymentDoc.ref.update({
      status: 'succeeded',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (type === 'deposit') {
      // Update wallet
      const walletRef = db.collection('wallets').doc(uid);
      await walletRef.update({
        availableDeposit: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else if (type === 'listing_fee' && auctionId) {
      // Update auction and activate
      const auctionRef = db.collection('auctions').doc(auctionId);
      const auctionDoc = await auctionRef.get();
      
      if (auctionDoc.exists) {
        const auctionData = auctionDoc.data();
        const state = auctionData.state;
        
        // Update auction with payment info
        await auctionRef.update({
          listingFeePaid: true,
          listingFeePaymentId: paymentId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        // Activate auction if it's in APPROVED_AWAITING_PAYMENT state
        if (state === 'APPROVED_AWAITING_PAYMENT') {
          await auctionRef.update({
            state: 'ACTIVE',
            activatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    } else if (type === 'buyer_commission' && auctionId) {
      // Handle buyer commission payment
      const auctionRef = db.collection('auctions').doc(auctionId);
      
      // Use transaction to ensure atomic update
      await db.runTransaction(async (tx) => {
        const auctionDoc = await tx.get(auctionRef);
        if (!auctionDoc.exists) {
          throw new Error('Auction not found');
        }
        
        const auctionData = auctionDoc.data();
        const sellerCommissionPaid = auctionData.sellerCommissionPaid || false;
        
        // Update auction with buyer commission payment
        const updateData = {
          buyerCommissionPaid: true,
          buyerCommissionPaymentId: paymentId,
          buyerCommissionPaidAt: admin.firestore.FieldValue.serverTimestamp(),
          // Set commissionStatus based on seller payment status
          commissionStatus: sellerCommissionPaid ? 'paid' : 'buyer_paid',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        
        // Also set winnerContactReleased=true (optional, UI already gates by buyerCommissionPaid)
        if (!auctionData.winnerContactReleased) {
          updateData.winnerContactReleased = true;
        }
        
        tx.update(auctionRef, updateData);
        
        // Create platformRevenue document for buyer commission
        const revenueRef = db.collection('platformRevenue').doc();
        tx.set(revenueRef, {
          auctionId: auctionId,
          uid: uid,
          amount: amount,
          currency: 'AED',
          type: 'buyer_commission',
          source: 'commission',
          status: 'paid',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      
      console.log('Buyer commission payment processed:', {
        auctionId,
        paymentId,
        amount,
      });
    } else if (type === 'seller_commission' && auctionId) {
      // Handle seller commission payment
      const auctionRef = db.collection('auctions').doc(auctionId);
      
      // Get seller ID from auction
      const auctionDoc = await auctionRef.get();
      if (!auctionDoc.exists) {
        throw new Error('Auction not found');
      }
      const auctionData = auctionDoc.data();
      const sellerId = auctionData.sellerId;
      
      // Use transaction to ensure atomic update
      await db.runTransaction(async (tx) => {
        const auctionDocTx = await tx.get(auctionRef);
        if (!auctionDocTx.exists) {
          throw new Error('Auction not found');
        }
        
        const auctionDataTx = auctionDocTx.data();
        const buyerCommissionPaid = auctionDataTx.buyerCommissionPaid || false;
        
        // Update auction with seller commission payment
        tx.update(auctionRef, {
          sellerCommissionPaid: true,
          sellerCommissionPaymentId: paymentId,
          sellerCommissionPaidAt: admin.firestore.FieldValue.serverTimestamp(),
          // Set commissionStatus to 'paid' if both commissions are paid
          commissionStatus: buyerCommissionPaid ? 'paid' : 'seller_paid',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        // Create platformRevenue document for seller commission
        const revenueRef = db.collection('platformRevenue').doc();
        tx.set(revenueRef, {
          auctionId: auctionId,
          uid: sellerId || uid, // Use sellerId from auction, fallback to uid from payment
          amount: amount,
          currency: 'AED',
          type: 'seller_commission',
          source: 'commission',
          status: 'paid',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      
      console.log('Seller commission payment processed:', {
        auctionId,
        paymentId,
        amount,
      });
    }
}

async function handlePaymentIntentFailed(paymentIntent) {
  const paymentIntentId = paymentIntent.id;

  // Find payment document
  const paymentsSnapshot = await db.collection('payments')
    .where('stripePaymentIntentId', '==', paymentIntentId)
    .limit(1)
    .get();

  if (paymentsSnapshot.empty) {
    console.error('Payment document not found for PaymentIntent:', paymentIntentId);
    return;
  }

  const paymentDoc = paymentsSnapshot.docs[0];

  // Update payment status
  await paymentDoc.ref.update({
    status: 'failed',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function handleChargeRefunded(charge) {
  const paymentIntentId = charge.payment_intent;

  // Find payment document
  const paymentsSnapshot = await db.collection('payments')
    .where('stripePaymentIntentId', '==', paymentIntentId)
    .limit(1)
    .get();

  if (paymentsSnapshot.empty) {
    console.error('Payment document not found for PaymentIntent:', paymentIntentId);
    return;
  }

  const paymentDoc = paymentsSnapshot.docs[0];
  const paymentData = paymentDoc.data();
  const uid = paymentData.uid;
  const refundAmount = charge.amount_refunded / 100; // Convert from cents

  // Update payment status
  await paymentDoc.ref.update({
    status: 'refunded',
    refundId: charge.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Update wallet if it was a deposit
  if (paymentData.type === 'deposit') {
    const walletRef = db.collection('wallets').doc(uid);
    await walletRef.update({
      availableDeposit: admin.firestore.FieldValue.increment(refundAmount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

// Scheduled function to enforce winner deadline (runs every 5 minutes)
exports.enforceWinnerDeadline = functions.pubsub.schedule('every 5 minutes').onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
  
  // Query auctions that need enforcement
  const auctionsSnapshot = await db.collection('auctions')
    .where('state', '==', 'ENDED')
    .where('buyerConfirmedPurchase', '==', false)
    .where('winnerDeadlineAt', '<=', now)
    .get();

  console.log(`Found ${auctionsSnapshot.size} auctions to enforce deadline`);

  for (const auctionDoc of auctionsSnapshot.docs) {
    const auctionId = auctionDoc.id;
    const auctionData = auctionDoc.data();
    const winnerId = auctionData.currentWinnerId;
    
    if (!winnerId) {
      console.log(`Skipping auction ${auctionId}: no winner`);
      continue;
    }

    // Skip if already forfeited
    if (auctionData.depositStatus === 'forfeited' || auctionData.state === 'ENDED_NO_RESPONSE') {
      console.log(`Skipping auction ${auctionId}: already forfeited`);
      continue;
    }

    try {
      // Get finalPrice or currentPrice
      const finalPrice = auctionData.finalPrice || auctionData.currentPrice || 0;
      
      // Get forfeit rules from adminSettings
      const settingsDoc = await db.collection('adminSettings').doc('main').get();
      if (!settingsDoc.exists) {
        console.error('Admin settings not found');
        continue;
      }
      
      const settings = settingsDoc.data();
      const forfeitRules = settings.forfeitRules || {};
      const tiers = forfeitRules.tiers || [];
      
      // Compute forfeit amount
      let forfeitAmount = 0;
      for (const tier of tiers) {
        const minValue = tier.min || 0;
        const maxValue = tier.max;
        const rate = tier.rate || 0;
        
        if (maxValue != null) {
          if (finalPrice >= minValue && finalPrice <= maxValue) {
            forfeitAmount = finalPrice * rate;
            break;
          }
        } else {
          // No max means highest tier
          if (finalPrice >= minValue) {
            forfeitAmount = finalPrice * rate;
            break;
          }
        }
      }

      // Process forfeit in transaction
      await db.runTransaction(async (tx) => {
        const walletRef = db.collection('wallets').doc(winnerId);
        const walletDoc = await tx.get(walletRef);
        
        if (!walletDoc.exists) {
          throw new Error('Winner wallet not found');
        }
        
        const walletData = walletDoc.data();
        const reservedDeposit = walletData.reservedDeposit || 0;
        
        // Take minimum of forfeitAmount and reservedDeposit
        const take = Math.min(forfeitAmount, reservedDeposit);
        
        if (take > 0) {
          // Deduct from reservedDeposit
          tx.update(walletRef, {
            reservedDeposit: admin.firestore.FieldValue.increment(-take),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        
        // Create platformRevenue document
        const revenueRef = db.collection('platformRevenue').doc();
        tx.set(revenueRef, {
          auctionId: auctionId,
          uid: winnerId,
          amount: take,
          currency: 'AED',
          type: 'forfeit',
          source: 'forfeit',
          status: 'paid',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        // Update auction
        tx.update(auctionDoc.ref, {
          state: 'ENDED_NO_RESPONSE',
          depositStatus: 'forfeited',
          forfeitAmount: take,
          forfeitedAt: admin.firestore.FieldValue.serverTimestamp(),
          commissionStatus: 'forfeited',
          winnerContactReleased: false,
        });
      });
      
      console.log(`Forfeited ${take} AED from winner ${winnerId} for auction ${auctionId}`);
    } catch (error) {
      console.error(`Error enforcing deadline for auction ${auctionId}:`, error);
    }
  }

  return null;
});

// Scheduled function to close ended auctions (runs every 1 minute)
exports.closeEndedAuctions = functions.pubsub.schedule('every 1 minutes').onRun(async (context) => {
  const now = admin.firestore.Timestamp.now();
  
  // Query active auctions that should have ended
  const auctionsSnapshot = await db.collection('auctions')
    .where('state', '==', 'ACTIVE')
    .where('endsAt', '<=', now)
    .get();

  console.log(`Found ${auctionsSnapshot.size} auctions to close`);

  for (const auctionDoc of auctionsSnapshot.docs) {
    const auctionId = auctionDoc.id;
    const auctionData = auctionDoc.data();
    
    // Idempotent check: skip if already ENDED
    if (auctionData.state === 'ENDED' || auctionData.state === 'ENDED_NO_RESPONSE') {
      console.log(`Skipping auction ${auctionId}: already ended`);
      continue;
    }

    const winnerId = auctionData.currentWinnerId;
    const currentPrice = auctionData.currentPrice || 0;
    const sellerId = auctionData.sellerId || '';
    const endsAt = auctionData.endsAt;

    try {
      // Get admin settings for deposit calculation
      const settingsDoc = await db.collection('adminSettings').doc('main').get();
      if (!settingsDoc.exists) {
        console.error('Admin settings not found');
        continue;
      }
      
      const settings = settingsDoc.data();
      const depositRules = settings.depositRules || {};
      const tiers = depositRules.tiers || [];
      const winnerDeadlineHours = settings.winnerDeadlineHours || 48;
      
      // Compute required deposit from tiers
      let requiredDeposit = 0;
      for (const tier of tiers) {
        const minValue = tier.min || 0;
        const maxValue = tier.max;
        const rate = tier.rate || 0;
        
        if (maxValue != null) {
          if (currentPrice >= minValue && currentPrice <= maxValue) {
            requiredDeposit = currentPrice * rate;
            break;
          }
        } else {
          // No max means highest tier
          if (currentPrice >= minValue) {
            requiredDeposit = currentPrice * rate;
            break;
          }
        }
      }

      // Calculate winnerDeadlineAt = endsAt + winnerDeadlineHours
      let deadlineAt;
      if (endsAt) {
        // Convert Firestore Timestamp to JavaScript Date
        const endsAtDate = endsAt.toDate ? endsAt.toDate() : new Date(endsAt._seconds * 1000);
        deadlineAt = new Date(endsAtDate.getTime() + winnerDeadlineHours * 3600000);
      } else {
        deadlineAt = new Date(Date.now() + winnerDeadlineHours * 3600000);
      }

      if (!winnerId || winnerId === '') {
        // No winner - just end the auction
        await auctionDoc.ref.update({
          state: 'ENDED',
          endedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Closed auction ${auctionId} with no winner`);
        continue;
      }

      // Check VIP waiver
      const userDoc = await db.collection('users').doc(winnerId).get();
      const userData = userDoc.data() || {};
      const vipWaived = userData.vipDepositWaived || false;

      // Hold deposit in transaction
      await db.runTransaction(async (tx) => {
        const walletRef = db.collection('wallets').doc(winnerId);
        const walletDoc = await tx.get(walletRef);
        
        if (!walletDoc.exists) {
          // Create wallet if it doesn't exist
          tx.set(walletRef, {
            availableDeposit: 0,
            reservedDeposit: 0,
            lockedDeposit: 0,
            depositStatus: 'none',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        
        const walletData = walletDoc.exists ? walletDoc.data() : {};
        const availableDeposit = walletData.availableDeposit || 0;
        const reservedDeposit = walletData.reservedDeposit || 0;
        
        // Check if deposit can be held (VIP waived or sufficient funds)
        if (vipWaived || availableDeposit >= requiredDeposit) {
          if (!vipWaived) {
            // Move from availableDeposit to reservedDeposit
            tx.update(walletRef, {
              availableDeposit: admin.firestore.FieldValue.increment(-requiredDeposit),
              reservedDeposit: admin.firestore.FieldValue.increment(requiredDeposit),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          
          // Update auction with deposit held
          tx.update(auctionDoc.ref, {
            state: 'ENDED',
            endedAt: admin.firestore.FieldValue.serverTimestamp(),
            depositRequired: requiredDeposit,
            depositHeld: vipWaived ? 0 : requiredDeposit,
            depositStatus: vipWaived ? 'waived' : 'held',
            winnerDeadlineAt: admin.firestore.Timestamp.fromDate(deadlineAt),
            winnerDeadlineHours: winnerDeadlineHours,
          });
        } else {
          // Insufficient deposit
          tx.update(auctionDoc.ref, {
            state: 'ENDED',
            endedAt: admin.firestore.FieldValue.serverTimestamp(),
            depositRequired: requiredDeposit,
            depositHeld: 0,
            depositStatus: 'insufficient',
            winnerDeadlineAt: admin.firestore.Timestamp.fromDate(deadlineAt),
            winnerDeadlineHours: winnerDeadlineHours,
          });
        }
      });

      // Create contract (outside transaction)
      if (sellerId && winnerId) {
        try {
          const contractRef = db.collection('contracts').doc(auctionId);
          const contractDoc = await contractRef.get();
          
          if (!contractDoc.exists) {
            await contractRef.set({
              sellerId: sellerId,
              buyerId: winnerId,
              auctionId: auctionId,
              termsAcceptedSeller: false,
              termsAcceptedBuyer: false,
              contractVersion: '1.0',
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        } catch (contractError) {
          console.error(`Error creating contract for auction ${auctionId}:`, contractError);
        }
      }

      console.log(`Closed auction ${auctionId}, winner: ${winnerId}, deposit: ${requiredDeposit}`);
    } catch (error) {
      console.error(`Error closing auction ${auctionId}:`, error);
    }
  }

  return null;
});

// Watermark auction images (Gen2 Storage trigger)
exports.watermarkAuctionImage = onObjectFinalized(async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    const bucketName = event.data.bucket;

    // Only process images in auctions/{auctionId}/original/ path
    if (!filePath || !filePath.startsWith('auctions/') || !filePath.includes('/original/')) {
      console.log('Skipping non-auction image:', filePath);
      return null;
    }

    // Validate content type
    if (!contentType || !contentType.startsWith('image/')) {
      console.log('Invalid content type, deleting:', filePath);
      await storage.bucket(bucketName).file(filePath).delete();
      return null;
    }

    // Validate file size (5MB max)
    const file = storage.bucket(bucketName).file(filePath);
    const [fileMetadata] = await file.getMetadata();
    const size = parseInt(fileMetadata.size || '0');
    
    if (size > 5 * 1024 * 1024) {
      console.log('File too large, deleting:', filePath);
      await file.delete();
      return null;
    }

    // Parse auctionId and imageId from path
    // Path format: auctions/{auctionId}/original/{imageId}.jpg
    const pathParts = filePath.split('/');
    if (pathParts.length !== 4 || pathParts[0] !== 'auctions' || pathParts[2] !== 'original') {
      console.log('Invalid path format:', filePath);
      return null;
    }

    const auctionId = pathParts[1];
    const imageId = pathParts[3].replace(/\.(jpg|jpeg|png|webp)$/i, '');

    console.log('Processing watermark for:', {auctionId, imageId, filePath});

    try {
      // Download original image
      const [originalBuffer] = await file.download();

      // Process with sharp: resize, strip EXIF, add watermark
      const maxWidth = 1600;
      let processedImage = sharp(originalBuffer)
        .resize(maxWidth, null, {
          withoutEnlargement: true,
          fit: 'inside',
        })
        .jpeg({quality: 85, mozjpeg: true})
        .removeAlpha();

      // Get image dimensions for watermark placement
      const imageMetadata = await processedImage.metadata();
      const width = imageMetadata.width || 1600;
      const height = imageMetadata.height || 1200;

      // Create watermark text SVG
      const watermarkText = 'M Auction';
      const fontSize = Math.max(24, Math.min(width, height) * 0.03); // 3% of smaller dimension
      const watermarkSvg = `
        <svg width="${width}" height="${height}">
          <text
            x="${width - 20}"
            y="${height - 20}"
            font-family="Arial, sans-serif"
            font-size="${fontSize}"
            font-weight="bold"
            fill="white"
            opacity="0.15"
            text-anchor="end"
            dominant-baseline="bottom"
          >${watermarkText}</text>
        </svg>
      `;

      // Composite watermark
      const watermarkBuffer = Buffer.from(watermarkSvg);
      processedImage = processedImage.composite([
        {
          input: watermarkBuffer,
          blend: 'over',
        },
      ]);

      // Get processed image buffer
      const watermarkedBuffer = await processedImage.toBuffer();

      // Upload watermarked image
      const wmPath = `auctions/${auctionId}/wm/${imageId}.jpg`;
      const wmFile = storage.bucket(bucketName).file(wmPath);
      
      await wmFile.save(watermarkedBuffer, {
        metadata: {
          contentType: 'image/jpeg',
        },
      });

      // Make public or get signed URL
      await wmFile.makePublic();
      const wmUrl = `https://storage.googleapis.com/${bucketName}/${wmPath}`;

      // Update Firestore with watermark path and URL
      const auctionRef = db.collection('auctions').doc(auctionId);
      const auctionDoc = await auctionRef.get();

      if (!auctionDoc.exists) {
        console.log('Auction not found:', auctionId);
        return null;
      }

      const auctionData = auctionDoc.data();
      const images = Array.isArray(auctionData.images) ? [...auctionData.images] : [];

      // Find and update image metadata
      const imageIndex = images.findIndex((img) => img.id === imageId);
      if (imageIndex >= 0) {
        images[imageIndex] = {
          ...images[imageIndex],
          wmPath: wmPath,
          url: wmUrl,
        };

        await auctionRef.update({
          images: images,
        });

        console.log('Watermark complete:', {auctionId, imageId, wmUrl});
      } else {
        console.log('Image metadata not found in Firestore:', imageId);
      }

      return null;
    } catch (error) {
      console.error('Error watermarking image:', error);
      // Don't throw - allow retry
      return null;
    }
  });
