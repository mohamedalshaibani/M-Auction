# Email action handler (hosting)

This folder is deployed to Firebase Hosting and provides a **custom email verification page** used when users click the link in the verification email.

## Why it’s needed

Firebase’s default verification page applies the one-time code as soon as the page loads. Some email providers (especially with custom domains) prefetch or scan links, which **consumes** the code before the user clicks. They then see “expired or already used.”

This handler **does not** apply the code on load. It shows a “Confirm my email” button and only applies the code when the user clicks it, so prefetch cannot consume the link.

## Setup (one-time)

1. **Deploy**
   ```bash
   firebase deploy --only hosting
   ```

2. **Set custom action URL in Firebase**
   - Console → **Authentication** → **Templates** → edit the email verification template.
   - Set **Action URL** to:
     `https://luxuryauction-e9c56.web.app/email-action.html`
   - Save.

3. After that, when users tap “Send new link” in the app, the new email will use this handler. Old emails still contain the previous (default) link.

See project root **EMAIL_VERIFICATION.md** for the full flow and deliverability notes.
