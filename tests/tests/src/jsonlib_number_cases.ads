with AUnit.Test_Cases;

package Jsonlib_Number_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

end Jsonlib_Number_Cases;
