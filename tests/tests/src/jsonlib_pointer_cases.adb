with AUnit.Assertions;

with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Pointers;

package body Jsonlib_Pointer_Cases is

   use AUnit.Assertions;

   package Doc renames Jsonlib.Documents;
   package Err renames Jsonlib.Errors;
   package P renames Jsonlib.Parsers;
   package Ptr renames Jsonlib.Pointers;

   use type Doc.Node;

   --  The example document from RFC 6901, which is the only way to be sure the
   --  odd cases -- an empty name, a name that is a number, names containing
   --  the two escaped characters -- are read the way the standard says.
   Sample : constant String :=
     "{""foo"":[""bar"",""baz""],"""":0,""a/b"":1,""c%d"":2,""e^f"":3,"
     & """g|h"":4,""i\\j"":5,""k\""l"":6,"" "":7,""m~n"":8}";

   procedure Resolves_The_Standard_Examples
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Absence_Is_Not_An_Error
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Malformed_Pointers_Are_Told_Apart
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Indices_Are_Zero_Based_And_Strict
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Escaping_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------
   -- Resolves_The_Standard_Examples --
   ---------------------------------------

   procedure Resolves_The_Standard_Examples
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;

      procedure Finds_Integer (Path : String; Expected : Long_Long_Integer);

      procedure Finds_Integer (Path : String; Expected : Long_Long_Integer) is
         Found : constant Doc.Node := Ptr.Resolve (Document, Path);
      begin
         Assert (Doc.Is_Present (Found), "the pointer " & Path & " found nothing");
         Assert (Doc.As_Integer (Document, Found) = Expected,
                 Path & " found"
                 & Long_Long_Integer'Image (Doc.As_Integer (Document, Found))
                 & " rather than" & Long_Long_Integer'Image (Expected));
      end Finds_Integer;

   begin
      P.Parse (Sample, Document, Error);
      Assert (not Err.Failed (Error),
              "the sample document failed: " & Err.Identifier (Error.Code));

      --  The empty pointer names the document itself.
      Assert (Ptr.Resolve (Document, "") = Doc.Root (Document),
              "the empty pointer did not name the document");

      Assert (Doc.Length (Document, Ptr.Resolve (Document, "/foo")) = 2,
              "/foo did not find the two-element array");
      Assert (Doc.As_String (Document, Ptr.Resolve (Document, "/foo/0")) = "bar",
              "/foo/0 did not find bar");
      Assert (Doc.As_String (Document, Ptr.Resolve (Document, "/foo/1")) = "baz",
              "/foo/1 did not find baz");

      --  A member whose name is empty. Legal JSON, and a pointer of a single
      --  slash is how it is named.
      Finds_Integer ("/", 0);

      --  The two escapes, and the characters that look like they need escaping
      --  and do not.
      Finds_Integer ("/a~1b", 1);
      Finds_Integer ("/c%d", 2);
      Finds_Integer ("/e^f", 3);
      Finds_Integer ("/g|h", 4);
      Finds_Integer ("/i\j", 5);
      Finds_Integer ("/k""l", 6);
      Finds_Integer ("/ ", 7);
      Finds_Integer ("/m~0n", 8);
   end Resolves_The_Standard_Examples;

   -----------------------------------
   -- Absence_Is_Not_An_Error --
   -----------------------------------

   procedure Absence_Is_Not_An_Error
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse ("{""a"":{""b"":1},""s"":""text""}", Document, Error);
      Assert (not Err.Failed (Error), "the sample document failed");

      --  Asking whether a configuration has a value at a path is the ordinary
      --  use. A program that had to catch something to find out "no" would be
      --  worse to write and worse to read.
      Assert (Ptr.Resolve (Document, "/missing") = Doc.No_Node,
              "a member that is not there was found");
      Assert (Ptr.Resolve (Document, "/a/missing") = Doc.No_Node,
              "a nested member that is not there was found");

      --  A path that goes on past a scalar. Not an error either: a
      --  configuration is allowed to hold a string where another holds an
      --  object.
      Assert (Ptr.Resolve (Document, "/s/deeper") = Doc.No_Node,
              "a path through a string found something");

      --  Relative resolution starts where it is told.
      declare
         Inner : constant Doc.Node := Ptr.Resolve (Document, "/a");
      begin
         Assert (Doc.As_Integer (Document, Ptr.Resolve (Document, Inner, "/b"))
                 = 1,
                 "a relative pointer did not resolve");
         Assert (Ptr.Resolve (Document, Inner, "") = Inner,
                 "an empty relative pointer did not name its base");
      end;
   end Absence_Is_Not_An_Error;

   -------------------------------------------
   -- Malformed_Pointers_Are_Told_Apart --
   -------------------------------------------

   procedure Malformed_Pointers_Are_Told_Apart
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      --  "You typed the path wrong" and "there is nothing there" are different
      --  things to tell a user, and only the first is their mistake.
      Assert (Ptr.Is_Valid (""), "the empty pointer was called malformed");
      Assert (Ptr.Is_Valid ("/a"), "a plain pointer was called malformed");
      Assert (Ptr.Is_Valid ("/a~0b"), "a tilde escape was called malformed");
      Assert (Ptr.Is_Valid ("/a~1b"), "a slash escape was called malformed");

      --  Not starting with a slash. The single commonest mistake, and one a
      --  parser that guessed would turn into a silent wrong answer.
      Assert (not Ptr.Is_Valid ("a"), "a pointer with no leading slash passed");
      Assert (not Ptr.Is_Valid ("a/b"), "a path-like string passed");

      --  A bare tilde. Guessing which of the two characters the author meant
      --  would be worse than telling them.
      Assert (not Ptr.Is_Valid ("/a~b"), "a bare tilde passed");
      Assert (not Ptr.Is_Valid ("/a~"), "a trailing tilde passed");
      Assert (not Ptr.Is_Valid ("/a~2b"), "an unknown escape passed");
   end Malformed_Pointers_Are_Told_Apart;

   -------------------------------------------
   -- Indices_Are_Zero_Based_And_Strict --
   -------------------------------------------

   procedure Indices_Are_Zero_Based_And_Strict
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      P.Parse ("[10,20,30]", Document, Error);
      Assert (not Err.Failed (Error), "the sample document failed");

      --  Zero-based, as RFC 6901 says, even though everything else in this
      --  crate counts from one. Making them one-based here would mean pointers
      --  written against any other tool silently address the wrong element.
      Assert (Doc.As_Integer (Document, Ptr.Resolve (Document, "/0")) = 10,
              "index 0 did not find the first element");
      Assert (Doc.As_Integer (Document, Ptr.Resolve (Document, "/2")) = 30,
              "index 2 did not find the third element");
      Assert (Ptr.Resolve (Document, "/3") = Doc.No_Node,
              "an index past the end found something");

      --  And strictly: none of these is an index, and treating one as an index
      --  would silently address an element the author did not name.
      Assert (Ptr.Resolve (Document, "/01") = Doc.No_Node,
              "a leading zero was treated as an index");
      Assert (Ptr.Resolve (Document, "/-") = Doc.No_Node,
              "the append token was treated as an index");
      Assert (Ptr.Resolve (Document, "/1x") = Doc.No_Node,
              "a number with a suffix was treated as an index");
      Assert (Ptr.Resolve (Document, "/") = Doc.No_Node,
              "an empty token was treated as an index");
   end Indices_Are_Zero_Based_And_Strict;

   -------------------------------
   -- Escaping_Round_Trips --
   -------------------------------

   procedure Escaping_Round_Trips
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Document : Doc.Document;
      Error    : Err.Error_Info;
   begin
      --  A pointer built from names that came from data has to escape them: a
      --  member called a/b written raw would produce a pointer naming two
      --  levels.
      Assert (Ptr.Escape_Token ("a/b") = "a~1b",
              "a slash escaped as " & Ptr.Escape_Token ("a/b"));
      Assert (Ptr.Escape_Token ("m~n") = "m~0n",
              "a tilde escaped as " & Ptr.Escape_Token ("m~n"));
      Assert (Ptr.Escape_Token ("~/") = "~0~1",
              "both escaped as " & Ptr.Escape_Token ("~/"));
      Assert (Ptr.Escape_Token ("plain") = "plain",
              "an ordinary name was changed");

      P.Parse ("{""a/b"":1,""m~n"":2,""~1"":3}", Document, Error);
      Assert (not Err.Failed (Error), "the sample document failed");

      --  Built and resolved, which is the pair that has to agree.
      Assert (Doc.As_Integer
                (Document,
                 Ptr.Resolve (Document, "/" & Ptr.Escape_Token ("a/b"))) = 1,
              "an escaped slash did not resolve");
      Assert (Doc.As_Integer
                (Document,
                 Ptr.Resolve (Document, "/" & Ptr.Escape_Token ("m~n"))) = 2,
              "an escaped tilde did not resolve");

      --  The worked example from the specification: ~01 is a tilde and a one,
      --  not a slash. Doing the two unescapes in the other order gets this
      --  wrong, and gets nothing else wrong -- which is why it is worth a test.
      Assert (Doc.As_Integer (Document, Ptr.Resolve (Document, "/~01")) = 3,
              "~01 was unescaped in the wrong order");
   end Escaping_Round_Trips;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Jsonlib.Pointers");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Resolves_The_Standard_Examples'Access,
                        "every example in RFC 6901 resolves as it says");
      Register_Routine (T, Absence_Is_Not_An_Error'Access,
                        "a pointer that names nothing returns nothing");
      Register_Routine (T, Malformed_Pointers_Are_Told_Apart'Access,
                        "a malformed pointer is told apart from an absent value");
      Register_Routine (T, Indices_Are_Zero_Based_And_Strict'Access,
                        "array indices are zero-based and strictly digits");
      Register_Routine (T, Escaping_Round_Trips'Access,
                        "a name escaped into a pointer resolves back to itself");
   end Register_Tests;

end Jsonlib_Pointer_Cases;
