import sys; sys.path.insert(0, sys.argv[1])
from fnames import T1, T2
from sonymdr import MDR, CMD1, CMD2
m = MDR()
print("protocol", m.send(bytes.fromhex("00 00"))[0][1].hex(' '))
print("capability", m.send(bytes.fromhex("02 00")))
for t in (1,2,3): print("devinfo", t, m.send(bytes([4,t])))
for mt, table, name in ((CMD1, T1, "T1"), (CMD2, T2, "T2")):
    r = m.send(bytes.fromhex("06 00"), mtype=mt)
    for t, p in r:
        print(name, "raw", p.hex(' '))
        n = p[2]; fs = p[3:3+2*n]
        for i in range(0, len(fs), 2):
            print(f"  {fs[i]:#04x} {table.get(fs[i], '?'):70} prio={fs[i+1]}")
m.close()
