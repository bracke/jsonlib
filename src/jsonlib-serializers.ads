with Jsonlib.Documents;

--  A document to text.
--
--  **Writing cannot fail.** There is no error result here and no exception to
--  catch, because every document that can be built is a document that can be
--  written: numbers keep the text they were parsed from, strings are escaped
--  rather than refused, and the walk is iterative rather than recursive, so a
--  document nested ten thousand deep writes out instead of exhausting the
--  stack. A serializer that could fail would make every caller handle a case
--  that need not exist.
--
--  **What was read comes back.** With the default settings, writing a document
--  that was just parsed gives back the same bytes -- the same number forms, the
--  same member order, the same escapes where escapes are required. That is what
--  makes it safe to read a file somebody else maintains, change one value, and
--  write it back.
package Jsonlib.Serializers is

   --  How the text is laid out.
   type Layout is
     (
      --  No whitespace at all. For anything a machine reads.
      Compact,

      --  Indented, one value to a line. For anything a person reads, and for
      --  anything kept under version control, where a compact document makes
      --  every change look like the whole file changed.
      Pretty);

   --  How to write.
   type Options is record
      Form : Layout := Compact;

      --  Spaces per level, for Pretty. Zero is allowed and gives line breaks
      --  without indentation, which some tools prefer.
      Indent : Natural := 2;

      --  Escape every character above ASCII as \u. JSON is UTF-8 and does not
      --  need this; some consumers on the far side of an old pipe do. Off by
      --  default, because escaping text that did not need it makes a document
      --  larger and much harder to read.
      Escape_Non_Ascii : Boolean := False;

      --  Write object members in name order rather than in the order they
      --  appear. For producing a document that can be compared byte for byte
      --  with another. Off by default: reordering somebody's configuration
      --  file when a program rewrites it is rude, and the diff is unreadable.
      Sort_Members : Boolean := False;
   end record;

   --  Compact, in document order, escaping only what must be escaped.
   Default_Options : constant Options :=
     (Form => Compact, Indent => 2,
      Escape_Non_Ascii => False, Sort_Members => False);

   --  Write a whole document.
   --
   --  @param From The document.
   --  @param Settings How to write.
   --  @return The text, as UTF-8, or "" when the document has no root.
   function To_String
     (From     : Jsonlib.Documents.Document;
      Settings : Options := Default_Options) return String;

   --  Write one value out of a document.
   --
   --  @param From The document.
   --  @param Item The value.
   --  @param Settings How to write.
   --  @return The text, as UTF-8, or "" when Item is absent.
   function To_String
     (From     : Jsonlib.Documents.Document;
      Item     : Jsonlib.Documents.Node;
      Settings : Options := Default_Options) return String;

   --  Escape a string the way JSON requires, without the surrounding quotes.
   --
   --  Exposed because callers building text around a document -- a log line, a
   --  query string -- need the same escaping, and a second implementation of
   --  it is a second set of bugs.
   --
   --  @param Item The text, as UTF-8.
   --  @param Escape_Non_Ascii True to escape everything above ASCII as \u.
   --  @return The escaped text.
   function Escape (Item : String; Escape_Non_Ascii : Boolean := False)
                    return String;

end Jsonlib.Serializers;
