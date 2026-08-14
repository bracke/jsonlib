--  What went wrong, as a code and a position.
--
--  Never a sentence. A library that returned English would decide the wording
--  for every consumer, in a language it has no way of knowing is the reader's,
--  and would make every diagnostic untestable except by string comparison. A
--  code and a position can be rendered, translated, counted, compared and
--  asserted on.
--
--  The positions are the ones a reader can act on: a line and a column that
--  match what an editor shows, and a byte offset for a tool that is indexing
--  the file rather than looking at it. Columns count characters, not bytes, so
--  a document with an accented character earlier in the line does not report a
--  column that is off by one for every error after it.
package Jsonlib.Errors is

   --  What was wrong with the input.
   --
   --  Flat and specific. A single "syntax error" code would be honest about
   --  the parser and useless to the reader: the difference between a missing
   --  comma and an unterminated string is exactly the information they need.
   type Error_Code is
     (
      --  Nothing went wrong. Present so a result value is always meaningful,
      --  and so a caller that checks the code rather than a separate Boolean
      --  is not writing a bug.
      No_Error,

      --  The document ended in the middle of something.
      Unexpected_End,

      --  A byte that cannot start any value here.
      Unexpected_Character,

      --  Text after the end of the top-level value. A second document
      --  concatenated to the first is the usual cause, and silently ignoring
      --  it would mean reading half of somebody's file.
      Trailing_Content,

      --  The document contained nothing at all.
      Empty_Document,

      --  A string was not closed before the line or the document ended.
      Unterminated_String,

      --  A backslash followed by something that is not an escape.
      Invalid_Escape,

      --  A \u escape whose four digits are not four hexadecimal digits.
      Invalid_Unicode_Escape,

      --  A \u escape naming half of a surrogate pair with no matching half.
      --  Refused rather than replaced: a lone surrogate cannot be encoded as
      --  UTF-8, and substituting a replacement character would corrupt the
      --  document silently.
      Lone_Surrogate,

      --  A control character written literally inside a string. RFC 8259
      --  requires these to be escaped, and passing one through would produce a
      --  document other parsers reject.
      Unescaped_Control_Character,

      --  Bytes that are not valid UTF-8.
      Invalid_Encoding,

      --  A number written in a form JSON does not define: a leading zero, a
      --  leading plus, a bare decimal point, a missing exponent digit, or one
      --  of the names some parsers accept and the standard does not.
      Invalid_Number,

      --  A number too large for this host's integer or float type. Reported
      --  rather than saturated: a configuration value that silently became the
      --  largest representable number is worse than one that was refused.
      Number_Out_Of_Range,

      --  A literal that begins like true, false or null and is not one.
      Invalid_Literal,

      --  An object member with no name, or a name that is not a string.
      Expected_Member_Name,

      --  A colon was expected between a member name and its value.
      Expected_Colon,

      --  A comma or a closing bracket was expected.
      Expected_Comma_Or_End,

      --  A comma with nothing after it. Trailing commas are not JSON, however
      --  many parsers allow them.
      Trailing_Comma,

      --  The same name twice in one object, where the caller asked for that to
      --  be refused. RFC 8259 leaves it undefined, which is precisely why a
      --  caller has to be able to say what it means.
      Duplicate_Member,

      --  Nesting deeper than the limit the caller set. A bound exists because
      --  a document is often something a program was handed rather than
      --  something it wrote, and unbounded nesting is unbounded recursion.
      Depth_Exceeded,

      --  The document was longer than the caller allowed.
      Document_Too_Large);

   --  Where in the document.
   type Position is record
      --  Byte offset from one. Zero when the error has no position -- an empty
      --  document, for instance, has nowhere to point at.
      Offset : Natural := 0;

      --  Line from one.
      Line : Positive := 1;

      --  Column from one, counted in characters rather than bytes.
      Column : Positive := 1;
   end record;

   --  A position that points nowhere.
   Nowhere : constant Position := (Offset => 0, Line => 1, Column => 1);

   --  What went wrong, and where.
   type Error_Info is record
      Code : Error_Code := No_Error;
      At_Position : Position := Nowhere;
   end record;

   --  Nothing went wrong.
   No_Error_Info : constant Error_Info :=
     (Code => No_Error, At_Position => Nowhere);

   --  @param Item The result to test.
   --  @return True when it records a failure.
   function Failed (Item : Error_Info) return Boolean is
     (Item.Code /= No_Error);

   --  A stable identifier for a code, for a message catalog to key on.
   --
   --  Lower case with dots, and stable across releases: a consumer's catalog
   --  keys on these, and renaming one would silently turn a translated message
   --  back into a fallback.
   --
   --  @param Code The code to name.
   --  @return Its identifier, for example "json.error.trailing-content".
   function Identifier (Code : Error_Code) return String;

end Jsonlib.Errors;
