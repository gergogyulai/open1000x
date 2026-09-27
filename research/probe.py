import sys
from sonymdr import MDR
m = MDR(verbose=True)
for name, p in [
    ("init", "00 00"),
    ("fw", "04 02"),
    ("battery", "22 00"),
    ("codec", "12 02"),
    ("ambient", "66 17"),
    ("eq", "56 00"),
    ("dsee", "e6 01"),
    ("speak2chat", "f6 0c"),
    ("auto-off", "26 05"),
    ("pause-on-removal", "26 01"),
]:
    r = m.send(bytes.fromhex(p))
    print(f"{name:18} -> {[ (hex(t), x.hex(' ')) for t,x in r ]}")
m.close()
