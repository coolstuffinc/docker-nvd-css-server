stock int NQ_CharCountBits(int mode, int ver) {
	int i = (ver + 7) / 17;
	if (mode == 1) return NQ_CC_BITS_NUMERIC[i];
	if (mode == 2) return NQ_CC_BITS_ALPHA[i];
	if (mode == 4) return NQ_CC_BITS_BYTE[i];
	if (mode == 8) return NQ_CC_BITS_KANJI[i];
	return 0;
}

stock int NQ_SegBitLen(int mode, int n) {
	if (n > 32767) return -1;
	if (mode == 1) { int r = (n * 10 + 2) / 3; if (r > 32767) return -1; return r; }
	if (mode == 2) { int r = (n * 11 + 1) / 2; if (r > 32767) return -1; return r; }
	if (mode == 4) { if (n * 8 > 32767) return -1; return n * 8; }
	if (mode == 8) { if (n * 13 > 32767) return -1; return n * 13; }
	return -1;
}

stock bool NQ_IsNum(const char[] t) {
	int l = strlen(t);
	for (int i = 0; i < l; i++)
		if (t[i] < '0' || t[i] > '9')
			return false;
	return true;
}

stock bool NQ_IsAlpha(const char[] t) {
	int l = strlen(t);
	int al = strlen(NQ_ALPHANUM);
	for (int i = 0; i < l; i++) {
		bool found = false;
		for (int j = 0; j < al; j++)
			if (t[i] == NQ_ALPHANUM[j]) { found = true; break; }
		if (!found)
			return false;
	}
	return true;
}

stock int NQ_TotalBits(const int[] modes, const int[] nchars, const int[] blens, int nsegs, int ver) {
	int r = 0;
	for (int i = 0; i < nsegs; i++) {
		int cc = NQ_CharCountBits(modes[i], ver);
		if (nchars[i] >= (1 << cc))
			return -1;
		r += 4 + cc + blens[i];
		if (r > 32767)
			return -1;
	}
	return r;
}

stock int NQ_EncodeSegs(const int[] modes, const int[] nchars, const int[] blens,
		const int[] segData, int nsegs, int ecl, int minV, int maxV,
		int[] qrbuf, int[] tempbuf) {

	int ver, dataUsed;
	for (ver = minV; ; ver++) {
		int cap = NQ_DataCodewords(ver, ecl) * 8;
		dataUsed = NQ_TotalBits(modes, nchars, blens, nsegs, ver);
		if (dataUsed != -1 && dataUsed <= cap)
			break;
		if (ver >= maxV)
			return 0;
	}
	for (int e = 1; e <= 3; e++)
		if (dataUsed <= NQ_DataCodewords(ver, e) * 8)
			ecl = e;

	int rawBytes = NQ_RawDataMods(ver) / 8;
	for (int i = 0; i < rawBytes + 16; i++)
		tempbuf[i] = 0;
	int bitLen = 0;
	for (int i = 0; i < nsegs; i++) {
		NQ_AppendBits(modes[i], 4, tempbuf, bitLen);
		NQ_AppendBits(nchars[i], NQ_CharCountBits(modes[i], ver), tempbuf, bitLen);
		// Copy bits directly from segData
		for (int j = 0; j < blens[i]; j++) {
			int b = (segData[j >> 3] >> (7 - (j & 7))) & 1;
			NQ_AppendBits(b, 1, tempbuf, bitLen);
		}
	}
	int cap = NQ_DataCodewords(ver, ecl) * 8;
	int term = cap - bitLen;
	if (term > 4) term = 4;
	NQ_AppendBits(0, term, tempbuf, bitLen);
	NQ_AppendBits(0, (8 - bitLen % 8) % 8, tempbuf, bitLen);
	for (int pb = 0xEC; bitLen < cap; pb ^= 0xEC ^ 0x11)
		NQ_AppendBits(pb, 8, tempbuf, bitLen);

	NQ_EccInterleave(tempbuf, ver, ecl, tempbuf);

	NQ_InitFunc(ver, qrbuf);
	NQ_DrawCodewords(tempbuf, NQ_RawDataMods(ver) / 8, qrbuf);
	NQ_DrawLightFunc(qrbuf, ver);

	NQ_InitFunc(ver, tempbuf);

	int bestM = 0, bestP = 2147483647;
	for (int m = 0; m < 8; m++) {
		NQ_ApplyMask(tempbuf, qrbuf, m);
		NQ_DrawFormatBits(ecl, m, qrbuf);
		int p = NQ_Penalty(qrbuf);
		if (p < bestP) { bestM = m; bestP = p; }
		NQ_ApplyMask(tempbuf, qrbuf, m);
	}
	NQ_ApplyMask(tempbuf, qrbuf, bestM);
	NQ_DrawFormatBits(ecl, bestM, qrbuf);
	return ver;
}

stock bool Nayuki_QrEncodeEx(const char[] text, int modules[][NQ_MODULE_MAX], int &versionOut, int &modeOut, int &eclOut, int minVer=0, int forceEcl=-1, bool forceByte=false) {
	int len = strlen(text);
	if (len == 0)
		return false;

	int mode, segNumChars, segBitLen;
	int[] segData = new int[512];

	if (forceByte) {
		mode = 4;
		segNumChars = len;
		segBitLen = NQ_SegBitLen(mode, len);
		if (segBitLen == -1)
			return false;
		int bl = 0;
		for (int i = 0; i < len; i++)
			NQ_AppendBits(text[i], 8, segData, bl);
	} else if (NQ_IsNum(text)) {
		mode = 1;
		segNumChars = len;
		segBitLen = NQ_SegBitLen(mode, len);
		if (segBitLen == -1)
			return false;
		int bl = 0, acc = 0, cnt = 0;
		for (int i = 0; i < len; i++) {
			acc = acc * 10 + (text[i] - '0');
			cnt++;
			if (cnt == 3) { NQ_AppendBits(acc, 10, segData, bl); acc = 0; cnt = 0; }
		}
		if (cnt > 0)
			NQ_AppendBits(acc, cnt * 3 + 1, segData, bl);
	} else if (NQ_IsAlpha(text)) {
		mode = 2;
		segNumChars = len;
		segBitLen = NQ_SegBitLen(mode, len);
		if (segBitLen == -1)
			return false;
		int bl = 0, acc = 0, cnt = 0;
		int al = strlen(NQ_ALPHANUM);
		for (int i = 0; i < len; i++) {
			int ci = -1;
			for (int j = 0; j < al; j++)
				if (text[i] == NQ_ALPHANUM[j]) { ci = j; break; }
			acc = acc * 45 + ci;
			cnt++;
			if (cnt == 2) { NQ_AppendBits(acc, 11, segData, bl); acc = 0; cnt = 0; }
		}
		if (cnt > 0)
			NQ_AppendBits(acc, 6, segData, bl);
	} else {
		mode = 4;
		segNumChars = len;
		segBitLen = NQ_SegBitLen(mode, len);
		if (segBitLen == -1)
			return false;
		int bl = 0;
		for (int i = 0; i < len; i++)
			NQ_AppendBits(text[i], 8, segData, bl);
	}

	int[] modes = new int[1];
	modes[0] = mode;
	int[] nchars = new int[1];
	nchars[0] = segNumChars;
	int[] blens = new int[1];
	blens[0] = segBitLen;

	int[] qrbuf = new int[512];
	int[] tempbuf = new int[512];

	int startVer = (minVer > 0) ? minVer : 1;
	int startEcl = (forceEcl >= 0 && forceEcl <= 3) ? forceEcl : 0;
	int ver = NQ_EncodeSegs(modes, nchars, blens, segData, 1, startEcl, startVer, NQ_VERSION_MAX, qrbuf, tempbuf);
	if (ver == 0)
		return false;

	eclOut = startEcl;
	if (forceEcl < 0) {
		int du = NQ_TotalBits(modes, nchars, blens, 1, ver);
		for (int e = 1; e <= 3; e++) {
			if (du <= NQ_DataCodewords(ver, e) * 8)
				eclOut = e;
		}
	}
	modeOut = mode;

	int sz = NQ_Size(qrbuf);
	for (int y = 0; y < sz && y < NQ_MODULE_MAX; y++)
		for (int x = 0; x < sz && x < NQ_MODULE_MAX; x++)
			modules[y][x] = NQ_GetMod(qrbuf, x, y) ? 1 : 0;

	versionOut = ver;
	return true;
}

stock bool Nayuki_QrEncode(const char[] text, int modules[][NQ_MODULE_MAX], int &versionOut) {
	int dummyMode, dummyEcl;
	return Nayuki_QrEncodeEx(text, modules, versionOut, dummyMode, dummyEcl, 0, -1);
}
