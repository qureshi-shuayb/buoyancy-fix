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
}

interface Listing {
  listing_id: string;   // UUID, server-generated
  address: string;      // required, non-empty
  price: number;        // required, positive number
  seller_id: string;    // user_id of the owner; must reference an existing user
  status: 'DRAFT' | 'AVAILABLE' | 'SOLD' | 'ARCHIVED';  // server-managed lifecycle
  locked_until: string | null;  // ISO 8601 datetime or null; when set to a future time, the listing is locked (no new offers, seller cannot accept other offers)
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
}
```


## API Endpoints

### POST /users
Creates a new user.

**Request Body:**
```json
{ "name": "Kobe Bryant", "email": "Kobe@example.com" }
```
- `name`: required, non-empty string
- `email`: required, non-empty string, unique across all users

**Response (201 Created):**
the created user
```json
{
"user_id": "ahh121212.",
"name": "Kobe Bryant",
"email": "Kobe@example.com"
}
```
- server generates `user_id` (UUID)

**Errors:**
- 400 if `name` or `email` is missing/empty
- 409 if a user with that `email` already exists


### POST /listings
Creates a new listing

**Request Body:**
​```json
{ "seller_id": "ahh121212", "address": "123 Main St", "price": 450000 }
​```
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
When archived, all PENDING offers on the listing become REJECTED.

**Response (200 OK):**
the updated Listing (status `ARCHIVED`)

**Errors:**
- 404 if no listing exists with that id
- 409 if the listing is not in DRAFT or AVAILABLE status (i.e., cannot archive a locked listing)


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
"buyer_id": "1asads", // user_id of the buyer, required
"listing_id": "ususus11221", // listing_id of the listing, required
"offer_value": 420000, // offer value, required, positive number
"expiration": "2024-02-15T10:30:00.000Z", // expiration date, required,
}
```


**Response (201 Created):**
Offer successfully created
return
```json
{
"status": "PENDING",
"made_by": "BUYER",
"offer_id": "1kl12k", // made by server
"created at": "2024-02-15T10:30:00.000Z",
}
```


**Errors:**
- 400 if any field is missing, buyer_id, listing_id, offer_value, expiration
- 400 if offer expiration is in invalid (in the past)
- 400 if offer value is a negative number
- 404 if listing does not exist
- 409 if buyer id === seller
- 409 if the listing is not AVAILABLE or is locked
- 409 if buyer already made an offer on listing


### POST /offers/:id/accept
The user accepts an offer on a listing.
User can be buyer or seller

**Request Body:**
- `actor_id`: required — must be the awaited party
  (BUYER offer → the listing's seller; SELLER counter → the offer's buyer)

**On success (200 OK):** returns the Offer.
- offer → ACCEPTED
- listing → SOLD
- all OTHER PENDING offers on that listing → REJECTED  (cascade)


**On success (200 OK):**
- successfully accepted the offer

```json
{
"status": "ACCEPTED",
"offer_id": "1kl12k", // made by server
}
```
- LISTING becomes SOLD
- all the other offer on the listing becomes REJECTED, we dont need to show this in the response

**Errors:**
- 400 if actor_id or offer_id is missing
- 404 if offer or list does not exist
- 409 if offer is made_by BUYER and the listing is not AVAILABLE or is locked
- 409 if offer is made_by SELLER and the listing is locked by a different offer (only the specific counter that locked the listing may be acted upon)
- 409 if offer expiration is in the past
- 409 if offer is not PENDING status
- 409 if offer is made_by BUYER and actor_id is not the seller
- 409 if offer is made_by SELLER and actor_id is not the buyer (buyer_id can be inferred from offer_id)


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
- if the offer was made by SELLER, the listing unlocks
- if the offer is made by BUYER, the listing status remains the same


**Errors:**
- 400 if actor_id or offer_id is missing
- 404 if offer or list does not exist
- 409 if offer is made_by BUYER and the listing is not AVAILABLE or is locked
- 409 if offer is made_by SELLER and the listing is locked by a different offer (only the specific counter that locked the listing may be acted upon)
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
"offer_value": 450000, //required, positive number
"expiration": "2024-02-15T10:30:00.000Z", //required, ISO 8601 datetime, must be after current time
}
```
**On success (201 Created):**
return the new offer
- orginal offer → REJECTED
- status → PENDING
- made_by → SELLER (if buyer counter) or BUYER (if seller counter)
- if the new offer is made by SELLER, the listing becomes locked (set `locked_until` to the new offer's expiration)
- if the new offer is made by BUYER, the listing becomes unlocked (set `locked_until` to null)

**Errors:**

- 400 if any field is missing, actor_id, offer_value, expiration
- 400 if offer expiration is in invalid (in the past)
- 400 if offer value is a negative number
- 404 if listing does not exist
- 404 if offer does not exist
- 409 if offer is made_by BUYER and the listing is not AVAILABLE or is locked
- 409 if offer is made_by SELLER and the listing is locked by a different offer (only the specific counter that locked the listing may be acted upon)
- 409 if offer expiration is in the past
- 409 if offer is not PENDING status
- 409 if offer is made_by BUYER and actor_id is not the seller
- 409 if offer is made_by SELLER and actor_id is not the buyer (buyer_id can be inferred from offer_id)



### GET /offers/:id
- get the offer details given the offer id


**Response (200 OK):**
- return the offer details
- if expiration is in the past, and the status is PENDING, the status becomes EXPIRED (before returning the offer details)
- if the now-EXPIRED offer was made by SELLER, the listing also unlocks (set `locked_until` to null)

**Errors:**
- 404 : if offer does not exist


### POST /clock
- sets the server's virtual clock.
- the expiration are compared against this time

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

7. **Timestamp Validation:**
`expiration` (offers/counters) and `now` (clock) must be valid ISO 8601 datetime strings.
Reject with 400 if missing, not a string, or not a valid datetime.
Additionally, an offer/counter `expiration` must be after the current virtual time (else 400).
