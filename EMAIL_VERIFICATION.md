# Email verification – flow and deliverability

## Required setup: custom action URL (fix “expired or already used” on first click)

With **custom-domain emails** (e.g. @parfa.net), many mail systems **prefetch** or scan links. Firebase’s **default** verification page applies the one-time code as soon as the page loads, so that prefetch **consumes** the link before the user clicks. They then see “expired or already used” when they open the email.

**Fix:** Use our **custom action handler**, which applies the code only when the user clicks “Confirm my email”, so prefetch does not consume it.

### Steps (do this once)

1. **Deploy the custom handler**
   ```bash
   firebase deploy --only hosting
   ```
   This serves `hosting/email-action.html` at  
   `https://luxuryauction-e9c56.web.app/email-action.html`

2. **Set the custom action URL in Firebase**
   - Open [Firebase Console](https://console.firebase.google.com/) → your project → **Authentication** → **Templates**.
   - Open the **“Email address verification”** (or “Verify and change email”) template.
   - Set **Action URL** to:
     ```
     https://luxuryauction-e9c56.web.app/email-action.html
     ```
   - Save.

3. **Request a new link**
   - In the app, use **“Link expired or already used? Send new link”** so the new email uses the custom URL.
   - Open the **new** email and click the link once. You should see our page with **“Confirm my email”**; click it to verify.

4. **If Safari shows “Connection Not Private” on .web.app**
   - Try opening the link in **Chrome** or on another device.
   - Confirm you ran `firebase deploy --only hosting`; Firebase Hosting uses a valid Google certificate for `.web.app`.

Until the custom action URL is set and hosting is deployed, new links will still go to Firebase’s default page and can be consumed by prefetch.

---

## In-app flow (summary)

1. **Send verification link** – User enters email; we call Firebase `User.verifyBeforeUpdateEmail(email)`. Firebase sends an email with a one-time link.
2. **Link behaviour** – The link is **single-use** and **time-limited** (Firebase default is on the order of days for email verification). After the user clicks it, Firebase updates the account and the link is consumed.
3. **“Expired or already used”** – Shown by Firebase’s web page when:
   - The link was already clicked once, or
   - The link has expired.
   - **In-app fix:** User can tap **“Link expired or already used? Send new link”** to get a fresh email. Each new send invalidates the previous link.
4. **After clicking the link** – User returns to the app and taps **“I’ve verified my email – Continue”**. We call `user.reload()` and, if `emailVerified == true`, we mark email verified in Firestore and continue the flow (listing or bidding).
5. **Resend** – Resend uses the same `verifyBeforeUpdateEmail` call. The previous link stops working; the user must use the **latest** email.

## Improving deliverability (avoid Spam/Junk)

Firebase sends verification emails through Google. To reduce the chance they land in Spam/Junk:

### 1. Firebase Console – email templates

- In [Firebase Console](https://console.firebase.google.com/) → **Authentication** → **Templates**:
  - Edit the **“Email address verification”** (or similar) template.
  - Use a clear, professional **sender name** (e.g. “M Auction” or your app name).
  - Keep the **subject** and body clear and non-spammy (no excessive caps, spammy words, or misleading content).
- Customise the **action URL** if you use a custom domain (see below).

### 2. Sender reputation and DNS (SPF/DKIM/DMARC)

- Firebase Auth sends from Google’s infrastructure (e.g. `noreply@<project>.firebaseapp.com`). You **cannot** change the sending server or add your own SPF/DKIM for that default sender.
- To use **your own domain** and control SPF/DKIM/DMARC:
  - Use a **custom email action handler**: your own HTTPS endpoint that receives the action link and then redirects to Firebase or your app. This is more involved and may require Cloud Functions or a separate service.
  - Alternatively, use an **extension or backend** (e.g. SendGrid, Mailgun) with your domain and send a custom verification email; then you’d need to verify the token via your backend and Firebase Admin SDK. This is a larger change and not required for the current in-app flow.

### 3. User-facing guidance (already in app)

- The app tells users to **check Spam/Junk** and explains that if they see **“expired or already used”** they should use **“Send new link”** in the app.
- Resend is always available after the first send so users are never stuck.

### 4. Optional: custom continue URL

- If you host a web app, you can pass **ActionCodeSettings** with a `continueUrl` when calling `verifyBeforeUpdateEmail`. After the user clicks the link and Firebase verifies, they can be redirected to your page (e.g. “Email verified – return to the app”).
- The domain of `continueUrl` must be **whitelisted** in Firebase Console → Authentication → **Authorized domains**.
- This does **not** change the “expired or already used” page (that is shown by Firebase when the link is invalid). It only customises where the user lands after a **successful** verification.

## Testing the full flow

1. **New email** – Use an address that has not been verified before (or use a new one).
2. **Send verification link** – Tap “Send verification link”; confirm the email arrives (inbox or Spam).
3. **First click** – Open the link once; confirm Firebase shows success (or your custom success page if configured).
4. **Continue in app** – In the app, tap “I’ve verified my email – Continue”; confirm the flow continues (e.g. to terms or listing).
5. **Expired / already used** – Either wait until the link expires or click the same link again; confirm Firebase shows “expired or already used”.
6. **Resend** – In the app, tap “Link expired or already used? Send new link”; confirm a new email arrives and that the **new** link works and the old link no longer works.
7. **Rate limit** – Sending many links in a short time can trigger `too-many-requests`; the app shows a short message and the user can retry after a few minutes.

## Summary

- **Link validity:** Single-use, time-limited; user can request a **new link** anytime via “Send new link”.
- **Web → app:** User opens link in browser (Firebase page); then returns to the app and taps “I’ve verified – Continue” so we reload and continue.
- **Deliverability:** Improve via Firebase Console templates and clear copy; for full control over domain/SPF/DKIM, a custom sender or custom action handler is required (not implemented in the current flow).
