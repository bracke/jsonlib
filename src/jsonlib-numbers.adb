with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Jsonlib.Numbers is

   subtype Digit is Character range '0' .. '9';

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (Text : String) return Boolean is
      Index : Natural := Text'First;

      function At_End return Boolean is (Index > Text'Last);

      function Skip_Digits return Natural;
      --  Consume digits and say how many.

      function Skip_Digits return Natural is
         Count : Natural := 0;
      begin
         while not At_End and then Text (Index) in Digit loop
            Count := Count + 1;
            Index := Index + 1;
         end loop;

         return Count;
      end Skip_Digits;

   begin
      if Text'Length = 0 then
         return False;
      end if;

      --  A minus and only a minus. JSON has no leading plus, which is the
      --  single most common thing hand-written generators get wrong.
      if Text (Index) = '-' then
         Index := Index + 1;

         if At_End then
            return False;
         end if;
      end if;

      --  The integer part: a single zero, or a non-zero digit and the rest.
      --  A leading zero is not a formatting nicety in JSON -- 0123 is simply
      --  not a number, and accepting it would produce documents other parsers
      --  reject.
      if At_End or else Text (Index) not in Digit then
         return False;
      end if;

      if Text (Index) = '0' then
         Index := Index + 1;

         if not At_End and then Text (Index) in Digit then
            return False;
         end if;
      else
         if Skip_Digits = 0 then
            return False;
         end if;
      end if;

      --  The fraction, if any. At least one digit after the point: "1." is not
      --  a number.
      if not At_End and then Text (Index) = '.' then
         Index := Index + 1;

         if Skip_Digits = 0 then
            return False;
         end if;
      end if;

      --  The exponent, if any. Here a plus *is* allowed.
      if not At_End and then (Text (Index) = 'e' or else Text (Index) = 'E') then
         Index := Index + 1;

         if not At_End
           and then (Text (Index) = '+' or else Text (Index) = '-')
         then
            Index := Index + 1;
         end if;

         if Skip_Digits = 0 then
            return False;
         end if;
      end if;

      --  Anything left over means the text was not only a number.
      return At_End;
   end Is_Valid;

   ----------------------
   -- Is_Integer_Form --
   ----------------------

   function Is_Integer_Form (Text : String) return Boolean is
   begin
      for Index in Text'Range loop
         case Text (Index) is
            when '.' | 'e' | 'E' => return False;
            when others          => null;
         end case;
      end loop;

      return True;
   end Is_Integer_Form;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Text         : String;
      Whole        : out Long_Long_Integer;
      Real         : out Long_Float;
      Out_Of_Range : out Boolean)
   is
   begin
      Whole := 0;
      Real := 0.0;
      Out_Of_Range := False;

      if Is_Integer_Form (Text) then
         begin
            Whole := Long_Long_Integer'Value (Text);
         exception
            when Constraint_Error =>
               --  Too many digits for this host. The float below may still
               --  hold it approximately, but the caller is told the integer
               --  did not fit rather than being handed a truncated one.
               Out_Of_Range := True;
         end;
      end if;

      begin
         --  Ada's 'Value wants a decimal point where JSON allows none, so
         --  "1e3" has to become "1.0e3" before it will be read.
         if Is_Integer_Form (Text) then
            Real := Long_Float'Value (Text & ".0");
         else
            declare
               Point : constant Natural :=
                 Ada.Strings.Fixed.Index (Text, ".");
               Exponent : constant Natural :=
                 Ada.Strings.Fixed.Index (Text, "e");
               Upper : constant Natural :=
                 Ada.Strings.Fixed.Index (Text, "E");
               Mark : constant Natural :=
                 (if Exponent /= 0 then Exponent else Upper);
            begin
               if Point = 0 and then Mark /= 0 then
                  Real := Long_Float'Value
                    (Text (Text'First .. Mark - 1) & ".0"
                     & Text (Mark .. Text'Last));
               else
                  Real := Long_Float'Value (Text);
               end if;
            end;
         end if;
      exception
         when Constraint_Error =>
            --  An exponent past what a float can hold. RFC 8259 permits the
            --  text and says nothing about representing it; refusing is the
            --  only answer that does not quietly turn a number into infinity.
            Out_Of_Range := True;
            Real := 0.0;
      end;

      --  Checked rather than assumed. This host's 'Value does not raise on an
      --  exponent that overflows -- it hands back an infinity -- so an
      --  exception handler alone would let 1e400 through as Inf, and the
      --  document would then hold a number that cannot be written back out.
      --
      --  'Valid rather than a comparison, and it has to come first: an
      --  infinity is not a value of the type, so *reading* it is what raises,
      --  and `abs Real <= Long_Float'Last` would fault before it could answer.
      --  'Valid is the one attribute defined to look at such an object without
      --  reading it as a number.
      if not Real'Valid then
         Out_Of_Range := True;
         Real := 0.0;
      end if;
   end Decode;

   -----------
   -- Image --
   -----------

   function Image (Value : Long_Long_Integer) return String is
      Text : constant String := Long_Long_Integer'Image (Value);
   begin
      --  Ada writes a leading blank where the sign would be. JSON has no room
      --  for it.
      if Text (Text'First) = ' ' then
         return Text (Text'First + 1 .. Text'Last);
      end if;

      return Text;
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Value : Long_Float) return String is
      package Float_Text is new Ada.Text_IO.Float_IO (Long_Float);

      --  Where plain decimal notation stops being readable. Outside this
      --  range the exponent form is both shorter and clearer, and inside it a
      --  configuration file reads the way its author wrote it.
      Plain_Lower : constant Long_Float := 1.0E-4;
      Plain_Upper : constant Long_Float := 1.0E+16;

      Magnitude : constant Long_Float := abs Value;

      Use_Plain : constant Boolean :=
        Value = 0.0
          or else (Magnitude >= Plain_Lower and then Magnitude < Plain_Upper);

      function Trimmed (Item : String) return String;
      --  Ada pads the integer part with blanks and writes a blank where the
      --  sign of a positive number would be. Neither belongs in JSON.

      function Trimmed (Item : String) return String is
         First : Natural := Item'First;
         Last  : Natural := Item'Last;
      begin
         while First <= Last and then Item (First) = ' ' loop
            First := First + 1;
         end loop;

         while Last >= First and then Item (Last) = ' ' loop
            Last := Last - 1;
         end loop;

         return Item (First .. Last);
      end Trimmed;

   begin
      --  JSON cannot write these at all. A program that produced one and asked
      --  for it to be written has a defect, and the alternatives -- emitting
      --  null, or the bare word NaN -- would put a document into the world
      --  that either lies or does not parse.
      if not Value'Valid or else Value - Value /= 0.0 then
         raise Constraint_Error with "a float that JSON cannot represent";
      end if;

      --  The shortest text that reads back as the same value. Trying
      --  increasing precisions is slower than the published shortest-round-trip
      --  algorithms and is obviously correct, which for a number being written
      --  into somebody's configuration file is the better trade.
      for Places in 1 .. 17 loop
         declare
            Buffer : String (1 .. 64) := [others => ' '];
         begin
            if Use_Plain then
               Float_Text.Put (Buffer, Value, Aft => Places, Exp => 0);
            else
               Float_Text.Put (Buffer, Value, Aft => Places, Exp => 3);
            end if;

            declare
               Candidate : constant String := Trimmed (Buffer);
            begin
               if Long_Float'Value (Candidate) = Value then
                  return Candidate;
               end if;
            end;
         exception
            when Ada.Text_IO.Layout_Error =>
               --  This precision does not fit the buffer. A wider one will not
               --  fit either, so there is nothing to gain by continuing.
               exit;
         end;
      end loop;

      --  Seventeen significant digits round-trip every IEEE double, so this is
      --  reached only on a host whose Long_Float is something else. Ada's own
      --  image is valid JSON, so the document is still correct -- just longer.
      return Trimmed (Long_Float'Image (Value));
   end Image;

end Jsonlib.Numbers;
