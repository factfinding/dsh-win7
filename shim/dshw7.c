/*
 * dshw7.dll: Windows 8+ synchronization and RNG entry points for Windows 7.
 *
 * Binaries built by current Rust (librsvg inside libvips, pnpm's reflink module, ...)
 * import WaitOnAddress/WakeByAddress* from api-ms-win-core-synch-l1-2-0.dll and
 * ProcessPrng from bcryptprimitives.dll; Windows 7 has neither. scripts/patch-imports.ps1
 * renames those import DLLs to dshw7.dll. Every export calls the real API when the
 * running Windows has it, so behavior on Windows 8+ is unchanged.
 *
 * Fallbacks:
 *  - WaitOnAddress: addresses hash into buckets of SRWLOCK + CONDITION_VARIABLE. The
 *    comparison runs under the bucket lock and wakers take the same lock, so a wake
 *    that follows the waker's store cannot be lost. WakeByAddressSingle wakes the whole
 *    bucket: WaitOnAddress may return spuriously, and callers re-check the value.
 *  - ProcessPrng: RtlGenRandom (advapi32!SystemFunction036). ProcessPrng never fails,
 *    so a failing RtlGenRandom terminates the process instead of returning weak bytes.
 * The other synch-l1-2-0 imports are forwarded to kernel32 in dshw7.def.
 */
#include <windows.h>

typedef BOOL(WINAPI *wait_on_address_fn)(volatile VOID *, PVOID, SIZE_T, DWORD);
typedef VOID(WINAPI *wake_by_address_fn)(PVOID);
typedef BOOL(WINAPI *process_prng_fn)(PBYTE, SIZE_T);
typedef BOOLEAN(WINAPI *rtl_gen_random_fn)(PVOID, ULONG);

static INIT_ONCE resolve_once = INIT_ONCE_STATIC_INIT;
static wait_on_address_fn real_wait_on_address;
static wake_by_address_fn real_wake_by_address_single;
static wake_by_address_fn real_wake_by_address_all;
static process_prng_fn real_process_prng;
static rtl_gen_random_fn rtl_gen_random;

static BOOL CALLBACK resolve(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  HMODULE synch, prng, advapi;
  (void)once; (void)parameter; (void)context;
  /* Windows 8+ implements the synch-l1-2-0 address waits in KernelBase. */
  synch = GetModuleHandleW(L"kernelbase.dll");
  if (synch != NULL) {
    real_wait_on_address = (wait_on_address_fn)GetProcAddress(synch, "WaitOnAddress");
    real_wake_by_address_single = (wake_by_address_fn)GetProcAddress(synch, "WakeByAddressSingle");
    real_wake_by_address_all = (wake_by_address_fn)GetProcAddress(synch, "WakeByAddressAll");
  }
  if (real_wait_on_address == NULL || real_wake_by_address_single == NULL || real_wake_by_address_all == NULL) {
    real_wait_on_address = NULL;
    real_wake_by_address_single = NULL;
    real_wake_by_address_all = NULL;
  }
  prng = LoadLibraryExW(L"bcryptprimitives.dll", NULL, 0);
  if (prng != NULL) real_process_prng = (process_prng_fn)GetProcAddress(prng, "ProcessPrng");
  if (real_process_prng == NULL) {
    advapi = LoadLibraryExW(L"advapi32.dll", NULL, 0);
    if (advapi != NULL) rtl_gen_random = (rtl_gen_random_fn)GetProcAddress(advapi, "SystemFunction036");
  }
  return TRUE;
}

static void ensure_resolved(void) {
  InitOnceExecuteOnce(&resolve_once, resolve, NULL, NULL);
}

#define BUCKET_COUNT 256
static struct {
  SRWLOCK lock;
  CONDITION_VARIABLE changed;
} buckets[BUCKET_COUNT]; /* zero is SRWLOCK_INIT and CONDITION_VARIABLE_INIT */

static unsigned bucket_index(volatile VOID *address) {
  ULONG_PTR value = (ULONG_PTR)address;
  value ^= value >> 17;
  value *= (ULONG_PTR)0x9E3779B97F4A7C15ull;
  return (unsigned)(value >> (sizeof(ULONG_PTR) * 8 - 8)) & (BUCKET_COUNT - 1);
}

static BOOL still_equal(volatile VOID *address, PVOID compare, SIZE_T size) {
  switch (size) {
    case 1: return *(volatile BYTE *)address == *(BYTE *)compare;
    case 2: return *(volatile WORD *)address == *(WORD *)compare;
    case 4: return *(volatile DWORD *)address == *(DWORD *)compare;
    default: return *(volatile DWORD64 *)address == *(DWORD64 *)compare;
  }
}

BOOL WINAPI DshWaitOnAddress(volatile VOID *address, PVOID compare, SIZE_T size, DWORD milliseconds) {
  unsigned index;
  BOOL woken = TRUE;
  ensure_resolved();
  if (real_wait_on_address != NULL) return real_wait_on_address(address, compare, size, milliseconds);
  if (size != 1 && size != 2 && size != 4 && size != 8) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  index = bucket_index(address);
  AcquireSRWLockExclusive(&buckets[index].lock);
  if (still_equal(address, compare, size)) {
    /* FALSE with ERROR_TIMEOUT matches WaitOnAddress's timeout result. */
    woken = SleepConditionVariableSRW(&buckets[index].changed, &buckets[index].lock, milliseconds, 0);
  }
  ReleaseSRWLockExclusive(&buckets[index].lock);
  return woken;
}

static void wake_bucket(PVOID address) {
  unsigned index = bucket_index(address);
  AcquireSRWLockExclusive(&buckets[index].lock);
  WakeAllConditionVariable(&buckets[index].changed);
  ReleaseSRWLockExclusive(&buckets[index].lock);
}

VOID WINAPI DshWakeByAddressSingle(PVOID address) {
  ensure_resolved();
  if (real_wake_by_address_single != NULL) {
    real_wake_by_address_single(address);
    return;
  }
  wake_bucket(address);
}

VOID WINAPI DshWakeByAddressAll(PVOID address) {
  ensure_resolved();
  if (real_wake_by_address_all != NULL) {
    real_wake_by_address_all(address);
    return;
  }
  wake_bucket(address);
}

BOOL WINAPI DshProcessPrng(PBYTE data, SIZE_T length) {
  ensure_resolved();
  if (real_process_prng != NULL) return real_process_prng(data, length);
  while (length > 0) {
    ULONG chunk = length > 0x10000000 ? 0x10000000 : (ULONG)length;
    if (rtl_gen_random == NULL || !rtl_gen_random(data, chunk)) TerminateProcess(GetCurrentProcess(), ERROR_CRC);
    data += chunk;
    length -= chunk;
  }
  return TRUE;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
  return TRUE;
}
