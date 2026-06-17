# Home Bidder API
You are tasked with creating a RESTful API for an online property marketplace.
Users can list their properties for sale, and make offers on properties.


## Data Model
We will have 3 data objects. User, Listing and Offer
```typescript

interface User {
  user_id: string;   // UUID, server-generated
  name: string;      // required, non-empty
  email: string;     // required, non-empty, unique across users
  budget: number;    // required, positive; cap on the buyer's total outstanding (PENDING) offers
}

interface Listing {
  listing_id: string;   // UUID, server-generated
  address: string;      // required, non-empty
  price: number;        // required, positive number
  seller_id: string;    // user_id of the owner; must reference an existing user
  status: 'DRAFT' | 'AVAILABLE' | 'CHAINED' | 'PENDING' | 'SOLD' | 'ARCHIVED';  // server-managed lifecycle
  created_at: string;   // ISO 8601 datetime, server-generated
}

interface Offer {
  offer_id: string;     // UUID, server-generated
  listing_id: string;   // the listing this offer is on
  buyer_id: string;     // the buyer in this negotiation; must reference an existing user
  made_by: 'BUYER' | 'SELLER';   // who created this offer / who the OTHER party must respond to
  offer_value: number;  // required, positive number
  expiration: string;   // ISO 8601 datetime; compared against the virtual clock
  status: 'PENDING' | 'ACCEPTED' | 'REJECTED' | 'EXPIRED';  // server-managed
  created_at: string;   // ISO 8601 datetime, server-generated
  contingent_on: string | null;   // optional listing_id this offer's acceptance depends on (must be SOLD); null if none
}
```


## Budget invariant
Every user has a base `budget`. At any time, the **sum of a buyer's outstanding (PENDING) offers across all listings must not exceed that buyer's *effective* budget** (see Self-financing below; with no sales, effective budget equals the base `budget`). Only `made_by: BUYER` offers with status `PENDING` count toward the total; offers that are REJECTED, EXPIRED, or ACCEPTED do not (their amount is released). This is enforced whenever a buyer commits money — creating a **non-contingent** offer (`POST /offers`) or countering a seller's offer (`POST /offers/:id/counter`). If the new amount would push the buyer's PENDING total over their effective budget, respond **409**. A total exactly equal to the effective budget is allowed.

**Example** (buyer effective budget = 100000):
- offer 60000 on listing A → 201 (committed 60000)
- offer 60000 on listing B → 409 (would be 120000 > 100000)
- reject/expire the listing-A offer → frees 60000
- offer 60000 on listing B → 201 (committed 60000)


## Self-financing (effective budget)
A user can both sell and buy. Selling raises their buying power: when a listing they own
becomes **SOLD**, the **value of the accepted offer** on it is added to that user's spending
power. Formally:

> **effective budget** = base `budget` + **proceeds** − committed
>
> where **proceeds** = the sum, over every listing this user owns that is `SOLD`, of the
> `offer_value` of the offer that was ACCEPTED on it; and **committed** = the sum of this
> user's own outstanding (PENDING) `made_by: BUYER` offers.

Proceeds are only realized once a listing is actually `SOLD`; a merely AVAILABLE or PENDING
listing contributes nothing. This models "I can only afford the next home after my current
one sells."

**Interaction with contingent offers (self-financing chains):**
- A **contingent** offer (one with `contingent_on` set) is **not** budget-checked at creation
  — it may be created even if its value exceeds the buyer's current effective budget, because
  the buyer intends to fund it by selling the listing it depends on.
- A **non-contingent** offer **is** budget-checked at creation, against the buyer's effective
  budget at that moment (so already-realized proceeds increase what the buyer may offer).
- At **settlement**, any committed (`made_by: BUYER`) offer is re-checked: the buyer's total
  commitments must not exceed their effective budget at that moment. Because the depended-on
  listing is `SOLD` by then, its proceeds count toward the buyer's effective budget. If the
  realized proceeds are insufficient, the offer is **REJECTED** and its listing reverts to
  `AVAILABLE` (see Property chains & auto-settlement).

**Example** (buyer B base budget = 100000, B owns listing Y):
- B makes an offer of 500000 on listing X **contingent on Y** → 201 (not checked at creation)
- accepting B's offer on X before Y is SOLD → **200**: it is committed, listing X becomes `CHAINED`
- Y sells for 450000 → B's proceeds become 450000, effective budget 550000 → the sweep settles the
  committed offer automatically (500000 ≤ 550000): X → `SOLD`. Had Y sold for only 350000 the offer
  would instead be `REJECTED` and X would revert to `AVAILABLE`.


## Contingent offers (dependency graph)
An offer may be **contingent on the sale of another listing** (e.g. the buyer must sell their current home first). Set the optional `contingent_on` field to a `listing_id` when creating an offer via `POST /offers`. Counters never carry a contingency (a countered offer's replacement has `contingent_on: null`).

Treat contingencies as a directed graph over listings: a **PENDING** offer on listing `X` with `contingent_on = Y` is an edge `X → Y` ("X's sale depends on Y selling first"). Rules:

- **R1 (validation):** if `contingent_on` is present it must reference an existing listing (else **400**); it may not equal the offer's own `listing_id` (else **409**).
- **R2 (no cycles):** creating the offer must not form a cycle in the graph — considering existing PENDING edges plus the new one — whether **direct or transitive** (e.g. X→Y, Y→Z already exist, then a new Z→X). A cycle → **409**. Only PENDING offers form edges (REJECTED/EXPIRED/ACCEPTED do not).
- **R3 (accept commits "subject to sale"):** accepting an offer with `contingent_on = D` **succeeds (200)** even if `D` is not yet SOLD. It does not settle immediately; instead it is **committed** (see Property chains & auto-settlement): the listing becomes `CHAINED` and the offer stays publicly `PENDING` until its dependency sells. If `D` is already SOLD at accept time, settlement happens right away.
- **R4 (cascade):** when a listing `D` is ARCHIVED, every PENDING offer with `contingent_on = D` becomes **REJECTED** (its contingency can never be satisfied); if such an offer was a committed (`CHAINED`) offer, its listing reverts to `AVAILABLE`.

**Accept-check precedence** (exact order for `POST /offers/:id/accept`, so the result is deterministic):
1. offer exists — else 404
2. offer is PENDING — else 409
3. `actor_id` present — else 400
4. `actor_id` is the awaited party — else 409
5. listing-lock rule (a BUYER offer requires its listing to be AVAILABLE) — else 409
6. if the offer is **contingent**, it is **committed** (listing → `CHAINED`, other PENDING offers cascade-rejected) and then settlement runs; the response is **200**. If the offer is **non-contingent**, it settles immediately, subject to the budget check below.
7. **budget affordability for a non-contingent offer** (a `made_by: BUYER` offer's buyer fits their effective budget; see Self-financing) — else 409. (A contingent offer is *not* budget-checked here; its affordability is resolved during settlement — see below.)


## Property chains & auto-settlement
Accepting a contingent offer is the seller saying *"yes, subject to your sale."* It commits the
deal without completing it. A **committed** offer is one whose listing is `CHAINED`; the offer's
public `status` stays `PENDING`. While a listing is `CHAINED` it behaves like a locked listing:
no new offers may be created on it and no other action may be taken against it.

After **every** state-changing request (and on `POST /clock`), the server runs a deterministic
**settlement sweep** that completes committed deals whose dependencies have sold, in a fixed order,
until no more can be settled (a fixpoint). The sweep obeys these rules:

- **Trigger:** a committed offer on listing `X` with `contingent_on = D` **settles** once `D` is
  `SOLD` and the buyer can **afford** it: the offer → `ACCEPTED`, listing `X` → `SOLD`, and the
  sale value is realized as proceeds for `X`'s seller (which may fund further settlements). One
  trigger can therefore complete an arbitrarily deep chain (e.g. `Z → Y → X`) hop by hop.
- **Order:** when more than one committed offer is settleable, exactly one is settled per step —
  the **earliest by `created_at`, then by `offer_id`** (ascending). Then the sweep re-evaluates.
- **Affordability & contention:** a buyer's spending power as deals settle is
  `base budget + proceeds − money already spent on completed purchases − other PENDING
  (non-committed) commitments`. Other committed offers by the same buyer do **not** count, so each
  is judged individually; but each settlement **spends** budget, so when two committed offers by
  one buyer are individually affordable yet **jointly** exceed the budget, the earlier one settles
  and the later one then **cannot** be afforded.
- **Insufficient funds at settlement:** a committed offer whose dependency is `SOLD` but which the
  buyer cannot afford is **REJECTED**, and its listing reverts `CHAINED → AVAILABLE`.
- **Expiry mid-chain:** expiry is applied before every step. A committed offer whose `expiration`
  passes becomes `EXPIRED` and its listing reverts `CHAINED → AVAILABLE`, which can change which
  downstream offers ever settle.
- **Dependency can never sell:** if a committed offer's dependency is `ARCHIVED`, the offer is
  `REJECTED` and its listing reverts `CHAINED → AVAILABLE` (the sweep then continues).

**Worked example — 3-deep chain.** Offers committed so that `X`'s sale depends on `Y`, and `Y`'s on
`Z` (listings `X` and `Y` are `CHAINED`). When a buyer's plain offer on `Z` is accepted, `Z` sells;
the sweep then settles `Y` (now its dependency `Z` is SOLD), which sells `Y`; then settles `X`. End
state: `X`, `Y`, `Z` all `SOLD`, all three offers `ACCEPTED`.

**Worked example — same-buyer contention.** Buyer `B` (effective budget 600000) has two committed
offers of 400000 each, both depending on listing `D`. When `D` sells, both become settleable. The
earlier-created offer settles (400000 ≤ 600000); `B` has now spent 400000, leaving 200000, so the
later offer (400000) can no longer be afforded → it is `REJECTED` and its listing reverts to
`AVAILABLE`.

**Worked example — mid-chain expiry.** `X` is committed depending on `Y`, and `Y` is committed
depending on `Z` (both `CHAINED`). If `Y`'s committed offer expires before `Z` sells, that offer
becomes `EXPIRED` and `Y` reverts to `AVAILABLE`; `X` stays `CHAINED` and can no longer settle
through `Y`.


## API Endpoints

> All success responses return the **full object** as defined in the Data Model
> (every field). The JSON blocks below are illustrative; server-generated values
> (`*_id`, `created_at`) are examples only and are never matched exactly.

### POST /users
Creates a new user.

**Request Body:**
```json
{ "name": "Kobe Bryant", "email": "Kobe@example.com", "budget": 1000000 }
```
- `name`: required, non-empty string
- `email`: required, non-empty string, unique across all users
- `budget`: required, positive number (the buyer's spending cap; see Budget invariant)

**Response (201 Created):**
the created user
```json
{
"user_id": "ahh121212.",
"name": "Kobe Bryant",
"email": "Kobe@example.com",
"budget": 1000000
}
```
- server generates `user_id` (UUID)

**Errors:**
- 400 if `name`, `email`, or `budget` is missing/empty/invalid (budget must be a positive number)
- 409 if a user with that `email` already exists


### POST /listings
Creates a new listing

**Request Body:**
```json
{ "seller_id": "ahh121212", "address": "123 Main St", "price": 450000 }
```
- `seller_id`: required, must reference an existing user
- `address`: required, non-empty string
- `price`: required, positive number (> 0)

**Response (201 Created):**
the created Listing

```json
{
"status": "DRAFT",
"listing_id": "ususus11221",
"seller_id" : "ahh121212",
"address" : "123 Main St",
"price": 450000,
  "created_at": "2024-01-15T10:30:00.000Z"

}
```


- server generates `listing_id` (UUID)
- seller id must be an existing user_id

**Errors:**
- 400 if any field is missing/invalid, or `seller_id` is not an existing user



### POST /listings/:id/publish

This end point publishes a Listing i.e changes the status from "DRAFT" to "AVAILABLE".

**Response (200 OK):**
the updated Listing (status `AVAILABLE`)

**Errors:**
- 404 if no listing exists with that id
- 409 if the listing is not in DRAFT status


### POST /listings/:id/archive
This end point archives  a listing. i.e chagnes status to "ARCHIVED".
When archived, all PENDING offers on the listing become REJECTED, and every PENDING offer **contingent on** this listing is also REJECTED (its contingency can never be satisfied).

**Response (200 OK):**
the updated Listing (status `ARCHIVED`)

**Errors:**
- 404 if no listing exists with that id
- 409 if the listing is not in DRAFT or AVAILABLE status


### GET /listings/:id
Gets the listing details given the listing id.

**Response (200 OK):**
the listing details, like address, price, seller_id, status, created_at etc

**Errors:**
- 404 : if listing does not exist


### POST /offers
Creates a new offer on a listing,


**Request Body:**

```json
{
  "buyer_id": "1asads",
  "listing_id": "ususus11221",
  "offer_value": 420000,
  "expiration": "2024-02-15T10:30:00.000Z",
  "contingent_on": null
}
```
- `contingent_on`: optional `listing_id` this offer depends on (see Contingent offers); omit or `null` for none


**Response (201 Created):**
the created Offer (full object)
```json
{
  "offer_id": "1kl12k",
  "listing_id": "ususus11221",
  "buyer_id": "1asads",
  "made_by": "BUYER",
  "offer_value": 420000,
  "expiration": "2024-02-15T10:30:00.000Z",
  "status": "PENDING",
  "created_at": "2024-01-15T10:30:00.000Z",
  "contingent_on": null
}
```


**Errors:**
- 400 if any field is missing, buyer_id, listing_id, offer_value, expiration
- 400 if offer expiration is in invalid (in the past)
- 400 if offer value is a negative number
- 404 if listing does not exist
- 409 if buyer id === seller
- 409 if listing is not in AVAILABLE status
- 409 if the buyer already has a **PENDING** offer on the listing (REJECTED or EXPIRED offers do not count, so a buyer may offer again after their previous offer ended)
- 409 if a **non-contingent** offer would exceed the buyer's effective budget (sum of the buyer's PENDING offers across all listings + this offer > effective budget; see Budget invariant and Self-financing). A **contingent** offer is *not* budget-checked at creation.
- 400 if `contingent_on` is present but does not reference an existing listing (see Contingent offers)
- 409 if `contingent_on` equals this offer's own listing, or would create a dependency cycle (see Contingent offers)


### POST /offers/:id/accept
The user accepts an offer on a listing.
User can be buyer or seller

**Request Body:**
- `actor_id`: required — must be the awaited party
  (BUYER offer → the listing's seller; SELLER counter → the offer's buyer)

**On success (200 OK):** returns the full Offer.

For a **non-contingent** offer (immediate sale):
- offer → ACCEPTED
- listing → SOLD
- all OTHER PENDING offers on that listing → REJECTED (cascade; not shown in the response)

For a **contingent** offer (commit "subject to sale"; see Property chains & auto-settlement):
- the offer is **committed**: its public `status` stays `PENDING`
- listing → `CHAINED`
- all OTHER PENDING offers on that listing → REJECTED (cascade)
- the settlement sweep then runs, which may immediately settle this offer (→ ACCEPTED, listing →
  SOLD) if its dependency is already SOLD and the buyer can afford it, or **REJECT** it (listing
  reverts to AVAILABLE) if the dependency is SOLD but the buyer cannot afford it.

The returned Offer reflects its state after the sweep.

```json
{
  "offer_id": "1kl12k",
  "listing_id": "ususus11221",
  "buyer_id": "1asads",
  "made_by": "BUYER",
  "offer_value": 420000,
  "expiration": "2024-02-15T10:30:00.000Z",
  "status": "ACCEPTED",
  "created_at": "2024-01-15T10:30:00.000Z"
}
```

**Errors:**
- 400 if actor_id or offer_id is missing
- 404 if offer or list does not exist
- 409 if offer is made_by BUYER and listing is not in AVAILABLE status
- 409 if offer is made_by SELLER and listing is not in PENDING status
- 409 if offer expiration is in the past
- 409 if offer is not PENDING status
- 409 if offer is made_by BUYER and actor_id is not the seller
- 409 if offer is made_by SELLER and actor_id is not the buyer (buyer_id can be inferred from offer_id)
- a **contingent** offer is no longer rejected when its dependency is not yet SOLD; it is committed instead (listing → `CHAINED`) — see Property chains & auto-settlement
- 409 if the offer is **non-contingent**, `made_by: BUYER`, and the buyer's total PENDING commitments would exceed their effective budget (see Self-financing). A contingent offer is not budget-checked here; its affordability is resolved during settlement.


### POST /offers/:id/reject
- the awaiting party (buyer or seller) rejects a PENDING offer on a listing.

**Request Body:**
```json
{
"actor_id": "0kasdsa",
}
```


**On success (200 OK):**
- successfully REJECTED the offer
- if the offer is made by SELLER, the listing status becomes PENDING -> AVAILABLE
- if the offer is made by BUYER, the listing status remains the same


**Errors:**
- 400 if actor_id or offer_id is missing
- 404 if offer or list does not exist
- 409 if offer is made_by BUYER and listing is not in AVAILABLE status
- 409 if offer is made_by SELLER and listing is not in PENDING status
- 409 if offer expiration is in the past
- 409 if offer is not PENDING status
- 409 if offer is made_by BUYER and actor_id is not the seller
- 409 if offer is made_by SELLER and actor_id is not the buyer (buyer_id can be inferred from offer_id)


### POST /offers/:id/counter
- the awaiting party (buyer or seller) counters a PENDING offer on a listing.
- the old offer becomes REJECTED, and a new offer is created with the counter value


**Request Body:**
```json
{
  "actor_id": "0kasdsa",
  "offer_value": 450000,
  "expiration": "2024-02-15T10:30:00.000Z"
}
```
- `offer_value`: required, positive number
- `expiration`: required, ISO 8601 datetime, must be after the current virtual time

**On success (201 Created):**
returns the new Offer (full object)
```json
{
  "offer_id": "9mn34p",
  "listing_id": "ususus11221",
  "buyer_id": "1asads",
  "made_by": "SELLER",
  "offer_value": 450000,
  "expiration": "2024-02-15T10:30:00.000Z",
  "status": "PENDING",
  "created_at": "2024-01-15T10:30:00.000Z"
}
```
- original offer → REJECTED
- new offer status → PENDING
- made_by → the party that created this counter (i.e. the `actor_id`):
  - SELLER when the seller counters a buyer's offer
  - BUYER when the buyer counters a seller's offer
- if the new counter offer is made_by SELLER, the listing status becomes AVAILABLE -> PENDING (locked)
- if the new counter offer is made_by BUYER, the listing status becomes PENDING -> AVAILABLE (unlocked)

**Counter value rule (negotiation direction):**
- when the **seller** counters a buyer's offer, the new `offer_value` must be **greater** than the buyer's offer (the seller is asking for more)
- when the **buyer** counters a seller's offer, the new `offer_value` must be **less** than the seller's offer (the buyer is offering less)
- example: buyer offers 400000 → seller may counter 450000 (valid), not 390000 (409); the buyer may then counter 420000 (valid), not 460000 (409)

**Errors:**

- 400 if any field is missing, actor_id, offer_value, expiration
- 400 if offer expiration is in invalid (in the past)
- 400 if offer value is a negative number
- 409 if the counter `offer_value` breaks the negotiation direction (a seller's counter is not greater than the buyer's offer, or a buyer's counter is not less than the seller's offer)
- 409 if a buyer's counter would exceed the buyer's effective budget (see Budget invariant and Self-financing)
- 404 if listing does not exist
- 404 if offer does not exist
- 409 if offer is made_by BUYER and listing is not in AVAILABLE status
- 409 if offer is made_by SELLER and listing is not in PENDING status
- 409 if offer expiration is in the past
- 409 if offer is not PENDING status
- 409 if offer is made_by BUYER and actor_id is not the seller
- 409 if offer is made_by SELLER and actor_id is not the buyer (buyer_id can be inferred from offer_id)



### GET /offers/:id
- get the offer details given the offer id


**Response (200 OK):**
- return the offer details
- if expiration is in the past, and the status is PENDING, the status becomes EXPIRED (before returning the offer details)
- if expiration is in the past, and the status is PENDING, and the offer is made by SELLER, the listing status becomes AVAILABLE (before returning the offer details)

**Errors:**
- 404 : if offer does not exist


### POST /clock
- sets the server's virtual clock.
- the expiration are compared against this time
- advancing the clock immediately re-evaluates expiry: any PENDING offer whose `expiration` is now at/before the clock becomes EXPIRED (and a SELLER offer doing so unlocks its PENDING listing to AVAILABLE).

**Request Body:**
```json
{ "now": "2030-01-01T00:00:00Z" }
```

**Response:**
- 200 OK
- returns the current virtual time set

**Errors:**
- 400 if `now` is not a valid ISO 8601 datetime
- 400 if `now` is missing


## Technical Requirements

1. **Language**: TypeScript with Node.js
2. **Framework**: Express.js (or similar HTTP framework)
3. **Server Startup**: The server must start via `npm start` and listen on the port specified by the `PORT` environment variable, defaulting to 3000 if not set. You may organize your code in any file structure you choose.
4. **Storage**: In-memory storage only (no database required). Data persists only for the lifetime of the server process.
5. **Dependencies**: You may use `express`, `uuid`, and their TypeScript types. List all dependencies in `package.json`.

6. **Date/Time Handling:** Use ISO 8601 datetimes in UTC (e.g. "2030-06-01T00:00:00Z"). `created_at` is server-generated. All expiration checks compare against the virtual clock set by `POST /clock`, never the real wall clock.

7. **Expiry is global and authoritative:** at any moment, an offer whose `expiration` is at or before the current virtual time is **EXPIRED**, regardless of which endpoint is called. Before applying the rules of *any* request — every read **and** every write, including the buyer-budget computation on `POST /offers` and `POST /offers/:id/counter` — the server must first treat all such offers as EXPIRED (a SELLER offer expiring also unlocks its PENDING listing back to AVAILABLE). Because an EXPIRED offer is no longer PENDING, it no longer counts toward a buyer's committed budget.

8. **Timestamp Validation:**
`expiration` (offers/counters) and `now` (clock) must be valid ISO 8601 datetime strings.
Reject with 400 if missing, not a string, or not a valid datetime.
Additionally, an offer/counter `expiration` must be after the current virtual time (else 400).
