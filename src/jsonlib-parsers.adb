with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

with Jsonlib.Numbers;

package body Jsonlib.Parsers is

   use Ada.Strings.Unbounded;

   package Doc renames Jsonlib.Documents;
   package Err renames Jsonlib.Errors;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Text     : String;
      Into     : in out Jsonlib.Documents.Document;
      Error    : out Jsonlib.Errors.Error_Info;
      Settings : Options := Default_Options)
   is
      --  Where we are. Offset indexes Text directly; line and column are kept
      --  alongside rather than recomputed, because recomputing means scanning
      --  from the start for every error and a document with many errors is
      --  exactly the one a reader is trying to fix.
      Offset : Natural := Text'First;
      Line   : Positive := 1;
      Column : Positive := 1;

      Failed : Boolean := False;

      function At_End return Boolean is (Offset > Text'Last);

      function Here return Err.Position is
        (Offset => (if At_End then 0 else Offset - Text'First + 1),
         Line   => Line,
         Column => Column);

      procedure Fail (Code : Err.Error_Code);
      procedure Fail_At (Code : Err.Error_Code; Where : Err.Position);
      procedure Advance;
      procedure Skip_Whitespace;
      function Parse_Value (Depth : Natural) return Doc.Node;

      ----------
      -- Fail --
      ----------

      procedure Fail (Code : Err.Error_Code) is
      begin
         Fail_At (Code, Here);
      end Fail;

      -------------
      -- Fail_At --
      -------------

      procedure Fail_At (Code : Err.Error_Code; Where : Err.Position) is
      begin
         --  The first failure wins. Later ones are consequences of it, and
         --  reporting the last would point at wreckage rather than at the
         --  cause.
         if not Failed then
            Failed := True;
            Error := (Code => Code, At_Position => Where);
         end if;
      end Fail_At;

      -------------
      -- Advance --
      -------------

      procedure Advance is
      begin
         if At_End then
            return;
         end if;

         if Text (Offset) = Character'Val (16#0A#) then
            Line := Line + 1;
            Column := 1;
         elsif Character'Pos (Text (Offset)) not in 16#80# .. 16#BF# then
            --  Continuation bytes do not advance the column: a column counts
            --  characters, so an accented letter earlier in the line must not
            --  put every later error off by one.
            Column := Column + 1;
         end if;

         Offset := Offset + 1;
      end Advance;

      ----------------------
      -- Skip_Whitespace --
      ----------------------

      procedure Skip_Whitespace is
      begin
         --  Four characters, and only these four. A vertical tab or a form
         --  feed is not whitespace in JSON, whatever a text editor thinks.
         while not At_End loop
            case Text (Offset) is
               when ' ' | Character'Val (16#09#)
                  | Character'Val (16#0A#) | Character'Val (16#0D#) =>
                  Advance;

               when others =>
                  return;
            end case;
         end loop;
      end Skip_Whitespace;

      --  Append one code point to a string being built, as UTF-8.
      procedure Append_Code_Point
        (Into : in out Unbounded_String; Code : Natural);

      procedure Append_Code_Point
        (Into : in out Unbounded_String; Code : Natural)
      is
      begin
         if Code < 16#80# then
            Append (Into, Character'Val (Code));
         elsif Code < 16#800# then
            Append (Into, Character'Val (16#C0# + Code / 16#40#));
            Append (Into, Character'Val (16#80# + Code mod 16#40#));
         elsif Code < 16#1_0000# then
            Append (Into, Character'Val (16#E0# + Code / 16#1000#));
            Append (Into, Character'Val
                      (16#80# + (Code / 16#40#) mod 16#40#));
            Append (Into, Character'Val (16#80# + Code mod 16#40#));
         else
            Append (Into, Character'Val (16#F0# + Code / 16#4_0000#));
            Append (Into, Character'Val
                      (16#80# + (Code / 16#1000#) mod 16#40#));
            Append (Into, Character'Val
                      (16#80# + (Code / 16#40#) mod 16#40#));
            Append (Into, Character'Val (16#80# + Code mod 16#40#));
         end if;
      end Append_Code_Point;

      --  Read the four hexadecimal digits of a \u escape.
      function Read_Hex_Quad (Value : out Natural) return Boolean;

      function Read_Hex_Quad (Value : out Natural) return Boolean is
      begin
         Value := 0;

         for Ignored in 1 .. 4 loop
            if At_End then
               return False;
            end if;

            declare
               Item : constant Character := Text (Offset);
               Nibble : Natural;
            begin
               case Item is
                  when '0' .. '9' =>
                     Nibble := Character'Pos (Item) - Character'Pos ('0');
                  when 'a' .. 'f' =>
                     Nibble := Character'Pos (Item) - Character'Pos ('a') + 10;
                  when 'A' .. 'F' =>
                     Nibble := Character'Pos (Item) - Character'Pos ('A') + 10;
                  when others =>
                     return False;
               end case;

               Value := Value * 16 + Nibble;
            end;

            Advance;
         end loop;

         return True;
      end Read_Hex_Quad;

      --  Check that a multi-byte character is well-formed UTF-8 and consume
      --  it. Strings are the only place a byte above 127 can legally appear,
      --  so this is the only place the check is needed.
      function Consume_Utf8 (Into : in out Unbounded_String) return Boolean;

      function Consume_Utf8 (Into : in out Unbounded_String) return Boolean is
         Lead   : constant Natural := Character'Pos (Text (Offset));
         Needed : Natural;
         Code   : Natural;
      begin
         if Lead < 16#80# then
            Append (Into, Text (Offset));
            Advance;
            return True;
         elsif Lead in 16#C2# .. 16#DF# then
            Needed := 1;
            Code := Lead - 16#C0#;
         elsif Lead in 16#E0# .. 16#EF# then
            Needed := 2;
            Code := Lead - 16#E0#;
         elsif Lead in 16#F0# .. 16#F4# then
            Needed := 3;
            Code := Lead - 16#F0#;
         else
            --  A continuation byte with nothing in front of it, or one of the
            --  lead bytes UTF-8 forbids -- C0 and C1, which only ever encode
            --  something shorter written long.
            return False;
         end if;

         Advance;

         for Ignored in 1 .. Needed loop
            if At_End
              or else Character'Pos (Text (Offset)) not in 16#80# .. 16#BF#
            then
               return False;
            end if;

            Code := Code * 16#40# + (Character'Pos (Text (Offset)) - 16#80#);
            Advance;
         end loop;

         --  Overlong forms, surrogate halves and anything past the last code
         --  point. All three are ways of writing something that is not text,
         --  and a parser that passed them through would produce a document
         --  that cannot be written out again.
         if (Needed = 1 and then Code < 16#80#)
           or else (Needed = 2 and then Code < 16#800#)
           or else (Needed = 3 and then Code < 16#1_0000#)
           or else Code in 16#D800# .. 16#DFFF#
           or else Code > 16#10_FFFF#
         then
            return False;
         end if;

         Append_Code_Point (Into, Code);
         return True;
      end Consume_Utf8;

      --  Read a string, which is both a value and a member name.
      function Parse_String (Value : out Unbounded_String) return Boolean;

      function Parse_String (Value : out Unbounded_String) return Boolean is
         Opened : constant Err.Position := Here;
      begin
         Value := Null_Unbounded_String;

         --  The caller has checked the quote is there; this consumes it.
         Advance;

         loop
            if At_End then
               Fail_At (Err.Unterminated_String, Opened);
               return False;
            end if;

            declare
               Item : constant Character := Text (Offset);
            begin
               if Item = '"' then
                  Advance;
                  return True;
               end if;

               if Item = '\' then
                  Advance;

                  if At_End then
                     Fail_At (Err.Unterminated_String, Opened);
                     return False;
                  end if;

                  case Text (Offset) is
                     when '"'  => Append (Value, '"');  Advance;
                     when '\'  => Append (Value, '\');  Advance;
                     when '/'  => Append (Value, '/');  Advance;
                     when 'b'  => Append (Value, Character'Val (16#08#)); Advance;
                     when 'f'  => Append (Value, Character'Val (16#0C#)); Advance;
                     when 'n'  => Append (Value, Character'Val (16#0A#)); Advance;
                     when 'r'  => Append (Value, Character'Val (16#0D#)); Advance;
                     when 't'  => Append (Value, Character'Val (16#09#)); Advance;

                     when 'u' =>
                        declare
                           Escape_At : constant Err.Position := Here;
                           First     : Natural;
                           Second    : Natural;
                        begin
                           Advance;

                           if not Read_Hex_Quad (First) then
                              Fail_At (Err.Invalid_Unicode_Escape, Escape_At);
                              return False;
                           end if;

                           if First in 16#D800# .. 16#DBFF# then
                              --  A high surrogate. JSON writes code points
                              --  above the basic plane as a pair, and half a
                              --  pair is not text: it cannot be encoded as
                              --  UTF-8 at all, so substituting a replacement
                              --  character would corrupt the document quietly.
                              if At_End or else Text (Offset) /= '\' then
                                 Fail_At (Err.Lone_Surrogate, Escape_At);
                                 return False;
                              end if;

                              Advance;

                              if At_End or else Text (Offset) /= 'u' then
                                 Fail_At (Err.Lone_Surrogate, Escape_At);
                                 return False;
                              end if;

                              Advance;

                              if not Read_Hex_Quad (Second) then
                                 Fail_At (Err.Invalid_Unicode_Escape, Escape_At);
                                 return False;
                              end if;

                              if Second not in 16#DC00# .. 16#DFFF# then
                                 Fail_At (Err.Lone_Surrogate, Escape_At);
                                 return False;
                              end if;

                              Append_Code_Point
                                (Value,
                                 16#1_0000#
                                 + (First - 16#D800#) * 16#400#
                                 + (Second - 16#DC00#));

                           elsif First in 16#DC00# .. 16#DFFF# then
                              --  A low surrogate with no high one before it.
                              Fail_At (Err.Lone_Surrogate, Escape_At);
                              return False;

                           else
                              Append_Code_Point (Value, First);
                           end if;
                        end;

                     when others =>
                        Fail (Err.Invalid_Escape);
                        return False;
                  end case;

               elsif Character'Pos (Item) < 16#20# then
                  --  RFC 8259 requires these to be escaped. Passing one
                  --  through would produce a document other parsers reject --
                  --  and a literal newline inside a string is almost always a
                  --  missing quote rather than something meant.
                  Fail (Err.Unescaped_Control_Character);
                  return False;

               else
                  if not Consume_Utf8 (Value) then
                     Fail (Err.Invalid_Encoding);
                     return False;
                  end if;
               end if;
            end;
         end loop;
      end Parse_String;

      --  Read a bare word: true, false or null.
      function Parse_Literal (Word : String) return Boolean;

      function Parse_Literal (Word : String) return Boolean is
         Started : constant Err.Position := Here;
      begin
         for Index in Word'Range loop
            if At_End or else Text (Offset) /= Word (Index) then
               Fail_At (Err.Invalid_Literal, Started);
               return False;
            end if;

            Advance;
         end loop;

         return True;
      end Parse_Literal;

      --  Read a number.
      function Parse_Number return Doc.Node;

      function Parse_Number return Doc.Node is
         Started : constant Err.Position := Here;
         First   : constant Natural := Offset;
         Result  : Doc.Node;
      begin
         --  Consume everything that could be part of a number, then hold the
         --  whole run to the grammar in one place. Deciding character by
         --  character would put the number grammar in two places -- here and
         --  in Jsonlib.Numbers -- and the two would drift.
         while not At_End loop
            case Text (Offset) is
               when '0' .. '9' | '-' | '+' | '.' | 'e' | 'E' =>
                  Advance;

               when others =>
                  exit;
            end case;
         end loop;

         declare
            Lexeme : constant String := Text (First .. Offset - 1);
            Whole  : Long_Long_Integer;
            Real   : Long_Float;
            Beyond : Boolean;
         begin
            if not Jsonlib.Numbers.Is_Valid (Lexeme) then
               Fail_At (Err.Invalid_Number, Started);
               return Doc.No_Node;
            end if;

            Jsonlib.Numbers.Decode (Lexeme, Whole, Real, Beyond);

            if Beyond then
               --  RFC 8259 permits the text and says nothing about
               --  representing it. Refusing is the only answer that does not
               --  quietly turn somebody's number into infinity or into a
               --  truncated integer.
               Fail_At (Err.Number_Out_Of_Range, Started);
               return Doc.No_Node;
            end if;

            if not Doc.New_Number (Into, Lexeme, Result) then
               Fail_At (Err.Invalid_Number, Started);
               return Doc.No_Node;
            end if;

            return Result;
         end;
      end Parse_Number;

      --  Read an array.
      function Parse_Array (Depth : Natural) return Doc.Node;

      function Parse_Array (Depth : Natural) return Doc.Node is
         Result : constant Doc.Node := Doc.New_Array (Into);
      begin
         Advance;  --  the opening bracket
         Skip_Whitespace;

         if not At_End and then Text (Offset) = ']' then
            Advance;
            return Result;
         end if;

         loop
            declare
               Item : constant Doc.Node := Parse_Value (Depth + 1);
            begin
               if Failed then
                  return Doc.No_Node;
               end if;

               Doc.Append (Into, Result, Item);
            end;

            Skip_Whitespace;

            if At_End then
               Fail (Err.Unexpected_End);
               return Doc.No_Node;
            end if;

            case Text (Offset) is
               when ']' =>
                  Advance;
                  return Result;

               when ',' =>
                  Advance;
                  Skip_Whitespace;

                  --  A comma with a closing bracket after it. Legal in several
                  --  other formats and not in JSON, and common enough to be
                  --  worth its own code rather than a general syntax error.
                  if not At_End and then Text (Offset) = ']' then
                     Fail (Err.Trailing_Comma);
                     return Doc.No_Node;
                  end if;

               when others =>
                  Fail (Err.Expected_Comma_Or_End);
                  return Doc.No_Node;
            end case;
         end loop;
      end Parse_Array;

      --  Read an object.
      function Parse_Object (Depth : Natural) return Doc.Node;

      --  The names an object has had, held apart so that asking whether one
      --  came before is a lookup rather than a walk over every member: a
      --  vocabulary of fifty thousand names took minutes walked.
      package Name_Sets is new Ada.Containers.Indefinite_Hashed_Sets
        (Element_Type        => String,
         Hash                => Ada.Strings.Hash,
         Equivalent_Elements => "=");

      function Parse_Object (Depth : Natural) return Doc.Node is
         Result : constant Doc.Node := Doc.New_Object (Into);
         Seen   : Name_Sets.Set;
      begin
         Advance;  --  the opening brace
         Skip_Whitespace;

         if not At_End and then Text (Offset) = '}' then
            Advance;
            return Result;
         end if;

         loop
            Skip_Whitespace;

            if At_End then
               Fail (Err.Unexpected_End);
               return Doc.No_Node;
            end if;

            --  A name is a string. Not a bare word, not a single-quoted one:
            --  those are other formats that look like JSON.
            if Text (Offset) /= '"' then
               Fail (Err.Expected_Member_Name);
               return Doc.No_Node;
            end if;

            declare
               Named   : Unbounded_String;
               Name_At : constant Err.Position := Here;
            begin
               if not Parse_String (Named) then
                  return Doc.No_Node;
               end if;

               Skip_Whitespace;

               if At_End or else Text (Offset) /= ':' then
                  Fail (Err.Expected_Colon);
                  return Doc.No_Node;
               end if;

               Advance;

               declare
                  Value : constant Doc.Node := Parse_Value (Depth + 1);
               begin
                  if Failed then
                     return Doc.No_Node;
                  end if;

                  case Settings.Duplicates is
                     when Refuse_Duplicates =>
                        if Seen.Contains (To_String (Named)) then
                           Fail_At (Err.Duplicate_Member, Name_At);
                           return Doc.No_Node;
                        end if;
                        Seen.Insert (To_String (Named));

                        Doc.Insert (Into, Result, To_String (Named), Value);

                     when Keep_Duplicates =>
                        Doc.Insert (Into, Result, To_String (Named), Value);

                     when Last_Wins =>
                        --  Replaced where the first one stands rather than
                        --  appended, so a document that is read and written
                        --  again keeps its order.
                        Doc.Set_Member
                          (Into, Result, To_String (Named), Value);
                  end case;
               end;
            end;

            Skip_Whitespace;

            if At_End then
               Fail (Err.Unexpected_End);
               return Doc.No_Node;
            end if;

            case Text (Offset) is
               when '}' =>
                  Advance;
                  return Result;

               when ',' =>
                  Advance;
                  Skip_Whitespace;

                  if not At_End and then Text (Offset) = '}' then
                     Fail (Err.Trailing_Comma);
                     return Doc.No_Node;
                  end if;

               when others =>
                  Fail (Err.Expected_Comma_Or_End);
                  return Doc.No_Node;
            end case;
         end loop;
      end Parse_Object;

      -----------------
      -- Parse_Value --
      -----------------

      function Parse_Value (Depth : Natural) return Doc.Node is
      begin
         if Depth > Settings.Max_Depth then
            --  Checked before recursing rather than after, because the point
            --  of the limit is that the recursion does not happen.
            Fail (Err.Depth_Exceeded);
            return Doc.No_Node;
         end if;

         Skip_Whitespace;

         if At_End then
            Fail (Err.Unexpected_End);
            return Doc.No_Node;
         end if;

         case Text (Offset) is
            when '{' =>
               return Parse_Object (Depth);

            when '[' =>
               return Parse_Array (Depth);

            when '"' =>
               declare
                  Value : Unbounded_String;
               begin
                  if not Parse_String (Value) then
                     return Doc.No_Node;
                  end if;

                  return Doc.New_String (Into, To_String (Value));
               end;

            when 't' =>
               if not Parse_Literal ("true") then
                  return Doc.No_Node;
               end if;

               return Doc.New_Boolean (Into, True);

            when 'f' =>
               if not Parse_Literal ("false") then
                  return Doc.No_Node;
               end if;

               return Doc.New_Boolean (Into, False);

            when 'n' =>
               if not Parse_Literal ("null") then
                  return Doc.No_Node;
               end if;

               return Doc.New_Null (Into);

            when '-' | '0' .. '9' =>
               return Parse_Number;

            when others =>
               Fail (Err.Unexpected_Character);
               return Doc.No_Node;
         end case;
      end Parse_Value;

   begin
      Error := Err.No_Error_Info;
      Doc.Clear (Into);

      if Settings.Max_Length > 0 and then Text'Length > Settings.Max_Length then
         Error := (Code => Err.Document_Too_Large,
                   At_Position => Err.Nowhere);
         return;
      end if;

      Skip_Whitespace;

      if At_End then
         --  Distinct from a syntax error: a file that is empty, or holds only
         --  whitespace, is a different problem from one that is malformed, and
         --  usually a different fix.
         Error := (Code => Err.Empty_Document, At_Position => Err.Nowhere);
         return;
      end if;

      declare
         Top : constant Doc.Node := Parse_Value (1);
      begin
         if Failed then
            --  Left empty rather than half-built. A caller that forgot to
            --  check the error would otherwise read values out of a fragment
            --  and get plausible answers.
            Doc.Clear (Into);
            return;
         end if;

         Skip_Whitespace;

         if not At_End then
            --  A second document concatenated to the first is the usual
            --  cause, and reading only the first half of somebody's file
            --  without saying so is the worst available outcome.
            Fail (Err.Trailing_Content);
            Doc.Clear (Into);
            return;
         end if;

         Doc.Set_Root (Into, Top);
      end;
   end Parse;

end Jsonlib.Parsers;
