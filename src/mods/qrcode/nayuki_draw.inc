stock int NQ_AlignPos(int ver, int[] out7) {
	if (ver == 1)
		return 0;
	int n = ver / 7 + 2;
	int step = (ver * 8 + n * 3 + 5) / (n * 4 - 4) * 2;
	for (int i = n - 1, pos = ver * 4 + 10; i >= 1; i--, pos -= step)
		out7[i] = pos;
	out7[0] = 6;
	return n;
}

stock void NQ_FillRect(int l, int t, int w, int h, int[] buf) {
	for (int dy = 0; dy < h; dy++)
		for (int dx = 0; dx < w; dx++)
			NQ_SetMod(buf, l + dx, t + dy, true);
}

stock void NQ_InitFunc(int ver, int[] buf) {
	int sz = ver * 4 + 17;
	NQ_ClearBuf(buf, sz);

	NQ_FillRect(6, 0, 1, sz, buf);
	NQ_FillRect(0, 6, sz, 1, buf);

	NQ_FillRect(0, 0, 9, 9, buf);
	NQ_FillRect(sz - 8, 0, 8, 9, buf);
	NQ_FillRect(0, sz - 8, 9, 8, buf);

	int pos[7];
	int n = NQ_AlignPos(ver, pos);
	for (int i = 0; i < n; i++)
		for (int j = 0; j < n; j++)
			if (!((i == 0 && j == 0) || (i == 0 && j == n - 1) || (i == n - 1 && j == 0)))
				NQ_FillRect(pos[i] - 2, pos[j] - 2, 5, 5, buf);

	if (ver >= 7) {
		NQ_FillRect(sz - 11, 0, 3, 6, buf);
		NQ_FillRect(0, sz - 11, 6, 3, buf);
	}
}

stock void NQ_DrawLightFunc(int[] buf, int ver) {
	int sz = NQ_Size(buf);
	for (int i = 7; i < sz - 7; i += 2) {
		NQ_SetMod(buf, 6, i, false);
		NQ_SetMod(buf, i, 6, false);
	}
	for (int dy = -4; dy <= 4; dy++) {
		for (int dx = -4; dx <= 4; dx++) {
			int d = NQ_Abs(dx);
			if (NQ_Abs(dy) > d)
				d = NQ_Abs(dy);
			if (d == 2 || d == 4) {
				NQ_SetModUnb(buf, 3 + dx, 3 + dy, false);
				NQ_SetModUnb(buf, sz - 4 + dx, 3 + dy, false);
				NQ_SetModUnb(buf, 3 + dx, sz - 4 + dy, false);
			}
		}
	}
	int pos[7];
	int n = NQ_AlignPos(ver, pos);
	for (int i = 0; i < n; i++)
		for (int j = 0; j < n; j++) {
			if ((i == 0 && j == 0) || (i == 0 && j == n - 1) || (i == n - 1 && j == 0))
				continue;
			for (int dy = -1; dy <= 1; dy++)
				for (int dx = -1; dx <= 1; dx++)
					NQ_SetMod(buf, pos[i] + dx, pos[j] + dy, dx == 0 && dy == 0);
		}
	if (ver >= 7) {
		int rem = ver;
		for (int i = 0; i < 12; i++)
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
		int bits = ver << 12 | rem;
		for (int i = 0; i < 6; i++)
			for (int j = 0; j < 3; j++) {
				int k = sz - 11 + j;
				NQ_SetMod(buf, k, i, (bits & 1) != 0);
				NQ_SetMod(buf, i, k, (bits & 1) != 0);
				bits >>= 1;
			}
	}
}

stock void NQ_DrawFormatBits(int ecl, int mask, int[] buf) {
	int data = NQ_FORMAT_TBL[ecl] << 3 | mask;
	int rem = data;
	for (int i = 0; i < 10; i++)
		rem = (rem << 1) ^ ((rem >> 9) * 0x537);
	int bits = (data << 10 | rem) ^ 0x5412;

	for (int i = 0; i <= 5; i++)
		NQ_SetMod(buf, 8, i, NQ_GetBit(bits, i) != 0);
	NQ_SetMod(buf, 8, 7, NQ_GetBit(bits, 6) != 0);
	NQ_SetMod(buf, 8, 8, NQ_GetBit(bits, 7) != 0);
	NQ_SetMod(buf, 7, 8, NQ_GetBit(bits, 8) != 0);
	for (int i = 9; i < 15; i++)
		NQ_SetMod(buf, 14 - i, 8, NQ_GetBit(bits, i) != 0);

	int sz = NQ_Size(buf);
	for (int i = 0; i < 8; i++)
		NQ_SetMod(buf, sz - 1 - i, 8, NQ_GetBit(bits, i) != 0);
	for (int i = 8; i < 15; i++)
		NQ_SetMod(buf, 8, sz - 15 + i, NQ_GetBit(bits, i) != 0);
	NQ_SetMod(buf, 8, sz - 8, true);
}

stock void NQ_DrawCodewords(const int[] data, int dataLen, int[] buf) {
	int sz = NQ_Size(buf);
	int i = 0;
	for (int right = sz - 1; right >= 1; right -= 2) {
		if (right == 6)
			right = 5;
		for (int vert = 0; vert < sz; vert++)
			for (int j = 0; j < 2; j++) {
				int x = right - j;
				bool up = ((right + 1) & 2) == 0;
				int y = up ? sz - 1 - vert : vert;
				if (!NQ_GetMod(buf, x, y) && i < dataLen * 8) {
					bool dark = NQ_GetBit(data[i >> 3], 7 - (i & 7)) != 0;
					NQ_SetMod(buf, x, y, dark);
					i++;
				}
			}
	}
}

stock void NQ_ApplyMask(const int[] func, int[] buf, int mask) {
	int sz = NQ_Size(buf);
	for (int y = 0; y < sz; y++)
		for (int x = 0; x < sz; x++) {
			if (NQ_GetMod(func, x, y))
				continue;
			bool invert;
			if (mask == 0)         invert = (x + y) % 2 == 0;
			else if (mask == 1)    invert = y % 2 == 0;
			else if (mask == 2)    invert = x % 3 == 0;
			else if (mask == 3)    invert = (x + y) % 3 == 0;
			else if (mask == 4)    invert = (x / 3 + y / 2) % 2 == 0;
			else if (mask == 5)    invert = x * y % 2 + x * y % 3 == 0;
			else if (mask == 6)    invert = (x * y % 2 + x * y % 3) % 2 == 0;
			else if (mask == 7)    invert = ((x + y) % 2 + x * y % 3) % 2 == 0;
			else                   invert = false;
			NQ_SetMod(buf, x, y, NQ_GetMod(buf, x, y) ^ invert);
		}
}

stock void AddHist(int run, int[] hist, int sz) {
	if (hist[0] == 0)
		run += sz;
	for (int i = 6; i > 0; i--)
		hist[i] = hist[i - 1];
	hist[0] = run;
}

stock int CountPatt(const int[] hist) {
	int n = hist[1];
	bool core = n > 0 && hist[2] == n && hist[3] == n * 3 && hist[4] == n && hist[5] == n;
	return (core && hist[0] >= n * 4 && hist[6] >= n ? 1 : 0)
	     + (core && hist[6] >= n * 4 && hist[0] >= n ? 1 : 0);
}

stock int TermAndCount(bool runColor, int runLen, int[] hist, int sz) {
	if (runColor) {
		AddHist(runLen, hist, sz);
		runLen = 0;
	}
	runLen += sz;
	AddHist(runLen, hist, sz);
	return CountPatt(hist);
}

stock int NQ_Penalty(const int[] buf) {
	int sz = NQ_Size(buf);
	int r = 0;
	for (int y = 0; y < sz; y++) {
		bool c = false;
		int run = 0;
		int h[7] = {0};
		for (int x = 0; x < sz; x++) {
			if (NQ_GetMod(buf, x, y) == c) {
				run++;
				if (run == 5)
					r += 3;
				else if (run > 5)
					r++;
			} else {
				AddHist(run, h, sz);
				if (!c)
					r += CountPatt(h) * 40;
				c = NQ_GetMod(buf, x, y);
				run = 1;
			}
		}
		r += TermAndCount(c, run, h, sz) * 40;
	}
	for (int x = 0; x < sz; x++) {
		bool c = false;
		int run = 0;
		int h[7] = {0};
		for (int y = 0; y < sz; y++) {
			if (NQ_GetMod(buf, x, y) == c) {
				run++;
				if (run == 5)
					r += 3;
				else if (run > 5)
					r++;
			} else {
				AddHist(run, h, sz);
				if (!c)
					r += CountPatt(h) * 40;
				c = NQ_GetMod(buf, x, y);
				run = 1;
			}
		}
		r += TermAndCount(c, run, h, sz) * 40;
	}
	for (int y = 0; y < sz - 1; y++)
		for (int x = 0; x < sz - 1; x++) {
			bool v = NQ_GetMod(buf, x, y);
			if (v == NQ_GetMod(buf, x + 1, y) && v == NQ_GetMod(buf, x, y + 1) && v == NQ_GetMod(buf, x + 1, y + 1))
				r += 3;
		}
	int dark = 0;
	for (int y = 0; y < sz; y++)
		for (int x = 0; x < sz; x++)
			if (NQ_GetMod(buf, x, y))
				dark++;
	int k = (NQ_Abs(dark * 20 - sz * sz * 10) + sz * sz - 1) / (sz * sz) - 1;
	if (k < 0) k = 0;
	if (k > 9) k = 9;
	r += k * 10;
	return r;
}
