"""
04_python_core_advanced.py - PYTHON CORE: ADVANCED
Syllabus: 1 Type hints, Protocol, Generic, TypedDict | 2 dataclasses (frozen, slots, post_init)
3 Descriptors & __slots__ | 4 Metaclasses & __init_subclass__ | 5 Dunder magic (__getattr__, __call__)
6 Design patterns | 7 Concurrency: threading, multiprocessing, asyncio | 8 Memory & GC, weakref
9 Profiling & optimisation | 10 NumPy vectorisation | 11 sqlite3 / DB-API | 12 Testing (unittest, mock)
13 Packaging, venv, config & secrets | 14 Functional tools | 15 Pythonic best practices
Run: python 04_python_core_advanced.py
"""
import sys, time, gc, weakref, asyncio, sqlite3, unittest, os, threading, io, cProfile, pstats, timeit
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
def h(t): print(f"\n{'='*8} {t} {'='*8}")

# --------------------------------------------------------------- module-level (needed by multiprocessing)
def cpu_task(n): return sum(i * i for i in range(n))

def main():
    h("1. Type hints, Protocol, Generic, TypedDict")
    from typing import Protocol, TypeVar, Generic, TypedDict, Optional, Callable, Iterable, Literal, overload
    T = TypeVar("T")
    class Scorer(Protocol):
        def score(self, x: float) -> float: ...
    class Linear:
        def score(self, x: float) -> float: return 2 * x
    def apply(s: Scorer, xs: Iterable[float]) -> list[float]: return [s.score(x) for x in xs]
    class Box(Generic[T]):
        def __init__(self, v: T) -> None: self.v = v
        def get(self) -> T: return self.v
    class Row(TypedDict): id: int; name: str
    def seg(x: float) -> Literal["hi", "lo"]: return "hi" if x > 5 else "lo"
    r: Row = {"id": 1, "name": "a"}
    print(apply(Linear(), [1, 2]), Box(5).get(), r, seg(9), apply.__annotations__["xs"])   # checked by mypy, not runtime

    h("2. dataclasses")
    from dataclasses import dataclass, field, asdict, replace
    @dataclass(frozen=True, order=True, slots=True)
    class Order:
        order_id: int
        amount: float = 0.0
        tags: tuple = ()
    @dataclass
    class Cust:
        cid: int
        orders: list = field(default_factory=list)
        total: float = field(init=False, default=0.0)
        def __post_init__(self): self.total = sum(self.orders)
    o = Order(1, 50.0); print(o, replace(o, amount=60), asdict(o), o < Order(2), Cust(1, [1, 2]).total)
    try: o.amount = 1
    except Exception as e: print("frozen:", type(e).__name__)

    h("3. Descriptors, properties & __slots__")
    class Positive:
        def __set_name__(self, owner, name): self.n = "_" + name
        def __get__(self, obj, typ=None): return getattr(obj, self.n)
        def __set__(self, obj, v):
            if v <= 0: raise ValueError(f"{self.n[1:]} must be > 0")
            setattr(obj, self.n, v)
    class Line:
        qty = Positive(); price = Positive()
        __slots__ = ("_qty", "_price")                 # no __dict__ -> less memory
        def __init__(self, q, p): self.qty, self.price = q, p
    ln = Line(2, 9.5)
    try: ln.qty = -1
    except ValueError as e: print(e, "| has __dict__:", hasattr(ln, "__dict__"))

    h("4. Metaclasses & __init_subclass__")
    registry = {}
    class Plugin:
        def __init_subclass__(cls, key=None, **kw): super().__init_subclass__(**kw); registry[key or cls.__name__] = cls
    class CsvLoader(Plugin, key="csv"): pass
    class SqlLoader(Plugin): pass
    class Meta(type):
        def __new__(m, name, bases, ns):
            ns["created_by"] = "Meta"; return super().__new__(m, name, bases, ns)
    class Thing(metaclass=Meta): pass
    print(registry, Thing.created_by, type(Thing).__name__)

    h("5. Dunder magic")
    class Config:
        def __init__(self, **kw): self._d = kw
        def __getattr__(self, k):
            try: return self._d[k]
            except KeyError: raise AttributeError(k)
        def __call__(self, k, default=None): return self._d.get(k, default)
        def __iter__(self): return iter(self._d.items())
        def __enter__(self): return self
        def __exit__(self, *a): return False
    cfg = Config(host="db", port=3306); print(cfg.host, cfg("port"), cfg("x", "none"), dict(cfg))
    class Vec:
        def __init__(s, *c): s.c = c
        def __add__(s, o): return Vec(*(a + b for a, b in zip(s.c, o.c)))
        def __mul__(s, k): return Vec(*(a * k for a in s.c))
        __rmul__ = __mul__
        def __repr__(s): return f"Vec{s.c}"
    print(Vec(1, 2) + Vec(3, 4), 3 * Vec(1, 2))

    h("6. Design patterns")
    class Singleton:
        _inst = None
        def __new__(cls):
            if cls._inst is None: cls._inst = super().__new__(cls)
            return cls._inst
    print(Singleton() is Singleton())
    def make_model(kind):                                         # factory
        return {"ols": lambda: "OLS()", "gbr": lambda: "GBR()"}[kind]()
    strategies = {"mean": lambda xs: sum(xs) / len(xs), "max": max}   # strategy
    print(make_model("gbr"), {k: f([1, 2, 6]) for k, f in strategies.items()})
    class Observable:                                              # observer
        def __init__(s): s.subs = []
        def sub(s, f): s.subs.append(f)
        def emit(s, e): [f(e) for f in s.subs]
    ob = Observable(); ob.sub(lambda e: print("  got", e)); ob.emit("etl_done")

    h("7a. Concurrency: threads (I/O-bound)")
    def io_task(i): time.sleep(0.2); return i * 2
    t = time.perf_counter()
    with ThreadPoolExecutor(5) as ex: res = list(ex.map(io_task, range(5)))
    print(res, f"{time.perf_counter()-t:.2f}s (vs 1.0s sequential)")
    lock, shared = threading.Lock(), {"n": 0}
    def inc():
        for _ in range(10000):
            with lock: shared["n"] += 1
    ths = [threading.Thread(target=inc) for _ in range(4)]; [x.start() for x in ths]; [x.join() for x in ths]
    print("locked counter:", shared["n"])

    h("7b. Multiprocessing (CPU-bound, bypasses the GIL)")
    with ProcessPoolExecutor(2) as ex: print(list(ex.map(cpu_task, [10**5, 2 * 10**5])))

    h("7c. asyncio")
    async def fetch(n, d): await asyncio.sleep(d); return f"job{n}"
    async def run():
        t = time.perf_counter()
        out = await asyncio.gather(fetch(1, .2), fetch(2, .2), fetch(3, .2))
        try: await asyncio.wait_for(fetch(9, 1), timeout=.1)
        except asyncio.TimeoutError: out.append("timeout")
        return out, round(time.perf_counter() - t, 1)
    print(asyncio.run(run()))

    h("8. Memory, GC, weakref")
    print(sys.getsizeof([]), sys.getsizeof(list(range(1000))), sys.getrefcount(cfg) > 1)
    class Node: pass
    n1 = Node(); wr = weakref.ref(n1); del n1; print("weakref dead:", wr() is None)
    a = []; a.append(a); del a; print("collected cycles:", gc.collect() >= 1)
    import tracemalloc; tracemalloc.start(); big = [i for i in range(100000)]
    cur, peak = tracemalloc.get_traced_memory(); tracemalloc.stop(); print(f"tracemalloc peak {peak/1e6:.1f} MB")

    h("9. Profiling & optimisation")
    print("timeit loop :", round(timeit.timeit("sum([i for i in range(1000)])", number=2000), 3))
    print("timeit genex:", round(timeit.timeit("sum(i for i in range(1000))", number=2000), 3))
    pr = cProfile.Profile(); pr.enable(); cpu_task(300000); pr.disable()
    s = io.StringIO(); pstats.Stats(pr, stream=s).sort_stats("cumtime").print_stats(2); print(s.getvalue().strip().splitlines()[0])
    print("membership list vs set:", round(timeit.timeit("99999 in l", "l=list(range(100000))", number=200), 4),
          round(timeit.timeit("99999 in s", "s=set(range(100000))", number=200), 6))

    h("10. NumPy vectorisation")
    import numpy as np
    x = np.random.default_rng(0).random(1_000_000)
    t = time.perf_counter(); s1 = sum(v * 2 for v in x.tolist()); tl = time.perf_counter() - t
    t = time.perf_counter(); s2 = (x * 2).sum(); tv = time.perf_counter() - t
    print(f"loop {tl:.3f}s vs vectorised {tv:.4f}s -> {tl/tv:.0f}x faster")
    M = np.arange(12).reshape(3, 4); print(M.T.shape, M.sum(axis=0), M[M > 5], (M + np.array([1, 0, 0, 1])).shape)

    h("11. sqlite3 / DB-API (same pattern as pymysql / SQLAlchemy)")
    con = sqlite3.connect(":memory:"); cur = con.cursor()
    cur.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, amt REAL)")
    cur.executemany("INSERT INTO t(amt) VALUES (?)", [(10,), (25.5,), (7,)])    # parameterised -> no SQL injection
    con.commit(); print(cur.execute("SELECT COUNT(*), SUM(amt) FROM t WHERE amt > ?", (8,)).fetchone())
    import pandas as pd; print(pd.read_sql("SELECT * FROM t", con).shape); con.close()

    h("13. Config & secrets")
    os.environ["MYSQL_URL"] = "mysql+pymysql://u:p@localhost/clv_db"
    print(os.getenv("MYSQL_URL", "").split("@")[-1], os.getenv("MISSING", "default"))
    # venv: python -m venv .venv ; pip freeze > requirements.txt ; never hard-code passwords (use env/.env/secrets manager)

    h("14. Functional toolkit")
    import functools as ft, operator
    from itertools import starmap
    pipeline = ft.reduce(lambda f, g: lambda x: g(f(x)), [lambda v: v + 1, lambda v: v * 2, str])
    print(pipeline(3), list(starmap(pow, [(2, 3), (3, 2)])), ft.partial(int, base=2)("101"))
    @ft.singledispatch
    def show(x): return f"obj {x}"
    @show.register(int)
    def _(x): return f"int {x}"
    print(show(1), show("s"))

    h("15. Pythonic best practices")
    d = {"a": 1}; print(d.get("b", 0), [*range(3), *"ab"], {**d, "z": 9}, any(v > 0 for v in d.values()))
    from pathlib import Path; print(Path("a") / "b" / "c.csv")
    print(f"{'EAFP':<6}| try/except beats pre-checks;", "PEP8 | black | ruff | mypy | pytest")

# --------------------------------------------------------------- 12. Testing (module level so unittest can discover)
def clv(aov, freq, margin=0.3): return aov * freq * margin
class TestCLV(unittest.TestCase):
    def setUp(self): self.base = clv(100, 4)
    def test_basic(self): self.assertAlmostEqual(self.base, 120.0)
    def test_zero(self): self.assertEqual(clv(0, 5), 0)
    def test_raises(self):
        with self.assertRaises(TypeError): clv("a", None)
    def test_mock(self):
        from unittest.mock import patch, MagicMock
        with patch("time.time", return_value=5): self.assertEqual(time.time(), 5)
        m = MagicMock(return_value=3); self.assertEqual(m(1), 3); m.assert_called_once_with(1)

if __name__ == "__main__":
    main()
    h("12. Testing (unittest; pytest style: plain `assert` + fixtures + parametrize)")
    r = unittest.TextTestRunner(verbosity=0, stream=sys.stdout).run(unittest.defaultTestLoader.loadTestsFromTestCase(TestCLV))
    print("tests passed:", r.wasSuccessful())
