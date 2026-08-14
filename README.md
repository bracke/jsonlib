# jsonlib

JSON, read and written exactly.

`jsonlib` reads [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) and nothing
else. No comments, no trailing commas, no unquoted keys, no single quotes, no
`NaN`, no hexadecimal, no leading zeros. There is no lenient mode and there will
not be one: a parser that quietly accepts more than the standard produces
documents that other tools reject, and the author finds out from somebody else's
error message rather than from ours.

## What it guarantees

**Malformed input is never an exception.** A document that does not parse is a
fact about the input, not a defect in the program, so it comes back as a
structured refusal carrying a code and a line and column. Exceptions are for the
program being wrong — asking a number for its string value — which is a bug at
the call site and should stop.

**What was written comes back.** Numbers keep the text they were written with,
so `1.0` does not become `1`, `1.500` keeps its zeros, and `0` is not confused
with `-0`. Object members keep their order. A document read and written again is
byte for byte the same document, which is what makes it safe to read a file
somebody else maintains, change one value, and write it back.

**Writing cannot fail.** There is no error result and no exception: the walk is
iterative, so a document nested ten thousand deep writes out instead of
exhausting the stack.

## Using it

```ada
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Pointers;
with Jsonlib.Serializers;

procedure Example is
   Document : Jsonlib.Documents.Document;
   Error    : Jsonlib.Errors.Error_Info;
begin
   Jsonlib.Parsers.Parse ("{""port"": 8080}", Document, Error);

   if Jsonlib.Errors.Failed (Error) then
      --  Render Jsonlib.Errors.Identifier (Error.Code) through your catalog,
      --  with Error.At_Position.Line and .Column.
      return;
   end if;

   declare
      Port : constant Jsonlib.Documents.Node :=
        Jsonlib.Pointers.Resolve (Document, "/port");
   begin
      if Jsonlib.Documents.Is_Present (Port) then
         --  Jsonlib.Documents.As_Integer (Document, Port) = 8080
         null;
      end if;
   end;
end Example;
```

## Packages

| Package | What it owns |
|---|---|
| `Jsonlib.Errors` | What went wrong, as a code and a position. Never a sentence. |
| `Jsonlib.Numbers` | JSON's number grammar, which is narrower than most people remember. |
| `Jsonlib.Documents` | The value model: an arena, so a document is one object with one lifetime. |
| `Jsonlib.Parsers` | Text to a document, with the two implementation-defined choices exposed. |
| `Jsonlib.Serializers` | A document to text, compact or indented. |
| `Jsonlib.Pointers` | RFC 6901, for reaching into a document by path. |

## What the caller decides

RFC 8259 leaves two things to the implementation, and both are options rather
than decisions made here:

- **What a repeated member name means.** The default refuses the document,
  because one whose meaning depends on which duplicate the reader preferred is
  one nobody can reason about. `Keep_Duplicates` and `Last_Wins` are there for
  tools that need them.
- **How deep is too deep.** There is no answer that suits both a configuration
  file and a message off a network, so `Max_Depth` is the caller's.

## Building

```
alr build
cd tests && alr build && ./bin/jsonlib_tests
```

Ada 2022, no dependencies beyond the compiler.
