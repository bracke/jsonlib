# AGENTS.md

Guidance for AI agents working in this repository. **This file is the canonical
copy** and applies to every AI coding tool; `CLAUDE.md` imports it so Claude
Code sees the same text. Edit this file, not that one.

## What this is

jsonlib is an Ada 2022 library that reads and writes
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) JSON, and nothing else. It
has no dependencies beyond the compiler: no host layer, no allocator of its
own, no configuration.

Its consumers read files other people maintain — a shell's history, a
manifest, a settings store — change one value and write the file back. That is
the use that decides most of the design here.

## Build, test, verify

Built with [Alire](https://alire.ada.dev/) (`alr`), pinned to
`gnat_native = "=15.2.1"`.

```sh
alr build                                    # the library
cd tests && alr build && ./bin/jsonlib_tests # the suite
cd check_jsonlib && alr build && ./bin/check_jsonlib   # the release gate
```

The gate is not optional before a release. CI runs all three on Linux, macOS
and Windows; a rule that only one host exercises is a rule that breaks on the
other two without anybody hearing about it.

## The rules that govern every change

1. **Malformed input is never an exception.** A document that does not parse is
   a fact about the input, so it comes back as a refusal carrying a code, a
   line and a column. Exceptions are for the program being wrong — asking a
   number for its string value — which is a bug at the call site and should
   stop. Adding a `raise` on a parse path is the one change most likely to be
   wrong here.

2. **What was written comes back.** Numbers keep the text they were written
   with, member order is preserved, and a document read and written again is
   byte for byte the same document. `1.0` must not become `1`, `1.500` keeps
   its zeros, and `0` is not `-0`. Any change that normalises a value on the
   way in breaks the use this library exists for.

3. **Writing cannot fail.** No error result, no exception, and the walk is
   iterative so that a document nested ten thousand deep writes out instead of
   exhausting the stack. A recursive serializer is a stack overflow waiting for
   somebody else's input.

4. **No lenient mode, ever.** No comments, no trailing commas, no unquoted
   keys, no single quotes, no `NaN`, no hexadecimal, no leading zeros. A parser
   that accepts more than the standard produces documents other tools reject,
   and its author finds out from somebody else's error message rather than from
   ours.

5. **Every refusal is documented.** `docs/refusals.md` lists every code with
   what it means, and the release gate checks that list against
   `src/jsonlib-errors.ads` in both directions. A code without a row, or a row
   without a code, fails the build rather than drifting.

6. **Bounds are the caller's.** Depth and document size are limits the caller
   sets, not constants this library chose. What this library must never do is
   exceed them quietly.

## What to do when something is wrong

Make the failure say more before reasoning about the cause. Every defect fixed
here so far was found by a test that reported what it saw rather than that it
was unhappy — a position, a byte, a count — and the ones that took longest were
the ones whose message named a symptom instead.
