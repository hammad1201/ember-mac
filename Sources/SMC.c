#include "Bridge.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t conn = 0;

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? 0 : -1;
}

static int call(SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t r = IOConnectCallStructMethod(conn, 2, in, sizeof(SMCKeyData), out, &outSize);
    return (r == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

int smc_read(const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type) {
    if (!conn || strlen(key) != 4) return -1;
    SMCKeyData in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = (uint32_t)(unsigned char)key[0] << 24 | (uint32_t)(unsigned char)key[1] << 16 |
             (uint32_t)(unsigned char)key[2] << 8 | (uint32_t)(unsigned char)key[3];
    in.data8 = 9; // get key info
    if (call(&in, &out)) return -1;
    in.keyInfo.dataSize = out.keyInfo.dataSize;
    *size = out.keyInfo.dataSize;
    *type = out.keyInfo.dataType;
    in.data8 = 5; // read key
    memset(&out, 0, sizeof out);
    if (call(&in, &out)) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}
