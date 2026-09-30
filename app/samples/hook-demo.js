/*
 * The script the app starts with.
 *
 * demo_guard is the interesting one to watch: its first instruction is a conditional
 * branch, so the engine has to relocate it rather than copy its encoding. Before that
 * rewrite existed, hooking this function killed the host with an undefined
 * instruction; here the program should reach "done" with demo_guard(0) = -1 and
 * demo_guard(1) = 2.
 *
 * onLeave is deliberately absent. The engine calls it from the same trampoline that
 * calls onEnter, before the original function has run, so the "return value" it hands
 * over is the first argument - demo_work(3) reports 3 where 10 came back. Printing a
 * wrong number in a demo teaches the wrong thing, so the hook reports only what it
 * can report correctly: onEnter.
 */

const work = Module.findExportByName(null, "demo_work");
const guard = Module.findExportByName(null, "demo_guard");

console.log("[script] demo_work  is at " + work);
console.log("[script] demo_guard is at " + guard);

Interceptor.attach(work, {
  onEnter(args) {
    console.log("[script] demo_work called with " + args[0]);
  }
});

Interceptor.attach(guard, {
  onEnter(args) {
    console.log("[script] demo_guard called with " + args[0]);
  }
});

console.log("[script] both hooks are in place");
