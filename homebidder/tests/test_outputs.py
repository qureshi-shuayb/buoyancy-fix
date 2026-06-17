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

def test_accept_contingent_commits_chained():
    """Accepting a contingent offer before its dependency is SOLD commits it 'subject to sale'."""
    set_clock(); sA, lA = available(); _, dep = available(); b = mk_user()
    o = mk_offer(lA, b, contingent_on=dep).json()["offer_id"]
    assert accept(o, sA).status_code == 200    # commits (was 409): dep not SOLD -> chained
    assert listing_status(lA) == "CHAINED"
    assert offer_status(o) == "PENDING"        # publicly still PENDING while chained

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
    """Selling your own listing funds settlement of a chained offer that exceeds base budget."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 200            # commit subject to sale; Y not SOLD yet
    assert listing_status(lX) == "CHAINED"
    assert offer_status(oX) == "PENDING"
    _sell(lY, B, 450000)                                # B realizes 450k proceeds -> auto-settles oX
    assert offer_status(oX) == "ACCEPTED"               # 500k <= 100k + 450k effective budget
    assert listing_status(lX) == "SOLD"

def test_self_finance_insufficient_proceeds_rejects():
    """If realized proceeds are too low, the chained offer is rejected at settlement and the listing reverts."""
    set_clock(T0); sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 200            # commit subject to sale; lX -> CHAINED
    assert listing_status(lX) == "CHAINED"
    _sell(lY, B, 350000)                                # only 350k proceeds -> 500k > 100k + 350k
    assert offer_status(oX) == "REJECTED"               # insufficient funds at settlement
    assert listing_status(lX) == "AVAILABLE"            # reverts

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

def test_accept_chained_rejects_when_other_commitment_exceeds_budget():
    """A chained offer that, with the buyer's other PENDING commitments, exceeds the effective budget is rejected at settlement."""
    set_clock(T0)
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    _sell(lY, B, 300000)                               # effective budget 400k
    sX, lX = available()
    assert mk_offer(lX, B, value=300000).status_code == 201    # non-contingent, commits 300k
    sZ, lZ = available()
    oZ = mk_offer(lZ, B, value=200000, contingent_on=lY).json()["offer_id"]  # lY already SOLD; relaxed at creation
    assert accept(oZ, sZ).status_code == 200           # commit; settle then rejects
    assert offer_status(oZ) == "REJECTED"              # committed 300k + 200k = 500k > 400k
    assert listing_status(lZ) == "AVAILABLE"           # reverts


# ---------- property chains & auto-settlement (CHAINED + settle() fixpoint) ----------
def test_accept_commit_cascade_rejects_others():
    """Committing a contingent offer locks the listing CHAINED and cascade-rejects other PENDING offers."""
    set_clock(T0)
    sX, lX = available(); _, dep = available()
    b1, b2 = mk_user(), mk_user()
    oX = mk_offer(lX, b1, contingent_on=dep).json()["offer_id"]
    o2 = mk_offer(lX, b2).json()["offer_id"]
    assert accept(oX, sX).status_code == 200
    assert listing_status(lX) == "CHAINED"
    assert offer_status(oX) == "PENDING"     # committed, awaiting dependency
    assert offer_status(o2) == "REJECTED"    # cascade

def test_three_deep_chain_auto_settles():
    """One accept at the bottom of a 3-deep chain settles every hop to a fixpoint."""
    set_clock(T0)
    sX, lX = available(); sY, lY = available(); sZ, lZ = available()
    bX, bY, bZ = mk_user(), mk_user(), mk_user()
    oX = mk_offer(lX, bX, value=400000, contingent_on=lY).json()["offer_id"]  # lX depends on lY
    oY = mk_offer(lY, bY, value=400000, contingent_on=lZ).json()["offer_id"]  # lY depends on lZ
    oZ = mk_offer(lZ, bZ, value=400000).json()["offer_id"]                     # bottom, non-contingent
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    assert accept(oY, sY).status_code == 200 and listing_status(lY) == "CHAINED"
    assert accept(oZ, sZ).status_code == 200            # triggers the full cascade
    for oid in (oX, oY, oZ):
        assert offer_status(oid) == "ACCEPTED"
    for lid in (lX, lY, lZ):
        assert listing_status(lid) == "SOLD"

def test_same_buyer_contention_ordered_settle_then_reject():
    """Two chained offers by one buyer, jointly over budget: in-order settle first, reject the loser, revert its listing."""
    sA0 = "2030-01-01T00:00:00Z"; sA1 = "2030-01-02T00:00:00Z"
    set_clock(sA0)
    s1, l1 = available(); s2, l2 = available(); sD, dep = available()
    B = mk_user(budget=600000)
    oA = mk_offer(l1, B, value=400000, contingent_on=dep).json()["offer_id"]   # created first (earlier created_at)
    set_clock(sA1)
    oB = mk_offer(l2, B, value=400000, contingent_on=dep).json()["offer_id"]   # created later
    assert accept(oA, s1).status_code == 200 and listing_status(l1) == "CHAINED"
    assert accept(oB, s2).status_code == 200 and listing_status(l2) == "CHAINED"
    _sell(dep, sD, 500000)                               # dep SOLD -> both become settleable in one sweep
    assert offer_status(oA) == "ACCEPTED"               # earlier created_at settles first (400k <= 600k)
    assert listing_status(l1) == "SOLD"
    assert offer_status(oB) == "REJECTED"               # remaining budget 200k < 400k -> insufficient
    assert listing_status(l2) == "AVAILABLE"            # reverts

def test_mid_chain_expiry_reverts_and_stops_downstream():
    """A chained offer expiring mid-chain becomes EXPIRED, reverts its listing, and stops downstream settlement."""
    set_clock(T0)
    sTop, lTop = available(); sMid, lMid = available(); _, lBot = available()
    bTop, bMid = mk_user(), mk_user()
    oTop = mk_offer(lTop, bTop, value=400000, expiration=EVEN_LATER, contingent_on=lMid).json()["offer_id"]
    oMid = mk_offer(lMid, bMid, value=400000, expiration=FUTURE, contingent_on=lBot).json()["offer_id"]
    assert accept(oMid, sMid).status_code == 200 and listing_status(lMid) == "CHAINED"
    assert accept(oTop, sTop).status_code == 200 and listing_status(lTop) == "CHAINED"
    set_clock(LATER)                                     # oMid expires (past FUTURE); oTop survives (EVEN_LATER)
    assert offer_status(oMid) == "EXPIRED"
    assert listing_status(lMid) == "AVAILABLE"          # reverts
    assert offer_status(oTop) == "PENDING"              # still committed
    assert listing_status(lTop) == "CHAINED"            # downstream stuck; its dependency can no longer sell via oMid

def test_dependency_archived_reverts_and_rejects_chained():
    """Archiving a dependency rejects every committed chained offer on it and reverts those listings."""
    set_clock(T0)
    sX, lX = available(); sY, lY = available(); _, lD = available()
    bX, bY = mk_user(), mk_user()
    oX = mk_offer(lX, bX, value=400000, contingent_on=lD).json()["offer_id"]
    oY = mk_offer(lY, bY, value=400000, contingent_on=lD).json()["offer_id"]
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    assert accept(oY, sY).status_code == 200 and listing_status(lY) == "CHAINED"
    assert requests.post(f"{BASE}/listings/{lD}/archive").status_code == 200
    assert offer_status(oX) == "REJECTED" and offer_status(oY) == "REJECTED"
    assert listing_status(lX) == "AVAILABLE" and listing_status(lY) == "AVAILABLE"


# ---------- preemptive offers / gazumping (CHAINED backup bids + auto-preemption) ----------
def _chain_listing(value=400000):
    """Make `lX` CHAINED via a contingent offer (depending on a never-sold `dep`). Returns (sX, lX, dep, bChain, oChain)."""
    sX, lX = available(); _, dep = available()
    bChain = mk_user()
    oChain = mk_offer(lX, bChain, value=value, contingent_on=dep).json()["offer_id"]
    assert accept(oChain, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    return sX, lX, dep, bChain, oChain

def test_backup_bid_on_chained_allowed_when_higher():
    """A non-contingent offer strictly above the committed value is accepted on a CHAINED listing."""
    set_clock(T0)
    sX, lX, dep, bChain, oChain = _chain_listing(value=400000)
    bBk = mk_user()
    r = mk_offer(lX, bBk, value=450000)
    assert r.status_code == 201
    assert r.json()["status"] == "PENDING"
    assert listing_status(lX) == "CHAINED"        # listing stays chained; this is just a backup
    assert offer_status(oChain) == "PENDING"      # committed offer untouched

def test_backup_must_exceed_committed_409():
    """A backup bid that does not strictly exceed the committed value, or any contingent bid, is rejected on CHAINED."""
    set_clock(T0)
    sX, lX, dep, bChain, oChain = _chain_listing(value=400000)
    assert mk_offer(lX, mk_user(), value=400000).status_code == 409   # equal -> not strictly greater
    assert mk_offer(lX, mk_user(), value=399999).status_code == 409   # below
    assert mk_offer(lX, mk_user(), value=500000, contingent_on=dep).status_code == 409  # contingent-on-CHAINED stays 409

def test_manual_gazump_via_accept():
    """Seller accepts a higher non-contingent backup on a CHAINED listing: the chained buyer is gazumped."""
    set_clock(T0)
    sX, lX, dep, bChain, oChain = _chain_listing(value=400000)
    bBk = mk_user()
    oBk = mk_offer(lX, bBk, value=450000).json()["offer_id"]
    assert accept(oBk, sX).status_code == 200
    assert offer_status(oBk) == "ACCEPTED"
    assert offer_status(oChain) == "REJECTED"     # gazumped
    assert listing_status(lX) == "SOLD"

def test_reentrant_gazump_settles_dependent_chain():
    """Gazumping a CHAINED listing X sells it, which in the same sweep settles a chain that depended on X."""
    set_clock(T0)
    sX, lX = available(); sW, lW = available(); _, dep = available()
    bX, bW, bGz = mk_user(), mk_user(), mk_user()
    oX = mk_offer(lX, bX, value=400000, contingent_on=dep).json()["offer_id"]   # X depends on dep (never sells)
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    oW = mk_offer(lW, bW, value=400000, contingent_on=lX).json()["offer_id"]    # W depends on X
    assert accept(oW, sW).status_code == 200 and listing_status(lW) == "CHAINED"
    oGz = mk_offer(lX, bGz, value=450000).json()["offer_id"]                    # higher backup on X
    assert accept(oGz, sX).status_code == 200                                    # gazump: X SOLD, oX REJECTED
    assert offer_status(oGz) == "ACCEPTED" and offer_status(oX) == "REJECTED"
    assert listing_status(lX) == "SOLD"
    assert offer_status(oW) == "ACCEPTED"          # re-entrant: now that X is SOLD, W's chain settles
    assert listing_status(lW) == "SOLD"

def test_auto_preemption_prefers_backup_over_revert():
    """A chained offer goes unaffordable at settlement while an affordable backup exists: the backup settles instead of reverting."""
    set_clock(T0)
    sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)               # B owns Y; will fund X via proceeds
    bBk = mk_user(budget=BIG_BUDGET)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    oBk = mk_offer(lX, bBk, value=510000).json()["offer_id"]   # higher backup, affordable
    assert offer_status(oBk) == "PENDING"
    _sell(lY, B, 350000)                          # B effective 450000 < 500000 -> oX unaffordable
    assert offer_status(oX) == "REJECTED"         # unaffordable chained offer rejected
    assert offer_status(oBk) == "ACCEPTED"        # affordable backup preempts the revert
    assert listing_status(lX) == "SOLD"           # listing does NOT revert to AVAILABLE

def test_affordable_chained_wins_over_backup():
    """When the chained offer is affordable at settlement, it settles and the backup is cascade-rejected (no auto-preemption)."""
    set_clock(T0)
    sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    bBk = mk_user(budget=BIG_BUDGET)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    oBk = mk_offer(lX, bBk, value=510000).json()["offer_id"]
    _sell(lY, B, 450000)                          # B effective 550000 >= 500000 -> oX affordable
    assert offer_status(oX) == "ACCEPTED"         # chained buyer keeps the deal
    assert offer_status(oBk) == "REJECTED"        # backup cascade-rejected; no gazump
    assert listing_status(lX) == "SOLD"

def test_no_affordable_backup_reverts():
    """If the only backup is itself unaffordable when the chained offer fails, the listing reverts to AVAILABLE."""
    set_clock(T0)
    sX, lX = available()
    B = mk_user(budget=100000)
    lY = mk_listing(B); publish(lY)
    oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
    assert accept(oX, sX).status_code == 200 and listing_status(lX) == "CHAINED"
    # Backup buyer can post the backup at creation, but has already spent most of its budget.
    bBk = mk_user(budget=600000)
    sZ, lZ = available()
    oZ = mk_offer(lZ, bBk, value=200000).json()["offer_id"]
    assert accept(oZ, sZ).status_code == 200       # bBk now has 200000 spent (completed purchase)
    oBk = mk_offer(lX, bBk, value=510000).json()["offer_id"]   # created: creation ignores already-spent money
    _sell(lY, B, 350000)                           # oX unaffordable; backup also unaffordable (510k > 600k-200k)
    assert offer_status(oX) == "REJECTED"
    assert offer_status(oBk) == "PENDING"          # backup not settleable -> stays pending
    assert listing_status(lX) == "AVAILABLE"       # reverts, as before

def test_preemption_deterministic():
    """The auto-preemption corner resolves identically across repeated runs."""
    for _ in range(3):
        set_clock(T0)
        sX, lX = available()
        B = mk_user(budget=100000)
        lY = mk_listing(B); publish(lY)
        bBk = mk_user(budget=BIG_BUDGET)
        oX = mk_offer(lX, B, value=500000, contingent_on=lY).json()["offer_id"]
        assert accept(oX, sX).status_code == 200
        oBk = mk_offer(lX, bBk, value=510000).json()["offer_id"]
        _sell(lY, B, 350000)
        assert offer_status(oX) == "REJECTED"
        assert offer_status(oBk) == "ACCEPTED"
        assert listing_status(lX) == "SOLD"

def test_seller_cannot_act_on_committed_chained_offer_409():
    """The committed (chained) offer itself stays settle()-only: the seller may not accept/reject/counter it directly."""
    set_clock(T0)
    sX, lX, dep, bChain, oChain = _chain_listing(value=400000)
    assert accept(oChain, sX).status_code == 409
    assert reject(oChain, sX).status_code == 409
    assert counter(oChain, sX, value=450000).status_code == 409
