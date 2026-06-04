stock const int NQ_ECC_PER_BLOCK[4][13] = {
	{-1, 7,10,15,20,26,18,20,24,30,18,20,24},
	{-1,10,16,26,18,24,16,18,22,22,26,30,22},
	{-1,13,22,18,26,18,24,18,22,20,24,28,26},
	{-1,17,28,22,16,22,28,26,26,24,28,24,28},
};
stock const int NQ_NUM_BLOCKS[4][13] = {
	{-1,1,1,1,1,1,2,2,2,2,4,4,4},
	{-1,1,1,1,2,2,4,4,4,5,5,5,8},
	{-1,1,1,2,4,4,4,6,6,8,8,8,10},
	{-1,1,1,2,4,4,4,5,6,8,8,11,11},
};
stock const char NQ_ALPHANUM[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
stock const int NQ_CC_BITS_NUMERIC[] = {10,12,14};
stock const int NQ_CC_BITS_ALPHA[]   = { 9,11,13};
stock const int NQ_CC_BITS_BYTE[]    = { 8,16,16};
stock const int NQ_CC_BITS_KANJI[]   = { 8,10,12};
stock const int NQ_FORMAT_TBL[] = {1,0,3,2};

stock int NQ_Abs(int x) {
	return x < 0 ? -x : x;
}

stock int NQ_Size(const int[] buf) {
	return buf[0];
}

stock bool NQ_GetMod(const int[] buf, int x, int y) {
	int size = buf[0];
	int idx = y * size + x;
	return (buf[1 + (idx >> 5)] >> (idx & 31)) & 1;
}

stock void NQ_SetMod(int[] buf, int x, int y, bool dark) {
	int size = buf[0];
	int idx = y * size + x;
	int elem = 1 + (idx >> 5);
	int bit = idx & 31;
	if (dark) buf[elem] |= (1 << bit);
	else      buf[elem] &= ~(1 << bit);
}

stock void NQ_SetModUnb(int[] buf, int x, int y, bool dark) {
	int size = buf[0];
	if (0 <= x && x < size && 0 <= y && y < size)
		NQ_SetMod(buf, x, y, dark);
}

stock void NQ_ClearBuf(int[] buf, int size) {
	int n = (size * size + 31) >> 5;
	for (int i = 0; i <= n; i++)
		buf[i] = 0;
	buf[0] = size;
}

stock int NQ_GetBit(int x, int i) {
	return (x >> i) & 1;
}

stock void NQ_AppendBits(int val, int numBits, int[] buf, int &bitLen) {
	for (int i = numBits - 1; i >= 0; i--, bitLen++) {
		int byteIdx = bitLen >> 3;
		buf[byteIdx] |= ((val >> i) & 1) << (7 - (bitLen & 7));
	}
}
