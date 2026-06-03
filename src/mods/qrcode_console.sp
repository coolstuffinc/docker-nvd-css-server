#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define QR_VERSION 1
#define QR_SIZE 21
#define QR_DATA_CODEWORDS 19
#define QR_ECC_CODEWORDS 7
#define QR_TOTAL_CODEWORDS 26
#define QR_MAX_TEXT_BYTES 17
#define QR_MASK 0
#define QR_QUIET_ZONE 2
#define QR_PRINT_LINE_LEN (((QR_SIZE + (QR_QUIET_ZONE * 2)) * 2) + 1)
#define QR_INPUT_BUFFER_SIZE 256
#define QR_GF256_PRIMITIVE 0x11D
#define QR_FORMAT_POLYNOMIAL 0x537
#define QR_FORMAT_MASK 0x5412
#define QR_PAD_BYTE_A 0xEC
#define QR_PAD_BYTE_B 0x11

public Plugin myinfo = {
    name = "Console QR Code",
    author = "coolstuffinc",
    description = "Generates version-1 QR codes in console",
    version = "1.0.0"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_qrcode", Command_QRCode, "sm_qrcode <text> - Print QR code in console");
    RegConsoleCmd("sm_qr", Command_QRCode, "sm_qr <text> - Alias for sm_qrcode");
}

public Action Command_QRCode(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_qrcode <text>");
        return Plugin_Handled;
    }

    char text[QR_INPUT_BUFFER_SIZE];
    GetCmdArgString(text, sizeof(text));
    TrimString(text);
    StripQuotes(text);

    int textLen = strlen(text);
    if (textLen < 1)
    {
        ReplyToCommand(client, "[QR] Text cannot be empty.");
        return Plugin_Handled;
    }

    if (textLen > QR_MAX_TEXT_BYTES)
    {
        ReplyToCommand(client, "[QR] Version 1-L supports up to %d bytes in byte mode.", QR_MAX_TEXT_BYTES);
        return Plugin_Handled;
    }

    int codewords[QR_TOTAL_CODEWORDS];
    if (!EncodeQrVersion1(text, textLen, codewords))
    {
        ReplyToCommand(client, "[QR] Failed to encode payload.");
        return Plugin_Handled;
    }

    int modules[QR_SIZE][QR_SIZE];
    bool functionModules[QR_SIZE][QR_SIZE];
    BuildMatrix(codewords, modules, functionModules);
    PrintMatrixToConsole(client, modules);

    ReplyToCommand(client, "[QR] Printed QR code for: %s", text);
    return Plugin_Handled;
}

bool EncodeQrVersion1(const char[] text, int textLen, int codewords[QR_TOTAL_CODEWORDS])
{
    int data[QR_DATA_CODEWORDS];
    for (int i = 0; i < QR_DATA_CODEWORDS; i++)
        data[i] = 0;

    int bitLen = 0;
    AppendBitsToBuffer(0x4, 4, data, bitLen);
    AppendBitsToBuffer(textLen, 8, data, bitLen);

    for (int i = 0; i < textLen; i++)
        AppendBitsToBuffer(text[i] & 0xFF, 8, data, bitLen);

    int dataCapacityBits = QR_DATA_CODEWORDS * 8;
    int terminatorBits = dataCapacityBits - bitLen;
    if (terminatorBits > 4)
        terminatorBits = 4;

    AppendBitsToBuffer(0, terminatorBits, data, bitLen);
    AppendBitsToBuffer(0, (8 - (bitLen % 8)) % 8, data, bitLen);

    for (int padByte = QR_PAD_BYTE_A; bitLen < dataCapacityBits; padByte ^= QR_PAD_BYTE_A ^ QR_PAD_BYTE_B)
        AppendBitsToBuffer(padByte, 8, data, bitLen);

    int generator[QR_ECC_CODEWORDS];
    int ecc[QR_ECC_CODEWORDS];
    ReedSolomonComputeDivisor(QR_ECC_CODEWORDS, generator);
    ReedSolomonComputeRemainder(data, QR_DATA_CODEWORDS, generator, QR_ECC_CODEWORDS, ecc);

    for (int i = 0; i < QR_DATA_CODEWORDS; i++)
        codewords[i] = data[i];
    for (int i = 0; i < QR_ECC_CODEWORDS; i++)
        codewords[QR_DATA_CODEWORDS + i] = ecc[i];

    return true;
}

void AppendBitsToBuffer(int value, int numBits, int buffer[QR_DATA_CODEWORDS], int &bitLen)
{
    for (int i = numBits - 1; i >= 0; i--)
    {
        if (((value >> i) & 1) != 0)
            buffer[bitLen >> 3] |= 1 << (7 - (bitLen & 7));
        bitLen++;
    }
}

void ReedSolomonComputeDivisor(int degree, int result[QR_ECC_CODEWORDS])
{
    for (int i = 0; i < degree; i++)
        result[i] = 0;

    result[degree - 1] = 1;
    int root = 1;

    for (int i = 0; i < degree; i++)
    {
        for (int j = 0; j < degree; j++)
        {
            result[j] = ReedSolomonMultiply(result[j], root);
            if (j + 1 < degree)
                result[j] ^= result[j + 1];
        }
        root = ReedSolomonMultiply(root, 0x02);
    }
}

void ReedSolomonComputeRemainder(const int data[QR_DATA_CODEWORDS], int dataLen, const int generator[QR_ECC_CODEWORDS], int degree, int result[QR_ECC_CODEWORDS])
{
    for (int i = 0; i < degree; i++)
        result[i] = 0;

    for (int i = 0; i < dataLen; i++)
    {
        int factor = data[i] ^ result[0];
        for (int j = 0; j < degree - 1; j++)
            result[j] = result[j + 1];

        result[degree - 1] = 0;
        for (int j = 0; j < degree; j++)
            result[j] ^= ReedSolomonMultiply(generator[j], factor);
    }
}

int ReedSolomonMultiply(int x, int y)
{
    int z = 0;
    for (int i = 7; i >= 0; i--)
    {
        z = ((z << 1) ^ (((z >> 7) & 1) * QR_GF256_PRIMITIVE)) & 0xFF;
        z ^= ((y >> i) & 1) * x;
    }
    return z & 0xFF;
}

void BuildMatrix(const int codewords[QR_TOTAL_CODEWORDS], int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    InitializeFunctionModules(modules, functionModules);
    DrawCodewords(codewords, modules, functionModules);
    DrawFormatBits(QR_MASK, modules, functionModules);
}

void InitializeFunctionModules(int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    for (int y = 0; y < QR_SIZE; y++)
    {
        for (int x = 0; x < QR_SIZE; x++)
        {
            modules[y][x] = 0;
            functionModules[y][x] = false;
        }
    }

    DrawFinderPattern(3, 3, modules, functionModules);
    DrawFinderPattern(QR_SIZE - 4, 3, modules, functionModules);
    DrawFinderPattern(3, QR_SIZE - 4, modules, functionModules);

    for (int i = 0; i < QR_SIZE; i++)
    {
        SetFunctionModule(6, i, (i % 2) == 0, modules, functionModules);
        SetFunctionModule(i, 6, (i % 2) == 0, modules, functionModules);
    }

    SetFunctionModule(8, QR_SIZE - 8, true, modules, functionModules);

    for (int i = 0; i <= 5; i++)
        SetFunctionModule(8, i, false, modules, functionModules);
    SetFunctionModule(8, 7, false, modules, functionModules);
    SetFunctionModule(8, 8, false, modules, functionModules);
    SetFunctionModule(7, 8, false, modules, functionModules);
    for (int i = 9; i < 15; i++)
        SetFunctionModule(14 - i, 8, false, modules, functionModules);

    for (int i = 0; i < 8; i++)
        SetFunctionModule(QR_SIZE - 1 - i, 8, false, modules, functionModules);
    for (int i = 8; i < 15; i++)
        SetFunctionModule(8, QR_SIZE - 15 + i, false, modules, functionModules);
}

void DrawFinderPattern(int centerX, int centerY, int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    for (int dy = -4; dy <= 4; dy++)
    {
        for (int dx = -4; dx <= 4; dx++)
        {
            int x = centerX + dx;
            int y = centerY + dy;
            if (x < 0 || x >= QR_SIZE || y < 0 || y >= QR_SIZE)
                continue;

            int dist = IntAbs(dx);
            if (IntAbs(dy) > dist)
                dist = IntAbs(dy);

            bool dark = (dist != 2 && dist != 4);
            SetFunctionModule(x, y, dark, modules, functionModules);
        }
    }
}

void DrawCodewords(const int codewords[QR_TOTAL_CODEWORDS], int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    int bitIndex = 0;
    int bitLen = QR_TOTAL_CODEWORDS * 8;

    for (int right = QR_SIZE - 1; right >= 1; right -= 2)
    {
        if (right == 6)
            right = 5;

        for (int vert = 0; vert < QR_SIZE; vert++)
        {
            bool upward = ((right + 1) & 2) == 0;
            int y = upward ? (QR_SIZE - 1 - vert) : vert;

            for (int j = 0; j < 2; j++)
            {
                int x = right - j;
                if (functionModules[y][x])
                    continue;

                int dark = 0;
                if (bitIndex < bitLen)
                    dark = (codewords[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1;

                if (IsMask0Inverted(x, y))
                    dark ^= 1;

                modules[y][x] = dark;
                bitIndex++;
            }
        }
    }
}

void DrawFormatBits(int mask, int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    int data = (1 << 3) | (mask & 0x7);
    int rem = data;
    for (int i = 0; i < 10; i++)
        rem = (rem << 1) ^ ((rem >> 9) * QR_FORMAT_POLYNOMIAL);

    int bits = ((data << 10) | rem) ^ QR_FORMAT_MASK;

    for (int i = 0; i <= 5; i++)
        SetFunctionModule(8, i, GetBit(bits, i), modules, functionModules);
    SetFunctionModule(8, 7, GetBit(bits, 6), modules, functionModules);
    SetFunctionModule(8, 8, GetBit(bits, 7), modules, functionModules);
    SetFunctionModule(7, 8, GetBit(bits, 8), modules, functionModules);
    for (int i = 9; i < 15; i++)
        SetFunctionModule(14 - i, 8, GetBit(bits, i), modules, functionModules);

    for (int i = 0; i < 8; i++)
        SetFunctionModule(QR_SIZE - 1 - i, 8, GetBit(bits, i), modules, functionModules);
    for (int i = 8; i < 15; i++)
        SetFunctionModule(8, QR_SIZE - 15 + i, GetBit(bits, i), modules, functionModules);

    SetFunctionModule(8, QR_SIZE - 8, true, modules, functionModules);
}

bool GetBit(int value, int i)
{
    return ((value >> i) & 1) != 0;
}

bool IsMask0Inverted(int x, int y)
{
    return ((x + y) % 2) == 0;
}

void SetFunctionModule(int x, int y, bool dark, int modules[QR_SIZE][QR_SIZE], bool functionModules[QR_SIZE][QR_SIZE])
{
    if (x < 0 || x >= QR_SIZE || y < 0 || y >= QR_SIZE)
        return;

    modules[y][x] = dark ? 1 : 0;
    functionModules[y][x] = true;
}

int IntAbs(int value)
{
    return value < 0 ? -value : value;
}

void PrintMatrixToConsole(int client, int modules[QR_SIZE][QR_SIZE])
{
    int quiet = QR_QUIET_ZONE;
    char line[QR_PRINT_LINE_LEN];

    PrintConsoleLine(client, "");

    for (int y = -quiet; y < QR_SIZE + quiet; y++)
    {
        int pos = 0;

        for (int x = -quiet; x < QR_SIZE + quiet; x++)
        {
            bool dark = (x >= 0 && x < QR_SIZE && y >= 0 && y < QR_SIZE && modules[y][x] == 1);
            for (int i = 0; i < 2; i++)
                line[pos++] = dark ? '#' : ' ';
        }

        line[pos] = '\0';
        PrintConsoleLine(client, line);
    }

    PrintConsoleLine(client, "");
}

void PrintConsoleLine(int client, const char[] message)
{
    if (client > 0)
        PrintToConsole(client, "%s", message);
    else
        PrintToServer("%s", message);
}
