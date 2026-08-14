with AUnit.Assertions;

with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;

package body Jsonlib_Parser_Cases is

   use AUnit.Assertions;

   package Doc renames Jsonlib.Documents;
   package Err renames Jsonlib.Errors;
   package P renames Jsonlib.Parsers;

   use type Doc.Node;
   use type Doc.Value_Kind;
   use type Err.Error_Code;

   procedure Reads_Every_Kind (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Refuses_What_Is_Not_Json
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Reports_Where (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Decodes_Escapes (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Refuses_Lone_Surrogates
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Refuses_Bad_Encoding
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Duplicates_Follow_The_Policy
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Depth_Is_Bounded (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Failure_Leaves_Nothing_Behind
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Numbers_Keep_Their_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ------------------------
   -- Reads_Every_Kind --
   ------------------------

   procedure Reads_Every_Kind (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse
        ("{""a"":null,""b"":true,""c"":false,""d"":1,""e"":1.5,"
         & """f"":""x"",""g"":[1,2],""h"":{}}",
         Document, Error);

      Assert (not Err.Failed (Error),
              "a valid document failed with " & Err.Identifier (Error.Code));

      declare
         Root : constant Doc.Node := Doc.Root (Document);
      begin
         Assert (Doc.Kind (Document, Root) = Doc.Object_Value,
                 "the root was not an object");
         Assert (Doc.Length (Document, Root) = 8,
                 "the object had" & Natural'Image (Doc.Length (Document, Root))
                 & " members rather than 8");

         Assert (Doc.Kind (Document, Doc.Member (Document, Root, "a"))
                 = Doc.Null_Value, "a was not null");
         Assert (Doc.As_Boolean (Document, Doc.Member (Document, Root, "b")),
                 "b was not true");
         Assert (not Doc.As_Boolean (Document, Doc.Member (Document, Root, "c")),
                 "c was not false");
         Assert (Doc.As_Integer (Document, Doc.Member (Document, Root, "d")) = 1,
                 "d was not 1");
         Assert (Doc.As_Float (Document, Doc.Member (Document, Root, "e")) = 1.5,
                 "e was not 1.5");
         Assert (Doc.As_String (Document, Doc.Member (Document, Root, "f")) = "x",
                 "f was not x");
         Assert (Doc.Length (Document, Doc.Member (Document, Root, "g")) = 2,
                 "g did not have two elements");
         Assert (Doc.Length (Document, Doc.Member (Document, Root, "h")) = 0,
                 "h was not empty");

         --  Member order is the order they were written. RFC 8259 calls an
         --  object unordered, which is a statement about equality, not a
         --  licence to shuffle somebody's configuration file.
         Assert (Doc.Name (Document, Root, 1) = "a", "the first member moved");
         Assert (Doc.Name (Document, Root, 8) = "h", "the last member moved");

         --  Absence is a value, not an exception: asking whether a
         --  configuration has a key is the ordinary case.
         Assert (Doc.Member (Document, Root, "missing") = Doc.No_Node,
                 "a member that is not there was found");
      end;

      --  A bare scalar is a document too, since RFC 8259 -- unlike its
      --  predecessor -- allows any value at the top.
      P.Parse ("42", Document, Error);
      Assert (not Err.Failed (Error), "a bare number was refused");
      Assert (Doc.As_Integer (Document, Doc.Root (Document)) = 42,
              "the bare number was not 42");

      P.Parse ("""hello""", Document, Error);
      Assert (not Err.Failed (Error), "a bare string was refused");
      Assert (Doc.As_String (Document, Doc.Root (Document)) = "hello",
              "the bare string was not hello");
   end Reads_Every_Kind;

   ---------------------------------
   -- Refuses_What_Is_Not_Json --
   ---------------------------------

   procedure Refuses_What_Is_Not_Json
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Refused (Text : String; Code : Err.Error_Code);

      procedure Refused (Text : String; Code : Err.Error_Code) is
      begin
         P.Parse (Text, Document, Error);
         Assert (Err.Failed (Error), "accepted " & Text);
         Assert (Error.Code = Code,
                 Text & " failed with " & Err.Identifier (Error.Code)
                 & " rather than " & Err.Identifier (Code));
      end Refused;

   begin
      --  The five things every lenient parser accepts and JSON does not. Each
      --  one produces a document that another tool rejects, and the author
      --  finds out from somebody else's error message.
      Refused ("{""a"":1,}", Err.Trailing_Comma);
      Refused ("[1,2,]", Err.Trailing_Comma);
      Refused ("{a:1}", Err.Expected_Member_Name);
      Refused ("{'a':1}", Err.Expected_Member_Name);
      Refused ("[1] // a comment", Err.Trailing_Content);

      --  And the rest of the ways a document can be wrong.
      Refused ("", Err.Empty_Document);
      Refused ("   ", Err.Empty_Document);
      Refused ("{", Err.Unexpected_End);
      Refused ("[1", Err.Unexpected_End);
      Refused ("{""a""}", Err.Expected_Colon);
      Refused ("{""a"":1 ""b"":2}", Err.Expected_Comma_Or_End);
      Refused ("[1 2]", Err.Expected_Comma_Or_End);
      Refused ("tru", Err.Invalid_Literal);
      Refused ("nul", Err.Invalid_Literal);
      Refused ("[01]", Err.Invalid_Number);
      Refused ("[+1]", Err.Unexpected_Character);
      Refused ("[1e400]", Err.Number_Out_Of_Range);
      Refused ("""unclosed", Err.Unterminated_String);
      Refused ("""bad \q escape""", Err.Invalid_Escape);
      Refused ("""\u12""", Err.Invalid_Unicode_Escape);
      Refused ("{} {}", Err.Trailing_Content);
      Refused ("@", Err.Unexpected_Character);

      --  A byte-order mark is not part of JSON. Skipping it would mean this
      --  crate accepts documents RFC 8259 does not.
      Refused ([Character'Val (16#EF#), Character'Val (16#BB#),
                Character'Val (16#BF#), '{', '}'],
               Err.Unexpected_Character);
   end Refuses_What_Is_Not_Json;

   ----------------------
   -- Reports_Where --
   ----------------------

   procedure Reports_Where (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      Newline : constant Character := Character'Val (16#0A#);
   begin
      --  Three lines, with the fault on the third. A position that pointed at
      --  the start of the document, or at the end, would be no help at all to
      --  whoever has to fix the file.
      P.Parse ("{" & Newline & "  ""a"": 1," & Newline & "  ""b"": @" & Newline
               & "}",
               Document, Error);

      Assert (Err.Failed (Error), "a malformed document was accepted");
      Assert (Error.At_Position.Line = 3,
              "the error was reported on line"
              & Positive'Image (Error.At_Position.Line) & " rather than 3");
      Assert (Error.At_Position.Column = 8,
              "the error was reported at column"
              & Positive'Image (Error.At_Position.Column) & " rather than 8");

      --  Columns count characters, not bytes. An accented letter earlier in
      --  the line must not put every later error off by one.
      P.Parse ("[""" & Character'Val (16#C3#) & Character'Val (16#A9#)
               & """, @]",
               Document, Error);
      Assert (Err.Failed (Error), "a malformed document was accepted");
      Assert (Error.At_Position.Column = 7,
              "a multi-byte character moved the column to"
              & Positive'Image (Error.At_Position.Column)
              & " rather than 7");
   end Reports_Where;

   -------------------------
   -- Decodes_Escapes --
   -------------------------

   procedure Decodes_Escapes (Test : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Decodes (Text : String; Expected : String);

      procedure Decodes (Text : String; Expected : String) is
      begin
         P.Parse (Text, Document, Error);
         Assert (not Err.Failed (Error),
                 Text & " failed with " & Err.Identifier (Error.Code));
         Assert (Doc.As_String (Document, Doc.Root (Document)) = Expected,
                 Text & " decoded as "
                 & Doc.As_String (Document, Doc.Root (Document)));
      end Decodes;

   begin
      Decodes ("""\""""", """");
      Decodes ("""\\""", "\");
      Decodes ("""\/""", "/");
      Decodes ("""\b""", [1 => Character'Val (16#08#)]);
      Decodes ("""\f""", [1 => Character'Val (16#0C#)]);
      Decodes ("""\n""", [1 => Character'Val (16#0A#)]);
      Decodes ("""\r""", [1 => Character'Val (16#0D#)]);
      Decodes ("""\t""", [1 => Character'Val (16#09#)]);

      --  A code point in the basic plane, as one escape.
      Decodes ("""\u00e9""",
               [Character'Val (16#C3#), Character'Val (16#A9#)]);

      --  A code point above it, as a surrogate pair -- which is the only way
      --  JSON can write one.
      Decodes ("""\ud83d\ude00""",
               [Character'Val (16#F0#), Character'Val (16#9F#),
                Character'Val (16#98#), Character'Val (16#80#)]);

      --  Escapes and literal text side by side.
      Decodes ("""a\tb""",
               "a" & Character'Val (16#09#) & "b");
   end Decodes_Escapes;

   ---------------------------------
   -- Refuses_Lone_Surrogates --
   ---------------------------------

   procedure Refuses_Lone_Surrogates
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Refused (Text : String);

      procedure Refused (Text : String) is
      begin
         P.Parse (Text, Document, Error);
         Assert (Err.Failed (Error), "accepted the lone surrogate in " & Text);
         Assert (Error.Code = Err.Lone_Surrogate,
                 Text & " failed with " & Err.Identifier (Error.Code)
                 & " rather than a lone surrogate");
      end Refused;

   begin
      --  Half a pair is not text: it cannot be encoded as UTF-8 at all, so
      --  substituting a replacement character would corrupt the document
      --  quietly, and passing it through would produce bytes that are not
      --  UTF-8.
      Refused ("""\ud83d""");           --  a high surrogate and nothing after
      Refused ("""\ud83dx""");          --  a high surrogate and ordinary text
      Refused ("""\ude00""");           --  a low surrogate on its own
      Refused ("""\ud83d\u0041""");   --  a high surrogate then a plain letter
   end Refuses_Lone_Surrogates;

   ------------------------------
   -- Refuses_Bad_Encoding --
   ------------------------------

   procedure Refuses_Bad_Encoding
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Refused (Text : String; Code : Err.Error_Code);

      procedure Refused (Text : String; Code : Err.Error_Code) is
      begin
         P.Parse (Text, Document, Error);
         Assert (Err.Failed (Error), "accepted malformed bytes");
         Assert (Error.Code = Code,
                 "failed with " & Err.Identifier (Error.Code)
                 & " rather than " & Err.Identifier (Code));
      end Refused;

   begin
      --  A continuation byte with nothing in front of it.
      Refused (['"', Character'Val (16#A9#), '"'], Err.Invalid_Encoding);

      --  A lead byte with its continuation missing.
      Refused (['"', Character'Val (16#C3#), '"'], Err.Invalid_Encoding);

      --  An overlong encoding: the letter A written in two bytes. Accepting it
      --  is how a filter that checks for "/" gets past by something that
      --  decodes to "/" later.
      Refused (['"', Character'Val (16#C0#), Character'Val (16#AF#), '"'],
               Err.Invalid_Encoding);

      --  A surrogate half written directly as UTF-8.
      Refused (['"', Character'Val (16#ED#), Character'Val (16#A0#),
                Character'Val (16#80#), '"'],
               Err.Invalid_Encoding);

      --  A literal control character inside a string. RFC 8259 requires these
      --  to be escaped, and one here is almost always a missing quote.
      Refused (['"', Character'Val (16#0A#), '"'],
               Err.Unescaped_Control_Character);
   end Refuses_Bad_Encoding;

   -----------------------------------------
   -- Duplicates_Follow_The_Policy --
   -----------------------------------------

   procedure Duplicates_Follow_The_Policy
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      Text : constant String := "{""a"":1,""b"":2,""a"":3}";
   begin
      --  The default refuses. A document whose meaning depends on which
      --  duplicate the reader preferred is one nobody can reason about.
      P.Parse (Text, Document, Error);
      Assert (Err.Failed (Error), "a duplicate member was accepted by default");
      Assert (Error.Code = Err.Duplicate_Member,
              "the duplicate failed with " & Err.Identifier (Error.Code));

      --  Keeping both is for a tool inspecting a document rather than reading
      --  values out of it: a formatter has to see what is actually there.
      P.Parse (Text, Document, Error,
               (P.Default_Options with delta Duplicates => P.Keep_Duplicates));
      Assert (not Err.Failed (Error), "keeping duplicates still refused them");
      Assert (Doc.Length (Document, Doc.Root (Document)) = 3,
              "keeping duplicates gave"
              & Natural'Image (Doc.Length (Document, Doc.Root (Document)))
              & " members rather than 3");
      Assert (Doc.As_Integer
                (Document, Doc.Member (Document, Doc.Root (Document), "a")) = 1,
              "the first duplicate was not the one found by name");

      --  Last wins is what most readers do, and it keeps the member where it
      --  first appeared so a rewritten document is not reordered.
      P.Parse (Text, Document, Error,
               (P.Default_Options with delta Duplicates => P.Last_Wins));
      Assert (not Err.Failed (Error), "last-wins still refused a duplicate");
      Assert (Doc.Length (Document, Doc.Root (Document)) = 2,
              "last-wins gave"
              & Natural'Image (Doc.Length (Document, Doc.Root (Document)))
              & " members rather than 2");
      Assert (Doc.As_Integer
                (Document, Doc.Member (Document, Doc.Root (Document), "a")) = 3,
              "last-wins kept the first value");
      Assert (Doc.Name (Document, Doc.Root (Document), 1) = "a",
              "last-wins moved the member to the end");
   end Duplicates_Follow_The_Policy;

   -------------------------
   -- Depth_Is_Bounded --
   -------------------------

   procedure Depth_Is_Bounded (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      Deep : String (1 .. 2_000) := [others => '['];
   begin
      --  A few kilobytes of open brackets is a crash in any parser that
      --  recurses without a bound, and a document is usually something a
      --  program was handed rather than something it wrote.
      for Index in 1_001 .. 2_000 loop
         Deep (Index) := ']';
      end loop;

      P.Parse (Deep, Document, Error);
      Assert (Err.Failed (Error), "a thousand levels of nesting was accepted");
      Assert (Error.Code = Err.Depth_Exceeded,
              "deep nesting failed with " & Err.Identifier (Error.Code));

      --  And the bound is the caller's to set, because there is no answer that
      --  suits both a configuration file and a message off a network.
      P.Parse (Deep, Document, Error,
               (P.Default_Options with delta Max_Depth => 2_000));
      Assert (not Err.Failed (Error),
              "a raised limit still refused the document: "
              & Err.Identifier (Error.Code));
   end Depth_Is_Bounded;

   ----------------------------------------
   -- Failure_Leaves_Nothing_Behind --
   ----------------------------------------

   procedure Failure_Leaves_Nothing_Behind
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse ("{""a"":1}", Document, Error);
      Assert (not Err.Failed (Error), "a valid document failed");

      --  A failed parse leaves the document empty rather than half-built. A
      --  caller that forgot to check the error would otherwise read values out
      --  of a fragment and get plausible answers.
      P.Parse ("{""a"":1,""b"":", Document, Error);
      Assert (Err.Failed (Error), "a truncated document was accepted");
      Assert (Doc.Root (Document) = Doc.No_Node,
              "a failed parse left a root behind");
   end Failure_Leaves_Nothing_Behind;

   -------------------------------
   -- Numbers_Keep_Their_Text --
   -------------------------------

   procedure Numbers_Keep_Their_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse ("[1.0,1e2,1.500,-0]", Document, Error);
      Assert (not Err.Failed (Error), "a document of odd number forms failed");

      declare
         Root : constant Doc.Node := Doc.Root (Document);
      begin
         --  Every one of these is a float by its text even though every one is
         --  a whole number, and every one keeps the form its author wrote.
         --  This is what makes a read-modify-write of somebody else's file
         --  safe.
         Assert (Doc.Kind (Document, Doc.Element (Document, Root, 1))
                 = Doc.Float_Value, "1.0 was not a float");
         Assert (Doc.Literal (Document, Doc.Element (Document, Root, 1)) = "1.0",
                 "1.0 came back as "
                 & Doc.Literal (Document, Doc.Element (Document, Root, 1)));
         Assert (Doc.Literal (Document, Doc.Element (Document, Root, 2)) = "1e2",
                 "1e2 came back as "
                 & Doc.Literal (Document, Doc.Element (Document, Root, 2)));
         Assert (Doc.Literal (Document, Doc.Element (Document, Root, 3))
                 = "1.500",
                 "1.500 lost its trailing zeros");
         Assert (Doc.Literal (Document, Doc.Element (Document, Root, 4)) = "-0",
                 "-0 came back as "
                 & Doc.Literal (Document, Doc.Element (Document, Root, 4)));
      end;
   end Numbers_Keep_Their_Text;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Jsonlib.Parsers");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Reads_Every_Kind'Access,
                        "every kind of value reads back as itself");
      Register_Routine (T, Refuses_What_Is_Not_Json'Access,
                        "everything that is not JSON is refused, by name");
      Register_Routine (T, Reports_Where'Access,
                        "an error carries the line and column a reader can use");
      Register_Routine (T, Decodes_Escapes'Access,
                        "every escape JSON defines decodes to UTF-8");
      Register_Routine (T, Refuses_Lone_Surrogates'Access,
                        "half a surrogate pair is refused, not substituted");
      Register_Routine (T, Refuses_Bad_Encoding'Access,
                        "malformed UTF-8 is refused, including overlong forms");
      Register_Routine (T, Duplicates_Follow_The_Policy'Access,
                        "a repeated member name does what the caller asked");
      Register_Routine (T, Depth_Is_Bounded'Access,
                        "nesting is bounded, and the bound is the caller's");
      Register_Routine (T, Failure_Leaves_Nothing_Behind'Access,
                        "a failed parse leaves the document empty");
      Register_Routine (T, Numbers_Keep_Their_Text'Access,
                        "a number keeps the text it was written with");
   end Register_Tests;

end Jsonlib_Parser_Cases;
