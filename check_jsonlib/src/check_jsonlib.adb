with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Files;
with Project_Tools.Text;

--  The release gate for jsonlib.
--
--  Every rule here is a claim this repository makes about itself somewhere a
--  reader will believe it: the README, the agent guidance, the refusals table.
--  A claim nothing checks is a claim that drifts, and the ones that drift
--  quietest are the ones written in prose.
--
--  Run from the crate root or from this directory:
--
--     cd check_jsonlib && alr build && ./bin/check_jsonlib
procedure Check_Jsonlib is
   use Ada.Text_IO;

   Failures : Natural := 0;

   procedure Fail (Message : String);

   procedure Fail (Message : String) is
   begin
      Put_Line (Standard_Error, "error: " & Message);
      Failures := Failures + 1;
   end Fail;

   function Root_Directory return String;

   function Root_Directory return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Here & "/jsonlib.gpr") then
         return Here;
      elsif Ada.Directories.Exists (Here & "/../jsonlib.gpr") then
         return Ada.Directories.Full_Name (Here & "/..");
      end if;

      Put_Line (Standard_Error, "error: jsonlib root not found from " & Here);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise Program_Error;
   end Root_Directory;

   Root  : constant String := Root_Directory;
   Src   : constant String := Root & "/src";
   Docs  : constant String := Root & "/docs";

   function Contents (Path : String) return String;

   function Contents (Path : String) return String is
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;

      return To_String (Project_Tools.Text.Read_Text_File (Path));
   end Contents;

   procedure Require_File (Path : String; Why : String);

   procedure Require_File (Path : String; Why : String) is
   begin
      if not Ada.Directories.Exists (Path) then
         Fail (Path & " is missing: " & Why);
      end if;
   end Require_File;

   procedure Require_Text (Path : String; Wanted : String; Why : String);

   procedure Require_Text (Path : String; Wanted : String; Why : String) is
      Text : constant String := Contents (Path);
   begin
      if Text = "" then
         Fail (Path & " could not be read: " & Why);
      elsif not Project_Tools.Text.Contains (Text, Wanted) then
         Fail (Path & " must say " & Wanted & ": " & Why);
      end if;
   end Require_Text;

   --  Every refusal the library can produce, and every one the documentation
   --  claims. Compared in both directions: a code with no row is a refusal a
   --  reader cannot look up, and a row with no code is documentation for
   --  something that no longer exists.
   procedure Check_Refusals_Are_Documented;

   procedure Check_Refusals_Are_Documented is
      Spec  : constant String := Contents (Src & "/jsonlib-errors.ads");
      Table : constant String := Contents (Docs & "/refusals.md");

      From     : Positive;
      Ends     : Natural;
      In_Enum  : Boolean := False;
      Counted  : Natural := 0;

      function Is_Code_Line (Line : String; Name_Last : out Natural)
        return Boolean;

      --  A line holding nothing but an enumeration literal, which is how this
      --  spec is written: one code per line, its comment above it.
      function Is_Code_Line (Line : String; Name_Last : out Natural)
        return Boolean
      is
         First : Natural := Line'First;
         Last  : Natural;
      begin
         Name_Last := 0;

         while First <= Line'Last
           and then (Line (First) = ' ' or else Line (First) = ASCII.HT)
         loop
            First := First + 1;
         end loop;

         if First > Line'Last or else Line (First) not in 'A' .. 'Z' then
            return False;
         end if;

         Last := First;
         while Last <= Line'Last
           and then (Line (Last) in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9'
                     or else Line (Last) = '_')
         loop
            Last := Last + 1;
         end loop;

         --  What follows a literal is a comma, or the closing parenthesis of
         --  the last one. Anything else is a declaration rather than a code.
         if Last <= Line'Last
           and then Line (Last) /= ','
           and then Line (Last) /= ')'
         then
            return False;
         end if;

         Name_Last := Last - 1;
         return Name_Last >= First;
      end Is_Code_Line;

   begin
      if Spec = "" then
         Fail ("src/jsonlib-errors.ads could not be read");
         return;
      end if;

      if Table = "" then
         Fail ("docs/refusals.md could not be read: every refusal must be "
               & "documented where a caller will look for it");
         return;
      end if;

      From := Spec'First;
      while From <= Spec'Last loop
         Ends := From;
         while Ends <= Spec'Last and then Spec (Ends) /= ASCII.LF loop
            Ends := Ends + 1;
         end loop;

         declare
            Line      : constant String := Spec (From .. Ends - 1);
            Name_Last : Natural;
         begin
            if Project_Tools.Text.Contains (Line, "type Error_Code is") then
               In_Enum := True;

            elsif In_Enum and then Is_Code_Line (Line, Name_Last) then
               declare
                  First : Natural := Line'First;
               begin
                  while Line (First) = ' ' or else Line (First) = ASCII.HT
                  loop
                     First := First + 1;
                  end loop;

                  declare
                     Name : constant String := Line (First .. Name_Last);
                  begin
                     Counted := Counted + 1;

                     if not Project_Tools.Text.Contains
                              (Table, "| " & '`' & Name & '`' & " |")
                     then
                        Fail ("docs/refusals.md has no row for " & Name
                              & ", which src/jsonlib-errors.ads declares");
                     end if;
                  end;

                  --  The closing parenthesis ends the enumeration; anything
                  --  after it is a different declaration.
                  if Ada.Strings.Fixed.Index (Line, ")") > 0 then
                     In_Enum := False;
                  end if;
               end;
            end if;
         end;

         From := Ends + 1;
      end loop;

      if Counted = 0 then
         Fail ("no error codes were found in src/jsonlib-errors.ads, so "
               & "nothing was checked -- this rule reads the enumeration and "
               & "the shape it expects has changed");
      end if;

      --  And the other direction.
      From := Table'First;
      while From <= Table'Last loop
         Ends := From;
         while Ends <= Table'Last and then Table (Ends) /= ASCII.LF loop
            Ends := Ends + 1;
         end loop;

         declare
            Line : constant String := Table (From .. Ends - 1);
         begin
            if Line'Length > 3
              and then Line (Line'First .. Line'First + 2) = "| " & '`'
            then
               declare
                  Closes : constant Natural :=
                    Ada.Strings.Fixed.Index
                      (Line (Line'First + 3 .. Line'Last), "`");
               begin
                  if Closes > 0 then
                     declare
                        Name : constant String :=
                          Line (Line'First + 3 .. Closes - 1);
                     begin
                        if not Project_Tools.Text.Contains (Spec, Name) then
                           Fail ("docs/refusals.md documents " & Name
                                 & ", which src/jsonlib-errors.ads does not "
                                 & "declare");
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;

         From := Ends + 1;
      end loop;

      if Failures = 0 then
         Put_Line ("refusals:" & Natural'Image (Counted)
                   & " codes, each documented");
      end if;
   end Check_Refusals_Are_Documented;

   --  Every suite of cases is registered. A case file nobody registers is a
   --  file of tests that never run, and it looks exactly like one that does.
   procedure Check_Every_Case_Suite_Is_Registered;

   --  Ada does not care about case and neither does this.
   function Folded (Text : String) return String;

   function Folded (Text : String) return String is
      Result : String := Text;
   begin
      for Index in Result'Range loop
         if Result (Index) in 'A' .. 'Z' then
            Result (Index) :=
              Character'Val (Character'Pos (Result (Index)) + 32);
         end if;
      end loop;

      return Result;
   end Folded;

   procedure Check_Every_Case_Suite_Is_Registered is
      Suite : constant String :=
        Contents (Root & "/tests/tests/src/jsonlib_suite.adb");

      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
   begin
      if Suite = "" then
         Fail ("tests/tests/src/jsonlib_suite.adb could not be read");
         return;
      end if;

      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Root & "/tests/tests/src",
         Pattern   => "*_cases.ads",
         Filter    => [Ada.Directories.Ordinary_File => True, others => False]);

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);

         declare
            Base : constant String :=
              Ada.Directories.Base_Name (Ada.Directories.Simple_Name (Item));
         begin
            Seen := Seen + 1;

            --  Folded, because a file is named in lower case and Ada names
            --  are written the way a reader writes them. Comparing the two
            --  as they stand reported every case package as unregistered,
            --  which was this rule failing rather than the suite.
            if not Project_Tools.Text.Contains
                     (Folded (Suite), Folded (Base))
            then
               Fail (Base & " is a case package the suite never registers");
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);

      if Seen = 0 then
         Fail ("no case packages were found; this rule is reading the wrong "
               & "place");
      elsif Failures = 0 then
         Put_Line ("suite:" & Natural'Image (Seen)
                   & " case packages, each registered");
      end if;
   end Check_Every_Case_Suite_Is_Registered;

begin
   --  The files a reader is entitled to find.
   Require_File (Root & "/README.md", "what this is, for somebody arriving");
   Require_File (Root & "/LICENSE", "the text the manifest declares");
   Require_File (Root & "/CHANGELOG.md",
                 "consumers pin this crate by path, so the commit is the "
                 & "version and this is where what came with it is written");
   Require_File (Root & "/AGENTS.md", "the canonical guidance for agents");
   Require_File (Root & "/CLAUDE.md", "the import that keeps one copy of it");
   Require_File (Docs & "/refusals.md", "every refusal, by code");
   Require_File (Root & "/tests/alire.toml", "the suite is its own crate");
   Require_File (Src & "/jsonlib.ads", "the root package");

   --  The toolchain, in every manifest that resolves one.
   Require_Text (Root & "/alire.toml", "gnat_native = " & '"' & "=15.2.1",
                 "one pinned compiler, or two crates build differently");
   Require_Text (Root & "/tests/alire.toml", "gnat_native = " & '"' & "=15.2.1",
                 "the suite must build with the compiler the library does");

   --  The claims the README makes about how to work here.
   Require_Text (Root & "/README.md", "alr build",
                 "a reader must be told how to build it");
   Require_Text (Root & "/README.md", "jsonlib_tests",
                 "and how to run the suite");
   Require_Text (Root & "/README.md", "RFC 8259",
                 "what this library implements, named exactly");
   Require_Text (Root & "/README.md", "no lenient mode",
                 "the refusal that decides most of the design");

   --  One copy of the agent guidance, imported rather than duplicated.
   Require_Text (Root & "/CLAUDE.md", "@AGENTS.md",
                 "CLAUDE.md imports AGENTS.md so the two cannot drift");
   Require_Text (Root & "/AGENTS.md", "canonical",
                 "AGENTS.md must say which copy is the canonical one");

   Check_Refusals_Are_Documented;
   Check_Every_Case_Suite_Is_Registered;

   if Failures = 0 then
      Put_Line ("jsonlib release checks passed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Put_Line (Standard_Error,
                "jsonlib release checks failed:" & Natural'Image (Failures)
                & " error(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

exception
   when Program_Error =>
      null;
end Check_Jsonlib;
