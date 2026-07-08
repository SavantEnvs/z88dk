// Bake detect_leaks=0 into the ASan fuzz binary (Mayhem owns ASAN_OPTIONS at runtime).
__attribute__((weak)) const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
