from sonymdr import MDR, CMD1, CMD2
m = MDR()
Q = [
 ("protocol", CMD1, "00 00"),
 ("series/color", CMD1, "04 03"),
 ("codec", CMD1, "12 02"),
 ("dsee effect status", CMD1, "12 03"),
 ("battery", CMD1, "22 00"),
 ("autooff wearing", CMD1, "26 05"),
 ("gs1 cap", CMD1, "d0 d1 01"), ("gs1", CMD1, "d6 d1"),
 ("gs2 cap", CMD1, "d0 d2 01"), ("gs2", CMD1, "d6 d2"),
 ("eq cap", CMD1, "50 00 01"), ("eq status", CMD1, "52 00"), ("eq", CMD1, "56 00"),
 ("ncasm", CMD1, "66 17"), ("nc/amb toggle", CMD1, "66 30"),
 ("sense cap", CMD1, "70 00"),
 ("play name", CMD1, "a6 01"), ("music vol", CMD1, "a6 20"), ("play status", CMD1, "a2 01"),
 ("conn mode", CMD1, "e6 00"),
 ("dsee cap", CMD1, "e0 01"), ("dsee status", CMD1, "e2 01"), ("dsee", CMD1, "e6 01"),
 ("pause on removal", CMD1, "f6 01"),
 ("va cap", CMD1, "f0 04"), ("va", CMD1, "f6 04"),
 ("s2c", CMD1, "f6 0c"), ("s2c ext", CMD1, "fa 0c"),
 ("quick access cap", CMD1, "f0 0d"), ("quick access", CMD1, "f6 0d"),
 ("sar cap", CMD1, "b0 00"),
 ("vg cap", CMD2, "40 01"), ("vg", CMD2, "46 01"),
 ("pairing status", CMD2, "32 02"), ("paired devices", CMD2, "36 02"), ("source switch", CMD2, "36 01"),
 ("safe listening", CMD2, "56 00"), ("sound pressure", CMD2, "5a 00"),
 ("link auto switch", CMD2, "f6 0a"),
 ("qa easy", CMD2, "f6 02"),
]
for name, mt, p in Q:
    r = m.send(bytes.fromhex(p), mtype=mt, timeout=1.5)
    print(f"{name:20} {p:10} -> " + (" ; ".join(f"[{t:02x}] {x.hex(' ')}" for t, x in r) or "(no reply)"))
m.close()
