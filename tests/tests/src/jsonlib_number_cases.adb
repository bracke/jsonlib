with AUnit.Assertions;

with Jsonlib.Numbers;

package body Jsonlib_Number_Cases is

   use AUnit.Assertions;

   package N renames Jsonlib.Numbers;

   procedure Accepts_The_Grammar (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Refuses_Everything_Else
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Integer_Form_Follows_The_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Out_Of_Range_Is_Reported
     (Test : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Floats_Round_Trip (Test : in out AUnit.Test_Cases.Test_Case'Class);

   -----------------------------
   -- Accepts_The_Grammar --
   -----------------------------

   procedure Accepts_The_Grammar
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      procedure Good (Text : String);

      procedure Good (Text : String) is
      begin
         Assert (N.Is_Valid (Text), "refused the valid number " & Text);
      end Good;

   begin
      Good ("0");
      Good ("-0");
      Good ("1");
      Good ("42");
      Good ("-42");
      Good ("0.5");
      Good ("-0.5");
      Good ("1.0");
      Good ("1e3");
      Good ("1E3");
      Good ("1e+3");
      Good ("1e-3");
      Good ("1.5e-3");
      Good ("-1.5E+300");

      --  Long enough that no host holds it exactly. Still valid JSON: the
      --  grammar says nothing about what a reader can represent.
      Good ("123456789012345678901234567890");
   end Accepts_The_Grammar;

   ---------------------------------
   -- Refuses_Everything_Else --
   ---------------------------------

   procedure Refuses_Everything_Else
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      procedure Bad (Text : String);

      procedure Bad (Text : String) is
      begin
         Assert (not N.Is_Valid (Text), "accepted the invalid number " & Text);
      end Bad;

   begin
      --  Every one of these is accepted by some JSON library somewhere, and
      --  each one produces a document another library rejects.
      Bad ("");
      Bad ("+1");        --  a leading plus
      Bad ("01");        --  a leading zero
      Bad ("00");
      Bad ("-01");
      Bad ("1.");        --  a point with nothing after it
      Bad (".5");        --  a point with nothing before it
      Bad ("-.5");
      Bad ("1e");        --  an exponent with no digits
      Bad ("1e+");
      Bad ("1.2.3");
      Bad ("0x1F");      --  hexadecimal
      Bad ("Infinity");
      Bad ("-Infinity");
      Bad ("NaN");
      Bad ("1 ");        --  trailing whitespace is the caller's to strip
      Bad (" 1");
      Bad ("--1");
      Bad ("1_000");     --  Ada's own separator, which JSON has no idea about
   end Refuses_Everything_Else;

   ----------------------------------------
   -- Integer_Form_Follows_The_Text --
   ----------------------------------------

   procedure Integer_Form_Follows_The_Text
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
   begin
      Assert (N.Is_Integer_Form ("1"), "1 was not an integer form");
      Assert (N.Is_Integer_Form ("-1000"), "-1000 was not an integer form");

      --  Decided by the text, never by the value. A configuration that wrote
      --  1.0 means a float, and a program that rewrote it as 1 would have
      --  changed what the file says.
      Assert (not N.Is_Integer_Form ("1.0"), "1.0 was treated as an integer");
      Assert (not N.Is_Integer_Form ("1e2"), "1e2 was treated as an integer");
      Assert (not N.Is_Integer_Form ("1E2"), "1E2 was treated as an integer");
   end Integer_Form_Follows_The_Text;

   ------------------------------------
   -- Out_Of_Range_Is_Reported --
   ------------------------------------

   procedure Out_Of_Range_Is_Reported
     (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);
      Whole  : Long_Long_Integer;
      Real   : Long_Float;
      Beyond : Boolean;
   begin
      N.Decode ("42", Whole, Real, Beyond);
      Assert (not Beyond, "42 was reported out of range");
      Assert (Whole = 42, "42 decoded as" & Long_Long_Integer'Image (Whole));
      Assert (Real = 42.0, "42 did not also decode as a float");

      --  More digits than any host's integer. Reported rather than truncated:
      --  a value that silently became the largest representable number is
      --  worse than one that was refused, because nothing downstream can tell
      --  it was ever wrong.
      N.Decode ("123456789012345678901234567890", Whole, Real, Beyond);
      Assert (Beyond, "an integer too large for the host was accepted");

      --  An exponent past what a float can hold. RFC 8259 permits the text and
      --  says nothing about representing it.
      N.Decode ("1e400", Whole, Real, Beyond);
      Assert (Beyond, "1e400 was accepted rather than refused");

      N.Decode ("1.5", Whole, Real, Beyond);
      Assert (not Beyond, "1.5 was reported out of range");
      Assert (Real = 1.5, "1.5 decoded as" & Long_Float'Image (Real));
   end Out_Of_Range_Is_Reported;

   -------------------------
   -- Floats_Round_Trip --
   -------------------------

   procedure Floats_Round_Trip (Test : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Test);

      procedure Round_Trip (Value : Long_Float);

      procedure Round_Trip (Value : Long_Float) is
         Text : constant String := N.Image (Value);
      begin
         --  Two things at once, and both matter: the text has to be a JSON
         --  number, and it has to read back as exactly the value it came from.
         --  A writer that produced a shorter text than it could read would
         --  lose precision that the document was carrying.
         Assert (N.Is_Valid (Text),
                 "the image " & Text & " is not a JSON number");
         Assert (Long_Float'Value (Text) = Value,
                 "the image " & Text & " did not read back as itself");
      end Round_Trip;

   begin
      Round_Trip (0.0);
      Round_Trip (1.0);
      Round_Trip (-1.0);
      Round_Trip (0.5);
      Round_Trip (3.141592653589793);
      Round_Trip (1.0E-10);
      Round_Trip (1.0E20);
      Round_Trip (-2.5E-30);
      Round_Trip (Long_Float'Last);
      Round_Trip (Long_Float'First);

      --  Integers keep Ada's image without its leading blank, which is what
      --  makes them valid JSON.
      Assert (N.Image (Long_Long_Integer'(42)) = "42",
              "42 imaged as " & N.Image (Long_Long_Integer'(42)));
      Assert (N.Image (Long_Long_Integer'(-42)) = "-42",
              "-42 imaged as " & N.Image (Long_Long_Integer'(-42)));
      Assert (N.Is_Valid (N.Image (Long_Long_Integer'Last)),
              "the largest integer did not image as a JSON number");
   end Floats_Round_Trip;

   ----------
   -- Name --
   ----------

   overriding function Name (T : Case_Type) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Jsonlib.Numbers");
   end Name;

   --------------------
   -- Register_Tests --
   --------------------

   overriding procedure Register_Tests (T : in out Case_Type) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Accepts_The_Grammar'Access,
                        "every form JSON defines is accepted");
      Register_Routine (T, Refuses_Everything_Else'Access,
                        "every form JSON does not define is refused");
      Register_Routine (T, Integer_Form_Follows_The_Text'Access,
                        "integer or float is decided by the text, not the value");
      Register_Routine (T, Out_Of_Range_Is_Reported'Access,
                        "a value the host cannot hold is reported, not truncated");
      Register_Routine (T, Floats_Round_Trip'Access,
                        "a float's image is JSON and reads back as itself");
   end Register_Tests;

end Jsonlib_Number_Cases;
