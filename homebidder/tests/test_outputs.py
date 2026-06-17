"""
Black-box HTTP grader for the Homebidder API. Exercises both state machines,
the alternating counter chain, the listing lock, the accept cascade, virtual-clock
expiry, and every error path. Deterministic: a test-controlled virtual clock,
unique emails per entity, exact status-code + state assertions.
"""
import itertools
import requests

BASE = "http://localhost:3000"
T0 = "2030-01-01T00:00:00Z"
FUTURE = "2030-06-01T00:00:00Z"
LATER = "2030-12-01T00:00:00Z"   # past FUTURE -> triggers expiry
_seq = itertools.count(1)


def email():
    return f"user{next(_seq)}@homebidder.test"

def set_clock(ts=T0):
    r = requests.post(f"{BASE}/clock", json={"now": ts}); assert r.status_code == 200, r.text; return r

def mk_user():
    r = requests.post(f"{BASE}/users", json={"name": "U", "email": email()})
    assert r.status_code == 201, r.text; return r.json()["user_id"]

def mk_listing(seller):
    r = requests.post(f"{BASE}/listings", json={"seller_id": seller, "address": "1 Main St", "price": 500000})
    assert r.status_code == 201, r.text; return r.json()["listing_id"]

def publish(lid):
    r = requests.post(f"{BASE}/listings/{lid}/publish"); assert r.status_code == 200, r.text

def available():
    """Return (seller_id, listing_id) for a published AVAILABLE listing."""
    s = mk_user(); lid = mk_listing(s); publish(lid); return s, lid

def mk_offer(lid, buyer, value=400000, expiration=FUTURE):
    return requests.post(f"{BASE}/offers", json={"listing_id": lid, "buyer_id": buyer, "offer_value": value, "expiration": expiration})

def accept(oid, actor): return requests.post(f"{BASE}/offers/{oid}/accept", json={"actor_id": actor})
def reject(oid, actor): return requests.post(f"{BASE}/offers/{oid}/reject", json={"actor_id": actor})
def counter(oid, actor, value=450000, expiration=FUTURE):
    return requests.post(f"{BASE}/offers/{oid}/counter", json={"actor_id": actor, "offer_value": value, "expiration": expiration})
def listing_status(lid): return requests.get(f"{BASE}/listings/{lid}").json()["status"]
def offer_status(oid): return requests.get(f"{BASE}/offers/{oid}").json()["status"]


# ---------- users ----------
def test_user_create_and_dup_email():
    set_clock()
    e = email()
    r1 = requests.post(f"{BASE}/users", json={"name": "A", "email": e}); assert r1.status_code == 201
    assert "user_id" in r1.json()
    r2 = requests.post(f"{BASE}/users", json={"name": "B", "email": e}); assert r2.status_code == 409

def test_user_bad_input_400():
    assert requests.post(f"{BASE}/users", json={"name": ""}).status_code == 400
    assert requests.post(f"{BASE}/users", json={"email": email()}).status_code == 400


# ---------- listings ----------
def test_listing_create_is_draft():
    s = mk_user()
    r = requests.post(f"{BASE}/listings", json={"seller_id": s, "address": "X", "price": 1})
    assert r.status_code == 201 and r.json()["status"] == "DRAFT"

def test_listing_invalid_seller_400():
    assert requests.post(f"{BASE}/listings", json={"seller_id": "nope", "address": "X", "price": 1}).status_code == 400

def test_publish_transitions_and_errors():
    set_clock()
    s = mk_user(); lid = mk_listing(s)
    assert requests.post(f"{BASE}/listings/{lid}/publish").status_code == 200
    assert listing_status(lid) == "AVAILABLE"
    assert requests.post(f"{BASE}/listings/{lid}/publish").status_code == 409  # not DRAFT anymore
    assert requests.post(f"{BASE}/listings/zzz/publish").status_code == 404


# ---------- offer creation ----------
def test_offer_on_available_is_pending_buyer():
    set_clock(); _, lid = available(); b = mk_user()
    r = mk_offer(lid, b); assert r.status_code == 201
    o = r.json(); assert o["status"] == "PENDING" and o["made_by"] == "BUYER"

def test_offer_on_draft_409():
    set_clock(); s = mk_user(); lid = mk_listing(s); b = mk_user()
    assert mk_offer(lid, b).status_code == 409  # DRAFT not AVAILABLE

def test_owner_cannot_offer_409():
    set_clock(); s, lid = available()
    assert mk_offer(lid, s).status_code == 409

def test_second_pending_offer_409():
    set_clock(); _, lid = available(); b = mk_user()
    assert mk_offer(lid, b).status_code == 201
    assert mk_offer(lid, b).status_code == 409

def test_offer_expiration_in_past_400():
    set_clock(T0); _, lid = available(); b = mk_user()
    assert mk_offer(lid, b, expiration="2020-01-01T00:00:00Z").status_code == 400

def test_offer_unknown_listing_404():
    set_clock(); b = mk_user()
    assert mk_offer("nope", b).status_code == 404


# ---------- accept + cascade ----------
def test_accept_marks_sold_and_cascades():
    set_clock(); s, lid = available()
    b1, b2 = mk_user(), mk_user()
    o1 = mk_offer(lid, b1).json()["offer_id"]
    o2 = mk_offer(lid, b2).json()["offer_id"]
    assert accept(o1, s).status_code == 200
    assert offer_status(o1) == "ACCEPTED"
    assert offer_status(o2) == "REJECTED"      # cascade
    assert listing_status(lid) == "SOLD"

def test_accept_wrong_party_409():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert accept(o, b).status_code == 409      # buyer offer is awaited by SELLER, not buyer


# ---------- reject ----------
def test_reject_buyer_offer_keeps_listing():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert reject(o, s).status_code == 200
    assert offer_status(o) == "REJECTED"
    assert listing_status(lid) == "AVAILABLE"   # unchanged


# ---------- counter chain + lock ----------
def test_seller_counter_locks_listing():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    r = counter(o1, s, value=380000); assert r.status_code == 201
    n = r.json()
    assert offer_status(o1) == "REJECTED"
    assert n["made_by"] == "SELLER" and n["status"] == "PENDING"
    assert listing_status(lid) == "PENDING"     # locked

def test_lock_blocks_new_offers_and_other_accepts():
    set_clock(); s, lid = available()
    b1, b2 = mk_user(), mk_user()
    o1 = mk_offer(lid, b1).json()["offer_id"]
    o2 = mk_offer(lid, b2).json()["offer_id"]   # made before lock
    counter(o1, s, value=380000)                               # listing now PENDING (locked)
    b3 = mk_user()
    assert mk_offer(lid, b3).status_code == 409   # no new offers while locked
    assert accept(o2, s).status_code == 409       # seller can't accept other offer while locked

def test_buyer_accepts_counter_sold():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s, value=380000).json()["offer_id"]
    assert accept(n, b).status_code == 200        # buyer is awaited party on a SELLER offer
    assert offer_status(n) == "ACCEPTED"
    assert listing_status(lid) == "SOLD"

def test_buyer_rejects_counter_unlocks():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s, value=380000).json()["offer_id"]
    assert reject(n, b).status_code == 200
    assert offer_status(n) == "REJECTED"
    assert listing_status(lid) == "AVAILABLE"     # unlocked

def test_buyer_counters_back_unlocks():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s, value=380000).json()["offer_id"]         # seller counter, listing PENDING
    r = counter(n, b)                              # buyer counters back
    assert r.status_code == 201
    n2 = r.json()
    assert offer_status(n) == "REJECTED"
    assert n2["made_by"] == "BUYER" and n2["status"] == "PENDING"
    assert listing_status(lid) == "AVAILABLE"     # unlocked, seller free again

def test_buyer_counter_must_be_higher_409():
    """Buyer countering a seller offer must have a higher value."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    n = counter(o1, s, value=380000).json()["offer_id"]  # seller counters at 380k (lower, valid)
    # Buyer tries to counter back at 370k (lower than seller's 380k) -> 409
    r = counter(n, b, value=370000)
    assert r.status_code == 409

def test_seller_counter_must_be_lower_409():
    """Seller countering a buyer offer must have a lower value."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    # Seller tries to counter at 410k (higher than buyer's 400k) -> 409
    r = counter(o1, s, value=410000)
    assert r.status_code == 409

def test_valid_directional_counter_succeeds():
    """Valid directional counters should succeed."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    # Seller counters lower at 380k -> 201
    r1 = counter(o1, s, value=380000)
    assert r1.status_code == 201
    n1 = r1.json()["offer_id"]
    # Buyer counters higher at 390k -> 201
    r2 = counter(n1, b, value=390000)
    assert r2.status_code == 201


# ---------- expiry (virtual clock) ----------
def test_offer_expires_with_clock():
    set_clock(T0); _, lid = available(); b = mk_user()
    o = mk_offer(lid, b, expiration=FUTURE).json()["offer_id"]
    assert offer_status(o) == "PENDING"
    set_clock(LATER)                               # advance past expiration
    assert offer_status(o) == "EXPIRED"

def test_seller_counter_expiry_unlocks():
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s, expiration=FUTURE).json()["offer_id"]
    assert listing_status(lid) == "PENDING"
    set_clock(LATER)                               # seller counter expires
    assert offer_status(n) == "EXPIRED"
    assert listing_status(lid) == "AVAILABLE"      # auto-unlocked

def test_cannot_accept_expired_409():
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, expiration=FUTURE).json()["offer_id"]
    set_clock(LATER)
    assert accept(o, s).status_code == 409


# ---------- archive ----------
def test_archive_rejects_pending_offers():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert requests.post(f"{BASE}/listings/{lid}/archive").status_code == 200
    assert listing_status(lid) == "ARCHIVED"
    assert offer_status(o) == "REJECTED"

def test_archive_blocked_when_locked_409():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    counter(o1, s, value=380000)                                 # listing PENDING
    assert requests.post(f"{BASE}/listings/{lid}/archive").status_code == 409


# ---------- misc ----------
def test_clock_invalid_400():
    assert requests.post(f"{BASE}/clock", json={"now": "not-a-date"}).status_code == 400

def test_unknown_offer_404():
    assert requests.get(f"{BASE}/offers/nope").status_code == 404
    assert accept("nope", "x").status_code == 404
