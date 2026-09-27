import time
from sonymdr import MDR
m = MDR(verbose=True)
m.send(bytes.fromhex("00 00"))
orig = m.send(bytes.fromhex("66 17"))[0][1]
print("orig", orig.hex(' '))
print("-> ambient lvl 10:", m.send(bytes.fromhex("68 17 01 01 01 00 0a")))
time.sleep(2)
print("readback", m.send(bytes.fromhex("66 17")))
print("pause-on-removal via f6 01:", m.send(bytes.fromhex("f6 01")))
print("volume get a6 20:", m.send(bytes.fromhex("a6 20")))
restore = bytes([0x68]) + orig[1:]
print("-> restore:", m.send(restore))
print("final", m.send(bytes.fromhex("66 17")))
m.close()
