// Sony MDR v2 client in Bun, talking RFCOMM through the ./rfcomm-bridge Swift sidecar.
// Usage: bun sony.ts [status|nc|ambient [level]|off]
const ADDR = process.env.SONY_ADDR;
if (!ADDR) throw new Error("set SONY_ADDR to the headset address, e.g. SONY_ADDR=AA-BB-CC-DD-EE-FF");
const [H, T, E] = [0x3e, 0x3c, 0x3d];

function encode(type: number, seq: number, payload: number[]): Uint8Array {
  const body = [type, seq, 0, 0, (payload.length >> 8) & 0xff, payload.length & 0xff, ...payload];
  body.push(body.reduce((a, b) => a + b, 0) & 0xff);
  const esc = body.flatMap((b) => ([H, T, E].includes(b) ? [E, b & 0xef] : [b]));
  return new Uint8Array([H, ...esc, T]);
}

function decode(frame: number[]) {
  const raw: number[] = [];
  for (let i = 0; i < frame.length; i++) raw.push(frame[i] === E ? frame[++i] | 0x10 : frame[i]);
  const len = (raw[2] << 24) | (raw[3] << 16) | (raw[4] << 8) | raw[5];
  return { type: raw[0], seq: raw[1], payload: raw.slice(6, 6 + len) };
}

const proc = Bun.spawn([import.meta.dir + "/rfcomm-bridge", ADDR, "9"], { stdin: "pipe", stdout: "pipe" });
let seq = 0;
let buf: number[] = [];
const waiters: ((p: number[]) => void)[] = [];

(async () => {
  for await (const chunk of proc.stdout) {
    buf.push(...chunk);
    let s: number, e: number;
    while ((s = buf.indexOf(H)) >= 0 && (e = buf.indexOf(T, s)) > s) {
      const m = decode(buf.slice(s + 1, e));
      buf = buf.slice(e + 1);
      if (m.type === 0x01) { seq = m.seq; continue; }
      proc.stdin.write(encode(0x01, 1 - m.seq, [])); // ACK
      waiters.shift()?.(m.payload);
    }
  }
})();

function send(payload: number[]): Promise<number[]> {
  return new Promise((res, rej) => {
    waiters.push(res);
    proc.stdin.write(encode(0x0c, seq, payload));
    proc.stdin.flush();
    setTimeout(() => rej(new Error("timeout " + payload.map((b) => b.toString(16)).join(" "))), 3000);
  });
}

const [cmd = "status", arg] = process.argv.slice(2);
await send([0x00, 0x00]); // init / protocol info
if (cmd === "nc") await send([0x68, 0x17, 0x01, 0x01, 0x00, 0x00, 0x14]);
if (cmd === "ambient") await send([0x68, 0x17, 0x01, 0x01, 0x01, 0x00, Number(arg ?? 20)]);
if (cmd === "off") await send([0x68, 0x17, 0x01, 0x00, 0x00, 0x00, 0x14]);
const bat = await send([0x22, 0x00]);
const asm = await send([0x66, 0x17]);
const mode = asm[3] === 0 ? "off" : asm[4] === 0 ? "noise-cancelling" : `ambient(${asm[6]}${asm[5] ? ", voice" : ""})`;
console.log(JSON.stringify({ battery: bat[2], charging: !!bat[3], mode }));
proc.stdin.end();
process.exit(0);
