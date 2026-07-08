// Turn LeakSanitizer OFF at BUILD time for the z80asm fuzz/repro binary.
//
// This is not housekeeping — it is the fix for the critical error that failed Mayhem run #4
// ("the target times out on every test case in the test suite and on the default test case").
//
// LeakSanitizer's end-of-process check suspends the process with ptrace, and it cannot do that
// when something is already tracing the target. Mayhem's fuzzing phase runs the target under its
// own tracer, so the leak check hits a fatal error on EVERY exec, whatever the input — which is
// why even Mayhem's trivial built-in default test case "timed out", while the untraced phases
// (smoketest, regression testing) sailed through. Reproduced locally with a 20-line
// PTRACE_TRACEME/PTRACE_CONT parent around the same binary:
//
//     untraced : rc=0 in 8ms
//     traced   : "LeakSanitizer has encountered a fatal error."
//                "HINT: LeakSanitizer does not work under ptrace (strace, gdb, etc)"
//                and the tracee dies instead of completing
//
// The hook below is read by the LSan runtime before it does any of that, so the check never runs
// and there is nothing to collide with. It has to be a linked-in hook rather than a suggested
// runtime default: Mayhem owns the target's sanitizer option string in the cloud, so a default the
// harness merely proposes is replaced there and leak detection quietly comes back on while still
// looking disabled locally. (The previous harness tried exactly that and it did not hold.)
//
// Fleet policy points the same way: leaks are not the bug class this target is fuzzed for, and
// -fsanitize=address always bundles LSan in with no flag to keep one and drop the other.
//
// ASan and UBSan stay fully ON and halting; only leak reporting is disabled.
extern "C" int __lsan_is_turned_off(void) { return 1; }
