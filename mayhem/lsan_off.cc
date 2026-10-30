// Build-time LeakSanitizer off-switch (ASan and the rest stay active); linked into the fuzz binary.
extern "C" int __lsan_is_turned_off() { return 1; }
