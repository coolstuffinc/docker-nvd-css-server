stock int NQ_RS_Mul(int x, int y) {
	int z = 0;
	for (int i = 7; i >= 0; i--) {
		z = (z << 1) ^ ((z >> 7) * 0x11D);
		z ^= ((y >> i) & 1) * x;
	}
	return z;
}

stock void NQ_RS_Divisor(int deg, int[] out) {
	for (int i = 0; i < deg; i++)
		out[i] = 0;
	out[deg - 1] = 1;
	int root = 1;
	for (int i = 0; i < deg; i++) {
		for (int j = 0; j < deg; j++) {
			out[j] = NQ_RS_Mul(out[j], root);
			if (j + 1 < deg)
				out[j] ^= out[j + 1];
		}
		root = NQ_RS_Mul(root, 0x02);
	}
}

stock void NQ_RS_Remainder(const int[] data, int dataOff, int dataLen, const int[] gen, int deg, int[] out) {
	for (int i = 0; i < deg; i++)
		out[i] = 0;
	for (int i = 0; i < dataLen; i++) {
		int factor = data[dataOff + i] ^ out[0];
		for (int j = 0; j < deg - 1; j++)
			out[j] = out[j + 1];
		out[deg - 1] = 0;
		for (int j = 0; j < deg; j++)
			out[j] ^= NQ_RS_Mul(gen[j], factor);
	}
}

stock int NQ_RawDataMods(int ver) {
	int r = (16 * ver + 128) * ver + 64;
	if (ver >= 2) {
		int a = ver / 7 + 2;
		r -= (25 * a - 10) * a - 55;
		if (ver >= 7)
			r -= 36;
	}
	return r;
}

stock int NQ_DataCodewords(int ver, int ecl) {
	return NQ_RawDataMods(ver) / 8 - NQ_ECC_PER_BLOCK[ecl][ver] * NQ_NUM_BLOCKS[ecl][ver];
}

stock void NQ_EccInterleave(int[] data, int ver, int ecl, int[] out) {
	int numBlk = NQ_NUM_BLOCKS[ecl][ver];
	int blkEcc = NQ_ECC_PER_BLOCK[ecl][ver];
	int rawCodewords = NQ_RawDataMods(ver) / 8;
	int dataLen = NQ_DataCodewords(ver, ecl);
	int numShort = numBlk - rawCodewords % numBlk;
	int shortDatLen = rawCodewords / numBlk - blkEcc;

	int gen[NQ_RS_DEGREE_MAX];
	NQ_RS_Divisor(blkEcc, gen);

	int off = 0;
	for (int i = 0; i < numBlk; i++) {
		int datLen = shortDatLen + (i < numShort ? 0 : 1);
		int ecc[NQ_RS_DEGREE_MAX];
		NQ_RS_Remainder(data, off, datLen, gen, blkEcc, ecc);
		for (int j = 0, k = i; j < datLen; j++, k += numBlk) {
			if (j == shortDatLen)
				k -= numShort;
			out[k] = data[off + j];
		}
		for (int j = 0, k = dataLen + i; j < blkEcc; j++, k += numBlk)
			out[k] = ecc[j];
		off += datLen;
	}
}
