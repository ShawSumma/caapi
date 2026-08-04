# Style

Rules for this codebase. Two kinds of entry appear here: rules that were stated
directly, and rules inferred by reading the code. Inferred ones are marked, and
are the ones most likely to be wrong.

The codebase does not fully follow this yet. Where existing code disagrees with
a rule, the rule wins.

## Formatting

Braces are never omitted. An `if`, `for`, `while` or `else` always has a block,
even for a single statement.

Do not align anything. No padding spaces to line up `=`, field names, comment
columns or anything else. One space either side of an operator.

A function call is either entirely on one line, or has one argument per line
with the closing parenthesis on its own line. Never partially split — never
some arguments on the first line and the rest wrapped underneath.

One thing per line. One statement, one declaration, one argument.

No cute one-liners. Clarity over brevity, always.

## Constructs

No `++` or `--`. Write `n = n + 1`.

No ternaries. Use `if` and `else`.

Never use classes. Structs only.

No `private`. Nothing is hidden.

No out parameters. A function returns its result.

Only `bool` is a boolean. Do not use an integer, a pointer or a count where a
boolean is meant, and do not test a non-boolean for truth.

## Globals

The only permitted globals are `static immutable` and `enum`. Nothing mutable
at module scope.

## Names

No name starts with an underscore. No name ends with an underscore.

One name per concept. If a thing is called `rps`, it is not also called
`cyclic` anywhere, including in command line arguments.

Enum members must carry meaning. `Side` running `A` through `L` and `Vertex`
running `A` through `T` in `common/dodeca.d` are the pattern to avoid: the
names say nothing about what the members are.

## Comments

No `///`. Use `//`.

Never use block comments. No `/* */` in any language.

No `---` or `===` inside a comment.

A comment line must read on its own. Do not wrap so that a continuation line
begins with a fragment, such as a line starting with a closing parenthesis of
a parenthetical opened on the line before.

Comments explain why, not what. A comment that restates the code, or that is
inaccurate, is worse than no comment.

## Language

This is D. It is not C written in D syntax, and it is not C++. Use the
language.

Do not use the garbage collector. Do not use anything outside `core.stdc`.

## C files

Every rule here applies to C sources as well. They are not exempt.

## Working practices

Do not use `/tmp` for anything.

Read files with the Read tool, in blocks. Do not read parts of files by other
means.

Do not use git.

Do not benchmark except with `ldc2` and optimisation enabled. Numbers from a
debug build are not measurements.

Do not assign provenance to anything not known for certain. Do not state who
wrote a piece of code, or when, or why it is there, on inference.

## Inferred from the code

These were read off existing sources rather than stated. Correct them if wrong.

Indent is four spaces, never tabs.

Opening brace goes on the same line as the thing it opens.

A module begins with its `module` declaration, then imports.

Imports are selective: `import common.math : Matrix4, MIsometry;` rather than
importing a whole module, except where the module is a package.

Types are PascalCase. Functions and variables are camelCase. Enum constants and
manifest constants are SCREAMING_SNAKE_CASE. Enum members that name a thing
rather than a constant are PascalCase.

Multi-line lists carry a trailing comma on the last element.
