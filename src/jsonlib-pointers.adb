with Ada.Strings.Unbounded;

package body Jsonlib.Pointers is

   use Ada.Strings.Unbounded;

   package Doc renames Jsonlib.Documents;

   use type Doc.Value_Kind;

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (Path : String) return Boolean is
   begin
      --  The empty pointer names the document itself, and is the one pointer
      --  that does not start with a slash.
      if Path'Length = 0 then
         return True;
      end if;

      if Path (Path'First) /= '/' then
         return False;
      end if;

      for Index in Path'Range loop
         if Path (Index) = '~' then
            --  A tilde is only ever the start of an escape. A bare one means
            --  the author wrote a pointer they did not mean, and guessing
            --  which of the two characters they intended would be worse than
            --  telling them.
            if Index = Path'Last
              or else Path (Index + 1) not in '0' | '1'
            then
               return False;
            end if;
         end if;
      end loop;

      return True;
   end Is_Valid;

   --  Undo the two escapes, in the order RFC 6901 requires.
   function Unescape (Token : String) return String;

   function Unescape (Token : String) return String is
      Result : Unbounded_String;
      Index  : Natural := Token'First;
   begin
      --  Tilde-one before tilde-zero. The other order turns ~01 into a slash
      --  rather than into the tilde-then-one the author wrote, which is the
      --  one worked example in the specification.
      while Index <= Token'Last loop
         if Token (Index) = '~' and then Index < Token'Last then
            case Token (Index + 1) is
               when '1' =>
                  Append (Result, '/');
                  Index := Index + 2;

               when '0' =>
                  Append (Result, '~');
                  Index := Index + 2;

               when others =>
                  Append (Result, Token (Index));
                  Index := Index + 1;
            end case;
         else
            Append (Result, Token (Index));
            Index := Index + 1;
         end if;
      end loop;

      return To_String (Result);
   end Unescape;

   -------------------
   -- Escape_Token --
   -------------------

   function Escape_Token (Name : String) return String is
      Result : Unbounded_String;
   begin
      --  The tilde first, going this way: escaping the slash first would then
      --  have its own tilde escaped by the second pass.
      for Index in Name'Range loop
         case Name (Index) is
            when '~'    => Append (Result, "~0");
            when '/'    => Append (Result, "~1");
            when others => Append (Result, Name (Index));
         end case;
      end loop;

      return To_String (Result);
   end Escape_Token;

   -------------
   -- Resolve --
   -------------

   function Resolve
     (From : Jsonlib.Documents.Document;
      Base : Jsonlib.Documents.Node;
      Path : String) return Jsonlib.Documents.Node
   is
      Current : Doc.Node := Base;
      Index   : Natural;
   begin
      if not Is_Valid (Path) or else not Doc.Is_Present (Base) then
         return Doc.No_Node;
      end if;

      if Path'Length = 0 then
         return Base;
      end if;

      --  Past the leading slash, then one token per slash. A trailing slash
      --  names a member whose name is empty, which is legal JSON and legal
      --  here.
      Index := Path'First + 1;

      loop
         declare
            Stop : Natural := Index;
         begin
            while Stop <= Path'Last and then Path (Stop) /= '/' loop
               Stop := Stop + 1;
            end loop;

            declare
               Token : constant String := Unescape (Path (Index .. Stop - 1));
            begin
               case Doc.Kind (From, Current) is
                  when Doc.Object_Value =>
                     Current := Doc.Member (From, Current, Token);

                  when Doc.Array_Value =>
                     --  Zero-based, as the standard says, and strictly: "01"
                     --  and "-" and " 1" are not indices, and treating them as
                     --  one would silently address an element the author did
                     --  not name.
                     if Token'Length = 0
                       or else (Token'Length > 1
                                and then Token (Token'First) = '0')
                     then
                        return Doc.No_Node;
                     end if;

                     declare
                        Position : Natural := 0;
                     begin
                        for Digit of Token loop
                           if Digit not in '0' .. '9' then
                              return Doc.No_Node;
                           end if;

                           Position := Position * 10
                             + (Character'Pos (Digit) - Character'Pos ('0'));
                        end loop;

                        Current := Doc.Element (From, Current, Position + 1);
                     end;

                  when others =>
                     --  A path that goes on past a scalar. Nothing there, and
                     --  not an error: a configuration is allowed to hold a
                     --  string where another one holds an object.
                     return Doc.No_Node;
               end case;
            end;

            if not Doc.Is_Present (Current) then
               return Doc.No_Node;
            end if;

            exit when Stop > Path'Last;

            Index := Stop + 1;
         end;
      end loop;

      return Current;
   end Resolve;

   -------------
   -- Resolve --
   -------------

   function Resolve
     (From : Jsonlib.Documents.Document;
      Path : String) return Jsonlib.Documents.Node
   is
   begin
      return Resolve (From, Doc.Root (From), Path);
   end Resolve;

end Jsonlib.Pointers;
