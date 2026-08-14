with Jsonlib_Number_Cases;
with Jsonlib_Parser_Cases;
with Jsonlib_Pointer_Cases;
with Jsonlib_Serializer_Cases;

package body Jsonlib_Suite is

   Result : aliased AUnit.Test_Suites.Test_Suite;

   Number_Case     : aliased Jsonlib_Number_Cases.Case_Type;
   Parser_Case     : aliased Jsonlib_Parser_Cases.Case_Type;
   Serializer_Case : aliased Jsonlib_Serializer_Cases.Case_Type;
   Pointer_Case    : aliased Jsonlib_Pointer_Cases.Case_Type;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
   begin
      --  Lowest layer first. A failure list that reads top-down tells you
      --  which layer broke rather than only that something did: a number
      --  failure and a parser failure look identical from the parser's end.
      AUnit.Test_Suites.Add_Test (Result'Access, Number_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Parser_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Serializer_Case'Access);
      AUnit.Test_Suites.Add_Test (Result'Access, Pointer_Case'Access);
      return Result'Access;
   end Suite;

end Jsonlib_Suite;
