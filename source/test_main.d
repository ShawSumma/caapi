module test_main;

// Entry point for the `unittest` configuration. The unittest blocks in the
// common modules run automatically before this returns; this just confirms the
// runner reached the end.
import std.stdio : writeln;

void main() {
    writeln("all unittests passed");
}
