with Jsonlib.Documents;
with Jsonlib.Errors;

--  Text to a document.
--
--  Strictly RFC 8259, with the two things the standard deliberately leaves to
--  the implementation exposed as choices rather than decided here:
--
--    * what a repeated member name means. The standard calls the behaviour
--      undefined, which is exactly why a caller has to be able to say;
--    * how deep is too deep. There is no answer that suits both a
--      configuration file and a message from a network.
--
--  Everything else is fixed, because everything else is defined. In
--  particular this parser does not accept comments, trailing commas, single
--  quotes, unquoted names, hexadecimal numbers, leading zeros, leading pluses,
--  NaN or Infinity -- not as an option, not with a flag. A "lenient mode"
--  would mean documents that this crate reads and other tools do not, and the
--  author would find out from somebody else.
package Jsonlib.Parsers is

   --  What a repeated member name means.
   type Duplicate_Policy is
     (
      --  Refuse the document. The safe default: a document whose meaning
      --  depends on which duplicate the reader preferred is one nobody can
      --  reason about, and silently choosing is how a configuration ends up
      --  doing something its author did not write.
      Refuse_Duplicates,

      --  Keep both, in order. For a tool inspecting or rewriting a document
      --  rather than reading values out of it -- a formatter has to be able to
      --  see what is actually there.
      Keep_Duplicates,

      --  Keep the last. What most JSON readers do, and what a caller reading a
      --  document written by one of them will want.
      Last_Wins);

   --  How to read.
   type Options is record
      --  How deeply values may nest. A bound exists because a document is
      --  usually something a program was handed rather than something it
      --  wrote, and unbounded nesting is unbounded recursion: a few kilobytes
      --  of open brackets is a crash otherwise.
      Max_Depth : Positive := 64;

      --  How many bytes the document may be. Zero means no limit.
      Max_Length : Natural := 0;

      --  What a repeated member name means.
      Duplicates : Duplicate_Policy := Refuse_Duplicates;
   end record;

   --  Sensible for a configuration file read off disk.
   Default_Options : constant Options :=
     (Max_Depth => 64, Max_Length => 0, Duplicates => Refuse_Duplicates);

   --  Read a document.
   --
   --  @param Text The document, as UTF-8. A byte-order mark is not part of
   --         JSON and is refused rather than skipped: skipping it would mean
   --         this crate accepts documents that RFC 8259 does not.
   --  @param Into The document. Emptied first, and left empty when the parse
   --         fails -- a half-built document is worse than none, because a
   --         caller that forgot to check the error would read from it.
   --  @param Error What went wrong, or No_Error_Info.
   --  @param Settings How to read.
   procedure Parse
     (Text     : String;
      Into     : in out Jsonlib.Documents.Document;
      Error    : out Jsonlib.Errors.Error_Info;
      Settings : Options := Default_Options);

end Jsonlib.Parsers;
