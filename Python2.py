"""
03_python_core_intermediate.py - PYTHON CORE: INTERMEDIATE
Syllabus: 1 OOP (class, inheritance, polymorphism, encapsulation, properties, dunder, abstract)
2 Exceptions | 3 Modules & packages | 4 File handling (txt/csv/json/pathlib) | 5 Regex | 6 datetime
7 collections | 8 itertools & functools | 9 Iterators & generators | 10 Closures & decorators
11 Context managers | 12 Logging | 13 argparse | 14 Enum | 15 Copying | 16 Sorting & searching
Run: python 03_python_core_intermediate.py
"""
import csv, json, re, copy, bisect, logging, argparse, tempfile, os
from pathlib import Path
def h(t): print(f"\n{'='*8} {t} {'='*8}")

h("1. OOP")
from abc import ABC, abstractmethod
class Customer:
    count = 0                                        # class attribute
    def __init__(self, cid, name, orders=None):
        self.cid, self.name = cid, name              # instance attributes
        self._orders = list(orders or [])            # _protected, __private = name-mangled
        self.__secret = "x"; Customer.count += 1
    @property
    def total(self): return sum(self._orders)        # computed attribute
    @total.setter
    def total(self, v): raise AttributeError("read-only")
    def add_order(self, amt):
        if amt <= 0: raise ValueError("amount must be positive")
        self._orders.append(amt); return self
    @classmethod
    def from_string(cls, s): cid, nm = s.split(","); return cls(int(cid), nm)
    @staticmethod
    def is_valid_id(cid): return isinstance(cid, int) and cid > 0
    def __repr__(self): return f"Customer({self.cid!r}, {self.name!r})"
    def __str__(self): return f"{self.name} (${self.total:,.2f})"
    def __len__(self): return len(self._orders)
    def __eq__(self, o): return isinstance(o, Customer) and self.cid == o.cid
    def __hash__(self): return hash(self.cid)
    def __lt__(self, o): return self.total < o.total
    def __add__(self, o): return self.total + o.total
    def __getitem__(self, i): return self._orders[i]
    def __contains__(self, amt): return amt in self._orders
c = Customer(1, "Asha").add_order(50).add_order(70)
c2 = Customer.from_string("2,Ravi")
print(c, repr(c), len(c), c[0], 50 in c, c == c2, c + c2, Customer.count, Customer.is_valid_id(5))
print(sorted([c, c2]), c._Customer__secret)         # name mangling

class PremiumCustomer(Customer):                     # inheritance
    def __init__(self, cid, name, orders=None, discount=0.1):
        super().__init__(cid, name, orders); self.discount = discount
    def __str__(self): return f"[VIP] {super().__str__()} disc={self.discount:.0%}"
print(PremiumCustomer(3, "Zed", [100]), isinstance(PremiumCustomer(4, "Q"), Customer), PremiumCustomer.__mro__[1].__name__)

class Model(ABC):                                    # abstract base class
    @abstractmethod
    def predict(self, x): ...
class Doubler(Model):
    def predict(self, x): return 2 * x
class Squarer(Model):
    def predict(self, x): return x * x
for m in (Doubler(), Squarer()): print(type(m).__name__, m.predict(4))   # polymorphism
try: Model()
except TypeError as e: print("abstract:", e)

class Multi(Doubler, Squarer): pass                  # multiple inheritance / MRO
print([k.__name__ for k in Multi.__mro__])

h("2. Exceptions")
class DataQualityError(Exception):
    def __init__(self, msg, rows=0): super().__init__(msg); self.rows = rows
def risky(v):
    try:
        if v == "bad": raise DataQualityError("bad rows", rows=3)
        return 10 / int(v)
    except ZeroDivisionError: return "div0"
    except (ValueError, TypeError) as e: return f"conv:{type(e).__name__}"
    except DataQualityError as e: return f"dq:{e.rows}"
    else: return "ok-else"                           # runs when no exception (not reached after return)
    finally: print("  cleanup for", repr(v))
print([risky(v) for v in ("2", "0", "x", "bad")])
try:
    try: int("x")
    except ValueError as e: raise RuntimeError("wrapped") from e   # exception chaining
except RuntimeError as e: print(repr(e), "| cause:", repr(e.__cause__))
assert 1 + 1 == 2, "math broke"

h("3. Modules & packages")
import math, random, statistics, os.path as osp
from collections import Counter as Cnt
print(math.sqrt(16), math.ceil(2.1), math.log10(1000), statistics.mean([1, 2, 3]), statistics.median([1, 9, 5]),
      statistics.stdev([2, 4, 4, 4, 5, 5, 7, 9]), osp.basename("/a/b/c.csv"), __name__)
random.seed(1); print(random.randint(1, 10), random.choice("abc"), random.sample(range(10), 3))
# packages: folder + __init__.py ; relative import `from .utils import f` ; `pip install pkg` ; sys.path

h("4. File handling")
tmp = Path(tempfile.mkdtemp())
(tmp / "n.txt").write_text("line1\nline2\n")
with open(tmp / "n.txt", "a") as f: f.write("line3\n")
with open(tmp / "n.txt") as f: print([ln.strip() for ln in f])              # iterate lazily
rows = [{"id": 1, "name": "A"}, {"id": 2, "name": "B"}]
with open(tmp / "d.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["id", "name"]); w.writeheader(); w.writerows(rows)
with open(tmp / "d.csv") as f: print(list(csv.DictReader(f)))
(tmp / "c.json").write_text(json.dumps({"cut": "2025-06-30", "k": [1, 2]}, indent=2))
print(json.loads((tmp / "c.json").read_text()), json.dumps({"a": 1}, sort_keys=True))
print(sorted(p.name for p in tmp.glob("*")), (tmp / "d.csv").stat().st_size, (tmp / "n.txt").suffix, tmp.exists())

h("5. Regular expressions")
text = "Order #A123 on 2025-06-30 by asha@mail.com; Order #B456 on 2025-07-01 by ravi@x.org"
print(re.findall(r"#([A-Z]\d+)", text), re.findall(r"\d{4}-\d{2}-\d{2}", text))
m = re.search(r"(?P<user>\w+)@(?P<dom>[\w.]+)", text); print(m.group("user"), m["dom"], m.span())
print(re.sub(r"\d", "#", "tel 98765"), re.split(r"[;,]\s*", "a; b,c"), bool(re.fullmatch(r"\d{5}", "12345")))
pat = re.compile(r"^\s*(\w+)\s*=\s*(.+?)\s*$", re.M); print(pat.findall("a = 1\nb= two "))

h("6. datetime")
from datetime import datetime, date, timedelta, timezone
d0 = datetime(2025, 6, 30, 14, 30)
print(d0.strftime("%d %b %Y %H:%M"), datetime.strptime("2025-12-31", "%Y-%m-%d").date(),
      d0 + timedelta(days=183), (date(2025, 12, 31) - date(2025, 6, 30)).days,
      d0.weekday(), d0.isocalendar()[1], d0.replace(tzinfo=timezone.utc).isoformat())

h("7. collections")
from collections import Counter, defaultdict, deque, OrderedDict, ChainMap
print(Counter("mississippi").most_common(2))
dd = defaultdict(list)
for k, v in [("a", 1), ("b", 2), ("a", 3)]: dd[k].append(v)
print(dict(dd))
dq = deque([1, 2, 3], maxlen=3); dq.appendleft(0); dq.append(9); print(dq, dq.popleft())
print(ChainMap({"a": 1}, {"a": 2, "b": 3})["b"])

h("8. itertools & functools")
import itertools as it, functools as ft, operator
print(list(it.islice(it.count(10, 5), 3)), list(it.chain([1], [2, 3])), list(it.product("ab", [1, 2])),
      list(it.permutations("abc", 2))[:3], list(it.combinations(range(4), 2))[:3],
      [(k, list(g)) for k, g in it.groupby("aabbbc")], list(it.accumulate([1, 2, 3, 4])))
print(ft.reduce(operator.mul, range(1, 6)), ft.partial(pow, 2)(10))
@ft.lru_cache(maxsize=None)
def fib(n): return n if n < 2 else fib(n - 1) + fib(n - 2)
print(fib(60), fib.cache_info().hits)

h("9. Iterators & generators")
class Countdown:
    def __init__(self, n): self.n = n
    def __iter__(self): return self
    def __next__(self):
        if self.n <= 0: raise StopIteration
        self.n -= 1; return self.n + 1
print(list(Countdown(3)))
def chunks(seq, n):
    for i in range(0, len(seq), n): yield seq[i:i + n]
def running_mean():
    total = count = 0
    while True:
        x = yield (total / count if count else None); total += x; count += 1
print(list(chunks(range(7), 3)))
rm = running_mean(); next(rm); print(rm.send(10), rm.send(20))
def flat(xs):
    for x in xs: yield from (flat(x) if isinstance(x, list) else [x])
print(list(flat([1, [2, [3, 4]], 5])))

h("10. Closures & decorators")
def make_counter():
    n = 0
    def inc(): nonlocal n; n += 1; return n
    return inc
cnt = make_counter(); cnt(); print("closure:", cnt())
import time
def timed(fn):
    @ft.wraps(fn)
    def w(*a, **k):
        t = time.perf_counter(); r = fn(*a, **k); print(f"  {fn.__name__}: {time.perf_counter()-t:.5f}s"); return r
    return w
def retry(times=3):                                  # decorator factory
    def deco(fn):
        @ft.wraps(fn)
        def w(*a, **k):
            for i in range(1, times + 1):
                try: return fn(*a, **k)
                except Exception as e: print(f"  attempt {i} failed: {e}")
            raise RuntimeError("all retries failed")
        return w
    return deco
calls = {"n": 0}
@retry(3)
@timed
def flaky():
    calls["n"] += 1
    if calls["n"] < 3: raise ConnectionError("db down")
    return "connected"
print(flaky())

h("11. Context managers")
from contextlib import contextmanager, suppress
@contextmanager
def stage(name):
    t = time.perf_counter(); print(f"  > {name}")
    try: yield
    finally: print(f"  < {name} {time.perf_counter()-t:.4f}s")
with stage("transform"): sum(range(10**5))
class Conn:
    def __enter__(self): print("  open"); return self
    def __exit__(self, et, ev, tb): print("  close", et.__name__ if et else ""); return True   # swallow error
with Conn(): raise ValueError
with suppress(FileNotFoundError): open("/no/file")

h("12. Logging")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s", datefmt="%H:%M:%S", force=True)
log = logging.getLogger("etl"); log.info("rows=%d", 100); log.warning("nulls found"); log.debug("hidden")

h("13. argparse (CLI)")
ap = argparse.ArgumentParser(description="CLV runner")
ap.add_argument("--cutoff", default="2025-06-30"); ap.add_argument("--horizon", type=int, default=183)
ap.add_argument("--dry-run", action="store_true"); ap.add_argument("files", nargs="*")
print(ap.parse_args(["--horizon", "90", "--dry-run", "a.csv"]))

h("14. Enum, 15. Copying, 16. Sorting & searching")
from enum import Enum, auto
class Seg(Enum):
    GOLD = auto(); SILVER = auto()
print(Seg.GOLD, Seg["SILVER"].value, [s.name for s in Seg])
orig = [[1, 2], [3]]; sh = copy.copy(orig); dp = copy.deepcopy(orig); orig[0].append(99)
print(sh, dp)
data = [("b", 2), ("a", 2), ("c", 1)]
print(sorted(data, key=lambda r: (r[1], r[0])), bisect.bisect_left([1, 3, 5, 7], 5), sorted("Bb aA", key=str.lower))
