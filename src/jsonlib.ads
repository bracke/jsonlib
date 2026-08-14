--  JSON, read and written exactly.
--
--  This crate is the one place JSON is parsed and written. It reads RFC 8259
--  and nothing else. That is the whole design, and it is worth stating plainly
--  because every JSON library drifts the same way:
--
--    * **no comments** -- JSON has none, and a file with them is not JSON;
--    * **no trailing commas**;
--    * **no unquoted or single-quoted keys**;
--    * **no NaN, Infinity or hexadecimal numbers**;
--    * **no leading zeros, no leading plus, no bare decimal point**.
--
--  A parser that quietly accepts more than the standard is not being helpful.
--  It produces documents that other tools reject, and the author finds out
--  from someone else's error message rather than from ours.
--
--  **Malformed input is never an exception.** A document that does not parse
--  is a fact about the input, not a defect in the program, so it comes back as
--  a structured refusal carrying a code and a position. Exceptions are
--  reserved for the program being wrong -- asking for the string value of a
--  number, say -- which is a bug at the call site and should stop.
--
--  **What was written is what comes back.** Numbers keep the text they were
--  written with, so `1.0` does not become `1` and `1e400` does not become
--  `Inf`. A document read and written again is byte for byte the same
--  document, which is what makes this safe to use on a file somebody else
--  maintains.
--
--  Its packages:
--
--    Jsonlib.Errors        what went wrong, as a code and a position
--    Jsonlib.Documents     the value model, and how to build one
--    Jsonlib.Parsers       text to a document
--    Jsonlib.Serializers   a document to text
--    Jsonlib.Pointers      RFC 6901, for reaching into a document by path
package Jsonlib is
   pragma Pure;

   --  This crate's version, as Alire records it.
   --
   --  Kept as a string rather than parsed into components: a consumer that
   --  wants to compare versions wants a version library, and one that wants to
   --  print it wants exactly this.
   Version : constant String := "0.1.0-dev";

end Jsonlib;
