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
  status: 'DRAFT' | 'AVAILABLE' | 'PENDING' | 'SOLD' | 'ARCHIVED';  // server-managed lifecycle
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
Every user has a `budget`. At any time, the **sum of a buyer's outstanding (PENDING) offers across all listings must not exceed that buyer's `budget`.** Only `made_by: BUYER` offers with status `PENDING` count toward the total; offers that are REJECTED, EXPIRED, or ACCEPTED do not (their amount is released). This is enforced whenever a buyer commits money — creating an offer (`POST /offers`) or countering a seller's offer (`POST /offers/:id/counter`). If the new amount would push the buyer's PENDING total over `budget`, respond **409**. A total exactly equal to `budget` is allowed.

**Example** (buyer budget = 100000):
- offer 60000 on listing A → 201 (committed 60000)
- offer 60000 on listing B → 409 (would be 120000 > 100000)
- reject/expire the listing-A offer → frees 60000
- offer 60000 on listing B → 201 (committed 60000)


## Contingent offers (dependency graph)
An offer may be **contingent on the sale of another listing** (e.g. the buyer must sell their current home first). Set the optional `contingent_on` field to a `listing_id` when creating an offer via `POST /offers`. Counters never carry a contingency (a countered offer's replacement has `contingent_on: null`).

Treat contingencies as a directed graph over listings: a **PENDING** offer on listing `X` with `contingent_on = Y` is an edge `X → Y` ("X's sale depends on Y selling first"). Rules:

- **R1 (validation):** if `contingent_on` is present it must reference an existing listing (else **400**); it may not equal the offer's own `listing_id` (else **409**).
- **R2 (no cycles):** creating the offer must not form a cycle in the graph — considering existing PENDING edges plus the new one — whether **direct or transitive** (e.g. X→Y, Y→Z already exist, then a new Z→X). A cycle → **409**. Only PENDING offers form edges (REJECTED/EXPIRED/ACCEPTED do not).
- **R3 (accept-block):** an offer with `contingent_on = D` can only be accepted once listing `D` is **SOLD**. Accepting while `D` is not SOLD → **409**.
- **R4 (cascade):** when a listing `D` is ARCHIVED, every PENDING offer with `contingent_on = D` becomes **REJECTED** (its contingency can never be satisfied).

**Accept-check precedence** (exact order for `POST /offers/:id/accept`, so the result is deterministic):
1. offer exists — else 404
2. offer is PENDING — else 409
3. `actor_id` present — else 400
4. `actor_id` is the awaited party — else 409
5. listing-lock rule (a BUYER offer requires its listing to be AVAILABLE) — else 409
6. **contingency satisfied** (`contingent_on` listing is SOLD) — else 409


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
- 409 if the offer would exceed the buyer's budget (sum of the buyer's PENDING offers across all listings + this offer > budget; see Budget invariant)
- 400 if `contingent_on` is present but does not reference an existing listing (see Contingent offers)
- 409 if `contingent_on` equals this offer's own listing, or would create a dependency cycle (see Contingent offers)


### POST /offers/:id/accept
The user accepts an offer on a listing.
User can be buyer or seller

**Request Body:**
- `actor_id`: required — must be the awaited party
  (BUYER offer → the listing's seller; SELLER counter → the offer's buyer)

**On success (200 OK):** returns the full Offer.
- offer → ACCEPTED
- listing → SOLD
- all OTHER PENDING offers on that listing → REJECTED (cascade; not shown in the response)

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
- 409 if the offer is contingent on a listing that is not yet SOLD (see Contingent offers, R3)


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
- 409 if a buyer's counter would exceed the buyer's budget (see Budget invariant)
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
