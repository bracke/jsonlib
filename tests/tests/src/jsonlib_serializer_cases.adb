with AUnit.Assertions;

with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;

package body Jsonlib_Serializer_Cases is

   use AUnit.Assertions;

   package Doc renames Jsonlib.Documents;
   package Err renames Jsonlib.Errors;
   package P renames Jsonlib.Parsers;
   package S renames Jsonlib.Serializers;

   procedure Round_Trips_Byte_For_Byte
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Escapes_What_Must_Be_Escaped
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Pretty_Is_Readable_And_Reparses
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Sorting_Is_Optional_And_Stable
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Deep_Documents_Write_Out
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Built_Documents_Write
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   -----------------------------------
   -- Round_Trips_Byte_For_Byte --
   -----------------------------------

   procedure Round_Trips_Byte_For_Byte
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Round_Trip (Text : String);

      procedure Round_Trip (Text : String) is
      begin
         P.Parse (Text, Document, Error);
         Assert (not Err.Failed (Error),
                 Text & " failed with " & Err.Identifier (Error.Code));
         Assert (S.To_String (Document) = Text,
                 Text & " came back as " & S.To_String (Document));
      end Round_Trip;

   begin
      --  This is the property that makes it safe to read a file somebody else
      --  maintains, change one value, and write it back: everything the
      --  program did not touch is unchanged, down to the bytes.
      Round_Trip ("null");
      Round_Trip ("true");
      Round_Trip ("false");
      Round_Trip ("42");
      Round_Trip ("-0");
      Round_Trip ("1.0");
      Round_Trip ("1e2");
      Round_Trip ("1.500");
      Round_Trip ("-1.5E+300");
      Round_Trip ("""hello""");
      Round_Trip ("[]");
      Round_Trip ("{}");
      Round_Trip ("[1,2,3]");
      Round_Trip ("{""a"":1,""b"":[true,null]}");
      Round_Trip ("{""z"":1,""a"":2}");
   end Round_Trips_Byte_For_Byte;

   -----------------------------------------
   -- Escapes_What_Must_Be_Escaped --
   -----------------------------------------

   procedure Escapes_What_Must_Be_Escaped
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  The two that always have to be escaped.
      Assert (S.Escape ("a""b") = "a\""b",
              "a quote was not escaped: " & S.Escape ("a""b"));
      Assert (S.Escape ("a\b") = "a\\b",
              "a backslash was not escaped: " & S.Escape ("a\b"));

      --  Control characters, with the short forms where they exist.
      Assert (S.Escape ("a" & Character'Val (16#0A#) & "b") = "a\nb",
              "a newline was not escaped as \n");
      Assert (S.Escape ([1 => Character'Val (16#01#)]) = "\u0001",
              "an obscure control character was not escaped as \u");

      --  The solidus need not be escaped, and escaping it makes every URL in a
      --  document harder to read.
      Assert (S.Escape ("a/b") = "a/b",
              "a solidus was escaped: " & S.Escape ("a/b"));

      --  UTF-8 passes through by default, because JSON is UTF-8.
      declare
         Accented : constant String :=
           [Character'Val (16#C3#), Character'Val (16#A9#)];
      begin
         Assert (S.Escape (Accented) = Accented,
                 "UTF-8 was escaped when it did not need to be");
         Assert (S.Escape (Accented, Escape_Non_Ascii => True) = "\u00e9",
                 "asking for ASCII output did not escape: "
                 & S.Escape (Accented, Escape_Non_Ascii => True));
      end;

      --  Above the basic plane, escaping produces a surrogate pair, which is
      --  the only way JSON can write one.
      declare
         Grinning : constant String :=
           [Character'Val (16#F0#), Character'Val (16#9F#),
            Character'Val (16#98#), Character'Val (16#80#)];
      begin
         Assert (S.Escape (Grinning, Escape_Non_Ascii => True)
                 = "\ud83d\ude00",
                 "a character above the basic plane escaped as "
                 & S.Escape (Grinning, Escape_Non_Ascii => True));
      end;
   end Escapes_What_Must_Be_Escaped;

   -----------------------------------------
   -- Pretty_Is_Readable_And_Reparses --
   -----------------------------------------

   procedure Pretty_Is_Readable_And_Reparses
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Again    : Doc.Document;
      Error    : Err.Error_Info;

      Newline : constant Character := Character'Val (16#0A#);
   begin
      P.Parse ("{""a"":[1,2],""b"":{}}", Document, Error);
      Assert (not Err.Failed (Error), "the sample document failed to parse");

      declare
         Pretty : constant String :=
           S.To_String (Document, (S.Default_Options with delta Form => S.Pretty));
      begin
         Assert (Pretty =
                   "{" & Newline
                   & "  ""a"": [" & Newline
                   & "    1," & Newline
                   & "    2" & Newline
                   & "  ]," & Newline
                   & "  ""b"": {}" & Newline
                   & "}",
                 "pretty output was:" & Newline & Pretty);

         --  And it is still the same document. A formatter that produced
         --  something that did not parse, or that parsed differently, would be
         --  worse than none.
         P.Parse (Pretty, Again, Error);
         Assert (not Err.Failed (Error),
                 "pretty output did not parse: " & Err.Identifier (Error.Code));
         Assert (S.To_String (Again) = S.To_String (Document),
                 "pretty output parsed to a different document");
      end;

      --  An empty container stays on one line, because a line break inside it
      --  would be whitespace around nothing.
      P.Parse ("[]", Document, Error);
      Assert (S.To_String (Document,
                (S.Default_Options with delta Form => S.Pretty)) = "[]",
              "an empty array was broken across lines");
   end Pretty_Is_Readable_And_Reparses;

   --------------------------------------
   -- Sorting_Is_Optional_And_Stable --
   --------------------------------------

   procedure Sorting_Is_Optional_And_Stable
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse ("{""z"":1,""a"":2,""m"":3}", Document, Error);
      Assert (not Err.Failed (Error), "the sample document failed to parse");

      --  Off by default: reordering somebody's configuration file when a
      --  program rewrites it is rude, and the diff is unreadable.
      Assert (S.To_String (Document) = "{""z"":1,""a"":2,""m"":3}",
              "the default output was reordered: " & S.To_String (Document));

      Assert (S.To_String
                (Document,
                 (S.Default_Options with delta Sort_Members => True))
              = "{""a"":2,""m"":3,""z"":1}",
              "sorted output was "
              & S.To_String (Document,
                             (S.Default_Options with delta Sort_Members => True)));

      --  Sorting must not change the document it is writing: asking twice, once
      --  each way, has to give both answers.
      Assert (S.To_String (Document) = "{""z"":1,""a"":2,""m"":3}",
              "sorting the output reordered the document itself");

      --  And it reaches nested objects too, since a canonical form that
      --  stopped at the top level would not be one.
      P.Parse ("{""b"":{""y"":1,""x"":2},""a"":3}", Document, Error);
      Assert (S.To_String
                (Document,
                 (S.Default_Options with delta Sort_Members => True))
              = "{""a"":3,""b"":{""x"":2,""y"":1}}",
              "nested members were not sorted");
   end Sorting_Is_Optional_And_Stable;

   -----------------------------------
   -- Deep_Documents_Write_Out --
   -----------------------------------

   procedure Deep_Documents_Write_Out
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      Levels : constant := 5_000;
      Deep   : String (1 .. Levels * 2) := [others => '['];
   begin
      for Index in Levels + 1 .. Levels * 2 loop
         Deep (Index) := ']';
      end loop;

      P.Parse (Deep, Document, Error,
               (P.Default_Options with delta Max_Depth => Levels));
      Assert (not Err.Failed (Error),
              "the deep document failed to parse: "
              & Err.Identifier (Error.Code));

      --  The serializer walks with an explicit stack rather than recursing, so
      --  a document this deep writes out instead of exhausting the stack. That
      --  is the reason writing has no failure mode at all.
      Assert (S.To_String (Document) = Deep,
              "a deeply nested document did not write back as itself");
   end Deep_Documents_Write_Out;

   -------------------------------
   -- Built_Documents_Write --
   -------------------------------

   procedure Built_Documents_Write
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;

      Root  : constant Doc.Node := Doc.New_Object (Document);
      Items : constant Doc.Node := Doc.New_Array (Document);
   begin
      Doc.Append (Document, Items, Doc.New_Integer (Document, 1));
      Doc.Append (Document, Items, Doc.New_String (Document, "two"));
      Doc.Append (Document, Items, Doc.New_Boolean (Document, True));

      Doc.Insert (Document, Root, "name", Doc.New_String (Document, "adash"));
      Doc.Insert (Document, Root, "items", Items);
      Doc.Set_Root (Document, Root);

      Assert (S.To_String (Document)
              = "{""name"":""adash"",""items"":[1,""two"",true]}",
              "a built document wrote as " & S.To_String (Document));

      --  Replacing keeps the member where it was, so rewriting one value does
      --  not reorder the file.
      Doc.Set_Member (Document, Root, "name",
                      Doc.New_String (Document, "renamed"));
      Assert (S.To_String (Document)
              = "{""name"":""renamed"",""items"":[1,""two"",true]}",
              "replacing a member moved it: " & S.To_String (Document));

      Assert (Doc.Remove_Member (Document, Root, "items"),
              "removing a member that exists reported failure");
      Assert (S.To_String (Document) = "{""name"":""renamed""}",
              "after removal the document was " & S.To_String (Document));
      Assert (not Doc.Remove_Member (Document, Root, "items"),
              "removing a member twice reported success");
   end Built_Documents_Write;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Jsonlib.Serializers");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Round_Trips_Byte_For_Byte'Access,
                        "a parsed document writes back byte for byte");
      Register_Routine (T, Escapes_What_Must_Be_Escaped'Access,
                        "escaping covers what JSON requires and no more");
      Register_Routine (T, Pretty_Is_Readable_And_Reparses'Access,
                        "pretty output is indented and parses to the same thing");
      Register_Routine (T, Sorting_Is_Optional_And_Stable'Access,
                        "sorting is off by default and does not touch the document");
      Register_Routine (T, Deep_Documents_Write_Out'Access,
                        "a deeply nested document writes out rather than crashing");
      Register_Routine (T, Built_Documents_Write'Access,
                        "a document built by hand writes as it was built");
   end Register_Tests;

end Jsonlib_Serializer_Cases;
