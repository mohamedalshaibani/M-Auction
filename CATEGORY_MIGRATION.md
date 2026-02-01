# Category Migration: Firestore + App

## 1. Firestore Data Model

### adminSettings/main

Update the document `adminSettings/main` to include the new category structure. Use the payload in **firestore_admin_settings_categories.json** and merge it into the existing document (do not remove existing fields such as `whitelist`, `durationOptions`, commission settings, etc.).

**Fields to add/update:**

| Field          | Type   | Description |
|----------------|--------|-------------|
| `categories`   | array  | Top-level category groups: `id`, `nameAr`, `nameEn`, `order`. |
| `subcategories`| array  | Subcategories: `id`, `parentId`, `nameAr`, `nameEn`, `order`. |

**Example (excerpt):**

```json
{
  "categories": [
    { "id": "watches", "nameAr": "ساعات", "nameEn": "Watches", "order": 1 },
    { "id": "bags", "nameAr": "شنط", "nameEn": "Bags", "order": 2 },
    { "id": "fashion", "nameAr": "فاشن", "nameEn": "Fashion", "order": 3 },
    { "id": "jewelry", "nameAr": "مجوهرات", "nameEn": "Jewelry", "order": 4 },
    { "id": "accessories", "nameAr": "اكسسوارات", "nameEn": "Accessories", "order": 5 },
    { "id": "collectibles", "nameAr": "مقتنيات", "nameEn": "Collectibles", "order": 6 }
  ],
  "subcategories": [
    { "id": "watches", "parentId": "watches", "nameAr": "ساعات", "nameEn": "Watches", "order": 1 },
    { "id": "bags", "parentId": "bags", "nameAr": "شنط", "nameEn": "Bags", "order": 1 },
    { "id": "clothing", "parentId": "fashion", "nameAr": "ملابس", "nameEn": "Clothing", "order": 1 },
    { "id": "shoes", "parentId": "fashion", "nameAr": "أحذية", "nameEn": "Shoes", "order": 2 },
    { "id": "caps", "parentId": "fashion", "nameAr": "قبعات", "nameEn": "Caps", "order": 3 },
    { "id": "jewelry", "parentId": "jewelry", "nameAr": "مجوهرات", "nameEn": "Jewelry", "order": 1 },
    { "id": "wallets", "parentId": "accessories", "nameAr": "محافظ", "nameEn": "Wallets", "order": 1 },
    { "id": "eyewear", "parentId": "accessories", "nameAr": "نظارات", "nameEn": "Eyewear", "order": 2 },
    { "id": "pens", "parentId": "accessories", "nameAr": "أقلام", "nameEn": "Pens", "order": 3 },
    { "id": "travel_bags", "parentId": "collectibles", "nameAr": "حقائب سفر", "nameEn": "Travel Bags", "order": 1 },
    { "id": "collectibles", "parentId": "collectibles", "nameAr": "مقتنيات", "nameEn": "Collectibles", "order": 2 }
  ]
}
```

Full payload: **firestore_admin_settings_categories.json**.

---

## 2. Migration of Existing Auctions

The **auctions** collection may have documents with only a legacy `category` string. Add the new fields and retire "art".

### New fields on each auction document

| Field          | Type   | Description |
|----------------|--------|-------------|
| `categoryGroup`| string | One of: `watches`, `bags`, `fashion`, `jewelry`, `accessories`, `collectibles`. |
| `subcategory`  | string | One of the subcategory ids (e.g. `watches`, `bags`, `clothing`, `shoes`, `caps`, `jewelry`, `wallets`, `eyewear`, `pens`, `travel_bags`, `collectibles`). |

**Rules:**

- If `category` is `"art"` (case-insensitive): set `categoryGroup: "collectibles"`, `subcategory: "collectibles"`. Optionally set `category: "collectibles"` for legacy readers.
- Otherwise: set `categoryGroup` and `subcategory` from the legacy `category` using the same mapping as `legacyCategoryToGroup` / `effectiveSubcategory` in the app (see `lib/models/category_model.dart`). Keep the existing `category` value for backward compatibility if desired.

### Mapping (legacy → categoryGroup / subcategory)

- `art` → `categoryGroup: "collectibles"`, `subcategory: "collectibles"`
- `watches` → `categoryGroup: "watches"`, `subcategory: "watches"`
- `bags` → `categoryGroup: "bags"`, `subcategory: "bags"`
- `jewelry` / `jewellery` → `categoryGroup: "jewelry"`, `subcategory: "jewelry"`
- `fashion`, `clothing`, `shoes`, `caps` → `categoryGroup: "fashion"`, `subcategory`: same as legacy (e.g. `clothing`, `shoes`, `caps`)
- `accessories`, `wallets`, `eyewear`, `pens` → `categoryGroup: "accessories"`, `subcategory`: same as legacy
- `collectibles`, `travel_bags` → `categoryGroup: "collectibles"`, `subcategory`: same as legacy
- Unknown / empty → `categoryGroup: "collectibles"`, `subcategory: "collectibles"`

### How to run the migration

**Option A – Firebase Console:** Manually edit each affected auction and add `categoryGroup` and `subcategory` (and update `category` for `art` → `collectibles`).

**Option B – Script (Node.js with Firebase Admin):** Run a one-off script that:

1. Reads all documents from `auctions`.
2. For each doc:
   - If it already has `categoryGroup` and `subcategory`, skip or leave as-is.
   - Else derive `categoryGroup` and `subcategory` from `category` using the mapping above; if `category === "art"`, set `category` to `"collectibles"` as well.
3. Writes the updated fields back (e.g. `update` with only the new/updated fields).

No new Firestore indexes are required if you keep using broad queries (e.g. by `status`) and filter by `categoryGroup` / `subcategory` in memory in the app.

---

## 3. App Behavior (Summary)

- **Home / Explore:** 6 top-level category tiles in order (watches, bags, fashion, jewelry, accessories, collectibles). Tapping a tile opens a filtered list; subcategory chips are optional.
- **Listings / search:** Use `categoryGroup` and `subcategory` for filtering; fall back to legacy `category` via `effectiveCategoryGroup()` and `effectiveSubcategory()` for old documents.
- **Create / Edit auction:** Select category group first, then subcategory; save both `categoryGroup` and `subcategory` (and legacy `category` = subcategory).
- **Auction detail:** Shows category as `categoryGroup display name / subcategory display name` with null-safe fallbacks for documents that only have `category`.

---

## 4. Simulator Verification Checklist

- [ ] **Categories order:** Home and Explore show the 6 category tiles in this order: Watches, Bags, Fashion, Jewelry, Accessories, Collectibles.
- [ ] **Category tile tap:** Tapping a category opens the filtered list for that category group; Active/Ended is respected where applicable.
- [ ] **Subcategory filter:** In the category listing view, subcategory chips appear; selecting one filters by that subcategory.
- [ ] **Old auctions still show:** Auctions that have only the legacy `category` field (no `categoryGroup`/`subcategory`) still appear in lists and detail; category displays using the fallback mapping.
- [ ] **Create/Edit flow:** Creating or editing a draft allows selecting category group then subcategory; saved draft has `categoryGroup`, `subcategory`, and legacy `category` set.
- [ ] **Auction detail:** Detail page shows "Category: &lt;Group&gt; / &lt;Subcategory&gt;" (e.g. "Watches / Watches") for both migrated and legacy documents.
- [ ] **No "art" in UI:** "Art" does not appear as a category option anywhere; any migrated "art" auction appears under Collectibles.
