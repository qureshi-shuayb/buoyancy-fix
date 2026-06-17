"""
Black-box HTTP grader for the Homebidder API. Exercises both state machines,
the alternating counter chain, the listing lock, the accept cascade, virtual-clock
expiry, and every error path. Deterministic: a test-controlled virtual clock,
unique emails per entity, exact status-code + state assertions.
"""
import itertools
from datetime import datetime
import pytest
import requests

BASE = "http://localhost:3000"
T0 = "2030-01-01T00:00:00Z"
FUTURE = "2030-06-01T00:00:00Z"
LATER = "2030-12-01T00:00:00Z"   # past FUTURE -> triggers expiry
EVEN_LATER = "2031-06-01T00:00:00Z"   # valid expiration once the clock has advanced to LATER
BIG_BUDGET = 10_000_000           # high enough not to constrain non-budget tests
_seq = itertools.count(1)


def email():
    return f"user{next(_seq)}@homebidder.test"

def set_clock(ts=T0):
    r = requests.post(f"{BASE}/clock", json={"now": ts}); assert r.status_code == 200, r.text; return r

def mk_user(budget=BIG_BUDGET):
    r = requests.post(f"{BASE}/users", json={"name": "U", "email": email(), "budget": budget})
    assert r.status_code == 201, r.text; return r.json()["user_id"]

def mk_listing(seller):
    r = requests.post(f"{BASE}/listings", json={"seller_id": seller, "address": "1 Main St", "price": 500000})
    assert r.status_code == 201, r.text; return r.json()["listing_id"]

def publish(lid):
    r = requests.post(f"{BASE}/listings/{lid}/publish"); assert r.status_code == 200, r.text

def available():
    """Return (seller_id, listing_id) for a published AVAILABLE listing."""
    s = mk_user(); lid = mk_listing(s); publish(lid); return s, lid

def mk_offer(lid, buyer, value=400000, expiration=FUTURE, contingent_on=None):
    body = {"listing_id": lid, "buyer_id": buyer, "offer_value": value, "expiration": expiration}
    if contingent_on is not None:
        body["contingent_on"] = contingent_on
    return requests.post(f"{BASE}/offers", json=body)

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
    r1 = requests.post(f"{BASE}/users", json={"name": "A", "email": e, "budget": BIG_BUDGET}); assert r1.status_code == 201
    assert "user_id" in r1.json()
    r2 = requests.post(f"{BASE}/users", json={"name": "B", "email": e, "budget": BIG_BUDGET}); assert r2.status_code == 409

def test_user_bad_input_400():
    assert requests.post(f"{BASE}/users", json={"name": ""}).status_code == 400
    assert requests.post(f"{BASE}/users", json={"email": email()}).status_code == 400
    assert requests.post(f"{BASE}/users", json={"name": "U", "email": email()}).status_code == 400          # budget missing
    assert requests.post(f"{BASE}/users", json={"name": "U", "email": email(), "budget": 0}).status_code == 400  # budget not positive


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
    r = counter(o1, s); assert r.status_code == 201   # seller counters higher (default 450k > 400k)
    n = r.json()
    assert offer_status(o1) == "REJECTED"
    assert n["made_by"] == "SELLER" and n["status"] == "PENDING"
    assert listing_status(lid) == "PENDING"     # locked

def test_lock_blocks_new_offers_and_other_accepts():
    set_clock(); s, lid = available()
    b1, b2 = mk_user(), mk_user()
    o1 = mk_offer(lid, b1).json()["offer_id"]
    o2 = mk_offer(lid, b2).json()["offer_id"]   # made before lock
    counter(o1, s)                                             # listing now PENDING (locked)
    b3 = mk_user()
    assert mk_offer(lid, b3).status_code == 409   # no new offers while locked
    assert accept(o2, s).status_code == 409       # seller can't accept other offer while locked

def test_buyer_accepts_counter_sold():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s).json()["offer_id"]
    assert accept(n, b).status_code == 200
    assert offer_status(n) == "ACCEPTED"
    assert listing_status(lid) == "SOLD"

def test_buyer_rejects_counter_unlocks():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s).json()["offer_id"]
    assert reject(n, b).status_code == 200
    assert offer_status(n) == "REJECTED"
    assert listing_status(lid) == "AVAILABLE"     # unlocked

def test_buyer_counters_back_unlocks():
    set_clock(); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b).json()["offer_id"]
    n = counter(o1, s).json()["offer_id"]                       # seller counter (higher), listing PENDING
    r = counter(n, b, value=420000)                # buyer counters back lower than seller's 450k
    assert r.status_code == 201
    n2 = r.json()
    assert offer_status(n) == "REJECTED"
    assert n2["made_by"] == "BUYER" and n2["status"] == "PENDING"
    assert listing_status(lid) == "AVAILABLE"     # unlocked, seller free again

def test_buyer_counter_must_be_lower_409():
    """Buyer countering a seller's offer must have a lower value."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    n = counter(o1, s, value=450000).json()["offer_id"]  # seller counters at 450k (higher, valid)
    # Buyer tries to counter back at 460k (higher than seller's 450k) -> 409
    r = counter(n, b, value=460000)
    assert r.status_code == 409

def test_seller_counter_must_be_higher_409():
    """Seller countering a buyer's offer must have a higher value."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    # Seller tries to counter at 390k (lower than buyer's 400k) -> 409
    r = counter(o1, s, value=390000)
    assert r.status_code == 409

def test_valid_directional_counter_succeeds():
    """Valid directional counters should succeed."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o1 = mk_offer(lid, b, value=400000).json()["offer_id"]
    # Seller counters higher at 450k -> 201
    r1 = counter(o1, s, value=450000)
    assert r1.status_code == 201
    n1 = r1.json()["offer_id"]
    # Buyer counters lower at 420k -> 201
    r2 = counter(n1, b, value=420000)
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
    n = counter(o1, s, expiration=FUTURE).json()["offer_id"]  # seller counter (default 450k, higher than buyer's 400k)
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
    counter(o1, s)                                               # listing PENDING (seller counters higher)
    assert requests.post(f"{BASE}/listings/{lid}/archive").status_code == 409


# ---------- misc ----------
def test_clock_invalid_400():
    assert requests.post(f"{BASE}/clock", json={"now": "not-a-date"}).status_code == 400

def test_unknown_offer_404():
    assert requests.get(f"{BASE}/offers/nope").status_code == 404
    assert accept("nope", "x").status_code == 404


# ---------- value validation ----------
def test_negative_offer_value_400():
    set_clock(); _, lid = available(); b = mk_user()
    assert mk_offer(lid, b, value=-100).status_code == 400

def test_archive_unknown_listing_404():
    assert requests.post(f"{BASE}/listings/nope/archive").status_code == 404


# ---------- terminal-state guards (offer must be PENDING) ----------
def test_counter_on_expired_offer_409():
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, expiration=FUTURE).json()["offer_id"]
    set_clock(LATER)                               # offer now EXPIRED
    # valid (future) counter expiration so the only failing condition is the expired target offer
    assert counter(o, s, value=450000, expiration=EVEN_LATER).status_code == 409

def test_reject_on_expired_offer_409():
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, expiration=FUTURE).json()["offer_id"]
    set_clock(LATER)
    assert reject(o, s).status_code == 409

def test_double_accept_409():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert accept(o, s).status_code == 200
    assert accept(o, s).status_code == 409         # already ACCEPTED, not PENDING


# ---------- wrong-party guards ----------
def test_reject_wrong_party_409():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert reject(o, b).status_code == 409         # buyer cannot reject own BUYER offer (awaited = seller)

def test_counter_wrong_party_409():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert counter(o, b, value=450000).status_code == 409   # awaited party is the seller


# ---------- one-PENDING-offer-per-buyer (terminal offers don't count) ----------
def test_reoffer_after_reject_allowed():
    set_clock(); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b).json()["offer_id"]
    assert reject(o, s).status_code == 200
    assert mk_offer(lid, b).status_code == 201     # previous offer is REJECTED -> buyer may offer again


# ---------- offers blocked on terminal listings ----------
def test_offer_on_sold_listing_409():
    set_clock(); s, lid = available()
    b1, b2 = mk_user(), mk_user()
    o1 = mk_offer(lid, b1).json()["offer_id"]
    assert accept(o1, s).status_code == 200        # listing SOLD
    assert mk_offer(lid, b2).status_code == 409

def test_offer_on_archived_listing_409():
    set_clock(); s, lid = available(); b = mk_user()
    assert requests.post(f"{BASE}/listings/{lid}/archive").status_code == 200
    assert mk_offer(lid, b).status_code == 409


# ---------- full alternating chain (made_by flips, buyer_id preserved) ----------
def test_full_counter_chain_to_sold():
    set_clock(T0); s, lid = available(); b = mk_user()
    o0 = mk_offer(lid, b, value=400000).json()
    assert o0["made_by"] == "BUYER"
    n1 = counter(o0["offer_id"], s, value=450000).json()   # seller higher
    assert n1["made_by"] == "SELLER" and n1["buyer_id"] == b
    assert listing_status(lid) == "PENDING"
    n2 = counter(n1["offer_id"], b, value=420000).json()   # buyer lower than seller's 450k
    assert n2["made_by"] == "BUYER" and n2["buyer_id"] == b
    assert listing_status(lid) == "AVAILABLE"
    n3 = counter(n2["offer_id"], s, value=440000).json()   # seller higher than buyer's 420k
    assert n3["made_by"] == "SELLER"
    assert listing_status(lid) == "PENDING"
    assert accept(n3["offer_id"], b).status_code == 200
    assert listing_status(lid) == "SOLD"


# ---------- budget invariant (buyer's PENDING offers across all listings <= budget) ----------
def test_budget_blocks_over_commit_409():
    set_clock(T0); _, l1 = available(); _, l2 = available()
    b = mk_user(budget=100000)
    assert mk_offer(l1, b, value=60000).status_code == 201
    assert mk_offer(l2, b, value=60000).status_code == 409   # 60k + 60k = 120k > 100k

def test_budget_exact_boundary_allowed():
    set_clock(T0); _, l1 = available(); _, l2 = available(); _, l3 = available()
    b = mk_user(budget=100000)
    assert mk_offer(l1, b, value=60000).status_code == 201
    assert mk_offer(l2, b, value=40000).status_code == 201   # sum exactly 100k == budget -> allowed
    assert mk_offer(l3, b, value=1).status_code == 409        # 100001 > 100k

def test_budget_released_on_reject():
    set_clock(T0); s1, l1 = available(); _, l2 = available()
    b = mk_user(budget=100000)
    o1 = mk_offer(l1, b, value=60000).json()["offer_id"]
    assert mk_offer(l2, b, value=60000).status_code == 409
    assert reject(o1, s1).status_code == 200                  # frees 60k
    assert mk_offer(l2, b, value=60000).status_code == 201

def test_budget_released_on_expiry():
    set_clock(T0); _, l1 = available(); _, l2 = available()
    b = mk_user(budget=100000)
    mk_offer(l1, b, value=60000, expiration=FUTURE)
    assert mk_offer(l2, b, value=60000).status_code == 409
    set_clock(LATER)                                          # l1 offer EXPIRES, frees 60k
    assert mk_offer(l2, b, value=60000, expiration=EVEN_LATER).status_code == 201

def test_budget_released_on_accept_cascade():
    set_clock(T0); s1, l1 = available(); _, l2 = available()
    bA = mk_user(budget=100000); bB = mk_user(budget=100000)
    oB = mk_offer(l1, bB, value=60000).json()["offer_id"]
    assert mk_offer(l2, bB, value=60000).status_code == 409   # bB committed 60k on l1
    oA = mk_offer(l1, bA, value=70000).json()["offer_id"]
    assert accept(oA, s1).status_code == 200                  # cascade-rejects bB's l1 offer -> frees bB's 60k
    assert mk_offer(l2, bB, value=60000).status_code == 201

def test_budget_counter_rechecks_409():
    set_clock(T0); s1, l1 = available(); _, l2 = available()
    b = mk_user(budget=100000)
    mk_offer(l2, b, value=30000)                              # committed 30k elsewhere
    o1 = mk_offer(l1, b, value=20000).json()["offer_id"]
    n = counter(o1, s1, value=90000).json()["offer_id"]      # seller counters higher -> SELLER offer 90k (l1 buyer offer freed)
    # buyer counter 80k: directional ok (80k < 90k) but 30k + 80k = 110k > budget -> 409
    assert counter(n, b, value=80000).status_code == 409
    # buyer counter 60k: 60k < 90k and 30k + 60k = 90k <= budget -> 201
    assert counter(n, b, value=60000).status_code == 201


# ---------- contingency dependency graph (offer contingent on a listing's sale) ----------
def test_contingent_offer_create_ok():
    set_clock(); _, l1 = available(); _, dep = available(); b = mk_user()
    r = mk_offer(l1, b, contingent_on=dep)
    assert r.status_code == 201
    assert r.json()["contingent_on"] == dep

def test_contingent_unknown_listing_400():
    set_clock(); _, l1 = available(); b = mk_user()
    assert mk_offer(l1, b, contingent_on="nope").status_code == 400

def test_contingent_self_409():
    set_clock(); _, l1 = available(); b = mk_user()
    assert mk_offer(l1, b, contingent_on=l1).status_code == 409

def test_cycle_direct_409():
    set_clock(); _, lA = available(); _, lB = available()
    assert mk_offer(lA, mk_user(), contingent_on=lB).status_code == 201   # A -> B
    assert mk_offer(lB, mk_user(), contingent_on=lA).status_code == 409   # B -> A closes a cycle

def test_cycle_transitive_409():
    set_clock(); _, lA = available(); _, lB = available(); _, lC = available()
    assert mk_offer(lA, mk_user(), contingent_on=lB).status_code == 201   # A -> B
    assert mk_offer(lB, mk_user(), contingent_on=lC).status_code == 201   # B -> C
    assert mk_offer(lC, mk_user(), contingent_on=lA).status_code == 409   # C -> A closes a transitive cycle

def test_no_cycle_diamond_ok():
    set_clock(); _, lA = available(); _, lB = available(); _, lC = available(); _, lD = available()
    assert mk_offer(lA, mk_user(), contingent_on=lB).status_code == 201   # A -> B
    assert mk_offer(lA, mk_user(), contingent_on=lC).status_code == 201   # A -> C
    assert mk_offer(lB, mk_user(), contingent_on=lD).status_code == 201   # B -> D
    assert mk_offer(lC, mk_user(), contingent_on=lD).status_code == 201   # C -> D (diamond, no cycle)

def test_accept_blocked_until_dependency_sold_409():
    set_clock(); sA, lA = available(); _, dep = available(); b = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    assert accept(o, sA).status_code == 409   # dep not SOLD -> contingency unmet

def test_accept_allowed_after_dependency_sold_200():
    set_clock(); sA, lA = available(); sDep, dep = available()
    b = mk_user(); bDep = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    oDep = mk_offer(dep, bDep).json()["offer_id"]
    assert accept(oDep, sDep).status_code == 200   # dep now SOLD
    assert accept(o, sA).status_code == 200         # contingency satisfied
    assert listing_status(lA) == "SOLD"

def test_archive_dependency_cascade_rejects():
    set_clock(); sA, lA = available(); _, dep = available(); b = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    assert requests.post(f"{BASE}/listings/{dep}/archive").status_code == 200
    assert offer_status(o) == "REJECTED"   # contingency can never be satisfied -> cascade reject

def test_rejected_edge_not_in_cycle_graph():
    set_clock(); sA, lA = available(); _, lB = available()
    oA = mk_offer(lA, mk_user(), contingent_on=lB).json()["offer_id"]   # A -> B edge
    assert reject(oA, sA).status_code == 200                            # edge removed (REJECTED)
    assert mk_offer(lB, mk_user(), contingent_on=lA).status_code == 201  # B -> A now fine (no cycle)

def test_accept_missing_actor_400_precedes_contingency():
    set_clock(); _, lA = available(); _, dep = available(); b = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    r = requests.post(f"{BASE}/offers/{o}/accept", json={})   # no actor_id
    assert r.status_code == 400   # missing actor_id (400) precedes the contingency check (409)


# ---------- self-financing (effective budget = base + proceeds from own SOLD listings) ----------
def _sell(lid, seller, value, expiration=FUTURE):
    """A fresh buyer buys `lid` for `value`; `seller` accepts so the listing becomes SOLD."""
    buyer = mk_user()
    oid = mk_offer(lid, buyer, value=value, expiration=expiration).json()["offer_id"]
    assert accept(oid, seller).status_code == 200

def test_contingent_offer_over_budget_allowed_at_creation():
    """A contingent offer is self-financing: not budget-checked at creation."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    assert mk_offer(lX, B, value=500000, contingent_on=lY).status_code == 201  # 500k >> 100k base, but contingent

def test_noncontingent_over_effective_budget_409():
    """A non-contingent offer is checked at creation; no proceeds -> base budget only."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    assert mk_offer(lX, B, value=150000).status_code == 409  # 150k > 100k, no proceeds

def test_self_finance_enables_accept():
    """Selling your own listing funds acceptance of a contingent offer that exceeds base budget."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 409          # Y not SOLD -> contingency unmet
    _sell(lY, B, 450000)                               # B realizes 450k proceeds
    assert accept(oX, sX).status_code == 200           # 500k <= 100k + 450k effective budget
    assert listing_status(lX) == "SOLD"

def test_self_finance_insufficient_proceeds_409():
    """If realized proceeds are too low, acceptance of the self-financed offer fails."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    _sell(lY, B, 350000)                               # only 350k proceeds
    assert accept(oX, sX).status_code == 409           # 500k > 100k + 350k
    assert listing_status(lX) == "AVAILABLE"
    assert offer_status(oX) == "PENDING"

def test_proceeds_raise_cap_for_noncontingent():
    """Realized proceeds raise the effective budget for ordinary (non-contingent) offers too."""
    set_clock(T0)
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    _sell(lY, B, 200000)                               # effective budget now 300k
    sX, lX = available()
    assert mk_offer(lX, B, value=300000).status_code == 201   # 300k <= 300k
    sZ, lZ = available()
    assert mk_offer(lZ, B, value=1).status_code == 409         # committed 300k + 1 > 300k

def test_accept_rechecks_effective_budget_with_other_commitment_409():
    """Acceptance re-check accounts for the buyer's other PENDING commitments, not just this offer."""
    set_clock(T0)
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    _sell(lY, B, 300000)                               # effective budget 400k
    sX, lX = available()
    assert mk_offer(lX, B, value=300000).status_code == 201    # non-contingent, commits 300k
    sZ, lZ = available()
    oZ = mk_offer(lZ, B, value=200000, contingent_on=lY).json()["offer_id"]  # lY already SOLD; relaxed at creation
    assert accept(oZ, sZ).status_code == 409           # committed 300k + 200k = 500k > 400k


# ---------- Lever F: multi-way field interpretation on counter ----------
# A counter treats `contingent_on` and `expiration` as THREE-valued (absent / explicit null /
# value), asymmetrically vs POST /offers. The obvious `if (body.field)` collapses absent+null.
PAST = "2029-01-01T00:00:00Z"
_OMIT = object()

def counter_raw(oid, actor, value=450000, expiration=_OMIT, contingent_on=_OMIT):
    body = {"actor_id": actor, "offer_value": value}
    if expiration is not _OMIT:
        body["expiration"] = expiration
    if contingent_on is not _OMIT:
        body["contingent_on"] = contingent_on
    return requests.post(f"{BASE}/offers/{oid}/counter", json=body)

def offer_field(oid, field):
    return requests.get(f"{BASE}/offers/{oid}").json()[field]

def _inst(s):
    # Compare datetimes by instant, not raw string, so a server that normalizes the
    # representation (e.g. adds .000) is not falsely failed.
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()

# --- contingent_on three-valued ---
def test_counter_inherits_contingency_when_absent():
    """Omitting contingent_on on a counter inherits the parent offer's contingency."""
    set_clock(T0); sX, lX = available(); sY, lY = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000, contingent_on=lY).json()["offer_id"]
    r = counter_raw(o, sX, value=450000)                     # contingent_on omitted -> inherit lY
    assert r.status_code == 201
    assert r.json()["contingent_on"] == lY
    assert r.json()["made_by"] == "SELLER"

def test_counter_clears_contingency_with_explicit_null():
    """Explicit null on a counter clears the contingency (distinct from omitting it)."""
    set_clock(T0); sX, lX = available(); sY, lY = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000, contingent_on=lY).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, contingent_on=None)
    assert r.status_code == 201
    assert r.json()["contingent_on"] is None

def test_counter_repoints_contingency_with_value():
    """A value on a counter re-points the contingency to that listing."""
    set_clock(T0); sX, lX = available(); sY, lY = available(); sZ, lZ = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000, contingent_on=lY).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, contingent_on=lZ)
    assert r.status_code == 201
    assert r.json()["contingent_on"] == lZ

def test_counter_repoint_unknown_listing_400_no_mutation():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, contingent_on="nope")
    assert r.status_code == 400
    assert offer_status(o) == "PENDING"                      # rejected request must not mutate
    assert listing_status(lX) == "AVAILABLE"

def test_counter_repoint_self_409_no_mutation():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, contingent_on=lX)
    assert r.status_code == 409
    assert offer_status(o) == "PENDING"
    assert listing_status(lX) == "AVAILABLE"

def test_counter_repoint_cycle_409_no_mutation():
    """Re-pointing must re-run transitive cycle detection over PENDING edges."""
    set_clock(T0); sX, lX = available(); sY, lY = available()
    b1 = mk_user(); b2 = mk_user()
    mk_offer(lX, b1, value=400000, contingent_on=lY)         # edge X -> Y
    oY = mk_offer(lY, b2, value=400000).json()["offer_id"]
    r = counter_raw(oY, sY, value=450000, contingent_on=lX)  # would add Y -> X, closing the cycle
    assert r.status_code == 409
    assert offer_status(oY) == "PENDING"

# --- expiration three-valued (DIFFERENT null-semantics: null is 400, not "clear") ---
def test_counter_inherits_expiration_when_absent():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000, expiration=FUTURE).json()["offer_id"]
    r = counter_raw(o, sX, value=450000)                     # expiration omitted -> inherit FUTURE
    assert r.status_code == 201
    assert _inst(r.json()["expiration"]) == _inst(FUTURE)

def test_counter_explicit_null_expiration_400_no_mutation():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, expiration=None)
    assert r.status_code == 400                              # null clears contingent_on, but is 400 for expiration
    assert offer_status(o) == "PENDING"

def test_counter_value_expiration_used():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, expiration=EVEN_LATER)
    assert r.status_code == 201
    assert _inst(r.json()["expiration"]) == _inst(EVEN_LATER)

def test_counter_past_expiration_400_no_mutation():
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    r = counter_raw(o, sX, value=450000, expiration=PAST)
    assert r.status_code == 400
    assert offer_status(o) == "PENDING"

# --- self-financing interaction: contingency inherited through a counter chain skips the
#     budget check at counter time, but clearing it re-imposes the base-budget check ---
def test_counter_back_inheriting_contingency_skips_budget_check():
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    o = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]   # contingent, not checked
    n1 = counter_raw(o, sX, value=520000)                    # seller counters higher, inherits lY
    assert n1.status_code == 201 and n1.json()["contingent_on"] == lY
    n1id = n1.json()["offer_id"]
    r = counter_raw(n1id, B, value=510000)                   # buyer counters back, inherits lY -> contingent
    assert r.status_code == 201                              # NOT budget-checked (510k >> 100k base)
    assert r.json()["contingent_on"] == lY and r.json()["made_by"] == "BUYER"

def test_counter_back_clearing_contingency_budget_checked_409():
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    o = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    n1id = counter_raw(o, sX, value=520000).json()["offer_id"]
    r = counter_raw(n1id, B, value=510000, contingent_on=None)  # clears -> now budget-checked vs base 100k
    assert r.status_code == 409
    assert offer_status(n1id) == "PENDING"                   # no mutation on rejection
    assert listing_status(lX) == "PENDING"                   # still locked

# --- density: parametrized invalid inputs on counter ---
# Only cases the spec PINS ("required, positive number"): non-positive and missing.
# Avoid type-coercion-ambiguous values (e.g. "100", [1]) where Number(x) is a valid
# positive and an equally-defensible lenient implementation would accept them.
@pytest.mark.parametrize("bad", [-1, 0, None])
def test_counter_invalid_offer_value_400(bad):
    set_clock(T0); sX, lX = available()
    b = mk_user()
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    assert counter_raw(o, sX, value=bad).status_code == 400


# ============================================================================
# Phase 1 — Density. Adds parametrized error-axis tables, no-mutation-on-rejection
# re-reads, expiry boundary checks, and an expanded Lever F / contingency matrix.
# Every assertion maps to a SPEC-PINNED behavior (one spec-derivable answer):
#   - "required / non-empty / positive number"  -> 400 on missing/empty/non-positive
#   - Technical Req #8: expiration "not a string / not a valid datetime" -> 400
#   - Counter-check precedence (1..10) and Accept-check precedence (1..7): all
#     validation precedes any mutation, so a 4xx leaves state unchanged.
#   - Req #7: an offer whose expiration is AT or before the clock is EXPIRED.
#   - Counter value rule: seller's counter strictly greater; buyer's strictly less.
# Type-coercion-ambiguous inputs (e.g. "100", date-only strings) are deliberately
# avoided so a defensible-but-different implementation is not unfairly failed.
# ============================================================================

# ---------- parametrized field validation: POST /users ----------
@pytest.mark.parametrize("mutate", [
    {"name": None},          # required
    {"name": ""},            # non-empty
    {"email": None},         # required
    {"email": ""},           # non-empty
    {"budget": None},        # required
    {"budget": 0},           # positive
    {"budget": -5},          # positive
])
def test_user_invalid_field_400(mutate):
    body = {"name": "U", "email": email(), "budget": BIG_BUDGET}
    body.update(mutate)
    assert requests.post(f"{BASE}/users", json=body).status_code == 400


# ---------- parametrized field validation: POST /listings ----------
@pytest.mark.parametrize("mutate", [
    {"address": None},                # required
    {"address": ""},                  # non-empty
    {"price": None},                  # required
    {"price": 0},                     # positive (> 0)
    {"price": -5},                    # positive
    {"seller_id": None},              # required
    {"seller_id": "nonexistent-id"},  # must reference an existing user
])
def test_listing_invalid_field_400(mutate):
    s = mk_user()
    body = {"seller_id": s, "address": "1 Main St", "price": 500000}
    body.update(mutate)
    assert requests.post(f"{BASE}/listings", json=body).status_code == 400


# ---------- parametrized field validation: POST /offers ----------
@pytest.mark.parametrize("mutate", [
    {"listing_id": None},             # required
    {"buyer_id": None},               # required
    {"offer_value": None},            # required
    {"offer_value": 0},               # positive
    {"offer_value": -5},              # positive
    {"expiration": None},             # required
    {"expiration": "not-a-date"},     # Req #8: not a valid datetime
    {"expiration": 12345},            # Req #8: not a string
])
def test_offer_invalid_field_400(mutate):
    set_clock(T0); _, lid = available(); b = mk_user()
    body = {"listing_id": lid, "buyer_id": b, "offer_value": 400000, "expiration": FUTURE}
    body.update(mutate)
    assert requests.post(f"{BASE}/offers", json=body).status_code == 400


# ---------- POST /offers contingent_on is TWO-valued (omit == null == none) ----------
def test_create_contingent_null_equals_omitted():
    set_clock(T0); _, lid1 = available(); _, lid2 = available()
    b1 = mk_user(); b2 = mk_user()
    r1 = requests.post(f"{BASE}/offers", json={
        "listing_id": lid1, "buyer_id": b1, "offer_value": 400000,
        "expiration": FUTURE, "contingent_on": None})
    assert r1.status_code == 201 and r1.json()["contingent_on"] is None
    r2 = requests.post(f"{BASE}/offers", json={
        "listing_id": lid2, "buyer_id": b2, "offer_value": 400000,
        "expiration": FUTURE})
    assert r2.status_code == 201 and r2.json()["contingent_on"] is None


# ---------- directional counter value rule (strict; equality is a 409) ----------
@pytest.mark.parametrize("counter_val, expected", [
    (450000, 201),   # seller higher than buyer's 400k
    (600000, 201),   # higher
    (400000, 409),   # equal -> not strictly greater
    (399999, 409),   # lower
])
def test_seller_counter_direction(counter_val, expected):
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, value=400000).json()["offer_id"]
    assert counter_raw(o, s, value=counter_val).status_code == expected

@pytest.mark.parametrize("counter_val, expected", [
    (449999, 201),   # buyer lower than seller's 450k
    (400000, 201),   # lower
    (450000, 409),   # equal -> not strictly less
    (460000, 409),   # higher
])
def test_buyer_counter_direction(counter_val, expected):
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, value=400000).json()["offer_id"]
    n = counter_raw(o, s, value=450000).json()["offer_id"]   # seller offer 450k, listing PENDING
    assert counter_raw(n, b, value=counter_val).status_code == expected


# ---------- terminal-state guards: accept/reject/counter require PENDING ----------
def _mk_terminal(state):
    """Return (seller, listing, buyer, offer_id) for a BUYER offer driven to `state`."""
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, value=400000, expiration=FUTURE).json()["offer_id"]
    if state == "EXPIRED":
        set_clock(LATER)
    elif state == "REJECTED":
        assert reject(o, s).status_code == 200
    elif state == "ACCEPTED":
        assert accept(o, s).status_code == 200
    return s, lid, b, o

@pytest.mark.parametrize("state", ["EXPIRED", "REJECTED", "ACCEPTED"])
@pytest.mark.parametrize("action", ["accept", "reject", "counter"])
def test_action_on_terminal_offer_409(action, state):
    s, lid, b, o = _mk_terminal(state)
    if action == "accept":
        r = accept(o, s)
    elif action == "reject":
        r = reject(o, s)
    else:
        r = counter_raw(o, s, value=450000, expiration=EVEN_LATER)
    assert r.status_code == 409


# ---------- expiry boundary (Req #7: at-or-before the clock is EXPIRED) ----------
@pytest.mark.parametrize("clock_ts, expected", [
    ("2030-05-31T23:59:59Z", "PENDING"),    # one second before expiration
    ("2030-06-01T00:00:00Z", "EXPIRED"),    # exactly at expiration -> EXPIRED
    ("2030-06-01T00:00:01Z", "EXPIRED"),    # one second after expiration
])
def test_expiry_boundary(clock_ts, expected):
    set_clock(T0); _, lid = available(); b = mk_user()
    o = mk_offer(lid, b, expiration=FUTURE).json()["offer_id"]   # FUTURE = 2030-06-01T00:00:00Z
    set_clock(clock_ts)
    assert offer_status(o) == expected


# ---------- no-mutation-on-rejection re-reads (precedence pins mutation last) ----------
def test_counter_wrong_party_409_no_mutation():
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, value=400000).json()["offer_id"]
    assert counter_raw(o, b, value=450000).status_code == 409   # awaited party is the seller
    assert offer_status(o) == "PENDING"
    assert listing_status(lid) == "AVAILABLE"

def test_counter_direction_violation_409_no_mutation():
    set_clock(T0); s, lid = available(); b = mk_user()
    o = mk_offer(lid, b, value=400000).json()["offer_id"]
    assert counter_raw(o, s, value=390000).status_code == 409   # seller counter not greater
    assert offer_status(o) == "PENDING"
    assert listing_status(lid) == "AVAILABLE"

def test_counter_budget_exceed_409_no_mutation():
    set_clock(T0); s1, l1 = available(); _, l2 = available()
    b = mk_user(budget=100000)
    mk_offer(l2, b, value=30000)                                  # committed 30k elsewhere
    o1 = mk_offer(l1, b, value=20000).json()["offer_id"]
    n = counter_raw(o1, s1, value=90000).json()["offer_id"]       # seller offer 90k, listing PENDING
    assert counter_raw(n, b, value=80000).status_code == 409      # 30k + 80k = 110k > 100k
    assert offer_status(n) == "PENDING"                           # seller offer untouched
    assert listing_status(l1) == "PENDING"                        # still locked

def test_accept_contingency_unmet_409_no_mutation():
    set_clock(T0); sA, lA = available(); _, dep = available(); b = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    assert accept(o, sA).status_code == 409                       # dep not SOLD
    assert offer_status(o) == "PENDING"
    assert listing_status(lA) == "AVAILABLE"

def test_offer_budget_exceed_409_no_listing_mutation():
    set_clock(T0); _, lX = available()
    b = mk_user(budget=100000)
    assert mk_offer(lX, b, value=150000).status_code == 409       # over base budget
    assert listing_status(lX) == "AVAILABLE"                      # listing unchanged
    assert mk_offer(lX, b, value=90000).status_code == 201        # nothing was committed -> within budget


# ---------- expanded Lever F / contingency matrix ----------
def test_counter_inherit_then_accept_blocked_until_sold():
    """A seller counter inherits the buyer's contingency; accept is blocked until it sells."""
    set_clock(T0); sX, lX = available(); sY, lY = available(); b = mk_user()
    o = mk_offer(lX, b, value=400000, contingent_on=lY).json()["offer_id"]
    n = counter_raw(o, sX, value=450000)                          # seller counter inherits lY
    assert n.status_code == 201 and n.json()["contingent_on"] == lY
    nid = n.json()["offer_id"]
    assert accept(nid, b).status_code == 409                      # lY not SOLD -> contingency unmet
    _sell(lY, sY, 100000)                                         # lY now SOLD
    assert accept(nid, b).status_code == 200
    assert listing_status(lX) == "SOLD"

def test_counter_repoint_to_sold_listing_then_accept_ok():
    """Re-pointing a contingency to an already-SOLD listing satisfies R3 immediately."""
    set_clock(T0); sX, lX = available(); sZ, lZ = available(); b = mk_user()
    _sell(lZ, sZ, 100000)                                         # lZ SOLD first
    o = mk_offer(lX, b, value=400000).json()["offer_id"]
    n = counter_raw(o, sX, value=450000, contingent_on=lZ)        # re-point to SOLD lZ
    assert n.status_code == 201 and n.json()["contingent_on"] == lZ
    assert accept(n.json()["offer_id"], b).status_code == 200     # lZ already SOLD -> allowed

def test_inherited_contingency_survives_2step_chain_then_archive_cascades():
    """Contingency carried through two counters still forms a live edge; archiving the
    depended-on listing cascade-rejects the surviving offer (R4)."""
    set_clock(T0); sX, lX = available(); sY, lY = available()
    B = mk_user(budget=100000)
    o = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]   # contingent (not checked)
    n1 = counter_raw(o, sX, value=520000).json()["offer_id"]      # seller inherits lY
    n2 = counter_raw(n1, B, value=510000)                         # buyer counters back, inherits lY
    assert n2.status_code == 201 and n2.json()["contingent_on"] == lY
    n2id = n2.json()["offer_id"]
    assert requests.post(f"{BASE}/listings/{lY}/archive").status_code == 200
    assert offer_status(n2id) == "REJECTED"                       # R4 cascade reached the inherited edge

def test_counter_back_repoint_contingency_skips_budget_check():
    """A buyer counter that re-points (stays contingent) is NOT budget-checked at counter time."""
    set_clock(T0); sX, lX = available(); _, lZ = available()
    B = mk_user(budget=100000)
    o = mk_offer(lX, B, value=50000).json()["offer_id"]           # within base budget
    n1 = counter_raw(o, sX, value=520000).json()["offer_id"]      # seller offer 520k
    r = counter_raw(n1, B, value=510000, contingent_on=lZ)        # buyer counter-back, re-point -> contingent
    assert r.status_code == 201                                   # 510k >> 100k base, but contingent
    assert r.json()["contingent_on"] == lZ and r.json()["made_by"] == "BUYER"

def test_cycle_four_node_transitive_409():
    set_clock(); _, lA = available(); _, lB = available(); _, lC = available(); _, lD = available()
    assert mk_offer(lA, mk_user(), contingent_on=lB).status_code == 201   # A -> B
    assert mk_offer(lB, mk_user(), contingent_on=lC).status_code == 201   # B -> C
    assert mk_offer(lC, mk_user(), contingent_on=lD).status_code == 201   # C -> D
    assert mk_offer(lD, mk_user(), contingent_on=lA).status_code == 409   # D -> A closes a 4-node cycle
