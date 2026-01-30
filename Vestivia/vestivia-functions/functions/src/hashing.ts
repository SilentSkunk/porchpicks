import * as imghash from "imghash";

/**
 * Compute a 64‑bit perceptual hash (hex string) from an image buffer.
 * Uses imghash pHash under the hood.
 */
export async function computeHexPHashFromBuffer(
  buf: Buffer | Uint8Array
): Promise<string> {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf);
  const hex = await (imghash as any).hash(b as any, 8, "hex");
  return String(hex);
}

function popcountBigInt(n: bigint): number {
  // Avoid BigInt literals to keep compatibility with older TS targets
  let count = 0;
  while (n !== BigInt(0)) {
    if ((n & BigInt(1)) === BigInt(1)) count++;
    n = n >> BigInt(1);
  }
  return count;
}

/**
 * Hamming distance between two 64‑bit hex pHashes.
 */
export function hammingHex(aHex: string, bHex: string): number {
  const a = aHex.padStart(16, "0");
  const b = bHex.padStart(16, "0");
  const x = BigInt("0x" + a) ^ BigInt("0x" + b);
  return popcountBigInt(x);
}