/* Reproducer: emulate Cygwin's fork-child stack setup (child_info_fork::alloc_stack
   + dcrt0.cc TEB restore), then grow the stack through the guard pages with a
   large alloca (which __chkstk_ms probes page by page). */
#include <windows.h>
#include <winternl.h>
#include <stdio.h>
#include <string.h>
#include <malloc.h>

#define RESERVE   (2u << 20)
#define COMMITTED 0x4000u
#define GUARD     0x3000u

static size_t allocsz;

static __attribute__((noinline)) int deep(void)
{
    volatile char *p = alloca(allocsz);
    p[0] = 1;
    return p[0];
}

static __attribute__((noinline)) void report(const char *tag, char *base)
{
    for (char *a = base - COMMITTED - GUARD - 0x3000; a < base; a += 0x1000) {
        MEMORY_BASIC_INFORMATION mbi;
        VirtualQuery(a, &mbi, sizeof mbi);
        printf("%s %p state=%lx protect=%lx\n", tag, a, mbi.State, mbi.Protect);
    }
}

static char *stackaddr, *stackbase;
static void *saved_rsp;

static void __attribute__((noinline, used)) on_new_stack(void)
{
    NT_TIB *tib = (NT_TIB *) NtCurrentTeb();
    report("before", stackbase);
    printf("TEB StackBase=%p StackLimit=%p\n", tib->StackBase, tib->StackLimit);
    fflush(stdout);
    deep();
    report("after", stackbase);
    printf("STACKPROBE_OK\n");
    fflush(stdout);
}

int main(int argc, char **argv)
{
    allocsz = argc > 1 ? strtoul(argv[1], 0, 0) : 0x11000;
    stackaddr = VirtualAlloc(NULL, RESERVE, MEM_RESERVE, PAGE_NOACCESS);
    stackbase = stackaddr + RESERVE;
    char *limit = stackbase - COMMITTED;
    VirtualAlloc(limit, COMMITTED, MEM_COMMIT, PAGE_READWRITE);
    VirtualAlloc(limit - GUARD, GUARD, MEM_COMMIT, PAGE_READWRITE | PAGE_GUARD);

    NT_TIB *tib = (NT_TIB *) NtCurrentTeb();
    void *oldbase = tib->StackBase, *oldlimit = tib->StackLimit;
    void **dealloc = (void **)((char *) NtCurrentTeb() + 0x1478); /* TEB64.DeallocationStack */
    void *olddealloc = *dealloc;

    tib->StackBase = stackbase;
    tib->StackLimit = limit;
    *dealloc = stackaddr;

    __asm__ volatile (
        "movq %%rsp, %0\n\t"
        "movq %1, %%rsp\n\t"
        "subq $0x1000, %%rsp\n\t"
        "call on_new_stack\n\t"
        "movq %0, %%rsp\n\t"
        : "=m"(saved_rsp) : "r"(stackbase) : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "memory");

    tib->StackBase = oldbase;
    tib->StackLimit = oldlimit;
    *dealloc = olddealloc;
    return 0;
}
