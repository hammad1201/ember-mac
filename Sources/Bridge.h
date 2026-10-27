// Private IOKit HID sensor API (no root needed) + small SMC reader.
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <libproc.h>

CF_IMPLICIT_BRIDGING_ENABLED
CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(CFTypeRef client, CFDictionaryRef matching);
CFArrayRef IOHIDEventSystemClientCopyServices(CFTypeRef client);
CFTypeRef IOHIDServiceClientCopyProperty(CFTypeRef service, CFStringRef key);
CFTypeRef IOHIDServiceClientCopyEvent(CFTypeRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(CFTypeRef event, int32_t field);
CF_IMPLICIT_BRIDGING_DISABLED

int smc_open(void);
// Reads a 4-char SMC key. Returns 0 on success; fills up to 32 bytes.
int smc_read(const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type);
