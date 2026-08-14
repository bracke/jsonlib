with Ada.Command_Line;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;

with Jsonlib_Suite;

--  Test_Runner exits zero whatever happens, so a failing suite would report
--  success and CI would go green over it. The status is the whole point of
--  running this in CI.
procedure Jsonlib_Tests is
   use type AUnit.Status;

   function Run is new AUnit.Run.Test_Runner_With_Status (Jsonlib_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Jsonlib_Tests;
