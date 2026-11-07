"""
02_python_core_basics.py  -  PYTHON CORE: BASICS
Syllabus: 1 Syntax & comments | 2 Variables | 3 Data types | 4 Type conversion | 5 Operators
6 Input/Output | 7 Strings | 8 List | 9 Tuple | 10 Set | 11 Dict | 12 Conditionals
13 Loops | 14 Functions | 15 Scope (LEGB) | 16 Lambda | 17 Comprehensions | 18 match-case
Run: python 02_python_core_basics.py
"""
def h(t): print(f"\n{'='*8} {t} {'='*8}")

h("1. Syntax: indentation, comments, line continuation")
# single-line comment ; triple-quoted strings act as docstrings / multi-line text
total = (1 + 2 +
         3)                         # parentheses allow line continuation
print("total =", total)

h("2. Variables & naming")
customer_id = 101                   # snake_case for variables
CHURN_THRESHOLD_DAYS = 90           # UPPER_CASE for constants (by convention)
a = b = c = 0                       # chained assignment
x, y = 5, 10; x, y = y, x           # tuple unpacking / swap
first, *middle, last = [1, 2, 3, 4, 5]
print(x, y, first, middle, last, id(x) == id(10))

h("3. Data types")
for v in (42, 3.14, 2 + 3j, "text", True, None, [1], (1,), {1}, {"k": 1}, b"bytes", range(3)):
    print(f"{v!r:12} -> {type(v).__name__}")
print(isinstance(5, int), isinstance(True, int), 0.1 + 0.2 == 0.3)
from decimal import Decimal
print(Decimal("0.1") + Decimal("0.2") == Decimal("0.3"))   # exact money maths

h("4. Type conversion")
print(int("42"), float("3.5"), str(99), bool(""), bool("a"), list("abc"), tuple([1, 2]), set([1, 1, 2]))
print(int(3.99), round(3.567, 2), round(2.5), round(3.5), int("101", 2), bin(10), hex(255), oct(8))

h("5. Operators")
print(7 + 2, 7 - 2, 7 * 2, 7 / 2, 7 // 2, 7 % 2, 7 ** 2, -7 // 2)       # arithmetic
print(5 > 3, 5 == 5.0, 5 != 4, 1 < 2 < 3)                               # comparison (chained)
print(True and False, True or False, not True)                          # logical
print(5 & 3, 5 | 3, 5 ^ 3, ~5, 5 << 1, 5 >> 1)                          # bitwise
print(3 in [1, 2, 3], "z" not in "abc")                                 # membership
l1 = [1]; l2 = [1]; print(l1 == l2, l1 is l2)                           # identity vs equality
n = 10; n += 5; n *= 2; n //= 4; print(n)                               # augmented assignment
if (m := len("walrus")) > 3: print("walrus operator:", m)               # assignment expression

h("6. Input / Output")
name = "Asha"; amount = 1234.5678
print("a", "b", sep="-", end="!\n")
print(f"{name:>8} | {amount:,.2f} | {0.256:.1%} | {42:05d} | {255:#x}")
print("%s has %d orders" % (name, 3), "{} {}".format("fmt", 1))
# name = input("Enter name: ")      # interactive input (always returns str)

h("7. Strings")
s = "  Customer Lifetime Value  "
print(s.strip().lower(), s.upper().strip(), s.replace("Value", "Worth").strip())
t = s.strip()
print(t[0], t[-1], t[:8], t[::-1], t[2:10:2], len(t))
print(t.split(), "-".join(["a", "b"]), t.startswith("Cust"), t.find("Life"), t.count("e"))
print("abc123".isalnum(), "123".isdigit(), "ABC".isupper(), "title case".title(), "x".center(5, "*"))
print("a,b,,c".split(","), "line1\nline2".splitlines(), "tab\tsep", r"raw\n", "é".encode("utf-8"))

h("8. List (mutable, ordered)")
L = [5, 3, 8, 1]
L.append(9); L.insert(0, 7); L.extend([2, 2]); L.remove(2); popped = L.pop()
print(L, popped, L.index(8), L.count(2), sorted(L), sorted(L, reverse=True), L[1:4])
L.sort(); L.reverse(); print(L, min(L), max(L), sum(L), len(L))
matrix = [[1, 2], [3, 4]]; print(matrix[1][0], [row[0] for row in matrix])

h("9. Tuple (immutable) & named tuple")
tp = (1, 2, 3); single = (1,)
print(tp[0], tp.count(2), single, tp + (4,))
from collections import namedtuple
Pt = namedtuple("Pt", "x y"); p = Pt(1, 2); print(p, p.x, p._asdict())

h("10. Set (unique, unordered)")
A, B = {1, 2, 3, 4}, {3, 4, 5}
print(A | B, A & B, A - B, A ^ B, A <= B, A.isdisjoint({9}))
A.add(10); A.discard(99); print(sorted(A), frozenset([1, 2]))

h("11. Dict (key -> value)")
d = {"id": 1, "city": "Pune"}
d["age"] = 30; d.update(city="Delhi", tier="Gold")
print(d.get("zip", "n/a"), d.pop("tier"), list(d.keys()), list(d.values()), list(d.items()))
d.setdefault("country", "India"); print(d, "age" in d, len(d))
for k, v in d.items(): print(" ", k, "=>", v)
print({**d, "extra": 1}, d | {"age": 31})                               # merge (3.9+)

h("12. Conditionals")
def tier(spend):
    if spend >= 1000: return "Platinum"
    elif spend >= 500: return "Gold"
    elif spend >= 100: return "Silver"
    else: return "Bronze"
print([tier(s) for s in (50, 150, 700, 2500)], "yes" if 5 > 3 else "no")
print("truthy:", [bool(v) for v in (0, 1, "", "x", [], [0], None)])

h("13. Loops")
for i in range(1, 10, 3): print(i, end=" ")
print()
for idx, ch in enumerate("abc", start=1): print(idx, ch, end=" | ")
print()
for a_, b_ in zip([1, 2, 3], "xyz"): print(a_, b_, end=" | ")
print()
n = 0
while True:
    n += 1
    if n % 2: continue                       # skip odds
    if n > 6: break
    print("even", n, end=" ")
else: print("never runs after break")
for i in range(3): pass
else: print("\nfor-else runs when loop wasn't broken")

h("14. Functions")
def clv(aov, freq=4, *extras, years=3, **opts):
    """Return simple CLV.  *extras -> tuple, **opts -> dict, years is keyword-only."""
    return round(aov * freq * years * opts.get("margin", 0.3), 2), extras, opts
print(clv(60), clv(60, 6, "x", years=5, margin=0.4))
def mutate(lst=None):                        # never use mutable default args
    lst = [] if lst is None else lst; lst.append(1); return lst
print(mutate(), mutate())
def fact(n): return 1 if n <= 1 else n * fact(n - 1)
print(fact(6), clv.__doc__[:30])
def stats(xs): return min(xs), max(xs), sum(xs) / len(xs)       # multiple returns
lo, hi, avg = stats([4, 8, 6]); print(lo, hi, avg)

h("15. Scope (LEGB)")
g = "global"
def outer():
    e = "enclosing"
    def inner():
        nonlocal e; e = "changed"; l = "local"; return l, e, g
    return inner()
print(outer())
counter = 0
def bump():
    global counter; counter += 1
bump(); bump(); print("counter", counter)

h("16. Lambda, map, filter, sorted key")
sq = lambda v: v ** 2
print(sq(4), list(map(sq, range(5))), list(filter(lambda v: v % 2, range(8))))
people = [("A", 30), ("B", 25), ("C", 35)]
print(sorted(people, key=lambda p: p[1]), max(people, key=lambda p: p[1]))

h("17. Comprehensions")
print([i * i for i in range(6) if i % 2 == 0], {c: ord(c) for c in "abc"},
      {len(w) for w in ["aa", "bb", "ccc"]}, [(i, j) for i in range(2) for j in range(2)])
gen = (i * i for i in range(1_000_000)); print(next(gen), next(gen))   # lazy generator expression

h("18. match-case (3.10+)")
def route(cmd):
    match cmd.split():
        case ["load", fname]: return f"loading {fname}"
        case ["quit" | "exit"]: return "bye"
        case ["scale", n] if n.isdigit(): return f"scaling x{n}"
        case [first, *rest]: return f"unknown {first} ({len(rest)} args)"
        case _: return "empty"
print(route("load data.csv"), route("exit"), route("scale 3"), route("foo a b"), route(""))
